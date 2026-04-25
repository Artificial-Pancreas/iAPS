import Combine
import CoreData
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let scriptExecutor: WebViewScriptExecutor
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)
    private let storage: FileStorage
    private let glucoseStorage: GlucoseStorage
    private let nightscout: NightscoutManager
    private let pumpStorage: PumpHistoryStorage

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    init(
        storage: FileStorage,
        glucoseStorage: GlucoseStorage,
        nightscout: NightscoutManager,
        pumpStorage: PumpHistoryStorage,
        scriptExecutor: WebViewScriptExecutor
    ) {
        self.storage = storage
        self.glucoseStorage = glucoseStorage
        self.nightscout = nightscout
        self.pumpStorage = pumpStorage
        self.scriptExecutor = scriptExecutor
    }

    func determineBasal(
        currentTemp: TempBasal,
        clock: Date = Date(),
        temporary: TemporaryData,
        override: Override?
    ) -> Future<Suggestion?, Never> {
        Future { promise in
            self.processQueue.async {
                Task {
                    // For debugging
                    let start = Date.now
                    var now = Date.now

                    debug(.openAPS, "Start determineBasal")
                    self.storage.save(clock, as: Monitor.clock)
                    let tempBasal = currentTemp.rawJSON
                    self.storage.save(tempBasal, as: Monitor.tempBasal)

                    let (
                        pumpHistory,
                        carbs,
                        glucose,
                        preferences,
                        basalProfile,
                        data,
                        autosens,
                        reservoir,
                        storedProfile
                    ) = await (
                        self.pumpHistory(),
                        self.carbHistory(),
                        self.glucoseHistory(),
                        self.preferencesHistory(),
                        self.basalHistory(),
                        self.dataHistory(),
                        self.autosensHistory(),
                        self.reservoirHistory(),
                        self.profileHistory()
                    )

                    let preferencesData = Preferences(from: preferences)
                    let settings = FreeAPSSettings(from: data)
                    var profile = storedProfile
                    print("Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

                    now = Date.now
                    let tdd = CoreDataStorage()
                        .fetchInsulinDistribution().first
                    print("Time for tdd \(-1 * now.timeIntervalSinceNow) seconds")

                    now = Date.now
                    let (meal, iob) = await (self.meal(
                        pumphistory: pumpHistory,
                        profile: storedProfile,
                        basalProfile: basalProfile,
                        clock: clock,
                        carbs: carbs,
                        glucose: glucose,
                        temporary: temporary
                    ), self.iob(
                        pumphistory: pumpHistory,
                        profile: storedProfile,
                        clock: clock,
                        autosens: autosens.isEmpty ? .null : autosens
                    ))

                    self.storage.save(meal, as: Monitor.meal)
                    self.storage.save(iob, as: Monitor.iob)

                    if let iobEntries = IOBTick0.parseArrayFromJSON(from: iob) {
                        let cd = CoreDataStorage()
                        _ = cd.saveInsulinData(iobEntries: iobEntries)
                    }

                    print(
                        "Time for Meal and IOB module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                    )

                    // The Middleware layer.
                    now = Date.now
                    let alteredProfile = await self.middleware(
                        glucose: glucose,
                        currentTemp: tempBasal,
                        iob: iob,
                        profile: profile,
                        autosens: autosens.isEmpty ? .null : autosens,
                        meal: meal,
                        microBolusAllowed: true,
                        reservoir: reservoir
                    )

                    now = Date.now
                    // Auto ISF Layer
                    if let freeAPSSettings = settings,
                       (freeAPSSettings.autoisfEffective && self.notDisabled(override: override, settings: freeAPSSettings)) ||
                       (self.aisfEnabled(override: override) && !freeAPSSettings.isNighttime)
                    {
                        now = Date.now
                        profile = await self.autosisf(
                            glucose: glucose,
                            iob: iob,
                            profile: alteredProfile,
                            autosens: autosens.isEmpty ? .null : autosens,
                            pumpHistory: pumpHistory
                        )
                        print(
                            "Time for AutoISF module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                        )
                    } else { profile = alteredProfile }

                    now = Date.now
                    // The OpenAPS layer
                    let suggested = await self.determineBasal(
                        glucose: glucose,
                        currentTemp: tempBasal,
                        iob: iob,
                        profile: profile,
                        autosens: autosens.isEmpty ? .null : autosens,
                        meal: meal,
                        microBolusAllowed: true,
                        reservoir: reservoir,
                        pumpHistory: pumpHistory
                    )
                    print(
                        "Time for Determine Basal module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                    )
                    debug(.openAPS, "SUGGESTED: \(suggested)")

                    // Update Suggestion, when applicable (middleware / dynamic ISF / Auto ISF)
                    if var suggestion = Suggestion(from: suggested) {
                        now = Date.now

                        // Auto ISF
                        if let mySettings = settings, mySettings.autoisfEffective, let iob = suggestion.iob {
                            // If IOB < one hour of negative insulin and keto protection is active, then enact a small keto protection basal rate
                            if mySettings.ketoProtect, iob < 0,
                               let rate = suggestion.rate, rate <= 0,
                               let basal = self.readBasal(alteredProfile), iob < -basal, (suggestion.units ?? 0) <= 0,
                               let basalRate = self.aisfBasal(mySettings, basal, oref0Suggestion: suggestion)
                            {
                                suggestion = basalRate
                            }
                        }

                        // Process any eventual middleware/B30 basal rate
                        if let newSuggestion = self.overrideBasal(alteredProfile: profile, oref0Suggestion: suggestion) {
                            suggestion = newSuggestion
                        }
                        // Add reasons, when needed
                        suggestion.reason = self.reasons(
                            reason: suggestion.reason,
                            suggestion: suggestion,
                            preferences: preferencesData,
                            profile: profile,
                            tdd: tdd,
                            settings: settings,
                            override: override
                        )
                        // Update time
                        suggestion.timestamp = suggestion.deliverAt ?? clock
                        // Save
                        self.storage.save(suggestion, as: Enact.suggested)

                        promise(.success(suggestion))
                    } else {
                        promise(.success(nil))
                    }
                }
            }
        }
    }

    func autosense() -> Future<Autosens?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autosens")
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
                let glucose = self.glucoseStorage.retrieveFiltered()
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)

                Task {
                    let autosensResult = await self.autosense(
                        glucose: glucose,
                        pumpHistory: pumpHistory,
                        basalprofile: basalProfile,
                        profile: profile,
                        carbs: carbs,
                        temptargets: tempTargets
                    )

                    debug(.openAPS, "AUTOSENS: \(autosensResult)")
                    if var autosens = Autosens(from: autosensResult) {
                        autosens.timestamp = Date()
                        self.storage.save(autosens, as: Settings.autosense)
                        promise(.success(autosens))
                    } else {
                        promise(.success(nil))
                    }
                }
            }
        }
    }

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) -> Future<Autotune?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autotune")
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let glucose = self.glucoseStorage.retrieveFiltered()
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let pumpProfile = self.loadFileFromStorage(name: Settings.pumpProfile)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)

                Task {
                    let autotunePreppedGlucose = await self.autotunePrepare(
                        pumphistory: pumpHistory,
                        profile: profile,
                        glucose: glucose,
                        pumpprofile: pumpProfile,
                        carbs: carbs,
                        categorizeUamAsBasal: categorizeUamAsBasal,
                        tuneInsulinCurve: tuneInsulinCurve
                    )
                    debug(.openAPS, "AUTOTUNE PREP: \(autotunePreppedGlucose)")

                    let previousAutotune = self.storage.retrieve(Settings.autotune, as: RawJSON.self)

                    let autotuneResult = await self.autotuneRun(
                        autotunePreparedData: autotunePreppedGlucose,
                        previousAutotuneResult: previousAutotune ?? profile,
                        pumpProfile: pumpProfile
                    )

                    debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult)")

                    if let autotune = Autotune(from: autotuneResult) {
                        self.storage.save(autotuneResult, as: Settings.autotune)
                        promise(.success(autotune))
                    } else {
                        promise(.success(nil))
                    }

                    // Build the improved ISF schedule if the user has opted in.
                    let freeapsRaw = self.loadFileFromStorage(name: FreeAPS.settings)
                    if FreeAPSSettings(from: freeapsRaw)?.calculateISFSuggestions == true {
                        self.buildReasonsISFSchedule()
                    }
                }
            }
        }
    }

    func makeProfiles(useAutotune: Bool, settings: FreeAPSSettings) -> Future<Autotune?, Never> {
        Future { promise in
            debug(.openAPS, "Start makeProfiles")
            self.processQueue.async {
                Task {
                    let start = Date.now
                    var now = Date.now

                    let (
                        preferencesResult,
                        pumpSettings,
                        bgTargets,
                        basalProfile,
                        isf,
                        cr,
                        tempTargets,
                        model,
                        autotune,
                        freeaps
                    ) = await (
                        self.preferencesHistory(),
                        self.pumpSettingsHistory(),
                        self.bgTargetsHistory(),
                        self.basalProfileHistory(),
                        self.isfHistory(),
                        self.crHistory(),
                        self.tempTargetsHistory(),
                        self.modelHistory(),
                        self.autotuneHistory(useAutotune: useAutotune),
                        self.settingsHistory()
                    )
                    print("MakeProfiles: Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

                    let preferences = preferencesResult.isEmpty ? Preferences().rawJSON : preferencesResult
                    let preferencesData = Preferences(from: preferences)
                    let freeapsData = FreeAPSSettings(from: freeaps)

                    now = Date.now
                    let (
                        tdd,
                        dynamicVariables
                    ) = await (
                        self.tdd(preferencesData: preferencesData),
                        self.dynamicVariables(preferencesData, freeapsData)
                    )
                    print(
                        "Time for tdd and DynamicVariables \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                    )

                    if let insulin = tdd, insulin.hours > 0 {
                        CoreDataStorage().saveTDD(insulin)
                    }

                    now = Date.now
                    let (pumpProfile, profile) = await (
                        self.makeProfile(
                            preferences: preferences,
                            pumpSettings: pumpSettings,
                            bgTargets: bgTargets,
                            basalProfile: basalProfile,
                            isf: isf,
                            carbRatio: cr,
                            tempTargets: tempTargets,
                            model: model,
                            autotune: RawJSON.null,
                            freeaps: freeaps,
                            dynamicVariables: dynamicVariables,
                            settings: settings
                        ),
                        self.makeProfile(
                            preferences: preferences,
                            pumpSettings: pumpSettings,
                            bgTargets: bgTargets,
                            basalProfile: basalProfile,
                            isf: isf,
                            carbRatio: cr,
                            tempTargets: tempTargets,
                            model: model,
                            autotune: autotune.isEmpty ? .null : autotune,
                            freeaps: freeaps,
                            dynamicVariables: dynamicVariables,
                            settings: settings
                        )
                    )
                    print(
                        "MakeProfiles: Time for profile and pumpProfile \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                    )

                    now = Date.now
                    self.storage.save(pumpProfile, as: Settings.pumpProfile)
                    self.storage.save(profile, as: Settings.profile)

                    print(
                        "MakeProfiles: Time for save files \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                    )

                    if let tunedProfile = Autotune(from: profile) {
                        promise(.success(tunedProfile))
                        return
                    }

                    promise(.success(nil))
                }
            }
        }
    }

    // MARK: - Private

    private func aisfEnabled(override: Override?) -> Bool {
        guard let current = override, current.enabled else { return false }
        guard current.overrideAutoISF, let settings = OverrideStorage().fetchAutoISFsetting(id: current.id ?? ""),
              settings.autoisf else { return false }
        return true
    }

    private func notDisabled(override: Override?, settings: FreeAPSSettings) -> Bool {
        guard let current = override, current.enabled else { return true }
        guard current.overrideAutoISF, let settings = OverrideStorage().fetchAutoISFsetting(id: current.id ?? ""),
              !settings.autoisf else { return true }
        return false
    }

    private func pumpHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: OpenAPS.Monitor.pumpHistory)
    }

    private func carbHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Monitor.carbHistory)
    }

    private func glucoseHistory() async -> [BloodGlucose] {
        // TODO: not async
        glucoseStorage.retrieveFiltered()
    }

    private func preferencesHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.preferences)
    }

    private func basalHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.basalProfile)
    }

    private func dataHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: FreeAPS.settings)
    }

    private func autosensHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.autosense)
    }

    private func reservoirHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Monitor.reservoir)
    }

    private func profileHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.profile)
    }

    private func pumpSettingsHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.settings)
    }

    private func bgTargetsHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.bgTargets)
    }

    private func basalProfileHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.basalProfile)
    }

    private func isfHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.insulinSensitivities)
    }

    private func crHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.carbRatios)
    }

    private func tempTargetsHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.tempTargets)
    }

    private func modelHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: Settings.model)
    }

    private func autotuneHistory(useAutotune: Bool) async -> RawJSON {
        await useAutotune ? loadFileFromStorageAsync(name: Settings.autotune) : .empty
    }

    private func settingsHistory() async -> RawJSON {
        await loadFileFromStorageAsync(name: FreeAPS.settings)
    }

    private func reasons(
        reason: String,
        suggestion: Suggestion,
        preferences: Preferences?,
        profile: RawJSON,
        tdd: InsulinDistribution?,
        settings: FreeAPSSettings?,
        override: Override?
    ) -> String {
        var reasonString = reason
        let startIndex = reasonString.startIndex
        var aisf = false
        var totalDailyDose: Decimal?

        // Autosens.ratio / Dynamic Ratios
        if let isf = suggestion.sensitivityRatio {
            // TDD
            var tddString = ""
            if let tdd = tdd {
                let total = ((tdd.bolus ?? 0) as Decimal) + ((tdd.tempBasal ?? 0) as Decimal)
                totalDailyDose = total
                let round = round(Double(total * 10)) / 10
                let bolus = Int(((tdd.bolus ?? 0) as Decimal) * 100 / (total != 0 ? total : 1))
                tddString = ", Insulin 24h: \(round) U, \(bolus) % Bolus"
            }
            // Auto ISF
            if let freeAPSSettings = settings,
               (freeAPSSettings.autoisfEffective && notDisabled(override: override, settings: freeAPSSettings)) ||
               (aisfEnabled(override: override) && !freeAPSSettings.isNighttime)
            {
                let reasons = profile.autoISFreasons ?? ""
                // If disabled in middleware or Auto ISF layer
                if let disabled = readAndExclude(json: profile, variable: "autoisf", exclude: "autoisf_m"),
                   let value = Bool(disabled), !value
                {
                    reasonString.insert(
                        contentsOf: "Autosens Ratio: \(isf)" + tddString + ", \(reasons), ",
                        at: startIndex
                    )
                } else {
                    let insertedResons = "Auto ISF Ratio: \(isf)"
                    reasonString.insert(contentsOf: insertedResons + tddString + ", \(reasons), ", at: startIndex)
                }
                aisf = true
            } else if let pref = preferences {
                // Dynamic
                if pref.useNewFormula {
                    var insertedResons = "Dynamic Ratio: \(isf)"
                    if pref.sigmoid {
                        insertedResons += ", Sigmoid function"
                    } else {
                        insertedResons += ", Logarithmic function"
                    }
                    insertedResons += ", AF: \(pref.adjustmentFactor)"
                    if pref.enableDynamicCR {
                        insertedResons += ", Dynamic ISF/CR is: On/On"
                    } else {
                        insertedResons += ", Dynamic ISF/CR is: On/Off"
                    }

                    insertedResons += tddString + ", "

                    if let settings = settings, autoisfDisabledByNighttime(settings: settings) {
                        debugAutoISF(settings: settings)
                        insertedResons += "Auto ISF disabled during nighttime" + ", "
                    }

                    reasonString.insert(contentsOf: insertedResons, at: startIndex)
                } else {
                    // Autosens
                    var comment = ""
                    if let settings = settings, autoisfDisabledByNighttime(settings: settings) {
                        debugAutoISF(settings: settings)
                        comment = "Auto ISF disabled during nighttime" + ", "
                    }
                    reasonString.insert(contentsOf: "Autosens ratio: \(isf)" + tddString + ", " + comment, at: startIndex)
                }
            }

            // Include ISF before eventual adjustment
            if let old = readMiddleware(json: profile, variable: "old_isf"),
               let new = readReason(reason: reason, variable: "ISF"),
               let oldISF = trimmedIsEqual(string: old, decimal: new)
            {
                reasonString = reasonString.replacingOccurrences(of: "ISF:", with: "ISF: \(oldISF) →")
            }

            // Include CR before eventual adjustment
            if let old = readMiddleware(json: profile, variable: "old_cr"),
               let new = readReason(reason: reason, variable: "CR"),
               let oldCR = trimmedIsEqual(string: old, decimal: new)
            {
                reasonString = reasonString.replacingOccurrences(of: "CR:", with: "CR: \(oldCR) →")
            }

            // Before and after eventual Basal adjustment
            if let index = reasonString.firstIndex(of: ";"),
               let basalAdjustment = basalAdjustment(profile: profile, ratio: isf)
            {
                reasonString.insert(
                    contentsOf: basalAdjustment,
                    at: index
                )
            }
        }

        // Display either Target or Override (where target is included).
        let targetGlucose = suggestion.targetBG
        if targetGlucose != nil, let override = override, override.enabled {
            var orString = ", Override: "
            if override.percentage != 100 {
                orString += (formatter.string(from: override.percentage as NSNumber) ?? "")
            }
            if override.smbIsOff {
                orString += ". SMBs off"
            }
            orString += ". Target \(targetGlucose ?? 0)"

            if let index = reasonString.firstIndex(of: ";") {
                reasonString.insert(contentsOf: orString, at: index)
            }
        } else if let target = targetGlucose {
            if let index = reasonString.firstIndex(of: ";") {
                reasonString.insert(contentsOf: ", Target: \(target)", at: index)
            }
        }

        // SMB Delivery ratio
        if targetGlucose != nil, let smbRatio = readJSON(json: profile, variable: "smb_delivery_ratio"),
           let value = Decimal(string: smbRatio), value != 0.5
        {
            let index = reasonString.firstIndex(of: ";") ?? reasonString.index(reasonString.startIndex, offsetBy: 0)
            reasonString.insert(contentsOf: ", SMB Ratio: \(smbRatio)", at: index)
        }

        // Middleware
        if targetGlucose != nil, let middlewareString = readMiddleware(json: profile, variable: "mw"),
           middlewareString.count > 2
        {
            let index = reasonString.firstIndex(of: ";") ?? reasonString.index(reasonString.startIndex, offsetBy: 0)
            if middlewareString != "Nothing changed" {
                reasonString.insert(contentsOf: ", Middleware: \(middlewareString)", at: index)
            }
        }

        // Auto ISF additional comments
        if aisf {
            let index = reasonString.endIndex
            reasonString.insert(contentsOf: "\n\nAuto ISF { \(profile.autoISFstring ?? "") }", at: index)
        }

        // Save Suggestion to CoreData
        coredataContext.perform { [self] in
            if let isf = readReason(reason: reason, variable: "ISF"),
               let minPredBG = readReason(reason: reason, variable: "minPredBG"),
               let cr = readReason(reason: reason, variable: "CR"),
               let iob = suggestion.iob, let cob = suggestion.cob, let target = targetGlucose
            {
                var aisfReasons: String?
                if aisf {
                    // Save AISF output
                    aisfReasons = "\(profile.autoISFreasons ?? "")"
                }

                let saveSuggestion = Reasons(context: coredataContext)
                saveSuggestion.isf = isf as NSDecimalNumber
                saveSuggestion.cr = cr as NSDecimalNumber
                saveSuggestion.tdd = totalDailyDose as NSDecimalNumber?
                saveSuggestion.iob = iob as NSDecimalNumber
                saveSuggestion.iob = iob as NSDecimalNumber
                saveSuggestion.cob = cob as NSDecimalNumber
                saveSuggestion.target = target as NSDecimalNumber
                saveSuggestion.minPredBG = minPredBG as NSDecimalNumber
                saveSuggestion.eventualBG = Decimal(suggestion.eventualBG ?? 100) as NSDecimalNumber
                saveSuggestion.insulinReq = (suggestion.insulinReq ?? 0) as NSDecimalNumber
                saveSuggestion.smb = (suggestion.units ?? 0) as NSDecimalNumber
                saveSuggestion.reasons = aisfReasons
                saveSuggestion.glucose = (suggestion.bg ?? 0) as NSDecimalNumber
                saveSuggestion.ratio = (suggestion.sensitivityRatio ?? 1) as NSDecimalNumber

                if let override = override, override.enabled {
                    saveSuggestion.override = true
                }

                saveSuggestion.date = Date.now

                if let rate = suggestion.rate {
                    saveSuggestion.rate = rate as NSDecimalNumber
                } else if let rate = readRate(comment: suggestion.reason) {
                    saveSuggestion.rate = rate as NSDecimalNumber
                }

                if let units = readJSON(json: profile, variable: "out_units"), units.contains("mmol/L") {
                    saveSuggestion.mmol = true
                } else {
                    saveSuggestion.mmol = false
                }

                try? coredataContext.save()
            } else {
                debug(.dynamic, "Couldn't save suggestion to CoreData")
            }
        }
        return reasonString
    }

    private func autoisfDisabledByNighttime(settings: FreeAPSSettings) -> Bool {
        settings.autoisf && settings.isNighttime
    }

    private func debugAutoISF(settings: FreeAPSSettings) {
        debug(
            .openAPS,
            "Auto ISF disabled during nighttime \(settings.nightTime.startHour):\(settings.nightTime.startMinute) - \(settings.nightTime.endHour):\(settings.nightTime.endMinute) ."
        )
    }

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private func trimmedIsEqual(string: String, decimal: Decimal) -> String? {
        let old = string.replacingOccurrences(of: ": ", with: "").replacingOccurrences(of: "f", with: "")
        let new = "\(decimal)"
        guard old != new else { return nil }

        return old
    }

    private func basalAdjustment(profile: RawJSON, ratio: Decimal) -> String? {
        guard let new = readAndExclude(json: profile, variable: "current_basal", exclude: "current_basal_safety_multiplier"),
              let old = readJSON(json: profile, variable: "old_basal"), let value = Decimal(string: old),
              let parseNew = Decimal(string: new) else { return nil }

        let adjusted = (parseNew * ratio)
        let oldValue = value.roundBolusIncrements(increment: 0.05)
        let newValue = adjusted.roundBolusIncrements(increment: 0.05)
        guard oldValue != newValue else { return nil }

        return ", Basal: \(oldValue) → \(newValue)"
    }

    private func overrideBasal(alteredProfile: RawJSON, oref0Suggestion: Suggestion) -> Suggestion? {
        guard let changeRate = readJSON(json: alteredProfile, variable: "set_basal"), Bool(changeRate) ?? false,
              let basal_rate_is = readJSON(json: alteredProfile, variable: "basal_rate") else { return nil }

        var returnSuggestion = oref0Suggestion
        let basal_rate = Decimal(string: basal_rate_is) ?? 0

        returnSuggestion.rate = basal_rate
        returnSuggestion.duration = 30
        var reasonString = oref0Suggestion.reason
        let endIndex = reasonString.endIndex
        let insertedResons: String = reasonString + ". Basal Rate overridden to: \(basal_rate) U/h"
        reasonString.insert(contentsOf: insertedResons, at: endIndex)
        returnSuggestion.reason = reasonString

        return returnSuggestion
    }

    /// If iob is less than one hour of negative insulin and keto protection active, then enact a small keto protection basal rate
    private func aisfBasal(
        _ settings: FreeAPSSettings,
        _ basal: Decimal,
        oref0Suggestion: Suggestion
    ) -> Suggestion? {
        guard settings.closedLoop else {
            return nil
        }

        guard basal > 0 else {
            return nil
        }

        guard let pumpSettings = storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self) else {
            return nil
        }

        var rate = basal
        var factor: Decimal = 1

        if settings.variableKetoProtect {
            factor = min(
                Swift.max(settings.ketoProtectBasalPercent, 5),
                50 // protectBasal as percentage can be between 5 and 50%
            )
            rate *= (factor / 100)
        }
        if settings.ketoProtectAbsolut {
            // Protect Basal as absolute rate can be between 0 and 2 U/hr, but never more than max basal setting
            rate = min(Swift.max(settings.ketoProtectBasalAbsolut, 0), 2)
        }

        var returnSuggestion = oref0Suggestion
        returnSuggestion.rate = min(rate, pumpSettings.maxBasal)
        returnSuggestion.duration = 30

        var reasonString = oref0Suggestion.reason
        let endIndex = reasonString.endIndex
        let insertedResons: String = reasonString + "\n\nKeto Protection Basal Rate Set: \(rate) U/h"
        debug(.openAPS, "Auto ISF Keto Protection: Basal rate \(rate) U/h set for 30 minutes.")
        reasonString.insert(contentsOf: insertedResons, at: endIndex)
        returnSuggestion.reason = reasonString

        return returnSuggestion
    }

    private func readJSON(json: RawJSON, variable: String) -> String? {
        if let string = json.debugDescription.components(separatedBy: ",").filter({ $0.contains(variable) }).first {
            let targetComponents = string.components(separatedBy: ":")
            if targetComponents.count == 2 {
                let trimmedString = targetComponents[1].trimmingCharacters(in: .whitespaces)
                return trimmedString
            }
        }
        return nil
    }

    private func readAndExclude(json: RawJSON, variable: String, exclude: String) -> String? {
        if let string = json.debugDescription.components(separatedBy: ",")
            .filter({ $0.contains(variable) && !$0.contains(exclude) })
            .first
        {
            let targetComponents = string.components(separatedBy: ":")
            if targetComponents.count == 2 {
                let trimmedString = targetComponents[1].trimmingCharacters(in: .whitespaces)
                return trimmedString
            }
        }
        return nil
    }

    private func readReason(reason: String, variable: String) -> Decimal? {
        if let string = reason.components(separatedBy: ",").filter({ $0.contains(variable) }).first {
            let targetComponents = string.components(separatedBy: ":")
            if targetComponents.count == 2 {
                let trimmedString = targetComponents[1].trimmingCharacters(in: .whitespaces)
                let decimal = Decimal(string: trimmedString) ?? 0
                return decimal
            }
        }
        return nil
    }

    private func readRate(comment: String) -> Decimal? {
        if let string = comment.components(separatedBy: ", ").filter({ $0.contains("maxSafeBasal:") }).last {
            if let targetComponents = string.components(separatedBy: ":").last {
                let trimmedString = targetComponents.trimmingCharacters(in: .whitespaces)
                let decimal = Decimal(string: trimmedString) ?? 0
                return decimal
            }
        }
        return nil
    }

    private func readBasal(_ profile: String) -> Decimal? {
        if let string = profile.components(separatedBy: ",")
            .filter({ !$0.contains("current_basal_safety_multiplier") && $0.contains("current_basal") }).first
        {
            let targetComponents = string.components(separatedBy: ":")
            if targetComponents.count == 2 {
                let trimmedString = targetComponents[1].trimmingCharacters(in: .whitespaces)
                let decimal = Decimal(string: trimmedString) ?? 0
                return decimal
            }
        }
        return nil
    }

    private func readMiddleware(json: RawJSON, variable: String) -> String? {
        if let string = json.debugDescription.components(separatedBy: ",").filter({ $0.contains(variable) }).first {
            let trimmedString = string.suffix(max(string.count - 14, 0)).trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\n", with: "")
                .replacingOccurrences(of: "\\", with: "")
                .replacingOccurrences(of: "}", with: "")
                .replacingOccurrences(
                    of: "\"",
                    with: "",
                    options: NSString.CompareOptions.literal,
                    range: nil
                )
            return trimmedString
        }
        return nil
    }

    private func tdd(preferencesData: Preferences?) async -> (bolus: Decimal, basal: Decimal, hours: Double)? {
        let preferences = preferencesData
        guard let pumpData = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) else { return nil }

        let tdd = TotalDailyDose().totalDailyDose(pumpData, increment: Double(preferences?.bolusIncrement ?? 0.1))
        return tdd
    }

    func dynamicVariables(_ preferences: Preferences?, _: FreeAPSSettings?) async -> DynamicVariables {
        coredataContext.performAndWait {
            let start = Date.now
            var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
            let wp = preferences?.weightPercentage ?? 1
            let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30) as NSDecimalNumber
            let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30) as NSDecimalNumber

            let cd = CoreDataStorage()
            let os = OverrideStorage()

            var now = Date.now
            // TDD
            let uniqueEvents = cd.fetchTDD(interval: DateFilter().tenDays)
            print(
                "dynamicVariables: Time to fetch TDD \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
            )

            // Temp Targets using slider
            now = Date.now
            let sliderArray = cd.fetchTempTargetsSlider()
            print(
                "dynamicVariables: Time for fetchTempTargetsSlider \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
            )

            // Overrides
            now = Date.now
            let overrideArray = os.fetchNumberOfOverrides(numbers: 2)
            print(
                "dynamicVariables: Time for fetchNumberOfOverrides \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
            )

            // Temp Target
            now = Date.now
            let tempTargetsArray = cd.fetchTempTargets()
            print(
                "dynamicVariables: Time for fetchTempTargets \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
            )

            // Time adjusted average
            var time = uniqueEvents.first?.timestamp ?? .distantPast
            var data_ = [tddData(date: time, tdd: (uniqueEvents.first?.tdd ?? 0) as Decimal)]

            for a in uniqueEvents {
                if a.timestamp ?? .distantFuture <= time.addingTimeInterval(-24.hours.timeInterval) {
                    let b = tddData(
                        date: a.timestamp ?? .distantFuture,
                        tdd: (a.tdd ?? 0) as Decimal
                    )
                    data_.append(b)
                    time = a.timestamp ?? .distantPast
                }
            }
            let total = data_.map(\.tdd).reduce(0, +)
            let indeces = data_.count

            // Only fetch once. Use same (previous) fetch
            let twoHoursArray = uniqueEvents
                .filter({ ($0.timestamp ?? Date()) >= Date.now.addingTimeInterval(-2.hours.timeInterval) })
            var nrOfIndeces = twoHoursArray.count
            let totalAmount = twoHoursArray.compactMap({ each in each.tdd as? Decimal ?? 0 }).reduce(0, +)

            var temptargetActive = tempTargetsArray.first?.active ?? false
            let isPercentageEnabled = sliderArray.first?.enabled ?? false

            var useOverride = overrideArray.first?.enabled ?? false
            var overridePercentage = Decimal(overrideArray.first?.percentage ?? 100)
            var unlimited = overrideArray.first?.indefinite ?? true
            var disableSMBs = overrideArray.first?.smbIsOff ?? false
            let overrideMaxIOB = overrideArray.first?.overrideMaxIOB ?? false
            let maxIOB = overrideArray.first?.maxIOB ?? (preferences?.maxIOB ?? 0) as NSDecimalNumber

            var name = ""
            if useOverride, overrideArray.first?.isPreset ?? false, let overridePreset = os.isPresetName() {
                name = overridePreset
            }

            if nrOfIndeces == 0 {
                nrOfIndeces = 1
            }

            let average2hours = totalAmount / Decimal(nrOfIndeces)
            let average14 = total / Decimal(indeces)
            let weighted_average = wp * average2hours + (1 - wp) * average14

            var duration: Decimal = 0
            var overrideTarget: Decimal = 0

            if useOverride {
                duration = (overrideArray.first?.duration ?? 0) as Decimal
                overrideTarget = (overrideArray.first?.target ?? 0) as Decimal
                let addedMinutes = Int(duration)
                let date = overrideArray.first?.date ?? Date()
                if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(), !unlimited {
                    useOverride = false
                    if OverrideStorage().cancelProfile() != nil {
                        debug(.nightscout, "Override ended, duration: \(duration) minutes")
                    }
                }
                // End with new Meal, when applicable
                if useOverride, overrideArray.first?.advancedSettings ?? false, overrideArray.first?.endWIthNewCarbs ?? false,
                   let recent = cd.recentMeal(), !unchanged(meal: recent),
                   (recent.actualDate ?? .distantPast) > (overrideArray.first?.date ?? .distantFuture)
                {
                    useOverride = false
                    if OverrideStorage().cancelProfile() != nil {
                        debug(
                            .nightscout,
                            "Override ended, because of new carbs: \(recent.carbs) g, duration: \(duration) minutes"
                        )
                    }
                }

                // End with new glucose trending up, when applicable
                if useOverride, overrideArray.first?.glucoseOverrideThresholdActive ?? false, let g = cd.fetchRecentGlucose(),
                   Decimal(g.glucose) > ((overrideArray.first?.glucoseOverrideThreshold ?? 100) as NSDecimalNumber) as Decimal,
                   g.direction ?? BloodGlucose.Direction.fortyFiveDown.symbol == BloodGlucose.Direction.fortyFiveUp.symbol || g
                   .direction ?? BloodGlucose
                   .Direction.singleDown.symbol == BloodGlucose.Direction.singleUp.symbol || g.direction ?? BloodGlucose
                   .Direction.doubleDown.symbol == BloodGlucose.Direction.doubleUp.symbol
                {
                    useOverride = false
                    let storage = OverrideStorage()
                    if let duration = storage.cancelProfile() {
                        let last_ = storage.fetchLatestOverride().last
                        let name = storage.isPresetName()
                        if let last = last_ {
                            nightscout.editOverride(name ?? "", duration, last.date ?? Date.now)
                        }
                        debug(
                            .nightscout,
                            "Override ended, because of new glucose: \(g.glucose) mg/dl \(g.direction ?? "")"
                        )
                    }
                }

                // End with new glucose when lower than setting, when applicable
                if useOverride, overrideArray.first?.glucoseOverrideThresholdActiveDown ?? false, let g = cd.fetchRecentGlucose(),
                   Decimal(g.glucose) <
                   ((overrideArray.first?.glucoseOverrideThresholdDown ?? 90) as NSDecimalNumber) as Decimal
                {
                    useOverride = false
                    let storage = OverrideStorage()
                    if let duration = OverrideStorage().cancelProfile() {
                        let last_ = storage.fetchLatestOverride().last
                        let name = storage.isPresetName()
                        if let last = last_ {
                            nightscout.editOverride(name ?? "", duration, last.date ?? Date.now)
                        }
                        debug(
                            .nightscout,
                            "Override ended, because of new glucose: \(g.glucose) mg/dl \(g.direction ?? "")"
                        )
                    }
                }
            }

            if !useOverride {
                unlimited = true
                overridePercentage = 100
                duration = 0
                overrideTarget = 0
                disableSMBs = false
            }

            if temptargetActive {
                var duration_ = 0
                var hbt = Double(hbt_)
                var dd = 0.0

                if temptargetActive {
                    duration_ = Int(truncating: tempTargetsArray.first?.duration ?? 0)
                    hbt = tempTargetsArray.first?.hbt ?? Double(hbt_)
                    let startDate = tempTargetsArray.first?.startDate ?? Date()
                    let durationPlusStart = startDate.addingTimeInterval(duration_.minutes.timeInterval)
                    dd = durationPlusStart.timeIntervalSinceNow.minutes

                    if dd > 0.1 {
                        hbt_ = Decimal(hbt)
                        temptargetActive = true
                    } else {
                        temptargetActive = false
                    }
                }
            }

            // Auto ISF
            var autoISFsettings = AutoISFsettings()
            if useOverride, overrideArray.first?.overrideAutoISF ?? false,
               let fetched = OverrideStorage().fetchAutoISFsetting(id: overrideArray.first?.id ?? "Not This One")
            {
                autoISFsettings = AutoISFsettings(
                    autoisf: fetched.autoisf,
                    autocr: fetched.autocr,
                    smbDeliveryRatioBGrange: (fetched.smbDeliveryRatioBGrange ?? 0) as Decimal,
                    smbDeliveryRatioMin: (fetched.smbDeliveryRatioMin ?? 0) as Decimal,
                    smbDeliveryRatioMax: (fetched.smbDeliveryRatioMax ?? 0) as Decimal,
                    autoISFhourlyChange: (fetched.autoISFhourlyChange ?? 0) as Decimal,
                    higherISFrangeWeight: (fetched.higherISFrangeWeight ?? 0) as Decimal,
                    lowerISFrangeWeight: (fetched.lowerISFrangeWeight ?? 0) as Decimal,
                    postMealISFweight: (fetched.postMealISFweight ?? 0) as Decimal,
                    enableBGacceleration: fetched.enableBGacceleration,
                    bgAccelISFweight: (fetched.bgAccelISFweight ?? 0) as Decimal,
                    bgBrakeISFweight: (fetched.bgBrakeISFweight ?? 0) as Decimal,
                    iobThresholdPercent: (fetched.iobThresholdPercent ?? 0) as Decimal,
                    autoisf_max: (fetched.autoisf_max ?? 0) as Decimal,
                    autoisf_min: (fetched.autoisf_min ?? 0) as Decimal,
                    use_B30: fetched.use_B30,
                    iTime_Start_Bolus: (fetched.iTime_Start_Bolus ?? 1.5) as Decimal,
                    b30targetLevel: (fetched.b30targetLevel ?? 80) as Decimal,
                    b30upperLimit: (fetched.b30upperLimit ?? 140) as Decimal,
                    b30upperdelta: (fetched.b30upperdelta ?? 8) as Decimal,
                    b30factor: (fetched.b30factor ?? 5) as Decimal,
                    b30_duration: (fetched.b30_duration ?? 30) as Decimal,
                    ketoProtect: fetched.ketoProtect,
                    variableKetoProtect: fetched.variableKetoProtect,
                    ketoProtectBasalPercent: (fetched.ketoProtectBasalPercent ?? 0) as Decimal,
                    ketoProtectAbsolut: fetched.ketoProtectAbsolut,
                    ketoProtectBasalAbsolut: (fetched.ketoProtectBasalAbsolut ?? 0.2) as Decimal,
                    id: fetched.id ?? "",
                    nightTime: fetched.nightTime?.value ?? .default
                )
            }

            let averages = DynamicVariables(
                average_total_data: average14,
                weightedAverage: weighted_average,
                weigthPercentage: wp,
                past2hoursAverage: average2hours,
                date: Date(),
                isEnabled: temptargetActive,
                presetActive: isPercentageEnabled,
                overridePercentage: overridePercentage,
                useOverride: useOverride,
                duration: duration,
                unlimited: unlimited,
                hbt: hbt_,
                overrideTarget: overrideTarget,
                smbIsOff: disableSMBs,
                advancedSettings: overrideArray.first?.advancedSettings ?? false,
                isfAndCr: overrideArray.first?.isfAndCr ?? false,
                isf: overrideArray.first?.isf ?? true,
                cr: overrideArray.first?.cr ?? true,
                basal: overrideArray.first?.basal ?? true,
                smbIsAlwaysOff: overrideArray.first?.smbIsAlwaysOff ?? false,
                start: (overrideArray.first?.start ?? 0) as Decimal,
                end: (overrideArray.first?.end ?? 0) as Decimal,
                smbMinutes: (overrideArray.first?.smbMinutes ?? smbMinutes) as Decimal,
                uamMinutes: (overrideArray.first?.uamMinutes ?? uamMinutes) as Decimal,
                maxIOB: maxIOB as Decimal,
                overrideMaxIOB: overrideMaxIOB,
                preset: name,
                autoISFoverrides: autoISFsettings,
                aisfOverridden: useOverride && (overrideArray.first?.overrideAutoISF ?? false)
            )
            self.storage.save(averages, as: OpenAPS.Monitor.dynamicVariables)
            return averages
        }
    }

    private func unchanged(meal: Meals) -> Bool {
        meal.carbs <= 0 && meal.fat <= 0 && meal.protein <= 0
    }

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) async -> RawJSON {
        // dispatchPrecondition(condition: .onQueue(processQueue))
        await scriptExecutor.call(name: OpenAPS.Prepare.iob, with: [
            pumphistory,
            profile,
            clock,
            autosens
        ])
    }

    func iobSync() async -> RawJSON {
        let (
            autosens,
            profile,
            pumpHistory
        ) = await (
            autosensHistory(),
            profileHistory(),
            pumpHistory()
        )

        return await scriptExecutor.call(name: OpenAPS.Prepare.iob, with: [
            pumpHistory,
            profile,
            Date(),
            autosens
        ])
    }

    private func meal(
        pumphistory: JSON,
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: JSON,
        glucose: JSON,
        temporary: TemporaryData
    ) async -> RawJSON {
        await scriptExecutor.call(name: OpenAPS.Prepare.meal, with: [
            pumphistory,
            profile,
            clock,
            glucose,
            basalProfile,
            carbs,
            temporary.forBolusView
        ])
    }

    private func autotunePrepare(
        pumphistory: JSON,
        profile: JSON,
        glucose: JSON,
        pumpprofile: JSON,
        carbs: JSON,
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool
    ) async -> RawJSON {
        // dispatchPrecondition(condition: .onQueue(processQueue))
        await scriptExecutor.call(name: OpenAPS.Prepare.autotunePrep, with: [
            pumphistory,
            profile,
            glucose,
            pumpprofile,
            carbs,
            categorizeUamAsBasal,
            tuneInsulinCurve
        ])
    }

    private func autotuneRun(
        autotunePreparedData: JSON,
        previousAutotuneResult: JSON,
        pumpProfile: JSON
    ) async -> RawJSON {
        // dispatchPrecondition(condition: .onQueue(processQueue))
        await scriptExecutor.call(name: OpenAPS.Prepare.autotuneCore, with: [
            autotunePreparedData,
            previousAutotuneResult,
            pumpProfile
        ])
    }

    private func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        pumpHistory: JSON
    ) async -> RawJSON {
        // dispatchPrecondition(condition: .onQueue(processQueue))

        await scriptExecutor.call(
            name: OpenAPS.Prepare.determineBasal,
            with: [
                iob,
                currentTemp,
                glucose,
                profile,
                autosens,
                meal,
                microBolusAllowed,
                reservoir,
                Date(),
                pumpHistory
            ]
        )
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) async -> RawJSON {
        // dispatchPrecondition(condition: .onQueue(processQueue))
        await scriptExecutor.call(
            name: OpenAPS.Prepare.autosens,
            with: [
                glucose,
                pumpHistory,
                basalprofile,
                profile,
                carbs,
                temptargets
            ]
        )
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
        autotune: JSON,
        freeaps: JSON,
        dynamicVariables: DynamicVariables,
        settings: JSON
    ) async -> RawJSON {
        // dispatchPrecondition(condition: .onQueue(processQueue))
        await scriptExecutor.call(
            name: OpenAPS.Prepare.profile,
            with: [
                pumpSettings,
                bgTargets,
                isf,
                basalProfile,
                preferences,
                carbRatio,
                tempTargets,
                model,
                autotune,
                freeaps,
                dynamicVariables,
                settings
            ]
        )
    }

    private func middleware(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON
    ) async -> RawJSON {
        // dispatchPrecondition(condition: .onQueue(processQueue))

        let script = middlewareScript(name: OpenAPS.Middleware.determineBasal)

        return await scriptExecutor.call(
            name: OpenAPS.Prepare.string,
            with: [
                "middleware",
                iob,
                currentTemp,
                glucose,
                profile,
                autosens,
                meal,
                microBolusAllowed,
                reservoir,
                Date()
            ],
            withBody: script?.body ?? ""
        )
    }

    private func autosisf(
        glucose: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        pumpHistory: JSON
    ) async -> RawJSON {
        await scriptExecutor.call(
            name: OpenAPS.AutoISF.autoisf,
            with: [
                iob,
                profile,
                autosens,
                glucose,
                Date(),
                pumpHistory
            ]
        )
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    private func saveAsync(_ file: JSON, name: String) async {
        storage.save(file, as: name)
    }

    private func loadFileFromStorageAsync(name: String) async -> RawJSON {
        let data = await storage.retrieveRawAsync(name)
        return data ?? OpenAPS.defaults(for: name)
    }

    private func middlewareScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: "Middleware", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "Middleware", body: try! String(contentsOf: url))
        }

        return nil
    }

    static func defaults(for file: String) -> RawJSON {
        let prefix = file.hasSuffix(".json") ? "json/defaults" : "javascript"
        guard let url = Foundation.Bundle.main.url(forResource: "\(prefix)/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }

    // MARK: - Calculated ISF Schedule

    /// Builds a per-hour median ISF schedule from CoreData Reasons entries using the
    /// improved algorithm: back-calculates isf_before = isf × ratio for every entry
    /// (no near-basal filter), applies a global p5/p95 trim, then buckets by hour.
    ///
    /// Uses a 21-day window to match the web ISF Profiler. Requires at least 12 hours
    /// with ≥ 3 direct data points each before the schedule is considered reliable.
    @discardableResult
    func buildReasonsISFSchedule() -> ReasonsISFSchedule? {
        let cutoff = Date().addingTimeInterval(-21 * 24 * 3600) as NSDate
        let reasons = CoreDataStorage().fetchReasons(interval: cutoff)

        guard !reasons.isEmpty else {
            debug(.openAPS, "Calculated ISF: no Reasons data available")
            return nil
        }

        // Back-calculate isf_before = applied_isf × sensitivity_ratio for every entry.
        // This recovers the profile (or autosens-adjusted) ISF before any dynamic scaling,
        // which is the quantity we want regardless of how aggressively AutoISF was working.
        var allEstimates: [(value: Double, hour: Int, date: Date)] = []

        for r in reasons {
            guard
                let isfDecimal = r.isf?.decimalValue, isfDecimal > 0,
                let ratioDecimal = r.ratio?.decimalValue, ratioDecimal > 0,
                let date = r.date
            else { continue }

            let isfBefore = isfDecimal * ratioDecimal
            if isfBefore <= 0 { continue }

            let hour = Calendar.current.component(.hour, from: date)
            allEstimates.append((value: Double(truncating: isfBefore as NSDecimalNumber), hour: hour, date: date))
        }

        guard !allEstimates.isEmpty else {
            debug(.openAPS, "Calculated ISF: no valid estimates after back-calculation")
            return nil
        }

        let totalEntries = allEstimates.count
        let fromDate = allEstimates.map(\.date).min() ?? cutoff as Date
        let toDate = allEstimates.map(\.date).max() ?? Date()

        // Count distinct calendar days represented.
        let calendar = Calendar.current
        let daysAnalyzed = Set(allEstimates.map { calendar.startOfDay(for: $0.date) }).count

        // Global p5/p95 trim — eliminates extreme outliers without filtering by ratio.
        let sorted = allEstimates.map(\.value).sorted()
        let n = sorted.count
        let p5Index  = Int((Double(n - 1) * 0.05).rounded())
        let p95Index = Int((Double(n - 1) * 0.95).rounded())
        let p5  = sorted[p5Index]
        let p95 = sorted[p95Index]

        var hourBuckets: [Int: [Double]] = [:]
        for e in allEstimates {
            guard e.value >= p5, e.value <= p95 else { continue }
            hourBuckets[e.hour, default: []].append(e.value)
        }

        let qualifyingEntries = hourBuckets.values.reduce(0) { $0 + $1.count }

        // Per-hour median (minimum 3 points for a direct measurement).
        var hourMedians: [Int: Double] = [:]
        var counts: [String: Int] = [:]

        for hour in 0 ..< 24 {
            let pts = hourBuckets[hour] ?? []
            counts[String(hour)] = pts.count
            if pts.count >= 3 {
                let s = pts.sorted()
                hourMedians[hour] = s[s.count / 2]
            }
        }

        // Require at least 12 hours with direct measurements.
        guard hourMedians.count >= 12 else {
            debug(.openAPS, "Calculated ISF: only \(hourMedians.count) hours have ≥ 3 data points (need 12)")
            return nil
        }

        // Interpolate hours with insufficient data from the nearest measured neighbour.
        var schedule: [String: Double] = [:]
        for (hour, median) in hourMedians {
            schedule[String(hour)] = median
        }
        for hour in 0 ..< 24 {
            guard schedule[String(hour)] == nil else { continue }
            for offset in 1 ..< 12 {
                if let v = schedule[String((hour - offset + 24) % 24)] { schedule[String(hour)] = v; break }
                if let v = schedule[String((hour + offset) % 24)]      { schedule[String(hour)] = v; break }
            }
        }

        // Overall median from directly-measured hours only.
        let measuredMedians = (0 ..< 24)
            .filter { (counts[String($0)] ?? 0) >= 3 }
            .compactMap { schedule[String($0)] }
            .sorted()
        let overallMedian = measuredMedians[measuredMedians.count / 2]

        // MARK: - Deviation analysis
        // Sort by date ascending and compute per-entry BG delta from consecutive readings.
        // deviation = actual_delta - expectedBGI, where expectedBGI = -IOB × isf_before × (elapsed/60).
        // Positive deviation → BG dropped less than expected → profile ISF is too high → suggest lower ISF.
        let sortedReasons = reasons.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        var devHourBuckets: [Int: [(isfBefore: Double, deviation: Double, absExpBGI: Double)]] = [:]
        var devQualifyingEntries = 0

        for i in 1 ..< sortedReasons.count {
            let prev = sortedReasons[i - 1]
            let curr = sortedReasons[i]

            guard
                let prevDate = prev.date,
                let currDate = curr.date,
                let currGlucoseDecimal = curr.glucose?.decimalValue,
                let prevGlucoseDecimal = prev.glucose?.decimalValue,
                let iobDecimal = curr.iob?.decimalValue,
                let isfDecimal = curr.isf?.decimalValue, isfDecimal > 0,
                let ratioDecimal = curr.ratio?.decimalValue, ratioDecimal > 0,
                let cobDecimal = curr.cob?.decimalValue
            else { continue }

            let elapsedMin = currDate.timeIntervalSince(prevDate) / 60.0
            guard elapsedMin >= 3, elapsedMin <= 10 else { continue }

            let iob = Double(truncating: iobDecimal as NSDecimalNumber)
            guard iob > 0 else { continue }

            let cob = Double(truncating: cobDecimal as NSDecimalNumber)
            guard cob <= 5 else { continue }

            let isfBefore = Double(truncating: (isfDecimal * ratioDecimal) as NSDecimalNumber)
            guard isfBefore > 0 else { continue }

            let delta = Double(truncating: currGlucoseDecimal as NSDecimalNumber)
                - Double(truncating: prevGlucoseDecimal as NSDecimalNumber)
            let expectedBGI = -iob * isfBefore * (elapsedMin / 60.0)
            guard abs(expectedBGI) > 0.5 else { continue }

            let deviation = delta - expectedBGI
            let hour = Calendar.current.component(.hour, from: currDate)
            devHourBuckets[hour, default: []].append((isfBefore, deviation, abs(expectedBGI)))
            devQualifyingEntries += 1
        }

        // Per-hour: median deviation → adjustment fraction → suggested ISF.
        var suggestedDirect: [String: Double] = [:]
        for (hour, entries) in devHourBuckets {
            guard entries.count >= 5 else { continue }

            let deviations  = entries.map(\.deviation).sorted()
            let expBGIs     = entries.map(\.absExpBGI).sorted()
            let isfBefores  = entries.map(\.isfBefore).sorted()

            let medDev      = deviations[deviations.count / 2]
            let medExpBGI   = expBGIs[expBGIs.count / 2]
            let medISFBefore = isfBefores[isfBefores.count / 2]

            guard medExpBGI > 0.5 else { continue }

            var adjFraction = medDev / medExpBGI
            adjFraction = max(-0.20, min(0.20, adjFraction))

            suggestedDirect[String(hour)] = medISFBefore * (1.0 - adjFraction)
        }

        // Interpolate suggested hours from nearest neighbour (require ≥6 directly-computed hours).
        var suggestedSchedule: [String: Double]? = nil
        if suggestedDirect.count >= 6 {
            var interpolated = suggestedDirect
            for hour in 0 ..< 24 {
                guard interpolated[String(hour)] == nil else { continue }
                for offset in 1 ..< 12 {
                    if let v = interpolated[String((hour - offset + 24) % 24)] { interpolated[String(hour)] = v; break }
                    if let v = interpolated[String((hour + offset) % 24)]      { interpolated[String(hour)] = v; break }
                }
            }
            suggestedSchedule = interpolated
        }

        let suggestedMeasured = suggestedDirect.values.sorted()
        let overallSuggestedMedian: Double? = suggestedMeasured.isEmpty
            ? nil
            : suggestedMeasured[suggestedMeasured.count / 2]

        let result = ReasonsISFSchedule(
            hours: schedule,
            counts: counts,
            overallMedian: overallMedian,
            generatedAt: Date(),
            daysAnalyzed: daysAnalyzed,
            totalEntries: totalEntries,
            qualifyingEntries: qualifyingEntries,
            fromDate: fromDate,
            toDate: toDate,
            suggestedHours: suggestedSchedule,
            overallSuggestedMedian: overallSuggestedMedian,
            devQualifyingEntries: devQualifyingEntries
        )

        storage.save(result, as: Settings.reasonsISFSchedule)
        debug(.openAPS, "Calculated ISF: built schedule from \(totalEntries) entries (\(daysAnalyzed) days); median \(String(format: "%.1f", overallMedian)) mg/dL/U; deviation entries \(devQualifyingEntries), suggested hours \(suggestedDirect.count)")
        return result
    }
}
