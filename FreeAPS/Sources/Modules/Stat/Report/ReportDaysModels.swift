import CoreGraphics
import Foundation

// The Days table of a report: one row a day, with subtotal rows and an Average row. The rows' numbers are built
// without formatting (`ReportDaysBuilder`, pure: the calendar is a parameter); a page's strings on the main actor
// (`Stat.ReportDaysPage`).

/// The numbers of a row of the Days table: a day's, or a group of days' averaged. nil: nothing to show (a dash).
struct ReportDaysNumbers: Sendable, Equatable {
    /// the time by band, of the covered time; nil without readings
    var shares: BandShares?
    /// percents of the covered time, exact: below the in-range band (low and very low) and above it
    var below: Double?
    var above: Double?
    /// mg/dL, time-weighted
    var mean: Double?
    var sd: Double?
    /// percent
    var cv: Double?
    /// mg/dL: the lowest and the highest reading
    var lowest: Int?
    var highest: Int?
    /// CGM coverage, percent
    var coverage: Int?
    /// U: a day's as delivered; a group's the Insulin tab's per-day means (complete days, the basal scaled)
    var tdd: Double?
    var basal: Double?
    /// the boluses and the SMBs
    var bolus: Double?
    /// a day outside the insulin averages: today, or pump data for less than half of it
    var insulinOutsideAverage = false
    /// g: a day's; a group's mean over its complete days with entries
    var carbs: Double?

    var hasGlucose: Bool { shares != nil }
}

/// A row of the Days table.
enum ReportDaysRow: Sendable, Equatable {
    /// a calendar day (its start), also one without data
    case day(Date, ReportDaysNumbers)
    /// the days of a week or a month inside the period, averaged: the first and the last of them
    case subtotal(first: Date, last: Date, ReportDaysNumbers)
    /// every day of the period, averaged
    case average(days: Int, ReportDaysNumbers)

    var numbers: ReportDaysNumbers {
        switch self {
        case let .day(_, numbers): return numbers
        case let .subtotal(_, _, numbers): return numbers
        case let .average(_, numbers): return numbers
        }
    }

    var isDay: Bool {
        if case .day = self { return true }
        return false
    }
}

enum ReportDaysBuilder {
    /// A day's (or a group's) insulin and meals, by the day's start.
    private struct Lookup {
        let insulin: [Date: DayInsulin]
        let meals: [Date: DayMeals]

        init(_ data: Stat.ReportData) {
            insulin = Dictionary(data.insulinDays.map { ($0.day.start, $0) }, uniquingKeysWith: { first, _ in first })
            meals = Dictionary(data.mealDays.map { ($0.day.start, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// The glucose numbers of a summary; none without readings.
    static func glucose(_ summary: GlucoseSummary, hasReadings: Bool) -> ReportDaysNumbers {
        guard hasReadings, !summary.isEmpty else { return ReportDaysNumbers() }
        var numbers = ReportDaysNumbers()
        numbers.shares = summary.bandShares
        numbers.below = (summary.fraction(.veryLow) + summary.fraction(.low)) * 100
        numbers.above = (summary.fraction(.high) + summary.fraction(.veryHigh)) * 100
        numbers.mean = summary.mean
        numbers.sd = summary.sd
        numbers.cv = summary.cv
        numbers.lowest = summary.minMax?.lowerBound
        numbers.highest = summary.minMax?.upperBound
        numbers.coverage = summary.coveragePercent
        return numbers
    }

    /// A day's numbers: its own summary on the bands, its insulin as delivered (the basal and the total only with
    /// pump data covering some of it, as the Insulin tab's day), its carbs when it has entries.
    static func day(
        _ aggregate: DayAggregate,
        endRule: StatsEndRule,
        bands: StatsBands,
        insulin: DayInsulin?,
        meals: DayMeals?
    ) -> ReportDaysNumbers {
        var numbers = glucose(
            GlucoseStatsEngine.daySummary(aggregate, endRule: endRule, bands: bands),
            hasReadings: aggregate.histogram.readingCount > 0
        )
        if let insulin, insulin.hasData {
            // as the Insulin part prints the day: the parts rounded so that they add up to the total as printed
            let covered = insulin.coveredSeconds > 0
            let split = ReportAmounts.split([covered ? insulin.basal : 0, insulin.smb, insulin.bolus], decimals: 1)
            numbers.tdd = covered ? split.total : nil
            numbers.basal = covered ? split.parts[0] : nil
            numbers.bolus = split.parts[1] + split.parts[2]
            numbers.insulinOutsideAverage = !insulin.isHeadline
        }
        if let meals, meals.hasEntries {
            numbers.carbs = meals.carbs
        }
        return numbers
    }

    /// A group of days averaged: the glucose pooled (time-weighted over the days, as a period's summary), the insulin
    /// the Insulin tab's means over its complete days (`InsulinStatsEngine.summary`), the carbs the Meals tab's mean
    /// over its complete days with entries.
    static func average(
        _ aggregates: [DayAggregate],
        endRule: StatsEndRule,
        bands: StatsBands,
        insulin: [DayInsulin],
        meals: [DayMeals]
    ) -> ReportDaysNumbers {
        guard let first = aggregates.first, let last = aggregates.last else { return ReportDaysNumbers() }
        let window = DateInterval(start: first.day.start, end: Swift.max(first.day.start, last.day.end))
        let pooled = GlucoseStatsEngine.summary(
            days: aggregates,
            window: window,
            endRule: endRule,
            period: nil,
            bands: bands
        )
        var numbers = glucose(pooled, hasReadings: aggregates.contains { $0.histogram.readingCount > 0 })
        if insulin.isNotEmpty {
            let summary = InsulinStatsEngine.summary(insulin, period: nil)
            if summary.tdd != nil {
                let split = ReportAmounts.split([summary.basal ?? 0, summary.smb ?? 0, summary.bolus ?? 0], decimals: 1)
                numbers.tdd = split.total
                numbers.basal = split.parts[0]
                numbers.bolus = split.parts[1] + split.parts[2]
            }
        }
        let averaged = meals.filter(\.isAveraged)
        if averaged.isNotEmpty {
            numbers.carbs = averaged.reduce(0) { $0 + $1.carbs } / Double(averaged.count)
        }
        return numbers
    }

    /// The start of the week or the month a day is in: the subtotals' groups.
    static func groupStart(
        of day: Date,
        _ subtotals: ReportOptions.DaysTableSettings.Subtotals,
        calendar: Calendar
    ) -> Date? {
        switch subtotals {
        case .none: return nil
        case .week: return calendar.dateInterval(of: .weekOfYear, for: day)?.start
        case .month: return calendar.dateInterval(of: .month, for: day)?.start
        }
    }

    /// The table's rows in the order printed: the days (oldest first, or newest first), a subtotal row after the days
    /// of each week or month (also of a part of one, at the period's ends), the Average row last. Every day of the
    /// period has a row, also one without data. None without the part's data.
    static func rows(_ data: Stat.ReportData, calendar: Calendar) -> [ReportDaysRow] {
        guard let period = data.glucoseDays, period.days.isNotEmpty else { return [] }
        let settings = data.request.daysTable
        let bands = data.summary.bands
        let lookup = Lookup(data)
        let aggregates = settings.newestFirst ? Array(period.days.reversed()) : period.days

        func average(_ group: [DayAggregate]) -> ReportDaysNumbers {
            // oldest -> newest, whatever the order printed
            let sorted = group.sorted { $0.day.start < $1.day.start }
            return Self.average(
                sorted,
                endRule: period.endRule,
                bands: bands,
                insulin: sorted.compactMap { lookup.insulin[$0.day.start] },
                meals: sorted.compactMap { lookup.meals[$0.day.start] }
            )
        }
        func subtotal(_ group: [DayAggregate]) -> ReportDaysRow? {
            guard let first = group.map(\.day.start).min(), let last = group.map(\.day.start).max() else { return nil }
            return .subtotal(first: first, last: last, average(group))
        }

        var rows: [ReportDaysRow] = []
        var group: [DayAggregate] = []
        var groupKey: Date?
        for aggregate in aggregates {
            let key = groupStart(of: aggregate.day.start, settings.subtotals, calendar: calendar)
            if settings.subtotals != .none, key != groupKey, group.isNotEmpty {
                if let row = subtotal(group) {
                    rows.append(row)
                }
                group = []
            }
            groupKey = key
            group.append(aggregate)
            rows.append(
                .day(
                    aggregate.day.start,
                    day(
                        aggregate,
                        endRule: period.endRule,
                        bands: bands,
                        insulin: lookup.insulin[aggregate.day.start],
                        meals: lookup.meals[aggregate.day.start]
                    )
                )
            )
        }
        if settings.subtotals != .none, let row = subtotal(group) {
            rows.append(row)
        }
        rows.append(.average(days: period.days.count, average(period.days)))
        return rows
    }

    /// The rows page by page: `perPage` on each, in order (the Average row ends the last one). The Average row is
    /// never alone on the last page: the row before it comes over with it.
    static func pages(_ rows: [ReportDaysRow], perPage: Int) -> [[ReportDaysRow]] {
        let size = Swift.max(perPage, 1)
        var pages = stride(from: 0, to: rows.count, by: size).map { Array(rows[$0 ..< Swift.min($0 + size, rows.count)]) }
        if pages.count > 1, pages[pages.count - 1].count == 1, pages[pages.count - 2].count > 1 {
            let moved = pages[pages.count - 2].removeLast()
            pages[pages.count - 1].insert(moved, at: 0)
        }
        return pages
    }
}

extension Stat.ReportData {
    /// A report laid out: its pages, and the Days table's rows page by page, built once for the report (each page
    /// takes its slice).
    struct Layout: Sendable, Equatable {
        let pages: [ReportPage]
        /// by the Days table's page; none without the part
        let dayRows: [[ReportDaysRow]]
    }

    /// The Days table's rows page by page; none without the part.
    func dayRows(calendar: Calendar) -> [[ReportDaysRow]] {
        guard request.parts.contains(.daysTable) else { return [] }
        return ReportDaysBuilder.pages(
            ReportDaysBuilder.rows(self, calendar: calendar),
            perPage: ReportPlan.daysTableRowsPerPage(request.paper)
        )
    }

    /// The pages a part takes in one unit: the Days table by its rows, Daily charts by its days with data (at least
    /// one page, saying there is nothing).
    func pageCount(of part: ReportPart, calendar: Calendar) -> Int {
        pageCount(of: part, dayRows: dayRows(calendar: calendar))
    }

    private func pageCount(of part: ReportPart, dayRows: [[ReportDaysRow]]) -> Int {
        switch part {
        case .daysTable:
            return Swift.max(dayRows.count, 1)
        case .dailyCharts:
            return Swift.max(ReportPlan.pageCount(chartDays.count, perPage: request.dailyCharts.daysPerPage), 1)
        // a part the report's period can't hold was left out by the builder: no page
        case .byHour:
            return hourOfDay == nil ? 0 : 1
        case .byWeekday:
            return weekday == nil ? 0 : 1
        case .weekly:
            return weekly.isEmpty ? 0 : 1
        case .goodBadDays:
            return goodBadDays.map { ReportGoodBadDaysLayout.pageCount($0, paper: request.paper) } ?? 0
        // the overview and the tables; one page saying so without data
        case .insulin:
            guard request.insulin.detailedTables, let period = insulinPeriod?.value, !period.summary.isEmpty else { return 1 }
            return ReportTablesLayout.pageCount(
                days: period.days.count,
                paper: request.paper,
                hourRows: Stat.ReportInsulin.hourRows
            )
        case .meals:
            guard request.meals.detailedTables, let period = mealPeriod?.value, !period.summary.isEmpty else { return 1 }
            return ReportTablesLayout.pageCount(
                days: period.days.count,
                paper: request.paper,
                hourRows: Stat.ReportMeals.hourRows
            )
        case .patches:
            return patches?.value.map { ReportPatchesLayout.pageCount($0, paper: request.paper) } ?? 1
        case .cgm:
            return cgm?.value.map { Stat.ReportCGM.pageCount($0, shown: request.cgmPick) } ?? 1
        case .settings:
            return ReportSettingsLayout.pageCount(request.settingsSnapshot, paper: request.paper)
        default:
            return 1
        }
    }

    /// The report laid out: part by part; with two units, a part's pages in the first unit, then in the second.
    func layout(calendar: Calendar) -> Layout {
        let dayRows = dayRows(calendar: calendar)
        let pages = request.parts.flatMap { part -> [ReportPage] in
            let count = pageCount(of: part, dayRows: dayRows)
            let size = request.size(of: part)
            // a part without glucose values is printed once, not once per unit
            let printed = part.printsGlucose ? request.units : Array(request.units.prefix(1))
            return printed.flatMap { units in
                (0 ..< count).map { ReportPage(part: part, units: units, size: size, index: $0) }
            }
        }
        return Layout(pages: pages, dayRows: dayRows)
    }

    func pages(calendar: Calendar) -> [ReportPage] {
        layout(calendar: calendar).pages
    }
}

extension Stat {
    /// A page of the Days table, formatted.
    struct ReportDaysPage: Equatable {
        enum Kind: Int, Sendable {
            case inRange
            case below
            case above
            case mean
            case sd
            case cv
            case lowHigh
            case coverage
            case tdd
            case basal
            case bolus
            case carbs
        }

        struct Column: Equatable, Identifiable {
            let kind: Kind
            /// "In range"
            let title: String
            /// "70–180", "mg/dL", "U"
            let subtitle: String
            /// its share of the width left of the date and the bar
            let weight: CGFloat

            var id: Int { kind.rawValue }
        }

        enum Style: Equatable {
            case day
            case subtotal
            case average
        }

        struct Row: Equatable, Identifiable {
            let id: Int
            let style: Style
            /// "Tue 20 Oct", "19 Oct – 25 Oct", "October 2026", "Average of 14 days"
            let title: String
            /// the nonzero bands, very low first; none without readings
            let segments: [BandSegment]
            /// by column
            let cells: [String]
        }

        /// "Date"
        let dateTitle: String
        let columns: [Column]
        let rows: [Row]
        /// under the table
        let footnote: String

        /// A day as its row writes it, in the calendar's time zone: "Tue 20 Oct".
        static func dayStyle(_ calendar: Calendar) -> Date.FormatStyle {
            var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            style.timeZone = calendar.timeZone
            return style
        }

        /// - Parameters:
        ///   - page: one of the part's (`index`): its rows
        ///   - rows: the table's rows page by page (`ReportData.Layout.dayRows`: built once for the report); nil: built here
        ///   - calendar: the days' (the subtotals' weeks and months, the dates' time zone)
        @MainActor init(_ data: ReportData, page: ReportPage, rows dayRows: [[ReportDaysRow]]? = nil, calendar: Calendar) {
            typealias Format = StatsFormatting
            let units = page.units
            let settings = data.request.daysTable
            let labels = ReportBuilder.standardBands(units)
            let unit = Format.unit(units)
            let insulinUnit = NSLocalizedString("U", comment: "Insulin unit")

            dateTitle = NSLocalizedString("Date", comment: "")
            var columns: [Column] = [
                Column(
                    kind: .inRange,
                    title: Format.name(.inRange),
                    subtitle: Format.label(.inRange, bands: labels, units: units) ?? "",
                    weight: 1.1
                ),
                Column(
                    kind: .below,
                    title: NSLocalizedString("Below", comment: "PDF report, Days table: the time below the in-range band"),
                    subtitle: "< " + Format.glucose(labels.low, units: units),
                    weight: 1
                ),
                Column(
                    kind: .above,
                    title: NSLocalizedString("Above", comment: "PDF report, Days table: the time above the in-range band"),
                    subtitle: "> " + Format.glucose(labels.high, units: units),
                    weight: 1
                ),
                Column(
                    kind: .mean,
                    title: NSLocalizedString("Mean", comment: "Statistics, mean glucose"),
                    subtitle: unit,
                    weight: 1
                )
            ]
            if settings.sdAndCV {
                columns.append(Column(kind: .sd, title: NSLocalizedString("SD", comment: ""), subtitle: unit, weight: 0.9))
                columns.append(Column(kind: .cv, title: NSLocalizedString("CV", comment: ""), subtitle: "%", weight: 0.9))
            }
            if settings.lowestAndHighest {
                columns.append(
                    Column(
                        kind: .lowHigh,
                        title: NSLocalizedString(
                            "Low–high",
                            comment: "PDF report, Days table: the lowest and the highest reading"
                        ),
                        subtitle: unit,
                        weight: 1.5
                    )
                )
            }
            if settings.cgmCoverage {
                columns.append(
                    Column(
                        kind: .coverage,
                        title: NSLocalizedString("CGM", comment: "Statistics topic: the CGM's own readings"),
                        subtitle: "%",
                        weight: 0.9
                    )
                )
            }
            if settings.insulin {
                columns.append(
                    Column(
                        kind: .tdd,
                        title: NSLocalizedString("Insulin", comment: "Statistics topic"),
                        subtitle: insulinUnit,
                        weight: 1.1
                    )
                )
                columns.append(Column(kind: .basal, title: InsulinPart.basal.name, subtitle: insulinUnit, weight: 1))
                columns.append(
                    Column(
                        kind: .bolus,
                        title: NSLocalizedString("Bolus + SMB", comment: "PDF report, Days table: the boluses and the SMBs"),
                        subtitle: insulinUnit,
                        weight: 1.2
                    )
                )
            }
            if settings.carbs {
                columns.append(
                    Column(kind: .carbs, title: NSLocalizedString("Carbs", comment: ""), subtitle: "g", weight: 1)
                )
            }
            self.columns = columns

            let pages = dayRows ?? data.dayRows(calendar: calendar)
            let pageRows = pages.indices.contains(page.index) ? pages[page.index] : []
            let dayStyle = Self.dayStyle(calendar)
            var shortStyle = Date.FormatStyle.dateTime.day().month(.abbreviated)
            shortStyle.timeZone = calendar.timeZone
            var monthStyle = Date.FormatStyle.dateTime.month(.wide).year()
            monthStyle.timeZone = calendar.timeZone
            let kinds = columns.map(\.kind)
            rows = pageRows.enumerated().map { index, row -> Row in
                let numbers = row.numbers
                let title: String
                let style: Style
                switch row {
                case let .day(day, _):
                    title = day.formatted(dayStyle)
                    style = .day
                case let .subtotal(first, last, _):
                    title = settings.subtotals == .month
                        ? first.formatted(monthStyle)
                        : first == last ? first.formatted(shortStyle) : String(
                            format: NSLocalizedString("%@ – %@", comment: "Statistics date range, first and last day"),
                            first.formatted(shortStyle),
                            last.formatted(shortStyle)
                        )
                    style = .subtotal
                case let .average(days, _):
                    title = String(
                        format: NSLocalizedString(
                            "Average of %d days",
                            comment: "PDF report, Days table: the last row, with the period's days"
                        ),
                        days
                    )
                    style = .average
                }
                return Row(
                    id: index,
                    style: style,
                    title: title,
                    segments: numbers.shares?.barSegments(GlucoseBand.allCases) ?? [],
                    cells: kinds.map { Self.cell($0, numbers, units: units) }
                )
            }

            // what couldn't be read first: its columns are dashes for that, not for a lack of data
            var notes: [String] = []
            let insulinFailed = settings.insulin && data.failedReads.contains(.insulin)
            let carbsFailed = settings.carbs && data.failedReads.contains(.meals)
            if insulinFailed {
                notes.append(
                    NSLocalizedString("Insulin data could not be read.", comment: "PDF report: the insulin days' read failed")
                )
            }
            if carbsFailed {
                notes.append(
                    NSLocalizedString("Carb entries could not be read.", comment: "PDF report: the meals' read failed")
                )
            }
            notes.append(
                NSLocalizedString(
                    "Averages: glucose is time-weighted over the days.",
                    comment: "PDF report, Days table footnote"
                )
            )
            if settings.insulin, !insulinFailed {
                notes.append(
                    NSLocalizedString(
                        "Insulin is averaged over complete days, the basal scaled to the whole day; * a day outside them (today, or pump data for less than half of it), as delivered.",
                        comment: "PDF report, Days table footnote: the insulin columns"
                    )
                )
            }
            if settings.carbs, !carbsFailed {
                notes.append(
                    NSLocalizedString(
                        "Carbs are averaged over complete days with entries.",
                        comment: "PDF report, Days table footnote: the carbs column"
                    )
                )
            }
            footnote = notes.joined(separator: " ")
        }

        /// "<1%" for a nonzero share that rounds to 0.
        static func percent(_ value: Double) -> String {
            let rounded = Int(value.rounded())
            return value > 0 && rounded == 0 ? "<1%" : "\(rounded)%"
        }

        @MainActor static func cell(_ kind: Kind, _ numbers: ReportDaysNumbers, units: GlucoseUnits) -> String {
            typealias Format = StatsFormatting
            let dash = "–"
            switch kind {
            case .inRange: return numbers.shares.map { Format.percent(.inRange, of: $0) } ?? dash
            case .below: return numbers.below.map { percent($0) } ?? dash
            case .above: return numbers.above.map { percent($0) } ?? dash
            case .mean: return numbers.mean.map { Format.glucose($0, units: units) } ?? dash
            case .sd: return numbers.sd.map { Format.glucose($0, units: units) } ?? dash
            case .cv: return numbers.cv.map { Format.percent(Int($0.rounded())) } ?? dash
            case .lowHigh:
                guard let lowest = numbers.lowest, let highest = numbers.highest else { return dash }
                return Format.glucose(lowest, units: units) + "–" + Format.glucose(highest, units: units)
            case .coverage: return numbers.coverage.map { Format.percent($0) } ?? dash
            case .tdd:
                guard let tdd = numbers.tdd else { return dash }
                return StatsAmount.number(tdd, digits: 1) + (numbers.insulinOutsideAverage ? "*" : "")
            case .basal: return numbers.basal.map { StatsAmount.number($0, digits: 1) } ?? dash
            case .bolus: return numbers.bolus.map { StatsAmount.number($0, digits: 1) } ?? dash
            case .carbs: return numbers.carbs.map { StatsAmount.number($0, digits: 0) } ?? dash
            }
        }
    }
}
