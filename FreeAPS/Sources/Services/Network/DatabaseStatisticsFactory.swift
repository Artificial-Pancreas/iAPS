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
    private let statistics: GlucoseStatistics

    private let coreDataStorage = CoreDataStorage()

    init(
        storage: FileStorage,
        settingsManager: SettingsManager,
        deviceDataManager: DeviceDataManager,
        appCoordinator: AppCoordinator,
        statistics: GlucoseStatistics
    ) {
        self.storage = storage
        self.settingsManager = settingsManager
        self.deviceDataManager = deviceDataManager
        self.appCoordinator = appCoordinator
        self.statistics = statistics
    }
}

extension DatabaseStatisticsFactory {
    private var profileName: String {
        get async {
            await coreDataStorage.fetchSettingProfileName()
        }
    }

    func buildVersion() -> DatabaseStatisticsVersion {
        DatabaseStatisticsVersion(
            created_at: Date.now,
            Build_Version: Bundle.main.releaseVersionNumber ?? "UnKnown",
            Branch: branch(),
            Memory: MemoryMetricsService.snapshot(full: false)
        )
    }

    func buildStats(settings: FreeAPSSettings) async -> Statistics {
        let units = settings.units
        let preferences = await settingsManager.preferences

        // Carbs
        let carbs = await coreDataStorage.fetchMealData(interval: DateFilter.day.startDate)
        let carbTotal: Decimal = carbs.map({ carbs in carbs.carbs ?? 0 }).reduce(0, +)

        // TDD
        let tdds = await coreDataStorage.fetchTDD(interval: DateFilter.fourteenDays.startDate)
        var currentTDD: Decimal = 0
        var tddTotalAverage: Decimal = 0
        if !tdds.isEmpty {
            currentTDD = tdds[0].tdd ?? 0
            let tddArray = tdds.compactMap({ insulin in insulin.tdd ?? 0 })
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
        // CGM readings: the rolling windows before E, from the statistics engine
        let bands = StatsBands(low: settings.low, high: settings.high, units: units)
        let hbA1cUnit = HbA1cUnit.resolve(units: units, override: settings.overrideHbA1cUnit)
        let day = await statistics.summary(rolling: .hours(24), bands: bands)
        let week = await statistics.summary(rolling: .days(7), bands: bands)
        let month = await statistics.summary(rolling: .days(30), bands: bands)
        let total = await statistics.summary(rolling: .days(90), bands: bands)
        let glucose = Self.glucoseNumbers(
            day: day,
            week: week,
            month: month,
            total: total,
            units: units,
            hbA1cUnit: hbA1cUnit
        )

        let range = Threshold(
            low: units == .mmolL ? Self.roundDecimal(settings.low.asMmolL, 1) :
                Self.roundDecimal(settings.low, 0),
            high: units == .mmolL ? Self.roundDecimal(settings.high.asMmolL, 1) :
                Self.roundDecimal(settings.high, 0)
        )
        let TimeInRange = TIRs(
            TIR: glucose.tir,
            Hypos: glucose.hypos,
            Hypers: glucose.hypers,
            Threshold: range,
            Euglycemic: glucose.euglycemic
        )

        // Loops
        let oneDayLoops = await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            request.predicate = NSPredicate(
                format: "interval > 0 AND start > %@",
                Date().subtractingTimeInterval(.hours(24)) as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]

            let lsr = (try? context.fetch(request)) ?? []
            return Self.loops(lsr)
        }

        // Compute LoopStats for 24 hours

        let loopstat = LoopCycles(
            loops: oneDayLoops.loops,
            errors: oneDayLoops.errors,
            mostFrequentErrorType: oneDayLoops.mostFrequentErrorType,
            mostFrequentErrorAmount: oneDayLoops.mostFrequentErrorAmount,
            readings: glucose.readings,
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
        let insulinDistribution = await coreDataStorage.fetchInsulinDistribution()
        let insulin = Ins(
            TDD: Self.roundDecimal(currentTDD, 2),
            bolus: insulinDistribution != nil ? ((insulinDistribution?.bolus ?? 0) as Decimal) : 0,
            temp_basal: insulinDistribution != nil ? ((insulinDistribution?.tempBasal ?? 0) as Decimal) : 0,
            scheduled_basal: insulinDistribution != nil ? ((insulinDistribution?.scheduledBasal ?? 0) as Decimal) : 0,
            total_average: Self.roundDecimal(tddTotalAverage, 1)
        )

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
            GlucoseStorage_Days: glucose.storageDays,
            Statistics: Stats(
                Distribution: TimeInRange,
                Glucose: glucose.averages,
                HbA1c: glucose.hbA1c,
                GMI: glucose.gmi,
                Units: Units(Glucose: units.rawValue, HbA1c: glucose.a1cUnit, GMI: glucose.a1cUnit),
                LoopCycles: loopstat,
                Insulin: insulin,
                Variance: glucose.variance
            ),
            // only what Settings › Sharing shares (`DemographicsSharing`)
            dob: settings.demographics.statisticsBirthDate,
            sex: settings.demographics.statisticsSex,
            Memory: MemoryMetricsService.snapshot(full: true)
        )
    }

    func buildProfile() async -> NightscoutProfileStore? {
        let sensitivities = appCoordinator.isfSchedule.value

        let targets = appCoordinator.bgTargetsSchedule.value

        let carbRatios = appCoordinator.crSchedule.value

        let basalProfile = appCoordinator.basalProfile.value

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

        let profileName = await self.profileName
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
        Bundle.main.gitBranch ?? "Unknown"
    }

    /// The glucose numbers of the upload, from the summaries of its four rolling windows (24 h, 7, 30 and 90 days
    /// before E). Time-weighted, over the bands of the Statistics low/high settings.
    struct GlucoseNumbers: Equatable, Sendable {
        /// in range (`low ... high`), percent
        let tir: Durations
        /// below low, percent
        let hypos: Durations
        /// above high, percent
        let hypers: Durations
        /// TITR (70-140 mg/dL, `StatsBands.titrRange`), percent
        let euglycemic: Durations
        /// mean and median, in the glucose units
        let averages: Averages
        /// ADAG estimated A1c (the eA1c the app shows), in `a1cUnit`
        let hbA1c: Durations
        /// Glucose Management Indicator, in `a1cUnit`
        let gmi: Durations
        /// SD in the glucose units, CV percent
        let variance: Variance
        /// "%" or "mmol/mol": the unit of `hbA1c` and `gmi`
        let a1cUnit: String
        /// the readings starting in the 24 h window
        let readings: Int
        /// from the first to the last reading of the 90 days, in days
        let storageDays: Decimal
    }

    /// The upload's glucose numbers from the window summaries: 1 decimal throughout, mean, median and SD converted
    /// to mmol/L for mmol users; 0 for an empty window.
    static func glucoseNumbers(
        day: GlucoseSummary,
        week: GlucoseSummary,
        month: GlucoseSummary,
        total: GlucoseSummary,
        units: GlucoseUnits,
        hbA1cUnit: HbA1cUnit
    ) -> GlucoseNumbers {
        let summaries = [day, week, month, total]
        func durations(_ value: (GlucoseSummary) -> Double?) -> Durations {
            let values = summaries.map { Self.roundDecimal(Decimal(value($0) ?? 0), 1) }
            return Durations(day: values[0], week: values[1], month: values[2], total: values[3])
        }
        func percent(_ bands: [GlucoseBand]) -> (GlucoseSummary) -> Double? {
            { summary in
                let fraction: Double = bands.reduce(0) { $0 + summary.fraction($1) }
                return fraction * 100
            }
        }
        let mmolPerMgdl = NSDecimalNumber(decimal: GlucoseUnits.exchangeRate).doubleValue
        func glucose(_ mgdl: Double?) -> Double? {
            mgdl.map { units == .mmolL ? $0 * mmolPerMgdl : $0 }
        }
        func a1c(_ estimate: Double?) -> Double? {
            estimate.map { hbA1cUnit == .mmolPerMol ? GlucoseStatsEngine.ifcc(fromPercent: $0) : $0 }
        }

        let storageDays = total.firstReading.flatMap { first in
            total.lastReading.map { $0.timeIntervalSince(first) / TimeInterval.days(1) }
        }

        return GlucoseNumbers(
            tir: durations(percent([.inRange])),
            hypos: durations(percent([.veryLow, .low])),
            hypers: durations(percent([.high, .veryHigh])),
            euglycemic: durations { $0.titrFraction * 100 },
            averages: Averages(
                Average: durations { glucose($0.mean) },
                Median: durations { glucose($0.histogram.quantile(0.5)) }
            ),
            hbA1c: durations { a1c($0.eA1cPercent) },
            gmi: durations { a1c($0.gmiPercent) },
            variance: Variance(
                SD: durations { glucose($0.sd) },
                CV: durations(\.cv)
            ),
            a1cUnit: hbA1cUnit == .mmolPerMol ? "mmol/mol" : "%",
            readings: day.histogram.readingCount,
            storageDays: Self.roundDecimal(Decimal(storageDays ?? 0), 1)
        )
    }

    private static func loops(_ loops: [LoopStatRecord]) -> Loops {
        // First date
        let previous = loops.last?.end ?? Date()
        // Last date (recent)
        let current = loops.first?.start ?? Date()
        // Total time in days
        let totalTime = current.timeIntervalSince(previous) / 8.64E4

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

    private static func roundDecimal(_ decimal: Decimal, _ digits: Double) -> Decimal {
        let rounded = round(Double(decimal) * pow(10, digits)) / pow(10, digits)
        return Decimal(rounded)
    }

    private static func medianCalculationDouble(array: [Double]) -> Double {
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
}
