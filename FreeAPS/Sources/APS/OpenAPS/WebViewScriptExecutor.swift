import WebKit

struct ScriptError: Decodable, Error {
    let script_error: String
}

@MainActor class WebViewScriptExecutor: NSObject, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var continuationStreams = [String: AsyncThrowingStream<String, Error>.Continuation]()

    init(frame _: CGRect = .zero) {
        super.init()

        webView = createWebView()
    }

    private func createWebView() -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(self, name: "consoleLog")
        contentController.add(self, name: "jsBridge")
        contentController.add(self, name: "scriptError")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)

        injectConsoleLogHandler(webView: webView)

        includeScript(webView: webView, script: Script(name: OpenAPS.Prepare.log))
        includeScript(webView: webView, script: Script(name: OpenAPS.Bundle.oref0))

        return webView
    }

    private func injectConsoleLogHandler(webView: WKWebView) {
        let consoleScript = """
        var _consoleLog = function (message) {
            window.webkit.messageHandlers.consoleLog.postMessage(message.join(" "));
        }
        window.addEventListener('error', function(event) {
            window.webkit.messageHandlers.scriptError.postMessage("[JAVASCRIPT][GLOBAL ERROR]: " + event.message + " at " + event.filename + ":" + event.lineno);
        });

        """
        webView.evaluateJavaScript(consoleScript, completionHandler: nil)
    }

    private func includeScript(webView: WKWebView, script: Script) {
        webView.evaluateJavaScript(script.body)
    }

    func callNew<I: Encodable, T: Decodable>(
        function: String,
        with input: I,
        as _: T.Type
    ) async throws -> T {
        let inputJson = input.rawJSON()

        let script = """
        return \(function)(\(inputJson))
        """

        let resultString: String
        do {
            resultString = try await evaluateFunction(body: script)
        } catch {
            print("Javascript function (\(function)) failed with error: \(error)")
            throw error
        }

        let data = Data(resultString.utf8) // cache, will be used twice below
        if let scriptError = try? JSONCoding.decoder.decode(ScriptError.self, from: data) {
            throw scriptError
        }

        return try T.decodeFrom(jsonData: data)
    }

    func callMiddleware<I: Encodable, T: Decodable>(
        function: String,
        with input: I,
        middleware body: String,
        middlewareFnName: String,
        as _: T.Type
    ) async throws -> T {
        let inputJson = input.rawJSON()

        let script = """
        \(body)

        let inputs = \(inputJson)

        inputs.middleware_fn = \(middlewareFnName)

        return \(function)(inputs)
        """

        let resultString: String
        do {
            resultString = try await evaluateFunction(body: script)
        } catch {
            print("Javascript function (\(function)) failed with error: \(error)")
            throw error
        }

        let data = Data(resultString.utf8) // cache, will be used twice below
        if let scriptError = try? JSONCoding.decoder.decode(ScriptError.self, from: data) {
            throw scriptError
        }

        return try T.decodeFrom(jsonData: data)
    }

    private func evaluateFunction(body: String, attempts: Int = 0) async throws -> String {
        let maxAttempts = 2
        let requestId = UUID().uuidString

        let script = """
        (() => {
            try {
                var result = (function() {
                    \(body)
                })();
                if (typeof result === 'undefined') {
                    throw new Error('undefined result')
                }
                window.webkit.messageHandlers.jsBridge.postMessage({ id: "\(requestId)", value: result });
            } catch (e) {
                window.webkit.messageHandlers.jsBridge.postMessage({ id: "\(requestId)", error: e.toString() });
            }
        })();
        """

        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuationStreams[requestId] = continuation
        }

        do {
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
        // Handle responses from evaluateFunction via jsBridge
        if message.name == "jsBridge",
           let body = message.body as? [String: Any],
           let id = body["id"] as? String,
           let continuation = continuationStreams.removeValue(forKey: id)
        {
            if let value = body["value"] as? String {
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
