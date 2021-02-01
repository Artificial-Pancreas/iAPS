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

//    func iob() {
//
//    }
//
    func meal() {
        let jsWorker = JavaScriptWorker()

        let pumphistory = loadJSON(name: "pumphistory")
        let profile = loadJSON(name: "profile")
        let clock = loadJSON(name: "clock")
        let glucose = loadJSON(name: "glucose")
        let basalProfile = loadJSON(name: "basal_profile")
        let carbhistory = loadJSON(name: "carbhistory")


        jsWorker.evaluate(script: Script(name:"lib-meal-index-bundle"))
        let result = jsWorker.call(function: "MEAL_JS_GENERATE", with: [
            pumphistory,
            profile,
            clock,
            glucose,
            basalProfile,
            carbhistory
        ])
        print(result)
    }

    func determineBasal() {
        let jsWorker = JavaScriptWorker()

        let scripts = [
            Script(name: "prepare"),
            Script(name: "basal-set-temp"),
            Script(name: "determine-basal"),
            Script(name: "glucose-get-last")
        ]

        scripts.forEach { jsWorker.evaluate(script: $0) }

        let glucose = loadJSON(name: "glucose")
        let currentTemp = loadJSON(name: "temp_basal")
        let iobData = loadJSON(name: "iob")
        let profile = loadJSON(name: "profile")
        let autosensData = Autosens(ratio: 1.0)
        let mealData = loadJSON(name: "meal")
        let tempBasalFunctions: OpenAPSName = .tempBasalFunctions
        let microBolusAllowed = true
        let reservoir = 100
        let tsMilliseconds = 1527924300000

        let glucoseStatus = jsWorker.call(function: .getLastGlucose, with: [glucose])
        let result = jsWorker.call(
            function: .determineBasal,
            with: [
                glucoseStatus,
                currentTemp,
                iobData,
                profile,
                autosensData,
                mealData,
                tempBasalFunctions,
                microBolusAllowed,
                reservoir,
                tsMilliseconds
            ]
        )
        print(jsWorker.log)
        print(result)
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }
}

enum OpenAPSName: String {
    case tempBasalFunctions
    case getLastGlucose
    case determineBasal = "determine_basal"
}

extension JavaScriptWorker {
    func call(function: OpenAPSName, with arguments: [JSON]) -> JSON {
        call(function: function.string, with: arguments)
    }
}
