import SwiftUI

// Good & bad days' print view: the two groups' profiles over the day, their glucose rows, what was different, and
// the groups' days. The heights are `ReportGoodBadDaysLayout`'s, which the plan counts pages with.

struct ReportGoodBadDaysContent: View {
    typealias Layout = ReportGoodBadDaysLayout

    let page: Stat.ReportGoodBadDays
    /// the content's, points
    let width: CGFloat

    private var content: Stat.GoodBadDays.Content { page.content }

    /// Every piece in a frame of its `Layout` height: the blocks' heights are the plan's.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .comparison: comparison
                case let .factors(sections, isFirst, isLast): factors(sections, isFirst: isFirst, isLast: isLast)
                case .lists: lists
                case .empty:
                    reportEmpty(page.emptyNote ?? "")
                        .frame(width: width, height: Layout.emptyHeight, alignment: .bottomLeading)
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// A section's title over its rule, in `Layout.sectionHeight`.
    private func title(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(ReportStyle.font(11, .bold))
                .lineLimit(1)
            Rectangle()
                .fill(ReportStyle.rule)
                .frame(height: 0.5)
        }
        .frame(width: width, height: Layout.sectionHeight - 4, alignment: .bottomLeading)
        .padding(.bottom, 4)
    }

    // MARK: - The comparison

    @ViewBuilder private var comparison: some View {
        intro
        if let message = content.message {
            VStack(alignment: .leading, spacing: 2) {
                reportCell(message.title, size: 10, weight: .semibold)
                reportNote(message.detail, width: width)
            }
            .frame(width: width, height: Layout.messageHeight, alignment: .topLeading)
        }
        if content.reference.isShown || content.compared.isShown {
            ReportGoodBadDaysChart(page: page, size: CGSize(width: width, height: Layout.chartHeight))
            legend
        }
        if content.isComparable {
            title(NSLocalizedString("Glucose on those days", comment: ""))
            glucoseTable
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 2) {
            reportCell(content.counts, size: 10, weight: .semibold)
            ForEach(Array(content.lines.prefix(3).enumerated()), id: \.offset) { _, line in
                reportCell(line, size: 8, secondary: true)
            }
            reportCell(page.griNote, size: 7.5, secondary: true)
        }
        .frame(width: width, height: Layout.introHeight, alignment: .topLeading)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                ForEach([content.reference, content.compared].filter(\.isShown), id: \.side) { group in
                    HStack(spacing: 4) {
                        ReportGroupKey(isReference: group.side == .reference)
                        Text(group.title)
                            .fixedSize()
                    }
                }
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(ReportStyle.rangeBand)
                        .frame(width: 14, height: 7)
                    Text(page.rangeLegend)
                        .fixedSize()
                }
            }
            .font(ReportStyle.font(7.5))
            .foregroundStyle(ReportStyle.secondary)
            .lineLimit(1)
            Text(page.chartNote)
                .font(ReportStyle.font(7))
                .foregroundStyle(ReportStyle.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: width, alignment: .leading)
        }
        .padding(.top, 3)
        .frame(width: width, height: Layout.chartNotesHeight, alignment: .topLeading)
    }

    private var glucoseTable: some View {
        let nameWidth: CGFloat = 170
        let cellWidth: CGFloat = 110
        let tableWidth = nameWidth + cellWidth * 3
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                reportCell(NSLocalizedString("median (IQR)", comment: ""), size: 7.5, secondary: true)
                    .frame(width: nameWidth, alignment: .leading)
                reportCell(content.reference.short, size: 7.5, weight: .semibold)
                    .frame(width: cellWidth, alignment: .leading)
                reportCell(content.compared.short, size: 7.5, weight: .semibold)
                    .frame(width: cellWidth, alignment: .leading)
                reportCell(NSLocalizedString("Difference", comment: ""), size: 7.5, weight: .semibold)
                    .frame(width: cellWidth, alignment: .leading)
            }
            .frame(height: Layout.rowHeight - 0.5)
            reportRule(tableWidth, strong: true)
            ForEach(content.glucoseRows) { row in
                HStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        reportCell(row.name)
                        if let detail = row.detail {
                            reportCell(detail, size: 7.5, secondary: true)
                        }
                    }
                    .frame(width: nameWidth, alignment: .leading)
                    cell(row.reference)
                        .frame(width: cellWidth, alignment: .leading)
                    cell(row.compared)
                        .frame(width: cellWidth, alignment: .leading)
                    reportCell(row.difference, weight: .semibold)
                        .frame(width: cellWidth, alignment: .leading)
                }
                .frame(height: Layout.rowHeight - 0.5)
                reportRule(tableWidth)
            }
        }
    }

    private func cell(_ cell: Stat.GoodBadDays.GlucoseRow.Cell) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            reportCell(cell.value, weight: .semibold)
            reportCell(cell.range, size: 7.5, secondary: true)
        }
    }

    // MARK: - What was different

    /// A row a line: the name, both groups' values, the difference and its direction. The sections the page's block
    /// names, under the title and the line that says what a row is (again after a page break).
    @ViewBuilder private func factors(_ sections: [Layout.Section], isFirst: Bool, isLast: Bool) -> some View {
        let nameWidth: CGFloat = 146
        let differenceWidth: CGFloat = 92
        let valuesWidth = width - nameWidth - differenceWidth
        let name = NSLocalizedString("What was different on those days", comment: "")
        title(
            isFirst ? name : String(
                format: NSLocalizedString("%@ (continued)", comment: "PDF report: a section going on after a page break"),
                name
            )
        )
        Text(content.factorIntro)
            .font(ReportStyle.font(7))
            .foregroundStyle(ReportStyle.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(width: width, height: Layout.factorIntroHeight, alignment: .topLeading)
        ForEach(content.factorSections.filter { sections.contains($0.id) }) { section in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                reportCell(section.title, size: 8.5, weight: .semibold)
                    .fixedSize()
                if let note = section.unavailable ?? section.note {
                    reportCell(note, size: 7, secondary: true)
                }
            }
            .frame(width: width, height: Layout.factorSectionHeight - 2.5, alignment: .bottomLeading)
            .padding(.bottom, 2)
            reportRule(width, strong: true)
            ForEach(section.rows) { row in
                HStack(spacing: 0) {
                    reportCell(row.name)
                        .frame(width: nameWidth - 6, alignment: .leading)
                        .padding(.trailing, 6)
                    reportCell(row.values, size: 7.5, secondary: true)
                        .frame(width: valuesWidth, alignment: .leading)
                    reportCell(row.difference + " " + row.direction, weight: .semibold)
                        .frame(width: differenceWidth, alignment: .trailing)
                }
                .frame(height: Layout.rowHeight - 0.5)
                reportRule(width)
            }
        }
        if isLast {
            Text(
                NSLocalizedString(
                    "Differences between these groups of days, not causes. Small groups differ by chance.",
                    comment: ""
                )
            )
            .font(ReportStyle.font(7))
            .foregroundStyle(ReportStyle.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 4)
            .frame(width: width, height: Layout.closingHeight, alignment: .topLeading)
        }
    }

    // MARK: - The days

    /// The two groups' days side by side, newest first; a long list in two columns.
    @ViewBuilder private var lists: some View {
        let columnWidth = (width - 20) / 2
        title(NSLocalizedString("The days", comment: "PDF report, Good & bad days: the groups' days"))
        HStack(alignment: .top, spacing: 20) {
            ForEach([content.reference, content.compared], id: \.side) { group in
                list(group, width: columnWidth)
            }
        }
    }

    private func list(_ group: Stat.GoodBadDays.Group, width columnWidth: CGFloat) -> some View {
        let rows = Layout.listRows(group.days.count)
        let split = rows < group.days.count
        let halves = split ? [Array(group.days.prefix(rows)), Array(group.days.dropFirst(rows))] : [group.days]
        let halfWidth = split ? (columnWidth - 10) / 2 : columnWidth
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ReportGroupKey(isReference: group.side == .reference)
                reportCell(group.title, size: 8.5, weight: .semibold)
                    .fixedSize()
                reportCell(group.span, size: 7.5, secondary: true)
            }
            .frame(width: columnWidth, height: Layout.listHeaderHeight - 0.5, alignment: .leading)
            reportRule(columnWidth, strong: true)
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(halves.enumerated()), id: \.offset) { _, days in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(days) { day in
                            HStack(spacing: 5) {
                                reportCell(day.title, size: 8)
                                    .frame(width: 62, alignment: .leading)
                                if !split {
                                    ReportBandBar(segments: day.segments, width: 50, height: 5)
                                    reportCell(day.detail, size: 7.5, secondary: true)
                                        .frame(width: 66, alignment: .leading)
                                }
                                reportCell(day.gri, size: 8, weight: .semibold)
                            }
                            .frame(width: halfWidth, height: Layout.dayHeight - 0.5, alignment: .leading)
                            reportRule(halfWidth)
                        }
                    }
                    .frame(width: halfWidth, alignment: .topLeading)
                }
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
    }
}

/// A group's key: the best third a solid line on its light band, the worst a dashed line on a darker one.
private struct ReportGroupKey: View {
    let isReference: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isReference ? ReportGoodBadDaysChart.referenceBand : ReportGoodBadDaysChart.comparedBand)
                .frame(width: 18, height: 7)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 3.5))
                path.addLine(to: CGPoint(x: 18, y: 3.5))
            }
            .stroke(
                isReference ? ReportStyle.text : ReportStyle.accent,
                style: StrokeStyle(lineWidth: 1.3, dash: isReference ? [] : [3, 2])
            )
            .frame(width: 18, height: 7)
        }
    }
}

/// The two groups' profiles over the day: each one's 25–75% band and median. Told apart without colour: the best third
/// a solid line on a light grey band, the worst a dashed line on a darker band.
struct ReportGoodBadDaysChart: View {
    static let referenceBand = Color(white: 0.86)
    static let comparedBand = Color(red: 0.72, green: 0.79, blue: 0.9)

    let page: Stat.ReportGoodBadDays
    let size: CGSize

    var body: some View {
        let plot = page.model.plot
        let groups = [page.content.reference, page.content.compared].filter(\.isShown)
        let leading: CGFloat = 30
        let rect = CGRect(x: leading, y: 5, width: size.width - leading - 6, height: size.height - 5 - 13)
        Canvas { context, _ in
            let span = Double(Swift.max(plot.axis.upperBound - plot.axis.lowerBound, 1))
            func y(_ mgdl: Double) -> CGFloat {
                rect.maxY - rect.height * CGFloat(Swift.min(Swift.max((mgdl - Double(plot.axis.lowerBound)) / span, 0), 1))
            }
            func x(_ minute: Int) -> CGFloat {
                rect.minX + rect.width * CGFloat(minute) / CGFloat(StatsClock.minutesPerDay)
            }
            func segments(_ points: [AGPPlotPoint]) -> [[AGPPlotPoint]] {
                Dictionary(grouping: points, by: \.segment).sorted { $0.key < $1.key }.map(\.value)
            }
            // the in-range band
            let top = y(Double(plot.high))
            context.fill(
                Path(CGRect(x: rect.minX, y: top, width: rect.width, height: Swift.max(y(Double(plot.low)) - top, 0))),
                with: .color(ReportStyle.rangeBand)
            )
            for tick in plot.xTicks {
                var rule = Path()
                rule.move(to: CGPoint(x: x(tick.minute), y: rect.minY))
                rule.addLine(to: CGPoint(x: x(tick.minute), y: rect.maxY))
                context.stroke(rule, with: .color(ReportStyle.hairline), lineWidth: 0.3)
                context.draw(
                    Text(tick.label).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                    at: CGPoint(x: x(tick.minute), y: rect.maxY + 2),
                    anchor: tick.minute == 0 ? .topLeading : .top
                )
            }
            for level in plot.yLabels {
                context.draw(
                    Text(level.label).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                    at: CGPoint(x: rect.minX - 3, y: y(Double(level.mgdl))),
                    anchor: .trailing
                )
            }
            // the bands under both lines
            for group in groups {
                let fill = group.side == .reference ? Self.referenceBand : Self.comparedBand
                for points in segments(group.points) where points.count > 1 {
                    var band = Path()
                    band.move(to: CGPoint(x: x(points[0].minute), y: y(points[0].p75)))
                    for point in points.dropFirst() {
                        band.addLine(to: CGPoint(x: x(point.minute), y: y(point.p75)))
                    }
                    for point in points.reversed() {
                        band.addLine(to: CGPoint(x: x(point.minute), y: y(point.p25)))
                    }
                    band.closeSubpath()
                    context.fill(band, with: .color(fill.opacity(0.75)))
                }
            }
            for group in groups {
                let isReference = group.side == .reference
                for points in segments(group.points) where points.count > 1 {
                    var line = Path()
                    line.move(to: CGPoint(x: x(points[0].minute), y: y(points[0].p50)))
                    for point in points.dropFirst() {
                        line.addLine(to: CGPoint(x: x(point.minute), y: y(point.p50)))
                    }
                    context.stroke(
                        line,
                        with: .color(isReference ? ReportStyle.text : ReportStyle.accent),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: isReference ? [] : [4, 2.5])
                    )
                }
            }
            context.stroke(Path(rect), with: .color(ReportStyle.rule), lineWidth: 0.5)
            context.draw(
                Text(plot.unit).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                at: CGPoint(x: rect.minX + 3, y: rect.minY + 2),
                anchor: .topLeading
            )
        }
        .frame(width: size.width, height: size.height)
        .environment(\.layoutDirection, .leftToRight)
    }
}
