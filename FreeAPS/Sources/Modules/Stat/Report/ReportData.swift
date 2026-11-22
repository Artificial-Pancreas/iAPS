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

/// A page of a report: a part in one unit.
struct ReportPage: Sendable, Equatable {
    let part: ReportPart
    let units: GlucoseUnits
    /// points
    let size: CGSize
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

/// The provider calls a report makes (`Stat.Provider`'s; tests pass a fake).
protocol ReportDataSource: Sendable {
    func beginSession() async
    func endSession() async
    /// the period's profile and summary (`Stat.Provider.agp`)
    func reportProfile(_ period: StatsPeriod, bands: StatsBands) async -> Stat.AGPResult
    /// the Insulin tab's summary of the period
    func reportInsulin(_ period: StatsPeriod) async throws -> InsulinSummary
    /// the Meals tab's summary of the period
    func reportMeals(_ period: StatsPeriod, factor: Double) async throws -> MealSummary
}

extension Stat.Provider: ReportDataSource {
    func reportProfile(_ period: StatsPeriod, bands: StatsBands) async -> Stat.AGPResult {
        await agp(period, bands: bands)
    }

    func reportInsulin(_ period: StatsPeriod) async throws -> InsulinSummary {
        try await insulin(period).insulin.summary
    }

    func reportMeals(_ period: StatsPeriod, factor: Double) async throws -> MealSummary {
        try await meals(period, factor: factor).meals.summary
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
        /// the current `individualAdjustmentFactor` (the Meals tab's read takes it)
        let carbEquivalentFactor: Double

        init(
            period: StatsPeriod,
            parts: [ReportPart],
            units: [GlucoseUnits],
            hbA1cUnit: HbA1cUnit,
            paper: ReportPaper,
            summary: ReportOptions.SummarySettings = .init(),
            carbEquivalentFactor: Double = 0.5
        ) {
            self.period = period
            self.parts = parts
            self.units = units
            self.hbA1cUnit = hbA1cUnit
            self.paper = paper
            self.summary = summary
            self.carbEquivalentFactor = carbEquivalentFactor
        }

        /// The report's pages: part by part, each once per unit.
        var pages: [ReportPage] {
            parts.flatMap { part in
                (0 ..< part.pageCount).flatMap { _ in
                    units.map { ReportPage(part: part, units: $0, size: paper.size(landscape: part.isLandscape)) }
                }
            }
        }

        /// the Summary part's insulin and carbs block is asked for
        var needsInsulinAndCarbs: Bool {
            parts.contains(.summary) && summary.insulinAndCarbs
        }
    }

    /// A report's data, read off the main actor (`ReportBuilder`): what the pages print, before formatting. Every
    /// number is computed once, so the pages of a report in both units only differ in how values and labels are
    /// written.
    struct ReportData: Sendable, Equatable {
        let request: ReportRequest
        let generatedAt: Date
        /// the period's, on the standard bands of the first unit printed
        let summary: GlucoseSummary
        /// the period's profile (`GlucoseStatsEngine.agpBinMinutes` each, from 00:00)
        let bins: [AGPBin?]
        /// the period's Glycemia Risk Index on `summary`'s bands (the range rows'); nil when not asked for
        let gri: GlycemiaRiskIndex?
        /// the Insulin tab's summary of the period (complete days only); nil when not asked for
        let insulin: ReportRead<InsulinSummary>?
        /// the Meals tab's summary of the period (complete days with entries); nil when not asked for
        let meals: ReportRead<MealSummary>?

        var pages: [ReportPage] { request.pages }

        /// The period's first and last day (their starts): the last one today, also without readings yet.
        func days(calendar: Calendar) -> (first: Date, last: Date) {
            let first = summary.window.start
            let count = request.period.calendarDayCount ?? 1
            return (first, calendar.date(byAdding: .day, value: count - 1, to: first) ?? first)
        }
    }

    enum ReportError: Error, Equatable {
        /// no CGM data in the period: nothing to print
        case noData
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

        /// The report's data. One profile read gives the period's summary too (as the AGP tab's); the readings are held
        /// by a statistics session meanwhile (it nests in the screen's own). Throws `CancellationError` when cancelled
        /// between the reads, `ReportError.noData` without CGM data.
        static func build(
            _ request: ReportRequest,
            source: any ReportDataSource,
            now: Date = Date()
        ) async throws -> ReportData {
            guard request.parts.isNotEmpty, let units = request.units.first else { throw ReportError.nothingSelected }
            await source.beginSession()
            do {
                let data = try await read(request, units: units, source: source, now: now)
                await source.endSession()
                return data
            } catch {
                await source.endSession()
                throw error
            }
        }

        private static func read(
            _ request: ReportRequest,
            units: GlucoseUnits,
            source: any ReportDataSource,
            now: Date
        ) async throws -> ReportData {
            try Task.checkCancellation()
            let profile = await source.reportProfile(request.period, bands: standardBands(units))
            try Task.checkCancellation()
            guard !profile.summary.isEmpty else { throw ReportError.noData }

            var insulin: ReportRead<InsulinSummary>?
            var meals: ReportRead<MealSummary>?
            if request.needsInsulinAndCarbs {
                do {
                    insulin = .value(try await source.reportInsulin(request.period))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    warning(.service, "Report: the insulin data couldn't be read", error: error)
                    insulin = .failed
                }
                try Task.checkCancellation()
                do {
                    meals = .value(try await source.reportMeals(request.period, factor: request.carbEquivalentFactor))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    warning(.service, "Report: the meals couldn't be read", error: error)
                    meals = .failed
                }
                try Task.checkCancellation()
            }
            return try assemble(
                request,
                summary: profile.summary,
                bins: profile.bins,
                insulin: insulin,
                meals: meals,
                now: now
            )
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
                meals: meals
            )
        }

        /// The period's Glycemia Risk Index (`GlucoseStatsEngine.gri`: 3.0 × very low + 2.4 × low + 1.6 × very high +
        /// 0.8 × high, percents of the covered time) on the summary's own bands, the ones its range rows are on.
        static func gri(_ summary: GlucoseSummary) -> GlycemiaRiskIndex? {
            GlucoseStatsEngine.gri(summary.histogram, bands: summary.bands)
        }

        /// A summary on other bands: the same histogram and window.
        private static func summary(_ summary: GlucoseSummary, bands: StatsBands) -> GlucoseSummary {
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
