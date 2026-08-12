import UIKit
import WebKit

struct ScriptError: Decodable, Error {
    let script_error: String
}

final class WebViewScriptExecutor: Sendable {
    @MainActor private var webView: WKWebView?

    nonisolated init(frame _: CGRect = .zero) {
        Task {
            await self.createWebView()
        }
    }

    deinit {
        let view = MainActor.assumeIsolated { self.webView }
        DispatchQueue.main.async {
            view?.removeFromSuperview()
        }
    }

    private func createWebView() async {
        await MainActor.run {
            let contentController = WKUserContentController()
            let messageHandler = JSMessageBridge()
            messageHandler.executor = self
            contentController.add(messageHandler, name: "consoleLog")
            contentController.add(messageHandler, name: "scriptError")

            let config = WKWebViewConfiguration()
            config.userContentController = contentController

            let webView = WKWebView(frame: .zero, configuration: config)

            injectConsoleLogHandler(webView: webView)

            includeScript(webView: webView, script: Script(name: OpenAPS.Bundle.oref0))

            self.webView = webView
            self.ensureAttachedToWindow()
        }
    }

    @MainActor private func ensureAttachedToWindow() {
        guard let webView, webView.superview == nil else { return }

        var window: UIWindow?
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        {
            window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        }
        if window == nil {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
            }
        }

        if let window = window {
            window.addSubview(webView)
            debug(.openAPS, "WebView successfully attached to window for background protection")
        } else {
            // If we still can't find it, we can schedule a retry
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    self.ensureAttachedToWindow()
                }
            }
        }
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

    func invoke<I: Encodable & Sendable, T: Decodable & Sendable>(
        function: String,
        with input: I,
        as _: T.Type
    ) async throws -> T {
        let resultString = try await evaluate(function: function, with: input)

        let data = Data(resultString.utf8) // cache, will be used twice below
        if let scriptError = try? JSONCoding.decoder.decode(ScriptError.self, from: data) {
            throw scriptError
        }

        do {
            let result = try T.decodeFrom(jsonData: data)
            return result
        } catch {
            debug(.openAPS, "failed to decode result of \(function): \(error.localizedDescription)")
            throw error
        }
    }

    private func evaluate<I: Encodable & Sendable>(
        function: String,
        with input: I,
        attempts: Int = 0
    ) async throws -> String {
        let maxAttempts = 2
        do {
            return try await Task { @MainActor in
                self.ensureAttachedToWindow()
                guard let webView else {
                    throw NSError(
                        domain: "WebViewScriptExecutor", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "WebView not initialized yet"]
                    )
                }

                return try await Signpost.measure("js", poi: true, function) {
                    try await webView.callAsyncJavaScriptShim(
                        "iaps.invoke(\"\(function)\", input)",
                        argument: input,
                    )
                }
            }.value
        } catch {
            debug(.openAPS, "Javascript function (\(function)) attempt \(attempts + 1) failed with error: \(error)")
            await MainActor.run {
                self.webView?.removeFromSuperview()
            }
            await createWebView()
            if attempts < maxAttempts {
                return try await evaluate(function: function, with: input, attempts: attempts + 1)
            } else {
                throw error
            }
        }
    }

    // Handle messages from JavaScript (e.g., console.log)
    @MainActor fileprivate func didReceive(_ message: WKScriptMessage) {
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

@MainActor private final class JSMessageBridge: NSObject, WKScriptMessageHandler {
    weak var executor: WebViewScriptExecutor?

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        executor?.didReceive(message)
    }
}

public extension WKWebView {
    @MainActor @preconcurrency func callAsyncJavaScriptShim<I: Encodable>(
        _ functionBody: String,
        argument: I,
    ) async throws -> String {
        #if targetEnvironment(simulator)
            // callAsyncJavaScript crashes in the simulator: // https://developer.apple.com/forums/thread/779012

            let argJSON = argument.rawJSON()
            let wrapped = """
              ((input) => \(functionBody))(\(argJSON))
            """

            return try await withCheckedThrowingContinuation { cont in
                self.evaluateJavaScript(wrapped) { value, error in
                    if let error = error {
                        debug(.openAPS, "JS function invocation failed: \(error.localizedDescription)")
                        cont.resume(throwing: error)
                    } else if let string = value as? String {
                        cont.resume(returning: string)
                    } else {
                        debug(.openAPS, "JS function invocation failed: invalid return value")
                        cont.resume(throwing: ScriptError(script_error: "invalid return value"))
                    }
                }
            }

        #else
            let wrapped = """
              return \(functionBody)
            """

            let result = try await callAsyncJavaScript(
                wrapped,
                arguments: ["input": argument.toJSONObject()],
                in: nil,
                contentWorld: .page
            )

            guard let string = result as? String else {
                throw ScriptError(script_error: "invalid return value")
            }
            return string

        #endif
    }
}
