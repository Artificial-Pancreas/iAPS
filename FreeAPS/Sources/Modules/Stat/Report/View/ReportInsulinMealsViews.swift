import SwiftUI

// The Insulin and Meals parts' print views: an overview page (the averages, the days and the clock hours as bars),
// then the tables. The tables' heights are `ReportTablesLayout`'s, which the plan counts pages with.

/// A bar chart of a report, drawn in a `Canvas`: the parts stacked, the average dashed, the steps over the bars.
struct ReportBarsChart: View {
    let bars: Stat.ReportBars
    let size: CGSize

    var body: some View {
        let bars = self.bars
        let leading: CGFloat = 26
        let plot = CGRect(x: leading, y: 10, width: size.width - leading - 4, height: size.height - 10 - 12)
        return Canvas { context, _ in
            let top = bars.top
            func y(_ value: Double) -> CGFloat {
                plot.maxY - plot.height * CGFloat(Swift.min(Swift.max(value / top, 0), 1))
            }
            for (index, level) in bars.levels.enumerated() {
                var rule = Path()
                rule.move(to: CGPoint(x: plot.minX, y: y(level)))
                rule.addLine(to: CGPoint(x: plot.maxX, y: y(level)))
                context.stroke(rule, with: .color(ReportStyle.hairline), lineWidth: 0.4)
                if index < bars.levelLabels.count {
                    context.draw(
                        Text(bars.levelLabels[index]).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                        at: CGPoint(x: plot.minX - 3, y: y(level)),
                        anchor: .trailing
                    )
                }
            }
            let count = Swift.max(bars.bars.count, 1)
            let slot = plot.width / CGFloat(count)
            let barWidth = slot * 0.72
            for (index, bar) in bars.bars.enumerated() {
                let x = plot.minX + slot * CGFloat(index) + (slot - barWidth) / 2
                var base = 0.0
                for (series, value) in bar.values.enumerated() where value > 0 {
                    let rect = CGRect(x: x, y: y(base + value), width: barWidth, height: y(base) - y(base + value))
                    let style = series < bars.styles.count ? bars.styles[series] : nil
                    context.fill(Path(rect), with: .color(style?.fill ?? ReportStyle.secondary))
                    if let stroke = style?.stroke {
                        context.stroke(Path(rect.insetBy(dx: 0.25, dy: 0.25)), with: .color(stroke), lineWidth: 0.5)
                    }
                    base += value
                }
                if bar.isMarked {
                    context.draw(
                        Text("*").font(ReportStyle.font(8, .semibold)).foregroundColor(ReportStyle.text),
                        at: CGPoint(x: x + barWidth / 2, y: y(base) - 1),
                        anchor: .bottom
                    )
                }
            }
            // the steps: a level across each bar's slot, joined to the next
            var steps = Path()
            var previous: CGFloat?
            for (index, step) in bars.steps.enumerated() {
                guard index < count, let step else {
                    previous = nil
                    continue
                }
                let x = plot.minX + slot * CGFloat(index)
                if let previous {
                    steps.addLine(to: CGPoint(x: x, y: previous))
                    steps.addLine(to: CGPoint(x: x, y: y(step)))
                } else {
                    steps.move(to: CGPoint(x: x, y: y(step)))
                }
                steps.addLine(to: CGPoint(x: x + slot, y: y(step)))
                previous = y(step)
            }
            context.stroke(steps, with: .color(ReportStyle.trace), lineWidth: 0.9)
            if let average = bars.average {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y(average)))
                line.addLine(to: CGPoint(x: plot.maxX, y: y(average)))
                context.stroke(line, with: .color(ReportStyle.trace), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
            }
            for tick in bars.ticks {
                context.draw(
                    Text(tick.label).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                    at: CGPoint(x: plot.minX + slot * (CGFloat(tick.id) + 0.5), y: plot.maxY + 2),
                    anchor: .top
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// The key of a bar chart.
struct ReportBarsLegend: View {
    let items: [Stat.ReportBars.LegendItem]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 3) {
                    key(item.key)
                    Text(item.title)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .font(ReportStyle.font(7))
        .foregroundStyle(ReportStyle.secondary)
    }

    @ViewBuilder private func key(_ key: Stat.ReportBars.LegendItem.Key) -> some View {
        switch key {
        case let .swatch(style):
            Rectangle()
                .fill(style.fill)
                .overlay(Rectangle().strokeBorder(style.stroke ?? style.fill, lineWidth: 0.5))
                .frame(width: 8, height: 8)
        case .dashed:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 14, y: 4))
            }
            .stroke(ReportStyle.trace, style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
            .frame(width: 14, height: 8)
        case .step:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6))
                path.addLine(to: CGPoint(x: 7, y: 6))
                path.addLine(to: CGPoint(x: 7, y: 2))
                path.addLine(to: CGPoint(x: 14, y: 2))
            }
            .stroke(ReportStyle.trace, lineWidth: 0.9)
            .frame(width: 14, height: 8)
        case .mark:
            Text("*")
                .font(ReportStyle.font(8, .semibold))
                .foregroundStyle(ReportStyle.text)
        }
    }
}

/// A table of a report in rows of `ReportTablesLayout.rowHeight`: the name's column, then the numbers' in equal
/// widths, right-aligned.
struct ReportTableView: View {
    typealias Layout = ReportTablesLayout

    let table: Stat.ReportTable
    let width: CGFloat
    var nameWidth: CGFloat = 150

    private static let spacing: CGFloat = 6

    var body: some View {
        let count = CGFloat(Swift.max(table.columns.count, 1))
        let column = Swift.min((width - nameWidth - Self.spacing * count) / count, 74)
        let tableWidth = nameWidth + (column + Self.spacing) * count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: Self.spacing) {
                reportCell(table.name, size: 7.5, weight: .semibold)
                    .fixedSize()
                    .frame(width: nameWidth, alignment: .leading)
                ForEach(table.columns) { item in
                    VStack(alignment: .trailing, spacing: 1) {
                        reportCell(item.title, size: 7.5, weight: .semibold)
                            .fixedSize()
                        // a column without a unit keeps the line, so the titles stay level
                        reportCell(item.subtitle.isEmpty ? " " : item.subtitle, size: 6.5, secondary: true)
                            .fixedSize()
                    }
                    .frame(width: column, alignment: .trailing)
                }
            }
            .frame(height: Layout.headerHeight - 3.5, alignment: .bottom)
            .padding(.bottom, 3)
            reportRule(tableWidth, strong: true)
            ForEach(table.rows) { row in
                HStack(spacing: Self.spacing) {
                    reportCell(row.title, weight: row.isEmphasized ? .semibold : .regular)
                        .frame(width: nameWidth, alignment: .leading)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        reportCell(cell, weight: row.isEmphasized ? .semibold : .regular)
                            .frame(width: column, alignment: .trailing)
                    }
                }
                .frame(width: tableWidth, height: Layout.rowHeight - 0.5, alignment: .leading)
                .background(row.isEmphasized ? ReportStyle.shade : Color.white)
                reportRule(tableWidth)
            }
        }
    }
}

/// A section's title over its rule, in `ReportTablesLayout.sectionHeight`.
struct ReportTableTitle: View {
    let text: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(ReportStyle.font(11, .bold))
                .lineLimit(1)
            Rectangle()
                .fill(ReportStyle.rule)
                .frame(height: 0.5)
        }
        .frame(width: width, height: ReportTablesLayout.sectionHeight - 4, alignment: .bottomLeading)
        .padding(.bottom, 4)
    }
}

/// The numbers of an overview page, side by side: the name over the value and its unit.
struct ReportFiguresRow: View {
    let figures: [Stat.ReportFigure]
    let width: CGFloat

    var body: some View {
        let column = width / CGFloat(Swift.max(figures.count, 1))
        HStack(alignment: .top, spacing: 0) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 2) {
                    reportCell(figure.title, size: 7.5, secondary: true)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        reportCell(figure.value, size: 11, weight: .semibold)
                            .fixedSize()
                        if let unit = figure.unit {
                            reportCell(unit, size: 7, secondary: true)
                        }
                    }
                }
                .frame(width: column - 6, alignment: .leading)
                .padding(.trailing, 6)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// The tables of a page: the clock hours (on the first of them), then the page's days with the note under them.
private struct ReportTablesPage: View {
    typealias Layout = ReportTablesLayout

    let hourTitle: String
    let hourTable: Stat.ReportTable?
    /// the clock hours' table's rows, as the plan counts them
    let hourRows: Int
    let dayTitle: String
    let dayTable: Stat.ReportTable?
    let footnote: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hourTable {
                ReportTableTitle(text: hourTitle, width: width)
                ReportTableView(table: hourTable, width: width)
                    .frame(
                        width: width,
                        height: Layout.headerHeight + CGFloat(hourRows) * Layout.rowHeight,
                        alignment: .topLeading
                    )
                Color.clear
                    .frame(width: width, height: Layout.spacing)
            }
            if let dayTable {
                ReportTableTitle(text: dayTitle, width: width)
                ReportTableView(table: dayTable, width: width)
                // two lines at most: the slot is `Layout.footnoteHeight`
                Text(footnote)
                    .font(ReportStyle.font(7))
                    .foregroundStyle(ReportStyle.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
                    .frame(width: width, height: Layout.footnoteHeight, alignment: .topLeading)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }
}

// MARK: - Insulin

struct ReportInsulinContent: View {
    let page: Stat.ReportInsulin
    /// the content's, points
    let width: CGFloat

    private static let chartHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let emptyNote = page.emptyNote {
                reportEmpty(emptyNote)
            } else if page.isOverview {
                overview
            } else {
                ReportTablesPage(
                    hourTitle: NSLocalizedString("By hour", comment: "Statistics view: time in ranges by the hour of the day"),
                    hourTable: page.hourTable,
                    hourRows: Stat.ReportInsulin.hourRows,
                    dayTitle: NSLocalizedString("Day by day", comment: "PDF report: the days' chart and table"),
                    dayTable: page.dayTable,
                    footnote: page.footnote,
                    width: width
                )
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    @ViewBuilder private var overview: some View {
        ReportSection(title: NSLocalizedString("Total daily dose", comment: "PDF report, Insulin: the average insulin per day")) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                reportCell(page.tdd, size: 22, weight: .bold)
                    .fixedSize()
                reportCell(page.tddNote, size: 8.5, secondary: true)
            }
            split
            ReportFiguresRow(figures: page.figures, width: width)
                .padding(.top, 4)
            ForEach(Array(page.notes.enumerated()), id: \.offset) { _, note in
                reportNote(note, width: width)
            }
        }
        ReportSection(title: NSLocalizedString("Day by day", comment: "PDF report: the days' chart and table")) {
            ReportBarsChart(bars: page.dayBars, size: CGSize(width: width, height: Self.chartHeight))
            ReportBarsLegend(items: page.dayBars.legend)
        }
        ReportSection(title: NSLocalizedString("By hour", comment: "Statistics view: time in ranges by the hour of the day")) {
            ReportBarsChart(bars: page.hourBars, size: CGSize(width: width, height: Self.chartHeight))
            ReportBarsLegend(items: page.hourBars.legend)
            reportNote(
                NSLocalizedString(
                    "Basal and scheduled basal: U per hour of pump data. SMB and bolus: U per day in that hour.",
                    comment: "PDF report, Insulin by hour: what the bars are"
                ),
                width: width
            )
        }
    }

    /// The average day's parts: one bar split by them, then each with its amount and share.
    private var split: some View {
        let barWidth = width
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(page.parts) { part in
                    Rectangle()
                        .fill(part.style.fill)
                        .overlay(Rectangle().strokeBorder(part.style.stroke ?? part.style.fill, lineWidth: 0.5))
                        .frame(width: barWidth * CGFloat(part.fraction), height: 9)
                }
            }
            .frame(width: barWidth, height: 9, alignment: .leading)
            HStack(spacing: 18) {
                ForEach(page.parts) { part in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Rectangle()
                            .fill(part.style.fill)
                            .overlay(Rectangle().strokeBorder(part.style.stroke ?? part.style.fill, lineWidth: 0.5))
                            .frame(width: 8, height: 8)
                        reportCell(part.name, size: 9)
                            .fixedSize()
                        reportCell(part.value, size: 9, weight: .semibold)
                            .fixedSize()
                        reportCell(part.percent, size: 8, secondary: true)
                            .fixedSize()
                    }
                }
            }
        }
    }
}

// MARK: - Meals

struct ReportMealsContent: View {
    let page: Stat.ReportMeals
    /// the content's, points
    let width: CGFloat

    private static let chartHeight: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let emptyNote = page.emptyNote {
                reportEmpty(emptyNote)
            } else if page.isOverview {
                overview
            } else {
                ReportTablesPage(
                    hourTitle: NSLocalizedString("By time of day", comment: ""),
                    hourTable: page.hourTable,
                    hourRows: Stat.ReportMeals.hourRows,
                    dayTitle: NSLocalizedString("Day by day", comment: "PDF report: the days' chart and table"),
                    dayTable: page.dayTable,
                    footnote: page.footnote,
                    width: width
                )
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    @ViewBuilder private var overview: some View {
        ReportSection(title: NSLocalizedString("Carbs", comment: "")) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                reportCell(page.carbs, size: 22, weight: .bold)
                    .fixedSize()
                reportCell(page.carbsNote, size: 8.5, secondary: true)
            }
            ReportFiguresRow(figures: page.figures, width: width)
                .padding(.top, 4)
            ForEach(Array(page.notes.enumerated()), id: \.offset) { _, note in
                reportNote(note, width: width)
            }
        }
        ReportSection(title: NSLocalizedString("Day by day", comment: "PDF report: the days' chart and table")) {
            ReportBarsChart(bars: page.dayBars, size: CGSize(width: width, height: Self.chartHeight))
            ReportBarsLegend(items: page.dayBars.legend)
        }
        ReportSection(title: NSLocalizedString("By time of day", comment: "")) {
            ReportBarsChart(bars: page.hourBars, size: CGSize(width: width, height: Self.chartHeight))
            ReportBarsLegend(items: page.hourBars.legend)
        }
        if page.topHours.isNotEmpty {
            ReportSection(title: NSLocalizedString("Most carbs", comment: "")) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(page.topHours) { hour in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            reportCell(hour.time, size: 9, weight: .semibold)
                                .frame(width: 130, alignment: .leading)
                            reportCell(hour.percent, size: 9, weight: .semibold)
                                .frame(width: 50, alignment: .leading)
                            reportCell(hour.detail, size: 9, secondary: true)
                        }
                    }
                }
            }
        }
    }
}
