import Charts
import SwiftUI

// MARK: - By hour

enum StatsHourBars {
    static let hourCount = 24
    /// the x axis: hour `h` of the day is `h ..< h + 1`
    static let domain = 0.0 ... Double(hourCount)

    /// The hour a point of the x axis (a tap, a drag) falls in, kept inside the day.
    static func hour(at x: Double) -> Int {
        guard x.isFinite else { return 0 }
        return Int(Swift.min(Swift.max(x, 0), Double(hourCount - 1)).rounded(.down))
    }

    /// A part of an hour's bar, in the chart's units: stacked from the bottom, or from a baseline up or down (the
    /// basal vs scheduled chart's 100%).
    struct Part: Equatable, Sendable, Identifiable {
        struct ID: Hashable, Sendable {
            let hour: Int
            let series: Int
        }

        let hour: Int
        let series: Int
        let lower: Double
        let upper: Double
        let style: StatsBarStyle

        var id: ID { ID(hour: hour, series: series) }
    }

    /// A label of the x axis: the local 00/06/12/18, at the start of their hour (as the AGP's).
    struct Tick: Equatable, Sendable {
        let hour: Int
        let label: String
    }

    /// A point of the step line (the scheduled basal): an hour's level from its start to its end.
    struct StepPoint: Equatable, Sendable, Identifiable {
        struct ID: Hashable, Sendable {
            let hour: Int
            let end: Bool
        }

        let x: Double
        let y: Double
        /// the run of consecutive hours with a level it belongs to (a line each)
        let run: Int
        let id: ID
    }

    /// The usual of an hour (Insulin's Today: the insulin, the negative IOB): a tick across its slot at its level.
    struct UsualTick: Equatable, Sendable, Identifiable {
        let hour: Int
        let level: Double

        var id: Int { hour }
    }

    /// What the chart draws. The marks view compares it to skip its body, so it holds no selection.
    struct Plot: Equatable, Sendable {
        let parts: [Part]
        /// the step line (the scheduled basal)
        let steps: [StepPoint]
        /// the usual by hour (Insulin's Today), a tick in each hour with one; no line between them
        let usual: [UsualTick]
        let yDomain: ClosedRange<Double>
        let levels: [Double]
        let levelLabels: [String]
        /// a solid rule across (the 100% of basal vs scheduled); nil without one
        let baseline: Double?
        /// every fill opaque (By hour's glucose bands): no card's colour drawn under the parts
        let opaqueFills: Bool
        /// the local 00/06/12/18
        let xTicks: [Tick]

        init(
            parts: [Part],
            steps: [Double?] = [],
            usual: [Double?] = [],
            yDomain: ClosedRange<Double>,
            levels: [Double],
            levelLabels: [String],
            baseline: Double? = nil,
            opaqueFills: Bool = false
        ) {
            self.parts = parts
            self.steps = Self.stepPoints(steps)
            self.usual = usual.indices.compactMap { hour in usual[hour].map { UsualTick(hour: hour, level: $0) } }
            self.yDomain = yDomain
            self.levels = levels
            self.levelLabels = levelLabels
            self.baseline = baseline
            self.opaqueFills = opaqueFills
            xTicks = stride(from: 0, to: StatsHourBars.hourCount, by: 6)
                .map { Tick(hour: $0, label: Stat.AGP.clockTime($0 * 60)) }
        }

        /// Stacked parts from the values of each hour: `values[hour][series]`, the nonzero ones in order.
        static func stacked(_ values: [[Double]], styles: [StatsBarStyle]) -> [Part] {
            values.indices.flatMap { hour -> [Part] in
                var top = 0.0
                return values[hour].indices.compactMap { series -> Part? in
                    guard values[hour][series] > 0, series < styles.count else { return nil }
                    let lower = top
                    top += values[hour][series]
                    return Part(hour: hour, series: series, lower: lower, upper: top, style: styles[series])
                }
            }
        }

        /// The step line's points: each hour with a level from its start to its end, consecutive hours one run.
        static func stepPoints(_ levels: [Double?]) -> [StepPoint] {
            var points: [StepPoint] = []
            var run = 0
            var previous: Double?
            for hour in levels.indices {
                guard let level = levels[hour] else {
                    if previous != nil {
                        run += 1
                    }
                    previous = nil
                    continue
                }
                points.append(StepPoint(x: Double(hour), y: level, run: run, id: .init(hour: hour, end: false)))
                points.append(StepPoint(x: Double(hour + 1), y: level, run: run, id: .init(hour: hour, end: true)))
                previous = level
            }
            return points
        }
    }
}

/// The by-hour chart with its selection: the marks (equatable) aren't re-rendered when the selection moves.
/// Without a selection (the Negative IOB card's): no picking.
struct StatsHourBarsChart: View {
    let plot: StatsHourBars.Plot
    var selection: HourSelection?
    var plotHeight = StatsChartMetrics.barPlotHeight

    /// the room under the plot for the time labels
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 20

    var body: some View {
        StatsHourBarsMarks(plot: plot, selection: selection)
            .equatable()
            .frame(height: plotHeight + labelHeight)
    }
}

/// The marks: a bar per hour, a step line or the usual's ticks, a baseline. Its inputs don't change while the selection
/// moves, so `.equatable()` skips its body; the selection reaches it only through `HourSelection`, which only
/// `StatsHourSelectionLayer` reads.
private struct StatsHourBarsMarks: View, Equatable {
    let plot: StatsHourBars.Plot
    let selection: HourSelection?

    nonisolated static func == (lhs: StatsHourBarsMarks, rhs: StatsHourBarsMarks) -> Bool {
        lhs.selection === rhs.selection && lhs.plot == rhs.plot
    }

    /// a bar's inset from its hour's edges, of the hour
    private static let inset = 0.16
    /// an outline's width, of the hour (about 1 pt of a 12 pt slot)
    private static let outlineWidth = 0.08
    /// a usual's tick's inset from its hour's edges, of the hour: a touch wider than the bar
    private static let usualInset = 0.1
    /// opaque fills (By hour's glucose bands, full height): how far the highlight reaches above the plot, a cap over
    /// the selected column
    private static let overhang: CGFloat = 6

    var body: some View {
        let plot = self.plot
        let selection = self.selection
        // about 1 pt of the plot's height
        let outlineHeight = (plot.yDomain.upperBound - plot.yDomain.lowerBound) * 0.0045
        Chart {
            if let baseline = plot.baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Color(.systemGray4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            // the card's colour under every part, as the day chart's: a translucent fill isn't crossed by the gridlines
            if !plot.opaqueFills {
                ForEach(plot.parts) { part in
                    Self.rectangle(part)
                        .foregroundStyle(Color(.secondarySystemGroupedBackground))
                }
            }

            ForEach(plot.parts) { part in
                if let stroke = part.style.stroke {
                    Self.outlinedRectangle(part, stroke: stroke, outlineHeight: outlineHeight)
                } else {
                    Self.rectangle(part)
                        .foregroundStyle(part.style.fill)
                }
            }

            ForEach(plot.steps) { point in
                LineMark(
                    x: .value("Hour", point.x),
                    y: .value("Level", point.y),
                    series: .value("Run", point.run)
                )
                .foregroundStyle(Color.primary)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
            }

            // over the bars: a tick inside a taller bar still shows
            ForEach(plot.usual) { tick in
                RuleMark(
                    xStart: .value("Start", Double(tick.hour) + Self.usualInset),
                    xEnd: .value("End", Double(tick.hour + 1) - Self.usualInset),
                    y: .value("Usual", tick.level)
                )
                .foregroundStyle(StatsChartMetrics.usualTick)
                .lineStyle(StrokeStyle(lineWidth: StatsChartMetrics.usualTickThickness))
            }
        }
        .chartXScale(domain: StatsHourBars.domain)
        .chartYScale(domain: plot.yDomain)
        .chartXAxis {
            StatsAxis.hours(plot.xTicks)
        }
        .chartYAxis {
            StatsAxis.levels(plot.levels, labels: plot.levelLabels)
        }
        .chartLegend(.hidden)
        // the selected hour's highlight, behind the marks
        .chartBackground { proxy in
            if let selection {
                StatsHourSelectionLayer(
                    selection: selection,
                    proxy: proxy,
                    overhang: plot.opaqueFills ? Self.overhang : 0,
                    isStrong: plot.opaqueFills
                )
            }
        }
        // the picking: no `chartXSelection` (its gesture takes every drag on the chart, and a vertical one has to reach
        // the scroll view and the sheet's swipe to dismiss); `ChartPicker` writes the x under the finger into the
        // selection, which nothing here reads (it would re-render the marks on every move)
        .chartOverlay { proxy in
            if let selection {
                ChartPicker(proxy: proxy) { (x: Double) in
                    selection.select(x: x)
                }
            }
        }
        // opaque fills: the room above the plot for the highlight's cap (its bottom stays at the plot's, clear of the
        // time labels)
        .padding(.top, plot.opaqueFills ? Self.overhang : 0)
    }

    /// A part's rectangle in its hour (`inset` inside the hour's edges), and `outlineX` (of the hour) and `outlineY` (in
    /// the chart's units) inside its own edges: the fill inside an outline.
    private static func rectangle(_ part: StatsHourBars.Part, outlineX: Double = 0, outlineY: Double = 0) -> RectangleMark {
        RectangleMark(
            xStart: .value("Start", Double(part.hour) + inset + outlineX),
            xEnd: .value("End", Double(part.hour + 1) - inset - outlineX),
            yStart: .value("From", part.lower + outlineY),
            yEnd: .value("To", part.upper - outlineY)
        )
    }

    /// An outlined part (a light fill): the outline's colour across the part, the card's colour and the fill inside
    /// it (none in a part no taller than its outline, `outlineHeight` in the chart's units).
    @ChartContentBuilder private static func outlinedRectangle(
        _ part: StatsHourBars.Part,
        stroke: Color,
        outlineHeight: Double
    ) -> some ChartContent {
        rectangle(part)
            .foregroundStyle(stroke)
        if part.upper - part.lower > 2 * outlineHeight {
            rectangle(part, outlineX: outlineWidth, outlineY: outlineHeight)
                .foregroundStyle(Color(.secondarySystemGroupedBackground))
            rectangle(part, outlineX: outlineWidth, outlineY: outlineHeight)
                .foregroundStyle(part.style.fill)
        }
    }
}

/// The selected hour: a soft fill across its slot (so also behind an hour without data), from the plot's bottom to its
/// top, as the day chart's highlight; behind opaque fills a stronger one, reaching `overhang` above the plot.
private struct StatsHourSelectionLayer: View {
    let selection: HourSelection
    let proxy: ChartProxy
    /// how far the fill reaches above the plot
    let overhang: CGFloat
    /// the stronger fill (behind opaque fills)
    let isStrong: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let hour = selection.hour
        let inset = StatsChartMetrics.highlightInset
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame.map({ geometry[$0] }),
               let start = proxy.position(forX: Double(hour) + inset),
               let end = proxy.position(forX: Double(hour + 1) - inset)
            {
                let isDark = colorScheme == .dark
                let fill = isStrong ? StatsChartMetrics.strongHighlight(isDark: isDark) : StatsChartMetrics
                    .highlight(isDark: isDark)
                let height = plotFrame.height + overhang
                // inside its frame: the bottom edge doesn't cross into the time labels
                RoundedRectangle(cornerRadius: StatsChartMetrics.highlightCornerRadius)
                    .fill(fill)
                    .frame(width: Swift.max(end - start, 0), height: height)
                    .position(x: plotFrame.minX + (start + end) / 2, y: plotFrame.maxY - height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}
