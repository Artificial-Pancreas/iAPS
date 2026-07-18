import CoreData
import Foundation
import JavaScriptCore
import Swinject

actor OpenAPS: Sendable {
    private let storage: FileStorage
    private let glucoseStorage: GlucoseStorage
    private let nightscout: NightscoutManager
    private let pumpStorage: PumpHistoryStorage
    private let settingsManager: SettingsManager
    private let appCoordinator: AppCoordinator

    private let coreDataStorage = CoreDataStorage()
    private let overrideStorage: OverrideStorage

    private let scriptExecutor = WebViewScriptExecutor()

    private static let filterIntervalFiveMinutes: TimeInterval = .minutes(4.5)
    private static let filterIntervalOneMinute: TimeInterval = .minutes(0.8)

    init(
        storage: FileStorage,
        glucoseStorage: GlucoseStorage,
        nightscout: NightscoutManager,
        pumpStorage: PumpHistoryStorage,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator,
        overrideStorage: OverrideStorage
    ) {
        self.storage = storage
        self.glucoseStorage = glucoseStorage
        self.nightscout = nightscout
        self.pumpStorage = pumpStorage
        self.settingsManager = settingsManager
        self.appCoordinator = appCoordinator
        self.overrideStorage = overrideStorage
    }

    func determineBasal(
        profile: Profile,
        autosens: Autosens?,
        currentTemp: TempBasal,
        clock: Date = Date(),
        temporaryCarbs: CarbsEntry?,
        override: OverrideSnapshot?
    ) async throws -> Suggestion {
        // For debugging
        let start = Date.now
        var now = Date.now

        debug(.openAPS, "Start determineBasal")
        await storage.save(clock, as: Monitor.clock)

        let pumpHistory = appCoordinator.pumpHistory.value
        let carbs = appCoordinator.carbHistory.value
        let glucose = await readGlucoseHistory()
        let preferences = appCoordinator.preferences.value
        let basalProfile = appCoordinator.basalProfile.value
        let settings = appCoordinator.settings.value
        let reservoir = readReservoir()

        var profile = profile
        print("Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

        now = Date.now
        let tdd = await coreDataStorage.fetchInsulinDistribution()
        print("Time for tdd \(-1 * now.timeIntervalSinceNow) seconds")

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

        now = Date.now
        // Auto ISF Layer
        let notDisabled = await notDisabled(override: override, settings: settings)
        let aisfEnabled = await aisfEnabled(override: override)
        if (settings.autoisfEffective && notDisabled) ||
            (aisfEnabled && !settings.isNighttime)
        {
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
        if settings.autoisfEffective, let iob = suggestion.iob {
            // If IOB < one hour of negative insulin and keto protection is active, then enact a small keto protection basal rate
            let basal = Decimal(alteredProfile.currentBasal)
            if settings.ketoProtect, iob < 0,
               let rate = suggestion.rate, rate <= 0,
               iob < -basal, (suggestion.units ?? 0) <= 0,
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
            currentTemp: currentTemp,
            tdd: tdd,
            settings: settings,
            override: override
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
        let glucose = await readGlucoseHistory()
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
        let glucose = await readGlucoseHistory()

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

    func makeProfiles(useAutotune: Bool, settings: FreeAPSSettings) async throws -> (profile: Profile, pumpProfile: Profile) {
        debug(.openAPS, "Start makeProfiles")
        let start = Date.now
        var now = Date.now

        let preferences = appCoordinator.preferences.value
        let pumpSettings = appCoordinator.pumpSettings.value
        let bgTargets = appCoordinator.bgTargetsSchedule.value
        let basalProfile = appCoordinator.basalProfile.value
        let isf = appCoordinator.isfSchedule.value
        let cr = appCoordinator.crSchedule.value
        let tempTargets = appCoordinator.tempTargets.value
        let model = appCoordinator.pumpStatus.value?.model ?? "722"
        let autotune = getAutotune(useAutotune: useAutotune)

        print("MakeProfiles: Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

        now = Date.now

        let tdd = await self.tdd(preferencesData: preferences)
        let dynamicVariables = await self.dynamicVariables(preferences)

        print(
            "Time for tdd and DynamicVariables \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        if let insulin = tdd, insulin.hours > 0 {
            await coreDataStorage.saveTDD(insulin)
        }

        now = Date.now
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
            "MakeProfiles: Time for profile and pumpProfile \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        now = Date.now

        print(
            "MakeProfiles: Time for save files \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        return (profile: profile, pumpProfile: pumpProfile)
    }

    // MARK: - Private

    private func aisfEnabled(override: OverrideSnapshot?) async -> Bool {
        guard let current = override, current.enabled else { return false }
        guard current.overrideAutoISF, let settings = await overrideStorage.fetchAutoISFsetting(id: current.id ?? ""),
              settings.autoisf else { return false }
        return true
    }

    private func notDisabled(override: OverrideSnapshot?, settings: FreeAPSSettings) async -> Bool {
        guard let current = override, current.enabled else { return true }
        guard current.overrideAutoISF, let settings = await overrideStorage.fetchAutoISFsetting(id: current.id ?? ""),
              !settings.autoisf else { return true }
        return false
    }

    private func readGlucoseHistory() async -> [GlucoseEntry0] {
        // newest->oldest
        let retrieved = appCoordinator.glucoseHistorySmoothed.value
        let settings = await settingsManager.settings

        let minInterval = settings.allowOneMinuteGlucose ? Self.filterIntervalOneMinute : Self.filterIntervalFiveMinutes

        return FrequentGlucoseFiltering
            .filterFrequentGlucose(retrieved, interval: minInterval)
            .map { g in
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

    private func reasons(
        reason: String,
        suggestion: Suggestion,
        preferences: Preferences,
        profile: Profile,
        currentTemp _: TempBasal,
        tdd: InsulinDistributionSnapshot?,
        settings: FreeAPSSettings,
        override: OverrideSnapshot?
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
            let notDisabled = await notDisabled(override: override, settings: settings)
            let aisfEnabled = await aisfEnabled(override: override)
            if (settings.autoisfEffective && notDisabled) ||
                (aisfEnabled && !settings.isNighttime)
            {
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

                    if autoisfDisabledByNighttime(settings: settings) {
                        debugAutoISF(settings: settings)
                        insertedResons += "Auto ISF disabled during nighttime" + ", "
                    }

                    reasonString.insert(contentsOf: insertedResons, at: startIndex)
                } else {
                    // Autosens
                    var comment = ""
                    if autoisfDisabledByNighttime(settings: settings) {
                        debugAutoISF(settings: settings)
                        comment = "Auto ISF disabled during nighttime" + ", "
                    }
                    reasonString.insert(contentsOf: "Autosens ratio: \(isf)" + tddString + ", " + comment, at: startIndex)
                }
            }

            let parsedReason = parseReason(reason)

            // Include ISF before eventual adjustment
            if let old = profile.oldISF,
               let new = parsedReason["ISF"]?.toDecimal,
               let oldISF = trimmedIsEqual(string: "\(old)", decimal: new)
            {
                reasonString = reasonString.replacingOccurrences(of: "ISF:", with: "ISF: \(oldISF) →")
            }

            // Include CR before eventual adjustment
            if let old = profile.oldCR,
               let new = parsedReason["CR"]?.toDecimal,
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
        if targetGlucose != nil, let override = override, override.enabled {
            var orString = ", Override: "
            if override.percentage != 100 {
                orString += (Self.formatter.string(from: override.percentage as NSNumber) ?? "")
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

        // TODO: parsed second time?
        let parsedReason = parseReason(reason)

        // Save Suggestion to CoreData
        if let isf = parsedReason["ISF"]?.toDecimal,
           let minPredBG = parsedReason["minPredBG"]?.toDecimal,
           let cr = parsedReason["CR"]?.toDecimal,
           let iob = suggestion.iob, let cob = suggestion.cob, let target = targetGlucose
        {
            var aisfReasons: String?
            if aisf {
                // Save AISF output
                aisfReasons = "\(profile.autoISFReasons ?? "")"
            }

            let rateToSave: Decimal? = suggestion.rate ?? parsedReason["maxSafeBasal"]?.toDecimal

            let mmolToSave = profile.outUnits == .mmolL

            let overrideToSave = override?.enabled ?? false

            let tddToSave = totalDailyDose

            await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
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

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

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

        return ", Basal: \(oldValue) → \(newValue)"
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

    private func tdd(preferencesData: Preferences?) async -> (bolus: Decimal, basal: Decimal, hours: Double)? {
        let preferences = preferencesData
        let pumpData = appCoordinator.pumpHistory.value

        let tdd = TotalDailyDose().totalDailyDose(pumpData, increment: Double(preferences?.bolusIncrement ?? 0.1))
        return tdd
    }

    func dynamicVariables(_ preferences: Preferences?) async -> DynamicVariables {
        // TODO: calls to nightscout should not be part of this!
        let start = Date.now
        var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
        let wp = preferences?.weightPercentage ?? 1
        let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30)
        let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30)

        var now = Date.now
        // TDD
        let uniqueEvents = await coreDataStorage.fetchTDD(interval: DateFilter.tenDays.startDate)
        print(
            "dynamicVariables: Time to fetch TDD \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Temp Targets using slider
        now = Date.now
        let sliderArray = await coreDataStorage.fetchTempTargetsSlider()
        print(
            "dynamicVariables: Time for fetchTempTargetsSlider \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Overrides
        now = Date.now
        let overrideArray = await overrideStorage.fetchNumberOfOverrides(numbers: 2)
        print(
            "dynamicVariables: Time for fetchNumberOfOverrides \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Temp Target
        now = Date.now
        let tempTargetsArray = await coreDataStorage.fetchTempTargets()
        print(
            "dynamicVariables: Time for fetchTempTargets \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)"
        )

        // Time adjusted average
        var time = uniqueEvents.first?.timestamp ?? .distantPast
        var data_ = [tddData(date: time, tdd: (uniqueEvents.first?.tdd ?? 0) as Decimal)]

        for a in uniqueEvents {
            if a.timestamp ?? .distantFuture <= time.subtractingTimeInterval(.hours(24)) {
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
            .filter({ ($0.timestamp ?? Date()) >= Date.now.subtractingTimeInterval(.hours(2)) })
        var nrOfIndeces = twoHoursArray.count
        let totalAmount = twoHoursArray.compactMap({ each in each.tdd ?? 0 }).reduce(0, +)

        var temptargetActive = tempTargetsArray.first?.active ?? false
        let isPercentageEnabled = sliderArray.first?.enabled ?? false

        var useOverride = overrideArray.first?.enabled ?? false
        var overridePercentage = Decimal(overrideArray.first?.percentage ?? 100)
        var unlimited = overrideArray.first?.indefinite ?? true
        var disableSMBs = overrideArray.first?.smbIsOff ?? false
        let overrideMaxIOB = overrideArray.first?.overrideMaxIOB ?? false
        let maxIOB = overrideArray.first?.maxIOB ?? (preferences?.maxIOB ?? 0)

        var name = ""
        if useOverride, overrideArray.first?.isPreset ?? false,
           let overridePreset = await overrideStorage.isPresetName()
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
            if date.addingTimeInterval(.minutes(addedMinutes)) < Date(), !unlimited {
                useOverride = false
                if await overrideStorage.cancelProfile() != nil {
                    debug(.nightscout, "Override ended, duration: \(duration) minutes")
                }
            }
            // End with new Meal, when applicable
            if useOverride, overrideArray.first?.advancedSettings ?? false, overrideArray.first?.endWIthNewCarbs ?? false,
               let recent = await coreDataStorage.recentMeal(), !self.unchanged(meal: recent),
               (recent.actualDate ?? .distantPast) > (overrideArray.first?.date ?? .distantFuture)
            {
                useOverride = false
                if await overrideStorage.cancelProfile() != nil {
                    debug(
                        .nightscout,
                        "Override ended, because of new carbs: \(String(describing: recent.carbs)) g, duration: \(duration) minutes"
                    )
                }
            }

            // End with new glucose trending up, when applicable
            if useOverride,
               overrideArray.first?.glucoseOverrideThresholdActive ?? false,
               let g = await coreDataStorage.fetchRecentGlucose(),
               Decimal(g.glucose) > ((overrideArray.first?.glucoseOverrideThreshold ?? 100) as NSDecimalNumber) as Decimal,
               g.direction ?? BloodGlucose.Direction.fortyFiveDown.symbol == BloodGlucose.Direction.fortyFiveUp.symbol || g
               .direction ?? BloodGlucose
               .Direction.singleDown.symbol == BloodGlucose.Direction.singleUp.symbol || g.direction ?? BloodGlucose
               .Direction.doubleDown.symbol == BloodGlucose.Direction.doubleUp.symbol
            {
                useOverride = false
                if let duration = await overrideStorage.cancelProfile() {
                    let last_ = await overrideStorage.fetchLatestOverride().last
                    let name = await overrideStorage.isPresetName()
                    if let last = last_ {
                        await nightscout.uploadOverride(name ?? "", duration, last.date ?? Date.now)
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
               let g = await coreDataStorage.fetchRecentGlucose(),
               Decimal(g.glucose) <
               ((overrideArray.first?.glucoseOverrideThresholdDown ?? 90) as NSDecimalNumber) as Decimal
            {
                useOverride = false
                if let duration = await overrideStorage.cancelProfile() {
                    let last_ = await overrideStorage.fetchLatestOverride().last
                    let name = await overrideStorage.isPresetName()
                    if let last = last_ {
                        await nightscout.uploadOverride(name ?? "", duration, last.date ?? Date.now)
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
                duration_ = Int(truncating: tempTargetsArray.first?.duration as? NSNumber ?? 0)
                hbt = tempTargetsArray.first?.hbt ?? Double(hbt_)
                let startDate = tempTargetsArray.first?.startDate ?? Date()
                let durationPlusStart = startDate.addingTimeInterval(.minutes(duration_))
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
           let fetched = await overrideStorage.fetchAutoISFsetting(id: overrideArray.first?.id ?? "Not This One")
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
            smbMinutes: overrideArray.first?.smbMinutes ?? smbMinutes,
            uamMinutes: overrideArray.first?.uamMinutes ?? uamMinutes,
            maxIOB: maxIOB as Decimal,
            overrideMaxIOB: overrideMaxIOB,
            preset: name,
            autoISFoverrides: autoISFsettings,
            aisfOverridden: useOverride && (overrideArray.first?.overrideAutoISF ?? false)
        )

        await storage.save(averages, as: OpenAPS.Monitor.dynamicVariables)
        return averages
    }

    private func unchanged(meal: MealsSnapshot) -> Bool {
        let hasMicros = meal.micronutrient.contains { ($0.amount ?? 0) > 0 }

        return (meal.carbs ?? 0) <= 0 &&
            (meal.fat ?? 0) <= 0 &&
            (meal.protein ?? 0) <= 0 &&
            !hasMicros
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
