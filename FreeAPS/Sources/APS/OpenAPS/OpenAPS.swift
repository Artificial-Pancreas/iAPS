import CoreData
import Foundation
import JavaScriptCore
import Swinject

actor OpenAPS: Sendable {
    private let storage: FileStorage
    private let glucoseStorage: GlucoseStorage
    private let pumpStorage: PumpHistoryStorage
    private let settingsManager: SettingsManager
    private let appCoordinator: AppCoordinator

    private let scriptExecutor = WebViewScriptExecutor()

    init(
        storage: FileStorage,
        glucoseStorage: GlucoseStorage,
        pumpStorage: PumpHistoryStorage,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.glucoseStorage = glucoseStorage
        self.pumpStorage = pumpStorage
        self.settingsManager = settingsManager
        self.appCoordinator = appCoordinator
    }

    /// override - current active (enabled=true) override
    func determineBasal(
        profile: Profile,
        autosens: Autosens?,
        currentTemp: TempBasal,
        clock: Date = Date(),
        temporaryCarbs: CarbsEntry?,
        override: OverrideSnapshot?,
        tdd: InsulinDistributionSnapshot? // TODO: this one is only here to put into the "reasons"
    ) async throws -> Suggestion {
        // For debugging
        let start = Date.now
        var now = Date.now

        debug(.openAPS, "Start determineBasal")
        await storage.save(clock, as: Monitor.clock)

        let pumpHistory = appCoordinator.pumpHistory.value
        let carbs = appCoordinator.carbHistory.value
        let glucose = readGlucoseHistory()
        let preferences = appCoordinator.preferences.value
        let basalProfile = appCoordinator.basalProfile.value
        let settings = appCoordinator.settings.value
        let pumpSettings = appCoordinator.pumpSettings.value
        let reservoir = readReservoir()

        var profile = profile
        print("Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

        now = Date.now
        let meal = try await self.meal(
            pumphistory: pumpHistory,
            profile: profile,
            basalProfile: basalProfile,
            clock: clock,
            carbs: carbs,
            glucose: glucose,
            temporaryCarbs: temporaryCarbs
        )
        let iob = try await self.iob(
            pumpHistory: pumpHistory,
            profile: profile,
            clock: clock,
            autosens: autosens
        )

        await storage.save(meal, as: Monitor.meal)
        await storage.save(iob, as: Monitor.iob)

        print(
            "Time for Meal and IOB module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // The Middleware layer.
        now = Date.now
        let alteredProfile = try await middleware(
            glucose: glucose,
            currentTemp: currentTemp,
            iob: iob,
            profile: profile,
            autosens: autosens,
            meal: meal,
            microBolusAllowed: true,
            reservoir: reservoir
        )

        // Auto ISF Layer
        let aisfOverride = aisfOverrideSetting(override: override)
        var aisfDisabledByNightTime = false
        var aisfActive = ((settings.autoisf && aisfOverride ?? true) || (aisfOverride ?? false))
        if aisfActive {
            if settings.isNighttime {
                aisfDisabledByNightTime = true
                aisfActive = false
            }
        }

        if aisfActive {
            now = Date.now
            profile = try await autosisf(
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
        let suggested = try await determineBasal(
            glucose: glucose,
            currentTemp: currentTemp,
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
        now = Date.now

        // Auto ISF
        if aisfActive, settings.ketoProtect {
            // If IOB < one hour of negative insulin and keto protection is active, then enact a small keto protection basal rate
            let basal = Decimal(alteredProfile.currentBasal)
            if let iob = suggestion.iob,
               iob < -basal,
               let rate = suggestion.rate,
               rate <= 0,
               (suggestion.units ?? 0) <= 0,
               let basalRate = aisfBasal(settings: settings, pumpSettings: pumpSettings, basal, oref0Suggestion: suggestion)
            {
                suggestion = basalRate
            }
        }

        // Process any eventual middleware/B30 basal rate
        if let newSuggestion = overrideBasal(alteredProfile: profile, oref0Suggestion: suggestion) {
            suggestion = newSuggestion
        }
        // Add reasons and other fields, when needed
        updateSuggestion(
            suggestion: &suggestion,
            preferences: preferences,
            profile: profile,
            currentTemp: currentTemp,
            tdd: tdd,
            settings: settings,
            override: override,
            aisfActive: aisfActive,
            aisfDisabledByNightTime: aisfDisabledByNightTime
        )
        // Update time
        suggestion.timestamp = suggestion.deliverAt ?? clock

        return suggestion
    }

    func autosens(
        profile: Profile
    ) async throws -> Autosens {
        debug(.openAPS, "Start autosens")
        let pumpHistory = appCoordinator.pumpHistory.value
        let carbs = appCoordinator.carbHistory.value
        let glucose = readGlucoseHistory()
        let basalProfile = appCoordinator.basalProfile.value
        let tempTargets = appCoordinator.tempTargets.value

        let autosensResult = try await autosens(
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
        return autosens
    }

    func autotune(
        profile: Profile,
        pumpProfile: Profile,
        previousAutotune: Profile?,
        categorizeUamAsBasal: Bool = false,
        tuneInsulinCurve: Bool = false
    ) async throws -> Profile? {
        debug(.openAPS, "Start autotune")
        let pumpHistory = appCoordinator.pumpHistory.value
        let carbs = appCoordinator.carbHistory.value
        let glucose = readGlucoseHistory()

        var autotuneResult = try await self.autotuneFull(
            pumphistory: pumpHistory,
            profile: profile,
            glucose: glucose,
            pumpprofile: pumpProfile,
            carbs: carbs,
            categorizeUamAsBasal: categorizeUamAsBasal,
            tuneInsulinCurve: tuneInsulinCurve,
            previousAutotuneResult: previousAutotune ?? profile,
        )
        autotuneResult.createdAt = Date.now
        debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult.rawJSON())")

        return autotuneResult
    }

    func makeProfiles(
        dynamicVariables: DynamicVariables,
        useAutotune: Bool,
        settings: FreeAPSSettings
    ) async throws -> (profile: Profile, pumpProfile: Profile) {
        debug(.openAPS, "Start makeProfiles")

        let preferences = appCoordinator.preferences.value
        let pumpSettings = appCoordinator.pumpSettings.value
        let bgTargets = appCoordinator.bgTargetsSchedule.value
        let basalProfile = appCoordinator.basalProfile.value
        let isf = appCoordinator.isfSchedule.value
        let cr = appCoordinator.crSchedule.value
        let tempTargets = appCoordinator.tempTargets.value
        let model = appCoordinator.pumpStatus.value?.model ?? "722"
        let autotune = getAutotune(useAutotune: useAutotune)

        let start = Date.now
        let pumpProfile = try await makeProfile(
            preferences: preferences,
            pumpSettings: pumpSettings,
            bgTargets: bgTargets,
            basalProfile: basalProfile,
            isf: isf,
            carbRatio: cr,
            tempTargets: tempTargets,
            model: model,
            autotune: nil,
            freeaps: settings,
            dynamicVariables: dynamicVariables,
            settings: settings
        )

        let profile: Profile
        if autotune == nil {
            profile = pumpProfile
        } else {
            profile = try await makeProfile(
                preferences: preferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: autotune,
                freeaps: settings,
                dynamicVariables: dynamicVariables,
                settings: settings
            )
        }

        print(
            "MakeProfiles: Time for profile and pumpProfile \(-1 * start.timeIntervalSinceNow) seconds"
        )

        return (profile: profile, pumpProfile: pumpProfile)
    }

    // MARK: - Private

    private func aisfOverrideSetting(override: OverrideSnapshot?) -> Bool? {
        guard let override, override.overrideAutoISF, let aisfOverride = override.aisf else { return nil }
        return aisfOverride.autoisf
    }

    private func readGlucoseHistory() -> [GlucoseEntry0] {
        // newest->oldest
        appCoordinator.glucoseFrequencyFiltered.value.map { g in
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

    private func readReservoir() -> Decimal {
        let reservoir: Decimal
        switch appCoordinator.pumpStatus.value?.reservoir {
        case let .units(units): reservoir = units
        case .aboveThreshold: reservoir = 100.0
        case nil: reservoir = 100.0
        }
        return reservoir
    }

    private func getAutotune(useAutotune: Bool) -> Profile? {
        useAutotune ? appCoordinator.autotune.value : nil
    }

    private func updateSuggestion(
        suggestion: inout Suggestion,
        preferences: Preferences,
        profile: Profile,
        currentTemp _: TempBasal,
        tdd: InsulinDistributionSnapshot?,
        settings: FreeAPSSettings,
        override: OverrideSnapshot?,
        aisfActive: Bool,
        aisfDisabledByNightTime: Bool
    ) {
        var reasonString = suggestion.reason
        let startIndex = reasonString.startIndex
        var aisf = false
        var totalDailyDose: Decimal?

        let parsedReason = parseReason(suggestion.reason)

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
            if aisfActive {
                let reasons = profile.autoISFReasons ?? ""
                // if Auto ISF is not active...
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
            } else {
                // Dynamic
                if preferences.useNewFormula {
                    var insertedResons = "Dynamic Ratio: \(isf)"
                    if preferences.sigmoid {
                        insertedResons += ", Sigmoid function"
                    } else {
                        insertedResons += ", Logarithmic function"
                    }
                    insertedResons += ", AF: \(preferences.adjustmentFactor)"
                    if preferences.enableDynamicCR {
                        insertedResons += ", Dynamic ISF/CR is: On/On"
                    } else {
                        insertedResons += ", Dynamic ISF/CR is: On/Off"
                    }

                    insertedResons += tddString + ", "

                    if aisfDisabledByNightTime {
                        debugAutoISF(settings: settings)
                        insertedResons += "Auto ISF disabled during nighttime" + ", "
                    }

                    reasonString.insert(contentsOf: insertedResons, at: startIndex)
                } else {
                    // Autosens
                    var comment = ""
                    if aisfDisabledByNightTime {
                        debugAutoISF(settings: settings)
                        comment = "Auto ISF disabled during nighttime" + ", "
                    }
                    reasonString.insert(contentsOf: "Autosens ratio: \(isf)" + tddString + ", " + comment, at: startIndex)
                }
            }

            // Include ISF before eventual adjustment
            if let old = profile.oldISF, let oldISF = "\(old)".toDecimal,
               let newISF = parsedReason["ISF"]?.toDecimal,
               oldISF != newISF
            {
                reasonString = reasonString.replacingOccurrences(of: "ISF:", with: "ISF: \(oldISF) →")
            }

            // Include CR before eventual adjustment
            if let old = profile.oldCR, let oldCR = "\(old)".toDecimal,
               let newCR = parsedReason["CR"]?.toDecimal,
               oldCR != newCR
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

        if let targetGlucose = suggestion.targetBG, let override = override, override.enabled {
            var orString = ", Override: "
            if override.percentage != 100 {
                orString += (Self.formatter.string(from: override.percentage as NSNumber) ?? "")
            }
            if override.smbIsOff {
                orString += ". SMBs off"
            }
            orString += ". Target \(targetGlucose)"

            if let index = reasonString.firstIndex(of: ";") {
                reasonString.insert(contentsOf: orString, at: index)
            }
        } else if let target = suggestion.targetBG {
            if let index = reasonString.firstIndex(of: ";") {
                reasonString.insert(contentsOf: ", Target: \(target)", at: index)
            }
        }

        // SMB Delivery ratio
        if profile.smbDeliveryRatio != 0.5
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

        suggestion.reason = reasonString

        let aisfReasons: String? = aisf ? "\(profile.autoISFReasons ?? "")" : nil
        suggestion.iaps = SuggestionExtraFields(
            aisfReasons: aisfReasons,
            maxSafeBasal: parsedReason["maxSafeBasal"]?.toDecimal,
            units: profile.outUnits,
            overrideActive: override?.enabled ?? false,
            totalDailyDose: totalDailyDose,
            isf: parsedReason["ISF"]?.toDecimal,
            cr: parsedReason["CR"]?.toDecimal,
            minPredBG: parsedReason["minPredBG"]?.toDecimal
        )
    }

    private func debugAutoISF(settings: FreeAPSSettings) {
        debug(
            .openAPS,
            "Auto ISF disabled during nighttime \(settings.nightTime.startHour):\(settings.nightTime.startMinute) - \(settings.nightTime.endHour):\(settings.nightTime.endMinute) ."
        )
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

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

        return ", Basal: \(oldValue) → \(newValue)"
    }

    /// If iob is less than one hour of negative insulin and keto protection active, then enact a small keto protection basal rate
    private func aisfBasal(
        settings: FreeAPSSettings,
        pumpSettings: PumpSettings,
        _ basal: Decimal,
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
        let insertedResons = reasonString + "\n\nKeto Protection Basal Rate Set: \(rate) U/h"
        debug(.openAPS, "Auto ISF Keto Protection: Basal rate \(rate) U/h set for 30 minutes.")
        reasonString.insert(contentsOf: insertedResons, at: endIndex)
        returnSuggestion.reason = reasonString

        return returnSuggestion
    }

    private func parseReason(_ reason: String) -> [String: String] {
        reason
            .split(separator: ",")
            .flatMap { part in part.split(separator: ";") }
            .reduce(into: [String: String]()) { acc, pair in
                let parts = pair.split(separator: ":", maxSplits: 1).map { String($0) }
                if parts.count == 2 {
                    acc[parts[0].trimmingCharacters(in: .whitespaces)] =
                        parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
    }

    private func iob(
        pumpHistory: [PumpHistoryEvent],
        profile: Profile,
        clock: Date,
        autosens: Autosens?
    ) async throws -> [IOBEntry] {
        try await scriptExecutor.invoke(
            function: "iob",
            with: IobInput(
                pump_history: pumpHistory, // TODO: ensure it's newest -> oldest
                profile: profile,
                clock: clock,
                autosens: autosens,
            ),
            as: [IOBEntry].self
        )
    }

    func iobSync(
        profile: Profile,
        autosens: Autosens?,
        pumpHistory: [PumpHistoryEvent],
        clock: Date,
    ) async throws -> [IOBEntry] {
        try await scriptExecutor.invoke(
            function: "iob",
            with: IobInput(
                pump_history: pumpHistory, // TODO: ensure it's newest -> oldest
                profile: profile,
                clock: clock,
                autosens: autosens
            ),
            as: [IOBEntry].self
        )
    }

    private func meal(
        pumphistory: [PumpHistoryEvent],
        profile: Profile,
        basalProfile: [BasalProfileEntry],
        clock: Date,
        carbs: [CarbsEntry],
        glucose: [GlucoseEntry0],
        temporaryCarbs: CarbsEntry? // TODO: is this CarbsEntry ?
    ) async throws -> RecentCarbs {
        try await scriptExecutor.invoke(
            function: "meal",
            with: MealInput(
                pump_history: pumphistory,
                profile: profile,
                basal_profile: basalProfile,
                clock: clock,
                carbs: carbs,
                glucose: glucose,
                temporaryCarbs: temporaryCarbs
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
        try await scriptExecutor.invoke(
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
        iob: [IOBEntry],
        profile: Profile,
        autosens: Autosens?,
        meal: RecentCarbs,
        microBolusAllowed: Bool,
        reservoir: Decimal,
        pumpHistory: [PumpHistoryEvent], // TODO: pumpHistory not used in prepare
        clock: Date
    ) async throws -> Suggestion {
        try await scriptExecutor.invoke(
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
        try await scriptExecutor.invoke(
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

    private func makeProfile(
        preferences: Preferences,
        pumpSettings: PumpSettings,
        bgTargets: BGTargets,
        basalProfile: [BasalProfileEntry],
        isf: InsulinSensitivities,
        carbRatio: CarbRatios,
        tempTargets: [TempTarget],
        model: String,
        autotune: Profile?,
        freeaps: FreeAPSSettings,
        dynamicVariables: DynamicVariables,
        settings: FreeAPSSettings // TODO: two FreeAPSSettings
    ) async throws -> Profile {
        try await scriptExecutor.invoke(
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
                clock: Date.now
            ),
            as: Profile.self
        )
    }

    private func middleware(
        glucose: [GlucoseEntry0],
        currentTemp: TempBasal,
        iob: [IOBEntry],
        profile: Profile,
        autosens: Autosens?,
        meal: RecentCarbs,
        microBolusAllowed: Bool, // not passed to the middleware function
        reservoir: Decimal
    ) async throws -> Profile {
        guard let script = try await middlewareScript(name: OpenAPS.Middleware.determineBasal)?.body else {
            return profile
        }

        return try await scriptExecutor.invoke(
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
        iob: [IOBEntry],
        profile: Profile,
        autosens: Autosens?,
        pumpHistory: [PumpHistoryEvent],
        clock: Date
    ) async throws -> Profile {
        try await scriptExecutor.invoke(
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

    private func middlewareScript(name: String) async throws -> Script? {
        if let body = await storage.retrieveRaw(name) {
            return Script(name: "Middleware", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "Middleware", body: try! String(contentsOf: url))
        }

        return nil
    }
}
