//
//  OpenAPS.swift
//  FreeAPS
//
//  Created by Ivan Valkou on 12.01.2021.
//

import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    func test() {
        processQueue.async {
            let now = Date()
            print("START at \(now)")
            let pumphistory = self.loadJSON(name: "pumphistory")
            let profile = self.loadJSON(name: "profile")
            let basalProfile = self.loadJSON(name: "basal_profile")
            let clock = self.loadJSON(name: "clock")
            let carbs = self.loadJSON(name: "carbhistory")
            let glucose = self.loadJSON(name: "glucose")
            let currentTemp = self.loadJSON(name: "temp_basal")
            let reservoir = 100
            let tsMilliseconds: Double = 1527924300000

            let autosensResult = self.autosense(
                pumpHistory: pumphistory,
                profile: profile,
                carbs: carbs,
                glucose: glucose,
                basalprofile: basalProfile,
                temptargets: "null"
            )
            print("AUTOSENS: \(autosensResult)")

            let iobResult = self.iob(
                pumphistory: pumphistory,
                profile: profile,
                clock: clock,
                autosens: autosensResult,
                pumphistory24: "null"
            )
            print("IOB: \(iobResult)")

            let mealResult = self.meal(
                pumphistory: pumphistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbs: carbs,
                glucose: glucose
            )

            print("MEAL: \(mealResult)")

            let glucoseStatus = self.glucoseGetLast(glucose: glucose)
            print("GLUCOSE STATUS: \(glucoseStatus)")

            let suggested = self.determineBasal(
                glucoseStatus: glucoseStatus,
                currentTemp: currentTemp,
                iob: iobResult,
                profile: profile,
                aurosens: autosensResult,
                meal: mealResult,
                microBolusAllowed: true,
                reservoir: reservoir,
                tsMilliseconds: tsMilliseconds
            )
            print("SUGGESTED: \(suggested)")
            let finishDate = Date()
            print("FINISH at \(finishDate), duration \(finishDate.timeIntervalSince(now)) s")
        }
    }

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON, pumphistory24: JSON) -> JSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name:"iob-bundle"))
            worker.evaluate(script: Script(name:"prepare-iob"))
            return worker.call(function: "generate", with: [
                pumphistory,
                profile,
                clock,
                autosens,
                pumphistory24
            ])
        }
    }

    private func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> JSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name:"meal-bundle"))
            worker.evaluate(script: Script(name:"prepare-meal"))
            return worker.call(function: "generate", with: [
                pumphistory,
                profile,
                basalProfile,
                clock,
                carbs,
                glucose
            ])
        }
    }

    private func glucoseGetLast(glucose: JSON) -> JSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name:"glucose-get-last-bundle"))
            return worker.call(function: "freeaps", with: [glucose])
        }
    }

    private func determineBasal(
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
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name:"basal-set-temp-bundle"))
            worker.evaluate(script: Script(name:"prepare-determine-basal"))
            let funcKey = "tempBasalFunctions"
            worker.evaluate(script: Script(name:"determine-basal-bundle"))

            return worker.call(
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
    }

    private func autosense(
        pumpHistory: JSON,
        profile: JSON,
        carbs: JSON,
        glucose: JSON,
        basalprofile: JSON,
        temptargets: JSON
    ) -> JSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name:"autosens-bundle"))
            worker.evaluate(script: Script(name:"prepare-autosens"))

            return worker.call(
                function: "generate",
                with: [
                    pumpHistory,
                    profile,
                    carbs,
                    glucose,
                    basalprofile,
                    temptargets
                ]
            )
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }
}
