import SwiftUI

struct WeekdayView: View {
    let weekday: Stat.Weekday
    let selection: WeekdaySelection

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// the gutter of the bars' levels and the table's row names
    @ScaledMetric(relativeTo: .caption) private var gutter: CGFloat = 58
    /// the summary table's number columns
    @ScaledMetric(relativeTo: .subheadline) private var summaryColumn: CGFloat = 76

    /// the larger text sizes: the bars as a list, the heatmap by 3-hour blocks
    private var largeText: Bool {
        dynamicTypeSize > .large
    }

    private var hoursPerRow: Int {
        largeText ? GlucoseStatsEngine.weekdayBlockHours : 1
    }

    /// The bars, the heatmap, the picked cell, then the workdays against the weekend.
    var body: some View {
        VStack(spacing: 16) {
            StatsCard { barsCard }
            StatsCard {
                WeekdayHeatmapCard(weekday: weekday, selection: selection, hoursPerRow: hoursPerRow)
            }
            WeekdayReadoutCard(weekday: weekday, selection: selection, hoursPerRow: hoursPerRow)
            if let workdays = weekday.workdays, let weekend = weekday.weekend {
                StatsCard { summaryCard(workdays, weekend) }
            }
        }
    }

    // MARK: - In range by weekday

    @ViewBuilder private var barsCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                barsTitle
                Spacer(minLength: 8)
                countNote
            }
            VStack(alignment: .leading, spacing: 2) {
                barsTitle
                countNote
            }
        }

        if largeText {
            weekdayList
        } else {
            WeekdayBarsTable(bars: weekday.bars, rows: weekday.tableRows, gutter: gutter)
                .equatable()
        }

        BandLegend(bands: weekday.legendBands)

        Text(weekday.barsFootnote)
            .statsNote()
    }

    private var barsTitle: some View {
        Text("In range by weekday")
            .statsSectionTitle()
    }

    private var countNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(weekday.countNote)
                .statsFootnote()
                .monospacedDigit()
            if let limitedNote = weekday.limitedNote {
                LimitedDataMarker(note: limitedNote)
            }
        }
    }

    /// The larger text sizes: a weekday a row, its band bar and in range, its other numbers under them.
    private var weekdayList: some View {
        VStack(spacing: 0) {
            ForEach(Array(weekday.weekdayRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                        BandBar(segments: row.segments, cornerRadius: 4)
                            .frame(height: 12)
                        Text(row.inRange)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(row.line)
                        .statsFootnote()
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Weekdays vs weekends

    @ViewBuilder private func summaryCard(_ workdays: Stat.Weekday.DayGroup, _ weekend: Stat.Weekday.DayGroup) -> some View {
        StatsCardHeader(title: "Weekdays vs weekends", range: weekday.dateRange)

        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                WeekdayGroupTile(group: workdays, limitedNote: weekday.limitedNote)
                WeekdayGroupTile(group: weekend, limitedNote: weekday.limitedNote)
            }
        }
        .fixedSize(horizontal: false, vertical: true)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(workdays.name)
                    .frame(width: summaryColumn, alignment: .trailing)
                Text(weekend.name)
                    .frame(width: summaryColumn, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.bottom, 4)
            ForEach(weekday.summaryRows) { row in
                Divider()
                HStack(spacing: 0) {
                    Text(row.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.workdays)
                        .fontWeight(.semibold)
                        .frame(width: summaryColumn, alignment: .trailing)
                    Text(row.weekend)
                        .fontWeight(.semibold)
                        .frame(width: summaryColumn, alignment: .trailing)
                }
                .font(.subheadline)
                .monospacedDigit()
                .frame(minHeight: 40)
            }
        }

        Text(weekday.summaryFootnote)
            .statsNote()
    }
}

/// The workdays or the weekend: in range, its days, its band bar; the limited mark with limited data.
private struct WeekdayGroupTile: View {
    let group: Stat.Weekday.DayGroup
    let limitedNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(group.inRange)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let limitedNote {
                    LimitedDataMarker(note: limitedNote, font: .footnote)
                }
            }
            Text(group.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            BandBar(segments: group.segments, cornerRadius: 4)
                .frame(height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemGroupedBackground)))
    }
}

// MARK: - The bars and their numbers

/// The bars over the table of their numbers, in the same columns: the gutter (the levels, the rows' names), then a
/// column per weekday (its bar and its numbers). `.equatable()` skips its body while its inputs are the same.
private struct WeekdayBarsTable: View, Equatable {
    let bars: Stat.Weekday.Bars
    let rows: [Stat.Weekday.TableRow]
    let gutter: CGFloat

    nonisolated static func == (lhs: WeekdayBarsTable, rhs: WeekdayBarsTable) -> Bool {
        lhs.gutter == rhs.gutter && lhs.bars == rhs.bars && lhs.rows == rhs.rows
    }

    static let plotHeight: CGFloat = 170
    static let barWidth: CGFloat = 24
    /// between the plot and the table
    static let spacing: CGFloat = 8
    static let rowHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            gutterColumn
                .frame(width: gutter)
            ForEach(bars.parts.indices, id: \.self) { column in
                VStack(spacing: 0) {
                    bar(bars.parts[column])
                        .frame(height: Self.plotHeight, alignment: .bottom)
                    Color.clear
                        .frame(height: Self.spacing)
                    ForEach(rows) { row in
                        Text(row.values.indices.contains(column) ? row.values[column] : "")
                            .fontWeight(Self.weight(row))
                            .foregroundStyle(row.isSecondary ? Color.secondary : Color.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.rowHeight)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .background(alignment: .topLeading) { lines }
    }

    /// In range in bold, the weekdays' row semibold.
    private static func weight(_ row: Stat.Weekday.TableRow) -> Font.Weight {
        if row.isEmphasized {
            return .bold
        }
        return row.isSecondary && row.name.isEmpty ? .semibold : .regular
    }

    /// The levels at their gridlines, then the rows' names.
    private var gutterColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ForEach(Stat.Weekday.Bars.levels.indices, id: \.self) { index in
                    Text(bars.levelLabels.indices.contains(index) ? bars.levelLabels[index] : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(height: 14)
                        .offset(y: Self.plotHeight * CGFloat(1 - Stat.Weekday.Bars.levels[index]) - 7)
                }
            }
            .padding(.trailing, 9)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: Self.plotHeight, alignment: .top)
            Color.clear
                .frame(height: Self.spacing)
            ForEach(rows) { row in
                Text(row.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.rowHeight)
            }
        }
    }

    /// A 100% bar, the bands from very low at the bottom up.
    @ViewBuilder private func bar(_ parts: [Stat.Weekday.Bars.Part]) -> some View {
        VStack(spacing: 0) {
            ForEach(parts.reversed()) { part in
                Rectangle()
                    .fill(part.band.color)
                    .frame(height: Self.plotHeight * CGFloat(part.upper - part.lower))
            }
        }
        .frame(width: Self.barWidth)
    }

    /// The plot's gridlines (from the levels' labels on) and the table's row separators (none above the weekdays).
    private var lines: some View {
        Canvas { context, size in
            var grid = Path()
            for level in Stat.Weekday.Bars.levels {
                let y = Self.plotHeight * CGFloat(1 - level)
                grid.move(to: CGPoint(x: gutter - 4, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(Color(.separator)), lineWidth: 0.5)
            var separators = Path()
            for row in rows.indices.dropFirst() {
                let y = Self.plotHeight + Self.spacing + Self.rowHeight * CGFloat(row)
                separators.move(to: CGPoint(x: 0, y: y))
                separators.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(separators, with: .color(Color(.separator)), lineWidth: 0.5)
        }
    }
}

// MARK: - The picked cell

/// The stepper through the hours (around midnight too) on the picked weekday, the cell's number as the metric shows it
/// against the usual, and its bands. Nothing until a cell is picked. Re-rendered when the selection moves, the rest of
/// the view isn't.
private struct WeekdayReadoutCard: View {
    let weekday: Stat.Weekday
    let selection: WeekdaySelection
    let hoursPerRow: Int

    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34

    var body: some View {
        if let picked = selection.weekday,
           let readout = weekday.readout(
               weekday: picked,
               hour: selection.hour,
               hoursPerRow: hoursPerRow,
               metric: selection.metric
           )
        {
            StatsCard {
                StatsStepper(
                    title: readout.title,
                    subtitle: readout.subtitle,
                    canGoBack: true,
                    canGoForward: true,
                    back: { selection.step(by: -1, hoursPerRow: hoursPerRow) },
                    forward: { selection.step(by: 1, hoursPerRow: hoursPerRow) }
                )

                if readout.hasData {
                    value(readout)
                    BandBar(segments: readout.segments, cornerRadius: 4)
                        .frame(height: 12)
                    VStack(spacing: 0) {
                        StatsDividedRows(readout.rows) { row in
                            StatsBandRowView(row: row)
                        }
                    }
                    if readout.isFew {
                        note(readout.fewNote)
                    }
                    note(readout.usualNote)
                } else {
                    Text("No readings")
                        .statsEmptyNote()
                }
            }
        }
    }

    /// The number, its unit and the few-readings mark; the usual at the trailing end, under them when it doesn't fit.
    private func value(_ readout: Stat.Weekday.Readout) -> some View {
        let number = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(readout.value)
                .font(.system(size: valueSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
            Text(readout.unit)
                .font(.subheadline.weight(.semibold))
            if readout.isFew {
                // the note is the text under the bands
                LimitedDataMarker(note: nil)
            }
        }
        let usual = Text(readout.usual)
            .statsFootnote()
            .monospacedDigit()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                number
                Spacer(minLength: 8)
                usual
            }
            VStack(alignment: .leading, spacing: 2) {
                number
                usual
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .statsNote()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
