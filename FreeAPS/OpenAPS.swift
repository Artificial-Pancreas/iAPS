//
//  OpenAPS.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 12.01.2021.
//

import Foundation
import JavaScriptCore

final class OpenAPS {
    private let vmQueue = DispatchQueue(label: "DispatchQueue.JSVirtualMachine")

    func determineBasal() {
        let vm = vmQueue.sync { JSVirtualMachine()! }
        let context = JSContext(virtualMachine: vm)!

        context.exceptionHandler = { context, exception in
            print(exception!.toString()!)
        }

        let scripts = [
            loadScript(name: "prepare"),
            loadScript(name: "basal-set-temp"),
            loadScript(name: "determine-basal"),
            loadScript(name: "glucose-get-last")
        ]

        scripts.forEach { context.evaluateScript($0) }

        let glucose = loadJSON(name: "glucose")
        let currentTemp = loadJSON(name: "temp_basal")
        let iobData = loadJSON(name: "iob")
        let profile = loadJSON(name: "profile")
        let autosensData = loadJSON(name: "autosens")
        let mealData = loadJSON(name: "meal")

        context.evaluateScript("var glucoseStatus = getLastGlucose(\(glucose));")
        let result = context.evaluateScript("determine_basal(glucoseStatus, \(currentTemp), \(iobData), \(profile), \(autosensData), \(mealData), tempBasalFunctions, true, 100, 1527924300000);")
        print(result!.toDictionary()!)
        print(context.objectForKeyedSubscript("logError")!
               .toString()!)

    }

    private func loadScript(name: String) -> String {
        try! String(contentsOf: Bundle.main.url(forResource: "javascript/\(name)", withExtension: "js")!)
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }
}
