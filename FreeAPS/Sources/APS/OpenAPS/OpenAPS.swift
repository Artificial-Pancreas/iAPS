import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage

    init(storage: FileStorage) {
        self.storage = storage
    }

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
            let tsMilliseconds: Double = 1_527_924_300_000

            let preferences = self.exportDefaultPreferences()

            print("DEFAULT PREFERENCES: \(preferences)")

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

            let autotunePreppedGlucose = self.autotunePrepare(
                pumphistory: pumphistory,
                profile: profile,
                glucose: glucose,
                pumpprofile: profile,
                categorizeUamAsBasal: true,
                tuneInsulinCurve: false
            )
            print("AUTOTUNE PREP: \(autotunePreppedGlucose)")

            let previousAutotune = try? self.storage.retrieve(Settings.autotune, as: RawJSON.self)

            let autotuneResult = self.autotuneRun(
                autotunePreparedData: autotunePreppedGlucose,
                previousAutotuneResult: previousAutotune ?? profile,
                pumpProfile: profile
            )

            try? self.storage.save(autotuneResult, as: Settings.autotune)

            print("AUTOTUNE RESULT: \(autotuneResult)")

            let finishDate = Date()
            print("FINISH at \(finishDate), duration \(finishDate.timeIntervalSince(now)) s")
        }
    }

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON, pumphistory24: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.iob))
            worker.evaluate(script: Script(name: Prepare.iob))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                autosens,
                pumphistory24
            ])
        }
    }

    private func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.meal))
            worker.evaluate(script: Script(name: Prepare.meal))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                basalProfile,
                clock,
                carbs,
                glucose
            ])
        }
    }

    private func autotunePrepare(
        pumphistory: JSON,
        profile: JSON,
        glucose: JSON,
        pumpprofile: JSON,
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.autotunePrep))
            worker.evaluate(script: Script(name: Prepare.autotunePrep))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                glucose,
                pumpprofile,
                categorizeUamAsBasal,
                tuneInsulinCurve
            ])
        }
    }

    private func autotuneRun(
        autotunePreparedData: JSON,
        previousAutotuneResult: JSON,
        pumpProfile: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.autotuneCore))
            worker.evaluate(script: Script(name: Prepare.autotuneCore))
            return worker.call(function: Function.generate, with: [
                autotunePreparedData,
                previousAutotuneResult,
                pumpProfile
            ])
        }
    }

    private func glucoseGetLast(glucose: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.getLastGlucose))
            return worker.call(function: Function.freeaps, with: [glucose])
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
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.basalSetTemp))
            worker.evaluate(script: Script(name: Prepare.determineBasal))
            worker.evaluate(script: Script(name: Bundle.determineBasal))

            return worker.call(
                function: Function.freeaps,
                with: [
                    glucoseStatus,
                    currentTemp,
                    iob,
                    profile,
                    aurosens,
                    meal,
                    Function.tempBasalFunctions,
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
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.autosens))
            worker.evaluate(script: Script(name: Prepare.autosens))

            return worker.call(
                function: Function.generate,
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

    private func exportDefaultPreferences() -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))
            return worker.call(function: Function.exportDefaults, with: [])
        }
    }

    private func makeProfile(
        preferences: JSON,
        pumpSettings: JSON,
        bgTargets: JSON,
        basalProfile: JSON,
        isf: JSON,
        carbRatio: JSON,
        tempTargets: JSON,
        model: JSON,
        autotune: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))

            return worker.call(
                function: Function.generate,
                with: [
                    preferences,
                    pumpSettings,
                    bgTargets,
                    basalProfile,
                    isf,
                    carbRatio,
                    tempTargets,
                    model,
                    autotune
                ]
            )
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }
}

extension OpenAPS {
    private enum Bundle {
        static let iob = "bundle/iob"
        static let meal = "bundle/meal"
        static let autotunePrep = "bundle/autotune-prep"
        static let autotuneCore = "bundle/autotune-core"
        static let getLastGlucose = "bundle/glucose-get-last"
        static let basalSetTemp = "bundle/basal-set-temp"
        static let determineBasal = "bundle/determine-basal"
        static let autosens = "bundle/autosens"
        static let profile = "bundle/profile"
    }

    private enum Prepare {
        static let iob = "prepare/iob"
        static let meal = "prepare/meal"
        static let autotunePrep = "prepare/autotune-prep"
        static let autotuneCore = "prepare/autotune-core"
        static let determineBasal = "prepare/determine-basal"
        static let autosens = "prepare/autosens"
        static let profile = "prepare/profile"
    }

    private enum Settings {
        static let autotune = "settings/autotune.json"
    }

    private enum Function {
        static let freeaps = "freeaps"
        static let generate = "generate"
        static let tempBasalFunctions = "tempBasalFunctions"
        static let exportDefaults = "exportDefaults"
    }
}
