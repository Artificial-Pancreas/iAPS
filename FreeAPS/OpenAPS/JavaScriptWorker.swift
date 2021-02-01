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

        context.setObject(require, forKeyedSubscript: "require" as NSString)

    }

    private lazy var require: @convention(block) (String) -> (JSValue?) = { path in
        switch path {
        case "../round-basal", "./round-basal":
            self.evaluate(script: Script(name: "oref0/lib/round-basal"))
        case "lodash/endsWith":
            self.evaluate(script: Script(name: "lodash"))
        default:
            return nil
        }

        return self.context.objectForKeyedSubscript("module")?.objectForKeyedSubscript("exports")
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
        context.objectForKeyedSubscript("freeaps")!.objectForKeyedSubscript("log")!.toString()!
    }

//    func recursivePathsForResources(type: String, in directoryPath: String) -> [String] {
//        // Enumerators are recursive
//        let enumerator = FileManager.default.enumerator(atPath: directoryPath)
//        var filePaths: [String] = []
//
//        while let filePath = enumerator?.nextObject() as? String {
//
//            if URL(fileURLWithPath: filePath).pathExtension == type {
//                filePaths.append(directoryPath.byAppending(pathComponent: filePath))
//            }
//        }
//        return filePaths
//    }
}
