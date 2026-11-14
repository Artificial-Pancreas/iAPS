import Charts
import SwiftUI

extension Stat {
    /// The Trace (the Day tab), formatted for display. The readings, the axes and the numbers come ready from the
    /// provider (`TraceResult`); only strings are built here.
    struct Trace: Equatable {
        /// What the chart draws. The marks view compares it to skip its body (`TraceMarks`), so it holds no selection.
        struct Plot: Equatable, Sendable {
            struct Tick: Equatable, Sendable {
                let date: Date
                let label: String
            }

            struct Level: Equatable, Sendable {
                let mgdl: Int
                let label: String
            }

            /// what the selection was picked in (`TraceSelection`)
            let range: TraceRange
            /// the x axis: the whole day, or the 24 hours
            let domain: DateInterval
            /// mg/dL
            let axis: ClosedRange<Int>
            /// oldest -> newest
            let points: [TraceResult.Point]
            /// the in-range band, shaded (not while the usual day is on), solid rules at its edges
            let low: Int
            let high: Int
            /// 54, 180 (mmol: 181) and 250 inside the axis, dashed; not where a range edge is
            let dashed: [Int]
            /// the local 00/06/12/18, and "now" at the end of the 24 hours
            let xTicks: [Tick]
            /// the last tick is the end of the 24 hours ("now")
            let endsNow: Bool
            let yLabels: [Level]
            let units: GlucoseUnits

            /// the solid rules
            var edges: [Int] { low == high ? [low] : [low, high] }

            /// The reading nearest to the date, the newest one without a date; nil without readings.
            func index(near date: Date?) -> Int? {
                guard let newest = points.indices.last else { return nil }
                guard let date else { return newest }
                return GlucoseStatsEngine.nearestIndex(to: date, in: points) { $0.time }
            }
        }

        let range: TraceRange
        /// what it was computed for: `.today` when its day is today (as of `now`)
        let pick: TraceDay
        /// "Today", "Last 24 hours", "Mon 27 Oct"
        let title: String
        /// Today and 24 h: the times; nil for a past day
        let windowSubtitle: String?
        let plot: Plot
        let legendBands: [GlucoseBand]

        let summaryTitle: String
        /// "CGM coverage 92%"
        let coverage: String
        let inRange: String
        /// "70–145 mg/dL" (the Overview's `inRangeRange`)
        let inRangeRange: String
        let tirTitle: String
        let tir: String
        let titrTitle: String
        let titr: String
        let unit: String
        let mean: String
        let cv: String
        let minMax: String

        @MainActor init(_ result: TraceResult, settings: StatsSettings, now: Date = Date()) {
            typealias Format = StatsFormatting
            let summary = result.summary
            let bands = summary.bands
            let units = settings.units
            // no reading starts in it (the previous evening's span running past midnight is no reading): dashes
            let empty = result.points.isEmpty
            let todayTitle = NSLocalizedString("Today", comment: "")
            let last24hTitle = NSLocalizedString("Last 24 hours", comment: "")

            range = result.range
            let shownEnd = Self.minute(Swift.min(result.window.end, now))
            switch result.range {
            case .last24h:
                pick = .last24h
                title = last24hTitle
                // both ends from the shown end: E can be a few minutes after now (the newest reading's span)
                windowSubtitle = Self.timeRange(shownEnd.addingTimeInterval(-TimeInterval.hours(24)), shownEnd, withDates: true)
                summaryTitle = title
            case .day:
                // its own day against now: today asked for just before midnight and shown after it is that day (the
                // refresh for the new today comes at once)
                if Calendar.current.isDate(result.domain.start, inSameDayAs: now) {
                    pick = .today
                    title = todayTitle
                    windowSubtitle = Self.timeRange(result.window.start, shownEnd, withDates: false)
                    summaryTitle = NSLocalizedString("Today so far", comment: "Statistics Trace, the summary of Today")
                } else {
                    pick = .day(result.domain.start)
                    title = Self.dayTitle(result.domain.start)
                    windowSubtitle = nil
                    summaryTitle = NSLocalizedString("This day", comment: "Statistics Trace, the summary of the day picked")
                }
            }

            let axis = result.axis
            plot = Plot(
                range: result.range,
                domain: result.domain,
                axis: axis,
                points: result.points,
                low: bands.low,
                high: bands.high,
                dashed: GlucoseStatsEngine.dashedLevels(bands: bands, axis: axis),
                xTicks: result.ticks.map { Plot.Tick(date: $0, label: $0.formatted(date: .omitted, time: .shortened)) }
                    + (
                        result.range == .last24h
                            ? [Plot.Tick(
                                date: result.domain.end,
                                label: NSLocalizedString("now", comment: "Statistics Trace, the end of the last 24 hours")
                            )]
                            : []
                    ),
                endsNow: result.range == .last24h,
                yLabels: GlucoseStatsEngine.labelledLevels(bands: bands, axis: axis)
                    .map { Plot.Level(mgdl: $0, label: Format.glucose($0, units: units)) },
                units: units
            )

            inRangeRange = Format.inRangeLabel(bands: bands, units: units)
            legendBands = bands.visibleBands

            coverage = String(
                format: NSLocalizedString("CGM coverage %@", comment: "Statistics Trace, the CGM coverage percent"),
                empty ? "–" : Format.percent(summary.coveragePercent)
            )
            inRange = empty ? "–" : Format.percent(.inRange, of: summary)
            tirTitle = Format.tirTitle(bands: bands, units: units)
            tir = empty ? "–" : Format.percent(summary.tirPercent)
            titrTitle = Format.titrTitle(bands: bands, units: units)
            titr = empty ? "–" : Format.percent(summary.titrPercent)
            unit = Format.unit(units)
            mean = (empty ? nil : summary.mean).map { Format.glucose($0, units: units) } ?? "–"
            cv = (empty ? nil : summary.cv).map { Format.percent(Int($0.rounded())) } ?? "–"
            minMax = summary.minMax.map { Format.range($0, units: units) } ?? "–"
        }

        /// "29 Oct 14:40", as the locale orders and joins them
        static let dateAndTime = Date.FormatStyle.dateTime.day().month(.abbreviated).hour().minute()

        /// "Mon 27 Oct" (also the Daily view's)
        static func dayTitle(_ day: Date) -> String {
            day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }

        /// "00:00 – 14:35", or with the dates: "29 Oct 14:40 – 30 Oct 14:35"
        private static func timeRange(_ start: Date, _ end: Date, withDates: Bool) -> String {
            func text(_ date: Date) -> String {
                withDates ? date.formatted(Self.dateAndTime) : date.formatted(date: .omitted, time: .shortened)
            }
            return String(
                format: NSLocalizedString("%@ – %@", comment: "Statistics date range, first and last day"),
                text(start),
                text(end)
            )
        }

        private static func minute(_ date: Date) -> Date {
            Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
        }
    }
}

extension Stat {
    /// The Day tab's usual day, formatted for display (`UsualDayResult`): the AGP of the last N days ending today, the
    /// same baseline for every day shown. Its placement on a day's axis is `UsualDayOverlay`.
    struct UsualDay: Equatable, Sendable {
        /// the baseline's bins as computed (the readout shows them, as the AGP's does)
        let bins: [AGPBin?]
        /// enough days with readings to draw it (`GlucoseStatsEngine.usualDayIsDrawn`)
        let isDrawn: Bool
        /// "Usual · last 14 days"
        let label: String
        /// why it is provisional, as the AGP's (`StatsFormatting.profileNote`), marked beside the key; nil when not
        /// drawn or not limited (`GlucoseStatsEngine.agpIsLimited`)
        let profileNote: String?
        /// why it isn't drawn: "Too few days with readings for a usual day: 2 of the last 14."
        let tooFewText: String?

        @MainActor init(_ result: UsualDayResult) {
            let summary = result.summary
            let dayCount = result.period.calendarDayCount ?? 1
            let drawn = GlucoseStatsEngine.usualDayIsDrawn(summary)
            let profileNote = drawn ? StatsFormatting.profileNote(summary) : nil
            bins = result.bins
            isDrawn = drawn

            label = String(
                format: NSLocalizedString(
                    "Usual · last %d days",
                    comment: "Statistics Day tab: the usual day's key, the days of its baseline"
                ),
                dayCount
            )
            self.profileNote = profileNote
            tooFewText = drawn
                ? nil
                : String(
                    format: NSLocalizedString(
                        "Too few days with readings for a usual day: %1$d of the last %2$d.",
                        comment: "Statistics Day tab: the usual day isn't drawn; the days with readings, the days of its baseline"
                    ),
                    summary.daysWithData,
                    dayCount
                )
        }
    }

    /// The usual day placed on a Trace's axes (`GlucoseStatsEngine.usualDayPoints`): built when the trace or the
    /// baseline changes (`StateModel.usualDayOverlay`), never while the selection moves.
    struct UsualDayOverlay: Equatable, Sendable {
        /// what it was placed on (`Trace.Plot`): drawn only on that one (`fits`)
        let domain: DateInterval
        let axis: ClosedRange<Int>
        /// oldest -> newest, mg/dL kept inside the axis
        let points: [UsualDayPoint]
        let usual: UsualDay

        init(_ usual: UsualDay, plot: Trace.Plot, calendar: Calendar = .current) {
            domain = plot.domain
            axis = plot.axis
            self.usual = usual
            points = usual.isDrawn
                ? GlucoseStatsEngine.usualDayPoints(
                    GlucoseStatsEngine.agpPlotPoints(usual.bins, axis: plot.axis),
                    domain: plot.domain,
                    calendar: calendar
                )
                : []
        }

        func fits(_ plot: Trace.Plot) -> Bool {
            domain == plot.domain && axis == plot.axis
        }
    }
}

extension Stat.Trace.Plot {
    /// "14:40"; in the 24 hours a reading before the last day gets the date: "29 Oct 14:40"
    @MainActor func time(of point: Stat.TraceResult.Point) -> String {
        guard endsNow, !Calendar.current.isDate(point.time, inSameDayAs: domain.end.addingTimeInterval(-1)) else {
            return point.time.formatted(date: .omitted, time: .shortened)
        }
        return point.time.formatted(Stat.Trace.dateAndTime)
    }

    @MainActor func value(of point: Stat.TraceResult.Point) -> String {
        StatsFormatting.glucose(point.mgdl, units: units)
    }
}

struct TraceView: View {
    let trace: Stat.Trace
    /// the day selector's items (`Stat.StateModel.traceSelector`): the stepper steps through its days
    let selector: [Stat.TraceSelectorItem]
    /// the day asked for (`traceShownDay`): the stepper follows it at once, before its trace comes in
    let selectedDay: Stat.TraceDay
    let selectDay: (Stat.TraceDay) -> Void
    /// the usual day (`Stat.StateModel`): shown or not and its period (set through `showUsualDay` /
    /// `select(usualDayPeriod:)`), the baseline, and its placement on a trace (drawn only on the trace it was placed on)
    @Binding var usualDayShown: Bool
    @Binding var usualDayPeriod: StatsPeriod
    let usualDay: Stat.UsualDay?
    let usualDayOverlay: Stat.UsualDayOverlay?

    @State private var selection = TraceSelection()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 16) {
            StatsCard { chartCard }
            StatsCard { summaryCard }
        }
        // a new day or range starts at its newest reading (`date(on:)` already ignores the old pick; this drops it)
        .onChange(of: trace.range) { selection.clear() }
    }

    // MARK: - Chart

    @ViewBuilder private var chartCard: some View {
        header

        // drawn while shown, on the trace it was placed on (a new day's trace comes in before its overlay is placed)
        let overlay = usualDayShown ? usualDayOverlay.flatMap { $0.fits(trace.plot) ? $0 : nil } : nil
        TraceChart(
            plot: trace.plot,
            usual: overlay,
            // with the toggle, not the overlay: off at once, before the usual day is in
            shadesRange: !usualDayShown,
            selection: selection
        )

        BandLegend(bands: trace.legendBands)

        UsualDayControls(shown: $usualDayShown, period: $usualDayPeriod, usual: usualDayShown ? usualDay : nil)
    }

    /// A day: the stepper through the selector's days (the 24 hours isn't one of them). The 24 hours: its title and
    /// times. The times only once the trace shown is the one asked for.
    @ViewBuilder private var header: some View {
        let days = selector.filter { $0.pick != .last24h }
        let subtitle = trace.pick == selectedDay ? trace.windowSubtitle : nil
        if selectedDay != .last24h, let index = days.firstIndex(where: { $0.pick == selectedDay }) {
            StatsStepper(title: days[index].title, subtitle: subtitle, index: index, count: days.count) {
                selectDay(days[$0].pick)
            }
        } else {
            StatsCardHeader(verbatim: selector.first { $0.pick == selectedDay }?.title ?? trace.title) {
                if let subtitle {
                    Text(subtitle)
                        .statsFootnote()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - Summary

    private var tiles: [StatsTileItem] {
        [
            StatsTileItem(id: 0, title: StatsFormatting.name(.inRange), value: trace.inRange, note: trace.inRangeRange),
            StatsTileItem(id: 1, title: trace.tirTitle, value: trace.tir),
            StatsTileItem(id: 2, title: trace.titrTitle, value: trace.titr),
            StatsTileItem(
                id: 3,
                title: NSLocalizedString("Mean", comment: "Statistics, mean glucose"),
                value: trace.mean,
                unit: trace.unit
            ),
            StatsTileItem(id: 4, title: NSLocalizedString("CV", comment: ""), value: trace.cv),
            StatsTileItem(
                id: 5,
                title: NSLocalizedString("Min–max", comment: "Statistics Trace, the lowest and highest reading"),
                value: trace.minMax,
                unit: trace.unit
            )
        ]
    }

    @ViewBuilder private var summaryCard: some View {
        StatsCardHeader(verbatim: trace.summaryTitle, detail: trace.coverage)

        // three columns, two at the larger text sizes
        StatsTileGrid(tiles, columns: StatTile.columns(dynamicTypeSize, regular: 3))
    }
}

// MARK: - Usual day

/// The usual day's controls under the chart: the toggle, then (shown) its period and what is drawn: the key ("Usual ·
/// last 14 days", the limited-data mark after it when limited, as the AGP's title has it), or the one line saying why
/// nothing is.
private struct UsualDayControls: View {
    @Binding var shown: Bool
    @Binding var period: StatsPeriod
    /// the baseline loaded, nil until it is (or while not shown)
    let usual: Stat.UsualDay?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $shown) {
                Text("Usual day")
                    .font(.subheadline)
            }

            if shown {
                StatsSegmentedControl(
                    items: StatsPeriod.usualDayPeriods,
                    selection: $period,
                    label: StatsFormatting.label
                )

                if let usual {
                    status(usual)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func status(_ usual: Stat.UsualDay) -> some View {
        if let tooFew = usual.tooFewText {
            Text(tooFew)
                .statsNote()
        } else {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(UsualDayStyle.band(isDark: colorScheme == .dark))
                        .frame(width: 16, height: 10)
                    Rectangle()
                        .fill(UsualDayStyle.median)
                        .frame(width: 16, height: 1.5)
                }
                Text(usual.label)
                    .lineLimit(1)
                if let profileNote = usual.profileNote {
                    LimitedDataMarker(note: profileNote, font: .caption)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            // the marker's 44 pt target reaches past the row: clear of the period control above
            .padding(.top, usual.profileNote == nil ? 0 : 8)
        }
    }
}

// MARK: - Day selector

/// The Day tab's selector, in place of a period control: the last 90 days, oldest -> newest (each with its in-range
/// bar), today, then the 24 hours at the trailing end, set apart (not a calendar day). It opens scrolled to the
/// selected item and keeps it in view. Empty (until its days are in), it keeps its height.
struct TraceDaySelector: View {
    let items: [Stat.TraceSelectorItem]
    let selected: Stat.TraceDay
    let select: (Stat.TraceDay) -> Void

    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 64

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        if item.pick == .last24h {
                            Divider()
                                .frame(height: cellHeight * 0.6)
                                .padding(.horizontal, 2)
                        }
                        cell(item)
                            .id(item.pick)
                    }
                }
                .padding(.horizontal, 16)
            }
            .defaultScrollAnchor(.trailing)
            .onAppear {
                proxy.scrollTo(selected, anchor: .center)
                // again once laid out, should the first one come before the layout (`StatsDayBarsChart` does the same)
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
            // the items come in after the selection, and midnight shifts them by a day
            .onChange(of: items.count) { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: items.first?.pick) { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) {
                withAnimation { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        .frame(height: cellHeight)
    }

    private func cell(_ item: Stat.TraceSelectorItem) -> some View {
        let isSelected = item.pick == selected
        return Button {
            select(item.pick)
        } label: {
            VStack(spacing: 4) {
                if let caption = item.caption {
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color.secondary)
                        .minimumScaleFactor(0.7)
                }
                Text(item.number)
                    .font(.headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                if let fraction = item.inRangeFraction {
                    Capsule()
                        .fill(isSelected ? Color(.systemGray).opacity(0.55) : Color(.systemGray5))
                        .frame(width: 26, height: 4)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(GlucoseBand.inRange.color)
                                .frame(width: 26 * fraction)
                        }
                        .clipShape(Capsule())
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 2)
            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
            .frame(width: cellWidth, height: cellHeight)
            .background(isSelected ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chart

/// The chart with its selection: the marks (`TraceMarks`, equatable) aren't re-rendered when the selection moves.
private struct TraceChart: View {
    let plot: Stat.Trace.Plot
    /// the usual day placed on this plot, nil when not drawn
    let usual: Stat.UsualDayOverlay?
    /// the in-range band shaded (off while the usual day is on)
    let shadesRange: Bool
    let selection: TraceSelection

    @Environment(\.colorScheme) private var colorScheme
    /// the room above the plot for the selected reading's one line, with air for its shadow; the same with the usual
    /// day (the layout doesn't move)
    @ScaledMetric(relativeTo: .title3) private var popoverHeight: CGFloat = 48

    var body: some View {
        let room = popoverHeight
        TraceMarks(
            plot: plot,
            usual: usual,
            shadesRange: shadesRange,
            selection: selection,
            isDark: colorScheme == .dark,
            popoverHeight: room
        )
        .equatable()
        .frame(height: StatsChartMetrics.curvePlotHeight + room)
        .overlay {
            if plot.points.isEmpty {
                Text("No readings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, room)
            }
        }
    }
}

/// The usual day's colours: the AGP's, fainter (it is behind the readings).
private enum UsualDayStyle {
    /// the 25–75% band (the AGP's 5–95% band's opacity)
    static func band(isDark: Bool) -> Color {
        Color(.statsAGP).opacity(StatsChartMetrics.outerBandOpacity(isDark: isDark))
    }

    static var median: Color {
        Color(.statsAGPMedian).opacity(0.5)
    }
}

/// The marks: up to 1440 readings a day (1-minute sensors). Its inputs don't change while the selection moves, so
/// `.equatable()` skips its body; the selection reaches it only through `TraceSelection`, which only
/// `TraceSelectionLayer` reads.
private struct TraceMarks: View, Equatable {
    let plot: Stat.Trace.Plot
    /// the usual day placed on the plot, behind the readings; nil when not drawn
    let usual: Stat.UsualDayOverlay?
    /// the in-range band shaded under everything
    let shadesRange: Bool
    let selection: TraceSelection
    let isDark: Bool
    let popoverHeight: CGFloat

    nonisolated static func == (lhs: TraceMarks, rhs: TraceMarks) -> Bool {
        lhs.selection === rhs.selection && lhs.isDark == rhs.isDark && lhs.popoverHeight == rhs.popoverHeight
            && lhs.shadesRange == rhs.shadesRange && lhs.plot == rhs.plot && lhs.usual == rhs.usual
    }

    var body: some View {
        let plot = self.plot
        let usual = self.usual
        let usualPoints = usual?.points ?? []
        let usualBand = UsualDayStyle.band(isDark: isDark)
        let selection = self.selection
        Chart {
            if shadesRange {
                RectangleMark(
                    xStart: .value("Start", plot.domain.start),
                    xEnd: .value("End", plot.domain.end),
                    yStart: .value("Low", plot.low),
                    yEnd: .value("High", plot.high)
                )
                .foregroundStyle(GlucoseBand.inRange.color.opacity(isDark ? 0.16 : 0.12))
            }

            RuleMark(y: .value("Axis", plot.axis.lowerBound))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color(.systemGray4))

            ForEach(plot.edges, id: \.self) { edge in
                RuleMark(y: .value("Range edge", edge))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color(.systemGray4))
            }

            ForEach(plot.dashed, id: \.self) { level in
                RuleMark(y: .value("Level", level))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }

            // the usual day, behind the readings: its 25–75% band and median, one series per segment (a gap stays a
            // gap); Int like every other y value here
            ForEach(usualPoints.indices, id: \.self) { index in
                AreaMark(
                    x: .value("Time", usualPoints[index].time),
                    yStart: .value("25th percentile", Int(usualPoints[index].p25.rounded())),
                    yEnd: .value("75th percentile", Int(usualPoints[index].p75.rounded())),
                    series: .value("Segment", "usual \(usualPoints[index].segment)")
                )
                .foregroundStyle(usualBand)
            }

            ForEach(usualPoints.indices, id: \.self) { index in
                LineMark(
                    x: .value("Time", usualPoints[index].time),
                    y: .value("Median", Int(usualPoints[index].p50.rounded())),
                    series: .value("Segment", "usual median \(usualPoints[index].segment)")
                )
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(UsualDayStyle.median)
            }

            ForEach(plot.points, id: \.time) { point in
                PointMark(x: .value("Time", point.time), y: .value("Glucose", point.plotted))
                    .symbolSize(14)
                    .foregroundStyle(point.band.color)
            }
        }
        .chartXScale(domain: plot.domain.start ... plot.domain.end)
        .chartYScale(domain: plot.axis.lowerBound ... plot.axis.upperBound)
        .chartXAxis {
            AxisMarks(values: plot.xTicks.map(\.date)) { value in
                let date = value.as(Date.self)
                AxisValueLabel(anchor: Self.anchor(of: date, index: value.index, count: value.count, plot: plot)) {
                    Text(date.flatMap { date in plot.xTicks.first { $0.date == date }?.label } ?? "")
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: plot.yLabels.map(\.mgdl)) { value in
                AxisValueLabel {
                    Text(value.as(Int.self).flatMap { mgdl in plot.yLabels.first { $0.mgdl == mgdl }?.label } ?? "")
                }
            }
        }
        .chartLegend(.hidden)
        // the picking: no `chartXSelection` (its gesture takes every drag on the chart, and a vertical one has to reach
        // the scroll view and the sheet's swipe to dismiss); `ChartPicker` writes the date under the finger into the
        // selection, which nothing here reads (it would re-render the marks on every move)
        .chartOverlay { proxy in
            ZStack {
                ChartPicker(proxy: proxy) { (date: Date) in
                    selection.pick(date, on: plot)
                }
                TraceSelectionLayer(
                    plot: plot,
                    selection: selection,
                    proxy: proxy,
                    popoverHeight: popoverHeight
                )
            }
        }
        .padding(.top, popoverHeight)
    }

    /// The first tick at the domain's start (a day's 00:00) starts there: centred, it would run into the y labels.
    /// The 24 h's last one ("now") ends at the domain's end.
    private static func anchor(of date: Date?, index: Int, count: Int, plot: Stat.Trace.Plot) -> UnitPoint {
        if date == plot.domain.start {
            return .topLeading
        }
        return plot.endsNow && index == count - 1 ? .topTrailing : .top
    }
}

/// The selected reading: a rule down to it, its dot, and the reading above the plot.
private struct TraceSelectionLayer: View {
    let plot: Stat.Trace.Plot
    let selection: TraceSelection
    let proxy: ChartProxy
    let popoverHeight: CGFloat

    var body: some View {
        let index = plot.index(near: selection.date(on: plot))
        GeometryReader { geometry in
            if let index, let plotFrame = proxy.plotFrame.map({ geometry[$0] }),
               let x = proxy.position(forX: plot.points[index].time),
               let y = proxy.position(forY: plot.points[index].plotted)
            {
                let point = plot.points[index]
                let center = CGPoint(x: plotFrame.minX + x, y: plotFrame.minY + y)
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: plotFrame.minY - 2))
                    path.addLine(to: CGPoint(x: center.x, y: Swift.max(center.y - 6, plotFrame.minY - 2)))
                }
                .stroke(Color.secondary, lineWidth: 1)

                Circle()
                    .fill(point.band.color)
                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2.5))
                    .frame(width: 12, height: 12)
                    .position(center)

                PopoverPlacement(centerX: center.x, y: -popoverHeight / 2) {
                    popover(point)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// "14:40 · 152 mg/dL", one line as wide as its text; only the time gives way, should the line be wider than the
    /// chart
    private func popover(_ point: Stat.TraceResult.Point) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(plot.time(of: point))
                .statsFootnote()
                .monospacedDigit()
            Text(verbatim: "·")
                .statsFootnote()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(plot.value(of: point))
                    .font(.title3.bold())
                    .monospacedDigit()
                Text(StatsFormatting.unit(plot.units))
                    .statsFootnote()
            }
            .fixedSize()
        }
        .lineLimit(1)
        .statsChartPopover(horizontalPadding: 12)
    }
}

/// The selected reading's popover at its own width (at most the container's), centred on `centerX` and kept inside
/// the container (`StatsPopover.x`), its centre at `y`. Takes the whole proposal.
private struct PopoverPlacement: Layout {
    let centerX: CGFloat
    let y: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let popover = subviews.first else { return }
        let width = Swift.min(popover.sizeThatFits(.unspecified).width, bounds.width)
        popover.place(
            at: CGPoint(x: bounds.minX + StatsPopover.x(center: centerX, width: width, in: bounds.width), y: bounds.minY + y),
            anchor: .center,
            proposal: ProposedViewSize(width: width, height: nil)
        )
    }
}
