import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage

    init(storage: FileStorage) {
        self.storage = storage
    }

    func loop() {
        processQueue.async {
            // status
            // check it before

            // profile
            let preferences = self.loadFileFromStorage(name: Settings.preferences)
            let pumpSettings = self.loadFileFromStorage(name: Settings.settings)
            let bgTargets = self.loadFileFromStorage(name: Settings.bgTargets)
            let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
            let isf = self.loadFileFromStorage(name: Settings.insulinSensitivities)
            let cr = self.loadFileFromStorage(name: Settings.carbRatios)
            let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
            let model = self.loadFileFromStorage(name: Settings.model)
            let autotune = self.loadFileFromStorage(name: Settings.autotune)

            let pumpProfile = self.makeProfile(
                preferences: preferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: RawJSON.null
            )

            let profile = self.makeProfile(
                preferences: preferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: autotune.isEmpty ? .null : autotune
            )

            try? self.storage.save(pumpProfile, as: Settings.pumpProfile)
            try? self.storage.save(profile, as: Settings.profile)

            // clock
            try? self.storage.save(Date(), as: Monitor.clock)

            // temp_basal
            let tempBasal = self.loadFileFromStorage(name: Monitor.tempBasal)

            // meal
            let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
            let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
            let glucose = self.loadFileFromStorage(name: Monitor.glucose)
            let clock = self.loadFileFromStorage(name: Monitor.clock)

            let meal = self.meal(
                pumphistory: pumpHistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbs: carbs,
                glucose: glucose
            )

            try? self.storage.save(meal, as: Monitor.meal)

            // iob
            let autosens = self.loadFileFromStorage(name: Settings.autosense)
            let iob = self.iob(
                pumphistory: pumpHistory,
                profile: profile,
                clock: clock,
                autosens: autosens.isEmpty ? .null : autosens
            )

            try? self.storage.save(iob, as: Monitor.iob)

            // determine-basal
            let reservoir = self.loadFileFromStorage(name: Monitor.reservoir)

            let suggested = self.determineBasal(
                glucose: glucose,
                currentTemp: tempBasal,
                iob: iob,
                profile: profile,
                autosens: autosens.isEmpty ? .null : autosens,
                meal: meal,
                microBolusAllowed: true,
                reservoir: reservoir
            )
            print("SUGGESTED: \(suggested)")

            try? self.storage.save(suggested, as: Enact.suggested)
        }
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

            let preferences = self.exportDefaultPreferences()

            print("DEFAULT PREFERENCES: \(preferences)")

            let autosensResult = self.autosense(
                pumpHistory: pumphistory,
                profile: profile,
                carbs: carbs,
                glucose: glucose,
                basalprofile: basalProfile,
                temptargets: RawJSON.null
            )
            print("AUTOSENS: \(autosensResult)")
            try? self.storage.save(autosensResult, as: Settings.autosense)

            let iobResult = self.iob(
                pumphistory: pumphistory,
                profile: profile,
                clock: clock,
                autosens: autosensResult
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
            try? self.storage.save(mealResult, as: Monitor.meal)

            let suggested = self.determineBasal(
                glucose: glucose,
                currentTemp: currentTemp,
                iob: iobResult,
                profile: profile,
                aurosens: autosensResult,
                meal: mealResult,
                microBolusAllowed: true,
                reservoir: reservoir
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

    func makeClock() {
        processQueue.async {
            try? self.storage.save(Date(), as: Monitor.clock)
        }
    }

    func makeMeal() {
        processQueue.async {
            let pumphistory = self.loadFileFromStorage(name: Monitor.pumpHistory)
            let profile = self.loadFileFromStorage(name: Settings.profile)
            let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
            let clock = self.loadFileFromStorage(name: Monitor.clock)
            let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
            let glucose = self.loadFileFromStorage(name: Monitor.glucose)

            let mealResult = self.meal(
                pumphistory: pumphistory,
                profile: profile,
                basalProfile: basalProfile,
                clock: clock,
                carbs: carbs,
                glucose: glucose
            )

            print("MEAL: \(mealResult)")
            try? self.storage.save(mealResult, as: Monitor.meal)
        }
    }

    func makeProfile(autotuned: Bool) {
        processQueue.async {
            print("MAKE PROFILE autotuned \(autotuned)")
            let preferences = self.loadFileFromStorage(name: Settings.preferences)
            let pumpSettings = self.loadFileFromStorage(name: Settings.settings)
            let bgTargets = self.loadFileFromStorage(name: Settings.bgTargets)
            let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
            let isf = self.loadFileFromStorage(name: Settings.insulinSensitivities)
            let cr = self.loadFileFromStorage(name: Settings.carbRatios)
            let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
            let model = self.loadFileFromStorage(name: Settings.model)
            let autotune = self.loadFileFromStorage(name: Settings.autotune)

            let profile = self.makeProfile(
                preferences: preferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: autotuned ? autotune : .null
            )

            print("PROFILE RESULT \n\(profile)")

            if autotuned {
                try? self.storage.save(profile, as: Settings.profile)
            } else {
                try? self.storage.save(profile, as: Settings.pumpProfile)
            }
        }
    }

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.iob))
            worker.evaluate(script: Script(name: Prepare.iob))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                autosens
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
                clock,
                glucose,
                basalProfile,
                carbs
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

    private func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Bundle.basalSetTemp))
            worker.evaluate(script: Script(name: Bundle.getLastGlucose))
            worker.evaluate(script: Script(name: Bundle.determineBasal))
            worker.evaluate(script: Script(name: Prepare.determineBasal))
            return worker.call(
                function: Function.generate,
                with: [
                    iob,
                    currentTemp,
                    glucose,
                    profile,
                    autosens,
                    meal,
                    microBolusAllowed,
                    reservoir
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
                    pumpSettings,
                    bgTargets,
                    isf,
                    basalProfile,
                    preferences,
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

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    static func defaults(for file: String) -> RawJSON {
        guard let url = Foundation.Bundle.main.url(forResource: "json/defaults/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }
}
