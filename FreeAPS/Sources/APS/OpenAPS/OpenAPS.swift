import Combine
import CoreData
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)
    private let storage: FileStorage
    private let nightscout: NightscoutManager
    private let pumpStorage: PumpHistoryStorage

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext // newBackgroundContext()

    init(storage: FileStorage, nightscout: NightscoutManager, pumpStorage: PumpHistoryStorage) {
        self.storage = storage
        self.nightscout = nightscout
        self.pumpStorage = pumpStorage
    }

    func determineBasal(currentTemp: TempBasal, clock: Date = Date()) -> Future<Suggestion?, Never> {
        Future { promise in
            self.processQueue.async {
                let start = Date.now
                var now = Date.now

                debug(.openAPS, "Start determineBasal")
                // clock
                self.storage.save(clock, as: Monitor.clock)
                let tempBasal = currentTemp.rawJSON
                self.storage.save(tempBasal, as: Monitor.tempBasal)
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let preferences = self.loadFileFromStorage(name: Settings.preferences)
                let preferencesData = Preferences(from: preferences)
                var profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                // To do: remove this struct.
                let dynamicVariables = self.loadFileFromStorage(name: Monitor.dynamicVariables)
                // For other settings
                let data = self.loadFileFromStorage(name: FreeAPS.settings)
                let settings = FreeAPSSettings(from: data)
                let tdd = CoreDataStorage().fetchInsulinDistribution().first
                print("Time for Loading files \(-1 * now.timeIntervalSinceNow) seconds")

                now = Date.now
                let meal = self.meal(
                    pumphistory: pumpHistory,
                    profile: profile,
                    basalProfile: basalProfile,
                    clock: clock,
                    carbs: carbs,
                    glucose: glucose
                )
                print("Time for Meal module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)")

                self.storage.save(meal, as: Monitor.meal)

                now = Date.now
                // iob
                let autosens = self.loadFileFromStorage(name: Settings.autosense)
                let iob = self.iob(
                    pumphistory: pumpHistory,
                    profile: profile,
                    clock: clock,
                    autosens: autosens.isEmpty ? .null : autosens
                )
                self.storage.save(iob, as: Monitor.iob)
                print("Time for IOB module \(-1 * now.timeIntervalSinceNow) seconds, total: \(-1 * start.timeIntervalSinceNow)")

                // determine-basal
                let reservoir = self.loadFileFromStorage(name: Monitor.reservoir)

                // The Middleware layer.
                let alteredProfile = self.middleware(
                    glucose: glucose,
                    currentTemp: tempBasal,
                    iob: iob,
                    profile: profile,
                    autosens: autosens.isEmpty ? .null : autosens,
                    meal: meal,
                    microBolusAllowed: true,
                    reservoir: reservoir,
                    dynamicVariables: dynamicVariables
                )

                // Auto ISF Layer
                if let freeAPSSettings = settings, freeAPSSettings.autoisf {
                    profile = self.autosisf(
                        glucose: glucose,
                        profile: alteredProfile,
                        autosens: autosens.isEmpty ? .null : autosens,
                        dynamicVariables: dynamicVariables,
                        pumpHistory: pumpHistory
                    )
                }

                now = Date.now
                // The OpenAPS layer
                let suggested = self.determineBasal(
                    glucose: glucose,
                    currentTemp: tempBasal,
                    iob: iob,
                    profile: profile,
                    autosens: autosens.isEmpty ? .null : autosens,
                    meal: meal,
                    microBolusAllowed: true,
                    reservoir: reservoir,
                    dynamicVariables: dynamicVariables,
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
                    if let mySettings = settings, mySettings.autoisf, let iob = suggestion.iob {
                        // If IOB < one hour of negative insulin and keto protection is active, then enact a small keto protection basal rate
                        if mySettings.ketoProtect, iob < 0,
                           let rate = suggestion.rate, rate <= 0,
                           let basal = self.readBasal(alteredProfile), iob < -basal, (suggestion.units ?? 0) <= 0,
                           let basalRate = self.aisfBasal(mySettings, basal, oref0Suggestion: suggestion)
                        {
                            suggestion = basalRate
                        }
                        // Use Auto ISF iobThresholdPercent limit for SMBs, when applicable
                        if let smbThreshold = self.exceedBy30Percent(
                            settings: mySettings,
                            suggestion: suggestion,
                            profile: alteredProfile,
                            iob: iob,
                            preferences: preferencesData
                        ) {
                            suggestion = smbThreshold
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
                } else {
                    promise(.success(nil))
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
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let autosensResult = self.autosense(
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

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) -> Future<Autotune?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autotune")
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let pumpProfile = self.loadFileFromStorage(name: Settings.pumpProfile)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)

                let autotunePreppedGlucose = self.autotunePrepare(
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

                let autotuneResult = self.autotuneRun(
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
            }
        }
    }

    func makeProfiles(useAutotune: Bool, settings: FreeAPSSettings) -> Future<Autotune?, Never> {
        Future { promise in
            debug(.openAPS, "Start makeProfiles")
            self.processQueue.async {
                var preferences = self.loadFileFromStorage(name: Settings.preferences)
                if preferences.isEmpty {
                    preferences = Preferences().rawJSON
                }
                let pumpSettings = self.loadFileFromStorage(name: Settings.settings)
                let bgTargets = self.loadFileFromStorage(name: Settings.bgTargets)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let isf = self.loadFileFromStorage(name: Settings.insulinSensitivities)
                let cr = self.loadFileFromStorage(name: Settings.carbRatios)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let model = self.loadFileFromStorage(name: Settings.model)
                let autotune = useAutotune ? self.loadFileFromStorage(name: Settings.autotune) : .empty
                let freeaps = self.loadFileFromStorage(name: FreeAPS.settings)
                let preferencesData = Preferences(from: preferences)
                let tdd = self.tdd(preferencesData: preferencesData)
                if let insulin = tdd, insulin.hours > 0 {
                    CoreDataStorage().saveTDD(insulin)
                }
                let dynamicVariables = self.dynamicVariables(preferencesData)

                let pumpProfile = self.makeProfile(
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
                    autotune: autotune.isEmpty ? .null : autotune,
                    freeaps: freeaps,
                    dynamicVariables: dynamicVariables,
                    settings: settings
                )

                self.storage.save(pumpProfile, as: Settings.pumpProfile)
                self.storage.save(profile, as: Settings.profile)

                if let tunedProfile = Autotune(from: profile) {
                    promise(.success(tunedProfile))
                    return
                }

                promise(.success(nil))
            }
        }
    }

    // MARK: - Private

    private func reasons(
        reason: String,
        suggestion: Suggestion,
        preferences: Preferences?,
        profile: RawJSON,
        tdd: InsulinDistribution?,
        settings: FreeAPSSettings?
    ) -> String {
        var reasonString = reason
        let startIndex = reasonString.startIndex
        var aisf = false

        // Autosens.ratio / Dynamic Ratios
        if let isf = suggestion.sensitivityRatio {
            // TDD
            var tddString = ""
            if let tdd = tdd {
                let total = ((tdd.bolus ?? 0) as Decimal) + ((tdd.tempBasal ?? 0) as Decimal)
                let round = round(Double(total * 10)) / 10
                let bolus = Int(((tdd.bolus ?? 0) as Decimal) * 100 / (total != 0 ? total : 1))
                tddString = ", Insulin 24h: \(round) U, \(bolus) % Bolus"
            }
            // Auto ISF
            if let freeAPSSettings = settings, freeAPSSettings.autoisf {
                let reasons = profile.autoISFreasons ?? ""
                // If disabled in middleware or Auto ISF layer
                if let disabled = readAndExclude(json: profile, variable: "autoisf", exclude: "autoisf_m"),
                   let value = Bool(disabled), !value
                {
                    reasonString.insert(
                        contentsOf: "Autosens Ratio: \(isf)" + tddString + ", ",
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
        }

        // Display either Target or Override (where target is included).
        let targetGlucose = suggestion.targetBG
        if targetGlucose != nil, let or = OverrideStorage().fetchLatestOverride().first, or.enabled {
            var orString = ", Override:"
            if or.percentage != 100 {
                orString += " \(or.percentage.formatted()) %"
            }
            if or.smbIsOff {
                orString += " SMBs off"
            }
            orString += " Target \(targetGlucose ?? 0)"

            let index = reasonString.firstIndex(of: ";") ?? reasonString.index(reasonString.startIndex, offsetBy: -1)
            reasonString.insert(contentsOf: orString, at: index)
        } else if let target = targetGlucose {
            let index = reasonString.firstIndex(of: ";") ?? reasonString.index(reasonString.startIndex, offsetBy: -1)
            reasonString.insert(contentsOf: ", Target: \(target)", at: index)
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
                saveSuggestion.iob = iob as NSDecimalNumber
                saveSuggestion.cob = cob as NSDecimalNumber
                saveSuggestion.target = target as NSDecimalNumber
                saveSuggestion.minPredBG = minPredBG as NSDecimalNumber
                saveSuggestion.eventualBG = Decimal(suggestion.eventualBG ?? 100) as NSDecimalNumber
                saveSuggestion.insulinReq = (suggestion.insulinReq ?? 0) as NSDecimalNumber
                saveSuggestion.smb = (suggestion.units ?? 0) as NSDecimalNumber
                saveSuggestion.rate = (suggestion.rate ?? 0) as NSDecimalNumber
                saveSuggestion.reasons = aisfReasons
                saveSuggestion.glucose = (suggestion.bg ?? 0) as NSDecimalNumber
                saveSuggestion.ratio = (suggestion.sensitivityRatio ?? 1) as NSDecimalNumber
                saveSuggestion.date = Date.now

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

    /// The curious 130% of Auto ISF iobThresholdPercent limit for SMBs
    private func exceedBy30Percent(
        settings: FreeAPSSettings,
        suggestion: Suggestion,
        profile: RawJSON,
        iob: Decimal,
        preferences: Preferences?
    ) -> Suggestion? {
        guard settings.iobThresholdPercent < 100 else { return nil }
        guard let insReq = suggestion.insulinReq else { return nil }
        guard let bolus = suggestion.units, bolus > 0 else { return nil }
        guard let maxIOB = readReason(reason: profile, variable: "max_iob"),
              let deliveryRatio = readReason(reason: profile, variable: "smb_delivery_ratio")
        else { return nil }
        guard iob < maxIOB, iob + insReq > maxIOB, iob + insReq * deliveryRatio < maxIOB * 1.3 else { return nil }
        guard let openAPSsettings = preferences,
              let basal = readReason(reason: profile, variable: "current_basal") else { return nil }
        guard basal <= 0, bolus * 1.3 <= basal * openAPSsettings.maxSMBBasalMinutes * deliveryRatio else { return nil }

        // Adjust SMB and the ventual basal rate
        var output = suggestion
        output.units = Swift.max(bolus, 1.3 * settings.iobThresholdPercent * maxIOB / 100)
        output.reason += " 130% of microbolus: \((bolus * 1.3).roundBolus(increment: 0.10)). "
        output.reason = output.reason.replacingOccurrences(
            of: "Microbolusing: \(bolus)U",
            with: "Microbolusing: \(output.units ?? bolus)U"
        )

        debug(.openAPS, "130% of microbolus: \((bolus * 1.3).roundBolus(increment: 0.10))")
        return output
    }

    private func trimmedIsEqual(string: String, decimal: Decimal) -> String? {
        let old = string.replacingOccurrences(of: ": ", with: "").replacingOccurrences(of: "f", with: "")
        let new = "\(decimal)"
        guard old != new else { return nil }

        return old
    }

    private func overrideBasal(alteredProfile: RawJSON, oref0Suggestion: Suggestion) -> Suggestion? {
        guard let changeRate = readJSON(json: alteredProfile, variable: "set_basal"), Bool(changeRate) ?? false,
              let basal_rate_is = readJSON(json: alteredProfile, variable: "basal_rate") else { return nil }

        var returnSuggestion = oref0Suggestion
        var basal_rate = Decimal(string: basal_rate_is) ?? 0

        guard let settings = storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self) else {
            return nil
        }

        basal_rate = min(basal_rate, settings.maxBasal)

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

    private func tdd(preferencesData: Preferences?) -> (bolus: Decimal, basal: Decimal, hours: Double)? {
        let preferences = preferencesData
        guard let pumpData = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) else { return nil }

        let tdd = TotalDailyDose().totalDailyDose(pumpData, increment: Double(preferences?.bolusIncrement ?? 0.1))
        return tdd
    }

    func dynamicVariables(_ preferences: Preferences?) -> RawJSON {
        coredataContext.performAndWait {
            var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
            let wp = preferences?.weightPercentage ?? 1
            let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30) as NSDecimalNumber
            let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30) as NSDecimalNumber

            let settings = self.loadFileFromStorage(name: FreeAPS.settings)
            let settingsData = FreeAPSSettings(from: settings)
            let disableCGMError = settingsData?.disableCGMError ?? true

            let cd = CoreDataStorage()
            let os = OverrideStorage()
            // TDD
            let uniqueEvents = cd.fetchTDD(interval: DateFilter().tenDays)
            // Temp Targets using slider
            let sliderArray = cd.fetchTempTargetsSlider()
            // Overrides
            let overrideArray = os.fetchNumberOfOverrides(numbers: 2)
            // Temp Target
            let tempTargetsArray = cd.fetchTempTargets()

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
                isf: overrideArray.first?.isf ?? false,
                cr: overrideArray.first?.cr ?? false,
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
            storage.save(averages, as: OpenAPS.Monitor.dynamicVariables)
            return self.loadFileFromStorage(name: Monitor.dynamicVariables)
        }
    }

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
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
            worker.evaluate(script: Script(name: Prepare.log))
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
        carbs: JSON,
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autotunePrep))
            worker.evaluate(script: Script(name: Prepare.autotunePrep))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                glucose,
                pumpprofile,
                carbs,
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
            worker.evaluate(script: Script(name: Prepare.log))
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
        reservoir: JSON,
        dynamicVariables: JSON,
        pumpHistory: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Prepare.determineBasal))
            worker.evaluate(script: Script(name: Bundle.basalSetTemp))
            worker.evaluate(script: Script(name: Bundle.getLastGlucose))
            worker.evaluate(script: Script(name: Bundle.determineBasal))

            if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
                worker.evaluate(script: middleware)
            }

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
                    reservoir,
                    Date(),
                    dynamicVariables,
                    pumpHistory
                ]
            )
        }
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autosens))
            worker.evaluate(script: Script(name: Prepare.autosens))
            return worker.call(
                function: Function.generate,
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
    }

    private func exportDefaultPreferences() -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
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
        autotune: JSON,
        freeaps: JSON,
        dynamicVariables: JSON,
        settings: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Prepare.profile))
            worker.evaluate(script: Script(name: Bundle.profile))
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
                    autotune,
                    freeaps,
                    dynamicVariables,
                    settings
                ]
            )
        }
    }

    private func middleware(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        dynamicVariables: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Prepare.string))

            if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
                worker.evaluate(script: middleware)
            }

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
                    reservoir,
                    Date(),
                    dynamicVariables
                ]
            )
        }
    }

    private func autosisf(
        glucose: JSON,
        profile: JSON,
        autosens: JSON,
        dynamicVariables: JSON,
        pumpHistory: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: AutoISF.getLastGlucose))
            if let aisf = self.aisfScript(name: OpenAPS.AutoISF.autoisf) {
                worker.evaluate(script: aisf)
            }

            return worker.call(
                function: Function.generate,
                with: [
                    profile,
                    autosens,
                    dynamicVariables,
                    glucose,
                    Date(),
                    pumpHistory
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

    private func middlewareScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: "Middleware", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "Middleware", body: try! String(contentsOf: url))
        }

        return nil
    }

    private func aisfScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: "AISF", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "AISF", body: try! String(contentsOf: url))
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
