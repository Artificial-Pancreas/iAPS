import Combine
import CoreData
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let scriptExecutor: WebViewScriptExecutor
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)
    private let storage: FileStorage
    private let nightscout: NightscoutManager
    private let pumpStorage: PumpHistoryStorage

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    init(
        storage: FileStorage,
        nightscout: NightscoutManager,
        pumpStorage: PumpHistoryStorage,
        scriptExecutor: WebViewScriptExecutor
    ) {
        self.storage = storage
        self.nightscout = nightscout
        self.pumpStorage = pumpStorage
        self.scriptExecutor = scriptExecutor
    }

    func determineBasal(currentTemp: TempBasal, clock: Date = Date(), temporary: TemporaryData) -> Future<Suggestion?, Error> {
        Future { promise in
            self.processQueue.async {
                Task {
                    do {
                        // For debugging
                        let start = Date.now
                        var now = Date.now

                        debug(.openAPS, "Start determineBasal")
                        self.storage.save(clock, as: Monitor.clock)
                        let tempBasal = currentTemp
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
                            storedProfile,
                            pumpSettings
                        ) = try await (
                            self.readPumpHistory(),
                            self.readCarbHistory(),
                            self.readGlucoseHistory(),
                            self.readPreferences(),
                            self.readBasalSchedule(),
                            self.readSettings(),
                            self.readAutosens(),
                            self.readReservoir(),
                            self.readProfile(),
                            self.readPumpSettings()
                        )

                        let preferencesData = preferences
                        let settings = data
                        var profile = storedProfile
                        print("Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

                        now = Date.now
                        let tdd = CoreDataStorage()
                            .fetchInsulinDistribution().first
                        print("Time for tdd \(-1 * now.timeIntervalSinceNow) seconds")

                        now = Date.now
                        let (meal, iob) = try await (self.meal(
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
                            autosens: autosens
                        ))

                        self.storage.save(meal, as: Monitor.meal)
                        self.storage.save(iob, as: Monitor.iob)

                        let cd = CoreDataStorage()
                        _ = cd.saveInsulinData(iobEntries: iob)

                        print(
                            "Time for Meal and IOB module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                        )
                        // The Middleware layer.
                        now = Date.now
                        let alteredProfile = try await self.middleware(
                            glucose: glucose,
                            currentTemp: tempBasal,
                            iob: iob,
                            profile: profile,
                            autosens: autosens,
                            meal: meal,
                            microBolusAllowed: true,
                            reservoir: reservoir
                        )

                        now = Date.now
                        // Auto ISF Layer
                        let freeAPSSettings = settings
                        if freeAPSSettings.autoisf {
                            now = Date.now
                            profile = try await self.autosisf(
                                glucose: glucose,
                                iob: iob,
                                profile: alteredProfile,
                                autosens: autosens,
                                pumpHistory: pumpHistory,
                                clock: clock
                            )
                            print(
                                "Time for AutoISF module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                            )
                        } else { profile = alteredProfile }

                        now = Date.now
                        // The OpenAPS layer
                        let suggested = try await self.determineBasal(
                            glucose: glucose,
                            currentTemp: tempBasal,
                            iob: iob,
                            profile: profile,
                            autosens: autosens,
                            meal: meal,
                            microBolusAllowed: true,
                            reservoir: reservoir,
                            pumpHistory: pumpHistory, // TODO: not used
                            clock: clock
                        )
                        print(
                            "Time for Determine Basal module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
                        )
                        debug(.openAPS, "SUGGESTED: \(suggested.rawJSON())")

                        // Update Suggestion, when applicable (middleware / dynamic ISF / Auto ISF)
                        var suggestion = suggested
                        //            if var suggestion = suggested {
                        now = Date.now

                        // Auto ISF
                        let mySettings = settings
                        if mySettings.autoisf, let iob = suggestion.iob {
                            // If IOB < one hour of negative insulin and keto protection is active, then enact a small keto protection basal rate
                            let basal = Decimal(profile.currentBasal)
                            if mySettings.ketoProtect, iob < 0,
                               let rate = suggestion.rate, rate <= 0,
                               iob < -basal, (suggestion.units ?? 0) <= 0,
                               let basalRate = self.aisfBasal(
                                   mySettings,
                                   basal,
                                   pumpSettings: pumpSettings,
                                   oref0Suggestion: suggestion
                               )
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
                            settings: settings
                        )
                        // Update time
                        suggestion.timestamp = suggestion.deliverAt ?? clock
                        // Save
                        self.storage.save(suggestion, as: Enact.suggested)

                        promise(.success(suggestion))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
        }
    }

    func autosens() -> Future<Autosens?, Error> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autosens")
                Task {
                    do {
                        let (
                            pumpHistory,
                            carbs,
                            glucose,
                            profile,
                            basalProfile,
                            tempTargets
                        ) = try await (
                            self.readPumpHistory(),
                            self.readCarbHistory(),
                            self.readGlucoseHistory(),
                            self.readProfile(),
                            self.readBasalSchedule(),
                            self.readTempTargets()
                        )

                        let autosensResult = try await self.autosens(
                            glucose: glucose,
                            pumpHistory: pumpHistory,
                            basalprofile: basalProfile,
                            profile: profile,
                            carbs: carbs,
                            temptargets: tempTargets
                        )

                        debug(.openAPS, "AUTOSENS: \(autosensResult)")
                        var autosens = autosensResult
                        autosens.timestamp = Date()
                        self.storage.save(autosens, as: Settings.autosense)
                        promise(.success(autosens))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
        }
    }

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) -> Future<Autotune?, Error> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autotune")
                Task {
                    do {
                        let (
                            pumpHistory,
                            carbs,
                            glucose,
                            profile,
                            pumpProfile
                        ) = try await (
                            self.readPumpHistory(),
                            self.readCarbHistory(),
                            self.readGlucoseHistory(),
                            self.readProfile(),
                            self.readPumpProfile()
                        )

                        let previousAutotune = try await self.readAutotuneAsProfile(useAutotune: true)

                        let autotuneResult = try await self.autotuneFull(
                            pumphistory: pumpHistory,
                            profile: profile,
                            glucose: glucose,
                            pumpprofile: pumpProfile,
                            carbs: carbs,
                            categorizeUamAsBasal: categorizeUamAsBasal,
                            tuneInsulinCurve: tuneInsulinCurve,
                            previousAutotuneResult: previousAutotune ?? profile,
                        )

                        debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult.rawJSON())")

                        let autotune = Autotune.from(profile: autotuneResult)
                        self.storage.save(autotuneResult, as: Settings.autotune)
                        promise(.success(autotune))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
        }
    }

    // TODO: settings is passed as an argument, but also is fetched from storage below
    func makeProfiles(useAutotune: Bool, settings: FreeAPSSettings) -> Future<Profile?, Error> {
        Future { promise in
            debug(.openAPS, "Start makeProfiles")
            self.processQueue.async {
                Task {
                    do {
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
                        ) = try await (
                            self.readPreferences(),
                            self.readPumpSettings(),
                            self.bgTargetsHistory(),
                            self.readBasalSchedule(),
                            self.readIsfSchedule(),
                            self.readCrSchedule(),
                            self.readTempTargets(),
                            self.readModel(),
                            self.readAutotune(useAutotune: useAutotune),
                            self.readSettings()
                        )
                        print("MakeProfiles: Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

                        let preferences = preferencesResult ?? Preferences()
                        let preferencesData = preferences
                        let freeapsData = freeaps

                        now = Date.now
                        let (
                            tdd,
                            dynamicVariables
                        ) = try await (
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
                        let (pumpProfile, profile) = try await (
                            self.makeProfileAsync(
                                preferences: preferences,
                                pumpSettings: pumpSettings,
                                bgTargets: bgTargets,
                                basalProfile: basalProfile,
                                isf: isf,
                                carbRatio: cr,
                                tempTargets: tempTargets,
                                model: model,
                                autotune: nil,
                                freeaps: freeaps,
                                dynamicVariables: dynamicVariables,
                                settings: settings
                            ),
                            self.makeProfileAsync(
                                preferences: preferences,
                                pumpSettings: pumpSettings,
                                bgTargets: bgTargets,
                                basalProfile: basalProfile,
                                isf: isf,
                                carbRatio: cr,
                                tempTargets: tempTargets,
                                model: model,
                                autotune: autotune,
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

                        promise(.success(profile))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func readPumpHistory() async throws -> [PumpHistoryEvent] {
        try await loadFileFromStorageAsync(name: OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)
    }

    private func readCarbHistory() async throws -> [CarbsEntry] {
        try await loadFileFromStorageAsync(name: Monitor.carbHistory, as: [CarbsEntry].self)
    }

    private func readGlucoseHistory() async throws -> [GlucoseEntry0] {
        let glucose = try await loadFileFromStorageAsync(name: Monitor.glucose, as: [BloodGlucose].self)
        return glucose.map { g in
            GlucoseEntry0(
                date: nil,
                displayTime: nil,
                dateString: g.dateString.ISO8601Format(),
                sgv: g.sgv,
                glucose: g.glucose,
                type: g.type,
                noise: g.noise,
            )
        }
    }

    private func readPreferences() async throws -> Preferences? {
        try await loadFileFromStorageAsyncOpt(name: Settings.preferences, as: Preferences.self)
    }

    private func readBasalSchedule() async throws -> [BasalProfileEntry] {
        try await loadFileFromStorageAsync(name: Settings.basalProfile, as: [BasalProfileEntry].self)
    }

    private func readSettings() async throws -> FreeAPSSettings {
        try await loadFileFromStorageAsync(name: FreeAPS.settings, as: FreeAPSSettings.self)
    }

    private func readAutosens() async throws -> Autosens? {
        try await loadFileFromStorageAsyncOpt(name: Settings.autosense, as: Autosens.self)
    }

    private func readReservoir() async throws -> Double {
        try await loadFileFromStorageAsync(name: Monitor.reservoir, as: Double.self)
    }

    private func readProfile() async throws -> Profile {
        try await loadFileFromStorageAsync(name: Settings.profile, as: Profile.self)
    }

    private func readPumpProfile() async throws -> Profile {
        try await loadFileFromStorageAsync(name: Settings.pumpProfile, as: Profile.self)
    }

    private func readPumpSettings() async throws -> PumpSettings {
        try await loadFileFromStorageAsync(name: Settings.settings, as: PumpSettings.self)
    }

    private func bgTargetsHistory() async throws -> BGTargets {
        try await loadFileFromStorageAsync(name: Settings.bgTargets, as: BGTargets.self)
    }

    private func readIsfSchedule() async throws -> InsulinSensitivities {
        try await loadFileFromStorageAsync(name: Settings.insulinSensitivities, as: InsulinSensitivities.self)
    }

    private func readCrSchedule() async throws -> CarbRatios {
        try await loadFileFromStorageAsync(name: Settings.carbRatios, as: CarbRatios.self)
    }

    private func readTempTargets() async throws -> [TempTarget] {
        try await loadFileFromStorageAsync(name: Settings.tempTargets, as: [TempTarget].self)
    }

    private func readModel() async throws -> String {
        try await loadFileFromStorageAsync(name: Settings.model, as: String.self)
    }

    private func readAutotune(useAutotune: Bool) async throws -> Autotune? {
        useAutotune ? try await loadFileFromStorageAsyncOpt(name: Settings.autotune, as: Autotune.self) : nil
    }

    private func readAutotuneAsProfile(useAutotune: Bool) async throws -> Profile? {
        useAutotune ? try await loadFileFromStorageAsyncOpt(name: Settings.autotune, as: Profile.self) : nil
    }

    private func reasons(
        reason: String,
        suggestion: Suggestion,
        preferences: Preferences?,
        profile: Profile,
        tdd: InsulinDistribution?,
        settings: FreeAPSSettings?
    ) -> String {
        var reasonString = reason
        let startIndex = reasonString.startIndex
        var aisf = false
        var totalDailyDose: Decimal?
        let or = OverrideStorage().fetchLatestOverride().first

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
            if let freeAPSSettings = settings, freeAPSSettings.autoisf {
                let reasons = profile.autoISFReasons ?? ""
                // If disabled in middleware or Auto ISF layer
                if !profile.iaps.autoisf
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
            } else if let settings = preferences {
                // Dynamic
                if settings.useNewFormula {
                    var insertedResons = "Dynamic Ratio: \(isf)"
                    if settings.sigmoid {
                        insertedResons += ", Sigmoid function"
                    } else {
                        insertedResons += ", Logarithmic function"
                    }
                    insertedResons += ", AF: \(settings.adjustmentFactor)"
                    if settings.enableDynamicCR {
                        insertedResons += ", Dynamic ISF/CR is: On/On"
                    } else {
                        insertedResons += ", Dynamic ISF/CR is: On/Off"
                    }
                    insertedResons += tddString + ", "
                    reasonString.insert(contentsOf: insertedResons, at: startIndex)
                } else {
                    // Autosens
                    reasonString.insert(contentsOf: "Autosens ratio: \(isf)" + tddString + ", ", at: startIndex)
                }
            }

            // Include ISF before eventual adjustment
            if let old = profile.oldISF,
               let new = readReason(reason: reason, variable: "ISF"),
               let oldISF = trimmedIsEqual(string: "\(old)", decimal: new)
            {
                reasonString = reasonString.replacingOccurrences(of: "ISF:", with: "ISF: \(oldISF) →")
            }

            // Include CR before eventual adjustment
            if let old = profile.oldCR,
               let new = readReason(reason: reason, variable: "CR"),
               let oldCR = trimmedIsEqual(string: "\(old)", decimal: new)
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
        if targetGlucose != nil, let override = or, override.enabled {
            var orString = ", Override:"
            if override.percentage != 100 {
                orString += " \(override.percentage.formatted()) %"
            }
            if override.smbIsOff {
                orString += " SMBs off"
            }
            orString += " Target \(targetGlucose ?? 0)"

            if let index = reasonString.firstIndex(of: ";") {
                reasonString.insert(contentsOf: orString, at: index)
            }
        } else if let target = targetGlucose {
            if let index = reasonString.firstIndex(of: ";") {
                reasonString.insert(contentsOf: ", Target: \(target)", at: index)
            }
        }

        // SMB Delivery ratio
        if targetGlucose != nil, profile.smbDeliveryRatio != 0.5
        {
            let index = reasonString.firstIndex(of: ";") ?? reasonString.index(reasonString.startIndex, offsetBy: 0)
            reasonString.insert(contentsOf: ", SMB Ratio: \(profile.smbDeliveryRatio)", at: index)
        }

        // Middleware
        if let mw = profile.mw, mw != "Nothing changed"
        {
            let index = reasonString.firstIndex(of: ";") ?? reasonString.index(reasonString.startIndex, offsetBy: 0)
            reasonString.insert(contentsOf: ", Middleware: \(mw)", at: index)
        }

        // Auto ISF additional comments
        if aisf {
            let index = reasonString.endIndex
            reasonString.insert(contentsOf: "\n\nAuto ISF { \(profile.autoISFString ?? "") }", at: index)
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
                    aisfReasons = "\(profile.autoISFReasons ?? "")"
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

                if let override = or, override.enabled {
                    saveSuggestion.override = true
                }

                saveSuggestion.date = Date.now

                if let rate = suggestion.rate {
                    saveSuggestion.rate = rate as NSDecimalNumber
                } else if let rate = readRate(comment: suggestion.reason) {
                    saveSuggestion.rate = rate as NSDecimalNumber
                }

                if profile.outUnits == GlucoseUnits.mmolL {
                    saveSuggestion.mmol = true
                } else {
                    saveSuggestion.mmol = false
                }

                do {
                    try coredataContext.save()
                } catch {
                    debug(.dynamic, "Couldn't save suggestion to CoreData: \(error.localizedDescription)")
                }
            } else {
                debug(.dynamic, "not persisting the suggestion (missing data)")
            }
        }
        return reasonString
    }

    private func trimmedIsEqual(string: String, decimal: Decimal) -> String? {
        let old = string.replacingOccurrences(of: ": ", with: "").replacingOccurrences(of: "f", with: "")
        let new = "\(decimal)"
        guard old != new else { return nil }

        return old
    }

    private func overrideBasal(
        alteredProfile: Profile,
        oref0Suggestion: Suggestion
    ) -> Suggestion? {
        guard alteredProfile.setBasal ?? false,
              let basal_rate_is = alteredProfile.basalRate
        else { return nil }

        var returnSuggestion = oref0Suggestion
        let basal_rate = Decimal(basal_rate_is)

        returnSuggestion.rate = basal_rate
        returnSuggestion.duration = 30
        var reasonString = oref0Suggestion.reason
        let endIndex = reasonString.endIndex
        let insertedResons: String = reasonString + ". Basal Rate overridden to: \(basal_rate) U/h"
        reasonString.insert(contentsOf: insertedResons, at: endIndex)
        returnSuggestion.reason = reasonString

        return returnSuggestion
    }

    private func basalAdjustment(profile: Profile, ratio: Decimal) -> String? {
        let new = Decimal(profile.currentBasal)
        guard let old = profile.old_basal else { return nil }

        let adjusted = (new * ratio)
        let oldValue = Decimal(old).roundBolusIncrements(increment: 0.05)
        let newValue = adjusted.roundBolusIncrements(increment: 0.05)
        guard oldValue != newValue else { return nil }

        return ", Basal \(oldValue) → \(newValue)"
    }

    /// If iob is less than one hour of negative insulin and keto protection active, then enact a small keto protection basal rate
    private func aisfBasal(
        _ settings: FreeAPSSettings,
        _ basal: Decimal,
        pumpSettings: PumpSettings,
        oref0Suggestion: Suggestion
    ) -> Suggestion? {
        guard settings.closedLoop else {
            return nil
        }

        guard basal > 0 else {
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

    // TODO: this looks the same as readReason above
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

    private func tdd(preferencesData: Preferences?) async throws -> (bolus: Decimal, basal: Decimal, hours: Double)? {
        let preferences = preferencesData
        let pumpData = try await readPumpHistory()

        let tdd = TotalDailyDose().totalDailyDose(pumpData, increment: Double(preferences?.bolusIncrement ?? 0.1))
        return tdd
    }

    func dynamicVariables(_ preferences: Preferences?, _ settingsData: FreeAPSSettings?) async throws -> DynamicVariables {
        let averages = coredataContext.performAndWait {
            let start = Date.now
            var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
            let wp = preferences?.weightPercentage ?? 1
            let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30) as NSDecimalNumber
            let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30) as NSDecimalNumber
            let disableCGMError = settingsData?.disableCGMError ?? true

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
                    id: fetched.id ?? ""
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
                disableCGMError: disableCGMError,
                preset: name,
                autoISFoverrides: autoISFsettings,
                aisfOverridden: useOverride && (overrideArray.first?.overrideAutoISF ?? false)
            )
            return averages
        }
        storage.save(averages, as: OpenAPS.Monitor.dynamicVariables)
        return averages
    }

    private func unchanged(meal: Meals) -> Bool {
        meal.carbs <= 0 && meal.fat <= 0 && meal.protein <= 0
    }

    private func iob(
        pumphistory: [PumpHistoryEvent],
        profile: Profile,
        clock: Date,
        autosens: Autosens?
    ) async throws -> [IOBItem] {
        try await scriptExecutor.callNew(
            function: "iob",
            with: IobInput(
                pump_history: pumphistory,
                profile: profile,
                clock: clock,
                autosens: autosens,
            ),
            as: [IOBItem].self
        )
    }

    func iobSync(
        clock: Date,
    ) async throws -> [IOBItem] {
        let (
            autosens,
            profile,
            pumpHistory
        ) = try await (
            readAutosens(),
            readProfile(),
            readPumpHistory()
        )

        return try await scriptExecutor.callNew(
            function: "iob",
            with: IobInput(
                pump_history: pumpHistory,
                profile: profile,
                clock: clock,
                autosens: autosens
            ),
            as: [IOBItem].self
        )
    }

    private func meal(
        pumphistory: [PumpHistoryEvent],
        profile: Profile,
        basalProfile: [BasalProfileEntry],
        clock: Date,
        carbs: [CarbsEntry],
        glucose: [GlucoseEntry0],
        temporary: TemporaryData
    ) async throws -> RecentCarbs {
        try await scriptExecutor.callNew(
            function: "meal",
            with: MealInput(
                pump_history: pumphistory,
                profile: profile,
                basal_profile: basalProfile,
                clock: clock,
                carbs: carbs,
                glucose: glucose,
                for_bolus_view: temporary.forBolusView
            ),
            as: RecentCarbs.self
        )
    }

    private func autotuneFull(
        pumphistory: [PumpHistoryEvent],
        profile: Profile,
        glucose: [GlucoseEntry0],
        pumpprofile: Profile,
        carbs: [CarbsEntry],
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool,
        previousAutotuneResult: Profile
    ) async throws -> Profile {
        try await scriptExecutor.callNew(
            function: "autotune",
            with: AutotuneInput(
                pump_history: pumphistory,
                profile: profile,
                glucose: glucose,
                pump_profile: pumpprofile,
                carbs: carbs,
                categorize_uam_as_basal: categorizeUamAsBasal,
                tune_insulin_curve: tuneInsulinCurve,
                previous_autotune_result: previousAutotuneResult
            ),
            as: Profile.self
        )
    }

    private func determineBasal(
        glucose: [GlucoseEntry0],
        currentTemp: TempBasal,
        iob: [IOBItem],
        profile: Profile,
        autosens: Autosens?,
        meal: RecentCarbs,
        microBolusAllowed: Bool,
        reservoir: Double,
        pumpHistory: [PumpHistoryEvent], // TODO: pumpHistory not used in prepare
        clock: Date
    ) async throws -> Suggestion {
        try await scriptExecutor.callNew(
            function: "determine_basal",
            with: DetermineBasalInput(
                glucose: glucose,
                current_temp: currentTemp,
                iob: iob,
                profile: profile,
                autosens: autosens,
                meal: meal,
                microbolus_allowed: microBolusAllowed,
                reservoir: reservoir,
                pump_history: pumpHistory,
                clock: clock
            ),
            as: Suggestion.self
        )
    }

    private func autosens(
        glucose: [GlucoseEntry0],
        pumpHistory: [PumpHistoryEvent],
        basalprofile: [BasalProfileEntry],
        profile: Profile,
        carbs: [CarbsEntry],
        temptargets: [TempTarget]
    ) async throws -> Autosens {
        try await scriptExecutor.callNew(
            function: "autosens",
            with: AutosensInput(
                glucose: glucose,
                pump_history: pumpHistory,
                basal_profile: basalprofile,
                profile: profile,
                carbs: carbs,
                temp_targets: temptargets
            ),
            as: Autosens.self
        )
    }

    private func makeProfileAsync(
        preferences: Preferences,
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        isf: InsulinSensitivities,
        carbRatio: CarbRatios,
        tempTargets: [TempTarget],
        model: String,
        autotune: Autotune?,
        freeaps: FreeAPSSettings,
        dynamicVariables: DynamicVariables,
        settings: FreeAPSSettings
    ) async throws -> Profile {
        let clock = Date.now
        let profile = try await scriptExecutor.callNew(
            function: "profile",
            with: PrepareProfileInput(
                preferences: preferences,
                pump_settings: pumpSettings,
                bg_targets: bgTargets,
                basal_profile: basalProfile,
                isf: isf,
                carb_ratio: carbRatio,
                temp_targets: tempTargets,
                model: model,
                autotune: autotune,
                freeaps: freeaps,
                dynamic_variables: dynamicVariables,
                settings: settings,
                clock: clock
            ),
            as: Profile.self
        )

        return profile
    }

    private func middleware(
        glucose: [GlucoseEntry0],
        currentTemp: TempBasal,
        iob: [IOBItem],
        profile: Profile,
        autosens: Autosens?,
        meal: RecentCarbs,
        microBolusAllowed: Bool, // not passed to the middleware function
        reservoir: Double
    ) async throws -> Profile {
        guard let script = try await middlewareScript(name: OpenAPS.Middleware.determineBasal)?.body else {
            return profile
        }
        return try await scriptExecutor.callNew(
            function: "middleware",
            with: MiddlewareInput(
                middleware_fn: script,
                glucose: glucose,
                current_temp: currentTemp,
                iob: iob,
                profile: profile,
                autosens: autosens,
                meal: meal,
                microbolus_allowed: microBolusAllowed,
                reservoir: reservoir,
                clock: Date.now
            ),
            as: Profile.self
        )
    }

    private func autosisf(
        glucose: [GlucoseEntry0],
        iob: [IOBItem],
        profile: Profile,
        autosens: Autosens?,
        pumpHistory: [PumpHistoryEvent],
        clock: Date
    ) async throws -> Profile {
        try await scriptExecutor.callNew(
            function: "autoisf",
            with: AutoIsfInput(
                glucose: glucose,
                iob: iob,
                profile: profile,
                autosens: autosens,
                pump_history: pumpHistory,
                clock: clock,
            ),
            as: Profile.self
        )
    }

    private func loadFileFromStorageAsync<T: Decodable>(name: String, as _: T.Type) async throws -> T {
        let raw = await storage.retrieveRawAsync(name) ?? OpenAPS.defaults(for: name)

        do {
            return try T.decodeFrom(json: raw)
        } catch {
            print("failed to decode \(name)")
            throw error
        }
    }

    private func loadFileFromStorageAsyncOpt<T: Decodable>(name: String, as _: T.Type) async throws -> T? {
        let raw = await storage.retrieveRawAsync(name) ?? OpenAPS.defaults(for: name)

        if raw == "" {
            return nil
        }
        do {
            return try T.decodeFrom(json: raw)
        } catch {
            print("failed to decode \(name)")
            throw error
        }
    }

    private func middlewareScript(name: String) async throws -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: "Middleware", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "Middleware", body: try! String(contentsOf: url))
        }

        return nil
    }

    static func defaults(for file: String) -> String {
        let prefix = file.hasSuffix(".json") ? "json/defaults" : "javascript"
        guard let url = Foundation.Bundle.main.url(forResource: "\(prefix)/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }
}
