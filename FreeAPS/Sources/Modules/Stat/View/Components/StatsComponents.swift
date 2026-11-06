import Charts
import SwiftUI
import UIKit

extension GlucoseBand {
    var color: Color {
        switch self {
        case .veryLow: return Color(.statsVeryLow)
        case .low: return Color(.statsLow)
        case .inRange: return Color(.statsInRange)
        case .high: return Color(.statsHigh)
        case .veryHigh: return Color(.statsVeryHigh)
        }
    }
}

/// A card of the Statistics screen.
struct StatsCard<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.18), radius: 1.25, y: 1)
    }
}

/// Spinner on the first load, the previous content dimmed while a new one is computed, a note when empty (for content
/// that can be empty) or when the data couldn't be read (for content read from a store that can fail).
struct StatsContentView<Value: Equatable, Loaded: View>: View {
    let content: Stat.ViewContent<Value>
    var emptyText: LocalizedStringKey?
    var failedText: LocalizedStringKey?
    @ViewBuilder let loaded: (Value) -> Loaded

    var body: some View {
        // the dimmed and the loaded content are one view, so its state survives a reload
        if let value = content.value {
            loaded(value)
                .opacity(content.isLoading ? 0.5 : 1)
        } else if content.isLoading {
            StatsCard {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        } else if content == .failed {
            if let failedText {
                note(failedText)
            }
        } else if let emptyText {
            note(emptyText)
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        StatsCard {
            Text(text)
                .statsEmptyNote(minHeight: 120)
                .multilineTextAlignment(.center)
        }
    }
}

/// A segmented control with 44 pt segments.
struct StatsSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: @MainActor(Item) -> String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colorScheme == .dark ? Color(.systemGray2) : Color.white)
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(height: 44)
        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The periods a view offers: chips in the Day tab's day selector's style (the one picked filled with the label colour,
/// the others bare), the row shared out evenly. 44 pt targets.
struct PeriodPicker: View {
    let periods: [StatsPeriod]
    @Binding var selection: StatsPeriod
    /// a chip's text
    var label: (StatsPeriod) -> String = { StatsFormatting.label($0) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(periods, id: \.self) { period in
                chip(period)
            }
        }
    }

    private func chip(_ period: StatsPeriod) -> some View {
        let selected = period == selection
        return Button {
            selection = period
        } label: {
            Text(label(period))
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The navigation title's menu (`.toolbarTitleMenu`, the title is `navigationTitle(_:)`): the Glucose views under a
/// "Glucose" heading, then Insulin, Patches (or Pods, or Sites; only while there is a session, or it is shown) and Meals, each
/// with its symbol, the one shown checked.
struct StatsViewMenu: View {
    @Binding var selection: StatsTab
    /// the Patches topic's naming; nil without a session in the last 120 days: no Patches item
    var patches: PatchTopic?

    var body: some View {
        Section(Self.title(StatsTopic.glucose)) {
            ForEach(StatsTopic.glucose.views) { view in
                item(view)
            }
        }
        Section {
            item(.insulin)
        }
        if Self.offersPatches(patches, shown: selection) {
            Section {
                item(.patches)
            }
        }
        Section {
            item(.meals)
        }
    }

    /// A toggle: checked when shown (the view shown picked again is a pick too, `Stat.StateModel.select(tab:)`)
    private func item(_ view: StatsTab) -> some View {
        Toggle(isOn: Binding(get: { selection == view }, set: { _ in selection = view })) {
            Label(Self.title(view, patches: patches), systemImage: Self.systemImage(view))
        }
    }

    /// The screen's title: "Glucose · Overview" for a glucose view (the topic, then the view), "Insulin", "Patches" (or
    /// "Pods", "Sites"), "Meals".
    static func navigationTitle(_ view: StatsTab, patches: PatchTopic? = nil) -> String {
        guard view.isGlucose else { return title(view, patches: patches) }
        return String(
            format: NSLocalizedString(
                "%1$@ · %2$@",
                comment: "Statistics title: the topic, the view (\"Glucose · Overview\")"
            ),
            title(view.topic),
            title(view)
        )
    }

    static func title(_ topic: StatsTopic, patches: PatchTopic? = nil) -> String {
        switch topic {
        case .glucose: return NSLocalizedString("Glucose", comment: "Statistics topic")
        case .insulin: return NSLocalizedString("Insulin", comment: "Statistics topic")
        case .patches: return patchesTitle(patches)
        case .meals: return NSLocalizedString("Meals", comment: "Statistics topic")
        }
    }

    /// The Patches item: while the last 120 days hold a session (`PatchStatsEngine.topic`), or while it is shown.
    static func offersPatches(_ patches: PatchTopic?, shown: StatsTab) -> Bool {
        patches != nil || shown == .patches
    }

    /// "Patches", "Pods" for Omnipod, "Sites" for a tube pump (its infusion sets)
    static func patchesTitle(_ patches: PatchTopic?) -> String {
        switch patches?.kind {
        case .pod: return NSLocalizedString("Pods", comment: "Statistics topic: Omnipod pods")
        case .site: return NSLocalizedString("Sites", comment: "Statistics topic: a tube pump's infusion sites")
        case nil,
             .patch: return NSLocalizedString("Patches", comment: "Statistics topic: the pump's patches")
        }
    }

    static func title(_ view: StatsTab, patches: PatchTopic? = nil) -> String {
        switch view {
        case .overview: return NSLocalizedString("Overview", comment: "Statistics view")
        case .trace: return NSLocalizedString("Day", comment: "Statistics view: one day's readings")
        case .agp: return NSLocalizedString("AGP", comment: "Statistics view, the ambulatory glucose profile")
        case .daily: return NSLocalizedString("In range by day", comment: "Statistics view: time in ranges day by day")
        case .hourOfDay: return NSLocalizedString("By hour", comment: "Statistics view: time in ranges by the hour of the day")
        case .weekday: return NSLocalizedString("By weekday", comment: "Statistics view: the weekdays, and each one's hours")
        case .weekly: return NSLocalizedString("Weekly", comment: "Statistics view: the last 13 weeks, week by week")
        case .insulin: return NSLocalizedString("Insulin", comment: "Statistics topic")
        case .patches: return patchesTitle(patches)
        case .meals: return NSLocalizedString("Meals", comment: "Statistics topic")
        }
    }

    static func systemImage(_ view: StatsTab) -> String {
        switch view {
        case .overview: return "chart.pie"
        case .trace: return "chart.xyaxis.line"
        case .agp: return "waveform.path"
        case .daily: return "chart.bar"
        case .hourOfDay: return "clock"
        case .weekday: return "square.grid.3x3"
        case .weekly: return "calendar"
        case .insulin: return "drop"
        case .patches: return "bandage"
        case .meals: return "fork.knife"
        }
    }
}

struct BandSegment: Equatable, Identifiable {
    let band: GlucoseBand
    let fraction: Double

    var id: GlucoseBand { band }
}

extension BandShares {
    /// The nonzero bands of `bands`, in their order.
    func barSegments(_ bands: [GlucoseBand]) -> [BandSegment] {
        bands.filter { fractions[$0.rawValue] > 0 }.map { BandSegment(band: $0, fraction: fractions[$0.rawValue]) }
    }
}

/// The 5 bands as one bar: 2 pt gaps, every nonzero band at least 4 pt wide (`StatsSplitBar`, in the bands' colours).
struct BandBar: View {
    /// the nonzero bands
    let segments: [BandSegment]
    var cornerRadius: CGFloat = 7

    var body: some View {
        StatsSplitBar(
            segments: segments
                .map {
                    StatsSplitBar.Segment(id: $0.band.rawValue, style: StatsBarStyle(fill: $0.band.color), fraction: $0.fraction)
                },
            cornerRadius: cornerRadius
        )
    }
}

/// The colour key of a band.
struct BandSwatch: View {
    let band: GlucoseBand
    var size: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(band.color)
            .frame(width: size, height: size)
    }
}

/// A number with its title, and an optional unit and note; `limitedNote` marks the number provisional
/// (`LimitedDataMarker`, beside it).
struct StatTile: View {
    enum Style {
        /// filled, a large value
        case primary
        /// outlined, a smaller value
        case secondary
        /// filled, a smaller value, the unit on its own line under it (a grid of three: "2.9–15.2 mmol/L" doesn't fit
        /// on one line at 375 pt)
        case compact
    }

    let title: String
    let value: String
    var unit: String?
    var note: String?
    /// why the value is provisional (`StatsFormatting.coverageNote` and the like), nil when it isn't
    var limitedNote: String?
    var style: Style = .primary

    @ScaledMetric(relativeTo: .largeTitle) private var primarySize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: style == .primary ? 4 : 2) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(style == .primary ? Font.system(size: primarySize, weight: .bold) : Font.title2.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit, style != .compact {
                    unitText(unit)
                        .font(.footnote)
                }
                if let limitedNote {
                    LimitedDataMarker(note: limitedNote, font: .subheadline)
                }
            }
            if let unit, style == .compact {
                unitText(unit)
                    .font(.caption)
                    .lineLimit(1)
            }
            if let note {
                Text(note)
                    .statsFootnote()
            }
        }
        .padding(.horizontal, style == .compact ? 10 : 12)
        .padding(.vertical, style == .primary ? 12 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            switch style {
            case .compact,
                 .primary:
                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemGroupedBackground))
            case .secondary:
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separator), lineWidth: 1)
            }
        }
    }

    private func unitText(_ unit: String) -> some View {
        Text(unit)
            .foregroundStyle(.secondary)
    }
}

extension StatTile {
    /// A grid's tile (`StatsTileGrid`).
    init(_ item: StatsTileItem, style: Style = .compact) {
        self.init(
            title: item.title,
            value: item.value,
            unit: item.unit,
            note: item.note,
            limitedNote: item.limitedNote,
            style: style
        )
    }

    /// The tiles across a grid's row: `regular`, two at the larger text sizes.
    static func columns(_ dynamicTypeSize: DynamicTypeSize, regular: Int) -> Int {
        dynamicTypeSize > .large ? 2 : regular
    }
}

/// A number of a grid of tiles (`StatTile`): its title, value, and an optional unit and note.
struct StatsTileItem: Equatable, Identifiable {
    let id: Int
    let title: String
    let value: String
    var unit: String?
    var note: String?
    /// why the value is provisional (`StatTile.limitedNote`)
    var limitedNote: String?
}

/// Tiles in rows of `columns`, the last row's short.
struct StatsTileGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let columns: Int
    @ViewBuilder let tile: (Item) -> Tile

    init(_ items: [Item], columns: Int, @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.columns = columns
        self.tile = tile
    }

    var body: some View {
        let columns = Swift.max(self.columns, 1)
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { first in
                GridRow {
                    ForEach(items[first ..< Swift.min(first + columns, items.count)]) { item in
                        tile(item)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension StatsTileGrid where Item == StatsTileItem, Tile == StatTile {
    /// Compact tiles.
    init(_ items: [StatsTileItem], columns: Int) {
        self.init(items, columns: columns) { StatTile($0) }
    }
}

/// A provisional number (limited data): a quiet mark beside it, in the secondary colour, without counts (orange is kept
/// for what needs acting on, the Loops card's warnings). A tap shows why in a popover.
struct LimitedDataMarker: View {
    /// why: `StatsFormatting.coverageNote`, `.a1cNote` or `.profileNote`. nil inside a control with a tap of its own
    /// (the Home cards, which open Statistics, whose marks explain): the mark alone.
    let note: String?
    /// the mark's size, with the text beside it (it is a text: on the baseline, scaled with Dynamic Type)
    var font: Font = .footnote

    @State private var isShown = false
    @ScaledMetric(relativeTo: .footnote) private var popoverWidth: CGFloat = 260

    var body: some View {
        if let note {
            Button {
                isShown = true
            } label: {
                glyph
                    // a 44 pt target centred on the mark, without growing the row (it reaches past the mark's frame)
                    .overlay {
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShown) {
                explanation(note)
                    .presentationCompactAdaptation(.popover)
            }
        } else {
            glyph
        }
    }

    private var glyph: some View {
        Text(Image(systemName: "exclamationmark.circle"))
            .font(font)
            .foregroundStyle(.secondary)
    }

    private func explanation(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Limited data")
                .font(.subheadline.weight(.semibold))
            Text(note)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        // a popover is as wide as its content: the text wraps at this width (kept on screen at the largest sizes)
        .frame(width: Swift.min(popoverWidth, 320), alignment: .leading)
        .padding(14)
    }
}

extension Text {
    /// A card's section title: a headline.
    func statsSectionTitle() -> some View {
        font(.headline)
    }

    /// A footnote in the secondary colour (still a `Text`).
    func statsFootnote() -> Text {
        font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// A card's "nothing to show" ("No readings"), centred in at least `minHeight`.
    func statsEmptyNote(minHeight: CGFloat = 80) -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

extension View {
    /// A footnote in the secondary colour, for a group of views.
    func statsFootnote() -> some View {
        font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// A footnote that wraps onto as many lines as it needs.
    func statsNote() -> some View {
        statsFootnote()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A table's column titles over its rows.
    func statsColumnHeader(bottomPadding: CGFloat = 4) -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, bottomPadding)
    }

    /// A Statistics page's content in its scroll view.
    func statsPageContent() -> some View {
        padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
    }

    /// A Statistics page: the grouped background, text sizes up to xxLarge, `title` inline in the bar.
    func statsPage(title: String) -> some View {
        background(Color(.systemGroupedBackground).ignoresSafeArea())
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    /// The box of a chart's selection readout above the plot (`StatsPopover.x` places it).
    func statsChartPopover(horizontalPadding: CGFloat) -> some View {
        modifier(StatsChartPopover(horizontalPadding: horizontalPadding))
    }
}

private struct StatsChartPopover: ViewModifier {
    let horizontalPadding: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                colorScheme == .dark ? Color(.systemGray5) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }
}

enum StatsPopover {
    /// The x of a readout `width` wide centred on `center`, kept inside `containerWidth` (at its middle when wider).
    static func x(center: CGFloat, width: CGFloat, in containerWidth: CGFloat) -> CGFloat {
        Swift.min(Swift.max(center, width / 2), Swift.max(containerWidth - width / 2, width / 2))
    }
}

/// Sizes and opacities several charts share.
enum StatsChartMetrics {
    /// the plot of a bar chart (day by day, by hour), without its labels
    static let barPlotHeight: CGFloat = 220
    /// the plot of a curve over the day (Trace, AGP), without its labels or popover
    static let curvePlotHeight: CGFloat = 230
    /// a bar's width, of its slot
    static let barWidthRatio: CGFloat = 0.62
    /// the AGP's 5–95% band, the usual day's band and the IOB's 10–90%
    static let outerBand = (light: 0.16, dark: 0.22)

    static func outerBandOpacity(isDark: Bool) -> Double {
        isDark ? outerBand.dark : outerBand.light
    }

    /// the selected day's or hour's highlight behind the bars
    static func highlight(isDark: Bool) -> Color {
        Color.primary.opacity(isDark ? 0.18 : 0.08)
    }

    /// the selected hour's highlight behind opaque fills (By hour's full-height glucose bands), stronger
    static func strongHighlight(isDark: Bool) -> Color {
        Color.primary.opacity(isDark ? 0.28 : 0.16)
    }

    /// the highlight's inset from its slot's edges, of the slot
    static let highlightInset = 0.06
    /// the highlight's corners
    static let highlightCornerRadius: CGFloat = 6
    /// the usual's tick on the by-hour bars (Insulin's Today) and its key: a grey that shows on the blue fills
    static let usualTick = Color.secondary
    static let usualTickThickness: CGFloat = 2
}

/// Chart axes several charts share.
enum StatsAxis {
    /// The y axis of `levels`: a gridline at each, its label (`labels`, by index) on the leading side.
    static func levels(_ levels: [Double], labels: [String]) -> some AxisContent {
        AxisMarks(position: .leading, values: levels) { value in
            AxisGridLine()
            AxisValueLabel {
                Text(value.index < labels.count ? labels[value.index] : "")
            }
        }
    }

    /// The x axis of the minutes of a day: a gridline at each of `values` (minutes, plotted as `Value`; `toMinute`
    /// reads one back), the labels of `ticks`.
    static func minutes<Value: Plottable>(
        _ values: [Value],
        ticks: [Stat.AGP.Plot.Tick],
        toMinute: @escaping @Sendable(Value) -> Int
    ) -> some AxisContent {
        AxisMarks(values: values) { value in
            let minute = value.as(Value.self).map(toMinute)
            AxisGridLine()
            // the day's start starts there: centred, it would run into the y labels
            AxisValueLabel(anchor: minute == 0 ? .topLeading : .top) {
                Text(minute.flatMap { minute in ticks.first { $0.minute == minute }?.label } ?? "")
            }
        }
    }

    /// The x axis of the hours of a day (`ticks`, plotted as `Double` hours).
    static func hours(_ ticks: [StatsHourBars.Tick]) -> some AxisContent {
        AxisMarks(values: ticks.map { Double($0.hour) }) { value in
            let hour = value.as(Double.self).map { Int($0) }
            // the day's start starts there: centred, it would run into the y labels
            AxisValueLabel(anchor: hour == 0 ? .topLeading : .top) {
                Text(hour.flatMap { hour in ticks.first { $0.hour == hour }?.label } ?? "")
            }
        }
    }
}

/// A full-width 44 pt button to another view ("Show Today"): its title and a chevron in the accent colour, on the
/// tertiary fill.
struct StatsLinkButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}

/// The colour key of the visible bands.
struct BandLegend: View {
    let bands: [GlucoseBand]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 84), spacing: 14, alignment: .leading)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(bands, id: \.self) { band in
                HStack(spacing: 5) {
                    Circle()
                        .fill(band.color)
                        .frame(width: 8, height: 8)
                    Text(StatsFormatting.name(band))
                        .lineLimit(1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Previous / next around a title (a day, a bin, an hour, a patch): the stepper alternative to picking on a chart.
struct StatsStepper: View {
    let title: String
    var subtitle: String?
    let canGoBack: Bool
    let canGoForward: Bool
    let back: () -> Void
    let forward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", enabled: canGoBack, action: back)
            VStack(spacing: 1) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .statsFootnote()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            button("chevron.right", enabled: canGoForward, action: forward)
        }
    }

    private func button(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
        .disabled(!enabled)
    }
}

extension StatsStepper {
    /// Through the days of a chart: the day at `index` of `count`, `pick` gets the one before or after it.
    init(title: String, subtitle: String? = nil, index: Int, count: Int, pick: @escaping (Int) -> Void) {
        self.init(
            title: title,
            subtitle: subtitle,
            canGoBack: index > 0,
            canGoForward: index < count - 1,
            back: { pick(index - 1) },
            forward: { pick(index + 1) }
        )
    }

    /// Through the hours of the day, around midnight too.
    init(hourTitle title: String, subtitle: String?, selection: HourSelection) {
        self.init(
            title: title,
            subtitle: subtitle,
            canGoBack: true,
            canGoForward: true,
            back: { selection.step(by: -1) },
            forward: { selection.step(by: 1) }
        )
    }
}

/// A row for each of `items`, with a divider between each two, in a `VStack(spacing: 0)` (a list in a card). The rows
/// themselves, not a stack: they sit in the stack around them, with what comes before and after.
struct StatsDividedRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.row = row
    }

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
                Divider()
            }
            row(item)
        }
    }
}

/// A band of a table of bands (the Overview's, the hour's, the picked cell's): its swatch, name and range, the time per
/// day (the Overview's), its percent; in range in bold.
struct StatsBandRow: Equatable, Identifiable {
    let band: GlucoseBand
    let name: String
    /// "70–145"
    let range: String
    /// "2 h 5 m" (the Overview's); nil: no column
    var perDay: String?
    /// largest remainder, "<1%"
    let percent: String

    var id: GlucoseBand { band }
}

/// A `StatsBandRow`.
struct StatsBandRowView: View {
    let row: StatsBandRow

    var body: some View {
        let emphasized = row.band == .inRange
        HStack(spacing: 10) {
            BandSwatch(band: row.band)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.name)
                    .font(.subheadline.weight(emphasized ? .bold : .regular))
                Text(row.range)
                    .statsFootnote()
            }
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let perDay = row.perDay {
                Text(perDay)
                    .statsFootnote()
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(row.percent)
                .font(.subheadline.weight(emphasized ? .bold : .regular))
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)
        }
        .frame(minHeight: 40)
    }
}

/// Picking on a chart (the Trace's, the AGP's, By hour's): a tap selects, and a drag that starts horizontal selects and
/// follows the finger (kept inside the plot); a drag that starts vertical is left to the scroll view and the sheet's swipe
/// to dismiss, and selects nothing. Lifting the finger keeps the selection. `onPick` gets the x value under the finger
/// (`proxy.value(atX:)`). In the chart's `chartOverlay`, over the whole chart; the chart has no `chartXSelection`, so no
/// selection gesture of its own (that one takes every drag).
///
/// UIKit: a SwiftUI drag owns the touch once recognised, whichever way it then goes, so the scroll view never got the
/// vertical pan. A pan recognizer that begins only for a horizontal drag fails a vertical one, which the scroll view's
/// pan then takes.
struct ChartPicker<X: Plottable>: View {
    let proxy: ChartProxy
    let onPick: @MainActor(X) -> Void

    var body: some View {
        GeometryReader { geometry in
            if let plotFrame = proxy.plotFrame.map({ geometry[$0] }) {
                // the overlay's coordinates -> the plot's, as `value(atX:)` takes them
                ChartPickerSurface { x in
                    let position = Swift.min(Swift.max(x - plotFrame.minX, 0), plotFrame.width)
                    if let value = proxy.value(atX: position, as: X.self) {
                        onPick(value)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}

/// A clear view with the tap and the pan; `select` gets the x of the touch in it.
private struct ChartPickerSurface: UIViewRepresentable {
    let select: @MainActor(CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator
        coordinator.select = select
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.select = select
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var select: (@MainActor(CGFloat) -> Void)?

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            select?(recognizer.location(in: view).x)
        }

        @objc func panned(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed, let view = recognizer.view else { return }
            select?(recognizer.location(in: view).x)
        }

        /// The pan begins only for a drag that starts horizontal (its first 10 pt); a vertical one fails it.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let translation = pan.translation(in: pan.view)
            let motion = translation == .zero ? pan.velocity(in: pan.view) : translation
            return abs(motion.x) > abs(motion.y)
        }

        /// The pans around it (the scroll view's, the sheet's) wait for the pan to fail, so the drag's direction is decided
        /// here first: a diagonal but mostly horizontal drag picks rather than scrolls. A vertical one fails the pan
        /// at once (at the same 10 pt), so scrolling isn't held up. Not an edge swipe (back).
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            guard recognizer is UIPanGestureRecognizer, other is UIPanGestureRecognizer,
                  !(other is UIScreenEdgePanGestureRecognizer),
                  let view = recognizer.view, let otherView = other.view, otherView !== view
            else { return false }
            return view.isDescendant(of: otherView)
        }
    }
}
