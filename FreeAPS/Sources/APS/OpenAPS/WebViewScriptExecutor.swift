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

    init(frame: CGRect = .zero) {
        super.init()

        // Configure WKWebView with a message handler for console logs
        let contentController = WKUserContentController()
        contentController.add(self, name: "consoleLog")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        // Initialize WKWebView
        webView = WKWebView(frame: frame, configuration: config)

        // Inject script to capture console.log and console.error
        injectConsoleLogHandler()

        // Load static JavaScript functions
        loadStaticScripts()
    }

    private func injectConsoleLogHandler() {
        let consoleScript = """
        delete window.strictMode;
        window.console.log = function(message) {
            window.webkit.messageHandlers.consoleLog.postMessage(message);
        };
        window.console.error = function(message) {
            window.webkit.messageHandlers.consoleLog.postMessage("[ERROR] " + message);
        };
        window._consoleLog = function(message) {
            window.webkit.messageHandlers.consoleLog.postMessage("[ERROR] " + message);
        };
        window.addEventListener('error', function(event) {
            window.webkit.messageHandlers.consoleLog.postMessage("[GLOBAL ERROR]: " + event.message + " at " + event.filename + ":" + event.lineno);
        });
        """
        webView.evaluateJavaScript(consoleScript, completionHandler: nil)
    }

    private func loadStaticScripts() {
        let scriptNames = [
            OpenAPS.Bundle.autosens,
            OpenAPS.Bundle.autotuneCore,
            OpenAPS.Bundle.autotunePrep,
            OpenAPS.Bundle.basalSetTemp,
            OpenAPS.Bundle.determineBasal,
            OpenAPS.Bundle.getLastGlucose,
            OpenAPS.Bundle.iob,
            OpenAPS.Bundle.meal,
            OpenAPS.Bundle.profile,
            OpenAPS.Prepare.log,
            OpenAPS.Prepare.autosens,
            OpenAPS.Prepare.autotuneCore,
            OpenAPS.Prepare.autotunePrep,
            OpenAPS.Prepare.determineBasal,
            OpenAPS.Prepare.iob,
            OpenAPS.Prepare.meal,
            OpenAPS.Prepare.profile
        ]
        for scriptName in scriptNames {
            webView.evaluateJavaScript(Script(name: scriptName).body) { _, error in
                if let error = error {
                    print("Error loading script \(scriptName): \(error)")
                } else {
                    print("Successfully loaded script: \(scriptName)")
                }
            }
        }
    }

    func evaluate(script: Script) {
        webView.evaluateJavaScript(script.body, completionHandler: nil)
    }

    func call(function: String, with arguments: [JSON]) -> RawJSON {
        let group = DispatchGroup()
        let asyncResult = WebViewScriptExecutorAtomic<Result<RawJSON, Error>?>(nil)

        group.enter()
        DispatchQueue.global().async {
            Task {
                do {
                    let result = try await self.callAsync(function: function, with: arguments)
                    asyncResult.set(.success(result))
                } catch {
                    print("Error in async call to \(function): \(error)")
                    asyncResult.set(.failure(error))
                }
                group.leave()
            }
        }

        group.wait()

        switch asyncResult.get() {
        case let .success(result):
            print("The script returned successfully:")
            print(result)
            return result
        case let .failure(error):
            print("An error occurred while executing the script:")
            print(error)
            return ""
        case .none:
            print("No result from the script")
            return ""
        }
    }

    func callAsync(function: String, with arguments: [JSON]) async throws -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")

        // JavaScript code to handle async functions and Promises
        let script = """
        (function() {
            let result = \(function)(\(joined));
            return JSON.stringify(result ?? "", null, 4);
        })();
        """

        var result: RawJSON?
        var scriptError: Error?

        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let resultString = result as? String {
                    continuation.resume(returning: resultString)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "ScriptExecutorError",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No result from script"]
                    ))
                }
            }
        }
    }

    // Handle messages from JavaScript (e.g., console.log)
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "consoleLog", let logMessage = message.body as? String {
            print("[JavaScript Console]: \(logMessage)")
        }
    }
}
