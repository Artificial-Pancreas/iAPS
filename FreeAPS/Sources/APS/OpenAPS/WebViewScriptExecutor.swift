import WebKit

@MainActor class WebViewScriptExecutor: NSObject, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var continuationStreams = [String: AsyncThrowingStream<RawJSON, Error>.Continuation]()
    private var scripts = [
        FunctionScript(name: OpenAPS.Bundle.autosens, function: "freeaps_autosens"),
        FunctionScript(name: OpenAPS.Bundle.autotuneCore, function: "freeaps_autotuneCore"),
        FunctionScript(name: OpenAPS.Bundle.autotunePrep, function: "freeaps_autotunePrep"),
        FunctionScript(name: OpenAPS.Bundle.basalSetTemp, function: "freeaps_basalSetTemp"),
        FunctionScript(name: OpenAPS.Bundle.determineBasal, function: "freeaps_determineBasal"),
        FunctionScript(name: OpenAPS.Bundle.getLastGlucose, function: "freeaps_glucoseGetLast"),
        FunctionScript(name: OpenAPS.Bundle.iob, function: "freeaps_iob"),
        FunctionScript(name: OpenAPS.Bundle.meal, function: "freeaps_meal"),
        FunctionScript(name: OpenAPS.Bundle.profile, function: "freeaps_profile"),
        FunctionScript(name: OpenAPS.Prepare.autosens, function: "generate", variable: "iaps_autosens"),
        FunctionScript(name: OpenAPS.Prepare.autotuneCore, function: "generate", variable: "iaps_autotuneCore"),
        FunctionScript(name: OpenAPS.Prepare.autotunePrep, function: "generate", variable: "iaps_autotunePrep"),
        FunctionScript(name: OpenAPS.Prepare.determineBasal, function: "generate", variable: "iaps_determineBasal"),
        FunctionScript(name: OpenAPS.Prepare.iob, function: "generate", variable: "iaps_iob"),
        FunctionScript(name: OpenAPS.Prepare.meal, function: "generate", variable: "iaps_meal"),
        FunctionScript(name: OpenAPS.Prepare.profile, function: "generate", variable: "iaps_profile"),
        FunctionScript(name: OpenAPS.Prepare.string, function: "generate", variable: "iaps_middleware"),
        FunctionScript(name: OpenAPS.AutoISF.autoisf, for: [
            Script(name: OpenAPS.AutoISF.getLastGlucose),
            Script(name: OpenAPS.AutoISF.autoisf)
        ], function: "generate", variable: "iaps_autoisf")
    ]

    init(frame _: CGRect = .zero) {
        super.init()

        webView = createWebView()
    }

    /// True once the current WebView has loaded its document and every user script
    /// (console hook + oref bundles) has been injected. Calls wait on this instead of
    /// racing the initial page load.
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    private func createWebView() -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(self, name: "consoleLog")
        contentController.add(self, name: "jsBridge")
        contentController.add(self, name: "scriptError")

        // Inject everything as WKUserScripts rather than one-shot evaluateJavaScript
        // calls: user scripts are re-applied by WebKit on every document load, so the
        // oref bundles survive a WebContent-process relaunch instead of vanishing.
        for source in userScriptSources() {
            contentController.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        // Posted after the atDocumentStart scripts have run — flips isReady below.
        contentController.addUserScript(WKUserScript(
            source: "window.webkit.messageHandlers.jsBridge.postMessage({ id: \"__ready__\", value: \"\" });",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)

        // User scripts only run as part of a document load — give the view one.
        isReady = false
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

        return webView
    }

    private func userScriptSources() -> [String] {
        let consoleScript = """
        var _consoleLog = function (message) {
            window.webkit.messageHandlers.consoleLog.postMessage(message.join(" "));
        }
        window.addEventListener('error', function(event) {
            window.webkit.messageHandlers.scriptError.postMessage("[JAVASCRIPT][GLOBAL ERROR]: " + event.message + " at " + event.filename + ":" + event.lineno);
        });

        """
        return [consoleScript] + scripts.map(\.body) + [Script(name: OpenAPS.Prepare.log).body]
    }

    private func awaitReady() async {
        if isReady { return }
        await withCheckedContinuation { continuation in
            readyWaiters.append(continuation)
        }
    }

    private func script(for name: String) -> FunctionScript? {
        scripts.filter { $0.name == name }.first
    }

    func call(name: String, with arguments: [JSON], withBody body: String = "") async -> RawJSON {
        if let script = script(for: name) {
            return await callFunctionAsync(function: script, with: arguments, withBody: body)
        } else {
            print("No script found for \"\(name)\"")
            return ""
        }
    }

    private func callFunctionAsync(
        function: FunctionScript,
        with arguments: [JSON],
        withBody body: String = ""
    ) async -> RawJSON {
        await callFunctionAsync(function: function.variable, with: arguments, withBody: body)
    }

    private func callFunctionAsync(function: String, with arguments: [JSON], withBody body: String = "") async -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")

        let script = """
        \(body)

        return JSON.stringify(\(function)(\(joined)) ?? "", null, 4);
        """

        do {
            let result = try await evaluateFunction(body: script)
            return result
        } catch {
            print(error)
            return ""
        }
    }

    private func evaluateFunction(body: String, attempts: Int = 0) async throws -> RawJSON {
        let maxAttempts = 2
        let requestId = UUID().uuidString

        let script = """
        (function () {
            (async function () {
                try {
                    var result = await (function() {
                        \(body)
                    })();
                    window.webkit.messageHandlers.jsBridge.postMessage({ id: "\(requestId)", value: result });
                } catch (e) {
                    window.webkit.messageHandlers.jsBridge.postMessage({ id: "\(requestId)", error: e.toString() });
                }
            })();
            return "";
        })();
        """

        let stream = AsyncThrowingStream<RawJSON, Error> { continuation in
            continuationStreams[requestId] = continuation
        }

        do {
            await awaitReady()
            try await webView.evaluateJavaScript(script)

            for try await value in stream {
                return value
            }
            throw NSError(domain: "WebViewScriptExecutor", code: 2, userInfo: [NSLocalizedDescriptionKey: "No result emitted"])
        } catch {
            print("Javascript function (\(requestId)) attempt \(attempts + 1) failed with error: \(error)")
            continuationStreams.removeValue(forKey: requestId)
            if attempts < maxAttempts {
                webView = createWebView()
                return try await evaluateFunction(body: body, attempts: attempts + 1)
            } else {
                throw error
            }
        }
    }

    // Handle messages from JavaScript (e.g., console.log)
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "consoleLog", let logMessage = message.body as? String {
            if logMessage.count > 3 { // Remove the cryptic test logs created during development of Autosens
                debug(.openAPS, "JavaScript log: \(logMessage)")
            }
        }
        if message.name == "scriptError", let logMessage = message.body as? String {
            warning(.openAPS, "JavaScript Error: \(logMessage)")
        }
        // The __ready__ user script fired: the document (re)loaded and all bundles are injected
        if message.name == "jsBridge",
           let body = message.body as? [String: Any],
           body["id"] as? String == "__ready__"
        {
            isReady = true
            let waiters = readyWaiters
            readyWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            return
        }
        // Handle responses from evaluateFunction via jsBridge
        if message.name == "jsBridge",
           let body = message.body as? [String: Any],
           let id = body["id"] as? String,
           let continuation = continuationStreams.removeValue(forKey: id)
        {
            if let value = body["value"] as? RawJSON {
                continuation.yield(value)
                continuation.finish()
            } else if let error = body["error"] as? String {
                continuation.finish(throwing: NSError(
                    domain: "WebViewScriptExecutor",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: error]
                ))
            } else {
                continuation.finish(throwing: NSError(
                    domain: "WebViewScriptExecutor",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown error"]
                ))
            }
        }
    }
}
