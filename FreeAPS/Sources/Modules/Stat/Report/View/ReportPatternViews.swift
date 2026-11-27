import SwiftUI

// By hour, By weekday and Weekly's print views: fixed sizes, no selection, the charts drawn in a `Canvas`.

/// A table's cell text.
@MainActor func reportCell(
    _ text: String,
    size: CGFloat = 8.5,
    weight: Font.Weight = .regular,
    secondary: Bool = false
) -> some View {
    Text(text)
        .font(ReportStyle.font(size, weight))
        .foregroundStyle(secondary ? ReportStyle.secondary : ReportStyle.text)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
}

@MainActor func reportRule(_ width: CGFloat, strong: Bool = false) -> some View {
    Rectangle()
        .fill(strong ? ReportStyle.rule : ReportStyle.hairline)
        .frame(width: width, height: 0.5)
}

@MainActor func reportNote(_ text: String, width: CGFloat) -> some View {
    Text(text)
        .font(ReportStyle.font(7))
        .foregroundStyle(ReportStyle.secondary)
        .lineLimit(3)
        .minimumScaleFactor(0.7)
        .frame(width: width, alignment: .leading)
}

/// In place of a part's content: why there is none.
@MainActor func reportEmpty(_ text: String) -> some View {
    Text(text)
        .font(ReportStyle.font(10))
        .foregroundStyle(ReportStyle.secondary)
}

/// A band bar: the nonzero bands side by side, very low at the leading end.
struct ReportBandBar: View {
    let segments: [BandSegment]
    let width: CGFloat
    var height: CGFloat = 7

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                Rectangle()
                    .fill(segment.band.color)
                    .frame(width: width * CGFloat(segment.fraction), height: height)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }
}

// MARK: - By hour

struct ReportHoursContent: View {
    let page: Stat.ReportHours
    /// the content's, points
    let width: CGFloat

    private static let timeWidth: CGFloat = 92
    private static let spacing: CGFloat = 6
    private static let rowHeight: CGFloat = 12.5
    private static let headerHeight: CGFloat = 20

    /// taller without the table under it
    private var chartHeight: CGFloat { page.showsTable ? 140 : 300 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if page.isEmpty {
                reportEmpty(NSLocalizedString("No CGM data in this period", comment: ""))
            } else {
                if page.showsChart {
                    chart
                    legend
                }
                if page.peaks.isNotEmpty {
                    ReportSection(title: NSLocalizedString("When it happens", comment: "")) {
                        peaks
                    }
                }
                if page.showsTable {
                    ReportSection(
                        title: NSLocalizedString(
                            "Time in ranges by hour, % of each hour's time",
                            comment: "PDF report, By hour: the table's title, what its percentages are of"
                        )
                    ) {
                        table
                    }
                }
                reportNote(page.note, width: width)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private var chart: some View {
        let page = self.page
        let size = CGSize(width: width, height: chartHeight)
        let leading: CGFloat = 26
        let plot = CGRect(x: leading, y: 4, width: size.width - leading - 4, height: size.height - 4 - 12)
        return Canvas { context, _ in
            let slot = plot.width / 24
            for (index, label) in page.levels.enumerated() {
                let y = plot.maxY - plot.height * CGFloat(index) / CGFloat(Swift.max(page.levels.count - 1, 1))
                var rule = Path()
                rule.move(to: CGPoint(x: plot.minX, y: y))
                rule.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(rule, with: .color(ReportStyle.hairline), lineWidth: 0.4)
                context.draw(
                    Text(label).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                    at: CGPoint(x: plot.minX - 3, y: y),
                    anchor: .trailing
                )
            }
            for bar in page.bars {
                let x = plot.minX + slot * CGFloat(bar.id) + slot * 0.14
                for segment in bar.segments {
                    let top = plot.maxY - plot.height * CGFloat(segment.upper)
                    let bottom = plot.maxY - plot.height * CGFloat(segment.lower)
                    context.fill(
                        Path(CGRect(x: x, y: top, width: slot * 0.72, height: Swift.max(bottom - top, 0))),
                        with: .color(segment.band.color)
                    )
                }
            }
            for tick in page.ticks {
                context.draw(
                    Text(tick.label).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                    at: CGPoint(x: plot.minX + slot * CGFloat(tick.id), y: plot.maxY + 2),
                    anchor: tick.id == 0 ? .topLeading : .top
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(page.legend) { item in
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(item.band.color)
                        .frame(width: 8, height: 8)
                    Text(item.text)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .font(ReportStyle.font(7))
        .foregroundStyle(ReportStyle.secondary)
    }

    private var peaks: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(page.peaks) { peak in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Rectangle()
                        .fill(peak.band.color)
                        .frame(width: 7, height: 7)
                    reportCell(peak.title, size: 9, weight: .semibold)
                        .frame(width: 96, alignment: .leading)
                    reportCell(peak.time, size: 9)
                        .frame(width: 96, alignment: .leading)
                    reportCell(peak.detail, size: 9, secondary: true)
                }
            }
        }
    }

    private var table: some View {
        let count = CGFloat(Swift.max(page.columns.count, 1))
        let column = Swift.min((width - Self.timeWidth - Self.spacing * count) / count, 58)
        let tableWidth = Self.timeWidth + (column + Self.spacing) * count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: Self.spacing) {
                reportCell(NSLocalizedString("Time", comment: ""), size: 7.5, weight: .semibold)
                    .fixedSize()
                    .frame(width: Self.timeWidth, alignment: .leading)
                ForEach(page.columns) { item in
                    VStack(alignment: .trailing, spacing: 1) {
                        reportCell(item.title, size: 7.5, weight: .semibold)
                            .fixedSize()
                        reportCell(item.subtitle, size: 6.5, secondary: true)
                            .fixedSize()
                    }
                    .frame(width: column, alignment: .trailing)
                }
            }
            .frame(height: Self.headerHeight, alignment: .bottom)
            .padding(.bottom, 3)
            reportRule(tableWidth, strong: true)
            ForEach(page.rows) { row in
                HStack(spacing: Self.spacing) {
                    reportCell(row.time)
                        .frame(width: Self.timeWidth, alignment: .leading)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                        reportCell(cell, weight: index == 0 ? .semibold : .regular)
                            .frame(width: column, alignment: .trailing)
                    }
                }
                .frame(height: Self.rowHeight - 0.5)
                reportRule(tableWidth)
            }
        }
    }
}

// MARK: - By weekday

struct ReportWeekdaysContent: View {
    let page: Stat.ReportWeekdays
    /// the content's, points
    let width: CGFloat

    private static let nameWidth: CGFloat = 78
    private static let barsHeight: CGFloat = 84
    private static let cellHeight: CGFloat = 19
    /// before the weekend's columns
    private static let weekendGap: CGFloat = 8

    private var model: Stat.Weekday { page.model }

    /// A weekday's column, the same under the bars, in the table and in the heat map.
    private var columnWidth: CGFloat {
        let count = CGFloat(Swift.max(model.columns.count, 1))
        let gap: CGFloat = model.weekendStart < model.columns.count ? Self.weekendGap : 0
        return Swift.min((width - Self.nameWidth - gap) / count, 62)
    }

    private func x(_ column: Int) -> CGFloat {
        Self.nameWidth + columnWidth * CGFloat(column) + (column >= model.weekendStart ? Self.weekendGap : 0)
    }

    private var gridWidth: CGFloat {
        x(model.columns.count - 1) + columnWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let emptyNote = page.emptyNote {
                reportEmpty(emptyNote)
            } else {
                sections
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    @ViewBuilder private var sections: some View {
        ReportSection(title: NSLocalizedString("In range by weekday", comment: "")) {
            bars
            table
            reportNote(model.barsFootnote, width: width)
        }
        ReportSection(title: page.heatTitle) {
            heatMap
            legend
            if let fewNote = page.fewNote {
                reportNote(fewNote, width: width)
            }
        }
        if model.workdays != nil || model.weekend != nil {
            ReportSection(title: NSLocalizedString("Weekdays vs weekends", comment: "")) {
                comparison
                reportNote(model.summaryFootnote, width: width)
            }
        }
        if let limitedNote = model.limitedNote {
            reportNote(limitedNote, width: width)
        }
    }

    /// A column a weekday, positioned as the table under it.
    private func row<Cell: View>(height: CGFloat, name: String, @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        ZStack(alignment: .topLeading) {
            reportCell(name, secondary: true)
                .frame(width: Self.nameWidth - 6, height: height, alignment: .leading)
            ForEach(model.columns.indices, id: \.self) { column in
                cell(column)
                    .frame(width: columnWidth, height: height)
                    .offset(x: x(column))
            }
        }
        .frame(width: gridWidth, height: height, alignment: .topLeading)
    }

    private var bars: some View {
        let parts = model.bars.parts
        return row(height: Self.barsHeight, name: "") { column in
            VStack(spacing: 0) {
                if column < parts.count {
                    ForEach(parts[column].reversed()) { part in
                        Rectangle()
                            .fill(part.band.color)
                            .frame(width: columnWidth * 0.62, height: Self.barsHeight * CGFloat(part.upper - part.lower))
                    }
                }
            }
            .frame(width: columnWidth, height: Self.barsHeight, alignment: .bottom)
        }
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.tableRows.enumerated()), id: \.offset) { index, tableRow in
                row(height: 13, name: tableRow.name) { column in
                    reportCell(
                        column < tableRow.values.count ? tableRow.values[column] : "",
                        weight: tableRow.isEmphasized || index == 0 ? .semibold : .regular,
                        secondary: tableRow.isSecondary && index != 0
                    )
                }
                reportRule(gridWidth, strong: index == 0)
            }
        }
    }

    private var heatMap: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(height: 12, name: "") { column in
                reportCell(model.columns[column].short, size: 7.5, weight: .semibold)
            }
            ForEach(model.blockLabels.indices, id: \.self) { block in
                row(height: Self.cellHeight, name: model.blockLabels[block]) { column in
                    heatCell(column: column, block: block)
                }
            }
        }
    }

    private func heatCell(column: Int, block: Int) -> some View {
        let cell = column < page.cells.count && block < page.cells[column].count ? page.cells[column][block] : nil
        let text = cell.map { $0.isFew ? "(" + $0.text + ")" : $0.text } ?? "–"
        return ZStack {
            if let step = cell?.step {
                Rectangle()
                    .fill(WeekdayCellStyle.color(page.metric, step: step, isDark: false))
                Rectangle()
                    .strokeBorder(ReportStyle.trace, lineWidth: ReportStyle.heatOutline(page.metric, step: step))
            } else {
                Rectangle()
                    .stroke(ReportStyle.hairline, lineWidth: 0.5)
            }
            // on white, so the value reads on every step and in black and white
            Text(text)
                .font(ReportStyle.font(8, .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 2)
                .background(Color.white.opacity(cell?.step == nil ? 0 : 0.82))
        }
        .frame(width: columnWidth - 2, height: Self.cellHeight - 2)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text(page.legend.title)
            ForEach(Array(page.legend.steps.enumerated()), id: \.offset) { step, label in
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(WeekdayCellStyle.color(page.metric, step: step, isDark: false))
                        .overlay(
                            Rectangle()
                                .strokeBorder(
                                    ReportStyle.trace,
                                    lineWidth: ReportStyle.heatOutline(page.metric, step: step)
                                )
                        )
                        .frame(width: 10, height: 8)
                    Text(label)
                        .fixedSize()
                }
            }
        }
        .font(ReportStyle.font(7))
        .foregroundStyle(ReportStyle.secondary)
        .lineLimit(1)
    }

    private var comparison: some View {
        let groups = [model.workdays, model.weekend].compactMap { $0 }
        let groupWidth: CGFloat = 150
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                Color.clear
                    .frame(width: 130, height: 1)
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 2) {
                        reportCell(group.name, size: 9, weight: .semibold)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            reportCell(group.inRange, size: 12, weight: .bold)
                            reportCell(group.subtitle, size: 7.5, secondary: true)
                        }
                        ReportBandBar(segments: group.segments, width: groupWidth - 20)
                    }
                    .frame(width: groupWidth, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.summaryRows) { summaryRow in
                    reportRule(130 + groupWidth * CGFloat(groups.count))
                    HStack(spacing: 0) {
                        reportCell(summaryRow.name)
                            .frame(width: 130, alignment: .leading)
                        reportCell(summaryRow.workdays, weight: .semibold)
                            .frame(width: groupWidth, alignment: .leading)
                        if groups.count > 1 {
                            reportCell(summaryRow.weekend, weight: .semibold)
                                .frame(width: groupWidth, alignment: .leading)
                        }
                    }
                    .frame(height: 13)
                }
            }
        }
    }
}

// MARK: - Weekly

struct ReportWeeksContent: View {
    let page: Stat.ReportWeeks
    /// the content's, points
    let width: CGFloat

    private static let chartHeight: CGFloat = 104
    private static let weekWidth: CGFloat = 150
    private static let rowHeight: CGFloat = 14

    private var model: Stat.Weekly { page.model }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let emptyNote = page.emptyNote {
                reportEmpty(emptyNote)
            } else {
                ReportSection(title: page.inRangeTitle + " · " + model.inRangeAverage) {
                    ReportWeeksChart(plot: model.inRangePlot, size: CGSize(width: width, height: Self.chartHeight))
                }
                ReportSection(title: model.meanTitle + " · " + model.meanAverage) {
                    ReportWeeksChart(plot: model.meanPlot, size: CGSize(width: width, height: Self.chartHeight))
                }
                ReportSection(title: NSLocalizedString("Weeks", comment: "")) {
                    table
                    reportNote(page.note, width: width)
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private var table: some View {
        let column: CGFloat = 70
        let tableWidth = Self.weekWidth + 90 + column * CGFloat(page.columns.count)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                reportCell(NSLocalizedString("Week", comment: ""), size: 7.5, weight: .semibold)
                    .frame(width: Self.weekWidth + 90, alignment: .leading)
                ForEach(page.columns) { item in
                    VStack(alignment: .trailing, spacing: 1) {
                        reportCell(item.title, size: 7.5, weight: .semibold)
                        reportCell(item.subtitle, size: 6.5, secondary: true)
                    }
                    .frame(width: column, alignment: .trailing)
                }
            }
            .padding(.bottom, 3)
            reportRule(tableWidth, strong: true)
            ForEach(model.rows) { row in
                HStack(spacing: 0) {
                    reportCell(row.title, size: 9)
                        .frame(width: Self.weekWidth, alignment: .leading)
                    reportCell(row.subtitle, size: 7.5, secondary: true)
                        .frame(width: 90, alignment: .leading)
                    if let values = row.values {
                        reportCell(values.inRange, size: 9, weight: .semibold)
                            .frame(width: column, alignment: .trailing)
                        reportCell(values.inRangeDelta, size: 9)
                            .frame(width: column, alignment: .trailing)
                        reportCell(values.mean, size: 9, weight: .semibold)
                            .frame(width: column, alignment: .trailing)
                        reportCell(values.meanDelta, size: 9)
                            .frame(width: column, alignment: .trailing)
                    } else {
                        reportCell(NSLocalizedString("no data", comment: ""), size: 9, secondary: true)
                            .frame(width: column * CGFloat(page.columns.count), alignment: .trailing)
                    }
                }
                .frame(height: Self.rowHeight - 0.5)
                reportRule(tableWidth)
            }
        }
    }
}

/// A Weekly chart: each week's bar from the average to its value, the average as a dashed line.
struct ReportWeeksChart: View {
    let plot: Stat.Weekly.Plot
    let size: CGSize

    var body: some View {
        let plot = self.plot
        let leading: CGFloat = 34
        let rect = CGRect(x: leading, y: 5, width: size.width - leading - 4, height: size.height - 5 - 13)
        Canvas { context, _ in
            let span = Swift.max(plot.domain.upperBound - plot.domain.lowerBound, 0.0001)
            func y(_ value: Double) -> CGFloat {
                rect.maxY - rect.height * CGFloat((value - plot.domain.lowerBound) / span)
            }
            let slot = rect.width / CGFloat(Swift.max(plot.slots.count, 1))
            func x(_ slotName: String) -> CGFloat {
                rect.minX + slot * (CGFloat(plot.slots.firstIndex(of: slotName) ?? 0) + 0.5)
            }
            for level in plot.levels {
                var rule = Path()
                rule.move(to: CGPoint(x: rect.minX, y: y(level.value)))
                rule.addLine(to: CGPoint(x: rect.maxX, y: y(level.value)))
                context.stroke(
                    rule,
                    with: .color(level.isAverage ? ReportStyle.text : ReportStyle.hairline),
                    style: StrokeStyle(lineWidth: level.isAverage ? 0.7 : 0.4, dash: level.isAverage ? [3, 2] : [])
                )
                context.draw(
                    Text(level.label)
                        .font(ReportStyle.font(6.5, level.isAverage ? .semibold : .regular))
                        .foregroundColor(level.isAverage ? ReportStyle.text : ReportStyle.secondary),
                    at: CGPoint(x: rect.minX - 3, y: y(level.value)),
                    anchor: .trailing
                )
            }
            for bar in plot.bars {
                let top = y(bar.upper)
                let bottom = y(bar.lower)
                context.fill(
                    Path(CGRect(x: x(bar.slot) - slot * 0.3, y: top, width: slot * 0.6, height: Swift.max(bottom - top, 0.8))),
                    with: .color(ReportStyle.accent)
                )
            }
            for tick in plot.ticks {
                context.draw(
                    Text(tick.label).font(ReportStyle.font(6.5)).foregroundColor(ReportStyle.secondary),
                    at: CGPoint(x: x(tick.slot), y: rect.maxY + 2),
                    anchor: .top
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.layoutDirection, .leftToRight)
    }
}
