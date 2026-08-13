import UIKit
import WebKit

struct ScriptError: Decodable, Error {
    let script_error: String
}

final class WebViewScriptExecutor: Sendable {
    static let defaultTimeout: Duration = .seconds(30)
    private static let maxAttachAttempts = 5
    private static let readyMessage = "ready"

    @MainActor private var webView: WKWebView?

    /// True once the current WebView has loaded its document and every user script has run.
    @MainActor private var isReady = false
    @MainActor private var readyWaiters = [CheckedContinuation<Void, Error>]()
    @MainActor private var webViewGeneration = 0

    nonisolated init(frame _: CGRect = .zero) {
        Task {
            await self.createWebView()
        }
    }

    /** This is not currently used in the app - we keep the WebViewScriptExecutor instance forever.
      * If at some point we need to create/destroy instances of WebViewScriptExecutor dynamically (tests, previews, etc),
      * the owner will be responsible for calling this function.
     */
    @MainActor func shutdown() {
        webView?.removeFromSuperview()
        failReadyWaiters("WebViewScriptExecutor was shut down")
    }

    private func createWebView() async {
        await MainActor.run {
            self.webView?.removeFromSuperview()
            self.failReadyWaiters("WebView replaced before it became ready")
            self.isReady = false
            self.webViewGeneration &+= 1

            let contentController = WKUserContentController()
            let messageHandler = JSMessageBridge()
            messageHandler.executor = self
            contentController.add(messageHandler, name: "consoleLog")
            contentController.add(messageHandler, name: "scriptError")
            contentController.add(messageHandler, name: Self.readyMessage)

            // Register the oref bundles as user scripts.
            // WebKit re-applies user scripts on every document load.
            for source in Self.userScriptSources() {
                contentController.addUserScript(WKUserScript(
                    source: source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                ))
            }
            contentController.addUserScript(WKUserScript(
                source: "window.webkit.messageHandlers.\(Self.readyMessage).postMessage(\"\");",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))

            let config = WKWebViewConfiguration()
            config.userContentController = contentController

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = messageHandler

            // User scripts only run as part of a document load, so give the view one.
            // This is also what makes webViewWebContentProcessDidTerminate reliable.
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

            self.webView = webView
            self.ensureAttachedToWindow()
        }
    }

    /// Recreate only if nobody else already did, so one dead process yields one rebuild.
    private func recreateWebView(ifGeneration generation: Int) async {
        let isCurrent = await MainActor.run { self.webViewGeneration == generation }
        if isCurrent {
            await createWebView()
        }
    }

    @MainActor private func failReadyWaiters(_ reason: String) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        guard !waiters.isEmpty else { return }

        let error = NSError(
            domain: "WebViewScriptExecutor", code: 3,
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    @MainActor private func awaitReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyWaiters.append(continuation)
        }
    }

    @MainActor fileprivate func webContentProcessDidTerminate(_ terminatedWebView: WKWebView) {
        guard terminatedWebView === webView else { return }

        // callAsyncJavaScript normally fails in-flight calls itself when the process
        // dies, and the watchdog covers it when it does not. Rebuilding here means the
        // retry lands on a live process instead of rediscovering the dead one — and it
        // puts jetsam in the log as something distinct from silent suspension.
        warning(.openAPS, "WebContent process terminated by iOS - rebuilding the WebView")
        Task { await createWebView() }
    }

    @MainActor private func ensureAttachedToWindow(attempt: Int = 0) {
        guard let webView, webView.superview == nil else { return }

        guard let window = Self.hostWindow() else {
            guard attempt < Self.maxAttachAttempts else {
                debug(.openAPS, "WebView has no window to attach to; retrying on next JS call")
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.ensureAttachedToWindow(attempt: attempt + 1)
            }
            return
        }

        webView.isUserInteractionEnabled = false
        window.addSubview(webView)
        debug(.openAPS, "WebView attached to window for background protection")
    }

    @MainActor private static func hostWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.compactMap { $0 as? UIWindowScene }.first
        guard let windowScene else { return nil }
        return windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
    }

    private static func userScriptSources() -> [String] {
        let consoleScript = """
        var _consoleLog = function (message) {
            window.webkit.messageHandlers.consoleLog.postMessage(message.join(" "));
        }
        window.addEventListener('error', function(event) {
            window.webkit.messageHandlers.scriptError.postMessage("[JAVASCRIPT][GLOBAL ERROR]: " + event.message + " at " + event.filename + ":" + event.lineno);
        });

        """
        return [consoleScript, Script(name: OpenAPS.Bundle.oref0).body]
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
        let generation = await MainActor.run { self.webViewGeneration }
        do {
            return try await withTimeout("js.\(function)", Self.defaultTimeout) { [self] in
                try await Task { @MainActor in
                    self.ensureAttachedToWindow()
                    try await self.awaitReady()
                    guard let webView = self.webView else {
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
            }
        } catch {
            warning(.openAPS, "Javascript function (\(function)) attempt \(attempts + 1) failed with error: \(error)")
            await recreateWebView(ifGeneration: generation)
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
        // The documentEnd user script fired: the document (re)loaded and the oref
        // bundle has been injected, so queued calls may proceed.
        // A replaced WebView's in-flight ready message must not mark its successor
        // ready before that one has injected anything.
        if message.name == Self.readyMessage, message.webView === webView {
            isReady = true
            let waiters = readyWaiters
            readyWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }
}

@MainActor private final class JSMessageBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var executor: WebViewScriptExecutor?

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        executor?.didReceive(message)
    }

    /// The WebContent (JS) process died — jetsam under memory pressure, a crash, or iOS
    /// reclaiming it in the background.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        executor?.webContentProcessDidTerminate(webView)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        // The blank document that carries the user scripts failed to load, so nothing
        // was injected and awaitReady() will time out. Log it or it is invisible.
        warning(.openAPS, "WebView document load failed: \(error.localizedDescription)")
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
