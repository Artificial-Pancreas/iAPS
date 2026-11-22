import SwiftUI
import UIKit

// Print-only views: fixed sizes, opaque colours, no scroll or lazy containers, nothing UIKit-backed. Rendered into a
// PDF page by `ReportPDFWriter`, never shown on screen.

enum ReportStyle {
    /// the page's margins
    static let margin: CGFloat = 40
    static let text = Color.black
    static let secondary = Color(white: 0.33)
    static let rule = Color(white: 0.5)
    static let hairline = Color(white: 0.78)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// the 5–95% band, the AGP's colour blended over the white page (opaque)
    static var outerBand: Color { blended(.statsAGP, opacity: 0.2) }
    /// the 25–75% band
    static var innerBand: Color { blended(.statsAGP, opacity: 0.45) }
    static var median: Color { Color(.statsAGPMedian) }

    /// A colour at an opacity over white, as one opaque colour (its light appearance).
    static func blended(_ resource: ColorResource, opacity: CGFloat) -> Color {
        let color = UIColor(resource: resource).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return Color(resource).opacity(opacity)
        }
        func over(_ component: CGFloat) -> Double {
            Double(1 - (1 - component) * opacity)
        }
        return Color(red: over(red), green: over(green), blue: over(blue))
    }
}

/// A page of a report: the header, the part's content, the footer, on white.
struct ReportPageView: View {
    let content: Stat.ReportPageContent
    let chrome: Stat.ReportPageChrome
    /// the page's, points
    let size: CGSize

    var body: some View {
        let width = size.width - ReportStyle.margin * 2
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch content {
                case let .summary(summary):
                    ReportSummaryContent(summary: summary, width: width, pageHeight: size.height)
                case let .percentile(percentile):
                    ReportPercentileContent(percentile: percentile, width: width, pageHeight: size.height)
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: width, height: size.height - ReportStyle.margin * 2, alignment: .topLeading)
        .padding(ReportStyle.margin)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ReportStyle.text)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(chrome.title)
                    .font(ReportStyle.font(22, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(chrome.dateRange)
                        .font(ReportStyle.font(11, .semibold))
                    Text(chrome.days)
                        .font(ReportStyle.font(8.5))
                        .foregroundStyle(ReportStyle.secondary)
                }
                .lineLimit(1)
                .fixedSize()
            }
            Rectangle()
                .fill(ReportStyle.text)
                .frame(height: 1)
            Text(chrome.ranges)
                .font(ReportStyle.font(7.5))
                .foregroundStyle(ReportStyle.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(ReportStyle.hairline)
                .frame(height: 0.5)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chrome.provenance)
                Spacer(minLength: 0)
                Text(chrome.pageNumber)
            }
            .font(ReportStyle.font(7.5))
            .foregroundStyle(ReportStyle.secondary)
            .lineLimit(1)
        }
    }
}

/// A section of a page: its title over a rule, then its content.
private struct ReportSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ReportStyle.font(11, .bold))
                Rectangle()
                    .fill(ReportStyle.rule)
                    .frame(height: 0.5)
            }
            content
        }
    }
}

/// Whether a goal is met: a check or a cross (drawn, not a glyph) with the words.
private struct ReportMetMark: View {
    let isMet: Bool

    var body: some View {
        HStack(spacing: 3) {
            Path { path in
                if isMet {
                    path.move(to: CGPoint(x: 0.5, y: 4))
                    path.addLine(to: CGPoint(x: 2.8, y: 6.5))
                    path.addLine(to: CGPoint(x: 6.5, y: 0.8))
                } else {
                    path.move(to: CGPoint(x: 1, y: 1))
                    path.addLine(to: CGPoint(x: 6, y: 6))
                    path.move(to: CGPoint(x: 6, y: 1))
                    path.addLine(to: CGPoint(x: 1, y: 6))
                }
            }
            .stroke(ReportStyle.text, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            .frame(width: 7, height: 7)
            Text(
                isMet
                    ? NSLocalizedString("met", comment: "PDF report: a consensus goal is met")
                    : NSLocalizedString("not met", comment: "PDF report: a consensus goal isn't met")
            )
            .font(ReportStyle.font(8, isMet ? .regular : .semibold))
            .fixedSize()
        }
    }
}

/// A goal beside a number, two cells of fixed widths: its text (it shrinks rather than run into the mark), then its
/// mark; empty without one.
private struct ReportGoalCells: View {
    let goal: Stat.ReportGoalMark?
    let textWidth: CGFloat

    static let markWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 6) {
            if let goal {
                Text(goal.text)
                    .font(ReportStyle.font(8))
                    .foregroundStyle(ReportStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: textWidth, alignment: .leading)
                ReportMetMark(isMet: goal.isMet)
                    .frame(width: Self.markWidth, alignment: .leading)
            } else {
                Color.clear
                    .frame(width: textWidth + 6 + Self.markWidth, height: 1)
            }
        }
    }
}

// MARK: - Summary

struct ReportSummaryContent: View {
    let summary: Stat.ReportSummary
    /// the content's, points
    let width: CGFloat
    /// the page's: a taller paper than US Letter gives its extra height to the chart
    let pageHeight: CGFloat

    private static let rowHeight: CGFloat = 21
    private static let headerHeight: CGFloat = 12
    private static let barWidth: CGFloat = 30
    /// on the shortest paper (US Letter)
    private static let chartHeight: CGFloat = 150

    private var chartHeight: CGFloat {
        Self.chartHeight + Swift.max(pageHeight - ReportPaper.letter.size.height, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            identity
            ReportSection(title: NSLocalizedString("Time in ranges", comment: "")) {
                HStack(alignment: .top, spacing: 14) {
                    bar
                        .padding(.top, Self.headerHeight)
                    ranges
                }
            }
            ReportSection(title: NSLocalizedString("Glucose", comment: "Statistics topic")) {
                metrics
                if let limitedNote = summary.limitedNote {
                    Text(limitedNote)
                        .font(ReportStyle.font(8))
                        .foregroundStyle(ReportStyle.secondary)
                }
            }
            ReportSection(title: NSLocalizedString("Percentile profile", comment: "PDF report part")) {
                ReportPercentileChart(plot: summary.plot, size: CGSize(width: width, height: chartHeight))
                ReportPercentileLegendView(legend: summary.legend)
            }
            if let insulinAndCarbs = summary.insulinAndCarbs {
                ReportSection(
                    title: NSLocalizedString(
                        "Insulin and carbs per day",
                        comment: "PDF report: the Summary's block, and its setting"
                    )
                ) {
                    amounts(insulinAndCarbs)
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// Filled in by hand: no name is stored.
    private var identity: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(NSLocalizedString("Name", comment: ""))
            blank(width: 210)
            Text(NSLocalizedString("Date of birth", comment: "PDF report: a blank to fill in by hand"))
                .padding(.leading, 14)
            blank(width: 120)
        }
        .font(ReportStyle.font(9.5))
        .padding(.top, 6)
    }

    private func blank(width: CGFloat) -> some View {
        Rectangle()
            .fill(ReportStyle.rule)
            .frame(width: width, height: 0.5)
    }

    /// The bands stacked, very high at the top: a bar as tall as the rows beside it.
    private var bar: some View {
        let height = Self.rowHeight * CGFloat(Swift.max(summary.rows.count, 1))
        let heights = StatsSplitBar.widths(summary.segments.map(\.fraction), total: height)
        return VStack(spacing: StatsSplitBar.gap) {
            ForEach(Array(summary.segments.enumerated()), id: \.element.id) { index, segment in
                Rectangle()
                    .fill(segment.band.color)
                    .frame(width: Self.barWidth, height: heights[index])
            }
        }
        .frame(width: Self.barWidth, height: height, alignment: .top)
    }

    /// The bands' table, in fixed columns across the width left of the bar: the name takes what the others leave.
    private var ranges: some View {
        let percentWidth: CGFloat = 40
        let perDayWidth: CGFloat = 58
        let goalWidth: CGFloat = 150
        let spacing: CGFloat = 10
        let tableWidth = width - Self.barWidth - 14
        let fixed = percentWidth + perDayWidth + goalWidth + 6 + ReportGoalCells.markWidth + spacing * 3
        let nameWidth = Swift.max(tableWidth - fixed, 60)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: spacing) {
                columnTitle(summary.unit)
                    .frame(width: nameWidth, alignment: .leading)
                columnTitle("%")
                    .frame(width: percentWidth, alignment: .trailing)
                columnTitle(NSLocalizedString("Per day", comment: ""))
                    .frame(width: perDayWidth, alignment: .trailing)
                columnTitle(NSLocalizedString("Consensus goal", comment: "PDF report: the column of the consensus goals"))
                    .frame(width: goalWidth, alignment: .leading)
            }
            .frame(height: Self.headerHeight, alignment: .top)
            ForEach(summary.rows) { row in
                Rectangle()
                    .fill(ReportStyle.hairline)
                    .frame(width: tableWidth, height: 0.5)
                HStack(spacing: spacing) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(row.band.color)
                            .frame(width: 8, height: 8)
                        Text(row.name)
                            .font(ReportStyle.font(9.5, row.band == .inRange ? .bold : .regular))
                            .minimumScaleFactor(0.7)
                        Text(row.range)
                            .font(ReportStyle.font(8.5))
                            .foregroundStyle(ReportStyle.secondary)
                            .fixedSize()
                    }
                    .frame(width: nameWidth, alignment: .leading)
                    Text(row.percent)
                        .font(ReportStyle.font(10, .semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: percentWidth, alignment: .trailing)
                    Text(row.perDay)
                        .font(ReportStyle.font(9))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: perDayWidth, alignment: .trailing)
                    ReportGoalCells(goal: row.goal, textWidth: goalWidth)
                }
                .frame(height: Self.rowHeight - 0.5)
            }
        }
        .lineLimit(1)
        .frame(width: tableWidth, alignment: .leading)
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(ReportStyle.font(7.5, .semibold))
            .foregroundStyle(ReportStyle.secondary)
    }

    /// Two tables side by side: the glucose numbers (short titles) in the narrower one.
    private var metrics: some View {
        let half = (summary.metrics.count + 1) / 2
        let gap: CGFloat = 24
        let leftWidth = ((width - gap) * 0.43).rounded()
        return HStack(alignment: .top, spacing: gap) {
            metricsTable(Array(summary.metrics.prefix(half)), width: leftWidth)
            metricsTable(Array(summary.metrics.dropFirst(half)), width: width - gap - leftWidth)
        }
    }

    /// A table of fixed columns: the title takes what the value and the goal leave, and shrinks before anything is cut.
    private func metricsTable(_ metrics: [Stat.ReportSummary.Metric], width tableWidth: CGFloat) -> some View {
        let valueWidth: CGFloat = 66
        let goalWidth: CGFloat = 44
        let spacing: CGFloat = 6
        let fixed = valueWidth + goalWidth + 6 + ReportGoalCells.markWidth + spacing * 2
        let titleWidth = Swift.max(tableWidth - fixed, 30)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(metrics) { metric in
                HStack(spacing: spacing) {
                    Text(metric.title)
                        .font(ReportStyle.font(9))
                        .minimumScaleFactor(0.6)
                        .frame(width: titleWidth, alignment: .leading)
                    Text(metric.value)
                        .font(ReportStyle.font(9.5, .semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: valueWidth, alignment: .trailing)
                    ReportGoalCells(goal: metric.goal, textWidth: goalWidth)
                }
                .frame(height: 17)
                Rectangle()
                    .fill(ReportStyle.hairline)
                    .frame(width: tableWidth, height: 0.5)
            }
        }
        .lineLimit(1)
        .frame(width: tableWidth, alignment: .leading)
    }

    private func amounts(_ block: Stat.ReportSummary.InsulinAndCarbs) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(block.amounts) { amount in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(amount.title)
                            .font(ReportStyle.font(8))
                            .foregroundStyle(ReportStyle.secondary)
                        Text(amount.value)
                            .font(ReportStyle.font(11, .semibold))
                            .monospacedDigit()
                            .fixedSize()
                        Text(amount.detail)
                            .font(ReportStyle.font(8.5))
                            .foregroundStyle(ReportStyle.secondary)
                    }
                    .lineLimit(1)
                    .frame(width: width / CGFloat(Swift.max(block.amounts.count, 1)), alignment: .leading)
                }
            }
            Text(block.notes.joined(separator: " · "))
                .font(ReportStyle.font(8))
                .foregroundStyle(ReportStyle.secondary)
        }
    }
}

// MARK: - Percentile profile

struct ReportPercentileContent: View {
    let percentile: Stat.ReportPercentile
    /// the content's, points
    let width: CGFloat
    /// the page's (landscape): a taller paper than A4 gives its extra height to the chart
    let pageHeight: CGFloat

    /// on the shortest paper (A4 landscape)
    private static let chartHeight: CGFloat = 258

    private var chartHeight: CGFloat {
        Self.chartHeight + Swift.max(pageHeight - ReportPaper.a4.size.width, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReportPercentileChart(plot: percentile.plot, size: CGSize(width: width, height: chartHeight))
            ReportPercentileLegendView(legend: percentile.legend)
            ReportSection(title: percentile.tableTitle) {
                table
            }
            if let limitedNote = percentile.limitedNote {
                Text(limitedNote)
                    .font(ReportStyle.font(8))
                    .foregroundStyle(ReportStyle.secondary)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// The percentiles in fixed columns across the width.
    private var table: some View {
        let titleWidth: CGFloat = 60
        let spacing: CGFloat = 6
        let count = CGFloat(Swift.max(percentile.times.count, 1))
        let cellWidth = (width - titleWidth - spacing * count) / count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: spacing) {
                Color.clear
                    .frame(width: titleWidth, height: 1)
                ForEach(Array(percentile.times.enumerated()), id: \.offset) { _, time in
                    Text(time)
                        .font(ReportStyle.font(8, .semibold))
                        .foregroundStyle(ReportStyle.secondary)
                        .frame(width: cellWidth, alignment: .trailing)
                }
            }
            .frame(height: 14)
            ForEach(percentile.rows) { row in
                Rectangle()
                    .fill(ReportStyle.hairline)
                    .frame(width: width, height: 0.5)
                HStack(spacing: spacing) {
                    Text(row.title)
                        .font(ReportStyle.font(9, row.id == 2 ? .bold : .regular))
                        .minimumScaleFactor(0.7)
                        .frame(width: titleWidth, alignment: .leading)
                    ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(ReportStyle.font(9, row.id == 2 ? .bold : .regular))
                            .monospacedDigit()
                            .frame(width: cellWidth, alignment: .trailing)
                    }
                }
                .frame(height: 15)
            }
        }
        .lineLimit(1)
    }
}

/// The colour key under a percentile chart.
struct ReportPercentileLegendView: View {
    let legend: Stat.ReportPercentileLegend

    var body: some View {
        HStack(spacing: 14) {
            item(legend.outer) {
                Rectangle().fill(ReportStyle.outerBand).frame(width: 14, height: 7)
            }
            item(legend.inner) {
                Rectangle().fill(ReportStyle.innerBand).frame(width: 14, height: 7)
            }
            item(legend.median) {
                Rectangle().fill(ReportStyle.median).frame(width: 14, height: 1.6)
            }
            item(legend.range) {
                Rectangle().fill(GlucoseBand.inRange.color).frame(width: 14, height: 1)
            }
        }
        .font(ReportStyle.font(8))
        .foregroundStyle(ReportStyle.secondary)
    }

    private func item<Swatch: View>(_ label: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 4) {
            swatch()
            Text(label)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// The percentile chart: the 5–95% and 25–75% bands and the median over the day, on a fixed glucose scale, with the
/// in-range band's edges. A `Canvas` in a fixed size; the labels are texts placed around it.
struct ReportPercentileChart: View {
    let plot: Stat.ReportPercentilePlot
    /// the chart's with its labels, points
    let size: CGSize

    private static let leading: CGFloat = 30
    private static let trailing: CGFloat = 12
    private static let top: CGFloat = 13
    private static let bottom: CGFloat = 15

    var body: some View {
        let rect = CGRect(
            x: Self.leading,
            y: Self.top,
            width: Swift.max(size.width - Self.leading - Self.trailing, 1),
            height: Swift.max(size.height - Self.top - Self.bottom, 1)
        )
        ZStack(alignment: .topLeading) {
            marks(rect)
            Text(plot.unit)
                .font(ReportStyle.font(6.5))
                .foregroundStyle(ReportStyle.secondary)
                .fixedSize()
                .frame(width: 60, alignment: .leading)
                .position(x: 30, y: 3.5)
            ForEach(plot.levels) { level in
                Text(level.label)
                    .font(ReportStyle.font(7.5))
                    .monospacedDigit()
                    .fixedSize()
                    .frame(width: Self.leading - 4, alignment: .trailing)
                    .position(x: (Self.leading - 4) / 2, y: Self.y(Double(level.mgdl), rect, plot.axis))
            }
            ForEach(plot.xTicks, id: \.minute) { tick in
                Text(tick.label)
                    .font(ReportStyle.font(7.5))
                    .monospacedDigit()
                    .fixedSize()
                    .position(x: Self.x(tick.minute, rect), y: rect.maxY + 8)
            }
        }
        .foregroundStyle(ReportStyle.text)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // the day runs left to right in every language
        .environment(\.layoutDirection, .leftToRight)
    }

    private func marks(_ rect: CGRect) -> some View {
        let plot = self.plot
        let outer = ReportStyle.outerBand
        let inner = ReportStyle.innerBand
        let median = ReportStyle.median
        let edge = GlucoseBand.inRange.color
        let segments = Dictionary(grouping: plot.points, by: \.segment)
            .sorted { $0.key < $1.key }
            .map(\.value)
        return Canvas { context, _ in
            for points in segments {
                context.fill(Self.band(points, rect, plot.axis, upper: \.p95, lower: \.p5), with: .color(outer))
            }
            for points in segments {
                context.fill(Self.band(points, rect, plot.axis, upper: \.p75, lower: \.p25), with: .color(inner))
            }
            for minute in plot.gridMinutes {
                var path = Path()
                let x = Self.x(minute, rect)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(path, with: .color(ReportStyle.hairline), lineWidth: 0.4)
            }
            for level in plot.levels where !plot.edges.contains(level.mgdl) {
                context.stroke(
                    Self.rule(Double(level.mgdl), rect, plot.axis),
                    with: .color(ReportStyle.hairline),
                    lineWidth: 0.4
                )
            }
            context.stroke(Path(rect), with: .color(ReportStyle.rule), lineWidth: 0.6)
            for level in plot.edges {
                context.stroke(Self.rule(Double(level), rect, plot.axis), with: .color(edge), lineWidth: 1)
            }
            for points in segments {
                context.stroke(
                    Self.line(points, rect, plot.axis, value: \.p50),
                    with: .color(median),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size.width, height: size.height)
    }

    static func x(_ minute: Int, _ rect: CGRect) -> CGFloat {
        rect.minX + rect.width * CGFloat(minute) / CGFloat(Stat.ReportPercentilePlot.dayMinutes)
    }

    static func y(_ mgdl: Double, _ rect: CGRect, _ axis: ClosedRange<Int>) -> CGFloat {
        let span = Double(Swift.max(axis.upperBound - axis.lowerBound, 1))
        let fraction = Swift.min(Swift.max((mgdl - Double(axis.lowerBound)) / span, 0), 1)
        return rect.maxY - rect.height * CGFloat(fraction)
    }

    private static func rule(_ mgdl: Double, _ rect: CGRect, _ axis: ClosedRange<Int>) -> Path {
        var path = Path()
        let y = Self.y(mgdl, rect, axis)
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }

    private static func line(
        _ points: [AGPPlotPoint],
        _ rect: CGRect,
        _ axis: ClosedRange<Int>,
        value: KeyPath<AGPPlotPoint, Double>
    ) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: x(point.minute, rect), y: y(point[keyPath: value], rect, axis))
            if index == 0 {
                path.move(to: position)
            } else {
                path.addLine(to: position)
            }
        }
        return path
    }

    /// The area between two percentiles: along the upper one, back along the lower.
    private static func band(
        _ points: [AGPPlotPoint],
        _ rect: CGRect,
        _ axis: ClosedRange<Int>,
        upper: KeyPath<AGPPlotPoint, Double>,
        lower: KeyPath<AGPPlotPoint, Double>
    ) -> Path {
        var path = line(points, rect, axis, value: upper)
        for point in points.reversed() {
            path.addLine(to: CGPoint(x: x(point.minute, rect), y: y(point[keyPath: lower], rect, axis)))
        }
        path.closeSubpath()
        return path
    }
}
