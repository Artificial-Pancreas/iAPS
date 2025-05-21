import WebKit

final class WebViewScriptExecutorAtomic<T> {
    private var value: T
    private let lock = DispatchQueue(label: "com.example.atomic.lock")

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.sync { value }
    }

    func set(_ newValue: T) {
        lock.sync { value = newValue }
    }
}

class WebViewScriptExecutor: NSObject, WKScriptMessageHandler {
    private var webView: WKWebView!
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

    init(frame: CGRect = .zero) {
        super.init()

        let contentController = WKUserContentController()
        contentController.add(self, name: "consoleLog")
        contentController.add(self, name: "jsBridge")
        contentController.add(self, name: "scriptError")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        webView = WKWebView(frame: frame, configuration: config)

        injectConsoleLogHandler()
        loadScripts()
    }

    private func injectConsoleLogHandler() {
        let consoleScript = """
        var _consoleLog = function (message) {
            window.webkit.messageHandlers.consoleLog.postMessage(message.join(" "));
        }
        window.addEventListener('error', function(event) {
            window.webkit.messageHandlers.scriptError.postMessage("[JAVASCRIPT][GLOBAL ERROR]: " + event.message + " at " + event.filename + ":" + event.lineno);
        });

        """
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(consoleScript, completionHandler: nil)
        }
    }

    func script(for name: String) -> FunctionScript? {
        scripts.filter { $0.name == name }.first
    }

    private func loadScripts() {
        DispatchQueue.main.async {
            for script in self.scripts {
                self.includeScript(script: script)
            }

            self.includeScript(script: Script(name: OpenAPS.Prepare.log))
        }
    }

    func includeScript(script: FunctionScript) {
        includeScript(script: Script(name: "Script", body: script.body))
    }

    func includeScript(script: Script) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script.body)
        }
    }

    func call(name: String, with arguments: [JSON], withBody body: String = "") -> RawJSON {
        if let script = script(for: name) {
            return callFunctionSync(function: script, with: arguments, withBody: body)
        } else {
            print("No script found for \"\(name)\"")
            return ""
        }
    }

    func callAsync(name: String, with arguments: [JSON], withBody body: String = "") async -> RawJSON {
        if let script = script(for: name) {
            return await callFunctionAsync(function: script, with: arguments, withBody: body)
        } else {
            print("No script found for \"\(name)\"")
            return ""
        }
    }

    func callFunctionAsync(function: FunctionScript, with arguments: [JSON], withBody body: String = "") async -> RawJSON {
        await callFunctionAsync(function: function.variable, with: arguments, withBody: body)
    }

    func callFunctionAsync(function: String, with arguments: [JSON], withBody body: String = "") async -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")

        print("[WKWebView]: Calling Javascript function \(function)")

        let script = """
        \(body)

        return JSON.stringify(\(function)(\(joined)) ?? "", null, 4);
        """

        do {
            let result = try await evaluateFunction(body: script) as! RawJSON
            print("[WKWebView]: Received script result for function \"\(function)\": \(result)")
            return result
        } catch {
            debug(.openAPS, "[WKWebView]: Received script error for function \"\(function)\": \(error)")
            print(error)
            return ""
        }
    }

    func callFunctionSync(function: FunctionScript, with arguments: [JSON], withBody body: String = "") -> RawJSON {
        callFunctionSync(function: function.variable, with: arguments, withBody: body)
    }

    func callFunctionSync(function: String, with arguments: [JSON], withBody body: String = "") -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")
        let script = """
        \(body)

        return JSON.stringify(\(function)(\(joined)) ?? "", null, 4);
        """

        do {
            return try evaluateFunctionSync(body: script) as! RawJSON
        } catch {
            print(error)
            return ""
        }
    }

    func evaluateFunctionSync(body: String) throws -> Any? {
        let group = DispatchGroup()
        let asyncResult = WebViewScriptExecutorAtomic<Result<Any, Error>?>(nil)

        group.enter()
        DispatchQueue.main.async {
            Task {
                do {
                    let result = try await self.evaluateFunction(body: body)
                    asyncResult.set(.success(result))
                } catch {
                    asyncResult.set(.failure(error))
                }
                group.leave()
            }
        }

        group.wait()

        switch asyncResult.get() {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        case .none:
            print("No result from the script")
            throw NSError(domain: "WebViewScriptExecutor", code: 1, userInfo: nil)
        }
    }

    var continuations: [String: CheckedContinuation<Any, Error>] = [:]

    func evaluateFunction(body: String) async throws -> Any {
        let requestId = UUID().uuidString
        // Just a timeout for security reason
        let timeoutSeconds: TimeInterval = 10

        let script = """
        setTimeout(() => (async function() {
            try {
                var result = await (function() {
                    \(body)
                })();
                window.webkit.messageHandlers.jsBridge.postMessage({ id: "\(requestId)", value: result });
            } catch (e) {
                window.webkit.messageHandlers.jsBridge.postMessage({ id: "\(requestId)", error: e.toString() });
            }
        })(), 0);
        """

        return try await withCheckedThrowingContinuation { continuation in
            continuations[requestId] = continuation

            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(script) { _, error in
                    if let error = error {
                        self.continuations.removeValue(forKey: requestId)
                        print(error)
                        continuation.resume(throwing: error)
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                if let cont = self.continuations.removeValue(forKey: requestId) {
                    cont.resume(throwing: NSError(
                        domain: "WebViewScriptExecutor",
                        code: 408,
                        userInfo: [NSLocalizedDescriptionKey: "JavaScript function timed out"]
                    ))
                }
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
        // Handle responses from evaluateFunction via jsBridge
        if message.name == "jsBridge", let body = message.body as? [String: Any], let id = body["id"] as? String {
            print("Received jsBridge response: ", body)
            if let continuation = continuations.removeValue(forKey: id) {
                if let value = body["value"] {
                    continuation.resume(returning: value)
                } else if let error = body["error"] as? String {
                    continuation
                        .resume(throwing: NSError(
                            domain: "WebViewScriptExecutor",
                            code: 500,
                            userInfo: [NSLocalizedDescriptionKey: error]
                        ))
                }
            }
        }
    }
}
