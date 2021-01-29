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
        context.exceptionHandler = { context, exception in
            print(exception!.toString()!)
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
        context.objectForKeyedSubscript(key)
    }
}
