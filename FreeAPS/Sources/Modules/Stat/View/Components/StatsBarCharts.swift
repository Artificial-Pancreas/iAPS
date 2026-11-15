import Charts
import SwiftUI

// The bar charts' shared parts: their styles, the split bar, the legend, the rows and the headers. The charts are in
// StatsDayBars.swift (day by day, scrolling through the period) and StatsHourBars.swift (by hour), each a stack of parts
// in the chart's own units (%, U, g).

/// How a part of a stacked bar is filled: a colour, and an outline for a light fill (the carb equivalents).
struct StatsBarStyle: Equatable, Sendable {
    let fill: Color
    var stroke: Color?
}

/// One bar split into parts (the insulin per day into basal, SMB and bolus): proportional widths with 2 pt gaps,
/// every nonzero part at least 4 pt wide (`widths`).
struct StatsSplitBar: View {
    struct Segment: Equatable, Identifiable {
        let id: Int
        let style: StatsBarStyle
        let fraction: Double
    }

    /// the nonzero parts
    let segments: [Segment]
    var cornerRadius: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            let widths = Self.widths(segments.map(\.fraction), total: geometry.size.width)
            HStack(spacing: Self.gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    Rectangle()
                        .fill(segment.style.fill)
                        .frame(width: widths[index])
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    static let gap: CGFloat = 2
    static let minimumWidth: CGFloat = 4

    /// Proportional widths, the ones below the minimum raised to it (and the others scaled down to make room).
    static func widths(_ fractions: [Double], total: CGFloat) -> [CGFloat] {
        guard !fractions.isEmpty else { return [] }
        let available = max(0, total - gap * CGFloat(fractions.count - 1))
        var fixed = Set<Int>()
        while true {
            let free = available - minimumWidth * CGFloat(fixed.count)
            let freeFraction = fractions.indices.filter { !fixed.contains($0) }.reduce(0) { $0 + fractions[$1] }
            let widths = fractions.indices.map { index -> CGFloat in
                guard !fixed.contains(index) else { return minimumWidth }
                return freeFraction > 0 ? max(0, free) * CGFloat(fractions[index] / freeFraction) : 0
            }
            let tooNarrow = fractions.indices.filter { !fixed.contains($0) && widths[$0] < minimumWidth }
            guard !tooNarrow.isEmpty, fixed.count + tooNarrow.count < fractions.count else { return widths }
            fixed.formUnion(tooNarrow)
        }
    }

    /// The nonzero values as segments, in order (their index is their id).
    static func segments(_ values: [Double], styles: [StatsBarStyle]) -> [Segment] {
        let total = values.reduce(0) { $0 + Swift.max($1, 0) }
        guard total > 0 else { return [] }
        return zip(values.indices, zip(values, styles)).compactMap { index, pair in
            pair.0 > 0 ? Segment(id: index, style: pair.1, fraction: pair.0 / total) : nil
        }
    }
}

/// The colour key of a chart: swatches, a dashed line (an average), a step line (the scheduled basal), a tick (a usual
/// by hour), a solid line (a reference), or a note.
struct StatsChartLegend: View {
    enum Key: Equatable {
        case swatch(StatsBarStyle)
        case dashed
        case step
        /// a short grey bar (the usual by hour, `StatsHourBars.UsualTick`)
        case tick
        /// a solid line (a reference on the day chart, `StatsDayBars.Rule`)
        case rule(Color)
        /// the dot above a partial day
        case dot
        /// text alone ("U per hour")
        case none
    }

    struct Item: Equatable, Identifiable {
        let id: Int
        let key: Key
        let title: String
    }

    let items: [Item]

    var body: some View {
        // wrapping, not a grid of fixed columns: "Carbs per day, by entry time" and "Average 29.5 U" aren't short
        StatsFlowLayout(horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    StatsKeyGlyph(key: item.key, size: .legend)
                    Text(item.title)
                        .lineLimit(1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Its subviews left to right at their own widths, wrapping onto the next line when they don't fit (a legend).
struct StatsFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = self.rows(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + verticalSpacing * CGFloat(Swift.max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let width = Swift.min(size.width, bounds.width)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: width, height: size.height)
                )
                x += width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let width = Swift.min(size.width, maxWidth)
            let needed = row.indices.isEmpty ? width : row.width + horizontalSpacing + width
            if needed > maxWidth, row.indices.isNotEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? width : row.width + horizontalSpacing + width
            row.height = Swift.max(row.height, size.height)
            row.indices.append(index)
        }
        if row.indices.isNotEmpty {
            rows.append(row)
        }
        return rows
    }
}

/// The y axis of a bar chart: from 0 to the maximum rounded up to a whole `unit` (at least one), with gridlines at
/// `divisions` equal steps.
enum StatsBarAxis {
    static func levels(maximum: Double, unit: Double, divisions: Int) -> [Double] {
        let top = Swift.max(unit, (Swift.max(maximum, 0) / unit).rounded(.up) * unit)
        let count = Swift.max(divisions, 1)
        return (0 ... count).map { top * Double($0) / Double(count) }
    }
}

/// A row of a readout card: a key (a swatch, the step line, or none), a name and a value.
struct StatsValueRow: View {
    let key: StatsChartLegend.Key
    let name: String
    let value: String
    var emphasized = false

    var body: some View {
        HStack(spacing: 10) {
            StatsKeyGlyph(key: key, size: .row)
                .frame(width: 14)
            Text(name)
                .font(.subheadline.weight(emphasized ? .semibold : .regular))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(emphasized ? .semibold : .regular))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 40)
    }
}

/// A key's glyph (`StatsChartLegend.Key`), at a legend's size (an 8 pt swatch, 16 pt lines) or a readout row's (a
/// 12 pt swatch, 14 pt lines; a row draws no rule or dot, their room left empty).
struct StatsKeyGlyph: View {
    enum Size {
        /// `StatsChartLegend`'s
        case legend
        /// a row's (`StatsValueRow`, `StatsPartRows`)
        case row
    }

    let key: StatsChartLegend.Key
    let size: Size

    var body: some View {
        switch size {
        case .legend:
            legend
        case .row:
            row
        }
    }

    @ViewBuilder private var legend: some View {
        switch key {
        case let .swatch(style):
            Self.swatch(style, side: 8, cornerRadius: 2)
        case .dashed:
            Self.dashed(width: 16, height: 9)
        case .step:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6.5))
                path.addLine(to: CGPoint(x: 8, y: 6.5))
                path.addLine(to: CGPoint(x: 8, y: 2.5))
                path.addLine(to: CGPoint(x: 16, y: 2.5))
            }
            .stroke(Color.primary, lineWidth: 1.5)
            .frame(width: 16, height: 9)
        case .tick:
            Self.tick(width: 14)
                .frame(width: 16, height: 9)
        case let .rule(color):
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4.5))
                path.addLine(to: CGPoint(x: 16, y: 4.5))
            }
            .stroke(color, lineWidth: 2)
            .frame(width: 16, height: 9)
        case .dot:
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var row: some View {
        switch key {
        case let .swatch(style):
            Self.swatch(style, side: 12, cornerRadius: 3)
        case .step:
            Rectangle()
                .fill(Color.primary)
                .frame(width: 14, height: 2)
        case .dashed:
            Self.dashed(width: 14, height: 2)
        case .tick:
            Self.tick(width: 14)
        case .dot,
             .none,
             .rule:
            Color.clear
                .frame(width: 12, height: 12)
        }
    }

    /// A rounded square in the style's fill, its outline inside the edge (a light fill's).
    private static func swatch(_ style: StatsBarStyle, side: CGFloat, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(style.fill)
            .overlay {
                if let stroke = style.stroke {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(stroke, lineWidth: 1)
                }
            }
            .frame(width: side, height: side)
    }

    /// A short solid grey bar (a usual by hour), as the chart's tick.
    private static func tick(width: CGFloat) -> some View {
        Rectangle()
            .fill(StatsChartMetrics.usualTick)
            .frame(width: width, height: StatsChartMetrics.usualTickThickness)
    }

    /// A dashed line across the middle (an average, a usual).
    private static func dashed(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addLine(to: CGPoint(x: width, y: height / 2))
        }
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        .frame(width: width, height: height)
    }
}

// MARK: - Shared by the topics and Home

/// Amounts (U, g) as the locale writes numbers: every topic's, and Home's cards.
enum StatsAmount {
    /// `digits` decimals (a range: as few as needed), rounded half away from zero
    static func number(_ value: Double, digits: ClosedRange<Int>) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).rounded(rule: .toNearestOrAwayFromZero))
    }

    /// "38.2": exactly `digits` decimals
    static func number(_ value: Double, digits: Int) -> String {
        number(value, digits: digits ... digits)
    }

    /// "17.1 U"
    static func units(_ value: Double, digits: Int) -> String {
        withUnits(number(value, digits: digits))
    }

    /// "%@ U": a number already formatted, with the unit
    static func withUnits(_ number: String) -> String {
        String(format: NSLocalizedString("%@ U", comment: "Statistics Insulin: an amount of insulin"), number)
    }

    /// "38.2 U per day"
    static func perDayUnits(_ number: String) -> String {
        String(format: NSLocalizedString("%@ U per day", comment: "Statistics Insulin: the TDD"), number)
    }

    /// "45 g", "12.5 g"
    static func grams(_ value: Double, digits: ClosedRange<Int> = 0 ... 1) -> String {
        String(
            format: NSLocalizedString("%@ g", comment: "Statistics Meals: an amount in grams"),
            number(value, digits: digits)
        )
    }

    static func grams(_ value: Double, digits: Int) -> String {
        grams(value, digits: digits ... digits)
    }
}

/// The parts of the insulin, stacked from the bottom in the charts: the Insulin tab's and the Patches'.
enum InsulinPart: Int, CaseIterable, Sendable {
    case basal
    case smb
    case bolus

    var name: String {
        switch self {
        case .basal: return NSLocalizedString("Basal", comment: "Statistics Insulin: the basal insulin")
        case .smb: return NSLocalizedString("SMB", comment: "Statistics Insulin: super micro boluses")
        case .bolus: return NSLocalizedString("Bolus", comment: "Statistics Insulin: the other boluses")
        }
    }

    var style: StatsBarStyle {
        switch self {
        // opaque (the `Insulin` blue at 65% over the card in light mode, 50% in dark), with an outline that
        // reaches 3:1 on white (in dark mode the outline is the fill)
        case .basal: return StatsBarStyle(fill: Color(.statsBasal), stroke: Color(.statsBasalOutline))
        case .smb: return StatsBarStyle(fill: Color(.insulin))
        case .bolus: return StatsBarStyle(fill: Color(.statsBolus))
        }
    }
}

/// Basal, SMB or bolus: U and % of the total.
struct InsulinPartRow: Equatable, Identifiable {
    let part: InsulinPart
    /// "17.1 U", "–"
    let value: String
    /// "45%", "–"
    let percent: String
    /// Today: the usual by now, "8.2 U", "–"; nil elsewhere (no column)
    var usual: String?

    var id: InsulinPart { part }
}

/// Basal, SMB, bolus: U (per day) and %; Insulin's Today with the usual by now in a column of its own. The Insulin tab's
/// and a patch's.
struct StatsPartRows: View {
    let rows: [InsulinPartRow]
    var unitHeader = NSLocalizedString("Per day", comment: "")

    /// the usual's column's width
    @ScaledMetric(relativeTo: .subheadline) private var usualWidth: CGFloat = 64

    private var hasUsual: Bool { rows.contains { $0.usual != nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(unitHeader)
                Text(verbatim: "%")
                    .frame(minWidth: 52, alignment: .trailing)
                if hasUsual {
                    Text("Usual")
                        .frame(minWidth: usualWidth, alignment: .trailing)
                }
            }
            .statsColumnHeader()

            StatsDividedRows(rows) { row in
                HStack(spacing: 10) {
                    StatsKeyGlyph(key: .swatch(row.part.style), size: .row)
                    Text(row.part.name)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.value)
                        .font(.subheadline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    Text(row.percent)
                        .font(.subheadline)
                        .monospacedDigit()
                        .frame(minWidth: 52, alignment: .trailing)
                    if let usual = row.usual {
                        Text(usual)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(minWidth: usualWidth, alignment: .trailing)
                    }
                }
                .frame(minHeight: 40)
            }
        }
    }
}

/// A card's title and on the trailing side the dates shown (`range`: the first card's, `StatsDateRange`) or
/// a quieter detail (a later card's repeat of the dates, "by hour"), or a trailing side of its own.
struct StatsCardHeader<Trailing: View>: View {
    private let title: Text
    private let trailing: Trailing

    /// a trailing side of its own (a marker beside the coverage, a note in the monospaced digits)
    init(title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.trailing = trailing()
    }

    /// a title already localized, with a trailing side of its own
    init(verbatim title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            title
                .statsSectionTitle()
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension StatsCardHeader where Trailing == StatsCardHeaderDetail {
    init(title: LocalizedStringKey, range: String) {
        self.init(title: title) { StatsCardHeaderDetail(text: range, isRange: true) }
    }

    init(title: LocalizedStringKey, detail: String) {
        self.init(title: title) { StatsCardHeaderDetail(text: detail, isRange: false) }
    }

    /// a title already localized (a nutrient's name)
    init(verbatim title: String, range: String) {
        self.init(verbatim: title) { StatsCardHeaderDetail(text: range, isRange: true) }
    }

    /// a title already localized ("Patch by patch", "Pod by pod"), with a detail
    init(verbatim title: String, detail: String) {
        self.init(verbatim: title) { StatsCardHeaderDetail(text: detail, isRange: false) }
    }
}

/// A `StatsCardHeader`'s trailing side: the dates shown (`StatsDateRange`), or a quieter detail.
struct StatsCardHeaderDetail: View {
    let text: String
    let isRange: Bool

    var body: some View {
        if isRange {
            StatsDateRange(text)
        } else {
            Text(text)
                .statsFootnote()
        }
    }
}

/// The dates a tab shows, in its first card: in the label colour at a readable size (not a footnote), so the period
/// shown is read first.
struct StatsDateRange: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// A number with its unit as a headline: "38.2 U per day", the limited mark after it.
struct StatsHeadlineNumber: View {
    let value: String
    let unit: String
    let caption: String
    var limitedNote: String?

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.title3.weight(.semibold))
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let limitedNote {
                LimitedDataMarker(note: limitedNote, font: .title3)
                    .padding(.leading, 4)
            }
        }
    }
}

/// "Show Today": today's column picked on 7–90 d of the Insulin and Meals tabs (and a nutrient's): the Today period,
/// which has today's view.
struct StatsShowTodayButton: View {
    let action: () -> Void

    var body: some View {
        StatsLinkButton("Show Today", action: action)
    }
}
