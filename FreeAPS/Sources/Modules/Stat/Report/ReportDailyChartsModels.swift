import CoreGraphics
import Foundation

// Daily charts of a report: one panel a day with its glucose trace, carbs, boluses, SMBs and basal. The days' data
// is cut out of the period's reads without formatting (`ReportChartsBuilder`, pure); a page's panels are built on the
// main actor when the page is drawn (`Stat.ReportChartsPage`), so no more than a page of them exists at a time.

/// A stretch of basal delivery of a chart day (`InsulinStatsEngine.timeline`'s segments, equal neighbours joined).
struct ReportBasalStep: Sendable, Equatable {
    let interval: DateInterval
    /// U/h delivered: a temp's rate, the schedule's, 0 while suspended
    let rate: Double
    /// U/h of the schedule in effect; nil outside the pump data's coverage
    let scheduled: Double?
}

/// Carbs entered at a time (entries close together are one, `ReportChartsBuilder.mergedCarbs`).
struct ReportCarbEntry: Sendable, Equatable {
    let time: Date
    /// g
    let grams: Double
}

/// A day of Daily charts: what its panel draws, and the numbers of its header line.
struct ReportChartDay: Sendable, Equatable {
    /// the whole calendar day (23, 24 or 25 h)
    let day: DateInterval
    /// the readings, about one per 5 minutes, oldest -> newest
    var points: [GlucosePoint] = []
    /// the day's time by band (the report's bands); nil without readings
    var shares: BandShares?
    /// mg/dL; nil without readings
    var mean: Double?
    /// U as delivered (the Insulin tab's day); nil without pump data covering some of the day
    var tdd: Double?
    /// the day is outside the insulin averages (today, or pump data for less than half of it: the Days table's `*`)
    var tddOutsideAverage = false
    /// g; nil without entries
    var carbs: Double?
    /// the boluses and the SMBs starting in the day, oldest -> newest
    var boluses: [InsulinBolus] = []
    var basal: [ReportBasalStep] = []
    /// the entries with carbs, oldest -> newest
    var carbEntries: [ReportCarbEntry] = []

    /// something to draw: a day without any is left out
    var hasData: Bool {
        points.isNotEmpty || boluses.isNotEmpty || basal.isNotEmpty || carbEntries.isNotEmpty
    }
}

enum ReportChartsBuilder {
    /// about one reading per this much time is drawn (a 1-minute CGM's are thinned to it)
    static let pointStep: TimeInterval = .minutes(4.5)
    /// readings further apart than this aren't joined by the line
    static let gap: TimeInterval = .minutes(15)
    /// carb entries (and boluses) at least this close together share one label; a narrow panel takes a longer time
    /// (`ReportChartMetrics.mergeWindow`)
    static let mergeWindow: TimeInterval = .minutes(15)

    /// The readings thinned to about two per `step` without losing an extreme: of each `step` of a stretch its lowest
    /// and its highest reading (in their order; one when they are the same), the first and the last reading of every
    /// stretch (the readings on either side of a gap), so a low or a peak of a minute is drawn as it was read.
    /// - Parameter points: oldest -> newest
    static func thinned(
        _ points: [GlucosePoint],
        step: TimeInterval = pointStep,
        gap: TimeInterval = ReportChartsBuilder.gap
    ) -> [GlucosePoint] {
        var kept: [GlucosePoint] = []
        var bucketStart: Date?
        var lowest: GlucosePoint?
        var highest: GlucosePoint?
        func append(_ point: GlucosePoint) {
            if kept.last != point {
                kept.append(point)
            }
        }
        func flush() {
            if let lowest, let highest {
                if lowest.time <= highest.time {
                    append(lowest)
                    append(highest)
                } else {
                    append(highest)
                    append(lowest)
                }
            }
            lowest = nil
            highest = nil
        }
        for index in points.indices {
            let point = points[index]
            let startsStretch = index == 0 || point.time.timeIntervalSince(points[index - 1].time) > gap
            let endsStretch = index == points.count - 1 || points[index + 1].time.timeIntervalSince(point.time) > gap
            if startsStretch {
                flush()
                append(point)
                bucketStart = point.time
            } else {
                if let start = bucketStart, point.time.timeIntervalSince(start) >= step {
                    flush()
                    bucketStart = point.time
                }
                if lowest.map({ point.mgdl < $0.mgdl }) ?? true { lowest = point }
                if highest.map({ point.mgdl > $0.mgdl }) ?? true { highest = point }
            }
            if endsStretch {
                flush()
                append(point)
            }
        }
        return kept
    }

    /// The readings as the stretches the line joins: a new one after every gap; one of a single reading is kept (a
    /// dot).
    static func stretches(_ points: [GlucosePoint], gap: TimeInterval = ReportChartsBuilder.gap) -> [[GlucosePoint]] {
        var result: [[GlucosePoint]] = []
        for point in points {
            if let previous = result.last?.last, point.time.timeIntervalSince(previous.time) <= gap {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    /// Entries within `window` of the first of a group are one, at the first one's time, their grams summed.
    /// - Parameter entries: oldest -> newest
    static func mergedCarbs(_ entries: [ReportCarbEntry], within window: TimeInterval = mergeWindow) -> [ReportCarbEntry] {
        var result: [ReportCarbEntry] = []
        for entry in entries {
            if let group = result.last, entry.time.timeIntervalSince(group.time) <= window {
                result[result.count - 1] = ReportCarbEntry(time: group.time, grams: group.grams + entry.grams)
            } else {
                result.append(entry)
            }
        }
        return result
    }

    /// The boluses that aren't SMBs, those within `window` of the first of a group as one (its units summed; External
    /// Insulin when any of them is).
    /// - Parameter boluses: oldest -> newest
    static func mergedBoluses(_ boluses: [InsulinBolus], within window: TimeInterval = mergeWindow) -> [InsulinBolus] {
        var result: [InsulinBolus] = []
        for bolus in boluses where !bolus.isSMB {
            if let group = result.last, bolus.date.timeIntervalSince(group.date) <= window {
                result[result.count - 1] = InsulinBolus(
                    date: group.date,
                    units: group.units + bolus.units,
                    isSMB: false,
                    isExternal: group.isExternal || bolus.isExternal
                )
            } else {
                result.append(bolus)
            }
        }
        return result
    }

    /// The basal steps of the timeline's segments: neighbours with the same rates joined.
    static func basalSteps(_ segments: [DeliverySegment]) -> [ReportBasalStep] {
        var steps: [ReportBasalStep] = []
        for segment in segments where segment.interval.duration > 0 {
            let scheduled: Double? = segment.isCovered ? segment.scheduledRate : nil
            if let last = steps.last, last.interval.end == segment.interval.start, last.rate == segment.rate,
               last.scheduled == scheduled
            {
                steps[steps.count - 1] = ReportBasalStep(
                    interval: DateInterval(start: last.interval.start, end: segment.interval.end),
                    rate: last.rate,
                    scheduled: scheduled
                )
            } else {
                steps.append(ReportBasalStep(interval: segment.interval, rate: segment.rate, scheduled: scheduled))
            }
        }
        return steps
    }

    /// The days with something to draw, oldest -> newest.
    /// - Parameters:
    ///   - days: the whole calendar days, oldest -> newest
    ///   - traces: by day (`ReportDataSource.reportTrace`)
    ///   - insulinDays: the Insulin tab's (the header's insulin)
    ///   - mealDays: the Meals tab's (the header's carbs, the entries)
    ///   - input: the window's pump events, coverage and schedules; nil when not read (no boluses, no basal)
    static func days(
        _ days: [DateInterval],
        traces: [ReportDayTrace],
        insulinDays: [DayInsulin],
        mealDays: [DayMeals],
        input: InsulinInput?,
        settings: ReportOptions.DailyChartsSettings,
        now: Date,
        calendar: Calendar
    ) -> [ReportChartDay] {
        guard let first = days.first, let last = days.last else { return [] }
        let insulin = Dictionary(insulinDays.map { ($0.day.start, $0) }, uniquingKeysWith: { first, _ in first })
        let meals = Dictionary(mealDays.map { ($0.day.start, $0) }, uniquingKeysWith: { first, _ in first })
        let window = DateInterval(start: first.start, end: Swift.max(first.start, last.end))

        var boluses: [InsulinBolus] = []
        var steps: [ReportBasalStep] = []
        if let input, settings.boluses || settings.basal {
            // the two sources' doubles dropped once: the timeline takes the same events (it filters what it is given
            // again, which changes nothing)
            let usable = InsulinStatsEngine.usableEvents(input.events, coverage: input.coverage)
            if settings.boluses {
                boluses = usable
                    .filter { $0.kind == .bolus && $0.units > 0 && $0.date <= now && window.contains($0.date) }
                    .map { InsulinBolus(date: $0.date, units: $0.units, isSMB: $0.isSMB, isExternal: $0.isExternal) }
            }
            if settings.basal {
                steps = basalSteps(
                    InsulinStatsEngine.timeline(
                        events: usable,
                        coverage: input.coverage,
                        schedules: input.schedules,
                        window: window,
                        now: now,
                        calendar: calendar
                    )
                )
            }
        }

        return days.enumerated().compactMap { index, day -> ReportChartDay? in
            var chart = ReportChartDay(day: day)
            if traces.indices.contains(index), traces[index].points.isNotEmpty {
                let trace = traces[index]
                chart.points = thinned(trace.points)
                chart.shares = trace.summary.bandShares
                chart.mean = trace.summary.mean
            }
            if let insulinDay = insulin[day.start], insulinDay.hasData, insulinDay.coveredSeconds > 0 {
                chart.tdd = insulinDay.total
                chart.tddOutsideAverage = !insulinDay.isHeadline
            }
            if let mealDay = meals[day.start], mealDay.hasEntries {
                chart.carbs = mealDay.carbs
                if settings.carbs {
                    chart.carbEntries = mealDay.entries.filter { $0.carbs > 0 }
                        .map { ReportCarbEntry(time: $0.actualDate, grams: $0.carbs) }
                }
            }
            chart.boluses = boluses.filter { $0.date >= day.start && $0.date < day.end }
            // the timeline is cut at midnight: a step is inside one day
            chart.basal = steps.flatMap { step -> [ReportBasalStep] in
                guard let interval = StatsIntervals.clipped(step.interval, to: day), interval.duration > 0 else { return [] }
                return [ReportBasalStep(interval: interval, rate: step.rate, scheduled: step.scheduled)]
            }
            return chart.hasData ? chart : nil
        }
    }
}

/// The sizes of a page of Daily charts: what the page's model (the labels that fit) and its view share.
enum ReportChartMetrics {
    /// what the page's header and footer take of the height inside the margins
    static let chrome: CGFloat = 86
    static let legendHeight: CGFloat = 12
    /// a line under the legend (a failed read, the `*`)
    static let noteHeight: CGFloat = 9
    static let rowSpacing: CGFloat = 9
    static let columnSpacing: CGFloat = 16
    /// a panel's header line
    static let headerHeight: CGFloat = 12
    /// the room of a chart's glucose labels, and its trailing inset
    static let leading: CGFloat = 24
    static let trailing: CGFloat = 5
    /// the marks' labels' sizes: the boluses' are smaller with two columns of panels
    static let labelSize: CGFloat = 6.5
    static let compactBolusLabelSize: CGFloat = 5.5
    /// the characters a label is taken to have at most: "12,5" U, "120" g
    static let bolusLabelCharacters = 4
    static let carbsLabelCharacters = 3

    /// A panel's size on a page of `page` points.
    static func panelSize(page: CGSize, columns: Int, rows: Int, noteLines: Int) -> CGSize {
        let rowCount = CGFloat(Swift.max(rows, 1))
        let columnCount = CGFloat(Swift.max(columns, 1))
        let width = page.width - ReportStyle.margin * 2
        let area = page.height - ReportStyle.margin * 2 - chrome - legendHeight - 6 - noteHeight * CGFloat(noteLines)
        return CGSize(
            width: (width - columnSpacing * (columnCount - 1)) / columnCount,
            height: Swift.max((area - rowSpacing * (rowCount - 1)) / rowCount, 40)
        )
    }

    /// The width of a panel's plot: the day from 00:00 to 24:00.
    static func plotWidth(panelWidth: CGFloat) -> CGFloat {
        Swift.max(panelWidth - leading - trailing, 1)
    }

    /// About the width of a label of digits.
    static func labelWidth(characters: Int, size: CGFloat) -> CGFloat {
        CGFloat(characters) * size * 0.58
    }

    /// The time two labels of `labelWidth` need between them on a plot `plotWidth` wide so they don't overprint (a day
    /// of 24 hours), at least `ReportChartsBuilder.mergeWindow`: marks closer than it are one, their amounts summed.
    static func mergeWindow(labelWidth: CGFloat, plotWidth: CGFloat) -> TimeInterval {
        let needed = TimeInterval((labelWidth + 2) / Swift.max(plotWidth, 1)) * .hours(24)
        return Swift.max(needed, ReportChartsBuilder.mergeWindow)
    }
}

extension Stat {
    /// A page of Daily charts, formatted: its panels on one glucose scale and one basal scale.
    struct ReportChartsPage: Equatable {
        /// A moment of a day as its panel places it: 0 at the day's start, 1 at its end.
        typealias Position = Double

        struct Sample: Equatable {
            let x: Position
            /// kept inside the axis
            let mgdl: Double
        }

        struct Marker: Equatable {
            let x: Position
            /// g or U
            let amount: Double
            /// "45 g", "4.5 U"; nil: the marker alone
            let label: String?
        }

        struct BasalStep: Equatable {
            let from: Position
            let to: Position
            /// U/h
            let rate: Double
            let scheduled: Double?
        }

        struct Tick: Equatable {
            let x: Position
            let label: String
        }

        struct Panel: Equatable, Identifiable {
            let id: Int
            /// "Tue 20 Oct 2026"
            let title: String
            /// "In range 76% · Mean 141 mg/dL · Insulin 38.2 U · Carbs 182 g", what the day has of them
            let stats: String
            /// the stretches the line joins
            let lines: [[Sample]]
            let carbs: [Marker]
            /// the boluses that aren't SMBs
            let boluses: [Marker]
            let smbs: [Marker]
            let basal: [BasalStep]
            /// the local clock's hours
            let ticks: [Tick]
            /// "No readings": a day drawn for its insulin or carbs alone
            let note: String?
        }

        struct Level: Equatable, Identifiable {
            let mgdl: Int
            let label: String

            var id: Int { mgdl }
        }

        /// What a legend entry shows beside its text.
        enum LegendKey: Equatable {
            case glucose
            case range
            case bolus
            case smb
            case carbs
            case basal
            case scheduled
        }

        struct LegendItem: Equatable, Identifiable {
            let id: Int
            let key: LegendKey
            let text: String
        }

        /// the layout: 1 × 1 (landscape), 1 × 2, 1 × 4, 2 × 4
        let columns: Int
        let rows: Int
        /// mg/dL, the same on every panel of the page
        let axis: ClosedRange<Int>
        /// the in-range band's edges
        let low: Int
        let high: Int
        /// hairlines: 54 and 250 inside the axis
        let hairlines: [Int]
        /// the labelled levels, ascending
        let levels: [Level]
        /// the basal lane is drawn
        let showsBasal: Bool
        /// U/h: the basal lane's top, the same on every panel of the page
        let basalMax: Double
        /// "3": the basal lane's top, written beside it
        let basalMaxLabel: String
        /// U: the largest bolus and the largest SMB on the page (the bars' and the ticks' full height)
        let bolusMax: Double
        let smbMax: Double
        let panels: [Panel]
        let legend: [LegendItem]
        /// under the legend, a line each: what couldn't be read, what `*` means (when a panel has one)
        let notes: [String]
        /// a panel's size on the page (`ReportChartMetrics.panelSize`)
        let panelSize: CGSize
        /// the time within which boluses, and carb entries, are one mark (`ReportChartMetrics.mergeWindow`)
        let bolusMergeWindow: TimeInterval
        let carbsMergeWindow: TimeInterval
        /// nothing to draw in the period
        let emptyNote: String?

        /// What couldn't be read, and what `*` means: the lines under the legend.
        static func notes(_ data: ReportData, days: [ReportChartDay]) -> [String] {
            var notes: [String] = []
            let settings = data.request.dailyCharts
            var failed: [String] = []
            if data.failedReads.contains(.insulin) {
                failed.append(
                    NSLocalizedString("Insulin data could not be read.", comment: "PDF report: the insulin days' read failed")
                )
            }
            if data.failedReads.contains(.pumpEvents), settings.boluses || settings.basal {
                failed.append(
                    NSLocalizedString(
                        "Pump events could not be read: no boluses or basal are drawn.",
                        comment: "PDF report, Daily charts: the pump events' read failed"
                    )
                )
            }
            if data.failedReads.contains(.meals) {
                failed.append(
                    NSLocalizedString("Carb entries could not be read.", comment: "PDF report: the meals' read failed")
                )
            }
            if failed.isNotEmpty {
                notes.append(failed.joined(separator: " "))
            }
            if days.contains(where: { $0.tdd != nil && $0.tddOutsideAverage }) {
                notes.append(
                    NSLocalizedString(
                        "* Insulin as delivered on a day outside the averages: today, or pump data for less than half of the day.",
                        comment: "PDF report, Daily charts: the mark on a day's insulin"
                    )
                )
            }
            return notes
        }

        /// The days a page shows, in the order printed.
        static func days(_ data: ReportData, page: Int) -> [ReportChartDay] {
            let settings = data.request.dailyCharts
            let ordered = settings.newestFirst ? Array(data.chartDays.reversed()) : data.chartDays
            let perPage = Swift.max(settings.daysPerPage, 1)
            let start = page * perPage
            guard start >= 0, start < ordered.count else { return [] }
            return Array(ordered[start ..< Swift.min(start + perPage, ordered.count)])
        }

        /// The basal lane's top for the steps' highest rate (delivered or scheduled): the next of 0.5, 1, 2, 3, 5, 10 …
        /// U/h at or above it.
        static func basalScale(_ highest: Double) -> Double {
            let steps: [Double] = [0.5, 1, 2, 3, 5, 10, 20, 35]
            return steps.first { $0 >= highest } ?? highest
        }

        /// - Parameters:
        ///   - page: one of the part's (`index`, `units`)
        ///   - calendar: the days' (the clock ticks, the dates' time zone)
        @MainActor init(_ data: ReportData, page: ReportPage, calendar: Calendar) {
            typealias Format = StatsFormatting
            let settings = data.request.dailyCharts
            let units = page.units
            let labels = ReportBuilder.standardBands(units)
            let days = Self.days(data, page: page.index)
            let compact = settings.daysPerPage >= 8
            columns = settings.columns
            rows = settings.rows
            let notes = Self.notes(data, days: days)
            self.notes = notes
            let panelSize = ReportChartMetrics.panelSize(
                page: page.size,
                columns: settings.columns,
                rows: settings.rows,
                noteLines: notes.count
            )
            self.panelSize = panelSize
            let plotWidth = ReportChartMetrics.plotWidth(panelWidth: panelSize.width)
            let bolusMergeWindow = ReportChartMetrics.mergeWindow(
                labelWidth: ReportChartMetrics.labelWidth(
                    characters: ReportChartMetrics.bolusLabelCharacters,
                    size: compact ? ReportChartMetrics.compactBolusLabelSize : ReportChartMetrics.labelSize
                ),
                plotWidth: plotWidth
            )
            // eight a page the carbs have no labels: only entries close in time are one mark
            let carbsMergeWindow = compact ? ReportChartsBuilder.mergeWindow : ReportChartMetrics.mergeWindow(
                labelWidth: ReportChartMetrics.labelWidth(
                    characters: ReportChartMetrics.carbsLabelCharacters,
                    size: ReportChartMetrics.labelSize
                ),
                plotWidth: plotWidth
            )
            self.bolusMergeWindow = bolusMergeWindow
            self.carbsMergeWindow = carbsMergeWindow

            let highest = days.flatMap(\.points).map { Double($0.mgdl) }.max()
            let axis = ReportPercentilePlot.axis(highest: highest, units: units)
            self.axis = axis
            low = labels.low
            high = labels.high
            hairlines = [StatsBands.veryLowBelow, StatsBands.veryHighAbove].filter { axis.contains($0) }
            // without the axis' floor: the basal lane's scale is written just under it
            levels = ReportPercentilePlot.levels(bands: labels, axis: axis, minimumGap: settings.rows >= 4 ? 0.15 : 0.08)
                .filter { $0 > axis.lowerBound }
                .map { Level(mgdl: $0, label: Format.glucose($0, units: units)) }

            let steps = days.flatMap(\.basal)
            showsBasal = settings.basal
            basalMax = Self.basalScale(steps.map { Swift.max($0.rate, $0.scheduled ?? 0) }.max() ?? 0)
            basalMaxLabel = StatsAmount.number(basalMax, digits: 0 ... 1)
            let merged = days.map { ReportChartsBuilder.mergedBoluses($0.boluses, within: bolusMergeWindow) }
            bolusMax = merged.flatMap { $0 }.map(\.units).max() ?? 0
            smbMax = days.flatMap(\.boluses).filter(\.isSMB).map(\.units).max() ?? 0

            var titleStyle = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
            titleStyle.timeZone = calendar.timeZone
            var hourStyle = Date.FormatStyle(date: .omitted, time: .shortened)
            hourStyle.timeZone = calendar.timeZone
            let lower = Double(axis.lowerBound)
            let upper = Double(axis.upperBound)

            panels = days.enumerated().map { index, day -> Panel in
                func position(_ date: Date) -> Position {
                    guard day.day.duration > 0 else { return 0 }
                    return Swift.min(Swift.max(date.timeIntervalSince(day.day.start) / day.day.duration, 0), 1)
                }
                var stats: [String] = []
                if let shares = day.shares {
                    let inRange = Format.percent(.inRange, of: shares)
                    stats.append(
                        compact ? inRange : String(
                            format: NSLocalizedString("In range %@", comment: "PDF report, Daily charts: a day's time in range"),
                            inRange
                        )
                    )
                }
                if let mean = day.mean {
                    let value = Format.glucose(mean, units: units) + (compact ? "" : " " + Format.unit(units))
                    stats.append(
                        compact ? value : String(
                            format: NSLocalizedString("Mean %@", comment: "PDF report, Daily charts: a day's mean glucose"),
                            value
                        )
                    )
                }
                if let tdd = day.tdd {
                    // outside the averages: marked as its row of the Days table (the page's note says why)
                    let value = StatsAmount.units(tdd, digits: 1) + (day.tddOutsideAverage ? "*" : "")
                    stats.append(
                        compact ? value : String(
                            format: NSLocalizedString("Insulin %@", comment: "PDF report, Daily charts: a day's insulin"),
                            value
                        )
                    )
                }
                if let carbs = day.carbs {
                    let value = StatsAmount.grams(carbs, digits: 0)
                    stats.append(
                        compact ? value : String(
                            format: NSLocalizedString("Carbs %@", comment: "PDF report, Daily charts: a day's carbs"),
                            value
                        )
                    )
                }
                let boluses = merged[index]
                return Panel(
                    id: index,
                    title: day.day.start.formatted(titleStyle),
                    stats: stats.joined(separator: " · "),
                    lines: ReportChartsBuilder.stretches(day.points).map { stretch in
                        stretch.map { Sample(x: position($0.time), mgdl: Swift.min(Swift.max(Double($0.mgdl), lower), upper)) }
                    },
                    carbs: ReportChartsBuilder.mergedCarbs(day.carbEntries, within: carbsMergeWindow).map {
                        Marker(
                            x: position($0.time),
                            amount: $0.grams,
                            // eight a page: no room for the labels
                            label: compact ? nil : StatsAmount.number($0.grams, digits: 0)
                        )
                    },
                    boluses: boluses.map {
                        Marker(
                            x: position($0.date),
                            amount: $0.units,
                            // the unit is the legend's: a shorter label leaves more boluses their own
                            label: StatsAmount.number($0.units, digits: 1 ... 2)
                        )
                    },
                    smbs: day.boluses.filter(\.isSMB).map { Marker(x: position($0.date), amount: $0.units, label: nil) },
                    basal: day.basal.map {
                        BasalStep(
                            from: position($0.interval.start),
                            to: position($0.interval.end),
                            rate: $0.rate,
                            scheduled: $0.scheduled
                        )
                    },
                    ticks: GlucoseStatsEngine.clockTicks(in: day.day, everyHours: compact ? 6 : 3, calendar: calendar)
                        .map { Tick(x: position($0), label: $0.formatted(hourStyle)) },
                    note: day.points.isEmpty ? NSLocalizedString("No readings", comment: "") : nil
                )
            }

            var legend: [LegendItem] = [
                LegendItem(
                    id: 0,
                    key: .glucose,
                    text: String(
                        format: NSLocalizedString(
                            "Glucose (%@)",
                            comment: "PDF report, Daily charts legend: the trace, its unit"
                        ),
                        Format.unit(units)
                    )
                ),
                LegendItem(
                    id: 1,
                    key: .range,
                    text: String(
                        format: NSLocalizedString("Range %@", comment: "PDF report, percentile chart legend: the in-range band"),
                        Format.label(.inRange, bands: labels, units: units) ?? ""
                    )
                )
            ]
            if settings.boluses {
                legend.append(
                    LegendItem(
                        id: 2,
                        key: .bolus,
                        text: NSLocalizedString("Bolus (U)", comment: "PDF report, Daily charts legend")
                    )
                )
                legend.append(
                    LegendItem(
                        id: 3,
                        key: .smb,
                        text: NSLocalizedString("SMB", comment: "Statistics Insulin: super micro boluses")
                    )
                )
            }
            if settings.carbs {
                legend.append(
                    LegendItem(
                        id: 4,
                        key: .carbs,
                        text: NSLocalizedString("Carbs (g)", comment: "PDF report, Daily charts legend")
                    )
                )
            }
            if settings.basal {
                legend.append(
                    LegendItem(
                        id: 5,
                        key: .basal,
                        text: String(
                            format: NSLocalizedString(
                                "Basal (0–%@ U/h)",
                                comment: "PDF report, Daily charts legend: the delivered basal, the lane's scale"
                            ),
                            basalMaxLabel
                        )
                    )
                )
                legend.append(
                    LegendItem(
                        id: 6,
                        key: .scheduled,
                        text: NSLocalizedString("Scheduled basal", comment: "PDF report, Daily charts legend")
                    )
                )
            }
            self.legend = legend
            emptyNote = days.isEmpty
                ? NSLocalizedString("No data in this period", comment: "PDF report, Daily charts: no day has anything to draw")
                : nil
        }
    }
}
