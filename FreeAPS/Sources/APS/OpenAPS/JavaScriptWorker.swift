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
                warning(.openAPS, "JavaScript Error: \(error)")
            }
        }
        let consoleLog: @convention(block) (String) -> Void = { message in
            if message.count > 3 { // Remove the cryptic test logs created during development of Autosens
                debug(.openAPS, "JavaScript log: \(message)")
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
        return ctx.evaluateScript(string)
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
