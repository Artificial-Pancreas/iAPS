//
//  JavaScriptWorker.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 29.01.2021.
//

import Foundation
import JavaScriptCore

final class JavaScriptWorker {
    private let processQueue = DispatchQueue(label: "DispatchQueue.JavaScriptWorker")
    private let virtualMachine: JSVirtualMachine
    private let context: JSContext

    init() {
        virtualMachine = processQueue.sync { JSVirtualMachine()! }
        context = JSContext(virtualMachine: virtualMachine)!
        context.exceptionHandler = { _, exception in
            if let error = exception?.toString() {
                print(error)
            }
        }
    }

    @discardableResult
    func evaluate(script: Script) -> JSValue! {
        context.evaluateScript(script.body)
    }

    @discardableResult
    func evaluate(string: String) -> JSValue! {
        context.evaluateScript(string)
    }

    subscript(key: String) -> JSValue! {
        get {
            context.objectForKeyedSubscript(key)
        }
        set(newValue) {
            context.setObject(newValue, forKeyedSubscript: key as NSString)
        }
    }


    func json(for string: String) -> JSON {
        evaluate(string: "JSON.stringify(\(string));")!.toString()!
    }

    func call(function: String, with arguments: [JSON]) -> JSON {
        let joined = arguments.map(\.string).joined(separator: ",")
        return json(for: "\(function)(\(joined))")
    }

    func setEnviromentValue(_ value: JSON, forKey key: String) {
        evaluate(string: "freeaps.\(key) = \(value.string);")
    }

    var log: String {
        context.objectForKeyedSubscript("freeapsLog")!.toString()!
    }
}
