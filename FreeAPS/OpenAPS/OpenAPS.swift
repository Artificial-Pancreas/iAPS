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
    private let jsWorker = JavaScriptWorker()

    init() {
        loadScripts()
    }

    private func loadScripts() {
        let scripts = [
            Script(name: "prepare"),
            Script(name: "basal-set-temp"),
            Script(name: "determine-basal"),
            Script(name: "glucose-get-last")
        ]

        scripts.forEach { jsWorker.evaluate(script: $0) }
    }

    func determineBasal() {
        let glucose = loadJSON(name: "glucose")
        let currentTemp = loadJSON(name: "temp_basal")
        let iobData = loadJSON(name: "iob")
        let profile = loadJSON(name: "profile")
        let autosensData = Autosens(ratio: 1.0).toString()
        let mealData = loadJSON(name: "meal")

        jsWorker.evaluate(string: "var glucoseStatus = getLastGlucose(\(glucose));")
        let result = jsWorker.evaluate(string: "determine_basal(glucoseStatus, \(currentTemp), \(iobData), \(profile), \(autosensData), \(mealData), tempBasalFunctions, true, 100, 1527924300000);")
        print(result!.toDictionary()!)
        print(jsWorker["logError"]!.toString()!)
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }
}
