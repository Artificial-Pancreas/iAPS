import SwiftUI

// Daily charts' print views: a page of panels, each a `Canvas` of a fixed size (the trace, the markers, the basal lane
// and their labels), and the page's legend.

struct ReportChartsContent: View {
    let page: Stat.ReportChartsPage
    /// the content's, points
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let emptyNote = page.emptyNote {
                Text(emptyNote)
                    .font(ReportStyle.font(10))
                    .foregroundStyle(ReportStyle.secondary)
            } else {
                panels
                ReportChartsLegend(items: page.legend)
                    .frame(height: ReportChartMetrics.legendHeight)
            }
            // what couldn't be read, what `*` means: also on a page without panels
            if page.notes.isNotEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(page.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(ReportStyle.font(7))
                            .foregroundStyle(ReportStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: width, height: ReportChartMetrics.noteHeight, alignment: .leading)
                    }
                }
                .padding(.top, -6)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// Row by row, left to right; a page with fewer days leaves the rest empty.
    private var panels: some View {
        let size = page.panelSize
        return VStack(alignment: .leading, spacing: ReportChartMetrics.rowSpacing) {
            ForEach(0 ..< Swift.max(page.rows, 1), id: \.self) { row in
                HStack(alignment: .top, spacing: ReportChartMetrics.columnSpacing) {
                    ForEach(0 ..< Swift.max(page.columns, 1), id: \.self) { column in
                        let index = row * Swift.max(page.columns, 1) + column
                        if index < page.panels.count {
                            ReportChartPanel(panel: page.panels[index], page: page, size: size)
                        } else {
                            Color.clear
                                .frame(width: size.width, height: size.height)
                        }
                    }
                }
            }
        }
    }
}

/// The colour key of a page of Daily charts.
struct ReportChartsLegend: View {
    let items: [Stat.ReportChartsPage.LegendItem]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(items) { item in
                HStack(spacing: 3) {
                    key(item.key)
                    Text(item.text)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .font(ReportStyle.font(7))
        .foregroundStyle(ReportStyle.secondary)
    }

    @ViewBuilder private func key(_ key: Stat.ReportChartsPage.LegendKey) -> some View {
        switch key {
        case .glucose:
            Rectangle().fill(ReportStyle.trace).frame(width: 14, height: 1.2)
        case .range:
            Rectangle().fill(ReportStyle.rangeBand).frame(width: 14, height: 7)
        case .bolus:
            Rectangle().fill(ReportStyle.insulin).frame(width: 1.8, height: 9)
        case .smb:
            Rectangle().fill(ReportStyle.insulin).frame(width: 0.7, height: 5)
        case .carbs:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6))
                path.addLine(to: CGPoint(x: 3, y: 0))
                path.addLine(to: CGPoint(x: 6, y: 6))
                path.closeSubpath()
            }
            .fill(ReportStyle.carbs)
            .frame(width: 6, height: 6)
        case .basal:
            Rectangle().fill(ReportStyle.basalFill).frame(width: 14, height: 7)
        case .scheduled:
            Rectangle().fill(ReportStyle.text).frame(width: 14, height: 0.8)
        }
    }
}

/// A day: its header line over its chart.
struct ReportChartPanel: View {
    let panel: Stat.ReportChartsPage.Panel
    let page: Stat.ReportChartsPage
    let size: CGSize

    private static let headerHeight = ReportChartMetrics.headerHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(panel.title)
                    .font(ReportStyle.font(8.5, .semibold))
                    .fixedSize()
                Spacer(minLength: 0)
                Text(panel.stats)
                    .font(ReportStyle.font(7.5))
                    .foregroundStyle(ReportStyle.secondary)
                    .minimumScaleFactor(0.6)
            }
            .lineLimit(1)
            .frame(width: size.width, height: Self.headerHeight, alignment: .topLeading)
            chart(CGSize(width: size.width, height: Swift.max(size.height - Self.headerHeight, 20)))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // the day runs left to right in every language
        .environment(\.layoutDirection, .leftToRight)
    }

    private func chart(_ size: CGSize) -> some View {
        let panel = self.panel
        let page = self.page
        let layout = ReportChartLayout(size: size, page: page)
        return Canvas { context, _ in
            ReportChartDrawing.frame(&context, layout, page, panel)
            // the trace under the marks: their labels stay readable where it runs through them
            ReportChartDrawing.glucose(&context, layout, page, panel)
            ReportChartDrawing.insulin(&context, layout, page, panel)
            ReportChartDrawing.carbs(&context, layout, panel)
            if page.showsBasal {
                ReportChartDrawing.basal(&context, layout, page, panel)
            }
            ReportChartDrawing.labels(&context, layout, page, panel)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Where a panel's chart draws: the glucose plot, the basal lane under it, and the labels' room.
struct ReportChartLayout {
    /// the y labels' room
    static let leading = ReportChartMetrics.leading
    static let trailing = ReportChartMetrics.trailing
    /// the x labels' room
    static let bottom: CGFloat = 10

    let plot: CGRect
    /// zero height without the basal lane
    let lane: CGRect
    /// the baseline of the x labels' top
    let labelsY: CGFloat
    let axis: ClosedRange<Int>
    let compact: Bool

    init(size: CGSize, page: Stat.ReportChartsPage) {
        let laneHeight: CGFloat = page.showsBasal ? Swift.max(size.height * 0.17, 10) : 0
        let laneGap: CGFloat = page.showsBasal ? 4 : 0
        let width = Swift.max(size.width - Self.leading - Self.trailing, 1)
        let plotHeight = Swift.max(size.height - 2 - Self.bottom - laneHeight - laneGap, 10)
        plot = CGRect(x: Self.leading, y: 2, width: width, height: plotHeight)
        lane = CGRect(x: Self.leading, y: plot.maxY + laneGap, width: width, height: laneHeight)
        labelsY = lane.maxY + 1.5
        axis = page.axis
        compact = page.columns > 1
    }

    func x(_ position: Double) -> CGFloat {
        plot.minX + plot.width * CGFloat(Swift.min(Swift.max(position, 0), 1))
    }

    func y(_ mgdl: Double) -> CGFloat {
        let span = Double(Swift.max(axis.upperBound - axis.lowerBound, 1))
        let fraction = Swift.min(Swift.max((mgdl - Double(axis.lowerBound)) / span, 0), 1)
        return plot.maxY - plot.height * CGFloat(fraction)
    }
}

/// The layers of a panel's chart, bottom to top.
enum ReportChartDrawing {
    typealias Page = Stat.ReportChartsPage
    typealias Panel = Stat.ReportChartsPage.Panel

    private static func line(_ from: CGPoint, _ to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }

    private static func text(_ string: String, size: CGFloat, color: Color = ReportStyle.secondary, bold: Bool = false) -> Text {
        Text(string)
            .font(ReportStyle.font(size, bold ? .semibold : .regular))
            .foregroundColor(color)
    }

    /// A label on white, so the trace, the band and the rules under it don't run through it.
    /// Kept inside `bounds` sideways: a mark at 00:00 or 24:00 has its label next to the plot's edge, not over it.
    private static func label(
        _ context: inout GraphicsContext,
        _ text: Text,
        at position: CGPoint,
        anchor: UnitPoint,
        in bounds: CGRect
    ) {
        let resolved = context.resolve(text)
        let size = resolved.measure(in: CGSize(width: 200, height: 40))
        let lowest = bounds.minX + 1 + size.width * anchor.x
        let highest = bounds.maxX - 1 - size.width * (1 - anchor.x)
        let point = CGPoint(x: Swift.min(Swift.max(position.x, lowest), Swift.max(highest, lowest)), y: position.y)
        let origin = CGPoint(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y)
        context.fill(
            Path(CGRect(origin: origin, size: size).insetBy(dx: -1, dy: 0)),
            with: .color(Color.white.opacity(0.85))
        )
        context.draw(resolved, at: point, anchor: anchor)
    }

    /// The in-range band, the hairlines at 54 and 250, the hours' rules and the plot's frame.
    static func frame(_ context: inout GraphicsContext, _ layout: ReportChartLayout, _ page: Page, _ panel: Panel) {
        let plot = layout.plot
        let top = layout.y(Double(page.high))
        let bottom = layout.y(Double(page.low))
        context.fill(
            Path(CGRect(x: plot.minX, y: top, width: plot.width, height: Swift.max(bottom - top, 0))),
            with: .color(ReportStyle.rangeBand)
        )
        for tick in panel.ticks {
            let x = layout.x(tick.x)
            context.stroke(
                line(CGPoint(x: x, y: plot.minY), CGPoint(x: x, y: plot.maxY)),
                with: .color(ReportStyle.hairline),
                lineWidth: 0.3
            )
        }
        for level in page.hairlines {
            let y = layout.y(Double(level))
            context.stroke(
                line(CGPoint(x: plot.minX, y: y), CGPoint(x: plot.maxX, y: y)),
                with: .color(ReportStyle.rule),
                lineWidth: 0.3
            )
        }
        context.stroke(Path(plot), with: .color(ReportStyle.rule), lineWidth: 0.5)
    }

    /// The SMBs as ticks from the top edge, their height by their units; the other boluses as bars from the top edge
    /// with their units under them.
    static func insulin(_ context: inout GraphicsContext, _ layout: ReportChartLayout, _ page: Page, _ panel: Panel) {
        let plot = layout.plot
        for smb in panel.smbs {
            let share = page.smbMax > 0 ? CGFloat(smb.amount / page.smbMax) : 0
            let x = layout.x(smb.x)
            context.stroke(
                line(CGPoint(x: x, y: plot.minY), CGPoint(x: x, y: plot.minY + 2.5 + 6 * share)),
                with: .color(ReportStyle.insulin),
                lineWidth: 0.6
            )
        }
        let longest = Swift.max(plot.height * 0.22, 10)
        for bolus in panel.boluses {
            let share = page.bolusMax > 0 ? CGFloat(bolus.amount / page.bolusMax) : 0
            let x = layout.x(bolus.x)
            let end = plot.minY + 7 + (longest - 7) * share
            context.stroke(
                line(CGPoint(x: x, y: plot.minY), CGPoint(x: x, y: end)),
                with: .color(ReportStyle.insulin),
                lineWidth: 1.8
            )
            if let label = bolus.label {
                Self.label(
                    &context,
                    text(
                        label,
                        size: layout.compact ? ReportChartMetrics.compactBolusLabelSize : ReportChartMetrics.labelSize,
                        color: ReportStyle.text
                    ),
                    at: CGPoint(x: x, y: end + 1),
                    anchor: .top,
                    in: plot
                )
            }
        }
    }

    /// The carbs as triangles on the bottom edge, with their grams over them.
    static func carbs(_ context: inout GraphicsContext, _ layout: ReportChartLayout, _ panel: Panel) {
        let plot = layout.plot
        let half: CGFloat = layout.compact ? 2 : 2.6
        for entry in panel.carbs {
            let x = layout.x(entry.x)
            var marker = Path()
            marker.move(to: CGPoint(x: x - half, y: plot.maxY))
            marker.addLine(to: CGPoint(x: x, y: plot.maxY - half * 2))
            marker.addLine(to: CGPoint(x: x + half, y: plot.maxY))
            marker.closeSubpath()
            context.fill(marker, with: .color(ReportStyle.carbs))
            if let label = entry.label {
                Self.label(
                    &context,
                    text(label, size: ReportChartMetrics.labelSize, color: ReportStyle.text),
                    at: CGPoint(x: x, y: plot.maxY - half * 2 - 1),
                    anchor: .bottom,
                    in: plot
                )
            }
        }
    }

    /// The trace: a line per stretch of readings, a dot for a reading on its own.
    static func glucose(_ context: inout GraphicsContext, _ layout: ReportChartLayout, _: Page, _ panel: Panel) {
        let width: CGFloat = layout.compact ? 0.8 : 1.1
        for stretch in panel.lines {
            guard let first = stretch.first else { continue }
            let start = CGPoint(x: layout.x(first.x), y: layout.y(first.mgdl))
            guard stretch.count > 1 else {
                context.fill(
                    Path(ellipseIn: CGRect(x: start.x - width, y: start.y - width, width: width * 2, height: width * 2)),
                    with: .color(ReportStyle.trace)
                )
                continue
            }
            var path = Path()
            path.move(to: start)
            for sample in stretch.dropFirst() {
                path.addLine(to: CGPoint(x: layout.x(sample.x), y: layout.y(sample.mgdl)))
            }
            context.stroke(
                path,
                with: .color(ReportStyle.trace),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// The basal lane: the delivered basal as a filled step area, the scheduled one as a line, on the page's scale.
    static func basal(_ context: inout GraphicsContext, _ layout: ReportChartLayout, _ page: Page, _ panel: Panel) {
        let lane = layout.lane
        guard lane.height > 0, page.basalMax > 0 else { return }
        func y(_ rate: Double) -> CGFloat {
            lane.maxY - lane.height * CGFloat(Swift.min(Swift.max(rate / page.basalMax, 0), 1))
        }
        for step in panel.basal where step.rate > 0 {
            let from = layout.x(step.from)
            let top = y(step.rate)
            context.fill(
                Path(CGRect(x: from, y: top, width: Swift.max(layout.x(step.to) - from, 0), height: lane.maxY - top)),
                with: .color(ReportStyle.basalFill)
            )
        }
        var scheduled = Path()
        var last: CGPoint?
        for step in panel.basal {
            guard let rate = step.scheduled else {
                last = nil
                continue
            }
            let start = CGPoint(x: layout.x(step.from), y: y(rate))
            let end = CGPoint(x: layout.x(step.to), y: y(rate))
            // joined to the step before it when they touch; a gap in the pump data starts anew
            if let last, abs(last.x - start.x) < 0.01 {
                scheduled.addLine(to: start)
            } else {
                scheduled.move(to: start)
            }
            scheduled.addLine(to: end)
            last = end
        }
        context.stroke(scheduled, with: .color(ReportStyle.text), lineWidth: 0.7)
        context.stroke(
            line(CGPoint(x: lane.minX, y: lane.maxY), CGPoint(x: lane.maxX, y: lane.maxY)),
            with: .color(ReportStyle.rule),
            lineWidth: 0.4
        )
    }

    /// The glucose levels on the leading side, the hours under the chart.
    static func labels(_ context: inout GraphicsContext, _ layout: ReportChartLayout, _ page: Page, _ panel: Panel) {
        for level in page.levels {
            context.draw(
                text(level.label, size: 6.5),
                at: CGPoint(x: layout.plot.minX - 3, y: layout.y(Double(level.mgdl))),
                anchor: .trailing
            )
        }
        for tick in panel.ticks {
            context.draw(text(tick.label, size: 6.5), at: CGPoint(x: layout.x(tick.x), y: layout.labelsY), anchor: .top)
        }
        if page.showsBasal, layout.lane.height > 0 {
            // the basal lane's scale: its top, U/h
            context.draw(
                text(page.basalMaxLabel, size: 6),
                at: CGPoint(x: layout.lane.minX - 3, y: layout.lane.minY + 3),
                anchor: .trailing
            )
            context.draw(
                text("0", size: 6),
                at: CGPoint(x: layout.lane.minX - 3, y: layout.lane.maxY - 2),
                anchor: .trailing
            )
        }
        if let note = panel.note {
            context.draw(
                text(note, size: layout.compact ? 7 : 8),
                at: CGPoint(x: layout.plot.midX, y: layout.y(Double(page.low + page.high) / 2)),
                anchor: .center
            )
        }
    }
}
