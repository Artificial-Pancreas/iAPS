import Charts
import SwiftUI

// MARK: - Day by day

enum StatsDayBars {
    /// A day's slot on the x axis, with its date label and its bar's top.
    struct Day: Equatable, Sendable, Identifiable {
        /// the whole calendar day
        let day: DateInterval
        /// "27"
        let number: String
        /// the weekday's initial ("M"), the month on the 1st ("Nov")
        let caption: String
        /// the stacked total; 0 without a bar
        let top: Double
        /// a dot above its bar (a past day the pump data covers only partly)
        let isMarked: Bool

        var id: Date { day.start }
        /// where its date label (and its dot) sits
        var middle: Date { day.start.addingTimeInterval(day.duration / 2) }
    }

    /// A part of a day's bar, from the bottom, in the chart's units.
    struct Part: Equatable, Sendable, Identifiable {
        struct ID: Hashable, Sendable {
            let day: Date
            let series: Int
        }

        /// the start of the day
        let day: Date
        /// its place in the stack (basal 0, SMB 1, ...)
        let series: Int
        let lower: Double
        let upper: Double
        let style: StatsBarStyle

        var id: ID { ID(day: day, series: series) }
    }

    /// A solid rule across the plot (a nutrient's reference intake or limit).
    struct Rule: Equatable, Sendable {
        let value: Double
        let color: Color
    }

    /// What the chart draws. The marks view compares it to skip its body.
    struct Plot: Equatable, Sendable {
        /// the whole calendar days of the period
        let domain: DateInterval
        /// oldest -> newest, the last one today
        let days: [Day]
        let parts: [Part]
        /// gridlines, from 0 up to the axis's top (`StatsBarAxis.levels`)
        let levels: [Double]
        /// by level: "0 U", "15", ...
        let levelLabels: [String]
        /// the dashed rule; nil without one
        let average: Double?
        /// a solid rule, under the average; nil without one
        let reference: Rule?

        /// the y scale's top, as a multiple of the top gridline: room above it for the dots (1: none, the Days tab's)
        let headroom: Double
        /// every fill opaque (the glucose bands): no card's colour drawn under the bars
        let opaqueFills: Bool

        /// Days and parts from the values of each day: `values[day][series]`, the nonzero ones stacked in order.
        init(
            days: [DateInterval],
            labels: [StatsDayLabel],
            values: [[Double]],
            styles: [StatsBarStyle],
            marked: [Bool],
            levels: [Double],
            levelLabels: [String],
            average: Double?,
            reference: Rule? = nil
        ) {
            var parts: [Part] = []
            for index in days.indices {
                var top = 0.0
                let dayValues = index < values.count ? values[index] : []
                for series in dayValues.indices where dayValues[series] > 0 && series < styles.count {
                    let upper = top + dayValues[series]
                    parts.append(Part(day: days[index].start, series: series, lower: top, upper: upper, style: styles[series]))
                    top = upper
                }
            }
            self.init(
                days: days,
                labels: labels,
                parts: parts,
                marked: marked,
                levels: levels,
                levelLabels: levelLabels,
                average: average,
                reference: reference
            )
        }

        /// Days from their parts, stacked already (the Days tab's bands): a day's top is its highest part's.
        init(
            days: [DateInterval],
            labels: [StatsDayLabel],
            parts: [Part],
            marked: [Bool] = [],
            levels: [Double],
            levelLabels: [String],
            average: Double? = nil,
            reference: Rule? = nil,
            headroom: Double = 1.08,
            opaqueFills: Bool = false
        ) {
            var tops: [Date: Double] = [:]
            for part in parts {
                tops[part.day] = Swift.max(tops[part.day] ?? 0, part.upper)
            }
            self.days = days.indices.map { index in
                let day = days[index]
                let top = tops[day.start] ?? 0
                let label = index < labels.count ? labels[index] : nil
                return Day(
                    day: day,
                    number: label?.number ?? "",
                    caption: label?.caption ?? "",
                    top: top,
                    isMarked: top > 0 && index < marked.count && marked[index]
                )
            }
            domain = DateInterval(
                start: days.first?.start ?? Date.distantPast,
                end: days.last?.end ?? days.first?.start ?? Date.distantPast
            )
            self.parts = parts
            self.levels = levels
            self.levelLabels = levelLabels
            self.average = average
            self.reference = reference
            self.headroom = headroom
            self.opaqueFills = opaqueFills
        }

        var dayIntervals: [DateInterval] { days.map(\.day) }

        /// the top gridline
        var axisTop: Double { levels.last ?? 1 }

        /// the y scale: a little room above the top gridline for the dots (`headroom`)
        var yDomain: ClosedRange<Double> { 0 ... axisTop * headroom }

        /// where a day's dot sits: above its bar
        func markHeight(of day: Day) -> Double {
            day.top + axisTop * 0.05
        }

        /// The days shown at once (the chart scrolls through the rest): `GlucoseStatsEngine.dailyVisibleDays`, fewer
        /// at the larger text sizes (the two-line date labels must not collide), the whole period when it fits.
        func visibleDays(largeText: Bool) -> Int {
            let days = largeText ? GlucoseStatsEngine.dailyVisibleDaysLargeText : GlucoseStatsEngine.dailyVisibleDays
            return Swift.min(days, Swift.max(self.days.count, 1))
        }

        /// The length of the visible part of the x axis: `days` × 24 h, or the whole period when it fits. In a week
        /// with a DST change that is an hour more or less than those calendar days (accepted: the bars sit inside
        /// their days, and the scroll position is read back as the nearest day start, `leadingEdge`).
        func visibleLength(days: Int) -> TimeInterval {
            self.days.count > days ? .days(days) : domain.duration
        }

        /// the day a date (a tap on the chart) falls in
        func index(containing date: Date) -> Int? {
            GlucoseStatsEngine.dayIndex(containing: date, in: dayIntervals)
        }

        /// The chart's scroll position (the start of the first day shown) that shows the selected day: from
        /// `position` as little scrolling as needed, without it the selected day at the trailing end. The position
        /// is read as the nearest day start, not the day it falls in: the chart can write back a moment before a
        /// midnight (and a `days` × 24 h window ends an hour off a midnight in a DST week), which would otherwise
        /// count the day before as the first one shown and scroll a day back.
        func leadingEdge(showing selected: Int, from position: Date?, visibleDays: Int) -> Date {
            guard days.isNotEmpty else { return domain.start }
            let leading = position.flatMap { position in
                GlucoseStatsEngine.nearestIndex(to: position, in: days) { $0.day.start }
            }
            let first = GlucoseStatsEngine.dailyLeadingDay(
                showing: selected,
                from: leading,
                dayCount: days.count,
                visibleDays: visibleDays
            )
            return days[first].day.start
        }
    }
}

/// The day-by-day chart with its scroll position (the Days tab's, the Insulin and Meals tabs'). A tap picks a day; every drag is left to the scrolling (and a vertical one to the page). Scrolling by the finger doesn't re-render
/// the marks (`StatsDayBarsMarks`, equatable); a pick does (the highlight and the bold date are marks of the chart, so
/// they scroll with it).
struct StatsDayBarsChart: View {
    let plot: StatsDayBars.Plot
    /// the index of the selected day
    let selected: Int
    let selection: DailySelection

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// the room under the plot for the date labels (two lines)
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 34
    /// the start of the first day shown
    @State private var scrollPosition: Date
    /// bumped when the chart is scrolled from here (a new period, a day picked out of view)
    @State private var scrollRequest = 0

    init(
        plot: StatsDayBars.Plot,
        selected: Int,
        selection: DailySelection
    ) {
        self.plot = plot
        self.selected = selected
        self.selection = selection
        // opens with the selected day at the trailing end (today: the newest days); the larger text sizes aren't known
        // here, so this shows 12 days' worth: `onAppear` sets it again with the days shown
        _scrollPosition = State(
            initialValue: plot.leadingEdge(showing: selected, from: nil, visibleDays: plot.visibleDays(largeText: false))
        )
    }

    private var visibleDays: Int {
        plot.visibleDays(largeText: dynamicTypeSize > .large)
    }

    var body: some View {
        StatsDayBarsMarks(
            plot: plot,
            selected: selected,
            visibleDays: visibleDays,
            isDark: colorScheme == .dark,
            scrollPosition: $scrollPosition,
            scrollRequest: scrollRequest,
            selection: selection
        )
        .equatable()
        .frame(height: StatsChartMetrics.barPlotHeight + labelHeight)
        // Belt and braces: should the binding's first value not be honoured on the first layout, it is set again once
        // the chart is laid out (the marks' body is made again, so the chart reads it). Also the days shown at the
        // larger text sizes.
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                scrollPosition = plot.leadingEdge(showing: selected, from: nil, visibleDays: visibleDays)
                scrollRequest += 1
            }
        }
        // a new period (midnight, a settings change): the selected day at the trailing end again
        .onChange(of: plot.domain) {
            scroll(to: plot.leadingEdge(showing: selected, from: nil, visibleDays: visibleDays), animated: false)
        }
        // a day picked out of view (the stepper), or fewer days shown (larger text): scrolled into it
        .onChange(of: selected) {
            scroll(to: plot.leadingEdge(showing: selected, from: scrollPosition, visibleDays: visibleDays), animated: true)
        }
        .onChange(of: visibleDays) {
            scroll(to: plot.leadingEdge(showing: selected, from: scrollPosition, visibleDays: visibleDays), animated: false)
        }
    }

    /// The position and the request in one transaction (one animation).
    private func scroll(to position: Date, animated: Bool) {
        guard position != scrollPosition else { return }
        if animated {
            withAnimation {
                scrollPosition = position
                scrollRequest += 1
            }
        } else {
            scrollPosition = position
            scrollRequest += 1
        }
    }
}

/// The marks: a stacked bar per day, the dashed average (over the solid reference), a dot above a partial day and the
/// selected day's highlight.
/// Its inputs don't change while the chart scrolls, so `.equatable()` skips its body then; the scroll position reaches
/// it through the binding, and a scroll from code (`scrollRequest`) makes the body again so the chart reads it.
private struct StatsDayBarsMarks: View, Equatable {
    let plot: StatsDayBars.Plot
    let selected: Int
    let visibleDays: Int
    let isDark: Bool
    @Binding var scrollPosition: Date
    let scrollRequest: Int
    let selection: DailySelection

    nonisolated static func == (lhs: StatsDayBarsMarks, rhs: StatsDayBarsMarks) -> Bool {
        lhs.selection === rhs.selection && lhs.selected == rhs.selected && lhs.visibleDays == rhs.visibleDays
            && lhs.isDark == rhs.isDark && lhs.scrollRequest == rhs.scrollRequest && lhs.plot == rhs.plot
    }

    /// the bar's width in its day
    private static let barWidth = StatsChartMetrics.barWidthRatio
    /// an outlined part's fill, inside its outline
    private static let innerWidth: CGFloat = 0.54

    var body: some View {
        let plot = self.plot
        let selection = self.selection
        let selected = self.selected
        let highlight: DateInterval? = plot.days.indices.contains(selected) ? plot.days[selected].day : nil
        let inset = StatsChartMetrics.highlightInset
        let barWidth = Self.barWidth
        // about 1 pt of the plot's height
        let outline = plot.axisTop * 0.006
        let bars = plot.days.filter { $0.top > 0 }
        let marked = plot.days.filter(\.isMarked)
        Chart {
            if let highlight {
                RectangleMark(
                    xStart: .value("Start", highlight.start.addingTimeInterval(highlight.duration * inset)),
                    xEnd: .value("End", highlight.end.addingTimeInterval(-highlight.duration * inset)),
                    yStart: .value("Bottom", 0.0),
                    yEnd: .value("Top", plot.yDomain.upperBound)
                )
                .foregroundStyle(StatsChartMetrics.highlight(isDark: isDark))
                .cornerRadius(StatsChartMetrics.highlightCornerRadius)
            }

            // the card's colour under every bar: a translucent fill (the basal) isn't crossed by the gridlines
            if !plot.opaqueFills {
                ForEach(bars) { day in
                    BarMark(
                        x: .value("Day", day.day.start, unit: .day),
                        yStart: .value("From", 0.0),
                        yEnd: .value("To", day.top),
                        width: .ratio(barWidth)
                    )
                    .foregroundStyle(Color(.secondarySystemGroupedBackground))
                }
            }

            ForEach(plot.parts) { part in
                if let stroke = part.style.stroke {
                    Self.outlinedBar(part, stroke: stroke, outline: outline)
                } else {
                    Self.bar(part, width: barWidth)
                        .foregroundStyle(part.style.fill)
                }
            }

            ForEach(marked) { day in
                PointMark(x: .value("Day", day.middle), y: .value("Mark", plot.markHeight(of: day)))
                    .symbol(.circle)
                    .symbolSize(18)
                    .foregroundStyle(Color.secondary)
            }

            if let reference = plot.reference {
                RuleMark(y: .value("Reference", reference.value))
                    .foregroundStyle(reference.color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let average = plot.average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartXScale(domain: plot.domain.start ... plot.domain.end)
        .chartYScale(domain: plot.yDomain)
        .chartXAxis {
            AxisMarks(values: plot.days.map(\.middle)) { value in
                AxisValueLabel(anchor: .top) {
                    Self.dateLabel(value.as(Date.self), plot: plot, selected: selected)
                }
            }
        }
        .chartYAxis {
            StatsAxis.levels(plot.levels, labels: plot.levelLabels)
        }
        .chartLegend(.hidden)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: plot.visibleLength(days: visibleDays))
        .chartScrollPosition(x: $scrollPosition)
        // snaps to local midnights; in a zone whose DST change is at midnight that day has no 00:00 to snap to (the
        // scroll then rests at its first hour; the position is read back as the nearest day start)
        .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(hour: 0)))
        // written only: `selectXValue` below converts a tap's location on the chart to its date and writes it here
        .chartXSelection(value: Binding<Date?>(get: { nil }, set: { date in
            if let date, let index = plot.index(containing: date) {
                selection.pick(index, in: plot.dayIntervals)
            }
        }))
        // a tap selects; replacing the selection's default gesture leaves every drag to the scrolling
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { value in
                    proxy.selectXValue(at: value.location.x)
                }
        }
    }

    /// A part's bar in its day, `yInset` (in the chart's units) inside its bottom and top.
    private static func bar(_ part: StatsDayBars.Part, yInset: Double = 0, width: CGFloat) -> BarMark {
        BarMark(
            x: .value("Day", part.day, unit: .day),
            yStart: .value("From", part.lower + yInset),
            yEnd: .value("To", part.upper - yInset),
            width: .ratio(width)
        )
    }

    /// An outlined part (a light fill): the outline's colour across the part, the card's colour and the fill inside
    /// it (none in a part no taller than its outline).
    @ChartContentBuilder private static func outlinedBar(
        _ part: StatsDayBars.Part,
        stroke: Color,
        outline: Double
    ) -> some ChartContent {
        bar(part, width: barWidth)
            .foregroundStyle(stroke)
        if part.upper - part.lower > 2 * outline {
            bar(part, yInset: outline, width: innerWidth)
                .foregroundStyle(Color(.secondarySystemGroupedBackground))
            bar(part, yInset: outline, width: innerWidth)
                .foregroundStyle(part.style.fill)
        }
    }

    /// The day's number over its weekday's initial (the month on the 1st); the selected day's number in bold.
    @ViewBuilder private static func dateLabel(_ date: Date?, plot: StatsDayBars.Plot, selected: Int) -> some View {
        if let index = date.flatMap({ date in plot.days.firstIndex { $0.middle == date } }) {
            let isSelected = index == selected
            VStack(spacing: 1) {
                Text(plot.days[index].number)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .monospacedDigit()
                Text(plot.days[index].caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            .lineLimit(1)
        }
    }
}
