import CoreGraphics
import Foundation

// The Insulin and Meals parts of a report: what the Insulin and Meals tabs show for the period, without anything that
// depends on a selection. The first page is the overview (the averages, the days and the clock hours as bar charts),
// the pages after it the same numbers as tables: every clock hour, then every day. The numbers are the tabs'
// (`InsulinPeriod`, `MealPeriod`: the same reads and rules); nothing here is in glucose units, so the parts are printed
// once, whatever the units of the report.

/// How the Insulin and Meals parts are laid out: an overview page, then the table pages. Every row has a fixed height,
/// so the rows a page holds are known before anything is drawn.
enum ReportTablesLayout {
    /// a row of a table
    static let rowHeight: CGFloat = 12
    /// a section's title with its rule and the space around it
    static let sectionHeight: CGFloat = 28
    /// a table's column titles (two lines) with their rule
    static let headerHeight: CGFloat = 24
    /// the note under the days (two lines)
    static let footnoteHeight: CGFloat = 24
    /// the space between the two tables
    static let spacing: CGFloat = 8

    /// The clock hours' table.
    /// - Parameter hourRows: its rows: the 24 hours, and Meals' line under them
    static func hoursHeight(_ hourRows: Int) -> CGFloat {
        sectionHeight + headerHeight + CGFloat(hourRows) * rowHeight + spacing
    }

    /// The height of a (portrait) page's content.
    static func available(_ paper: ReportPaper) -> CGFloat {
        paper.size.height - ReportStyle.margin * 2 - ReportGoodBadDaysLayout.chrome
    }

    /// The day rows a table page holds: the first one under the clock hours' table.
    /// - Parameter hourRows: the clock hours' table's rows on the first table page; nil: a later page, without it
    static func rowsPerPage(_ paper: ReportPaper, hourRows: Int?) -> Int {
        let height = available(paper) - sectionHeight - headerHeight - footnoteHeight
            - (hourRows.map { hoursHeight($0) } ?? 0)
        return Swift.max(Int(height / rowHeight), 4)
    }

    /// The day rows of each table page (there is always one, with the clock hours). The averages' row is never alone
    /// on the last page: the last day goes there with it.
    /// - Parameters:
    ///   - rows: the days' rows, the average's too
    ///   - hourRows: the clock hours' table's rows
    static func dayRanges(rows: Int, paper: ReportPaper, hourRows: Int) -> [Range<Int>] {
        let count = Swift.max(rows, 0)
        let first = Swift.min(count, rowsPerPage(paper, hourRows: hourRows))
        var ranges = [0 ..< first]
        let perPage = rowsPerPage(paper, hourRows: nil)
        var lower = first
        while lower < count {
            let upper = Swift.min(lower + perPage, count)
            ranges.append(lower ..< upper)
            lower = upper
        }
        if ranges.count > 1, let last = ranges.last, last.count == 1, ranges[ranges.count - 2].count > 1 {
            let previous = ranges[ranges.count - 2]
            ranges[ranges.count - 2] = previous.lowerBound ..< previous.upperBound - 1
            ranges[ranges.count - 1] = last.lowerBound - 1 ..< last.upperBound
        }
        return ranges
    }

    /// The pages of a part with `days` days: the overview and the table pages.
    static func pageCount(days: Int, paper: ReportPaper, hourRows: Int) -> Int {
        1 + dayRanges(rows: days + 1, paper: paper, hourRows: hourRows).count
    }
}

/// Amounts rounded so that the parts printed add up to the total printed.
enum ReportAmounts {
    /// `values` rounded to `decimals` so that their sum is the rounded sum of the exact values (largest remainder: each
    /// rounded down, then the steps left given to the largest remainders, ties to the earlier one; remainders are
    /// compared in millionths, so two that differ only by the binary fractions' noise are a tie). Negative values count
    /// as 0.
    static func split(_ values: [Double], decimals: Int) -> (parts: [Double], total: Double) {
        let scale = pow(10, Double(Swift.max(decimals, 0)))
        let scaled = values.map { Swift.max($0, 0) * scale }
        let target = Int(scaled.reduce(0, +).rounded())
        var floors = scaled.map { Int($0.rounded(.down)) }
        let left = target - floors.reduce(0, +)
        if left > 0 {
            let remainders = scaled.indices.map { ((scaled[$0] - Double(floors[$0])) * 1E6).rounded() }
            let order = scaled.indices.sorted { a, b in
                remainders[a] == remainders[b] ? a < b : remainders[a] > remainders[b]
            }
            for index in order.prefix(left) {
                floors[index] += 1
            }
        }
        return (floors.map { Double($0) / scale }, Double(target) / scale)
    }
}

extension Stat {
    /// A bar chart of a report: a bar a day or a clock hour, its parts stacked from the bottom.
    struct ReportBars: Equatable {
        struct Bar: Equatable, Identifiable {
            let id: Int
            /// by series, from the bottom
            let values: [Double]
            /// "*" above it
            var isMarked = false
        }

        struct Tick: Equatable, Identifiable {
            /// the bar its label is under
            let id: Int
            let label: String
        }

        struct LegendItem: Equatable, Identifiable {
            enum Key: Equatable {
                case swatch(StatsBarStyle)
                case dashed
                case step
                case mark
            }

            let id: Int
            let key: Key
            let title: String
        }

        let bars: [Bar]
        /// by series
        let styles: [StatsBarStyle]
        /// the gridlines, the first 0 and the last the top of the scale
        let levels: [Double]
        let levelLabels: [String]
        /// a dashed line across: the average; nil without one
        let average: Double?
        /// a stepped line over the bars, by bar (the scheduled basal by hour); nil where there is none
        var steps: [Double?] = []
        let ticks: [Tick]
        let legend: [LegendItem]

        var top: Double { Swift.max(levels.last ?? 1, .leastNonzeroMagnitude) }

        /// The days' labels: every day up to a week, every second up to two, then every seventh, from the first.
        @MainActor static func dayTicks(_ days: [Date], calendar: Calendar) -> [Tick] {
            var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            style.timeZone = calendar.timeZone
            let step = days.count <= 7 ? 1 : (days.count <= 14 ? 2 : 7)
            return stride(from: 0, to: days.count, by: step).map { Tick(id: $0, label: days[$0].formatted(style)) }
        }

        /// Every third clock hour.
        @MainActor static var hourTicks: [Tick] {
            stride(from: 0, to: 24, by: 3).map { Tick(id: $0, label: AGP.clockTime($0 * 60)) }
        }
    }

    /// A table of a report: the first column the row's name, the others numbers.
    struct ReportTable: Equatable {
        struct Column: Equatable, Identifiable {
            let id: Int
            /// "Basal"
            let title: String
            /// "U", "U per hour"
            let subtitle: String
        }

        struct Row: Equatable, Identifiable {
            let id: Int
            /// "Tue 20 Oct", "08:00–09:00"
            let title: String
            /// by column
            let cells: [String]
            /// the average's, the total's
            var isEmphasized = false
        }

        /// the first column's title: "Date", "Time"
        let name: String
        let columns: [Column]
        let rows: [Row]
    }

    /// A number of an overview page with its name: "Basal vs scheduled", "96%".
    struct ReportFigure: Equatable, Identifiable {
        let id: Int
        let title: String
        let value: String
        /// "U per day"
        var unit: String?
    }

    // MARK: - Insulin

    /// A page of the Insulin part.
    struct ReportInsulin: Equatable {
        /// the clock hours' table's rows
        static let hourRows = 24

        /// Basal, SMB or bolus of the average day.
        struct Part: Equatable, Identifiable {
            let id: Int
            let name: String
            /// "17.1 U"
            let value: String
            /// "41%"
            let percent: String
            /// of the bar, 0...1
            let fraction: Double
            let style: StatsBarStyle
        }

        let header: ReportPageHeader
        /// in place of everything: no pump data in the period, or it couldn't be read
        let emptyNote: String?
        /// the first page: the averages and the charts; the others are the tables
        let isOverview: Bool

        /// "41.5", "–" without a complete day
        let tdd: String
        /// "U per day · average of 13 complete days", "Needs one complete day"
        let tddNote: String
        let parts: [Part]
        /// the basal against the schedule, the time at zero basal and below zero IOB, the pump data's coverage
        let figures: [ReportFigure]
        /// why the averages are provisional, the profile assumed: under the figures
        let notes: [String]
        let dayBars: ReportBars
        let hourBars: ReportBars

        /// the clock hours; nil on the pages without it
        let hourTable: ReportTable?
        /// this page's days (the average's row after the last one); nil on the overview
        let dayTable: ReportTable?
        /// under the days
        let footnote: String

        /// A day's cells: total, basal, SMB, bolus (the parts add up to the total as printed), the basal against the
        /// schedule, the time at zero basal, the pump data's coverage. Without covered time the basal, and so the total,
        /// is unknown; "*" marks a day outside the averages (today, or pump data for less than half of it).
        @MainActor static func cells(_ day: DayInsulin) -> [String] {
            typealias Format = StatsFormatting
            let dash = "–"
            guard day.hasData else { return Array(repeating: dash, count: 7) }
            let covered = day.coveredSeconds > 0
            let split = ReportAmounts.split([covered ? day.basal : 0, day.smb, day.bolus], decimals: 1)
            let mark = day.isHeadline ? "" : "*"
            return [
                covered ? StatsAmount.number(split.total, digits: 1) + mark : dash + mark,
                covered ? StatsAmount.number(split.parts[0], digits: 1) : dash,
                StatsAmount.number(split.parts[1], digits: 1),
                StatsAmount.number(split.parts[2], digits: 1),
                (covered ? day.basalVsScheduled : nil).map { Format.percent(fraction: $0) } ?? dash,
                covered ? Format.duration(seconds: day.zeroBasalSeconds) : dash,
                day.isToday ? dash : Format.percent(Int((day.coverageFraction * 100).rounded()))
            ]
        }

        /// The pump data's coverage of the complete days averaged (`DayInsulin.isHeadline`), their mean, percent; nil
        /// without one.
        static func averageCoverage(_ days: [DayInsulin]) -> Int? {
            let averaged = days.filter(\.isHeadline)
            guard averaged.isNotEmpty else { return nil }
            return Int((averaged.reduce(0) { $0 + $1.coverageFraction } / Double(averaged.count) * 100).rounded())
        }

        /// The averages' cells, as a day's: the means over the complete days, the basal scaled to the whole day, the
        /// pump data's coverage of those days.
        @MainActor static func averageCells(_ period: InsulinPeriod) -> [String] {
            typealias Format = StatsFormatting
            let dash = "–"
            let summary = period.summary
            guard summary.tdd != nil else { return Array(repeating: dash, count: 7) }
            let split = ReportAmounts.split([summary.basal ?? 0, summary.smb ?? 0, summary.bolus ?? 0], decimals: 1)
            return [
                StatsAmount.number(split.total, digits: 1),
                StatsAmount.number(split.parts[0], digits: 1),
                StatsAmount.number(split.parts[1], digits: 1),
                StatsAmount.number(split.parts[2], digits: 1),
                summary.basalVsScheduledPercent.map { Format.percent($0) } ?? dash,
                summary.zeroBasalSecondsPerDay.map { Format.duration(seconds: $0) } ?? dash,
                averageCoverage(period.days).map { Format.percent($0) } ?? dash
            ]
        }

        /// A clock hour's cells: basal and scheduled basal (U per hour of pump data), SMB and bolus (U per day in the
        /// hour), their total (the parts add up to it as printed), the basal against the schedule, the time at zero
        /// basal.
        @MainActor static func cells(_ hour: InsulinHourSummary) -> [String] {
            typealias Format = StatsFormatting
            let dash = "–"
            let split = ReportAmounts.split([hour.basal ?? 0, hour.smb, hour.bolus], decimals: 2)
            let hasData = Insulin.hasData(hour)
            return [
                hour.basal == nil ? dash : StatsAmount.number(split.parts[0], digits: 2),
                hour.scheduled.map { StatsAmount.number($0, digits: 2) } ?? dash,
                StatsAmount.number(split.parts[1], digits: 2),
                StatsAmount.number(split.parts[2], digits: 2),
                hasData ? StatsAmount.number(split.total, digits: 2) : dash,
                hour.basalVsScheduled.map { Format.percent(fraction: $0) } ?? dash,
                hour.zeroBasalSeconds.map { Format.duration(seconds: $0) } ?? dash
            ]
        }

        /// A row of the page's days has a "*" after its first number.
        static func isMarked(_ table: ReportTable?) -> Bool {
            table?.rows.contains { $0.cells.first?.hasSuffix("*") ?? false } ?? false
        }

        /// The days' rows, oldest first, then the averages'.
        @MainActor static func dayRows(_ period: InsulinPeriod, calendar: Calendar) -> [ReportTable.Row] {
            let style = ReportDaysPage.dayStyle(calendar)
            var rows = period.days.enumerated().map { index, day in
                ReportTable.Row(id: index, title: day.day.start.formatted(style), cells: cells(day))
            }
            rows.append(
                ReportTable.Row(
                    id: rows.count,
                    title: String(
                        format: NSLocalizedString(
                            "Average of %d complete days",
                            comment: "PDF report, Insulin: the averages' row, the days averaged"
                        ),
                        period.summary.headlineDays
                    ),
                    cells: averageCells(period),
                    isEmphasized: true
                )
            )
            return rows
        }

        /// - Parameters:
        ///   - page: one of the part's (`index`)
        ///   - calendar: the days' (their names, the dates' time zone)
        @MainActor init(_ data: ReportData, page: ReportPage, calendar: Calendar) {
            typealias Format = StatsFormatting
            let read = data.insulinPeriod
            let period = read?.value
            let summary = period?.summary
            isOverview = page.index == 0

            // the tab's own days (a view's own export reads nothing else); without them the report's
            let days = summary.map { ReportData.days(of: $0.window, calendar: calendar) } ?? data.days(calendar: calendar)
            header = ReportPageHeader(
                dateRange: ReportPageHeader.dateRange(days.first, days.last, calendar: calendar),
                days: summary.map {
                    String(
                        format: NSLocalizedString(
                            "Days with pump data %@",
                            comment: "Statistics Insulin: the days with pump data, \"5 of 7\""
                        ),
                        Format.days($0.daysWithData, of: $0.calendarDays)
                    )
                } ?? ""
            )
            if read == .failed || read == nil {
                emptyNote = NSLocalizedString("The pump data couldn't be read.", comment: "")
            } else if summary?.isEmpty ?? true {
                emptyNote = NSLocalizedString("No pump data in this period", comment: "")
            } else {
                emptyNote = nil
            }

            let parts = InsulinPart.allCases
            let means = [summary?.basal, summary?.smb, summary?.bolus]
            let split = ReportAmounts.split(means.map { $0 ?? 0 }, decimals: 1)
            tdd = summary?.tdd == nil ? "–" : StatsAmount.number(split.total, digits: 1)
            tddNote = summary?.tdd == nil
                ? Insulin.noCompleteDay
                : String(
                    format: NSLocalizedString(
                        "U per day · average of %d complete days",
                        comment: "PDF report, Insulin: the total daily dose's unit and the days averaged"
                    ),
                    summary?.headlineDays ?? 0
                )
            self.parts = parts.map { part in
                Part(
                    id: part.rawValue,
                    name: part.name,
                    value: summary?.tdd == nil ? "–" : StatsAmount.units(split.parts[part.rawValue], digits: 1),
                    percent: summary?.tdd == nil ? "–" : Format.percent(summary?.splitPercents[part.rawValue] ?? 0),
                    fraction: split.total > 0 ? split.parts[part.rawValue] / split.total : 0,
                    style: part.style
                )
            }
            let perDay = NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count")
            figures = [
                ReportFigure(
                    id: 0,
                    title: NSLocalizedString(
                        "Basal vs scheduled",
                        comment: "PDF report, Insulin: the basal as a share of the schedule"
                    ),
                    value: summary?.basalVsScheduledPercent.map { Format.percent($0) } ?? "–"
                ),
                ReportFigure(
                    id: 1,
                    title: NSLocalizedString("Scheduled basal", comment: "Statistics Insulin: the basal schedule"),
                    value: summary?.scheduledPerDay.map { StatsAmount.number($0, digits: 1) } ?? "–",
                    unit: NSLocalizedString("U per day", comment: "Statistics Insulin: the unit of a daily amount")
                ),
                ReportFigure(
                    id: 2,
                    title: NSLocalizedString("Time at zero basal", comment: "Statistics Good & bad days: a factor"),
                    value: summary?.zeroBasalSecondsPerDay.map { Format.duration(seconds: $0) } ?? "–",
                    unit: perDay
                ),
                ReportFigure(
                    id: 3,
                    title: NSLocalizedString("IOB below zero", comment: "PDF report, Insulin: the time the IOB is negative"),
                    value: summary?.negativeIOBSecondsPerDay.map { Format.duration(seconds: $0) } ?? "–",
                    unit: perDay
                ),
                ReportFigure(
                    id: 4,
                    title: NSLocalizedString("Pump data coverage", comment: "PDF report, Insulin: the time the pump data covers"),
                    value: summary.map { Format.percent($0.coveragePercent) } ?? "–"
                )
            ]
            var notes: [String] = []
            if let summary, let note = Insulin.limitedNote(summary) {
                notes.append(note)
            }
            if let summary, let note = Insulin.profileAssumedNote(summary, calendar: calendar) {
                notes.append(note)
            }
            self.notes = notes

            dayBars = Self.dayBars(period, calendar: calendar)
            hourBars = Self.hourBars(period?.hours ?? [])

            let unit = NSLocalizedString("U", comment: "Insulin unit")
            let ranges = ReportTablesLayout.dayRanges(
                rows: (period?.days.count ?? 0) + 1,
                paper: data.request.paper,
                hourRows: Self.hourRows
            )
            let table = page.index - 1
            if let period, !isOverview, ranges.indices.contains(table) {
                let rows = Self.dayRows(period, calendar: calendar)
                let range = ranges[table].clamped(to: 0 ..< rows.count)
                dayTable = ReportTable(
                    name: NSLocalizedString("Date", comment: "PDF report, Days table: the day's column"),
                    columns: [
                        ReportTable.Column(id: 0, title: NSLocalizedString("Total", comment: ""), subtitle: unit),
                        ReportTable.Column(id: 1, title: InsulinPart.basal.name, subtitle: unit),
                        ReportTable.Column(id: 2, title: InsulinPart.smb.name, subtitle: unit),
                        ReportTable.Column(id: 3, title: InsulinPart.bolus.name, subtitle: unit),
                        ReportTable.Column(
                            id: 4,
                            title: InsulinPart.basal.name,
                            subtitle: NSLocalizedString(
                                "vs scheduled",
                                comment: "Statistics Insulin day: the basal as a share of the schedule"
                            )
                        ),
                        ReportTable.Column(
                            id: 5,
                            title: NSLocalizedString("Zero basal", comment: "PDF report, Insulin: the time at zero basal"),
                            subtitle: NSLocalizedString("time", comment: "PDF report: a column of durations")
                        ),
                        ReportTable.Column(
                            id: 6,
                            title: NSLocalizedString(
                                "Pump data",
                                comment: "PDF report, Insulin: the pump data's coverage of the day"
                            ),
                            subtitle: NSLocalizedString("of the day", comment: "PDF report, Insulin: what the coverage is of")
                        )
                    ],
                    rows: Array(rows[range])
                )
                hourTable = table == 0 ? Self.hourTable(period.hours) : nil
            } else {
                dayTable = nil
                hourTable = nil
            }
            // the "*" is explained on the pages that have one
            footnote = Self.isMarked(dayTable)
                ? NSLocalizedString(
                    "Insulin is averaged over complete days, the basal scaled to the whole day; * a day outside them (today, or pump data for less than half of it), as delivered.",
                    comment: "PDF report, Days table footnote: the insulin columns"
                )
                : NSLocalizedString(
                    "Insulin is averaged over complete days, the basal scaled to the whole day.",
                    comment: "PDF report, Insulin: the note under the days, on a page without a * day"
                )
        }

        @MainActor private static func hourTable(_ hours: [InsulinHourSummary]) -> ReportTable {
            let perHour = NSLocalizedString("U per hour", comment: "Statistics Insulin by hour: the unit")
            let inHour = NSLocalizedString("U per day", comment: "Statistics Insulin: the unit of a daily amount")
            return ReportTable(
                name: NSLocalizedString("Time", comment: ""),
                columns: [
                    ReportTable.Column(id: 0, title: InsulinPart.basal.name, subtitle: perHour),
                    ReportTable.Column(
                        id: 1,
                        title: NSLocalizedString("Scheduled", comment: "Statistics Insulin: the scheduled basal"),
                        subtitle: perHour
                    ),
                    ReportTable.Column(id: 2, title: InsulinPart.smb.name, subtitle: inHour),
                    ReportTable.Column(id: 3, title: InsulinPart.bolus.name, subtitle: inHour),
                    ReportTable.Column(id: 4, title: NSLocalizedString("Total", comment: ""), subtitle: inHour),
                    ReportTable.Column(
                        id: 5,
                        title: InsulinPart.basal.name,
                        subtitle: NSLocalizedString(
                            "vs scheduled",
                            comment: "Statistics Insulin day: the basal as a share of the schedule"
                        )
                    ),
                    ReportTable.Column(
                        id: 6,
                        title: NSLocalizedString("Zero basal", comment: "PDF report, Insulin: the time at zero basal"),
                        subtitle: NSLocalizedString("per hour", comment: "PDF report, Insulin: the time at zero basal in an hour")
                    )
                ],
                rows: hours.map { hour in
                    ReportTable.Row(
                        id: hour.hour,
                        title: AGP.clockInterval(from: hour.hour * 60, to: (hour.hour + 1) * 60),
                        cells: cells(hour)
                    )
                }
            )
        }

        /// Day by day: the parts stacked (the basal only with covered time, as the tab's), the average dashed, "*"
        /// above a day outside the averages.
        @MainActor private static func dayBars(_ period: InsulinPeriod?, calendar: Calendar) -> ReportBars {
            let parts = InsulinPart.allCases
            let days = period?.days ?? []
            let values = days.map(Insulin.dayValues)
            let tdd = period?.summary.tdd
            let levels = StatsBarAxis.levels(
                maximum: Swift.max(values.map { $0.reduce(0, +) }.max() ?? 0, tdd ?? 0),
                unit: Insulin.dayAxisUnit,
                divisions: 3
            )
            let marked = days.map { $0.hasData && !$0.isHeadline }
            var legend = parts.map {
                ReportBars.LegendItem(id: $0.rawValue, key: .swatch($0.style), title: $0.name)
            }
            if let tdd {
                legend.append(
                    ReportBars.LegendItem(
                        id: 10,
                        key: .dashed,
                        title: String(
                            format: NSLocalizedString("Average %@ U", comment: "Statistics Insulin chart legend: the TDD"),
                            StatsAmount.number(tdd, digits: 1)
                        )
                    )
                )
            }
            if marked.contains(true) {
                legend.append(
                    ReportBars.LegendItem(
                        id: 11,
                        key: .mark,
                        title: NSLocalizedString(
                            "not in the average, as delivered",
                            comment: "PDF report, Insulin chart legend: the * above a day outside the averages"
                        )
                    )
                )
            }
            return ReportBars(
                bars: days.indices.map { ReportBars.Bar(id: $0, values: values[$0], isMarked: marked[$0]) },
                styles: parts.map(\.style),
                levels: levels,
                levelLabels: levels.map { StatsAmount.number($0, digits: 0) },
                average: tdd,
                ticks: ReportBars.dayTicks(days.map(\.day.start), calendar: calendar),
                legend: legend
            )
        }

        /// By hour: the parts stacked by clock hour, the scheduled basal as steps.
        @MainActor private static func hourBars(_ hours: [InsulinHourSummary]) -> ReportBars {
            let parts = InsulinPart.allCases
            let levels = StatsBarAxis.levels(
                maximum: hours.map { Swift.max($0.total, $0.scheduled ?? 0) }.max() ?? 0,
                unit: 0.5,
                divisions: 2
            )
            return ReportBars(
                bars: hours.map { ReportBars.Bar(id: $0.hour, values: [$0.basal ?? 0, $0.smb, $0.bolus]) },
                styles: parts.map(\.style),
                levels: levels,
                levelLabels: levels.map { StatsAmount.number($0, digits: 0 ... 2) },
                average: nil,
                steps: hours.map(\.scheduled),
                ticks: ReportBars.hourTicks,
                legend: parts.map { ReportBars.LegendItem(id: $0.rawValue, key: .swatch($0.style), title: $0.name) } + [
                    ReportBars.LegendItem(
                        id: 10,
                        key: .step,
                        title: NSLocalizedString("Scheduled basal", comment: "Statistics Insulin: the basal schedule")
                    )
                ]
            )
        }
    }

    // MARK: - Meals

    /// A page of the Meals part.
    struct ReportMeals: Equatable {
        /// the clock hours' table's rows: the hours and the line under them
        static let hourRows = 25

        /// A line of "Most carbs".
        struct TopHour: Equatable, Identifiable {
            let id: Int
            /// "12:00–13:00"
            let time: String
            /// "entries on 11 of 14 days · 41 g each"
            let detail: String
            /// "28%"
            let percent: String
        }

        let header: ReportPageHeader
        /// in place of everything: no carb entry in the period, or the entries couldn't be read
        let emptyNote: String?
        let isOverview: Bool
        /// fat, protein and carb equivalents are printed: asked for, and logged
        let showsNutrients: Bool

        /// "182", "–" without a complete day with entries
        let carbs: String
        /// "g per day · average of 12 days with entries", "No entries on a complete day yet"
        let carbsNote: String
        /// entries per day, per entry; with the nutrients: fat, protein and carb equivalents per day
        let figures: [ReportFigure]
        /// why the averages are provisional
        let notes: [String]
        let dayBars: ReportBars
        let hourBars: ReportBars
        /// up to 3, the most first
        let topHours: [TopHour]

        let hourTable: ReportTable?
        let dayTable: ReportTable?
        let footnote: String

        /// The fat, protein and carb equivalents are printed: the setting is on and an entry of the last 90 days has
        /// fat or protein (as the tab shows its tiles).
        static func printsNutrients(_ settings: ReportOptions.MealsSettings, summary: MealSummary?) -> Bool {
            settings.includeNutrients && (summary?.logsFatOrProtein ?? false)
        }

        /// A day's cells: carbs, entries; with the nutrients: fat, protein, carb equivalents. "*" marks today (so far,
        /// not in the averages); a day without entries has no amounts.
        @MainActor static func cells(_ day: DayMeals, nutrients: Bool) -> [String] {
            let dash = "–"
            guard day.hasEntries else {
                return [dash, "0"] + (nutrients ? [dash, dash, dash] : [])
            }
            var cells = [
                StatsAmount.number(day.carbs, digits: 0) + (day.isToday ? "*" : ""),
                "\(day.entries.count)"
            ]
            if nutrients {
                cells += [
                    StatsAmount.number(day.fat, digits: 0),
                    StatsAmount.number(day.protein, digits: 0),
                    StatsAmount.number(day.carbEquivalents, digits: 0)
                ]
            }
            return cells
        }

        /// The averages' cells, as a day's: over the complete days with entries.
        @MainActor static func averageCells(_ summary: MealSummary, nutrients: Bool) -> [String] {
            let dash = "–"
            var cells = [
                summary.carbsPerDay.map { StatsAmount.number($0, digits: 0) } ?? dash,
                summary.entriesPerDay.map { StatsAmount.number($0, digits: 1) } ?? dash
            ]
            if nutrients {
                cells += [
                    summary.fatPerDay.map { StatsAmount.number($0, digits: 0) } ?? dash,
                    summary.proteinPerDay.map { StatsAmount.number($0, digits: 0) } ?? dash,
                    summary.carbEquivalentsPerDay.map { StatsAmount.number($0, digits: 0) } ?? dash
                ]
            }
            return cells
        }

        /// The clock hours' shares of the carbs as printed, percent: largest remainder, so they add up to 100.
        static func shares(_ hours: [HourMeals]) -> [Int] {
            GlucoseStatsEngine.largestRemainder(hours.map(\.share))
        }

        /// The clock hours' rows and the line under them: the carbs per day by the hour of entry (to one decimal, adding
        /// up to the line's total as printed), the share of the carbs (adding up to 100%), the entries, the days with
        /// an entry in the hour, the carbs per entry.
        @MainActor static func hourRows(_ period: MealPeriod) -> [ReportTable.Row] {
            let dash = "–"
            let hours = period.hours
            let averaged = period.summary.daysWithEntries
            let split = ReportAmounts.split(hours.map(\.carbsPerDay), decimals: 1)
            let shares = Self.shares(hours)
            var rows = hours.enumerated().map { index, hour in
                ReportTable.Row(
                    id: hour.hour,
                    title: AGP.clockInterval(from: hour.hour * 60, to: (hour.hour + 1) * 60),
                    cells: [
                        StatsAmount.number(split.parts[index], digits: 1),
                        StatsFormatting.percent(shares[index]),
                        "\(hour.entries)",
                        averaged > 0 ? StatsFormatting.days(hour.daysWithEntries, of: averaged) : dash,
                        hour.perEntry.map { StatsAmount.number($0, digits: 0) } ?? dash
                    ]
                )
            }
            rows.append(
                ReportTable.Row(
                    id: 24,
                    title: NSLocalizedString("All day", comment: "PDF report, Meals by time of day: the line under the hours"),
                    cells: [
                        StatsAmount.number(split.total, digits: 1),
                        StatsFormatting.percent(shares.reduce(0, +)),
                        "\(hours.reduce(0) { $0 + $1.entries })",
                        // the hours' counts are of the days averaged: nothing to add up here
                        dash,
                        period.summary.perEntry.map { StatsAmount.number($0, digits: 0) } ?? dash
                    ],
                    isEmphasized: true
                )
            )
            return rows
        }

        /// The days' rows, oldest first, then the averages'.
        @MainActor static func dayRows(_ period: MealPeriod, nutrients: Bool, calendar: Calendar) -> [ReportTable.Row] {
            let style = ReportDaysPage.dayStyle(calendar)
            var rows = period.days.enumerated().map { index, day in
                ReportTable.Row(id: index, title: day.day.start.formatted(style), cells: cells(day, nutrients: nutrients))
            }
            rows.append(
                ReportTable.Row(
                    id: rows.count,
                    title: String(
                        format: NSLocalizedString(
                            "Average of %d days with entries",
                            comment: "PDF report, Meals: the averages' row, the days averaged"
                        ),
                        period.summary.daysWithEntries
                    ),
                    cells: averageCells(period.summary, nutrients: nutrients),
                    isEmphasized: true
                )
            )
            return rows
        }

        /// - Parameters:
        ///   - page: one of the part's (`index`)
        ///   - calendar: the days' (their names, the dates' time zone)
        @MainActor init(_ data: ReportData, page: ReportPage, calendar: Calendar) {
            typealias Format = StatsFormatting
            let read = data.mealPeriod
            let period = read?.value
            let summary = period?.summary
            let nutrients = Self.printsNutrients(data.request.meals, summary: summary)
            showsNutrients = nutrients
            isOverview = page.index == 0

            // the tab's own days (a view's own export reads nothing else); without them the report's
            let days = summary.map { ReportData.days(of: $0.window, calendar: calendar) } ?? data.days(calendar: calendar)
            header = ReportPageHeader(
                dateRange: ReportPageHeader.dateRange(days.first, days.last, calendar: calendar),
                days: summary.map {
                    String(
                        format: NSLocalizedString(
                            "Days with entries %@",
                            comment: "Statistics Meals: the complete days with carb entries, \"5 of 6\""
                        ),
                        Format.days($0.daysWithEntries, of: $0.completeDays)
                    )
                } ?? ""
            )
            if read == .failed || read == nil {
                emptyNote = NSLocalizedString("The carb entries couldn't be read.", comment: "")
            } else if summary?.isEmpty ?? true {
                emptyNote = NSLocalizedString("No carb entries in this period", comment: "")
            } else {
                emptyNote = nil
            }

            carbs = summary?.carbsPerDay.map { StatsAmount.number($0, digits: 0) } ?? "–"
            carbsNote = summary?.carbsPerDay == nil
                ? Meals.noCompleteDay
                : String(
                    format: NSLocalizedString(
                        "g per day · average of %d days with entries",
                        comment: "PDF report, Meals: the carbs' unit and the days averaged"
                    ),
                    summary?.daysWithEntries ?? 0
                )
            // the tab's tiles: entries and per entry, then fat, protein and carb equivalents
            let tiles = summary.map { Meals.entryTiles($0) + (nutrients ? Meals.nutrientTiles($0) : []) } ?? []
            figures = tiles.map { ReportFigure(id: $0.id, title: $0.title, value: $0.value, unit: $0.unit) }
            notes = summary.flatMap { Meals.limitedNote($0) }.map { [$0] } ?? []

            dayBars = Self.dayBars(period, nutrients: nutrients, calendar: calendar)
            hourBars = Self.hourBars(period?.hours ?? [])
            let averaged = summary?.daysWithEntries ?? 0
            // the tab's lines, with the shares the hours' table prints (adding up to 100%)
            let shares = Self.shares(period?.hours ?? [])
            topHours = Meals.topHours(period?.topHours ?? [], averagedDays: averaged).map { hour in
                TopHour(
                    id: hour.hour,
                    time: hour.time,
                    detail: hour.subtitle,
                    percent: shares.indices.contains(hour.hour) ? Format.percent(shares[hour.hour]) : hour.percent
                )
            }

            let grams = NSLocalizedString("g", comment: "Statistics Meals: grams")
            let ranges = ReportTablesLayout.dayRanges(
                rows: (period?.days.count ?? 0) + 1,
                paper: data.request.paper,
                hourRows: Self.hourRows
            )
            let table = page.index - 1
            if let period, !isOverview, ranges.indices.contains(table) {
                let rows = Self.dayRows(period, nutrients: nutrients, calendar: calendar)
                let range = ranges[table].clamped(to: 0 ..< rows.count)
                var columns = [
                    ReportTable.Column(id: 0, title: Meals.Part.carbs.name, subtitle: grams),
                    ReportTable.Column(
                        id: 1,
                        title: NSLocalizedString("Entries", comment: "Statistics Meals: the carb entries"),
                        subtitle: ""
                    )
                ]
                if nutrients {
                    columns += [
                        ReportTable.Column(id: 2, title: NSLocalizedString("Fat", comment: ""), subtitle: grams),
                        ReportTable.Column(id: 3, title: NSLocalizedString("Protein", comment: ""), subtitle: grams),
                        ReportTable.Column(id: 4, title: Meals.Part.carbEquivalents.name, subtitle: grams)
                    ]
                }
                dayTable = ReportTable(
                    name: NSLocalizedString("Date", comment: "PDF report, Days table: the day's column"),
                    columns: columns,
                    rows: Array(rows[range])
                )
                hourTable = table == 0
                    ? ReportTable(
                        name: NSLocalizedString("Time", comment: ""),
                        columns: [
                            ReportTable.Column(
                                id: 0,
                                title: Meals.Part.carbs.name,
                                subtitle: NSLocalizedString("g per day", comment: "Statistics Meals: the unit of a daily amount")
                            ),
                            ReportTable.Column(
                                id: 1,
                                title: NSLocalizedString(
                                    "Share of carbs",
                                    comment: "Statistics Meals by time of day: the hour's share"
                                ),
                                subtitle: ""
                            ),
                            ReportTable.Column(
                                id: 2,
                                title: NSLocalizedString("Entries", comment: "Statistics Meals: the carb entries"),
                                subtitle: ""
                            ),
                            ReportTable.Column(
                                id: 3,
                                title: NSLocalizedString(
                                    "Days",
                                    comment: "PDF report, Meals by time of day: the days with an entry in the hour"
                                ),
                                subtitle: NSLocalizedString(
                                    "with entries",
                                    comment: "PDF report, Meals by time of day: what the days are"
                                )
                            ),
                            ReportTable.Column(
                                id: 4,
                                title: NSLocalizedString("Per entry", comment: "Statistics Meals: the carbs per entry"),
                                subtitle: grams
                            )
                        ],
                        rows: Self.hourRows(period)
                    )
                    : nil
            } else {
                dayTable = nil
                hourTable = nil
            }
            // the "*" is explained on the pages that have one
            footnote = NSLocalizedString(
                "Carbs are averaged over complete days with entries.",
                comment: "PDF report, Days table footnote: the carbs column"
            ) + (
                ReportInsulin.isMarked(dayTable)
                    ? " " + NSLocalizedString(
                        "* today, so far: not in the averages.",
                        comment: "PDF report, Meals: the * after today's carbs"
                    )
                    : ""
            )
        }

        /// Day by day: the carbs (with the nutrients, the carb equivalents above them), the average dashed, "*" above
        /// today.
        @MainActor private static func dayBars(_ period: MealPeriod?, nutrients: Bool, calendar: Calendar) -> ReportBars {
            let parts = Meals.Part.allCases
            let days = period?.days ?? []
            let values = days.map { Meals.dayValues($0, logsFatOrProtein: nutrients) }
            let perDay = period?.summary.carbsPerDay
            let levels = StatsBarAxis.levels(
                maximum: Swift.max(values.map { $0.reduce(0, +) }.max() ?? 0, perDay ?? 0),
                unit: Meals.dayAxisUnit,
                divisions: 3
            )
            let marked = days.map { $0.isToday && $0.hasEntries }
            var legend = [ReportBars.LegendItem(id: 0, key: .swatch(Meals.Part.carbs.style), title: Meals.Part.carbs.name)]
            if nutrients {
                legend.append(
                    ReportBars.LegendItem(
                        id: 1,
                        key: .swatch(Meals.Part.carbEquivalents.style),
                        title: Meals.Part.carbEquivalents.name
                    )
                )
            }
            if let perDay {
                legend.append(
                    ReportBars.LegendItem(
                        id: 10,
                        key: .dashed,
                        title: String(
                            format: NSLocalizedString(
                                "Average %@ g",
                                comment: "Statistics Meals chart legend: the carbs per day"
                            ),
                            StatsAmount.number(perDay, digits: 0)
                        )
                    )
                )
            }
            if marked.contains(true) {
                legend.append(
                    ReportBars.LegendItem(
                        id: 11,
                        key: .mark,
                        title: NSLocalizedString("today, so far", comment: "PDF report, Meals chart legend: the * above today")
                    )
                )
            }
            return ReportBars(
                bars: days.indices.map { ReportBars.Bar(id: $0, values: values[$0], isMarked: marked[$0]) },
                styles: parts.map(\.style),
                levels: levels,
                levelLabels: levels.map { StatsAmount.number($0, digits: 0) },
                average: perDay,
                ticks: ReportBars.dayTicks(days.map(\.day.start), calendar: calendar),
                legend: legend
            )
        }

        /// By time of day: the carbs per day by the hour of entry.
        @MainActor private static func hourBars(_ hours: [HourMeals]) -> ReportBars {
            let levels = StatsBarAxis.levels(maximum: hours.map(\.carbsPerDay).max() ?? 0, unit: 10, divisions: 2)
            return ReportBars(
                bars: hours.map { ReportBars.Bar(id: $0.hour, values: [$0.carbsPerDay]) },
                styles: [Meals.Part.carbs.style],
                levels: levels,
                levelLabels: levels.map { StatsAmount.number($0, digits: 0) },
                average: nil,
                ticks: ReportBars.hourTicks,
                legend: [
                    ReportBars.LegendItem(
                        id: 0,
                        key: .swatch(Meals.Part.carbs.style),
                        title: NSLocalizedString(
                            "Carbs per day, by entry time",
                            comment: "Statistics Meals by time of day: the legend"
                        )
                    )
                ]
            )
        }
    }
}
