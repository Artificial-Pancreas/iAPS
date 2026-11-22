import CoreGraphics
import Foundation

/// A read of a report's optional data: its value, or that it couldn't be read (the block says so, the report is
/// still made).
enum ReportRead<Value: Sendable & Equatable>: Sendable, Equatable {
    case value(Value)
    case failed

    var value: Value? {
        if case let .value(value) = self { return value }
        return nil
    }
}

/// A page of a report: a page of a part in one unit.
struct ReportPage: Sendable, Equatable {
    let part: ReportPart
    let units: GlucoseUnits
    /// points
    let size: CGSize
    /// the page of the part's pages (in this unit), from 0
    var index = 0
}

/// A consensus goal for CGM data (Battelino et al. 2019, adults), judged on the exact value: the fraction of the time,
/// the CV, never the rounded number printed beside it.
enum ReportGoal: CaseIterable, Sendable, Hashable {
    /// in range 70–180: more than 70%
    case inRange
    /// below 70 (low and very low): less than 4%
    case below70
    /// below 54: less than 1%
    case below54
    /// above 180 (high and very high): less than 25%
    case above180
    /// above 250: less than 5%
    case above250
    /// CV: at most 36%
    case cv
    /// days with data: at least 14
    case days
    /// CGM active: at least 70%
    case cgmActive

    enum Comparison: Sendable {
        case moreThan
        case lessThan
        case atMost
        case atLeast
    }

    var threshold: Int {
        switch self {
        case .inRange: return 70
        case .below70: return 4
        case .below54: return 1
        case .above180: return 25
        case .above250: return 5
        case .cv: return 36
        case .days: return 14
        case .cgmActive: return 70
        }
    }

    var comparison: Comparison {
        switch self {
        case .inRange: return .moreThan
        case .above180,
             .above250,
             .below54,
             .below70: return .lessThan
        case .cv: return .atMost
        case .cgmActive,
             .days: return .atLeast
        }
    }

    /// a percent; the days goal is a count
    var isPercent: Bool { self != .days }

    func isMet(_ value: Double) -> Bool {
        let threshold = Double(self.threshold)
        switch comparison {
        case .moreThan: return value > threshold
        case .lessThan: return value < threshold
        case .atMost: return value <= threshold
        case .atLeast: return value >= threshold
        }
    }

    /// The exact value the goal is judged on: the percent of the covered time in the bands (summed for below 70 and
    /// above 180), the CV, the days with data, the covered share of the period. nil without data.
    /// - Parameter summary: on standard bands (`Stat.ReportBuilder.standardBands`)
    func value(_ summary: GlucoseSummary) -> Double? {
        guard !summary.isEmpty else { return nil }
        func percent(_ bands: GlucoseBand...) -> Double {
            bands.reduce(0) { $0 + summary.fraction($1) } * 100
        }
        switch self {
        case .inRange: return percent(.inRange)
        case .below70: return percent(.veryLow, .low)
        case .below54: return percent(.veryLow)
        case .above180: return percent(.high, .veryHigh)
        case .above250: return percent(.veryHigh)
        case .cv: return summary.cv
        case .days: return Double(summary.daysWithData)
        case .cgmActive: return summary.coverage * 100
        }
    }

    func isMet(_ summary: GlucoseSummary) -> Bool? {
        value(summary).map { isMet($0) }
    }
}

/// A day's readings as Daily charts draw them (`Stat.Provider.trace` of the day), with the day's summary.
struct ReportDayTrace: Sendable, Equatable {
    /// oldest -> newest
    let points: [GlucosePoint]
    let summary: GlucoseSummary
}

/// A read of a report that failed without failing the report: the pages it feeds say so.
enum ReportReadFailure: String, Sendable, Hashable {
    /// the Insulin tab's days
    case insulin
    /// the Meals tab's days
    case meals
    /// the window's pump events (Daily charts' boluses and basal)
    case pumpEvents
}

/// The provider calls a report makes (`Stat.Provider`'s; tests pass a fake).
protocol ReportDataSource: Sendable {
    func beginSession() async
    func endSession() async
    /// the period's profile and summary (`Stat.Provider.agp`)
    func reportProfile(_ period: StatsPeriod, bands: StatsBands) async -> Stat.AGPResult
    /// the Insulin tab's period: its summary and its days
    func reportInsulin(_ period: StatsPeriod) async throws -> InsulinPeriod
    /// the Meals tab's period: its summary and its days
    func reportMeals(_ period: StatsPeriod, factor: Double) async throws -> MealPeriod
    /// the period's day aggregates, as "In range by day" reads them (`GlucoseStatistics.periodDays`); Weekly's 13
    /// weeks too, read once for every unit printed
    func reportDays(_ period: StatsPeriod) async -> PeriodDays
    /// a day's readings, as the Day view reads them (`Stat.Provider.trace`)
    func reportTrace(day: Date, bands: StatsBands) async -> ReportDayTrace
    /// the pump events, coverage and basal schedules of a window, read once (what `InsulinStatsEngine.timeline` takes)
    /// - Parameter now: the report's clock: nothing after it is read
    func reportInsulinInput(_ window: DateInterval, now: Date) async throws -> InsulinInput
    /// By hour's result (`Stat.Provider.hourOfDay`)
    func reportHourOfDay(_ period: StatsPeriod, bands: StatsBands) async -> Stat.HourOfDayResult
    /// By weekday's result: whole weeks to yesterday (`Stat.Provider.weekday`)
    func reportWeekday(_ period: StatsPeriod, bands: StatsBands) async -> Stat.WeekdayResult
    /// Good & bad days' result with its factor rows (`Stat.Provider.goodBadDays`)
    func reportGoodBadDays(_ period: StatsPeriod, bands: StatsBands, allowOneMinuteLoop: Bool) async -> Stat.GoodBadDaysData
    /// the Patches topic's result for the period (`Stat.Provider.patches`)
    /// - Parameters: the report's clock and calendar
    func reportPatches(
        _ period: StatsPeriod,
        bands: StatsBands,
        input: ReportPatchesInput,
        now: Date,
        calendar: Calendar
    ) async throws -> Stat.PatchesResult
    /// the CGM topic's result for the period, computed for the report (`Stat.Provider.cgmUncached`)
    /// - Parameters: the report's clock and calendar
    func reportCGM(_ period: StatsPeriod, now: Date, calendar: Calendar) async throws -> Stat.CGMResult
}

extension Stat.Provider: ReportDataSource {
    /// The Patches topic's result on the report's bands, computed on its own: the screen's kept sessions
    /// (`patchesCache`, on the user's range) are neither used nor dropped, so the Patches screen is as it was when the
    /// report is done. The same reads and engine calls as `patches`, every session computed (as that one's first read).
    func reportPatches(
        _ period: StatsPeriod,
        bands: StatsBands,
        input: ReportPatchesInput,
        now: Date,
        calendar: Calendar
    ) async throws -> Stat.PatchesResult {
        let storage = CoreDataStorage()
        let records = try await Self.pumpSessions(now: now, storage: storage)
        let sessions = PatchStatsEngine.sessions(records)
        let inUseID = PatchStatsEngine.inUse(sessions, deliveringPlugin: input.deliveringPlugin)?.id
        var computed: [PatchStats] = []
        for run in StatsIntervals.runs(Array(sessions.indices)) {
            let runSessions = run.map { sessions[$0] }
            let patchInput = try await Self.patchInput(runSessions, now: now, storage: storage)
            try Task.checkCancellation()
            computed += PatchStatsEngine.stats(
                runSessions,
                input: patchInput,
                bands: bands,
                allowOneMinuteLoop: input.allowOneMinuteLoop,
                inUseID: inUseID,
                now: now,
                calendar: calendar
            )
        }
        let stats = PatchStatsEngine.assembled(sessions, reused: [:], computed: computed)
        return Self.patchesResult(stats, period: period, currentPlugin: input.currentPlugin, now: now, calendar: calendar)
    }

    func reportCGM(_ period: StatsPeriod, now: Date, calendar: Calendar) async throws -> Stat.CGMResult {
        try await cgmUncached(period, now: now, calendar: calendar)
    }

    func reportProfile(_ period: StatsPeriod, bands: StatsBands) async -> Stat.AGPResult {
        await agp(period, bands: bands)
    }

    func reportInsulin(_ period: StatsPeriod) async throws -> InsulinPeriod {
        try await insulin(period).insulin
    }

    func reportMeals(_ period: StatsPeriod, factor: Double) async throws -> MealPeriod {
        try await meals(period, factor: factor).meals
    }

    func reportDays(_ period: StatsPeriod) async -> PeriodDays {
        await periodDays(period)
    }

    func reportTrace(day: Date, bands: StatsBands) async -> ReportDayTrace {
        let result = await trace(.day(day), bands: bands)
        return ReportDayTrace(
            points: result.points.map { GlucosePoint(time: $0.time, mgdl: Int16(clamping: $0.mgdl)) },
            summary: result.summary
        )
    }

    func reportInsulinInput(_ window: DateInterval, now: Date) async throws -> InsulinInput {
        try await Stat.ReportBuilder.insulinInput(window, now: now, source: CoreDataStorage())
    }

    func reportHourOfDay(_ period: StatsPeriod, bands: StatsBands) async -> Stat.HourOfDayResult {
        await hourOfDay(period, bands: bands)
    }

    func reportWeekday(_ period: StatsPeriod, bands: StatsBands) async -> Stat.WeekdayResult {
        await weekday(period, bands: bands)
    }

    func reportGoodBadDays(_ period: StatsPeriod, bands: StatsBands, allowOneMinuteLoop: Bool) async -> Stat.GoodBadDaysData {
        await goodBadDays(period, bands: bands, allowOneMinuteLoop: allowOneMinuteLoop)
    }
}

extension Stat {
    /// What a report is made from: the choices, and what the user's settings give.
    struct ReportRequest: Sendable, Equatable {
        /// one of `ReportOptions.periods`
        let period: StatsPeriod
        /// in the report's order
        let parts: [ReportPart]
        /// the units printed, in the pages' order (`ReportUnits.printed`): the numbers are computed on the first one's
        /// bands
        let units: [GlucoseUnits]
        /// the user's (the existing setting), on every page
        let hbA1cUnit: HbA1cUnit
        let paper: ReportPaper
        let summary: ReportOptions.SummarySettings
        let daysTable: ReportOptions.DaysTableSettings
        let dailyCharts: ReportOptions.DailyChartsSettings
        let byHour: ReportOptions.ByHourSettings
        let byWeekday: ReportOptions.ByWeekdaySettings
        let meals: ReportOptions.MealsSettings
        let insulin: ReportOptions.InsulinSettings
        /// what the Patches topic's read takes from the screen (`ReportPatchesInput`)
        let patchesInput: ReportPatchesInput
        /// the CGM on screen: its own "Export PDF" prints that one; nil for a report, which prints each
        let cgmPick: CGMPick?
        /// the settings as they are when the report is asked for; nil: not given (the Settings part says so)
        let settingsSnapshot: ReportSettingsSnapshot?
        /// the current `individualAdjustmentFactor` (the Meals tab's read takes it)
        let carbEquivalentFactor: Double
        /// the current `allowOneMinuteLoop` (Good & bad days' loop row counts its slots by it)
        let allowOneMinuteLoop: Bool
        /// A view's own period for its part alone (its "Export PDF"): By weekday's weeks, Good & bad days' days; nil
        /// for a report, whose parts follow `period`.
        let partPeriod: StatsPeriod?
        /// One day alone (the Day view's "Export PDF"): its chart on a single landscape page, whatever the period and
        /// the days per page; nil for a period's report.
        let day: Date?

        init(
            period: StatsPeriod,
            parts: [ReportPart],
            units: [GlucoseUnits],
            hbA1cUnit: HbA1cUnit,
            paper: ReportPaper,
            summary: ReportOptions.SummarySettings = .init(),
            daysTable: ReportOptions.DaysTableSettings = .init(),
            dailyCharts: ReportOptions.DailyChartsSettings = .init(),
            byHour: ReportOptions.ByHourSettings = .init(),
            byWeekday: ReportOptions.ByWeekdaySettings = .init(),
            meals: ReportOptions.MealsSettings = .init(),
            insulin: ReportOptions.InsulinSettings = .init(),
            patchesInput: ReportPatchesInput = .init(),
            cgmPick: CGMPick? = nil,
            settingsSnapshot: ReportSettingsSnapshot? = nil,
            carbEquivalentFactor: Double = 0.5,
            allowOneMinuteLoop: Bool = false,
            partPeriod: StatsPeriod? = nil,
            day: Date? = nil
        ) {
            self.period = day == nil ? period : Self.dayPeriod
            self.parts = day == nil ? parts : [.dailyCharts]
            self.units = units
            self.hbA1cUnit = hbA1cUnit
            self.paper = paper
            self.summary = summary
            self.daysTable = daysTable
            var charts = dailyCharts
            if day != nil {
                charts.daysPerPage = 1
            }
            self.dailyCharts = charts
            self.byHour = byHour
            self.byWeekday = byWeekday
            self.meals = meals
            self.insulin = insulin
            self.patchesInput = patchesInput
            self.cgmPick = cgmPick
            self.settingsSnapshot = settingsSnapshot
            self.carbEquivalentFactor = carbEquivalentFactor
            self.allowOneMinuteLoop = allowOneMinuteLoop
            self.partPeriod = partPeriod
            self.day = day
        }

        /// Weekly's period: the screen's, whatever the report's.
        static let weeklyPeriod: StatsPeriod = .weeks13

        /// By weekday's whole weeks: a view's own (4, 8 or 13), else those of the report's period (30 days: 4 weeks,
        /// 90 days: 13); nil for a shorter period: the part is left out, never widened.
        var weekdayPeriod: StatsPeriod? {
            if let partPeriod, StatsPeriod.weekdayPeriods.contains(partPeriod) { return partPeriod }
            guard ReportPart.byWeekday.availability(for: period).isAvailable else { return nil }
            return period == .days90 ? .weeks13 : .weeks4
        }

        /// Good & bad days' period: a view's own (14, 30 or 90 days), else the report's when it is one of them; nil for
        /// 7 days: the part is left out.
        var goodBadDaysPeriod: StatsPeriod? {
            if let partPeriod, StatsPeriod.usualDayPeriods.contains(partPeriod) { return partPeriod }
            return StatsPeriod.usualDayPeriods.contains(period) ? period : nil
        }

        /// Weekly is printed: the report's period is long enough for it, or it was asked for on its own.
        var printsWeekly: Bool {
            parts == [.weekly] || ReportPart.weekly.availability(for: period).isAvailable
        }

        /// The one part of a view's own "Export PDF" that reads nothing but its own result: By hour, By weekday,
        /// Weekly, Good & bad days, Insulin, Meals, Patches or CGM alone. nil for a report and for the other parts.
        var ownPart: ReportPart? {
            guard parts.count == 1, let part = parts.first, day == nil else { return nil }
            return [.byHour, .byWeekday, .weekly, .goodBadDays, .insulin, .meals, .patches, .cgm].contains(part) ? part : nil
        }

        /// the period a single day's request carries (the Day view's days); its insulin and meals are read from the
        /// smallest period that holds the day (`ReportBuilder.period(containing:)`)
        static let dayPeriod: StatsPeriod = .days90

        /// the Summary part's insulin and carbs block is asked for
        var needsInsulinAndCarbs: Bool {
            parts.contains(.summary) && summary.insulinAndCarbs
        }

        /// the Insulin tab's days are read: the Summary's block, the Days table's columns, Daily charts' TDD, the
        /// Insulin part
        var needsInsulin: Bool {
            needsInsulinAndCarbs || (parts.contains(.daysTable) && daysTable.insulin) || parts.contains(.dailyCharts)
                || parts.contains(.insulin)
        }

        /// the Meals tab's days are read: the Summary's block, the Days table's column, Daily charts' carbs, the Meals
        /// part
        var needsMeals: Bool {
            needsInsulinAndCarbs || (parts.contains(.daysTable) && daysTable.carbs) || parts.contains(.dailyCharts)
                || parts.contains(.meals)
        }

        func size(of part: ReportPart) -> CGSize {
            paper.size(landscape: ReportPlan.isLandscape(part, dailyCharts: dailyCharts))
        }
    }

    /// A report's data, read off the main actor (`ReportBuilder`): what the pages print, before formatting. Every
    /// number is computed once, so the pages of a report in both units only differ in how values and labels are
    /// written.
    struct ReportData: Sendable, Equatable {
        let request: ReportRequest
        let generatedAt: Date
        /// the period's (a single day's report: the day's), on the standard bands of the first unit printed
        let summary: GlucoseSummary
        /// the period's profile (`GlucoseStatsEngine.agpBinMinutes` each, from 00:00)
        let bins: [AGPBin?]
        /// the period's Glycemia Risk Index on `summary`'s bands (the range rows'); nil when not asked for
        let gri: GlycemiaRiskIndex?
        /// the Insulin tab's summary of the period (complete days only); nil when not asked for
        let insulin: ReportRead<InsulinSummary>?
        /// the Meals tab's summary of the period (complete days with entries); nil when not asked for
        let meals: ReportRead<MealSummary>?
        /// the Days table's glucose: the period's day aggregates, oldest -> newest; nil without the part
        var glucoseDays: PeriodDays?
        /// the Insulin tab's days of the period, oldest -> newest; none when not read
        var insulinDays: [DayInsulin] = []
        /// the Meals tab's days of the period, oldest -> newest; none when not read
        var mealDays: [DayMeals] = []
        /// Daily charts' days with data, oldest -> newest; none without the part
        var chartDays: [ReportChartDay] = []
        /// the reads that failed: the Days table and Daily charts say so under them
        var failedReads: Set<ReportReadFailure> = []
        /// By hour's result, on `summary`'s bands; nil without the part
        var hourOfDay: HourOfDayResult?
        /// By weekday's result (`request.weekdayPeriod`'s whole weeks); nil without the part
        var weekday: WeekdayResult?
        /// Weekly's result of 13 weeks in each unit printed, all from one read of the weeks' days (only the means and
        /// their Δ are taken in the unit shown); none without the part
        var weekly: [WeeklyResult] = []
        /// Good & bad days' result (`request.goodBadDaysPeriod`); nil without the part
        var goodBadDays: GoodBadDaysData?
        /// the Insulin part's: the Insulin tab's period (its summary, days and clock hours), or that it couldn't be
        /// read; nil without the part
        var insulinPeriod: ReportRead<InsulinPeriod>?
        /// the Meals part's: the Meals tab's period (its summary, days and clock hours), or that it couldn't be read;
        /// nil without the part
        var mealPeriod: ReportRead<MealPeriod>?
        /// the Patches part's: the Patches topic's result, or that it couldn't be read; nil without the part
        var patches: ReportRead<PatchesResult>?
        /// the CGM part's: the CGM topic's result, or that it couldn't be read; nil without the part
        var cgm: ReportRead<CGMResult>?

        /// The first and the last day printed (their starts): the period's, the last one today, also without readings
        /// yet; a single day's report: that day.
        func days(calendar: Calendar) -> (first: Date, last: Date) {
            if let day = request.day {
                let start = calendar.startOfDay(for: day)
                return (start, start)
            }
            let first = summary.window.start
            let count = request.period.calendarDayCount ?? 1
            return (first, calendar.date(byAdding: .day, value: count - 1, to: first) ?? first)
        }

        /// The first and the last day (their starts) of a window of whole days (`[start, end)`).
        static func days(of window: DateInterval, calendar: Calendar) -> (first: Date, last: Date) {
            (window.start, calendar.startOfDay(for: Swift.max(window.start, window.end.addingTimeInterval(-1))))
        }

        /// The days the file is named by: a report of one part that states its own dates in its header (By weekday's
        /// whole weeks, Weekly's 13 weeks, Good & bad days' complete days, the Insulin and Meals tabs' days) those, else the
        /// period's (`days`).
        func fileDays(calendar: Calendar) -> (first: Date, last: Date) {
            guard request.parts.count == 1, let part = request.parts.first else { return days(calendar: calendar) }
            switch part {
            case .byWeekday:
                if let weekday { return (weekday.window.start, weekday.lastDay) }
            case .weekly:
                if let weeks = weekly.first?.weeks, let first = weeks.first, let last = weeks.last {
                    return (first.days.start, last.lastDay)
                }
            case .goodBadDays:
                if let window = goodBadDays?.result.window { return Self.days(of: window, calendar: calendar) }
            case .insulin:
                if let window = insulinPeriod?.value?.summary.window { return Self.days(of: window, calendar: calendar) }
            case .meals:
                if let window = mealPeriod?.value?.summary.window { return Self.days(of: window, calendar: calendar) }
            case .patches:
                if let window = patches?.value?.window { return Self.days(of: window, calendar: calendar) }
            case .cgm:
                if let window = cgm?.value?.window { return Self.days(of: window, calendar: calendar) }
            default: break
            }
            return days(calendar: calendar)
        }
    }

    enum ReportError: Error, Equatable {
        /// no CGM data in the period: nothing to print
        case noData
        /// the Insulin part alone: no pump data in the period
        case noPumpData
        /// the Meals part alone: no carb entry in the period
        case noCarbEntries
        /// the Insulin part alone: the pump data couldn't be read
        case pumpDataNotRead
        /// the Meals part alone: the carb entries couldn't be read
        case carbEntriesNotRead
        /// the Patches part alone: no patch (pod, site) in the period; the text says which
        case noPatches(String)
        /// the Patches part alone: the pump data couldn't be read
        case patchesNotRead
        /// the CGM part alone: the readings couldn't be read
        case cgmNotRead
        /// a single day's report: the day has no CGM data
        case noDataOnDay
        /// no part selected
        case nothingSelected
        /// the PDF file couldn't be created
        case notWritten
    }

    /// Reads a report's data with the Statistics provider: the same services, caches and definitions as the tabs.
    enum ReportBuilder {
        /// The bands every report uses, whatever the user's low/high: <54, 54–70, 70–180, 180–250, >250 mg/dL (mmol/L:
        /// the edges displayed like them).
        static func standardBands(_ units: GlucoseUnits) -> StatsBands {
            StatsBands(
                low: Decimal(StatsBands.tirMgdl.lowerBound),
                high: Decimal(StatsBands.tirMgdl.upperBound),
                units: units
            )
        }

        /// The report's data. The profile read first holds the period's readings for a statistics session (it nests in
        /// the screen's own), so the days' reads after it come from them. Throws `CancellationError` when cancelled
        /// between the reads, `ReportError.noData` without CGM data.
        /// - Parameter calendar: the days' (Daily charts' days, the timeline's clock)
        static func build(
            _ request: ReportRequest,
            source: any ReportDataSource,
            now: Date = Date(),
            calendar: Calendar = .current
        ) async throws -> ReportData {
            guard request.parts.isNotEmpty, let units = request.units.first else { throw ReportError.nothingSelected }
            await source.beginSession()
            do {
                let data: ReportData
                if request.day == nil {
                    data = try await read(request, units: units, source: source, now: now, calendar: calendar)
                } else {
                    data = try await readDay(request, units: units, source: source, now: now, calendar: calendar)
                }
                await source.endSession()
                return data
            } catch {
                await source.endSession()
                throw error
            }
        }

        /// A read that may fail without failing the report (`ReportRead.failed`, logged); a cancellation is thrown on.
        private static func tolerant<Value>(
            _ what: String,
            _ body: () async throws -> Value
        ) async throws -> ReportRead<Value> where Value: Sendable & Equatable {
            do {
                return .value(try await body())
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warning(.service, "Report: \(what) couldn't be read", error: error)
                return .failed
            }
        }

        /// The pump events, coverage and basal schedules of a window, as the Patches topic reads a run of sessions
        /// (`Stat.Provider.patchInput`): the events with the state running into the window, up to an hour after it but
        /// never after `now`, the coverage from that state on, the schedule records. No IOB rows: the charts draw none.
        static func insulinInput(_ window: DateInterval, now: Date, source: InsulinDataSource) async throws -> InsulinInput {
            let start = window.start
            let to = Swift.max(start, Swift.min(window.end.addingTimeInterval(.hours(1)), now))
            async let events = source.fetchPumpEvents(from: start, to: to)
            let runningInto = try await source.fetchPumpEventsRunningInto(start)
            let coverage = try await source.fetchCoverage(from: Swift.min(runningInto.first?.date ?? start, start), to: to)
            let schedules = try await source.fetchBasalSchedules(from: start, to: to)
            return try await InsulinInput(events: runningInto + events, coverage: coverage, schedules: schedules)
        }

        /// The smallest period a report offers that holds `day` (it ends today); nil for a day before the longest one.
        static func period(containing day: Date, now: Date, calendar: Calendar) -> StatsPeriod? {
            let from = calendar.startOfDay(for: day)
            let back = calendar.dateComponents([.day], from: from, to: calendar.startOfDay(for: now)).day ?? 0
            let days = Swift.max(back, 0) + 1
            return ReportOptions.periods.first { ($0.calendarDayCount ?? 0) >= days }
        }

        private static func read(
            _ request: ReportRequest,
            units: GlucoseUnits,
            source: any ReportDataSource,
            now: Date,
            calendar: Calendar
        ) async throws -> ReportData {
            let bands = standardBands(units)
            try Task.checkCancellation()
            if let part = request.ownPart {
                return try await readOwn(part, request: request, bands: bands, source: source, now: now, calendar: calendar)
            }
            // no part with glucose values (Insulin and Meals together): the glucose isn't read, and isn't needed
            guard request.parts.contains(where: \.printsGlucose) else {
                return try await readWithoutGlucose(request, bands: bands, source: source, now: now, calendar: calendar)
            }
            let profile = await source.reportProfile(request.period, bands: bands)
            try Task.checkCancellation()
            guard !profile.summary.isEmpty else { throw ReportError.noData }

            var failed: Set<ReportReadFailure> = []
            var insulin: ReportRead<InsulinPeriod>?
            var meals: ReportRead<MealPeriod>?
            if request.needsInsulin {
                let read = try await tolerant("the insulin data") { try await source.reportInsulin(request.period) }
                if read == .failed {
                    failed.insert(.insulin)
                }
                insulin = read
                try Task.checkCancellation()
            }
            if request.needsMeals {
                let read = try await tolerant("the meals") {
                    try await source.reportMeals(request.period, factor: request.carbEquivalentFactor)
                }
                if read == .failed {
                    failed.insert(.meals)
                }
                meals = read
                try Task.checkCancellation()
            }
            var summary = profile.summary
            var glucoseDays: PeriodDays?
            if request.parts.contains(.daysTable) {
                let days = await source.reportDays(request.period)
                try Task.checkCancellation()
                glucoseDays = days
                // one read for the table's days, its Average row and the Summary's numbers: a reading that came in after
                // the profile's read can't make them differ
                let pooled = GlucoseStatsEngine.summary(
                    days: days.days,
                    window: days.window,
                    endRule: days.endRule,
                    period: request.period,
                    bands: bands
                )
                if !pooled.isEmpty {
                    summary = pooled
                }
            }
            var chartDays: [ReportChartDay] = []
            if request.parts.contains(.dailyCharts) {
                let charts = try await readCharts(
                    request,
                    days: InsulinStatsEngine.periodDays(request.period, now: now, calendar: calendar),
                    traces: nil,
                    bands: bands,
                    source: source,
                    insulinDays: insulin?.value?.days ?? [],
                    mealDays: meals?.value?.days ?? [],
                    now: now,
                    calendar: calendar
                )
                chartDays = charts.days
                if charts.eventsFailed {
                    failed.insert(.pumpEvents)
                }
            }
            var data = try assemble(
                request,
                summary: summary,
                bins: profile.bins,
                insulin: request.needsInsulinAndCarbs ? insulin.map { mapped($0, \.summary) } : nil,
                meals: request.needsInsulinAndCarbs ? meals.map { mapped($0, \.summary) } : nil,
                glucoseDays: glucoseDays,
                insulinDays: insulin?.value?.days ?? [],
                mealDays: meals?.value?.days ?? [],
                chartDays: chartDays,
                failedReads: failed,
                now: now
            )
            if request.parts.contains(.insulin) {
                data.insulinPeriod = insulin ?? .failed
            }
            if request.parts.contains(.meals) {
                data.mealPeriod = meals ?? .failed
            }
            try await readPatterns(request, into: &data, bands: bands, source: source)
            try await readDevices(request, into: &data, bands: bands, source: source, now: now, calendar: calendar)
            return data
        }

        /// The Patches and the CGM topics' results; a read that fails is said on the part's page.
        private static func readDevices(
            _ request: ReportRequest,
            into data: inout ReportData,
            bands: StatsBands,
            source: any ReportDataSource,
            now: Date,
            calendar: Calendar
        ) async throws {
            if request.parts.contains(.patches) {
                try Task.checkCancellation()
                data.patches = try await tolerant("the patches") {
                    try await source.reportPatches(
                        request.period,
                        bands: bands,
                        input: request.patchesInput,
                        now: now,
                        calendar: calendar
                    )
                }
            }
            if request.parts.contains(.cgm) {
                try Task.checkCancellation()
                data.cgm = try await tolerant("the CGM readings") {
                    try await source.reportCGM(request.period, now: now, calendar: calendar)
                }
            }
            try Task.checkCancellation()
        }

        /// A report's data without anything of the glucose: an empty summary of the period's window (the period's days
        /// are still its header's and its file's), for the parts' own results to be put in.
        private static func withoutGlucose(
            _ request: ReportRequest,
            bands: StatsBands,
            now: Date,
            calendar: Calendar
        ) -> ReportData {
            ReportData(
                request: request,
                generatedAt: now,
                summary: GlucoseStatsEngine.summary(
                    GlucoseHistogram(),
                    window: GlucoseStatsEngine.window(for: request.period, now: now, end: now, calendar: calendar),
                    endRule: .stalled,
                    calendarDays: request.period.calendarDayCount ?? 0,
                    daysWithData: 0,
                    bands: bands
                ),
                bins: [],
                gri: nil,
                insulin: nil,
                meals: nil
            )
        }

        /// A report of parts without glucose values only (Insulin and Meals): the tabs' periods and nothing of the
        /// glucose, so it is made without CGM data too. A read that fails, or a period without data, is said on the
        /// part's page.
        private static func readWithoutGlucose(
            _ request: ReportRequest,
            bands: StatsBands,
            source: any ReportDataSource,
            now: Date,
            calendar: Calendar
        ) async throws -> ReportData {
            var data = withoutGlucose(request, bands: bands, now: now, calendar: calendar)
            if request.parts.contains(.insulin) {
                try Task.checkCancellation()
                data.insulinPeriod = try await tolerant("the insulin data") { try await source.reportInsulin(request.period) }
            }
            if request.parts.contains(.meals) {
                try Task.checkCancellation()
                data.mealPeriod = try await tolerant("the meals") {
                    try await source.reportMeals(request.period, factor: request.carbEquivalentFactor)
                }
            }
            try Task.checkCancellation()
            return data
        }

        /// One of the glucose views' parts alone (its "Export PDF"): its own result and nothing else, so no profile of
        /// the whole period is computed for it. Without data in it: `noData`. The summary is the result's own where it
        /// has one, else an empty one of the part's days (nothing prints it: the part states its own dates).
        private static func readOwn(
            _ part: ReportPart,
            request: ReportRequest,
            bands: StatsBands,
            source: any ReportDataSource,
            now: Date,
            calendar: Calendar
        ) async throws -> ReportData {
            var data = withoutGlucose(request, bands: bands, now: now, calendar: calendar)
            // Insulin or Meals alone: the tab's period, and nothing of the glucose; a read that fails fails the report,
            // saying which
            if part == .insulin {
                try Task.checkCancellation()
                let read = try await tolerant("the insulin data") { try await source.reportInsulin(request.period) }
                guard let period = read.value else { throw ReportError.pumpDataNotRead }
                guard !period.summary.isEmpty else { throw ReportError.noPumpData }
                data.insulinPeriod = .value(period)
                return data
            }
            if part == .meals {
                try Task.checkCancellation()
                let read = try await tolerant("the meals") {
                    try await source.reportMeals(request.period, factor: request.carbEquivalentFactor)
                }
                guard let period = read.value else { throw ReportError.carbEntriesNotRead }
                guard !period.summary.isEmpty else { throw ReportError.noCarbEntries }
                data.mealPeriod = .value(period)
                return data
            }
            // Patches or CGM alone: the topic's result; without data, or unread, no report, saying why
            if part == .patches || part == .cgm {
                try await readDevices(request, into: &data, bands: bands, source: source, now: now, calendar: calendar)
                if part == .patches {
                    guard let result = data.patches?.value else { throw ReportError.patchesNotRead }
                    guard !result.isEmpty else { throw ReportError.noPatches(ReportPatches.emptyText(result.topic)) }
                } else {
                    guard let result = data.cgm?.value else { throw ReportError.cgmNotRead }
                    guard !result.isEmpty else { throw ReportError.noData }
                }
                return data
            }
            try await readPatterns(request, into: &data, bands: bands, source: source)
            let summary: GlucoseSummary?
            switch part {
            case .byHour: summary = data.hourOfDay.flatMap { $0.isEmpty ? nil : $0.summary }
            case .byWeekday: summary = data.weekday.flatMap { $0.isEmpty ? nil : data.summary }
            case .weekly: summary = data.weekly.first.flatMap { $0.isEmpty ? nil : $0.summary }
            case .goodBadDays: summary = data.goodBadDays.flatMap { $0.isEmpty ? nil : data.summary }
            default: summary = nil
            }
            guard let summary else { throw ReportError.noData }
            var result = ReportData(
                request: request,
                generatedAt: now,
                summary: summary,
                bins: [],
                gri: nil,
                insulin: nil,
                meals: nil
            )
            result.hourOfDay = data.hourOfDay
            result.weekday = data.weekday
            result.weekly = data.weekly
            result.goodBadDays = data.goodBadDays
            return result
        }

        /// The glucose views' results, each read once with the report's bands: By hour, By weekday (its whole weeks),
        /// Weekly (13 weeks' days read once, whatever the units printed) and Good & bad days. A part whose period the
        /// report can't hold is left out.
        private static func readPatterns(
            _ request: ReportRequest,
            into data: inout ReportData,
            bands: StatsBands,
            source: any ReportDataSource
        ) async throws {
            if request.parts.contains(.byHour) {
                try Task.checkCancellation()
                data.hourOfDay = await source.reportHourOfDay(request.period, bands: bands)
            }
            if request.parts.contains(.byWeekday), let weeks = request.weekdayPeriod {
                try Task.checkCancellation()
                data.weekday = await source.reportWeekday(weeks, bands: bands)
            }
            if request.parts.contains(.weekly), request.printsWeekly {
                try Task.checkCancellation()
                // one read: the weeks and their average are the same on every unit's page, which only takes the means
                // (and their Δ) in its unit
                let period = ReportRequest.weeklyPeriod
                let days = await source.reportDays(period)
                let summary = GlucoseStatsEngine.summary(
                    days: days.days,
                    window: days.window,
                    endRule: days.endRule,
                    period: period,
                    bands: bands
                )
                let weeks = GlucoseStatsEngine.weeks(days.days, count: period.weekCount ?? 0)
                data.weekly = request.units.map { WeeklyResult(summary: summary, weeks: weeks, units: $0) }
            }
            if request.parts.contains(.goodBadDays), let period = request.goodBadDaysPeriod {
                try Task.checkCancellation()
                data.goodBadDays = await source.reportGoodBadDays(
                    period,
                    bands: bands,
                    allowOneMinuteLoop: request.allowOneMinuteLoop
                )
            }
            try Task.checkCancellation()
        }

        /// One day's chart. Its readings first: without any there is no chart (`noDataOnDay`), whatever else the day
        /// has, and nothing else is read. Then its insulin and meals out of the smallest period that holds the day; a
        /// day with readings alone is drawn too.
        private static func readDay(
            _ request: ReportRequest,
            units: GlucoseUnits,
            source: any ReportDataSource,
            now: Date,
            calendar: Calendar
        ) async throws -> ReportData {
            guard let date = request.day else { throw ReportError.nothingSelected }
            let day = StatsClock.wholeDay(of: date, calendar: calendar)
            let bands = standardBands(units)
            try Task.checkCancellation()
            let trace = await source.reportTrace(day: day.start, bands: bands)
            guard trace.points.isNotEmpty else { throw ReportError.noDataOnDay }

            var failed: Set<ReportReadFailure> = []
            var insulinDays: [DayInsulin] = []
            var mealDays: [DayMeals] = []
            if let period = period(containing: day.start, now: now, calendar: calendar) {
                try Task.checkCancellation()
                let insulin = try await tolerant("the insulin data") { try await source.reportInsulin(period) }
                if insulin == .failed {
                    failed.insert(.insulin)
                }
                insulinDays = insulin.value?.days ?? []
                try Task.checkCancellation()
                let meals = try await tolerant("the meals") {
                    try await source.reportMeals(period, factor: request.carbEquivalentFactor)
                }
                if meals == .failed {
                    failed.insert(.meals)
                }
                mealDays = meals.value?.days ?? []
            }
            let charts = try await readCharts(
                request,
                days: [day],
                traces: [trace],
                bands: bands,
                source: source,
                insulinDays: insulinDays,
                mealDays: mealDays,
                now: now,
                calendar: calendar
            )
            if charts.eventsFailed {
                failed.insert(.pumpEvents)
            }
            return ReportData(
                request: request,
                generatedAt: now,
                summary: trace.summary,
                bins: [],
                gri: nil,
                insulin: nil,
                meals: nil,
                chartDays: charts.days,
                failedReads: failed
            )
        }

        /// Daily charts' days: each day's readings (from the readings the session holds; `traces` when already read),
        /// then the window's pump events read once and cut by day.
        private static func readCharts(
            _ request: ReportRequest,
            days: [DateInterval],
            traces read: [ReportDayTrace]?,
            bands: StatsBands,
            source: any ReportDataSource,
            insulinDays: [DayInsulin],
            mealDays: [DayMeals],
            now: Date,
            calendar: Calendar
        ) async throws -> (days: [ReportChartDay], eventsFailed: Bool) {
            var traces = read ?? []
            if read == nil {
                for day in days {
                    try Task.checkCancellation()
                    traces.append(await source.reportTrace(day: day.start, bands: bands))
                }
            }
            var input: InsulinInput?
            var eventsFailed = false
            let settings = request.dailyCharts
            if settings.boluses || settings.basal, let first = days.first, let last = days.last {
                try Task.checkCancellation()
                let window = DateInterval(start: first.start, end: Swift.max(first.start, last.end))
                let events = try await tolerant("the pump events") { try await source.reportInsulinInput(window, now: now) }
                input = events.value
                eventsFailed = events == .failed
            }
            try Task.checkCancellation()
            let chartDays = ReportChartsBuilder.days(
                days,
                traces: traces,
                insulinDays: insulinDays,
                mealDays: mealDays,
                input: input,
                settings: settings,
                now: now,
                calendar: calendar
            )
            return (chartDays, eventsFailed)
        }

        private static func mapped<Period, Summary>(
            _ read: ReportRead<Period>,
            _ summary: KeyPath<Period, Summary>
        ) -> ReportRead<Summary> {
            switch read {
            case let .value(period): return .value(period[keyPath: summary])
            case .failed: return .failed
            }
        }

        /// The report's data from what was read: the summary on the first unit's standard bands, the GRI on the same
        /// bands when asked for.
        /// - Parameter summary: the period's, on any bands
        static func assemble(
            _ request: ReportRequest,
            summary: GlucoseSummary,
            bins: [AGPBin?],
            insulin: ReportRead<InsulinSummary>? = nil,
            meals: ReportRead<MealSummary>? = nil,
            glucoseDays: PeriodDays? = nil,
            insulinDays: [DayInsulin] = [],
            mealDays: [DayMeals] = [],
            chartDays: [ReportChartDay] = [],
            failedReads: Set<ReportReadFailure> = [],
            now: Date
        ) throws -> ReportData {
            guard request.parts.isNotEmpty, let units = request.units.first else { throw ReportError.nothingSelected }
            guard !summary.isEmpty else { throw ReportError.noData }
            let summary = Self.summary(summary, bands: standardBands(units))
            let wantsGRI = request.parts.contains(.summary) && request.summary.gri
            return ReportData(
                request: request,
                generatedAt: now,
                summary: summary,
                bins: bins,
                gri: wantsGRI ? gri(summary) : nil,
                insulin: insulin,
                meals: meals,
                glucoseDays: glucoseDays,
                insulinDays: insulinDays,
                mealDays: mealDays,
                chartDays: chartDays,
                failedReads: failedReads
            )
        }

        /// The period's Glycemia Risk Index (`GlucoseStatsEngine.gri`: 3.0 × very low + 2.4 × low + 1.6 × very high +
        /// 0.8 × high, percents of the covered time) on the summary's own bands, the ones its range rows are on.
        static func gri(_ summary: GlucoseSummary) -> GlycemiaRiskIndex? {
            GlucoseStatsEngine.gri(summary.histogram, bands: summary.bands)
        }

        /// A summary on other bands: the same histogram and window.
        static func summary(_ summary: GlucoseSummary, bands: StatsBands) -> GlucoseSummary {
            guard summary.bands != bands else { return summary }
            return GlucoseStatsEngine.summary(
                summary.histogram,
                window: summary.window,
                endRule: summary.endRule,
                calendarDays: summary.calendarDays,
                daysWithData: summary.daysWithData,
                bands: bands
            )
        }
    }
}
