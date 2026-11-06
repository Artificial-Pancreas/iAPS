import SwiftUI

// MARK: - IOB

extension Stat.Insulin {
    /// The IOB card: the IOB by time of day, the time below zero shaded. 7–90 d: the headline days' 10th to 90th
    /// percentiles by 15 minutes (`InsulinStatsEngine.iobProfile`), with fewer than 3 the days as lines; Today: today's
    /// 15-minute means so far over the usual, the 7 days before (25–75%, the median dashed).
    struct IOBCard: Equatable {
        /// What the chart draws, in U by the minute of the day. The marks view compares it to skip its body.
        struct Plot: Equatable, Sendable {
            /// A bin's band at its middle minute; `segment`: the bins between two without a value.
            struct Band: Equatable, Sendable {
                let minute: Double
                let segment: Int
                let lower: Double
                let upper: Double
            }

            /// A point of a line; `series`: a line of its own (a gap, a day, a crossing of zero starts one).
            struct Point: Equatable, Sendable {
                let minute: Double
                let value: Double
                let series: Int
            }

            /// the x axis: the minutes of the day
            static let domain = 0.0 ... 1440.0

            let yDomain: ClosedRange<Double>
            let levels: [Double]
            let levelLabels: [String]
            /// 10–90% (7–90 d)
            let outer: [Band]
            /// 25–75%
            let inner: [Band]
            let median: [Point]
            /// Today's usual: the median dashed, its band lighter
            let isUsual: Bool
            /// the headline days as lines (fewer than `InsulinStatsEngine.iobProfileMinimumDays`)
            let dayLines: [Point]
            /// today's line, split where it crosses zero
            let todayAbove: [Point]
            let todayBelow: [Point]
            /// Today: the minute of the day now
            let now: Double?
            /// the local 00/06/12/18, as the AGP's
            let xTicks: [Stat.AGP.Plot.Tick]

            var isEmpty: Bool { median.isEmpty && dayLines.isEmpty && todayAbove.isEmpty && todayBelow.isEmpty }
        }

        /// "by time of day", "so far"
        let detail: String
        let plot: Plot
        let legend: [StatsChartLegend.Item]
        /// "The percentile bands need 3 complete days: …", "The usual needs 3 complete days.", "Needs one complete day"
        let note: String?
    }

    /// The Negative IOB card: the time below zero, its depth and its hours. 7–90 d: over the headline days
    /// (`InsulinStatsEngine.negativeIOB`); Today: so far, its hours over the usual.
    struct NegativeIOBCard: Equatable {
        struct Tile: Equatable, Identifiable {
            let id: Int
            let title: String
            /// "−0.35", "–"
            let value: String
            /// "U", "U · Tue 28 Oct, 03:15", "U · 03:15"
            let unit: String?
        }

        /// "1 h 05 m", "–"
        let headline: String
        /// "per day", "so far"
        let headlineUnit: String
        /// "6% of the time" (7–90 d); nil without, and Today
        let subtitle: String?
        /// why the headline is provisional (7–90 d, `Stat.Insulin.limitedNote`)
        let limitedNote: String?
        /// Mean depth, Lowest (7–90 d); Lowest (Today)
        let tiles: [Tile]
        /// the minutes below zero by hour, hanging from the top (0 at the top edge): per day, or today's over the usual
        /// dashed
        let hourPlot: StatsHourBars.Plot
        /// "minutes per day", "minutes"
        let hourDetail: String
        /// Today's; none for 7–90 d
        let hourLegend: [StatsChartLegend.Item]
    }

    /// The bars of the Negative IOB card, in the warning colour (less insulin than the scheduled basal, as "less than
    /// scheduled")
    static let negativeHourStyle = StatsBarStyle(fill: Color(.statsWarning))

    // MARK: IOB card

    /// 7–90 d: the percentiles of the headline days with IOB rows, or with fewer than 3 of them the days as lines;
    /// "Needs one complete day" without a headline day, "No IOB data" without IOB rows on them.
    /// - Parameter titles: the days' ("Tue 28 Oct"), by day
    @MainActor static func iobCard(period days: [DayInsulin], titles: [String]) -> IOBCard {
        let detail = NSLocalizedString("by time of day", comment: "Statistics Insulin: the IOB card's detail")
        let headline = days.indices.filter { days[$0].isHeadline }
        guard headline.isNotEmpty else {
            return IOBCard(detail: detail, plot: iobPlot(), legend: [], note: noCompleteDay)
        }
        // the headline days with IOB rows: a headline day is the pump data's, the IOB is the loop's
        let withIOB = headline.filter { days[$0].iob.bins.contains { $0 != nil } }
        guard withIOB.isNotEmpty else {
            return IOBCard(detail: detail, plot: iobPlot(), legend: [], note: nil)
        }
        let headlineDays = withIOB.map { days[$0] }
        let banded = withIOB.count >= InsulinStatsEngine.iobProfileMinimumDays
        let plot = banded
            ? iobPlot(profile: InsulinStatsEngine.iobProfile(headlineDays))
            : iobPlot(lines: headlineDays.map(\.iob.bins))
        var legend: [StatsChartLegend.Item]
        if banded {
            legend = [
                StatsChartLegend.Item(
                    id: 0,
                    key: .rule(IOBChartStyle.median),
                    title: NSLocalizedString("Median", comment: "Statistics AGP, the 50th percentile")
                ),
                StatsChartLegend.Item(
                    id: 1,
                    key: .swatch(StatsBarStyle(fill: IOBChartStyle.inner)),
                    title: StatsFormatting.percentileBand(25, 75)
                ),
                StatsChartLegend.Item(
                    id: 2,
                    key: .swatch(StatsBarStyle(fill: IOBChartStyle.outer)),
                    title: StatsFormatting.percentileBand(10, 90)
                )
            ]
        } else {
            legend = [StatsChartLegend.Item(
                id: 0,
                key: .rule(IOBChartStyle.median),
                title: withIOB.count == 1
                    ? (titles.indices.contains(withIOB[0]) ? titles[withIOB[0]] : "")
                    : NSLocalizedString("Each day", comment: "Statistics Insulin IOB card legend: a line per complete day")
            )]
        }
        legend.append(negativeLegendItem)
        let note: String? = banded ? nil : withIOB.count == 1
            ? NSLocalizedString(
                "The percentile bands need 3 complete days: the day is drawn as a line.",
                comment: "Statistics Insulin IOB card: one complete day, drawn as a line"
            )
            : NSLocalizedString(
                "The percentile bands need 3 complete days: the days are drawn as lines.",
                comment: "Statistics Insulin IOB card: two complete days, drawn as lines"
            )
        return IOBCard(detail: detail, plot: plot, legend: legend, note: note)
    }

    /// Today: today's means so far over the usual, the headline days of the 7 before (from 3 of them).
    /// - Parameters:
    ///   - days: Today's: the 7 days before today, and today
    ///   - now: the read's time, to its minute
    ///   - period: the usual's ("7 d")
    @MainActor static func iobCard(today days: [DayInsulin], now: Date, period: StatsPeriod, calendar: Calendar) -> IOBCard {
        let usualDays = days.filter { $0.isHeadline && $0.iob.bins.contains { $0 != nil } }
        let banded = usualDays.count >= InsulinStatsEngine.iobProfileMinimumDays
        let clock = InsulinClockAverage.clock(of: now, calendar: calendar)
        let plot = iobPlot(
            profile: banded ? InsulinStatsEngine.iobProfile(usualDays) : nil,
            isUsual: true,
            today: days.last(where: \.isToday)?.iob.bins ?? [],
            now: (Double(clock.hour) + clock.passed) * 60
        )
        var legend = [StatsChartLegend.Item(
            id: 0,
            key: .rule(Color(.insulin)),
            title: NSLocalizedString("Today", comment: "")
        )]
        if plot.todayBelow.isNotEmpty {
            legend.append(StatsChartLegend.Item(
                id: 1,
                key: .rule(Color(.statsWarning)),
                title: NSLocalizedString("Today, negative", comment: "Statistics Insulin IOB card legend: today below zero")
            ))
        }
        if banded {
            legend.append(StatsChartLegend.Item(
                id: 2,
                key: .dashed,
                title: String(
                    format: NSLocalizedString(
                        "Usual · %@",
                        comment: "Statistics Insulin Today by hour: the usual by hour, over the period (\"7 d\")"
                    ),
                    StatsFormatting.label(period)
                )
            ))
            legend
                .append(StatsChartLegend.Item(
                    id: 3,
                    key: .swatch(StatsBarStyle(fill: IOBChartStyle.usual)),
                    title: StatsFormatting.percentileBand(25, 75)
                ))
        }
        legend.append(negativeLegendItem)
        return IOBCard(
            detail: NSLocalizedString("so far", comment: ""),
            plot: plot,
            legend: legend,
            note: banded
                ? nil
                : NSLocalizedString("The usual needs 3 complete days.", comment: "Statistics Insulin IOB card, Today")
        )
    }

    /// The chart's plot: the profile's bands and median, days as lines, today's line split at zero; the axis from at
    /// least −1 to 2 U, whole units (every second one past 6 U), "0 U" at zero.
    /// - Parameters:
    ///   - profile: by bin; nil: no bands
    ///   - isUsual: the profile is Today's usual: 25–75% only, the median dashed
    ///   - lines: days by bin, each a line
    ///   - today: today's means by bin
    ///   - now: the minute of the day now (Today)
    static func iobPlot(
        profile: [IOBProfileBin?]? = nil,
        isUsual: Bool = false,
        lines: [[Double?]] = [],
        today: [Double?]? = nil,
        now: Double? = nil
    ) -> IOBCard.Plot {
        typealias Plot = IOBCard.Plot
        var outer: [Plot.Band] = []
        var inner: [Plot.Band] = []
        var median: [Plot.Point] = []
        var segment = 0
        var inSegment = false
        for (bin, value) in (profile ?? []).enumerated() {
            guard let value else {
                if inSegment {
                    segment += 1
                }
                inSegment = false
                continue
            }
            inSegment = true
            let minute = iobMinute(ofBin: bin)
            if !isUsual {
                outer.append(Plot.Band(minute: minute, segment: segment, lower: value.p10, upper: value.p90))
            }
            inner.append(Plot.Band(minute: minute, segment: segment, lower: value.p25, upper: value.p75))
            median.append(Plot.Point(minute: minute, value: value.p50, series: segment))
        }

        var dayLines: [Plot.Point] = []
        var series = 0
        for line in lines {
            var previous: Double?
            for (bin, value) in line.enumerated() {
                guard let value else {
                    if previous != nil {
                        series += 1
                    }
                    previous = nil
                    continue
                }
                dayLines.append(Plot.Point(minute: iobMinute(ofBin: bin), value: value, series: series))
                previous = value
            }
            series += 1
        }

        let (above, below) = signRuns(today ?? [])
        let values = outer.flatMap { [$0.lower, $0.upper] } + inner.flatMap { [$0.lower, $0.upper] }
            + (median + dayLines + above + below).map(\.value)
        let lower = Swift.min(-1, (values.min() ?? 0).rounded(.down))
        let upper = Swift.max(2, (values.max() ?? 0).rounded(.up))
        let step = upper - lower > 6 ? 2.0 : 1.0
        let levels = Array(stride(from: (lower / step).rounded(.up) * step, through: upper, by: step))
        return Plot(
            yDomain: lower ... upper,
            levels: levels,
            levelLabels: levels.map { level in
                level == 0 ? StatsAmount.withUnits("0") : level < 0 ? "−" + StatsAmount.number(-level, digits: 0) : StatsAmount
                    .number(level, digits: 0)
            },
            outer: outer,
            inner: inner,
            median: median,
            isUsual: isUsual,
            dayLines: dayLines,
            todayAbove: above,
            todayBelow: below,
            now: now,
            xTicks: Stat.AGP.Plot.gridMinutes.dropLast().map { Stat.AGP.Plot.Tick(minute: $0, label: Stat.AGP.clockTime($0)) }
        )
    }

    /// A line by bin split where it crosses zero (at the crossing, by straight lines between the bins' middles): the
    /// stretches at or above zero, and below it. A gap ends a stretch.
    static func signRuns(_ values: [Double?]) -> (above: [IOBCard.Plot.Point], below: [IOBCard.Plot.Point]) {
        typealias Point = IOBCard.Plot.Point
        var above: [Point] = []
        var below: [Point] = []
        var series = 0
        var last: (minute: Double, value: Double)?
        func append(_ minute: Double, _ value: Double, below isBelow: Bool) {
            if isBelow {
                below.append(Point(minute: minute, value: value, series: series))
            } else {
                above.append(Point(minute: minute, value: value, series: series))
            }
        }
        for (bin, value) in values.enumerated() {
            guard let value else {
                if last != nil {
                    series += 1
                }
                last = nil
                continue
            }
            let minute = iobMinute(ofBin: bin)
            if let previous = last, (previous.value < 0) != (value < 0) {
                let crossing = previous.minute + (0 - previous.value) / (value - previous.value) * (minute - previous.minute)
                // at a bin's own 0 the bin's point is the crossing: not twice
                if crossing > previous.minute {
                    append(crossing, 0, below: previous.value < 0)
                }
                series += 1
                if crossing < minute {
                    append(crossing, 0, below: value < 0)
                }
            }
            append(minute, value, below: value < 0)
            last = (minute, value)
        }
        return (above, below)
    }

    /// The minute of the day a 15-minute bin is drawn at: its middle.
    static func iobMinute(ofBin bin: Int) -> Double {
        Double(bin * DayIOB.binMinutes) + Double(DayIOB.binMinutes) / 2
    }

    private static var negativeLegendItem: StatsChartLegend.Item {
        StatsChartLegend.Item(
            id: 9,
            key: .swatch(StatsBarStyle(fill: IOBChartStyle.negativeKey)),
            title: NSLocalizedString("Negative", comment: "Statistics Insulin IOB card legend: the region below zero")
        )
    }

    /// An IOB: "−0.42", "1.20", "0.00" (no sign when it rounds to 0).
    static func signedIOB(_ value: Double, digits: Int = 2) -> String {
        let magnitude = StatsAmount.number(abs(value), digits: digits)
        return value < 0 && magnitude != StatsAmount.number(0, digits: digits) ? "−" + magnitude : magnitude
    }

    // MARK: Negative IOB card

    /// 7–90 d, over the headline days: the time per day and its share, the mean depth, the lowest (with its day and
    /// time), the minutes per day by hour.
    /// - Parameter titles: the days' ("Tue 28 Oct"), by day
    @MainActor static func negativeCard(period days: [DayInsulin], titles: [String], summary: InsulinSummary) -> NegativeIOBCard {
        typealias Format = StatsFormatting
        let stats = InsulinStatsEngine.negativeIOB(days)
        func title(_ index: Int?) -> String? {
            index.flatMap { titles.indices.contains($0) ? titles[$0] : nil }
        }
        let headline = stats.secondsPerDay.map { Format.duration(seconds: $0) } ?? "–"
        let share = stats.share.map { share in
            String(
                format: NSLocalizedString(
                    "%@ of the time",
                    comment: "Statistics Insulin Negative IOB: the share of the IOB time below zero, \"6%\""
                ),
                Format.percent(fraction: share)
            )
        }
        // the pump data's note; otherwise the IOB rows not covering the headline days (the same rule)
        let note = limitedNote(summary) ?? (
            stats.isIOBLimited && stats.secondsPerDay != nil
                ? NSLocalizedString(
                    "IOB data doesn't cover every complete day of this period, so these numbers may not represent it.",
                    comment: "Statistics limited data: the IOB rows don't cover every complete day"
                )
                : nil
        )
        let perDay = NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count")
        // the lowest row's own day: a row running over midnight is the day before's
        let lowestDay = stats.lowestDay.map { index in
            stats.lowestAt.map { $0 < days[index].day.start && index > 0 ? index - 1 : index } ?? index
        }
        let lowestAt = stats.lowestAt.flatMap { date in
            title(lowestDay).map { day in
                String(
                    format: NSLocalizedString(
                        "U · %1$@, %2$@",
                        comment: "Statistics Insulin Negative IOB: the lowest IOB's unit, its day and time (\"U · Tue 28 Oct, 03:15\")"
                    ),
                    day,
                    date.formatted(date: .omitted, time: .shortened)
                )
            }
        }
        let tiles = [
            NegativeIOBCard.Tile(
                id: 0,
                title: NSLocalizedString("Mean depth", comment: "Statistics Insulin Negative IOB: the mean IOB below zero"),
                value: stats.meanDepth.map { signedIOB($0) } ?? "–",
                unit: NSLocalizedString("U", comment: "")
            ),
            NegativeIOBCard.Tile(
                id: 1,
                title: NSLocalizedString("Lowest", comment: "Statistics Insulin Negative IOB: the lowest IOB"),
                value: stats.lowest.map { signedIOB($0) } ?? "–",
                unit: lowestAt ?? NSLocalizedString("U", comment: "")
            )
        ]
        let minutes = stats.hours?.map { $0 / 60 } ?? []
        return NegativeIOBCard(
            headline: headline,
            headlineUnit: perDay,
            subtitle: share,
            limitedNote: note,
            tiles: tiles,
            hourPlot: negativeHourPlot(minutes.map { Optional($0) }),
            hourDetail: NSLocalizedString("minutes per day", comment: "Statistics Insulin Negative IOB by hour: the unit"),
            hourLegend: []
        )
    }

    /// Today: so far, the lowest, the minutes by hour over the usual (`InsulinClockAverage.negativeIOBSeconds`). "–"
    /// without IOB rows today.
    /// - Parameters:
    ///   - days: Today's: the 7 days before today, and today
    ///   - average: the usual (`InsulinStatsEngine.clockAverage` of the days)
    ///   - now: the read's time, to its minute
    @MainActor static func negativeCard(
        today days: [DayInsulin],
        average: InsulinClockAverage?,
        now: Date,
        period: StatsPeriod,
        calendar: Calendar
    ) -> NegativeIOBCard {
        typealias Format = StatsFormatting
        let index = days.lastIndex(where: \.isToday)
        let day = index.map { days[$0] }
        let seconds: Double? = (day?.iobSeconds ?? 0) > 0 ? day?.negativeIOBSeconds : nil
        let lowest = day?.iob.lowest
        let soFar = NSLocalizedString("so far", comment: "")
        let tiles = [
            NegativeIOBCard.Tile(
                id: 0,
                title: NSLocalizedString("Lowest", comment: "Statistics Insulin Negative IOB: the lowest IOB"),
                value: lowest.map { signedIOB($0.iob) } ?? "–",
                unit: lowest.map { lowest in
                    String(
                        format: NSLocalizedString(
                            "U · %@",
                            comment: "Statistics Insulin Negative IOB Today: the lowest IOB's unit and time (\"U · 03:15\")"
                        ),
                        lowest.at.formatted(date: .omitted, time: .shortened)
                    )
                } ?? NSLocalizedString("U", comment: "")
            )
        ]

        // by hour: the hours up to now, the current one so far, none after it
        let clock = InsulinClockAverage.clock(of: now, calendar: calendar)
        let currentHour = day.map { $0.day.contains(now) ? clock.hour : -1 } ?? -1
        let minutes = (0 ..< 24).map { hour -> Double? in
            guard hour <= currentHour, let h = day?.hours.first(where: { $0.hour == hour }) else { return nil }
            return h.negativeIOBSeconds / 60
        }
        let usualMinutes = average?.negativeIOBSeconds?.within.map { $0 / 60 }
        var legend =
            [StatsChartLegend.Item(id: 0, key: .swatch(negativeHourStyle), title: NSLocalizedString("Today", comment: ""))]
        if usualMinutes != nil {
            legend.append(StatsChartLegend.Item(
                id: 1,
                key: .tick,
                title: String(
                    format: NSLocalizedString(
                        "Usual · %@",
                        comment: "Statistics Insulin Today by hour: the usual by hour, over the period (\"7 d\")"
                    ),
                    Format.label(period)
                )
            ))
        }

        return NegativeIOBCard(
            headline: seconds.map { Format.duration(seconds: $0) } ?? "–",
            headlineUnit: soFar,
            subtitle: nil,
            limitedNote: nil,
            tiles: tiles,
            hourPlot: negativeHourPlot(minutes, usual: usualMinutes),
            hourDetail: NSLocalizedString("minutes", comment: "Statistics Insulin Negative IOB Today by hour: the unit"),
            hourLegend: legend
        )
    }

    /// The minutes below zero by hour, hanging from the top edge (below zero is down): the bars from 0 down to each
    /// hour's minutes, the usual a tick at the same depth; the axis 0, 15 m, 30 m (whole half hours, halved),
    /// 0 at the top (`topInset` above it).
    /// - Parameter minutes: by hour, nil for none (Today after now)
    @MainActor static func negativeHourPlot(_ minutes: [Double?], usual: [Double]? = nil) -> StatsHourBars.Plot {
        let maximum = Swift.max(minutes.compactMap { $0 }.max() ?? 0, usual?.max() ?? 0)
        let levels = StatsBarAxis.levels(maximum: maximum, unit: 30, divisions: 2)
        let depth = levels.last ?? 30
        let parts = minutes.indices.compactMap { hour -> StatsHourBars.Part? in
            guard let value = minutes[hour], value > 0 else { return nil }
            return StatsHourBars.Part(
                hour: hour,
                series: 0,
                lower: -Swift.min(value, depth),
                upper: 0,
                style: negativeHourStyle
            )
        }
        return StatsHourBars.Plot(
            parts: parts,
            usual: usual.map { $0.map { Optional(-Swift.min($0, depth)) } } ?? [],
            // a little room above 0 (about 2 pt of 110)
            yDomain: -depth ... depth * topInset,
            levels: levels.reversed().map { -$0 },
            levelLabels: levels.reversed().map { $0 == 0 ? "0" : StatsFormatting.duration(minutes: $0) }
        )
    }

    /// The room above 0 on the hour bars, of their depth.
    static let topInset = 0.02
}
