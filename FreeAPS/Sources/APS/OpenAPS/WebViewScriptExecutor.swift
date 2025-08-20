import WebKit

struct ScriptError: Decodable, Error {
    let script_error: String
}

@MainActor class WebViewScriptExecutor: NSObject, WKScriptMessageHandler {
    private var webView: WKWebView!

    init(frame _: CGRect = .zero) {
        super.init()

        webView = createWebView()
    }

    private func createWebView() -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(self, name: "consoleLog")
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

    func invoke<I: Encodable, T: Decodable>(
        function: String,
        with input: I,
        as _: T.Type
    ) async throws -> T {
        let resultString: String
        do {
            resultString = try await webView.callAsyncJavaScriptShim(
                "(input) => iaps.invoke(\"\(function)\", input)",
                argument: input,
                in: nil,
                contentWorld: .page
            )
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
    }
}

public extension WKWebView {
    @MainActor @preconcurrency func callAsyncJavaScriptShim<I: Encodable>(
        _ functionBody: String,
        argument: I,
        in frame: WKFrameInfo? = nil,
        contentWorld: WKContentWorld
    ) async throws -> String {
        #if targetEnvironment(simulator)
            // callAsyncJavaScript crashes in the simulator: // https://developer.apple.com/forums/thread/779012

            let argJSON = argument.rawJSON()
            let wrapped = """
              (\(functionBody))(\(argJSON));
            """

            return try await withCheckedThrowingContinuation { cont in
                self.evaluateJavaScript(wrapped) { value, error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else if let string = value as? String {
                        cont.resume(returning: string)
                    } else {
                        cont.resume(throwing: ScriptError(script_error: "invalid return value"))
                    }
                }
            }

        #else

            let result = try await callAsyncJavaScript(
                functionBody,
                arguments: ["input": argument.toJSONObject()],
                in: frame,
                contentWorld: contentWorld
            )

            guard let string = result as? String else {
                throw ScriptError(script_error: "invalid return value")
            }
            return string

        #endif
    }
}
