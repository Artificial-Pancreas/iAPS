import SwiftUI

// MARK: - Heatmap

/// The heatmap's card: the metric, the grid (a column per weekday, a row per hour or 3-hour block), its key and its
/// note. Re-rendered when the metric changes; the cells only when their heatmap does (`WeekdayCells`).
struct WeekdayHeatmapCard: View {
    let weekday: Stat.Weekday
    let selection: WeekdaySelection
    let hoursPerRow: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let metric = selection.metric
        VStack(alignment: .leading, spacing: 14) {
            content(metric)
        }
    }

    @ViewBuilder private func content(_ metric: WeekdayMetric) -> some View {
        StatsCardHeader(title: "By weekday and hour", range: weekday.dateRange)

        StatsSegmentedControl(
            items: WeekdayMetric.allCases,
            selection: Binding(get: { selection.metric }, set: { selection.select(metric: $0) }),
            label: { Stat.Weekday.title($0) }
        )

        if let heatmap = weekday.heatmap(metric, hoursPerRow: hoursPerRow) {
            WeekdayHeatmapGrid(
                weekday: weekday,
                heatmap: heatmap,
                rowLabels: hoursPerRow == 1 ? weekday.hourLabels : weekday.blockLabels.map { $0 as String? },
                isDark: colorScheme == .dark,
                selection: selection
            )
        }

        legend(metric)

        Text(hoursPerRow == 1 ? weekday.hourFootnote : weekday.blockFootnote)
            .statsNote()
    }

    /// The five steps under their values, what they measure; the hatched and the outlined cell. Each line under the
    /// other when it doesn't fit.
    @ViewBuilder private func legend(_ metric: WeekdayMetric) -> some View {
        let isDark = colorScheme == .dark
        VStack(alignment: .leading, spacing: 8) {
            if let legend = weekday.legends[metric] {
                let steps = HStack(spacing: 2) {
                    ForEach(legend.steps.indices, id: \.self) { step in
                        VStack(spacing: 2) {
                            WeekdaySwatch(cell: .init(step: step, isFew: false), metric: metric, isDark: isDark)
                                .frame(height: 12)
                            Text(legend.steps[step])
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(minWidth: 40)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        steps
                        Text(legend.title)
                            .padding(.bottom, 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        steps
                        Text(legend.title)
                    }
                }
            }
            let few = HStack(spacing: 5) {
                WeekdaySwatch(cell: .init(step: 2, isFew: true), metric: metric, isDark: isDark)
                    .frame(width: 14, height: 12)
                Text(
                    String(
                        format: NSLocalizedString(
                            "under %d h of readings",
                            comment: "Statistics By weekday heatmap key: a hatched cell, the hours of data"
                        ),
                        Int(GlucoseStatsEngine.weekdayFewHours) * hoursPerRow
                    )
                )
            }
            let none = HStack(spacing: 5) {
                WeekdaySwatch(cell: .init(step: nil, isFew: false), metric: metric, isDark: isDark)
                    .frame(width: 14, height: 12)
                Text("no readings", comment: "Statistics By weekday: a day without readings")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    few
                    none
                }
                VStack(alignment: .leading, spacing: 4) {
                    few
                    none
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// The colours of the heatmap in five steps, in light and dark: in range diverging at the 70% target, two oranges below
/// (`StatsHigh` and a pale one) and three greens above (a pale yellowish one, a muted one, `StatsInRange`), each apart
/// from the others' dimmed shades too; low and mean a single hue (more ink for more of it). A few-readings cell dimmed
/// towards the card and hatched, an empty one outlined.
private enum WeekdayCellStyle {
    typealias RGB = (red: Double, green: Double, blue: Double)

    private static func rgb(_ hex: UInt32) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func ramp(_ metric: WeekdayMetric, isDark: Bool) -> [UInt32] {
        switch (metric, isDark) {
        case (.inRange, false): return [0xFF9C00, 0xFFD6AD, 0xBDE58A, 0x6FA263, 0x2F9902]
        case (.inRange, true): return [0xFFC145, 0xA77F31, 0x608201, 0x629E55, 0x3FBD12]
        case (.low, false): return [0xFEE0DD, 0xFEB5B0, 0xFB817C, 0xE2484B, 0xB01D29]
        case (.low, true): return [0x532B29, 0x843C39, 0xBC504E, 0xEA716D, 0xFEA6A0]
        case (.mean, false): return [0xE2E6FE, 0xBEC6FF, 0x9AA3F6, 0x7278E4, 0x4E4AC8]
        case (.mean, true): return [0x30335B, 0x484D91, 0x666CC8, 0x878FF6, 0xB2BBFF]
        }
    }

    /// the card's background (`secondarySystemGroupedBackground`)
    private static func card(isDark: Bool) -> RGB {
        rgb(isDark ? 0x1C1C1E : 0xFFFFFF)
    }

    static func color(_ metric: WeekdayMetric, step: Int, isDark: Bool) -> Color {
        let steps = ramp(metric, isDark: isDark)
        let value = rgb(steps[Swift.min(Swift.max(step, 0), steps.count - 1)])
        return Color(red: value.red, green: value.green, blue: value.blue)
    }

    /// the step's colour 55% of the way to the card
    static func dimmed(_ metric: WeekdayMetric, step: Int, isDark: Bool) -> Color {
        let steps = ramp(metric, isDark: isDark)
        let value = rgb(steps[Swift.min(Swift.max(step, 0), steps.count - 1)])
        let card = card(isDark: isDark)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * 0.55 }
        return Color(red: mix(value.red, card.red), green: mix(value.green, card.green), blue: mix(value.blue, card.blue))
    }

    static func hatch(isDark: Bool) -> Color {
        isDark ? Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255, opacity: 0.55)
            : Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.6)
    }

    /// A cell in its rectangle.
    static func draw(
        _ cell: Stat.Weekday.Heatmap.Cell,
        metric: WeekdayMetric,
        in rect: CGRect,
        cornerRadius: CGFloat,
        isDark: Bool,
        context: inout GraphicsContext
    ) {
        let shape = Path(roundedRect: rect, cornerRadius: cornerRadius)
        guard let step = cell.step else {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius),
                with: .color(Color(.separator)),
                lineWidth: 1
            )
            return
        }
        guard cell.isFew else {
            context.fill(shape, with: .color(color(metric, step: step, isDark: isDark)))
            return
        }
        context.fill(shape, with: .color(dimmed(metric, step: step, isDark: isDark)))
        // 1 pt stripes rising to the right, 3.5 pt apart across them
        var stripes = context
        stripes.clip(to: shape)
        let spacing: CGFloat = 3.5 * CGFloat(2).squareRoot()
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        stripes.stroke(path, with: .color(hatch(isDark: isDark)), lineWidth: 1)
    }
}

/// A cell of the key.
private struct WeekdaySwatch: View {
    let cell: Stat.Weekday.Heatmap.Cell
    let metric: WeekdayMetric
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            WeekdayCellStyle.draw(
                cell,
                metric: metric,
                in: CGRect(origin: .zero, size: size),
                cornerRadius: 2,
                isDark: isDark,
                context: &context
            )
        }
    }
}

/// Where the cells are: equal columns with a wider gap before the weekend, equal rows.
struct WeekdayGridLayout: Equatable {
    static let columnGap: CGFloat = 2
    /// added before the first weekend column
    static let weekendGap: CGFloat = 6
    static let rowGap: CGFloat = 1

    let width: CGFloat
    let columns: Int
    let rows: Int
    let rowHeight: CGFloat
    /// the first weekend column; `columns` without a weekend
    let weekendStart: Int

    private var hasWeekendGap: Bool {
        weekendStart > 0 && weekendStart < columns
    }

    var cellWidth: CGFloat {
        let gaps = Self.columnGap * CGFloat(Swift.max(columns - 1, 0)) + (hasWeekendGap ? Self.weekendGap : 0)
        return Swift.max((width - gaps) / CGFloat(Swift.max(columns, 1)), 1)
    }

    var height: CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(Swift.max(rows - 1, 0)) * Self.rowGap
    }

    func x(_ column: Int) -> CGFloat {
        CGFloat(column) * (cellWidth + Self.columnGap) + (hasWeekendGap && column >= weekendStart ? Self.weekendGap : 0)
    }

    func y(_ row: Int) -> CGFloat {
        CGFloat(row) * (rowHeight + Self.rowGap)
    }

    func rect(column: Int, row: Int) -> CGRect {
        CGRect(x: x(column), y: y(row), width: cellWidth, height: rowHeight)
    }

    /// A column's tap target, across the grid's whole height: its cells and the gaps beside them up to the middle of
    /// each (the weekend's too), so the columns' targets cover the grid with no gap between them.
    func target(_ column: Int) -> (minX: CGFloat, width: CGFloat) {
        let left = column > 0 ? (x(column - 1) + cellWidth + x(column)) / 2 : x(column)
        let right = column < columns - 1 ? (x(column) + cellWidth + x(column + 1)) / 2 : x(column) + cellWidth
        return (left, Swift.max(right - left, 0))
    }

    /// The row a point of a column falls in (a gap between rows: the row above it), kept inside the grid.
    func row(at y: CGFloat) -> Int {
        guard y.isFinite else { return 0 }
        return Swift.min(Swift.max(Int((y / (rowHeight + Self.rowGap)).rounded(.down)), 0), Swift.max(rows - 1, 0))
    }
}

/// The grid: the hours labelled on the left, the weekdays on top. A column per weekday, each a tap target (the row under
/// the finger).
private struct WeekdayHeatmapGrid: View {
    let weekday: Stat.Weekday
    let heatmap: Stat.Weekday.Heatmap
    /// by row
    let rowLabels: [String?]
    let isDark: Bool
    let selection: WeekdaySelection

    @ScaledMetric(relativeTo: .caption2) private var headerHeight: CGFloat = 18

    /// an hour a row: the whole day in a short card; a 3-hour block: 44 pt tall, the larger text sizes' tap target
    private var rowHeight: CGFloat {
        heatmap.hoursPerRow == 1 ? 15 : 44
    }

    private func label(_ row: Int) -> String {
        guard rowLabels.indices.contains(row) else { return "" }
        return rowLabels[row] ?? ""
    }

    var body: some View {
        let rows = heatmap.rowCount
        let gridHeight = CGFloat(rows) * rowHeight + CGFloat(Swift.max(rows - 1, 0)) * WeekdayGridLayout.rowGap
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing, spacing: WeekdayGridLayout.rowGap) {
                ForEach(0 ..< rows, id: \.self) { row in
                    Text(label(row))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: rowHeight)
                }
            }
            .padding(.top, headerHeight)

            GeometryReader { geometry in
                let layout = WeekdayGridLayout(
                    width: geometry.size.width,
                    columns: heatmap.cells.count,
                    rows: rows,
                    rowHeight: rowHeight,
                    weekendStart: heatmap.weekendStart
                )
                ZStack(alignment: .topLeading) {
                    ForEach(weekday.columns.indices, id: \.self) { column in
                        Text(weekday.columns[column].short)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: layout.cellWidth, height: headerHeight)
                            .offset(x: layout.x(column))
                    }
                    Group {
                        WeekdayCells(heatmap: heatmap, layout: layout, isDark: isDark)
                            .equatable()
                        WeekdaySelectionBox(selection: selection, columns: weekday.columns, heatmap: heatmap, layout: layout)
                        WeekdayColumnTargets(weekday: weekday, heatmap: heatmap, layout: layout, selection: selection)
                    }
                    .offset(y: headerHeight)
                }
            }
            .frame(height: headerHeight + gridHeight)
        }
    }
}

/// The cells, drawn at once. Its inputs don't change while the selection moves, so `.equatable()` skips its body.
private struct WeekdayCells: View, Equatable {
    let heatmap: Stat.Weekday.Heatmap
    let layout: WeekdayGridLayout
    let isDark: Bool

    nonisolated static func == (lhs: WeekdayCells, rhs: WeekdayCells) -> Bool {
        lhs.isDark == rhs.isDark && lhs.layout == rhs.layout && lhs.heatmap == rhs.heatmap
    }

    var body: some View {
        let heatmap = self.heatmap
        let layout = self.layout
        let isDark = self.isDark
        Canvas { context, _ in
            let cornerRadius: CGFloat = heatmap.hoursPerRow == 1 ? 2 : 4
            for (column, cells) in heatmap.cells.enumerated() {
                for (row, cell) in cells.enumerated() {
                    WeekdayCellStyle.draw(
                        cell,
                        metric: heatmap.metric,
                        in: layout.rect(column: column, row: row),
                        cornerRadius: cornerRadius,
                        isDark: isDark,
                        context: &context
                    )
                }
            }
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }
}

/// The picked cell's outline, a little outside it.
private struct WeekdaySelectionBox: View {
    let selection: WeekdaySelection
    let columns: [Stat.Weekday.Column]
    let heatmap: Stat.Weekday.Heatmap
    let layout: WeekdayGridLayout

    var body: some View {
        if let weekday = selection.weekday, let column = columns.firstIndex(where: { $0.weekday == weekday }) {
            let rect = layout.rect(column: column, row: selection.hour / Swift.max(heatmap.hoursPerRow, 1))
                .insetBy(dx: -2, dy: -2)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.primary, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }
}

/// A target per weekday column, over its cells and the gaps beside them: a tap picks the row under the finger.
private struct WeekdayColumnTargets: View {
    let weekday: Stat.Weekday
    let heatmap: Stat.Weekday.Heatmap
    let layout: WeekdayGridLayout
    let selection: WeekdaySelection

    var body: some View {
        let hoursPerRow = Swift.max(heatmap.hoursPerRow, 1)
        ForEach(weekday.columns.indices, id: \.self) { column in
            let day = weekday.columns[column]
            let target = layout.target(column)
            Rectangle()
                .fill(Color.clear)
                .frame(width: target.width, height: layout.height)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            selection.select(weekday: day.weekday, hour: layout.row(at: value.location.y) * hoursPerRow)
                        }
                )
                .offset(x: target.minX)
        }
    }
}
