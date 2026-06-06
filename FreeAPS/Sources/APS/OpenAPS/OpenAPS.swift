import CoreData
import Foundation
import JavaScriptCore
import Swinject

final class OpenAPS {
    private let storage: FileStorage
    private let glucoseStorage: GlucoseStorage
    private let nightscout: NightscoutManager
    private let pumpStorage: PumpHistoryStorage
    private let settingsManager: SettingsManager
    private let appCoordinator: AppCoordinator

    private let coreDataStorage = CoreDataStorage()
    private let overrideStorage = OverrideStorage()

    private let scriptExecutor = WebViewScriptExecutor()

    init(
        storage: FileStorage,
        glucoseStorage: GlucoseStorage,
        nightscout: NightscoutManager,
        pumpStorage: PumpHistoryStorage,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.glucoseStorage = glucoseStorage
        self.nightscout = nightscout
        self.pumpStorage = pumpStorage
        self.settingsManager = settingsManager
        self.appCoordinator = appCoordinator
    }

    func determineBasal(
        currentTemp: TempBasal,
        clock: Date = Date(),
        temporaryCarbs: CarbsEntry?,
        override: Override?
    ) async -> Suggestion? {
        // For debugging
        let start = Date.now
        var now = Date.now

        debug(.openAPS, "Start determineBasal")
        await storage.save(clock, as: Monitor.clock)
        let tempBasal = currentTemp.rawJSON
        await storage.save(tempBasal, as: Monitor.tempBasal)

        let pumpHistory = await self.pumpHistory()
        let carbs = await carbHistory()
        let glucose = await glucoseHistory()
        let preferences = await settingsManager.preferences
        let basalProfile = await basalHistory()
        let settings = await settingsManager.settings
        let autosens = await autosensHistory()
        let reservoir = await reservoirHistory()
        let storedProfile = await profileHistory()

        var profile = storedProfile
        print("Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

        now = Date.now
        let tdd = coreDataStorage.fetchInsulinDistribution().first
        print("Time for tdd \(-1 * now.timeIntervalSinceNow) seconds")

        now = Date.now
        let meal = await self.meal(
            pumphistory: pumpHistory,
            profile: storedProfile,
            basalProfile: basalProfile,
            clock: clock,
            carbs: carbs,
            glucose: glucose,
            temporaryCarbs: temporaryCarbs ?? RawJSON.null
        )
        let iob = await self.iob(
            pumphistory: pumpHistory,
            profile: storedProfile,
            clock: clock,
            autosens: autosens.isEmpty ? .null : autosens
        )

        await storage.save(meal, as: Monitor.meal)
        await storage.save(iob, as: Monitor.iob)

        if let iobEntries = IOBTick0.parseArrayFromJSON(from: iob) {
            _ = coreDataStorage.saveInsulinData(iobEntries: iobEntries)
        }

        print(
            "Time for Meal and IOB module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // The Middleware layer.
        now = Date.now
        let alteredProfile = await middleware(
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
        if (settings.autoisfEffective && notDisabled(override: override, settings: settings)) ||
            (aisfEnabled(override: override) && !settings.isNighttime)
        {
            now = Date.now
            profile = await autosisf(
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
        let suggested = await determineBasal(
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
            if settings.autoisfEffective, let iob = suggestion.iob {
                // If IOB < one hour of negative insulin and keto protection is active, then enact a small keto protection basal rate
                if settings.ketoProtect, iob < 0,
                   let rate = suggestion.rate, rate <= 0,
                   let basal = readBasal(alteredProfile), iob < -basal, (suggestion.units ?? 0) <= 0,
                   let basalRate = await aisfBasal(settings, basal, oref0Suggestion: suggestion)
                {
                    suggestion = basalRate
                }
            }

            // Process any eventual middleware/B30 basal rate
            if let newSuggestion = overrideBasal(alteredProfile: profile, oref0Suggestion: suggestion) {
                suggestion = newSuggestion
            }
            // Add reasons, when needed
            suggestion.reason = await reasons(
                reason: suggestion.reason,
                suggestion: suggestion,
                preferences: preferences,
                profile: profile,
                tdd: tdd,
                settings: settings,
                override: override
            )
            // Update time
            suggestion.timestamp = suggestion.deliverAt ?? clock
            // Save
            await storage.save(suggestion, as: Enact.suggested)

            return suggestion
        } else {
            return nil
        }
    }

    func autosense() async -> Autosens? {
        debug(.openAPS, "Start autosens")
        let pumpHistory = await loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
        let carbs = await loadFileFromStorage(name: Monitor.carbHistory)
        let glucose = await glucoseStorage.retrieveFiltered()
        let profile = await loadFileFromStorage(name: Settings.profile)
        let basalProfile = await loadFileFromStorage(name: Settings.basalProfile)
        let tempTargets = await loadFileFromStorage(name: Settings.tempTargets)

        let autosensResult = await autosense(
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
            await storage.save(autosens, as: Settings.autosense)
            return autosens
        } else {
            return nil
        }
    }

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) async -> Autotune? {
        debug(.openAPS, "Start autotune")
        let pumpHistory = await loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
        let glucose = await glucoseStorage.retrieveFiltered()
        let profile = await loadFileFromStorage(name: Settings.profile)
        let pumpProfile = await loadFileFromStorage(name: Settings.pumpProfile)
        let carbs = await loadFileFromStorage(name: Monitor.carbHistory)

        let autotunePreppedGlucose = await autotunePrepare(
            pumphistory: pumpHistory,
            profile: profile,
            glucose: glucose,
            pumpprofile: pumpProfile,
            carbs: carbs,
            categorizeUamAsBasal: categorizeUamAsBasal,
            tuneInsulinCurve: tuneInsulinCurve
        )
        debug(.openAPS, "AUTOTUNE PREP: \(autotunePreppedGlucose)")

        let previousAutotune = await storage.retrieve(Settings.autotune, as: RawJSON.self)

        let autotuneResult = await autotuneRun(
            autotunePreparedData: autotunePreppedGlucose,
            previousAutotuneResult: previousAutotune ?? profile,
            pumpProfile: pumpProfile
        )

        debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult)")

        if let autotune = Autotune(from: autotuneResult) {
            await storage.save(autotuneResult, as: Settings.autotune)
            return autotune
        } else {
            return nil
        }
    }

    func makeProfiles(useAutotune: Bool, settings: FreeAPSSettings) async -> Autotune? {
        debug(.openAPS, "Start makeProfiles")
        let start = Date.now
        var now = Date.now

        let preferences = await settingsManager.preferences
        let pumpSettings = await settingsManager.pumpSettings
        let bgTargets = await bgTargetsHistory()
        let basalProfile = await basalProfileHistory()
        let isf = await isfHistory()
        let cr = await crHistory()
        let tempTargets = await tempTargetsHistory()
        let model = await modelHistory()
        let autotune = await autotuneHistory(useAutotune: useAutotune)

        print("MakeProfiles: Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

        now = Date.now

        let tdd = await self.tdd(preferencesData: preferences)
        let dynamicVariables = await self.dynamicVariables(preferences)

        print(
            "Time for tdd and DynamicVariables \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        if let insulin = tdd, insulin.hours > 0 {
            coreDataStorage.saveTDD(insulin)
        }

        now = Date.now
        let pumpProfile = await makeProfile(
            preferences: preferences,
            pumpSettings: pumpSettings,
            bgTargets: bgTargets,
            basalProfile: basalProfile,
            isf: isf,
            carbRatio: cr,
            tempTargets: tempTargets,
            model: model,
            autotune: RawJSON.null,
            freeaps: settings,
            dynamicVariables: dynamicVariables,
            settings: settings
        )
        let profile = await makeProfile(
            preferences: preferences,
            pumpSettings: pumpSettings,
            bgTargets: bgTargets,
            basalProfile: basalProfile,
            isf: isf,
            carbRatio: cr,
            tempTargets: tempTargets,
            model: model,
            autotune: autotune.isEmpty ? .null : autotune,
            freeaps: settings,
            dynamicVariables: dynamicVariables,
            settings: settings
        )

        print(
            "MakeProfiles: Time for profile and pumpProfile \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        now = Date.now
        await storage.save(pumpProfile, as: Settings.pumpProfile)
        await storage.save(profile, as: Settings.profile)

        print(
            "MakeProfiles: Time for save files \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        if let tunedProfile = Autotune(from: profile) {
            return tunedProfile
        }

        return nil
    }

    // MARK: - Private

    private func aisfEnabled(override: Override?) -> Bool {
        guard let current = override, current.enabled else { return false }
        guard current.overrideAutoISF, let settings = overrideStorage.fetchAutoISFsetting(id: current.id ?? ""),
              settings.autoisf else { return false }
        return true
    }

    private func notDisabled(override: Override?, settings: FreeAPSSettings) -> Bool {
        guard let current = override, current.enabled else { return true }
        guard current.overrideAutoISF,
              !settings.autoisf,
              let settings = overrideStorage.fetchAutoISFsetting(id: current.id ?? "")
        else { return true }
        return false
    }

    private func pumpHistory() async -> RawJSON {
        await loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
    }

    private func carbHistory() async -> RawJSON {
        await loadFileFromStorage(name: Monitor.carbHistory)
    }

    private func glucoseHistory() async -> [BloodGlucose] {
        await glucoseStorage.retrieveFiltered()
    }

//    private func preferencesHistory() async -> RawJSON {
//        await loadFileFromStorageAsync(name: Settings.preferences)
//    }

    private func basalHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.basalProfile)
    }

//    private func dataHistory() async -> RawJSON {
//        await loadFileFromStorageAsync(name: FreeAPS.settings)
//    }

    private func autosensHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.autosense)
    }

    private func reservoirHistory() async -> RawJSON {
        let reservoir = appCoordinator.pumpReservoir.value ?? 100.0
        return "\(reservoir)"
//        await loadFileFromStorageAsync(name: Monitor.reservoir)
    }

    private func profileHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.profile)
    }

//    private func pumpSettingsHistory() async -> RawJSON {
//        await loadFileFromStorageAsync(name: Settings.settings)
//    }

    private func bgTargetsHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.bgTargets)
    }

    private func basalProfileHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.basalProfile)
    }

    private func isfHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.insulinSensitivities)
    }

    private func crHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.carbRatios)
    }

    private func tempTargetsHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.tempTargets)
    }

    private func modelHistory() async -> RawJSON {
        await loadFileFromStorage(name: Settings.model)
    }

    private func autotuneHistory(useAutotune: Bool) async -> RawJSON {
        await useAutotune ? loadFileFromStorage(name: Settings.autotune) : .empty
    }

//    private func settingsHistory() async -> RawJSON {
//        await loadFileFromStorageAsync(name: FreeAPS.settings)
//    }

    private func reasons(
        reason: String,
        suggestion: Suggestion,
        preferences: Preferences?,
        profile: RawJSON,
        tdd: InsulinDistribution?,
        settings: FreeAPSSettings?,
        override: Override?
    ) async -> String {
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
        if let isf = readReason(reason: reason, variable: "ISF"),
           let minPredBG = readReason(reason: reason, variable: "minPredBG"),
           let cr = readReason(reason: reason, variable: "CR"),
           let iob = suggestion.iob, let cob = suggestion.cob, let target = targetGlucose
        {
            let aisfReasons: String? = aisf ? "\(profile.autoISFreasons ?? "")" : nil

            let rateToSave: Decimal? = suggestion.rate ?? readRate(comment: suggestion.reason)

            let mmolToSave = readJSON(json: profile, variable: "out_units")?.contains("mmol/L") ?? false

            let overrideToSave = override?.enabled ?? false

            let context = CoreDataStack.shared.persistentContainer.newBackgroundContext()

            let tddToSave = totalDailyDose

            await context.perform {
                let saveSuggestion = Reasons(context: context)
                saveSuggestion.isf = isf as NSDecimalNumber
                saveSuggestion.cr = cr as NSDecimalNumber
                saveSuggestion.tdd = tddToSave as NSDecimalNumber?
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

                saveSuggestion.override = overrideToSave

                saveSuggestion.date = Date.now

                if let r = rateToSave {
                    saveSuggestion.rate = r as NSDecimalNumber
                }

                saveSuggestion.mmol = mmolToSave

                try? context.save()
            }

        } else {
            debug(.dynamic, "Couldn't save suggestion to CoreData")
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
    ) async -> Suggestion? {
        guard settings.closedLoop else {
            return nil
        }

        guard basal > 0 else {
            return nil
        }

        let pumpSettings = await settingsManager.pumpSettings

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
        guard let pumpData = await storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) else { return nil }

        let tdd = TotalDailyDose().totalDailyDose(pumpData, increment: Double(preferences?.bolusIncrement ?? 0.1))
        return tdd
    }

    func dynamicVariables(_ preferences: Preferences?) async -> DynamicVariables {
        // TODO: calls to coreDataStorage / overrideStorage run on main thread which is bad
        // TODO: calls to nightscout should not be part of this!
        let start = Date.now
        var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
        let wp = preferences?.weightPercentage ?? 1
        let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30) as NSDecimalNumber
        let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30) as NSDecimalNumber

        var now = Date.now
        // TDD
        let uniqueEvents = coreDataStorage.fetchTDD(interval: DateFilter.tenDays.startDate)
        print(
            "dynamicVariables: Time to fetch TDD \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Temp Targets using slider
        now = Date.now
        let sliderArray = coreDataStorage.fetchTempTargetsSlider()
        print(
            "dynamicVariables: Time for fetchTempTargetsSlider \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Overrides
        now = Date.now
        let overrideArray = overrideStorage.fetchNumberOfOverrides(numbers: 2)
        print(
            "dynamicVariables: Time for fetchNumberOfOverrides \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Temp Target
        now = Date.now
        let tempTargetsArray = coreDataStorage.fetchTempTargets()
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
        if useOverride, overrideArray.first?.isPreset ?? false,
           let overridePreset = overrideStorage.isPresetName()
        {
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
                if overrideStorage.cancelProfile() != nil {
                    debug(.nightscout, "Override ended, duration: \(duration) minutes")
                }
            }
            // End with new Meal, when applicable
            if useOverride, overrideArray.first?.advancedSettings ?? false, overrideArray.first?.endWIthNewCarbs ?? false,
               let recent = coreDataStorage.recentMeal(), !self.unchanged(meal: recent),
               (recent.actualDate ?? .distantPast) > (overrideArray.first?.date ?? .distantFuture)
            {
                useOverride = false
                if overrideStorage.cancelProfile() != nil {
                    debug(
                        .nightscout,
                        "Override ended, because of new carbs: \(recent.carbs) g, duration: \(duration) minutes"
                    )
                }
            }

            // End with new glucose trending up, when applicable
            if useOverride,
               overrideArray.first?.glucoseOverrideThresholdActive ?? false,
               let g = coreDataStorage.fetchRecentGlucose(),
               Decimal(g.glucose) > ((overrideArray.first?.glucoseOverrideThreshold ?? 100) as NSDecimalNumber) as Decimal,
               g.direction ?? BloodGlucose.Direction.fortyFiveDown.symbol == BloodGlucose.Direction.fortyFiveUp.symbol || g
               .direction ?? BloodGlucose
               .Direction.singleDown.symbol == BloodGlucose.Direction.singleUp.symbol || g.direction ?? BloodGlucose
               .Direction.doubleDown.symbol == BloodGlucose.Direction.doubleUp.symbol
            {
                useOverride = false
                if let duration = overrideStorage.cancelProfile() {
                    let last_ = overrideStorage.fetchLatestOverride().last
                    let name = overrideStorage.isPresetName()
                    if let last = last_ {
                        await nightscout.editOverride(name ?? "", duration, last.date ?? Date.now)
                    }
                    debug(
                        .nightscout,
                        "Override ended, because of new glucose: \(g.glucose) mg/dl \(g.direction ?? "")"
                    )
                }
            }

            // End with new glucose when lower than setting, when applicable
            if useOverride,
               overrideArray.first?.glucoseOverrideThresholdActiveDown ?? false,
               let g = coreDataStorage.fetchRecentGlucose(),
               Decimal(g.glucose) <
               ((overrideArray.first?.glucoseOverrideThresholdDown ?? 90) as NSDecimalNumber) as Decimal
            {
                useOverride = false
                if let duration = overrideStorage.cancelProfile() {
                    let last_ = overrideStorage.fetchLatestOverride().last
                    let name = overrideStorage.isPresetName()
                    if let last = last_ {
                        await nightscout.editOverride(name ?? "", duration, last.date ?? Date.now)
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
           let fetched = overrideStorage.fetchAutoISFsetting(id: overrideArray.first?.id ?? "Not This One")
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

        await storage.save(averages, as: OpenAPS.Monitor.dynamicVariables)
        return averages
    }

    private func unchanged(meal: Meals) -> Bool {
        let hasMicros = (meal.micronutrient as? Set<Micronutrient>)?.contains { ($0.amount?.decimalValue ?? 0) > 0 } ?? false

        return (meal.carbs?.decimalValue ?? 0) <= 0 &&
            (meal.fat?.decimalValue ?? 0) <= 0 &&
            (meal.protein?.decimalValue ?? 0) <= 0 &&
            !hasMicros
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
        temporaryCarbs: JSON
    ) async -> RawJSON {
        // TODO: in prepare-meal - account for temporaryCarbs==null case
        await scriptExecutor.call(name: OpenAPS.Prepare.meal, with: [
            pumphistory,
            profile,
            clock,
            glucose,
            basalProfile,
            carbs,
            temporaryCarbs
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

        let script = await middlewareScript(name: OpenAPS.Middleware.determineBasal)

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

    private func loadFileFromStorage(name: String) async -> RawJSON {
        await storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    private func middlewareScript(name: String) async -> Script? {
        if let body = await storage.retrieveRaw(name) {
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
}
