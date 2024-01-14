import Foundation
import JavaScriptCore

private let contextLock = NSRecursiveLock()

final class JavaScriptWorker {
    private let processQueue = DispatchQueue(label: "DispatchQueue.JavaScriptWorker")
    private let virtualMachine: JSVirtualMachine
    @SyncAccess(lock: contextLock) private var commonContext: JSContext? = nil

    init() {
        virtualMachine = processQueue.sync { JSVirtualMachine()! }
    }

    private func createContext() -> JSContext {
        let context = JSContext(virtualMachine: virtualMachine)!

        context.exceptionHandler = { _, exception in
            if let error = exception?.toString() {
                warning(.openAPS, "JavaScript Exception Handler: \(error)")
            }
        }

        let consoleLog: @convention(block) (String) -> Void = { message in
            // try not to log "x", "-", "+", "=", etc.
            if message.count > 1 {
                debug(.openAPS, "JavaScript Log: \(message)")
            }
        }

        context.setObject(
            consoleLog,
            forKeyedSubscript: "_consoleLog" as NSString
        )

        return context
    }

    @discardableResult func evaluate(script: Script) -> JSValue! {
        evaluate(string: script.body)
    }

    private func evaluate(string: String) -> JSValue! {
        let ctx = commonContext ?? createContext()
        let result = ctx.evaluateScript(string)

        // Check if result is defined
        guard let result = result else {
            debug(.openAPS, "JavaScript Evalutation Log: JS returning UNDEFINED")
            return nil
        }

        if !result.isObject, let log = result.toString(), log != "undefined", !log.isEmpty, !log.contains("insulinReq\":") {
            debug(.openAPS, "JavaScript Evalutation Log: \(log)")
        }

        return result
    }

    private func json(for string: String) -> RawJSON {
        evaluate(string: "JSON.stringify(\(string), null, 4);")!.toString()!
    }

    func call(function: String, with arguments: [JSON]) -> RawJSON {
        let joined = arguments.map(\.rawJSON).joined(separator: ",")
        return json(for: "\(function)(\(joined))")
    }

    func inCommonContext<Value>(execute: (JavaScriptWorker) -> Value) -> Value {
        commonContext = createContext()
        defer {
            commonContext = nil
        }
        return execute(self)
    }
}
