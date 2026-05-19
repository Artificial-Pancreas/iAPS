import CoreData
import Foundation
import SwiftDate
import SwiftUI
import Swinject

extension Stat {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!

        // Settings
        @Published var highLimit: Decimal = 10 / 0.0555
        @Published var lowLimit: Decimal = 4 / 0.0555
        @Published var overrideUnit: Bool = false
        @Published var layingChart: Bool = false
        @Published var units: GlucoseUnits = .mmolL

        // Selected view and chart types
        @Published var selectedView: StatisticViewType = .overview
        @Published var selectedGlucoseChartType: GlucoseChartType = .percentileByTime
        @Published var selectedInsulinChartType: InsulinChartType = .totalDailyDose
        @Published var selectedLoopingChartType: LoopingChartType = .loopingPerformance
        @Published var selectedMealChartType: MealChartType = .totalMeals

        // Selected intervals
        @Published var selectedIntervalForGlucoseStats: StatsTimeIntervalWithToday = .today
        @Published var selectedIntervalForInsulinStats: StatsTimeIntervalWithToday = .today
        @Published var selectedIntervalForLoopStats: StatsTimeIntervalWithToday = .today
        @Published var selectedIntervalForMealStats: StatsTimeIntervalWithToday = .today

        // Computed data caches
        @Published var dailyTDDStats: [TDDStats] = []
        @Published var hourlyTDDStats: [TDDStats] = []
        @Published var dailyBolusStats: [BolusStats] = []
        @Published var hourlyBolusStats: [BolusStats] = []
        @Published var dailyMealStats: [MealStats] = []
        @Published var hourlyMealStats: [MealStats] = []
        @Published var last24hHourlyTDDStats: [TDDStats] = []
        @Published var last24hHourlyBolusStats: [BolusStats] = []
        @Published var loopStats: [LoopStatsProcessedData] = []
        @Published var hourlyStats: [HourlyStats] = []
        @Published var agpToday: [AGPSlot] = []
        @Published var agpDay: [AGPSlot] = []
        @Published var agpWeek: [AGPSlot] = []
        @Published var agpMonth: [AGPSlot] = []
        @Published var agpTotal: [AGPSlot] = []
        @Published var distributionToday: [GlucoseDistributionSlot] = []
        @Published var distributionDay: [GlucoseDistributionSlot] = []
        @Published var distributionWeek: [GlucoseDistributionSlot] = []
        @Published var distributionMonth: [GlucoseDistributionSlot] = []
        @Published var distributionTotal: [GlucoseDistributionSlot] = []

        // Insulin summary (mirrors HomeStateModel for consistency with HomeRootView)
        @Published var neg: Int = 0
        @Published var tddChange: Decimal = 0
        @Published var tddAverage: Decimal = 0
        @Published var tddYesterday: Decimal = 0
        @Published var tdd2DaysAgo: Decimal = 0
        @Published var tdd3DaysAgo: Decimal = 0
        @Published var tddActualAverage: Decimal = 0

        override func subscribe() {
            highLimit = settingsManager.settings.high
            lowLimit = settingsManager.settings.low
            units = settingsManager.settings.units
            overrideUnit = settingsManager.settings.overrideHbA1cUnit
            layingChart = settingsManager.settings.oneDimensionalGraph

            setupInsulinStats()
            setupInsulinSummary()
            setupMealStats()
            setupAGP()
        }

        // MARK: - Insulin Summary (mirrors HomeStateModel.setupData)

        /// Computes the daily TDD summary values exactly the same way HomeRootView does,
        /// so the values shown in the Stat insulin summary card always match the home view.
        private func setupInsulinSummary() {
            let tdds = CoreDataStorage().fetchTDD(interval: DateFilter().tenDays)
            let yesterday = (tdds.first(where: {
                ($0.timestamp ?? .distantFuture) <= Date().addingTimeInterval(-24.hours.timeInterval)
            })?.tdd ?? 0) as Decimal
            let oneDaysAgo = CoreDataStorage().fetchTDD(interval: DateFilter().today).last

            tddChange = ((tdds.first?.tdd ?? 0) as Decimal) - yesterday
            tddYesterday = (oneDaysAgo?.tdd ?? 0) as Decimal
            tdd2DaysAgo = (tdds.first(where: {
                ($0.timestamp ?? .distantFuture) <= (oneDaysAgo?.timestamp ?? .distantPast)
                    .addingTimeInterval(-1.days.timeInterval)
            })?.tdd ?? 0) as Decimal
            tdd3DaysAgo = (tdds.first(where: {
                ($0.timestamp ?? .distantFuture) <= (oneDaysAgo?.timestamp ?? .distantPast)
                    .addingTimeInterval(-2.days.timeInterval)
            })?.tdd ?? 0) as Decimal

            if let dyn = provider.dynamicVariables {
                tddAverage = ((tdds.first?.tdd ?? 0) as Decimal) - dyn.average_total_data
                tddActualAverage = dyn.average_total_data
            }

            if let iobData = provider.reasons() {
                neg = iobData.filter { $0.iob < 0 }.count * 5
            }
        }

        // MARK: - Date Filter

        func filterDate(for interval: StatsTimeIntervalWithToday) -> NSDate {
            switch interval {
            case .today: return Calendar.current.startOfDay(for: Date()) as NSDate
            case .day: return Date().addingTimeInterval(-24 * 3600) as NSDate
            case .week: return Date().addingTimeInterval(-7 * 24 * 3600) as NSDate
            case .month: return Date().addingTimeInterval(-30 * 24 * 3600) as NSDate
            case .total: return Date().addingTimeInterval(-90 * 24 * 3600) as NSDate
            }
        }

        func filterDate(for interval: StatsTimeInterval) -> NSDate {
            switch interval {
            case .day: return Date().addingTimeInterval(-24 * 3600) as NSDate
            case .week: return Date().addingTimeInterval(-7 * 24 * 3600) as NSDate
            case .month: return Date().addingTimeInterval(-30 * 24 * 3600) as NSDate
            case .total: return Date().addingTimeInterval(-90 * 24 * 3600) as NSDate
            }
        }

        // MARK: - Filtered Data Accessors

        /// Filters daily TDD stats to the selected time interval
        var filteredDailyTDDStats: [TDDStats] {
            let cutoff = filterDate(for: selectedIntervalForInsulinStats) as Date
            return dailyTDDStats.filter { $0.date >= cutoff }
        }

        /// Filters daily bolus stats to the selected time interval
        var filteredDailyBolusStats: [BolusStats] {
            let cutoff = filterDate(for: selectedIntervalForInsulinStats) as Date
            return dailyBolusStats.filter { $0.date >= cutoff }
        }

        /// Filters daily meal stats to the selected time interval
        var filteredDailyMealStats: [MealStats] {
            let cutoff = filterDate(for: selectedIntervalForMealStats) as Date
            return dailyMealStats.filter { $0.date >= cutoff }
        }

        /// Hourly meal stats filtered to today only (from midnight), with all 24h slots filled
        var todayHourlyMealStats: [MealStats] {
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: Date())
            let todayData = hourlyMealStats.filter { $0.date >= midnight }

            // Build a full 24h timeline with empty slots
            var hourlyMap: [Date: (carbs: Double, fat: Double, protein: Double)] = [:]
            for h in 0 ..< 24 {
                if let hourDate = calendar.date(byAdding: .hour, value: h, to: midnight) {
                    hourlyMap[hourDate] = (0, 0, 0)
                }
            }
            // Overlay actual data
            for stat in todayData {
                let hour = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: stat.date))!
                hourlyMap[hour] = (stat.carbs, stat.fat, stat.protein)
            }
            return hourlyMap
                .map { MealStats(date: $0.key, carbs: $0.value.carbs, fat: $0.value.fat, protein: $0.value.protein) }
                .sorted { $0.date < $1.date }
        }

        // MARK: - Insulin Setup (TDD + Bolus Distribution)

        /// Computes both TDD and Bolus Distribution stats from a single source (InsulinDistribution).
        /// This guarantees that TDD total == Bolus total + Basal total at all times.
        ///
        /// For "today", the values from CoreData represent a rolling 24h window (not calendar-day),
        /// so we override today's entry with the actually-delivered amount since midnight, computed
        /// directly from PumpHistoryStorage.
        private func setupInsulinStats() {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            let request = NSFetchRequest<InsulinDistribution>(entityName: "InsulinDistribution")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            request.predicate = NSPredicate(format: "date > %@", Date().addingTimeInterval(-90 * 24 * 3600) as NSDate)

            guard let results = try? context.fetch(request) else { return }

            let calendar = Calendar.current
            let todayStart = calendar.startOfDay(for: Date())

            // InsulinDistribution records are saved every loop cycle (~5 min) by saveTDD().
            // Each record stores a CUMULATIVE rolling 24h value of bolus and tempBasal.
            // We take the LATEST record per day (by timestamp) and read both bolus & basal
            // from that SAME record. This guarantees consistency: TDD = bolus + basal.
            var dailyLatest: [Date: (timestamp: Date, bolus: Double, basal: Double)] = [:]
            for record in results {
                guard let date = record.date else { continue }
                let day = calendar.startOfDay(for: date)
                let bolus = Double(truncating: record.bolus ?? 0)
                let basal = Double(truncating: record.tempBasal ?? 0)
                    + Double(truncating: record.scheduledBasal ?? 0)
                if let existing = dailyLatest[day] {
                    if date > existing.timestamp {
                        dailyLatest[day] = (date, bolus, basal)
                    }
                } else {
                    dailyLatest[day] = (date, bolus, basal)
                }
            }

            // Override today's entry with the actually delivered amount since midnight,
            // computed directly from pump history (not the rolling 24h cumulative value).
            let increment = Double(settingsManager.preferences.bolusIncrement)
            let pumpEvents = pumpHistoryStorage?.recent() ?? []
            let todayActual = TotalDailyDose().insulinToday(pumpEvents, increment: increment)
            let todayBolus = Double(truncating: todayActual.bolus as NSDecimalNumber)
            let todayBasal = Double(truncating: todayActual.basal as NSDecimalNumber)
            dailyLatest[todayStart] = (Date(), todayBolus, todayBasal)

            let sortedDaily = dailyLatest.sorted { $0.key < $1.key }
            dailyBolusStats = sortedDaily.map {
                BolusStats(date: $0.key, manualBolus: $0.value.bolus, smb: 0, external: $0.value.basal)
            }
            dailyTDDStats = sortedDaily.map {
                TDDStats(date: $0.key, amount: $0.value.bolus + $0.value.basal)
            }

            // Hourly stats (for "Day" view): build directly from today's pump history events
            // so values reflect actually-delivered amounts per hour (not cumulative deltas).
            var hourlyMap: [Date: (bolus: Double, basal: Double)] = [:]

            // Initialize all 24 hours of today so the chart shows a continuous timeline
            for h in 0 ..< 24 {
                if let hourDate = calendar.date(byAdding: .hour, value: h, to: todayStart) {
                    hourlyMap[hourDate] = (0, 0)
                }
            }

            // Sum boluses per hour from pump events
            let todayEvents = pumpEvents.filter { $0.timestamp >= todayStart }
            for event in todayEvents where event.type == .bolus {
                let hour = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: event.timestamp))!
                let amount = Double(truncating: (event.amount ?? 0) as NSDecimalNumber)
                hourlyMap[hour, default: (0, 0)].bolus += amount
            }

            // Distribute today's basal proportionally across hours that have elapsed.
            // (Hour-by-hour temp basal reconstruction is complex; proportional split keeps
            //  the daily total accurate while giving a reasonable per-hour visualization.)
            let now = Date()
            let elapsedHours = max(1, calendar.dateComponents([.hour], from: todayStart, to: now).hour ?? 0) + 1
            if todayBasal > 0, elapsedHours > 0 {
                let perHour = todayBasal / Double(elapsedHours)
                for h in 0 ..< elapsedHours {
                    if let hourDate = calendar.date(byAdding: .hour, value: h, to: todayStart) {
                        hourlyMap[hourDate, default: (0, 0)].basal += perHour
                    }
                }
            }

            let sortedHourly = hourlyMap.sorted { $0.key < $1.key }
            hourlyBolusStats = sortedHourly.map {
                BolusStats(date: $0.key, manualBolus: $0.value.bolus, smb: 0, external: $0.value.basal)
            }
            hourlyTDDStats = sortedHourly.map {
                TDDStats(date: $0.key, amount: $0.value.bolus + $0.value.basal)
            }

            // Last 24h hourly stats (for "Day" picker – covers yesterday evening through now)
            let dayAgoStart = now.addingTimeInterval(-24 * 3600)
            let dayAgoHourStart = calendar.date(from: calendar.dateComponents(
                [.year, .month, .day, .hour], from: dayAgoStart
            ))!

            var last24hMap: [Date: (bolus: Double, basal: Double)] = [:]
            // Initialize all 24 hour-slots
            for h in 0 ..< 24 {
                if let hourDate = calendar.date(byAdding: .hour, value: h, to: dayAgoHourStart) {
                    last24hMap[hourDate] = (0, 0)
                }
            }

            // Sum boluses from pump events in the last 24h
            let last24hEvents = pumpEvents.filter { $0.timestamp >= dayAgoStart }
            for event in last24hEvents where event.type == .bolus {
                let hour = calendar.date(from: calendar.dateComponents(
                    [.year, .month, .day, .hour], from: event.timestamp
                ))!
                let amount = Double(truncating: (event.amount ?? 0) as NSDecimalNumber)
                last24hMap[hour, default: (0, 0)].bolus += amount
            }

            // Distribute basal: use yesterday's daily basal for pre-midnight hours,
            // today's basal for post-midnight hours
            let yesterdayStart = calendar.startOfDay(for: dayAgoStart)
            let yesterdayDaily = dailyLatest[yesterdayStart]
            let yesterdayBasal = yesterdayDaily?.basal ?? 0
            // Hours from yesterday (dayAgoHourStart until midnight)
            let preHourCount = max(1, calendar.dateComponents([.hour], from: dayAgoHourStart, to: todayStart).hour ?? 0)
            if yesterdayBasal > 0 {
                let perHour = yesterdayBasal / 24.0
                for h in 0 ..< preHourCount {
                    if let hourDate = calendar.date(byAdding: .hour, value: h, to: dayAgoHourStart) {
                        last24hMap[hourDate, default: (0, 0)].basal += perHour
                    }
                }
            }
            // Hours from today (midnight until now)
            if todayBasal > 0, elapsedHours > 0 {
                let perHour = todayBasal / Double(elapsedHours)
                for h in 0 ..< elapsedHours {
                    if let hourDate = calendar.date(byAdding: .hour, value: h, to: todayStart) {
                        last24hMap[hourDate, default: (0, 0)].basal += perHour
                    }
                }
            }

            let sortedLast24h = last24hMap.sorted { $0.key < $1.key }
            last24hHourlyBolusStats = sortedLast24h.map {
                BolusStats(date: $0.key, manualBolus: $0.value.bolus, smb: 0, external: $0.value.basal)
            }
            last24hHourlyTDDStats = sortedLast24h.map {
                TDDStats(date: $0.key, amount: $0.value.bolus + $0.value.basal)
            }
        }

        // MARK: - Meal Setup

        private func setupMealStats() {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            let request = NSFetchRequest<Carbohydrates>(entityName: "Carbohydrates")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            request.predicate = NSPredicate(format: "date > %@", Date().addingTimeInterval(-90 * 24 * 3600) as NSDate)

            guard let results = try? context.fetch(request) else { return }

            let calendar = Calendar.current

            // Daily
            var dailyMap: [Date: (carbs: Double, fat: Double, protein: Double)] = [:]
            for record in results {
                guard let date = record.date else { continue }
                let day = calendar.startOfDay(for: date)
                dailyMap[day, default: (0, 0, 0)].carbs += Double(truncating: record.carbs ?? 0)
                dailyMap[day, default: (0, 0, 0)].fat += Double(truncating: record.fat ?? 0)
                dailyMap[day, default: (0, 0, 0)].protein += Double(truncating: record.protein ?? 0)
            }
            dailyMealStats = dailyMap
                .map { MealStats(date: $0.key, carbs: $0.value.carbs, fat: $0.value.fat, protein: $0.value.protein) }
                .sorted { $0.date < $1.date }

            // Hourly (last 24h with all hour slots filled)
            let now = Date()
            let dayAgo = now.addingTimeInterval(-24 * 3600)
            let dayAgoHourStart = calendar.date(from: calendar.dateComponents(
                [.year, .month, .day, .hour], from: dayAgo
            ))!

            var hourlyMap: [Date: (carbs: Double, fat: Double, protein: Double)] = [:]
            // Initialize all 24 hour slots
            for h in 0 ..< 24 {
                if let hourDate = calendar.date(byAdding: .hour, value: h, to: dayAgoHourStart) {
                    hourlyMap[hourDate] = (0, 0, 0)
                }
            }
            // Overlay actual data
            for record in results {
                guard let date = record.date, date > dayAgo else { continue }
                let hour = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date))!
                hourlyMap[hour, default: (0, 0, 0)].carbs += Double(truncating: record.carbs ?? 0)
                hourlyMap[hour, default: (0, 0, 0)].fat += Double(truncating: record.fat ?? 0)
                hourlyMap[hour, default: (0, 0, 0)].protein += Double(truncating: record.protein ?? 0)
            }
            hourlyMealStats = hourlyMap
                .map { MealStats(date: $0.key, carbs: $0.value.carbs, fat: $0.value.fat, protein: $0.value.protein) }
                .sorted { $0.date < $1.date }
        }

        // MARK: - AGP Setup

        private func setupAGP() {
            let context = CoreDataStack.shared.persistentContainer.viewContext
            let request = NSFetchRequest<Readings>(entityName: "Readings")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.predicate = NSPredicate(
                format: "glucose > 0 AND date > %@",
                Date().addingTimeInterval(-90 * 24 * 3600) as NSDate
            )

            guard let allReadings = try? context.fetch(request) else { return }

            let convert = units == .mmolL ? 0.0555 : 1.0
            let todayCutoff = Calendar.current.startOfDay(for: Date())
            let dayCutoff = Date().addingTimeInterval(-24 * 3600)
            let weekCutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            let monthCutoff = Date().addingTimeInterval(-30 * 24 * 3600)

            let todayReadings = allReadings.filter { ($0.date ?? .distantPast) >= todayCutoff }
            let dayReadings = allReadings.filter { ($0.date ?? .distantPast) >= dayCutoff }
            let weekReadings = allReadings.filter { ($0.date ?? .distantPast) >= weekCutoff }
            let monthReadings = allReadings.filter { ($0.date ?? .distantPast) >= monthCutoff }

            agpToday = computeChronologicalAGPSlots(from: todayReadings, start: todayCutoff, convert: convert)
            agpDay = computeChronologicalAGPSlots(from: dayReadings, start: dayCutoff, convert: convert)
            agpWeek = computeAGPSlots(from: weekReadings, convert: convert)
            agpMonth = computeAGPSlots(from: monthReadings, convert: convert)
            agpTotal = computeAGPSlots(from: allReadings, convert: convert)

            distributionToday = computeHourlyDistributionSlots(
                from: todayReadings, referenceStart: todayCutoff
            )
            distributionDay = computeHourlyDistributionSlots(
                from: dayReadings, referenceStart: dayCutoff
            )
            distributionWeek = computeDistributionSlots(from: weekReadings)
            distributionMonth = computeDistributionSlots(from: monthReadings)
            distributionTotal = computeDistributionSlots(from: allReadings)
        }

        /// Computes AGP-like slots chronologically (actual timestamps, not time-of-day mapped).
        /// Used for Today/Day where we want to see the real timeline, not a 00–24 overlay.
        private func computeChronologicalAGPSlots(
            from readings: [Readings],
            start: Date,
            convert: Double
        ) -> [AGPSlot] {
            let calendar = Calendar.current
            let hourStart = calendar.date(from: calendar.dateComponents(
                [.year, .month, .day, .hour], from: start
            ))!

            // Group readings by actual hour
            var hourlyValues: [Date: [Double]] = [:]
            for h in 0 ..< 24 {
                if let hourDate = calendar.date(byAdding: .hour, value: h, to: hourStart) {
                    hourlyValues[hourDate] = []
                }
            }
            for reading in readings {
                guard let date = reading.date else { continue }
                let hour = calendar.date(from: calendar.dateComponents(
                    [.year, .month, .day, .hour], from: date
                ))!
                hourlyValues[hour, default: []].append(Double(reading.glucose) * convert)
            }

            // Only include hours that have actual readings — skip future/empty hours
            var result: [AGPSlot] = []
            let sortedHours = hourlyValues.sorted { $0.key < $1.key }
            for (idx, entry) in sortedHours.enumerated() {
                let values = entry.value
                guard !values.isEmpty else { continue }
                let sorted = values.sorted()
                result.append(AGPSlot(
                    id: idx, date: entry.key,
                    p10: Self.percentile(sorted, 0.10),
                    p25: Self.percentile(sorted, 0.25),
                    p50: Self.percentile(sorted, 0.50),
                    p75: Self.percentile(sorted, 0.75),
                    p90: Self.percentile(sorted, 0.90)
                ))
            }

            return result
        }

        private func computeAGPSlots(from readings: [Readings], convert: Double) -> [AGPSlot] {
            let calendar = Calendar.current
            let refDay = calendar.startOfDay(for: Date())

            // Group readings into 30-minute slots by time of day
            var slotValues: [Int: [Double]] = [:]
            for reading in readings {
                guard let date = reading.date else { continue }
                let comps = calendar.dateComponents([.hour, .minute], from: date)
                let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                let slot = (minuteOfDay / 30) * 30
                slotValues[slot, default: []].append(Double(reading.glucose) * convert)
            }

            // Build all 48 slots
            var result: [AGPSlot] = []
            for slotMinute in stride(from: 0, to: 1440, by: 30) {
                guard let slotDate = calendar.date(byAdding: .minute, value: slotMinute, to: refDay) else { continue }
                if let values = slotValues[slotMinute], !values.isEmpty {
                    let sorted = values.sorted()
                    result.append(AGPSlot(
                        id: slotMinute,
                        date: slotDate,
                        p10: Self.percentile(sorted, 0.10),
                        p25: Self.percentile(sorted, 0.25),
                        p50: Self.percentile(sorted, 0.50),
                        p75: Self.percentile(sorted, 0.75),
                        p90: Self.percentile(sorted, 0.90)
                    ))
                } else {
                    // Empty slot — will be filled by interpolation
                    result.append(AGPSlot(id: slotMinute, date: slotDate, p10: 0, p25: 0, p50: 0, p75: 0, p90: 0))
                }
            }

            // Interpolate empty slots from neighbors
            for i in 0 ..< result.count where slotValues[result[i].id] == nil {
                let prev = (0 ..< i).last(where: { slotValues[result[$0].id] != nil }).map { result[$0] }
                let next = ((i + 1) ..< result.count).first(where: { slotValues[result[$0].id] != nil }).map { result[$0] }
                let slot = result[i]
                if let p = prev, let n = next, n.id != p.id {
                    let t = Double(slot.id - p.id) / Double(n.id - p.id)
                    result[i] = AGPSlot(
                        id: slot.id, date: slot.date,
                        p10: p.p10 + (n.p10 - p.p10) * t,
                        p25: p.p25 + (n.p25 - p.p25) * t,
                        p50: p.p50 + (n.p50 - p.p50) * t,
                        p75: p.p75 + (n.p75 - p.p75) * t,
                        p90: p.p90 + (n.p90 - p.p90) * t
                    )
                } else if let p = prev {
                    result[i] = AGPSlot(
                        id: slot.id,
                        date: slot.date,
                        p10: p.p10,
                        p25: p.p25,
                        p50: p.p50,
                        p75: p.p75,
                        p90: p.p90
                    )
                } else if let n = next {
                    result[i] = AGPSlot(
                        id: slot.id,
                        date: slot.date,
                        p10: n.p10,
                        p25: n.p25,
                        p50: n.p50,
                        p75: n.p75,
                        p90: n.p90
                    )
                }
            }

            return result
        }

        /// Computes glucose distribution (% time in each range) per hour for Today/Day views.
        private func computeHourlyDistributionSlots(
            from readings: [Readings],
            referenceStart: Date
        ) -> [GlucoseDistributionSlot] {
            let calendar = Calendar.current
            let hourStart = calendar.date(from: calendar.dateComponents(
                [.year, .month, .day, .hour], from: referenceStart
            ))!

            // Initialize all 24 hour slots
            var hourlyValues: [Date: [Int16]] = [:]
            for h in 0 ..< 24 {
                if let hourDate = calendar.date(byAdding: .hour, value: h, to: hourStart) {
                    hourlyValues[hourDate] = []
                }
            }

            // Group readings into hours
            for reading in readings {
                guard let date = reading.date else { continue }
                let hour = calendar.date(from: calendar.dateComponents(
                    [.year, .month, .day, .hour], from: date
                ))!
                hourlyValues[hour, default: []].append(reading.glucose)
            }

            return hourlyValues.map { hour, values in
                guard !values.isEmpty else {
                    return GlucoseDistributionSlot(
                        id: hour, date: hour,
                        veryLow: 0, low: 0, inRange: 0, high: 0, veryHigh: 0,
                        totalReadings: 0
                    )
                }
                let total = Double(values.count)
                let veryLow = Double(values.filter { $0 < 54 }.count) / total * 100
                let low = Double(values.filter { $0 >= 54 && $0 < 70 }.count) / total * 100
                let inRange = Double(values.filter { $0 >= 70 && $0 <= 180 }.count) / total * 100
                let high = Double(values.filter { $0 > 180 && $0 <= 250 }.count) / total * 100
                let veryHigh = Double(values.filter { $0 > 250 }.count) / total * 100
                return GlucoseDistributionSlot(
                    id: hour, date: hour,
                    veryLow: veryLow, low: low, inRange: inRange, high: high, veryHigh: veryHigh,
                    totalReadings: values.count
                )
            }.sorted { $0.date < $1.date }
        }

        /// Computes glucose distribution (% time in each range) per calendar day.
        /// Thresholds are in mg/dL: very low <54, low 54–70, in range 70–180, high 180–250, very high >250.
        private func computeDistributionSlots(from readings: [Readings]) -> [GlucoseDistributionSlot] {
            let calendar = Calendar.current

            // Group readings by calendar day
            var dayValues: [Date: [Int16]] = [:]
            for reading in readings {
                guard let date = reading.date else { continue }
                let day = calendar.startOfDay(for: date)
                dayValues[day, default: []].append(reading.glucose)
            }

            return dayValues.map { day, values in
                let total = Double(values.count)
                let veryLow = Double(values.filter { $0 < 54 }.count) / total * 100
                let low = Double(values.filter { $0 >= 54 && $0 < 70 }.count) / total * 100
                let inRange = Double(values.filter { $0 >= 70 && $0 <= 180 }.count) / total * 100
                let high = Double(values.filter { $0 > 180 && $0 <= 250 }.count) / total * 100
                let veryHigh = Double(values.filter { $0 > 250 }.count) / total * 100
                return GlucoseDistributionSlot(
                    id: day, date: day,
                    veryLow: veryLow, low: low, inRange: inRange, high: high, veryHigh: veryHigh,
                    totalReadings: values.count
                )
            }.sorted { $0.date < $1.date }
        }

        private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
            let n = sorted.count
            guard n > 0 else { return 0 }
            let index = p * Double(n - 1)
            let lower = Int(floor(index))
            let upper = min(Int(ceil(index)), n - 1)
            if lower == upper { return sorted[lower] }
            let frac = index - Double(lower)
            return sorted[lower] * (1 - frac) + sorted[upper] * frac
        }
    }
}
