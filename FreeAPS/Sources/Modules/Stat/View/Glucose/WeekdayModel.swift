import SwiftUI

extension Stat {
    /// By weekday, formatted for display. The pools come ready from the provider (`WeekdayResult`), in the columns'
    /// order (the workdays, then the weekend); only strings, the bars and the heatmap's steps are built here, the picked
    /// cell's readout when it is shown (`readout`).
    struct Weekday: Equatable {
        /// A weekday's column: of the bars, the table, the heatmap and its readout.
        struct Column: Equatable, Sendable, Identifiable {
            /// `Calendar` weekday, 1 Sunday … 7 Saturday
            let weekday: Int
            /// "Mon"
            let short: String
            /// "Monday"
            let name: String

            var id: Int { weekday }
        }

        /// The in-range bars: a 100% bar per weekday with readings. The bars view compares it to skip its body.
        struct Bars: Equatable, Sendable {
            /// A band's part of a weekday's bar.
            struct Part: Equatable, Sendable, Identifiable {
                let band: GlucoseBand
                /// fractions of the weekday's covered time, from the bottom
                let lower: Double
                let upper: Double

                var id: GlucoseBand { band }
            }

            /// the y axis: gridlines at 0, 50 and 100%
            static let levels: [Double] = [0, 0.5, 1]

            /// by column, the bands from very low up; empty without readings
            let parts: [[Part]]
            /// "0%", "50%", "100%"
            let levelLabels: [String]
        }

        /// A row of the numbers under the bars: In range, Mean, Low, High (and Days with limited data).
        struct TableRow: Equatable, Identifiable {
            let name: String
            /// by column; "–" without readings
            let values: [String]
            /// In range: in bold
            let isEmphasized: Bool
            /// Days: in the secondary colour
            let isSecondary: Bool

            var id: String { name }
        }

        /// A weekday at the larger text sizes, where the bars and the table make a list.
        struct WeekdayRow: Equatable, Identifiable {
            let weekday: Int
            /// "Mon"
            let name: String
            let segments: [BandSegment]
            /// "62%", "–"
            let inRange: String
            /// "7.4 mmol/L · 3% low · 12% high", "no readings"
            let line: String

            var id: Int { weekday }
        }

        /// The heatmap of a metric: every cell's step (`GlucoseStatsEngine.weekdayStep`). The cells view compares it to
        /// skip its body.
        struct Heatmap: Equatable, Sendable {
            struct Cell: Equatable, Sendable {
                /// 0...4 (`GlucoseStatsEngine.weekdayStepEdges`); nil without readings (an outline)
                let step: Int?
                /// under `GlucoseStatsEngine.weekdayFewHours` per hour of it: hatched and dimmed
                let isFew: Bool
            }

            let metric: WeekdayMetric
            /// 1, or `GlucoseStatsEngine.weekdayBlockHours` (the larger text sizes)
            let hoursPerRow: Int
            /// by column, then by row from 00:00
            let cells: [[Cell]]
            /// the first weekend column (a gap before it); the column count without a weekend
            let weekendStart: Int

            var rowCount: Int { 24 / Swift.max(hoursPerRow, 1) }
        }

        /// The heatmap's key of a metric: its five steps and what they measure.
        struct Legend: Equatable {
            /// "<50", "50–70", …, "≥90"
            let steps: [String]
            /// "% in range", "% below 70", "mmol/L"
            let title: String
        }

        /// The picked cell (a weekday's hour or 3-hour block) as its metric shows it, with its bands.
        struct Readout: Equatable {
            /// "Saturday · 10:00–11:00"
            let title: String
            /// "8 days · 480 readings (8 h 00 m)", "8 days · no readings"
            let subtitle: String
            let hasData: Bool
            /// "62%", "3%", "7.4"
            let value: String
            /// "in range", "low, below 4.0", "mmol/L mean"
            let unit: String
            /// "usual 71%": the same hours on the other six days; "" without data there
            let usual: String
            /// under `GlucoseStatsEngine.weekdayFewHours` per hour: the mark, and `fewNote`
            let isFew: Bool
            let fewNote: String
            let segments: [BandSegment]
            /// very high first, as the mock lists them
            let rows: [StatsBandRow]
            /// "Usual: 10:00–11:00 on the other days of the week."
            let usualNote: String
        }

        /// The workdays or the weekend, a tile of "Weekdays vs weekends".
        struct DayGroup: Equatable {
            /// "Mon–Fri"
            let name: String
            /// "62%"
            let inRange: String
            /// "in range · 40 days"
            let subtitle: String
            let segments: [BandSegment]
        }

        /// A row of the workdays' and the weekend's numbers.
        struct SummaryRow: Equatable, Identifiable {
            /// "Mean, mmol/L"
            let name: String
            let workdays: String
            let weekend: String

            var id: String { name }
        }

        let columns: [Column]
        /// the first weekend column; `columns.count` without a weekend
        let weekendStart: Int
        /// "3–29 Oct": the period's first and last day (yesterday)
        let dateRange: String
        /// "8 of each weekday", "2–3 of each weekday"
        let countNote: String
        /// fewer of some weekday with readings than the period holds (`WeekdayResult.isLimited`): why, for the mark
        let limitedNote: String?
        let bars: Bars
        let tableRows: [TableRow]
        let weekdayRows: [WeekdayRow]
        let legendBands: [GlucoseBand]
        let barsFootnote: String
        /// by metric: by the hour, and by 3-hour block
        let hourHeatmaps: [WeekdayMetric: Heatmap]
        let blockHeatmaps: [WeekdayMetric: Heatmap]
        let legends: [WeekdayMetric: Legend]
        /// by row: the hour labelled on its left (every third), nil for the others
        let hourLabels: [String?]
        /// by 3-hour block: its start
        let blockLabels: [String]
        let hourFootnote: String
        let blockFootnote: String
        /// the workdays and the weekend; nil without a weekend (no comparison)
        let workdays: DayGroup?
        let weekend: DayGroup?
        let summaryRows: [SummaryRow]
        let summaryFootnote: String

        private let result: WeekdayResult
        private let units: GlucoseUnits
        private let bands: StatsBands

        /// - Parameter calendar: the weekday names'
        @MainActor init(_ result: WeekdayResult, settings: StatsSettings, calendar: Calendar = .current) {
            typealias Format = StatsFormatting
            typealias Engine = GlucoseStatsEngine
            let units = settings.units
            let bands = settings.bands
            let visible = bands.visibleBands
            self.result = result
            self.units = units
            self.bands = bands

            let columns = Self.columns(result, calendar: calendar)
            self.columns = columns
            let weekendStart = columns.count - result.weekendCount
            self.weekendStart = weekendStart
            legendBands = visible
            // the siblings' "3 Oct – 29 Oct": the period's days from its start, so the last one is yesterday
            dateRange = Format.dateRange(result.window, period: result.period)

            // the counts: every weekday the period's weeks, or with limited data the fewest to the most of them
            let counts = Self.counts(result)
            countNote = String(
                format: NSLocalizedString(
                    "%@ of each weekday",
                    comment: "Statistics By weekday: the days of each weekday in the period, \"8\" or \"2–3\""
                ),
                counts
            )
            limitedNote = result.isLimited
                ? NSLocalizedString(
                    "Some weekdays have fewer days with readings than the period holds, so one day weighs a lot.",
                    comment: "Statistics limited data: By weekday with fewer of some weekday than the period holds"
                )
                : nil

            // the bars and the numbers under them
            bars = Self.bars(result, visible: visible)
            tableRows = Self.tableRows(result, columns: columns, units: units)
            weekdayRows = Self.weekdayRows(result, columns: columns, units: units, visible: visible)

            let unit = Format.unit(units)
            let lowEdge = Format.glucose(bands.low, units: units)
            barsFootnote = Self.barsFootnote(result, counts: counts, units: units, bands: bands)

            // the heatmap
            hourHeatmaps = Self.heatmaps(result.hours, hoursPerRow: 1, weekendStart: weekendStart, units: units)
            blockHeatmaps = Self.heatmaps(
                result.blocks,
                hoursPerRow: Engine.weekdayBlockHours,
                weekendStart: weekendStart,
                units: units
            )
            legends = Dictionary(uniqueKeysWithValues: WeekdayMetric.allCases.map { metric in
                (metric, Self.legend(metric, units: units, unit: unit, lowEdge: lowEdge))
            })
            hourLabels = (0 ..< 24).map { hour -> String? in
                hour % 3 == 0 ? AGP.clockTime(hour * 60) : nil
            }
            blockLabels = stride(from: 0, to: 24, by: Engine.weekdayBlockHours).map { AGP.clockTime($0 * 60) }
            hourFootnote = String(
                format: NSLocalizedString(
                    "Each cell pools that hour over the period's %d days of its weekday; tap one for its numbers. Usual: the same hours on the other six days.",
                    comment: "Statistics By weekday heatmap: the period's weeks"
                ),
                result.weeks
            )
            blockFootnote = NSLocalizedString(
                "At this text size a cell is 3 hours, the whole day in view. Usual: the same hours on the other six days.",
                comment: "Statistics By weekday heatmap at the larger text sizes"
            )

            // weekdays vs weekends
            let comparison = Self.comparison(result, columns: columns, weekendStart: weekendStart, units: units, bands: bands)
            workdays = comparison.workdays
            weekend = comparison.weekend
            summaryRows = comparison.summaryRows
            summaryFootnote = comparison.footnote
        }

        // MARK: - The init's parts

        /// The weekdays from the region's first, the weekend last.
        private static func columns(_ result: WeekdayResult, calendar: Calendar) -> [Column] {
            result.order.map { weekday in
                Column(
                    weekday: weekday,
                    short: calendar.shortWeekdaySymbols[(weekday - 1) % 7],
                    name: calendar.weekdaySymbols[(weekday - 1) % 7]
                )
            }
        }

        /// The days of each weekday: the period's weeks, or with limited data the fewest to the most ("2–3").
        private static func counts(_ result: WeekdayResult) -> String {
            let fewest = result.daysWithData.min() ?? 0
            let most = result.daysWithData.max() ?? 0
            return result.isLimited ? Self.countRange(fewest, most) : "\(result.weeks)"
        }

        /// The weekdays' bands, stacked from very low.
        @MainActor private static func bars(_ result: WeekdayResult, visible: [GlucoseBand]) -> Bars {
            typealias Format = StatsFormatting
            return Bars(
                parts: result.weekdays.map { pool in
                    pool.bandShares.stacked(visible).map { Bars.Part(band: $0.band, lower: $0.lower, upper: $0.upper) }
                },
                levelLabels: Bars.levels.map { Format.percent(fraction: $0) }
            )
        }

        /// The numbers under the bars: the weekdays, in range, mean, low, high (and the days, limited).
        @MainActor private static func tableRows(_ result: WeekdayResult, columns: [Column], units: GlucoseUnits) -> [TableRow] {
            typealias Format = StatsFormatting
            func values(_ value: (WeekdayPool) -> String) -> [String] {
                result.weekdays.map { $0.hasData ? value($0) : "–" }
            }
            var rows = [
                TableRow(name: "", values: columns.map(\.short), isEmphasized: false, isSecondary: true),
                TableRow(name: Format.name(.inRange), values: values { inRangeText($0) }, isEmphasized: true, isSecondary: false),
                TableRow(
                    name: NSLocalizedString("Mean", comment: "Statistics, mean glucose"),
                    values: values { meanText($0, units: units) },
                    isEmphasized: false,
                    isSecondary: false
                ),
                TableRow(name: Format.name(.low), values: values { lowText($0) }, isEmphasized: false, isSecondary: false),
                TableRow(name: Format.name(.high), values: values { highText($0) }, isEmphasized: false, isSecondary: false)
            ]
            if result.isLimited {
                rows.append(
                    TableRow(
                        name: NSLocalizedString("Days", comment: "Days of saved readings"),
                        values: result.daysWithData.map { "\($0)" },
                        isEmphasized: false,
                        isSecondary: true
                    )
                )
            }
            return rows
        }

        /// The weekdays at the larger text sizes: a row each, its bands and its numbers in a line.
        @MainActor private static func weekdayRows(
            _ result: WeekdayResult,
            columns: [Column],
            units: GlucoseUnits,
            visible: [GlucoseBand]
        ) -> [WeekdayRow] {
            typealias Format = StatsFormatting
            let unit = Format.unit(units)
            return zip(columns, result.weekdays).enumerated().map { index, entry -> WeekdayRow in
                let (column, pool) = entry
                var line = String(
                    format: NSLocalizedString(
                        "%1$@ · %2$@ low · %3$@ high",
                        comment: "Statistics By weekday, a weekday at the larger text sizes: its mean with its unit, percent low and high"
                    ),
                    Self.valueWithUnit(meanText(pool, units: units), unit),
                    lowText(pool),
                    highText(pool)
                )
                if result.isLimited {
                    line = String(
                        format: NSLocalizedString(
                            "%1$@ · %2$d days",
                            comment: "Statistics By weekday with limited data, a weekday at the larger text sizes: its numbers, its days with readings"
                        ),
                        line,
                        result.daysWithData[index]
                    )
                }
                return WeekdayRow(
                    weekday: column.weekday,
                    name: column.short,
                    segments: pool.bandShares.barSegments(visible),
                    inRange: pool.hasData ? inRangeText(pool) : "–",
                    line: pool.hasData
                        ? line
                        : NSLocalizedString("no readings", comment: "Statistics By weekday: a day without readings")
                )
            }
        }

        /// The days the bars are over, and (limited) why one day weighs a lot.
        @MainActor private static func barsFootnote(
            _ result: WeekdayResult,
            counts: String,
            units: GlucoseUnits,
            bands: StatsBands
        ) -> String {
            typealias Format = StatsFormatting
            let unit = Format.unit(units)
            let lowEdge = Format.glucose(bands.low, units: units)
            let highEdge = Format.glucose(bands.high, units: units)
            let dayCount = result.weeks * 7
            if result.isLimited {
                return result.recordedSince.map { since in
                    String(
                        format: NSLocalizedString(
                            "Recorded since %1$@: %2$@ of each weekday so far, not the %3$d the period holds, so one day weighs a lot.",
                            comment: "Statistics By weekday with limited data: the first day with readings, the days of each weekday (\"2–3\"), the period's weeks"
                        ),
                        Trace.dayTitle(since),
                        counts,
                        result.weeks
                    )
                } ?? String(
                    format: NSLocalizedString(
                        "Readings on %1$@ of each weekday, not the %2$d the period holds, so one day weighs a lot.",
                        comment: "Statistics By weekday with limited data: the days of each weekday with readings (\"6–8\"), the period's weeks"
                    ),
                    counts,
                    result.weeks
                )
            } else {
                return String(
                    format: NSLocalizedString(
                        "The %1$d days to yesterday: %2$d of each weekday (today counts once it is over). Mean in %3$@; low below %4$@, high above %5$@.",
                        comment: "Statistics By weekday: the period's days, its weeks, the unit, your range's low and high end"
                    ),
                    dayCount,
                    result.weeks,
                    unit,
                    lowEdge,
                    highEdge
                )
            }
        }

        /// A heatmap of each metric: a column per weekday, a row per hour (or block of `hoursPerRow`).
        @MainActor private static func heatmaps(
            _ pools: [[WeekdayPool]],
            hoursPerRow: Int,
            weekendStart: Int,
            units: GlucoseUnits
        ) -> [WeekdayMetric: Heatmap] {
            typealias Engine = GlucoseStatsEngine
            func heatmap(_ metric: WeekdayMetric) -> Heatmap {
                Heatmap(
                    metric: metric,
                    hoursPerRow: hoursPerRow,
                    cells: pools.map { column in
                        column.map { Heatmap.Cell(step: Engine.weekdayStep($0, metric: metric, units: units), isFew: $0.isFew) }
                    },
                    weekendStart: weekendStart
                )
            }
            return Dictionary(uniqueKeysWithValues: WeekdayMetric.allCases.map {
                ($0, heatmap($0))
            })
        }

        /// Weekdays vs weekends: the two tiles and their rows; nil, nil, none without a weekend.
        @MainActor private static func comparison(
            _ result: WeekdayResult,
            columns: [Column],
            weekendStart: Int,
            units: GlucoseUnits,
            bands: StatsBands
        ) -> (workdays: DayGroup?, weekend: DayGroup?, summaryRows: [SummaryRow], footnote: String) {
            typealias Format = StatsFormatting
            let visible = bands.visibleBands
            let unit = Format.unit(units)
            let lowEdge = Format.glucose(bands.low, units: units)
            let highEdge = Format.glucose(bands.high, units: units)
            if let weekendPool = result.weekend, weekendStart > 0 {
                let workdays = dayGroup(result.workdays, columns: columns[..<weekendStart], visible: visible)
                let weekend = dayGroup(weekendPool, columns: columns[weekendStart...], visible: visible)
                func value(_ pool: WeekdayPool, _ text: (WeekdayPool) -> String) -> String {
                    pool.hasData ? text(pool) : "–"
                }
                let summaryRows = [
                    SummaryRow(
                        name: String(
                            format: NSLocalizedString(
                                "Mean, %@",
                                comment: "Statistics By weekday, weekdays vs weekends: the unit"
                            ),
                            unit
                        ),
                        workdays: value(result.workdays) { meanText($0, units: units) },
                        weekend: value(weekendPool) { meanText($0, units: units) }
                    ),
                    SummaryRow(
                        name: String(
                            format: NSLocalizedString(
                                "Low, below %@",
                                comment: "Statistics By weekday, weekdays vs weekends: your range's low end"
                            ),
                            lowEdge
                        ),
                        workdays: value(result.workdays) { lowText($0) },
                        weekend: value(weekendPool) { lowText($0) }
                    ),
                    SummaryRow(
                        name: String(
                            format: NSLocalizedString(
                                "High, above %@",
                                comment: "Statistics By weekday, weekdays vs weekends: your range's high end"
                            ),
                            highEdge
                        ),
                        workdays: value(result.workdays) { highText($0) },
                        weekend: value(weekendPool) { highText($0) }
                    )
                ]
                let footnote = String(
                    format: NSLocalizedString(
                        "The weekend follows your region: %@ here.",
                        comment: "Statistics By weekday, weekdays vs weekends: the weekend's days (\"Saturday and Sunday\")"
                    ),
                    ListFormatter.localizedString(byJoining: columns[weekendStart...].map(\.name))
                )
                return (workdays, weekend, summaryRows, footnote)
            } else {
                return (nil, nil, [], "")
            }
        }

        /// The workdays or the weekend, a tile.
        @MainActor private static func dayGroup(
            _ pool: WeekdayPool,
            columns: ArraySlice<Column>,
            visible: [GlucoseBand]
        ) -> DayGroup {
            let first = columns.first?.short ?? ""
            let last = columns.last?.short ?? ""
            return DayGroup(
                name: columns.count > 1 ? Self.weekdayRange(first, last) : first,
                inRange: pool.hasData ? inRangeText(pool) : "–",
                subtitle: String(
                    format: NSLocalizedString(
                        "in range · %d days",
                        comment: "Statistics By weekday, the workdays or the weekend: their days with readings"
                    ),
                    pool.days
                ),
                segments: pool.bandShares.barSegments(visible)
            )
        }

        /// "62%", "<1%"
        @MainActor private static func inRangeText(_ pool: WeekdayPool) -> String {
            StatsFormatting.percent(.inRange, of: pool)
        }

        @MainActor private static func lowText(_ pool: WeekdayPool) -> String {
            StatsFormatting.percent(pool.lowPercent, belowOne: pool.lowBelowOnePercent)
        }

        @MainActor private static func highText(_ pool: WeekdayPool) -> String {
            StatsFormatting.percent(pool.highPercent, belowOne: pool.highBelowOnePercent)
        }

        /// "6.3", "–"
        @MainActor private static func meanText(_ pool: WeekdayPool, units: GlucoseUnits) -> String {
            pool.mean.map { StatsFormatting.glucose($0, units: units) } ?? "–"
        }

        /// "7.4 mmol/L", "62% in range": a value and its unit
        static func valueWithUnit(_ value: String, _ unit: String) -> String {
            String(
                format: NSLocalizedString(
                    "%1$@ %2$@ (value unit)",
                    comment: "Statistics By weekday: a value and its unit (\"7.4 mmol/L\")"
                ),
                value,
                unit
            )
        }

        /// "Mon–Fri": the first and the last weekday of a run of them
        static func weekdayRange(_ first: String, _ last: String) -> String {
            String(
                format: NSLocalizedString(
                    "%1$@–%2$@ (weekday range)",
                    comment: "Statistics By weekday: a run of weekdays, its first and last (\"Mon–Fri\")"
                ),
                first,
                last
            )
        }

        /// "8", "2–3": the fewest and the most days of a weekday
        static func countRange(_ fewest: Int, _ most: Int) -> String {
            guard fewest != most else { return "\(fewest)" }
            return String(
                format: NSLocalizedString("%1$d–%2$d", comment: "Statistics: a range of counts, the fewest and the most"),
                fewest,
                most
            )
        }

        /// The key of a metric's steps (`GlucoseStatsEngine.weekdayStepEdges`): below the first edge, between two, at or
        /// above the last; low's first step is no low at all ("0"), its second any low under 2% ("<2", "<1%" too).
        /// - Parameter unit: the mean's (`StatsFormatting.unit`)
        static func legend(_ metric: WeekdayMetric, units: GlucoseUnits, unit: String, lowEdge: String) -> Legend {
            let edges = GlucoseStatsEngine.weekdayStepEdges(metric, units: units).map { "\($0)" }
            guard let first = edges.first, let last = edges.last else { return Legend(steps: [], title: "") }
            var steps = ["<" + first] + zip(edges, edges.dropFirst()).map { $0 + "–" + $1 } + ["≥" + last]
            let title: String
            switch metric {
            case .inRange:
                title = String(
                    format: NSLocalizedString(
                        "%% in range",
                        comment: "Statistics By weekday heatmap key: what the in-range steps measure"
                    )
                )
            case .low:
                steps[0] = "0"
                steps[1] = edges.count > 1 ? "<" + edges[1] : steps[1]
                title = String(
                    format: NSLocalizedString(
                        "%% below %@",
                        comment: "Statistics By weekday heatmap key: what the low steps measure, your range's low end"
                    ),
                    lowEdge
                )
            case .mean:
                title = unit
            }
            return Legend(steps: steps, title: title)
        }

        /// The segmented control's titles.
        static func title(_ metric: WeekdayMetric) -> String {
            switch metric {
            case .inRange: return NSLocalizedString(
                    "Time in range",
                    comment: "Statistics By weekday heatmap: the in-range metric"
                )
            case .low: return NSLocalizedString("Time low", comment: "Statistics By weekday heatmap: the low metric")
            case .mean: return NSLocalizedString("Mean", comment: "Statistics, mean glucose")
            }
        }

        func heatmap(_ metric: WeekdayMetric, hoursPerRow: Int) -> Heatmap? {
            hoursPerRow == 1 ? hourHeatmaps[metric] : blockHeatmaps[metric]
        }

        /// The cell of a weekday's hour (or its 3-hour block, `hoursPerRow`) as the metric shows it; nil for a weekday
        /// that isn't a column.
        @MainActor func readout(weekday: Int, hour: Int, hoursPerRow: Int, metric: WeekdayMetric) -> Readout? {
            typealias Format = StatsFormatting
            guard let column = columns.firstIndex(where: { $0.weekday == weekday }) else { return nil }
            let size = hoursPerRow == 1 ? 1 : GlucoseStatsEngine.weekdayBlockHours
            let pools = size == 1 ? result.hours : result.blocks
            let usualPools = size == 1 ? result.usualHours : result.usualBlocks
            let row = Swift.min(Swift.max(hour, 0), 23) / size
            guard pools.indices.contains(column), pools[column].indices.contains(row) else { return nil }
            let pool = pools[column][row]
            let usualPool = usualPools[column][row]
            let start = row * size * 60
            let time = AGP.clockInterval(from: start, to: start + size * 60)
            let title = String(
                format: NSLocalizedString(
                    "%1$@ · %2$@",
                    comment: "Statistics title: the topic, the view (\"Glucose · Overview\")"
                ),
                columns[column].name,
                time
            )
            let usualNote = String(
                format: NSLocalizedString(
                    "Usual: %@ on the other days of the week.",
                    comment: "Statistics By weekday, the cell picked: the hours of the usual"
                ),
                time
            )
            guard pool.hasData else {
                return Self.emptyReadout(title: title, days: result.daysWithData[column], usualNote: usualNote)
            }

            let lowEdge = Format.glucose(bands.low, units: units)
            let metricUnit = Self.metricUnit(metric, units: units, lowEdge: lowEdge)
            let shown = Self.metricValue(pool, metric: metric, units: units)
            let visible = bands.visibleBands
            func percent(_ band: GlucoseBand) -> String {
                Format.percent(band, of: pool)
            }
            let fewNote = Self.fewNote(blockHours: size)
            return Readout(
                title: title,
                subtitle: String(
                    format: NSLocalizedString(
                        "%1$d days · %2$@ readings (%3$@)",
                        comment: "Statistics By weekday, the cell picked: its days with readings, its readings, their time"
                    ),
                    pool.days,
                    pool.readingCount.formatted(),
                    Format.duration(seconds: pool.seconds)
                ),
                hasData: true,
                value: shown,
                unit: metricUnit,
                usual: usualPool.hasData
                    ? String(
                        format: NSLocalizedString("usual %@", comment: "Statistics Insulin Today: a usual by now, \"8.2 U\""),
                        Self.metricValue(usualPool, metric: metric, units: units)
                    )
                    : "",
                isFew: pool.isFew,
                fewNote: fewNote,
                segments: pool.bandShares.barSegments(visible),
                rows: Format.bandRows(visible.reversed(), bands: bands, units: units, percent: percent),
                usualNote: usualNote
            )
        }

        /// The picked cell without readings.
        @MainActor private static func emptyReadout(title: String, days: Int, usualNote: String) -> Readout {
            Readout(
                title: title,
                subtitle: String(
                    format: NSLocalizedString(
                        "%d days · no readings",
                        comment: "Statistics By weekday, the cell picked: the weekday's days with readings"
                    ),
                    days
                ),
                hasData: false,
                value: "–",
                unit: "",
                usual: "",
                isFew: false,
                fewNote: "",
                segments: [],
                rows: [],
                usualNote: usualNote
            )
        }

        /// The cell's number as the metric shows it: "62%", "<1%", "6.3", "–".
        @MainActor private static func metricValue(_ pool: WeekdayPool, metric: WeekdayMetric, units: GlucoseUnits) -> String {
            switch metric {
            case .inRange: return inRangeText(pool)
            case .low: return lowText(pool)
            case .mean: return meanText(pool, units: units)
            }
        }

        /// "in range", "low, below 3.9", "mmol/L mean"
        @MainActor private static func metricUnit(_ metric: WeekdayMetric, units: GlucoseUnits, lowEdge: String) -> String {
            typealias Format = StatsFormatting
            let unit = Format.unit(units)
            switch metric {
            case .inRange:
                return NSLocalizedString("in range", comment: "Statistics Patches: the time in range under a number")
            case .low:
                return String(
                    format: NSLocalizedString(
                        "low, below %@",
                        comment: "Statistics By weekday, the cell picked: the low metric's unit, your range's low end"
                    ),
                    lowEdge
                )
            case .mean:
                return String(
                    format: NSLocalizedString(
                        "%@ mean",
                        comment: "Statistics By weekday, the cell picked: the mean's unit (\"mmol/L mean\")"
                    ),
                    unit
                )
            }
        }

        /// Under the hatching's hours of data in the hour (or the block of `blockHours`).
        private static func fewNote(blockHours: Int) -> String {
            let fewFormat = blockHours == 1
                ? NSLocalizedString(
                    "Few readings: under %d hours of data in this hour, so take it as a hint.",
                    comment: "Statistics By weekday, the cell picked: under the hatching's hours of data"
                )
                : NSLocalizedString(
                    "Few readings: under %d hours of data in this block, so take it as a hint.",
                    comment: "Statistics By weekday, the cell picked at the larger text sizes (3-hour blocks): under the hatching's hours of data"
                )
            return String(format: fewFormat, Int(GlucoseStatsEngine.weekdayFewHours) * blockHours)
        }
    }
}
