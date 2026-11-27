import Foundation

// By hour, By weekday and Weekly as a report prints them: the on-screen views' results and display models
// (`Stat.HourOfDayResult`, `Stat.Weekday`, `Stat.Weekly`), without anything that depends on a selection: a printed
// page shows every hour, cell and week. The numbers are the data's (computed once, on the report's bands); a page's
// unit only decides how values and range labels are written.

extension Stat {
    /// A part's own header lines: its dates and what they hold, when they aren't the report's period (By weekday's
    /// whole weeks, Weekly's 13 weeks, Good & bad days' complete days).
    struct ReportPageHeader: Equatable {
        /// "20 Oct 2026 – 16 Nov 2026"
        let dateRange: String
        /// "4 whole weeks to yesterday · 4 of each weekday"
        let days: String

        /// "20 Oct 2026 – 16 Nov 2026": the first and the last day (their starts), in the calendar's time zone.
        static func dateRange(_ first: Date, _ last: Date, calendar: Calendar) -> String {
            let style = ReportPageChrome.dayStyle(calendar)
            return String(
                format: NSLocalizedString("%@ – %@", comment: "Statistics date range, first and last day"),
                first.formatted(style),
                last.formatted(style)
            )
        }

        /// The first and the last day of a window of whole days (`[start, end)`).
        static func dateRange(_ window: DateInterval, calendar: Calendar) -> String {
            let last = calendar.startOfDay(for: Swift.max(window.start, window.end.addingTimeInterval(-1)))
            return dateRange(window.start, last, calendar: calendar)
        }
    }

    // MARK: - By hour

    /// The By hour page: the 24 hours' bands as stacked columns, every hour's numbers, and "When it happens".
    struct ReportHours: Equatable {
        struct Column: Equatable, Identifiable {
            let id: Int
            /// "In range"
            let title: String
            /// "70–180"
            let subtitle: String
        }

        struct Row: Equatable, Identifiable {
            /// the clock hour, 0...23
            let id: Int
            /// "08:00–09:00"
            let time: String
            /// by column; "–" for an hour without readings
            let cells: [String]
        }

        /// An hour's column of the chart.
        struct Bar: Equatable, Identifiable {
            let id: Int
            /// the nonzero bands stacked from very low up, fractions of the hour's covered time; none without readings
            let segments: [BandShares.Segment]
        }

        struct Tick: Equatable, Identifiable {
            /// the hour its label starts at
            let id: Int
            let label: String
        }

        /// A line of "When it happens".
        struct Peak: Equatable, Identifiable {
            let id: Int
            let band: GlucoseBand
            /// "Lows"
            let title: String
            /// "03:00–04:00"
            let time: String
            /// "below 70 · 12% of that hour"
            let detail: String
        }

        struct LegendItem: Equatable, Identifiable {
            let band: GlucoseBand
            /// "In range 70–180"
            let text: String

            var id: GlucoseBand { band }
        }

        let showsChart: Bool
        let showsTable: Bool
        let bars: [Bar]
        /// every third hour
        let ticks: [Tick]
        /// "0%", "50%", "100%"
        let levels: [String]
        let legend: [LegendItem]
        let columns: [Column]
        let rows: [Row]
        /// lows, highs, most in range; those without any left out
        let peaks: [Peak]
        /// "Each hour pools its readings over the period's 14 days."
        let note: String
        /// no reading in the period
        let isEmpty: Bool

        /// Below or above the range as an hour's row writes it: the sum of the hour's largest-remainder percents of
        /// the group's two bands (so the row adds up to 100 and equals "When it happens"), "<1%" when there is some but
        /// the sum is 0 (as `GlucoseStatsEngine.weekdayPool`).
        @MainActor static func percent(_ group: PeakHour.Group, of hour: HourOfDayHour) -> String {
            let percent = group.bands.reduce(0) { $0 + hour.percent($1) }
            let fraction = group.bands.reduce(0) { $0 + hour.fraction($1) }
            return StatsFormatting.percent(percent, belowOne: fraction > 0 && percent == 0)
        }

        /// - Parameter units: the page's: how the ranges are written
        @MainActor init(_ data: ReportData, units: GlucoseUnits) {
            typealias Format = StatsFormatting
            let settings = data.request.byHour
            let labels = ReportBuilder.standardBands(units)
            let hours = data.hourOfDay?.hours ?? []
            let times = data.hourOfDay?.labels ?? []
            showsChart = settings.showsChart
            showsTable = settings.showsTable
            isEmpty = hours.allSatisfy { !$0.hasData }

            bars = hours.map { Bar(id: $0.hour, segments: $0.segments) }
            ticks = stride(from: 0, to: 24, by: 3).map { Tick(id: $0, label: AGP.clockTime($0 * 60)) }
            levels = [0, 0.5, 1].map { Format.percent(fraction: $0) }
            legend = GlucoseBand.allCases.reversed().map { band in
                LegendItem(band: band, text: Format.name(band) + " " + (Format.label(band, bands: labels, units: units) ?? ""))
            }

            let lowEdge = Format.glucose(labels.low, units: units)
            let highEdge = Format.glucose(labels.high, units: units)
            func column(_ id: Int, _ title: String, _ subtitle: String) -> Column {
                Column(id: id, title: title, subtitle: subtitle)
            }
            func band(_ id: Int, _ band: GlucoseBand) -> Column {
                column(id, Format.name(band), Format.label(band, bands: labels, units: units) ?? "")
            }
            columns = [
                band(0, .inRange),
                column(
                    1,
                    NSLocalizedString("Below", comment: "PDF report, Days table: the time below the in-range band"),
                    "< " + lowEdge
                ),
                column(
                    2,
                    NSLocalizedString("Above", comment: "PDF report, Days table: the time above the in-range band"),
                    "> " + highEdge
                ),
                band(3, .veryLow),
                band(4, .low),
                band(5, .high),
                band(6, .veryHigh),
                column(
                    7,
                    NSLocalizedString("Data", comment: "PDF report, By hour: the hours of readings in the clock hour"),
                    NSLocalizedString("hours", comment: "PDF report, By hour: the unit of the data column")
                )
            ]
            rows = hours.enumerated().map { index, hour -> Row in
                let time = index < times.count ? times[index] : AGP.clockTime(hour.hour * 60)
                guard hour.hasData else {
                    return Row(id: hour.hour, time: time, cells: Array(repeating: "–", count: 8))
                }
                return Row(
                    id: hour.hour,
                    time: time,
                    cells: [
                        Format.percent(.inRange, of: hour),
                        Self.percent(.below, of: hour),
                        Self.percent(.above, of: hour),
                        Format.percent(.veryLow, of: hour),
                        Format.percent(.low, of: hour),
                        Format.percent(.high, of: hour),
                        Format.percent(.veryHigh, of: hour),
                        StatsAmount.number(hour.hoursOfData, digits: 0)
                    ]
                )
            }

            let found = data.hourOfDay.map { HourOfDay.shownPeaks($0) } ?? []
            peaks = found.enumerated().map { index, shown -> Peak in
                let percent = shown.percent
                let time = shown.index < times.count ? times[shown.index] : AGP.clockTime(shown.peak.hour * 60)
                switch shown.group {
                case .below:
                    return Peak(
                        id: index,
                        band: .low,
                        title: NSLocalizedString("Lows", comment: "Statistics By hour, when it happens: below your range"),
                        time: time,
                        detail: String(
                            format: NSLocalizedString(
                                "below %1$@ · %2$@ of that hour",
                                comment: "Statistics By hour, when it happens: your range's low end, the share of the hour"
                            ),
                            lowEdge,
                            percent
                        )
                    )
                case .above:
                    return Peak(
                        id: index,
                        band: .high,
                        title: NSLocalizedString("Highs", comment: "Statistics By hour, when it happens: above your range"),
                        time: time,
                        detail: String(
                            format: NSLocalizedString(
                                "above %1$@ · %2$@ of that hour",
                                comment: "Statistics By hour, when it happens: your range's high end, the share of the hour"
                            ),
                            highEdge,
                            percent
                        )
                    )
                case .inRange:
                    return Peak(
                        id: index,
                        band: .inRange,
                        title: NSLocalizedString(
                            "Most in range",
                            comment: "Statistics By hour, when it happens: the hour most in your range"
                        ),
                        time: time,
                        detail: String(
                            format: NSLocalizedString(
                                "%@ of that hour in range",
                                comment: "PDF report, By hour, when it happens: the share of the hour in range"
                            ),
                            percent
                        )
                    )
                }
            }
            note = String(
                format: NSLocalizedString(
                    "Each hour pools its readings over the period's %d days, by the local clock.",
                    comment: "PDF report, By hour: what an hour's numbers are of"
                ),
                data.request.period.calendarDayCount ?? 1
            )
        }
    }

    // MARK: - By weekday

    /// The By weekday page: the weekdays' bars and numbers, the weekday × time heat map in 3-hour blocks with each
    /// cell's value, and the workdays against the weekend (`Stat.Weekday`, the screen's model).
    struct ReportWeekdays: Equatable {
        struct Cell: Equatable {
            /// 0...4 (`GlucoseStatsEngine.weekdayStepEdges`); nil without readings
            let step: Int?
            /// few hours of data: the value is a hint
            let isFew: Bool
            /// "62%", "7.4", "–"
            let text: String
        }

        let header: ReportPageHeader
        /// the screen's model: the columns, the bars, the table's rows, the comparison
        let model: Weekday
        let metric: WeekdayMetric
        /// "Time in range by weekday and time of day"
        let heatTitle: String
        /// the steps' key, written in the page's unit
        let legend: Weekday.Legend
        /// by column, then by 3-hour block from 00:00; the steps are the first unit's on every page
        let cells: [[Cell]]
        /// some cell has few hours of data
        let fewNote: String?
        /// in place of the bars, the table and the map: the weeks hold no reading
        let emptyNote: String?

        /// A pool's value as its cell writes it.
        @MainActor static func text(_ pool: WeekdayPool, metric: WeekdayMetric, units: GlucoseUnits) -> String {
            pool.hasData ? Weekday.metricValue(pool, metric: metric, units: units) : "–"
        }

        /// The mean's key on the page of another unit than the steps': the same edges, written in the page's unit
        /// ("<6", "6–7" mmol/L are "<108", "108–126" mg/dL). nil for the other metrics and on the steps' own unit: the
        /// screen's key.
        @MainActor static func legend(_ metric: WeekdayMetric, of first: GlucoseUnits, in units: GlucoseUnits) -> Weekday
            .Legend?
        {
            guard metric == .mean, first != units else { return nil }
            let edges = GlucoseStatsEngine.weekdayStepEdges(metric, units: first).map { edge -> String in
                let mgdl = first == .mmolL ? edge / GlucoseUnits.exchangeRate : edge
                return StatsFormatting.glucose(NSDecimalNumber(decimal: mgdl).doubleValue, units: units)
            }
            guard let low = edges.first, let high = edges.last else { return nil }
            return Weekday.Legend(
                steps: ["<" + low] + zip(edges, edges.dropFirst()).map { $0 + "–" + $1 } + ["≥" + high],
                title: StatsFormatting.unit(units)
            )
        }

        /// nil without the part's result
        /// - Parameters:
        ///   - units: the page's
        ///   - calendar: the weekdays' names', the dates' time zone
        @MainActor init?(_ data: ReportData, units: GlucoseUnits, calendar: Calendar) {
            guard let result = data.weekday else { return nil }
            let settings = StatsSettings(report: units, hbA1cUnit: data.request.hbA1cUnit)
            let model = Weekday(result, settings: settings, calendar: calendar)
            self.model = model
            let metric = data.request.byWeekday.heatMap.metric
            self.metric = metric
            heatTitle = String(
                format: NSLocalizedString(
                    "%@ by weekday and time of day",
                    comment: "PDF report, By weekday: the heat map's title, its metric (\"Time in range\")"
                ),
                Weekday.title(metric)
            )
            // one set of steps: the first unit's (the mean's edges are round numbers of the unit they are taken in), so a
            // cell has the same colour on both units' pages; the other unit's page only writes the key in its own
            let first = data.request.units.first ?? units
            let stepsModel = first == units
                ? model
                : Weekday(result, settings: StatsSettings(report: first, hbA1cUnit: data.request.hbA1cUnit), calendar: calendar)
            legend = Self.legend(metric, of: first, in: units) ?? model.legends[metric] ?? Weekday.Legend(steps: [], title: "")
            let steps = stepsModel.blockHeatmaps[metric]?.cells ?? []
            cells = result.blocks.enumerated().map { column, pools in
                pools.enumerated().map { row, pool in
                    let cell = column < steps.count && row < steps[column].count ? steps[column][row] : nil
                    return Cell(
                        step: cell?.step,
                        isFew: cell?.isFew ?? false,
                        text: Self.text(pool, metric: metric, units: units)
                    )
                }
            }
            emptyNote = result.isEmpty ? NSLocalizedString("No CGM data in this period", comment: "") : nil
            fewNote = cells.contains { $0.contains { $0.isFew } }
                ? NSLocalizedString(
                    "A cell in brackets has few hours of data: its value is less certain.",
                    comment: "PDF report, By weekday: the heat map's cells with little data"
                )
                : nil
            header = ReportPageHeader(
                dateRange: ReportPageHeader.dateRange(result.window.start, result.lastDay, calendar: calendar),
                days: String(
                    format: NSLocalizedString(
                        "%1$d whole weeks to yesterday · %2$@",
                        comment: "PDF report, By weekday header: the weeks, then the days of each weekday (\"4 of each weekday\")"
                    ),
                    result.weeks,
                    model.countNote
                )
            )
        }
    }

    // MARK: - Weekly

    /// The Weekly page: 13 weeks against their average, as two small charts and a table (`Stat.Weekly`, the screen's
    /// model, in the page's unit).
    struct ReportWeeks: Equatable {
        struct Column: Equatable, Identifiable {
            let id: Int
            let title: String
            let subtitle: String
        }

        let header: ReportPageHeader
        /// the screen's model: the charts' plots, the rows (newest first)
        let model: Weekly
        /// "In range 70–180 mg/dL"
        let inRangeTitle: String
        /// in range, its Δ, the mean, its Δ
        let columns: [Column]
        /// "Δ: the week against the 13 weeks' average, as shown."
        let note: String
        /// in place of the charts and the table: no week has a reading
        let emptyNote: String?

        /// Weekly's result of the page's unit.
        static func result(_ data: ReportData, units: GlucoseUnits) -> WeeklyResult? {
            data.weekly.first { $0.units == units }
        }

        /// nil without the part's result
        @MainActor init?(_ data: ReportData, units: GlucoseUnits, calendar: Calendar) {
            typealias Format = StatsFormatting
            guard let result = Self.result(data, units: units) else { return nil }
            let period = ReportRequest.weeklyPeriod
            let model = Weekly(result, period: period)
            self.model = model
            let labels = ReportBuilder.standardBands(units)
            let unit = Format.unit(units)
            inRangeTitle = Format.name(.inRange) + " " + Format.inRangeLabel(bands: labels, units: units)
            let delta = NSLocalizedString("Δ", comment: "PDF report, Weekly: the difference from the average")
            let average = NSLocalizedString("vs average", comment: "PDF report, Weekly: what a Δ is against")
            columns = [
                Column(id: 0, title: Format.name(.inRange), subtitle: Format.label(.inRange, bands: labels, units: units) ?? ""),
                Column(id: 1, title: delta, subtitle: average),
                Column(id: 2, title: NSLocalizedString("Mean", comment: "Statistics, mean glucose"), subtitle: unit),
                Column(id: 3, title: delta, subtitle: average)
            ]
            let weeks = period.weekCount ?? result.weeks.count
            emptyNote = result.isEmpty ? NSLocalizedString("No CGM data in this period", comment: "") : nil
            note = String(
                format: NSLocalizedString(
                    "Δ: the week against the %d weeks' average, as shown. Glucose is time-weighted.",
                    comment: "PDF report, Weekly: what the Δ columns are"
                ),
                weeks
            )
            let first = result.weeks.first?.days.start ?? result.summary.window.start
            let last = result.weeks.last?.lastDay ?? first
            header = ReportPageHeader(
                dateRange: ReportPageHeader.dateRange(first, last, calendar: calendar),
                days: String(
                    format: NSLocalizedString(
                        "%d weeks, the last one to today",
                        comment: "PDF report, Weekly header: the weeks printed"
                    ),
                    weeks
                )
            )
        }
    }
}
