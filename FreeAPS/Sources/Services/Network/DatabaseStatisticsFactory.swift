import CoreData
import Foundation
import LoopKitUI
import SwiftDate
import Swinject

actor DatabaseStatisticsFactory {
    private let storage: FileStorage
    private let settingsManager: SettingsManager
    private let deviceDataManager: DeviceDataManager
    private let appCoordinator: AppCoordinator

    private let coreDataStorage = CoreDataStorage()

    private let coredataContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()

    init(
        storage: FileStorage,
        settingsManager: SettingsManager,
        deviceDataManager: DeviceDataManager,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.settingsManager = settingsManager
        self.deviceDataManager = deviceDataManager
        self.appCoordinator = appCoordinator
    }
}

extension DatabaseStatisticsFactory {
    private var profileName: String {
        coreDataStorage.fetchSettingProfileName()
    }

    func buildVersion() -> DatabaseStatisticsVersion {
        DatabaseStatisticsVersion(
            created_at: Date.now,
            Build_Version: Bundle.main.releaseVersionNumber ?? "UnKnown", Branch: branch()
        )
    }

    func buildStats(settings: FreeAPSSettings) async -> Statistics {
        let units = settings.units
        let preferences = await settingsManager.preferences

        // Carbs
        let carbs = coreDataStorage.fetchMealData(interval: DateFilter.day.startDate)
        let carbTotal: Decimal = carbs.map({ carbs in carbs.carbs as? Decimal ?? 0 }).reduce(0, +)

        // TDD
        let tdds = coreDataStorage.fetchTDD(interval: DateFilter.fourteenDays.startDate)
        var currentTDD: Decimal = 0
        var tddTotalAverage: Decimal = 0
        if !tdds.isEmpty {
            currentTDD = tdds[0].tdd?.decimalValue ?? 0
            let tddArray = tdds.compactMap({ insulin in insulin.tdd as? Decimal ?? 0 })
            tddTotalAverage = tddArray.reduce(0, +) / Decimal(tddArray.count)
        }

        var algo_ = "Oref0"

        if settings.autoisf {
            algo_ = "Auto ISF"
        } else if preferences.sigmoid, preferences.enableDynamicCR {
            algo_ = "Dynamic ISF + CR: Sigmoid"
        } else if preferences.sigmoid, !preferences.enableDynamicCR {
            algo_ = "Dynamic ISF: Sigmoid"
        } else if preferences.useNewFormula, preferences.enableDynamicCR {
            algo_ = "Dynamic ISF + CR: Logarithmic"
        } else if preferences.useNewFormula, !preferences.sigmoid,!preferences.enableDynamicCR {
            algo_ = "Dynamic ISF: Logarithmic"
        }

        let af = preferences.adjustmentFactor
        let insulin_type = preferences.curve
        let buildDate = Bundle.main.buildDate
        let version = Bundle.main.releaseVersionNumber
        let build = Bundle.main.buildVersionNumber

        // Read branch information from branch.txt instead of infoDictionary
        let branch = branch()
        let copyrightNotice_ = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
        let pump_ = appCoordinator.pumpInfo.value?.name ?? ""

        var iPa: Decimal = 75
        if preferences.useCustomPeakTime {
            iPa = preferences.insulinPeakTime
        } else if preferences.curve.rawValue == "rapid-acting" {
            iPa = 65
        } else if preferences.curve.rawValue == "ultra-rapid" {
            iPa = 50
        }
        // CGM Readings
        let glucose_24 = coreDataStorage.fetchGlucose(interval: DateFilter.day.startDate) // Day
        let glucose_7 = coreDataStorage.fetchGlucose(interval: DateFilter.week.startDate) // Week
        let glucose_30 = coreDataStorage.fetchGlucose(interval: DateFilter.month.startDate) // Month
        let glucose = coreDataStorage.fetchGlucose(interval: DateFilter.total.startDate) // Total

        // First date
        let previous = glucose.last?.date ?? Date()
        // Last date (recent)
        let current = glucose.first?.date ?? Date()
        // Total time in days
        let numberOfDays = (current - previous).timeInterval / 8.64E4

        // Get glucose computations for every case
        let oneDayGlucose = glucoseStats(glucose_24, settings: settings)
        let sevenDaysGlucose = glucoseStats(glucose_7, settings: settings)
        let thirtyDaysGlucose = glucoseStats(glucose_30, settings: settings)
        let totalDaysGlucose = glucoseStats(glucose, settings: settings)

        let median = Durations(
            day: roundDecimal(Decimal(oneDayGlucose.median), 1),
            week: roundDecimal(Decimal(sevenDaysGlucose.median), 1),
            month: roundDecimal(Decimal(thirtyDaysGlucose.median), 1),
            total: roundDecimal(Decimal(totalDaysGlucose.median), 1)
        )

        let overrideHbA1cUnit = settings.overrideHbA1cUnit

        let hbs = Durations(
            day: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                roundDecimal(Decimal(oneDayGlucose.ifcc), 1) : roundDecimal(Decimal(oneDayGlucose.ngsp), 1),
            week: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                roundDecimal(Decimal(sevenDaysGlucose.ifcc), 1) : roundDecimal(Decimal(sevenDaysGlucose.ngsp), 1),
            month: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                roundDecimal(Decimal(thirtyDaysGlucose.ifcc), 1) : roundDecimal(Decimal(thirtyDaysGlucose.ngsp), 1),
            total: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                roundDecimal(Decimal(totalDaysGlucose.ifcc), 1) : roundDecimal(Decimal(totalDaysGlucose.ngsp), 1)
        )

        // Get TIR computations for every case
        let oneDay_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = tir(glucose_24, settings: settings)
        let sevenDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = tir(glucose_7, settings: settings)
        let thirtyDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = tir(glucose_30, settings: settings)
        let totalDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = tir(glucose, settings: settings)

        let tir = Durations(
            day: roundDecimal(Decimal(oneDay_.TIR), 1),
            week: roundDecimal(Decimal(sevenDays_.TIR), 1),
            month: roundDecimal(Decimal(thirtyDays_.TIR), 1),
            total: roundDecimal(Decimal(totalDays_.TIR), 1)
        )
        let hypo = Durations(
            day: Decimal(oneDay_.hypos),
            week: Decimal(sevenDays_.hypos),
            month: Decimal(thirtyDays_.hypos),
            total: Decimal(totalDays_.hypos)
        )
        let hyper = Durations(
            day: Decimal(oneDay_.hypers),
            week: Decimal(sevenDays_.hypers),
            month: Decimal(thirtyDays_.hypers),
            total: Decimal(totalDays_.hypers)
        )
        let normal = Durations(
            day: Decimal(oneDay_.normal_),
            week: Decimal(sevenDays_.normal_),
            month: Decimal(thirtyDays_.normal_),
            total: Decimal(totalDays_.normal_)
        )
        let range = Threshold(
            low: units == .mmolL ? roundDecimal(settings.low.asMmolL, 1) :
                roundDecimal(settings.low, 0),
            high: units == .mmolL ? roundDecimal(settings.high.asMmolL, 1) :
                roundDecimal(settings.high, 0)
        )
        let TimeInRange = TIRs(
            TIR: tir,
            Hypos: hypo,
            Hypers: hyper,
            Threshold: range,
            Euglycemic: normal
        )
        let avgs = Durations(
            day: roundDecimal(Decimal(oneDayGlucose.average), 1),
            week: roundDecimal(Decimal(sevenDaysGlucose.average), 1),
            month: roundDecimal(Decimal(thirtyDaysGlucose.average), 1),
            total: roundDecimal(Decimal(totalDaysGlucose.average), 1)
        )
        let avg = Averages(Average: avgs, Median: median)
        // Standard Deviations
        let standardDeviations = Durations(
            day: roundDecimal(Decimal(oneDayGlucose.sd), 1),
            week: roundDecimal(Decimal(sevenDaysGlucose.sd), 1),
            month: roundDecimal(Decimal(thirtyDaysGlucose.sd), 1),
            total: roundDecimal(Decimal(totalDaysGlucose.sd), 1)
        )
        // CV = standard deviation / sample mean x 100
        let cvs = Durations(
            day: roundDecimal(Decimal(oneDayGlucose.cv), 1),
            week: roundDecimal(Decimal(sevenDaysGlucose.cv), 1),
            month: roundDecimal(Decimal(thirtyDaysGlucose.cv), 1),
            total: roundDecimal(Decimal(totalDaysGlucose.cv), 1)
        )
        let variance = Variance(SD: standardDeviations, CV: cvs)

        // Loops
        let request = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
        request.predicate = NSPredicate(
            format: "interval > 0 AND start > %@",
            Date().removingTimeInterval(.hours(24)) as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]
        let lsr = (try? coredataContext.fetch(request)) ?? []

        // Compute LoopStats for 24 hours
        let oneDayLoops = loops(lsr)
        let loopstat = LoopCycles(
            loops: oneDayLoops.loops,
            errors: oneDayLoops.errors,
            mostFrequentErrorType: oneDayLoops.mostFrequentErrorType,
            mostFrequentErrorAmount: oneDayLoops.mostFrequentErrorAmount,
            readings: Int(oneDayGlucose.readings),
            success_rate: oneDayLoops.success_rate,
            avg_interval: oneDayLoops.avg_interval,
            median_interval: oneDayLoops.median_interval,
            min_interval: oneDayLoops.min_interval,
            max_interval: oneDayLoops.max_interval,
            avg_duration: oneDayLoops.avg_duration,
            median_duration: oneDayLoops.median_duration,
            min_duration: oneDayLoops.min_duration,
            max_duration: oneDayLoops.max_duration
        )

        // Insulin
        let insulinDistribution = coreDataStorage.fetchInsulinDistribution()
        let insulin = Ins(
            TDD: roundDecimal(currentTDD, 2),
            bolus: insulinDistribution.first != nil ? ((insulinDistribution.first?.bolus ?? 0) as Decimal) : 0,
            temp_basal: insulinDistribution.first != nil ? ((insulinDistribution.first?.tempBasal ?? 0) as Decimal) : 0,
            scheduled_basal: insulinDistribution
                .first != nil ? ((insulinDistribution.first?.scheduledBasal ?? 0) as Decimal) : 0,
            total_average: roundDecimal(tddTotalAverage, 1)
        )

        let hbA1cUnit = !overrideHbA1cUnit ? (units == .mmolL ? "mmol/mol" : "%") : (units == .mmolL ? "%" : "mmol/mol")

        return Statistics(
            created_at: Date(),
            iPhone: await UIDevice.current.getDeviceId,
            iOS: await UIDevice.current.getOSInfo,
            Build_Version: version ?? "",
            Build_Number: build ?? "1",
            Branch: branch,
            CopyRightNotice: String(copyrightNotice_.prefix(32)),
            Build_Date: buildDate,
            Algorithm: algo_,
            AdjustmentFactor: af,
            Pump: pump_,
            CGM: appCoordinator.cgmInfo.value?.identifierForStatistics ?? "",
            insulinType: insulin_type.rawValue,
            peakActivityTime: iPa,
            Carbs_24h: carbTotal,
            GlucoseStorage_Days: Decimal(roundDouble(numberOfDays, 1)),
            Statistics: Stats(
                Distribution: TimeInRange,
                Glucose: avg,
                HbA1c: hbs, Units: Units(Glucose: units.rawValue, HbA1c: hbA1cUnit),
                LoopCycles: loopstat,
                Insulin: insulin,
                Variance: variance
            ),
            dob: settings.birthDate,
            sex: settings.sexSetting
        )
    }

    func buildProfile() async -> NightscoutProfileStore? {
        guard let sensitivities = await storage.retrieveFile(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
        else { return nil }

        guard let targets = await storage.retrieveFile(OpenAPS.Settings.bgTargets, as: BGTargets.self) else { return nil }

        guard let carbRatios = await storage.retrieveFile(OpenAPS.Settings.carbRatios, as: CarbRatios.self) else { return nil }

        guard let basalProfile = await storage.retrieveFile(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
        else { return nil }

        let sens = sensitivities.sensitivities.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.sensitivity,
                timeAsSeconds: item.offset * 60
            )
        }

        let target_low = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.low,
                timeAsSeconds: item.offset * 60
            )
        }

        let target_high = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.high,
                timeAsSeconds: item.offset * 60
            )
        }

        let cr = carbRatios.schedule.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.ratio,
                timeAsSeconds: item.offset * 60
            )
        }

        let basal = basalProfile.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.rate,
                timeAsSeconds: item.minutes * 60
            )
        }

        let settings = await settingsManager.settings
        let preferences = await settingsManager.preferences
        let pumpSettings = await settingsManager.pumpSettings

        var nsUnits = ""
        switch settings.units {
        case .mgdL:
            nsUnits = "mg/dl"
        case .mmolL:
            nsUnits = "mmol"
        }

        var carbs_hr: Decimal = 0
        if let isf = sensitivities.sensitivities.map(\.sensitivity).first,
           let cr = carbRatios.schedule.map(\.ratio).first,
           isf > 0, cr > 0
        {
            // CarbImpact -> Carbs/hr = CI [mg/dl/5min] * 12 / ISF [mg/dl/U] * CR [g/U]
            carbs_hr = preferences.min5mCarbimpact * 12 / isf * cr
            if settings.units == .mmolL {
                carbs_hr = carbs_hr * GlucoseUnits.exchangeRate
            }
            // No, Decimal has no rounding function.
            carbs_hr = Decimal(round(Double(carbs_hr) * 10.0)) / 10
        }

        let ps = ScheduledNightscoutProfile(
            dia: pumpSettings.insulinActionCurve,
            carbs_hr: Int(carbs_hr),
            delay: 0,
            timezone: TimeZone.current.identifier,
            target_low: target_low,
            target_high: target_high,
            sens: sens,
            basal: basal,
            carbratio: cr,
            units: nsUnits
        )

        let now = Date.now

        let profile = NightscoutProfileStore(
            defaultProfile: "default",
            startDate: now,
            mills: Int(now.timeIntervalSince1970) * 1000,
            units: nsUnits,
            enteredBy: NigtscoutTreatment.local,
            store: ["default": ps],
            profile: profileName
        )

        return profile
    }

    private func branch() -> String {
        var branch = "Unknown"
        if let branchFileURL = Bundle.main.url(forResource: "branch", withExtension: "txt"),
           let branchFileContent = try? String(contentsOf: branchFileURL)
        {
            let lines = branchFileContent.components(separatedBy: .newlines)
            for line in lines {
                let components = line.components(separatedBy: "=")
                if components.count == 2 {
                    let key = components[0].trimmingCharacters(in: .whitespaces)
                    let value = components[1].trimmingCharacters(in: .whitespaces)

                    if key == "BRANCH" {
                        branch = value
                        break
                    }
                }
            }
        }
        return branch
    }

    private func glucoseStats(_ fetchedGlucose: [Readings], settings: FreeAPSSettings)
        -> (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
    {
        // First date
        let last = fetchedGlucose.last?.date ?? Date()
        // Last date (recent)
        let first = fetchedGlucose.first?.date ?? Date()
        // Total time in days
        let numberOfDays = (first - last).timeInterval / 8.64E4
        let denominator = numberOfDays < 1 ? 1 : numberOfDays
        let justGlucoseArray = fetchedGlucose.compactMap({ each in Int(each.glucose as Int16) })
        let sumReadings = justGlucoseArray.reduce(0, +)
        let countReadings = justGlucoseArray.count
        let glucoseAverage = Double(sumReadings) / Double(countReadings)
        let medianGlucose = medianCalculation(array: justGlucoseArray)
        let NGSPa1CStatisticValue = (glucoseAverage + 46.7) / 28.7 // NGSP (%)
        let IFCCa1CStatisticValue = 10.929 *
            (NGSPa1CStatisticValue - 2.152) // IFCC (mmol/mol)  A1C(mmol/mol) = 10.929 * (A1C(%) - 2.15)

        var sumOfSquares = 0.0

        for array in justGlucoseArray {
            sumOfSquares += pow(Double(array) - Double(glucoseAverage), 2)
        }
        var sd = 0.0
        var cv = 0.0
        // Avoid division by zero
        if glucoseAverage > 0 {
            sd = sqrt(sumOfSquares / Double(countReadings))
            cv = sd / Double(glucoseAverage) * 100
        }
        let conversionFactor = 0.0555
        let units = settings.units

        return (
            ifcc: IFCCa1CStatisticValue,
            ngsp: NGSPa1CStatisticValue,
            average: glucoseAverage * (units == .mmolL ? conversionFactor : 1),
            median: medianGlucose * (units == .mmolL ? conversionFactor : 1),
            sd: sd * (units == .mmolL ? conversionFactor : 1), cv: cv,
            readings: Double(countReadings) / denominator
        )
    }

    private func tir(
        _ glucose: [Readings],
        settings: FreeAPSSettings
    ) -> (TIR: Double, hypos: Double, hypers: Double, normal_: Double) {
        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let totalReadings = justGlucoseArray.count
        let highLimit = settings.high
        let lowLimit = settings.low
        let hyperArray = glucose.filter({ $0.glucose >= Int(highLimit) })
        let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
        let hyperPercentage = Double(hyperReadings) / Double(totalReadings) * 100
        let hypoArray = glucose.filter({ $0.glucose <= Int(lowLimit) })
        let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
        let hypoPercentage = Double(hypoReadings) / Double(totalReadings) * 100
        // Euglyccemic range
        let normalArray = glucose.filter({ $0.glucose >= 70 && $0.glucose <= 140 })
        let normalReadings = normalArray.compactMap({ each in each.glucose as Int16 }).count
        let normalPercentage = Double(normalReadings) / Double(totalReadings) * 100
        // TIR
        let tir = 100 - (hypoPercentage + hyperPercentage)
        return (
            roundDouble(tir, 1),
            roundDouble(hypoPercentage, 1),
            roundDouble(hyperPercentage, 1),
            roundDouble(normalPercentage, 1)
        )
    }

    private func loops(_ loops: [LoopStatRecord]) -> Loops {
        // First date
        let previous = loops.last?.end ?? Date()
        // Last date (recent)
        let current = loops.first?.start ?? Date()
        // Total time in days
        let totalTime = (current - previous).timeInterval / 8.64E4

        let durationArray = loops.compactMap({ each in each.duration })
        let durationArrayCount = durationArray.count
        let durationAverage = durationArray.reduce(0, +) / Double(durationArrayCount) * 60
        let medianDuration = medianCalculationDouble(array: durationArray) * 60
        let max_duration = (durationArray.max() ?? 0) * 60
        let min_duration = (durationArray.min() ?? 0) * 60
        let successsNR = loops.compactMap({ each in each.loopStatus }).filter({ $0.contains("Success") }).count
        let errorNR = durationArrayCount - successsNR
        let total = Double(successsNR + errorNR) == 0 ? 1 : Double(successsNR + errorNR)
        let successRate: Double = (Double(successsNR) / total) * 100
        let loopNr = totalTime <= 1 ? total : round(total / (totalTime != 0 ? totalTime : 1))
        let intervalArray = loops.compactMap({ each in each.interval as Double })
        let count = intervalArray.count != 0 ? intervalArray.count : 1
        let median_interval = medianCalculationDouble(array: intervalArray)
        let intervalAverage = intervalArray.reduce(0, +) / Double(count)
        let maximumInterval = intervalArray.max()
        let minimumInterval = intervalArray.min()

        // Loop errors
        let errorArray = loops.compactMap(\.error)
        let mostFrequentString = errorArray.mostFrequent()?.description ?? ""

        return Loops(
            loops: Int(loopNr),
            errors: errorNR,
            mostFrequentErrorType: mostFrequentString,
            mostFrequentErrorAmount: errorArray.filter({ $0 == mostFrequentString }).count,
            success_rate: roundDecimal(Decimal(successRate), 1),
            avg_interval: roundDecimal(Decimal(intervalAverage), 1),
            median_interval: roundDecimal(Decimal(median_interval), 1),
            min_interval: roundDecimal(Decimal(minimumInterval ?? 0), 1),
            max_interval: roundDecimal(Decimal(maximumInterval ?? 0), 1),
            avg_duration: roundDecimal(Decimal(durationAverage), 1),
            median_duration: roundDecimal(Decimal(medianDuration), 1),
            min_duration: roundDecimal(Decimal(min_duration), 1),
            max_duration: roundDecimal(Decimal(max_duration), 1)
        )
    }

    private func roundDecimal(_ decimal: Decimal, _ digits: Double) -> Decimal {
        let rounded = round(Double(decimal) * pow(10, digits)) / pow(10, digits)
        return Decimal(rounded)
    }

    private func roundDouble(_ double: Double, _ digits: Double) -> Double {
        let rounded = round(Double(double) * pow(10, digits)) / pow(10, digits)
        return rounded
    }

    private func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    private func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }
}
