//
//  OpenAPS.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 12.01.2021.
//

import Foundation
import JavaScriptCore

final class OpenAPS {
    func test() {
        let pumphistory = loadJSON(name: "pumphistory")
        let profile = loadJSON(name: "profile")
        let basalProfile = loadJSON(name: "basal_profile")
        let clock = loadJSON(name: "clock")
        let carbs = loadJSON(name: "carbhistory")
        let glucose = loadJSON(name: "glucose")
        let currentTemp = loadJSON(name: "temp_basal")
        let autosens = Autosens(ratio: 1)
        let reservoir = 100
        let tsMilliseconds: Double = 1527924300000


        let iobResult = iob(
            pumphistory: pumphistory,
            profile: profile,
            clock: clock,
            autosens: autosens,
            pumphistory24: "null"
        )
        print("IOB: \(iobResult)")

        let mealResult = meal(
            pumphistory: pumphistory,
            profile: profile,
            basalProfile: basalProfile,
            clock: clock,
            carbs: carbs,
            glucose: glucose
        )

        print("MEAL: \(mealResult)")

        let glucoseStatus = glucoseGetLast(glucose: glucose)
        print("GLUCOSE STATUS: \(glucoseStatus)")

        let suggested = determineBasal(
            glucoseStatus: glucoseStatus,
            currentTemp: currentTemp,
            iob: iobResult,
            profile: profile,
            aurosens: autosens,
            meal: mealResult,
            microBolusAllowed: true,
            reservoir: reservoir,
            tsMilliseconds: tsMilliseconds
        )

        print("SUGGESTED: \(suggested)")
    }

    func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON, pumphistory24: JSON) -> JSON {
        let jsWorker = JavaScriptWorker()
        jsWorker.evaluate(script: Script(name:"iob-bundle"))
        jsWorker.evaluate(script: Script(name:"prepare-iob"))
        return jsWorker.call(function: "generate", with: [
            pumphistory,
            profile,
            clock,
            autosens,
            pumphistory24
        ])
    }

    func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> JSON {
        let jsWorker = JavaScriptWorker()
        jsWorker.evaluate(script: Script(name:"meal-bundle"))
        jsWorker.evaluate(script: Script(name:"prepare-meal"))
        return jsWorker.call(function: "generate", with: [
            pumphistory,
            profile,
            basalProfile,
            clock,
            carbs,
            glucose
        ])
    }

    func glucoseGetLast(glucose: JSON) -> JSON {
        let jsWorker = JavaScriptWorker()
        jsWorker.evaluate(script: Script(name:"glucose-get-last-bundle"))
        return jsWorker.call(function: "freeaps", with: [glucose])
    }

    func determineBasal(
        glucoseStatus: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        aurosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: Int,
        tsMilliseconds: Double
    ) -> JSON {
        let jsWorker = JavaScriptWorker()

        jsWorker.evaluate(script: Script(name:"basal-set-temp-bundle"))
        jsWorker.evaluate(script: Script(name:"prepare-determine-basal"))
        let funcKey = "tempBasalFunctions"
        jsWorker.evaluate(script: Script(name:"determine-basal-bundle"))

        return jsWorker.call(
            function: "freeaps",
            with: [
                glucoseStatus,
                currentTemp,
                iob,
                profile,
                aurosens,
                meal,
                funcKey,
                microBolusAllowed,
                reservoir,
                tsMilliseconds
            ]
        )
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }
}
