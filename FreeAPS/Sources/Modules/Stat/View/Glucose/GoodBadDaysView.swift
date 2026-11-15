import Charts
import SwiftUI

/// Good & bad days: the period's days scored by GRI, the best third against the worst. The two groups'
/// profiles overlaid on the AGP's frame with the stretches where the medians differ most, the glucose rows, what was
/// different on those days, and the groups' days listed in place (a day opens the Day tab).
struct GoodBadDaysView: View {
    let model: Stat.GoodBadDays
    let selection: GoodBadDaysSelection
    /// a day of a list: the Day tab on it (`Stat.StateModel.openDay`)
    let openDay: (Date) -> Void

    @State private var griShown = false

    var body: some View {
        let content = model.content
        VStack(spacing: 16) {
            StatsCard { comparisonCard(content) }
            if content.isComparable {
                StatsCard { glucoseCard(content) }
            }
            if content.factorSections.isNotEmpty {
                StatsCard { factorCard(content) }
            }
            StatsCard { daysCard(content) }
        }
        .sheet(isPresented: $griShown) {
            GRIInfoSheet(content: model.griSheet)
        }
    }

    // MARK: - The comparison

    @ViewBuilder private func comparisonCard(_ content: Stat.GoodBadDays.Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Good vs bad days")
                .statsSectionTitle()
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                StatsDateRange(model.dateRange)
                if content.isLimited {
                    LimitedDataMarker(note: model.limitedNote)
                }
            }
            Button {
                griShown = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, -11)
            .padding(.trailing, -12)
        }

        VStack(alignment: .leading, spacing: 3) {
            Text(content.counts)
                .font(.subheadline)
                .monospacedDigit()
            ForEach(content.lines, id: \.self) { line in
                Text(line)
                    .statsFootnote()
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Text(Stat.GoodBadDays.griCaption)
            .statsNote()

        GoodBadDaysChart(plot: model.plot, content: content, selection: selection)

        if let message = content.message {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.title)
                    .font(.subheadline.weight(.semibold))
                Text(message.detail)
                    .statsNote()
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        } else {
            if let caption = content.caption {
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            GoodBadDaysTime(plot: model.plot, content: content, selection: selection)
        }

        GoodBadDaysLegend(content: content, range: model.legendRange)

        Text(content.profileNote)
            .statsNote()
    }

    // MARK: - Glucose

    @ViewBuilder private func glucoseCard(_ content: Stat.GoodBadDays.Content) -> some View {
        StatsCardHeader(title: "Glucose on those days") {
            Text("median (IQR)")
                .statsFootnote()
        }

        Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 0) {
            GridRow {
                Color.clear
                    .frame(width: 0, height: 0)
                    .gridColumnAlignment(.leading)
                columnHeader(content.reference)
                columnHeader(content.compared)
                Text("Difference")
                    .statsColumnHeader()
            }
            ForEach(content.glucoseRows) { row in
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                GridRow(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                        if let detail = row.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    cell(row.reference)
                    cell(row.compared)
                    Text(row.difference)
                        .font(.subheadline.weight(.semibold))
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 6)
            }
        }

        Text(model.glucoseNote)
            .statsNote()
    }

    private func columnHeader(_ group: Stat.GoodBadDays.Group) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(group.short)
            Text(String(format: NSLocalizedString("%d days", comment: "Statistics AGP, the days of the period"), group.dayCount))
                .fontWeight(.regular)
        }
        .statsColumnHeader()
    }

    private func cell(_ cell: Stat.GoodBadDays.GlucoseRow.Cell) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(cell.value)
                .font(.subheadline)
            Text(cell.range)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Factors

    @ViewBuilder private func factorCard(_ content: Stat.GoodBadDays.Content) -> some View {
        StatsCardHeader(title: "What was different on those days") {
            Text("median (IQR)")
                .statsFootnote()
        }
        Text(content.factorIntro)
            .statsNote()

        ForEach(content.factorSections) { section in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                    if let note = section.note {
                        Text(note)
                            .statsNote()
                    }
                    if let unavailable = section.unavailable {
                        Text(unavailable)
                            .statsNote()
                    }
                }
                .padding(.bottom, 4)
                ForEach(section.rows) { row in
                    Divider()
                    factorRow(row)
                }
            }
        }

        Text("Differences between these groups of days, not causes. Small groups differ by chance.")
            .statsNote()
    }

    /// Two lines at phone width: the name and the difference, then both groups' values.
    private func factorRow(_ row: Stat.GoodBadDays.FactorRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(row.difference)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(row.direction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            Text(row.values)
                .statsNote()
                .monospacedDigit()
            if let note = row.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
    }

    // MARK: - Days

    @ViewBuilder private func daysCard(_ content: Stat.GoodBadDays.Content) -> some View {
        StatsCardHeader(title: "Days") {
            Text(model.periodLabel)
                .statsFootnote()
        }
        VStack(spacing: 0) {
            GoodBadDaysGroupList(
                group: content.reference,
                selection: selection,
                openDay: openDay
            )
            Divider()
            GoodBadDaysGroupList(
                group: content.compared,
                selection: selection,
                openDay: openDay
            )
        }
        Text("Tap a day to open it in Day. A run of bad days in one stretch can be a settings change, not the factors above.")
            .statsNote()
    }
}

// MARK: - Style

/// The groups' colours: the best third in the in-range green, the worst third in the data indigo (the CGM topic's).
/// Each line a darker step of its hue in light mode, for contrast on the card; the compared median dashed, so no colour
/// stands alone.
enum GoodBadDaysStyle {
    /// the bands' opacity
    static func bandOpacity(isDark: Bool) -> Double {
        isDark ? 0.34 : 0.28
    }

    static func band(_ side: GoodBadDaysSelection.Side) -> Color {
        switch side {
        case .reference: return GlucoseBand.inRange.color
        case .compared: return dynamic(light: 0x7278E4, dark: 0x878FF6)
        }
    }

    static func line(_ side: GoodBadDaysSelection.Side) -> Color {
        switch side {
        case .reference: return dynamic(light: 0x2A8A02, dark: 0x3FBD12)
        case .compared: return dynamic(light: 0x4E4AC8, dark: 0x878FF6)
        }
    }

    /// the compared median's dash; the reference's is solid
    static func dash(_ side: GoodBadDaysSelection.Side) -> [CGFloat] {
        side == .compared ? [6, 4] : []
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        return Color(UIColor { traits in color(traits.userInterfaceStyle == .dark ? dark : light) })
    }
}

/// A group's key: its band with its median across it.
private struct GoodBadDaysSwatch: View {
    let side: GoodBadDaysSelection.Side

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(GoodBadDaysStyle.band(side).opacity(GoodBadDaysStyle.bandOpacity(isDark: colorScheme == .dark)))
                .frame(width: 16, height: 10)
            Path { path in
                path.move(to: CGPoint(x: 1, y: 5))
                path.addLine(to: CGPoint(x: 15, y: 5))
            }
            .stroke(
                GoodBadDaysStyle.line(side),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: side == .compared ? [5, 3] : [])
            )
            .frame(width: 16, height: 10)
        }
    }
}

// MARK: - Chart

/// The two groups' profiles with the selected time: the marks (`GoodBadDaysMarks`, equatable) aren't re-rendered when
/// the selection moves.
private struct GoodBadDaysChart: View {
    let plot: Stat.GoodBadDays.Plot
    let content: Stat.GoodBadDays.Content
    let selection: GoodBadDaysSelection

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GoodBadDaysMarks(plot: plot, content: content, selection: selection, isDark: colorScheme == .dark)
            .equatable()
            .frame(height: StatsChartMetrics.curvePlotHeight)
    }
}

/// The highlighted stretches behind, the AGP's frame, both groups' 25–75% bands and medians (the compared one dashed),
/// as segments between the bins without data.
private struct GoodBadDaysMarks: View, Equatable {
    let plot: Stat.GoodBadDays.Plot
    let content: Stat.GoodBadDays.Content
    let selection: GoodBadDaysSelection
    let isDark: Bool

    nonisolated static func == (lhs: GoodBadDaysMarks, rhs: GoodBadDaysMarks) -> Bool {
        lhs.selection === rhs.selection && lhs.isDark == rhs.isDark && lhs.plot == rhs.plot && lhs.content == rhs.content
    }

    /// A stretch drawn: its id, its minutes.
    private struct Stretch: Identifiable {
        let id: Int
        let minutes: Range<Int>
    }

    var body: some View {
        let plot = self.plot
        let content = self.content
        let selection = self.selection
        let opacity = GoodBadDaysStyle.bandOpacity(isDark: isDark)
        let stretches = content.highlights.enumerated().map { Stretch(id: $0.offset, minutes: $0.element) }
        let groups = [content.reference, content.compared].filter(\.isShown)
        Chart {
            ForEach(stretches) { stretch in
                RectangleMark(
                    xStart: .value("Start", stretch.minutes.lowerBound),
                    xEnd: .value("End", stretch.minutes.upperBound),
                    yStart: .value("Bottom", Double(plot.axis.lowerBound)),
                    yEnd: .value("Top", Double(plot.axis.upperBound))
                )
                .foregroundStyle(StatsChartMetrics.highlight(isDark: isDark))
            }

            AGPFrameMarks(floor: plot.axis.lowerBound, dashed: plot.dashed)

            ForEach(groups, id: \.name) { group in
                ForEach(group.points, id: \.minute) { point in
                    AreaMark(
                        x: .value("Time", point.minute),
                        yStart: .value("25th percentile", point.p25),
                        yEnd: .value("75th percentile", point.p75),
                        series: .value("Segment", "\(group.name) band \(point.segment)")
                    )
                    .foregroundStyle(GoodBadDaysStyle.band(group.side).opacity(opacity))
                }
            }

            AGPFrameMarks.Edges(edges: plot.edges)

            ForEach(groups, id: \.name) { group in
                ForEach(group.points, id: \.minute) { point in
                    LineMark(
                        x: .value("Time", point.minute),
                        y: .value("Median", point.p50),
                        series: .value("Segment", "\(group.name) median \(point.segment)")
                    )
                    .lineStyle(StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: GoodBadDaysStyle.dash(group.side)
                    ))
                    .foregroundStyle(GoodBadDaysStyle.line(group.side))
                }
            }
        }
        .agpFrameAxes(axis: plot.axis, xTicks: plot.xTicks, yLabels: plot.yLabels)
        // the picking as the AGP's (`ChartPicker`): the minute under the finger into the selection, which nothing here
        // reads
        .chartOverlay { proxy in
            ZStack {
                ChartPicker(proxy: proxy) { (minute: Int) in
                    selection.select(bin: GlucoseStatsEngine.agpBin(atMinute: minute, binCount: plot.binCount))
                }
                GoodBadDaysSelectionLayer(plot: plot, content: content, selection: selection, proxy: proxy)
            }
        }
    }
}

/// The selected time: a rule down through it and each shown group's median dot.
private struct GoodBadDaysSelectionLayer: View {
    let plot: Stat.GoodBadDays.Plot
    let content: Stat.GoodBadDays.Content
    let selection: GoodBadDaysSelection
    let proxy: ChartProxy

    var body: some View {
        let bin = selection.bin(opening: content.openingBin)
        GeometryReader { geometry in
            if bin < plot.binCount, let plotFrame = proxy.plotFrame.map({ geometry[$0] }),
               let x = proxy.position(forX: plot.minute(ofBin: bin))
            {
                let centerX = plotFrame.minX + x
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: plotFrame.minY - 2))
                    path.addLine(to: CGPoint(x: centerX, y: plotFrame.maxY))
                }
                .stroke(Color.secondary, lineWidth: 1)

                ForEach([content.reference, content.compared].filter(\.isShown), id: \.name) { group in
                    if let median = group.plottedMedians[bin], let y = proxy.position(forY: median) {
                        Circle()
                            .fill(GoodBadDaysStyle.line(group.side))
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            .frame(width: 10, height: 10)
                            .position(x: centerX, y: plotFrame.minY + y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The time picked

/// The selected time, 30 minutes back or on (around midnight too), and both groups' 25%, median and 75% then.
private struct GoodBadDaysTime: View {
    let plot: Stat.GoodBadDays.Plot
    let content: Stat.GoodBadDays.Content
    let selection: GoodBadDaysSelection

    /// 30 minutes
    private static let step = 30 / GlucoseStatsEngine.agpBinMinutes

    var body: some View {
        let bin = Swift.min(selection.bin(opening: content.openingBin), plot.binCount - 1)
        if bin >= 0 {
            StatsStepper(
                title: plot.binStarts[bin],
                subtitle: NSLocalizedString("Selected time", comment: "Statistics AGP, the time picked"),
                canGoBack: true,
                canGoForward: true,
                back: { selection.select(bin: GlucoseStatsEngine.agpStep(bin, by: -Self.step, binCount: plot.binCount)) },
                forward: { selection.select(bin: GlucoseStatsEngine.agpStep(bin, by: Self.step, binCount: plot.binCount)) }
            )
            .padding(.horizontal, -8)

            Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 0) {
                GridRow {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(plot.binTimes[bin])
                        Text(plot.unit)
                            .fontWeight(.regular)
                    }
                    .gridColumnAlignment(.leading)
                    Text(StatsFormatting.percent(25))
                    Text("Median")
                    Text(StatsFormatting.percent(75))
                }
                .statsColumnHeader()
                ForEach([content.reference, content.compared], id: \.name) { group in
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        HStack(spacing: 6) {
                            GoodBadDaysSwatch(side: group.side)
                            Text(group.name)
                                .font(.subheadline.weight(.semibold))
                        }
                        let values = group.readouts[bin]
                        Text(values?[0] ?? "–")
                        Text(values?[1] ?? "–")
                            .fontWeight(.bold)
                        Text(values?[2] ?? "–")
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

// MARK: - Legend

/// The colour key: both groups (their days), the range, the stretches.
private struct GoodBadDaysLegend: View {
    let content: Stat.GoodBadDays.Content
    let range: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shown = [content.reference, content.compared].filter(\.isShown)
        FlowRows(spacing: 14, lineSpacing: 6) {
            ForEach(shown, id: \.name) { group in
                item(group.title) {
                    GoodBadDaysSwatch(side: group.side)
                }
            }
            item(range) {
                Rectangle().fill(GlucoseBand.inRange.color).frame(width: 16, height: 2)
            }
            if content.highlights.isNotEmpty {
                item(NSLocalizedString("Medians differ most", comment: "Statistics Good & bad days legend: the stretches")) {
                    Rectangle()
                        .fill(StatsChartMetrics.highlight(isDark: colorScheme == .dark))
                        .frame(width: 16, height: 12)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func item<Swatch: View>(_ label: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(label)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Its items in rows, left to right, wrapping to the next row where one doesn't fit.
private struct FlowRows: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = self.rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(Swift.max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, current.indices.isNotEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = Swift.max(current.height, size.height)
            current.indices.append(index)
        }
        if current.indices.isNotEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - Days

/// A group's row, which lists its days in place, newest first: the date, the TIR, the band bar, GRI and its zone. A day
/// opens the Day tab.
private struct GoodBadDaysGroupList: View {
    let group: Stat.GoodBadDays.Group
    let selection: GoodBadDaysSelection
    let openDay: (Date) -> Void

    var body: some View {
        let isOpen = selection.open.contains(group.side) && group.days.isNotEmpty
        VStack(spacing: 0) {
            Button {
                selection.toggle(group.side)
            } label: {
                HStack(spacing: 10) {
                    GoodBadDaysSwatch(side: group.side)
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Text(
                        isOpen ? NSLocalizedString("newest first", comment: "Statistics Good & bad days: a day list's order") :
                            group.span
                    )
                    .statsFootnote()
                    .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(group.days.isEmpty)

            if isOpen {
                ForEach(group.days) { day in
                    Divider()
                    Button {
                        openDay(day.id)
                    } label: {
                        dayRow(day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dayRow(_ day: Stat.GoodBadDays.Day) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(day.title)
                    .font(.subheadline)
                Text(day.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(minWidth: 96, alignment: .leading)
            BandBar(segments: day.segments, cornerRadius: 3)
                .frame(height: 10)
            Text(day.gri)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 26)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
