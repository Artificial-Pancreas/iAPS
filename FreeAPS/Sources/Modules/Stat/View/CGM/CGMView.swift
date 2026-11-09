import Charts
import SwiftUI

/// The CGM topic's Overview and Sensors views (Smoothing is `CGMSmoothingView`): cards of the result shown
/// (`Stat.CGMReport`), Unknown's explainer first when it is picked.
struct CGMView: View {
    let report: Stat.CGMReport
    let tab: StatsTab

    var body: some View {
        VStack(spacing: 16) {
            if let unknown = report.unknown {
                StatsCard { CGMUnknownCard(unknown: unknown) }
            }
            if tab == .cgmSensors {
                sensors
            } else {
                overview
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder private var overview: some View {
        let overview = report.overview
        StatsCard { CGMReadingsCard(readings: overview.readings) }
        if let rate = overview.rate {
            StatsCard { CGMRateCard(rate: rate) }
        }
        if let comparison = overview.comparison {
            StatsCard { CGMComparisonCard(comparison: comparison) }
        }
        if let entered = report.entered {
            StatsCard { CGMEnteredCard(entered: entered) }
        }
    }

    // MARK: - Sensors

    @ViewBuilder private var sensors: some View {
        let sensors = report.sensors
        StatsCard {
            StatsCardHeader(
                verbatim: NSLocalizedString("Sensor by sensor", comment: "Statistics CGM Sensors: the list of the sensors"),
                detail: sensors.rows
                    .isEmpty ? "" : NSLocalizedString("newest first", comment: "Statistics Patches: the list's order")
            )
            if sensors.rows.isEmpty {
                Text(sensors.emptyText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    StatsDividedRows(sensors.rows) { row in
                        CGMSensorRowView(row: row)
                    }
                }
                Text(sensors.note)
                    .statsNote()
            }
        }
        if sensors.noiseDays.isNotEmpty {
            StatsCard { CGMNoiseDaysCard(sensors: sensors, units: report.units) }
        }
    }
}

enum CGMChartMetrics {
    /// the sensor days' bars: lower than the other topics' charts, a few values
    static let plotHeight: CGFloat = 140
}

// MARK: - The picker

/// The CGM picker: a segmented control of the short names (`PickerItem.label`) while each fits its share, else, and
/// with more than `maxSegments`, a menu button naming the CGM shown ("CGM: Libre 3"), the full names in its menu.
struct CGMPickerControl: View {
    let items: [Stat.CGMReport.PickerItem]
    @Binding var selection: Stat.CGMPick

    /// More segments than this go in the menu: three CGMs and Unknown are too many for a 375 pt phone.
    static let maxSegments = 3
    /// A segment's label keeps this much room on each side, pt.
    private static let labelMargin: CGFloat = 6

    var body: some View {
        if items.count > Self.maxSegments {
            menu
        } else {
            // the probe's ideal width is the widest label's share times the segments: wider than the row, the menu
            ViewThatFits(in: .horizontal) {
                ZStack {
                    probe
                        .hidden()
                    StatsSegmentedControl(
                        items: items.map(\.pick),
                        selection: $selection,
                        label: { pick in items.first { $0.pick == pick }?.label ?? "" }
                    )
                }
                menu
            }
        }
    }

    /// The labels as the segment picked shows them, at equal widths (the segmented control's spacing and padding).
    private var probe: some View {
        CGMEqualWidths(spacing: 2) {
            ForEach(items) { item in
                Text(item.label)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Self.labelMargin)
            }
        }
        .padding(.horizontal, 2)
    }

    private var menu: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(items) { item in
                    Text(item.title).tag(item.pick)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(String(
                    format: NSLocalizedString(
                        "CGM: %@",
                        comment: "Statistics CGM: the picker's menu button, the CGM shown (\"Libre 3\")"
                    ),
                    items.first { $0.pick == selection }?.label ?? ""
                ))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
    }
}

/// Its subviews side by side at one width, the row shared out evenly; its ideal width is the widest one's times the
/// count, so `ViewThatFits` passes it over once a subview is wider than its share.
private struct CGMEqualWidths: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let gaps = spacing * CGFloat(Swift.max(subviews.count - 1, 0))
        let ideal = (sizes.map(\.width).max() ?? 0) * CGFloat(subviews.count) + gaps
        return CGSize(width: proposal.width ?? ideal, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard !subviews.isEmpty else { return }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let width = Swift.max((bounds.width - gaps) / CGFloat(subviews.count), 0)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}

// MARK: - Shared parts

/// A callout: its title, the line in bold and the one under it, on the tile fill.
struct CGMCalloutView: View {
    let callout: Stat.CGMReport.Callout

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(callout.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(callout.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if callout.detail.isNotEmpty {
                Text(callout.detail)
                    .statsFootnote()
                    .monospacedDigit()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Keys and values, a note under a value (Unknown's, the smoothing view's).
struct CGMFactsView: View {
    let facts: [Stat.CGMReport.Fact]

    @ScaledMetric(relativeTo: .subheadline) private var keyWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            StatsDividedRows(facts) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(fact.key)
                        .foregroundStyle(.secondary)
                        .frame(width: keyWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(fact.value)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        if let detail = fact.detail {
                            Text(detail)
                                .statsFootnote()
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Overview's cards

/// Unknown picked: what its readings are.
struct CGMUnknownCard: View {
    let unknown: Stat.CGMReport.Unknown

    var body: some View {
        StatsCardHeader(
            verbatim: NSLocalizedString("Unknown CGM", comment: "Statistics CGM Unknown: the card's title"),
            detail: unknown.detail
        )
        Text(unknown.body)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        CGMFactsView(facts: unknown.facts)
        if let editor = unknown.editor {
            CGMUnknownControls(editor: editor, entered: unknown.entered, asks: true)
        }
    }
}

/// The coverage, the cadence and the tiles.
private struct CGMReadingsCard: View {
    let readings: Stat.CGMReport.Readings

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 34

    var body: some View {
        StatsCardHeader(verbatim: readings.title) {
            HStack(spacing: 4) {
                StatsDateRange(readings.dateRange)
                if let note = readings.limitedNote {
                    LimitedDataMarker(note: note)
                }
            }
        }
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(readings.coverage)
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(NSLocalizedString("of expected readings", comment: "Statistics CGM Overview: the coverage's unit"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(readings.coverageDetail)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        // the units wrap: "longest 15 m · 6 h 26 m in all" doesn't fit a 375 pt phone's half on one line
        StatsTileGrid(readings.tiles, columns: 2) { StatTile($0, unitLines: 3) }
        Text(readings.note)
            .statsNote()
    }
}

/// The time in each rate-of-change band, and the fastest rise and fall.
private struct CGMRateCard: View {
    let rate: Stat.CGMReport.Rate

    var body: some View {
        StatsCardHeader(
            verbatim: NSLocalizedString("Rate of change", comment: "Statistics CGM Overview: the rate of change card"),
            detail: rate.unitTitle
        )
        StatsSplitBar(segments: rate.segments, cornerRadius: 4)
            .frame(height: 12)
        VStack(spacing: 0) {
            StatsDividedRows(rate.rows) { row in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CGMChartStyle.ramp[Swift.min(row.id, CGMChartStyle.ramp.count - 1)])
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.subheadline.weight(row.id == 0 ? .semibold : .regular))
                        Text(row.range)
                            .statsFootnote()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(row.percent)
                            .font(.subheadline.weight(.semibold))
                        Text(row.perDay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .monospacedDigit()
                .frame(minHeight: 44)
                .padding(.vertical, 2)
            }
        }
        if let fastest = rate.fastest {
            CGMCalloutView(callout: fastest)
        }
        Text(rate.note)
            .statsNote()
    }
}

/// With two or more CGMs: a column per CGM. Above the default text size, and with more than three columns, a row's
/// name goes on a line of its own over its values, the columns shared out evenly: the names and three columns don't
/// both fit a 375 pt phone at xxLarge (`PatchesDayGrid`).
private struct CGMComparisonCard: View {
    let comparison: Stat.CGMReport.Comparison

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var column: CGFloat = 66

    private var isStacked: Bool { dynamicTypeSize > .large || comparison.columns.count > 3 }

    var body: some View {
        StatsCardHeader(
            verbatim: NSLocalizedString("By CGM", comment: "Statistics CGM Overview: the comparison of the CGMs"),
            range: comparison.dateRange
        )
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if !isStacked {
                    Spacer(minLength: 0)
                }
                ForEach(Array(comparison.columns.enumerated()), id: \.offset) { _, name in
                    cell(
                        Text(name)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    )
                }
            }
            .statsColumnHeader()
            ForEach(comparison.rows) { row in
                Divider()
                if isStacked {
                    VStack(alignment: .leading, spacing: 4) {
                        name(row)
                        values(row)
                    }
                    .padding(.vertical, 8)
                } else {
                    HStack(spacing: 4) {
                        name(row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        values(row)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        Text(comparison.note)
            .statsNote()
    }

    private func name(_ row: Stat.CGMReport.Comparison.Row) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.name)
                .fontWeight(.semibold)
            if row.unit.isNotEmpty {
                Text(row.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func values(_ row: Stat.CGMReport.Comparison.Row) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                cell(
                    Text(value)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                )
            }
        }
        .font(.footnote)
        .monospacedDigit()
    }

    /// A column's cell: `column` wide beside the names, an even share of the row stacked.
    private func cell(_ text: some View) -> some View {
        text.frame(
            minWidth: isStacked ? 0 : column,
            maxWidth: isStacked ? .infinity : column,
            alignment: .trailing
        )
    }
}

// MARK: - Sensors' cards

/// A sensor: its CGM and its tags (in use, how it ended, entered, from Nightscout), its dates and length, its bar, its
/// noise.
private struct CGMSensorRowView: View {
    let row: Stat.CGMReport.SensorRow

    /// the bar's height, every row's the same
    static let barHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // the tags beside the name, under it when they don't fit ("FreeStyle Libre 3 / 3+" and "Ended at the CGM
            // change")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    title
                    tags
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        tags
                    }
                }
            }
            Text(row.span)
                .statsFootnote()
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if let bar = row.bar {
                // the expected life, the time worn of it
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                        Capsule()
                            .fill(CGMChartStyle.data)
                            .frame(width: Swift.max(geometry.size.width * bar, Self.barHeight))
                    }
                }
                .frame(height: Self.barHeight)
            }
            if let noise = row.noise {
                Text(noise)
                    .font(.footnote)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: some View {
        Text(row.title)
            .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder private var tags: some View {
        if row.isInUse {
            CGMTag(text: NSLocalizedString("In use", comment: "Statistics Patches: the one delivering now"), isAccent: true)
        }
        if let early = row.earlyText {
            CGMTag(text: early)
        }
        if row.isEntered {
            CGMTag(text: NSLocalizedString("Entered by you", comment: "Statistics CGM Sensors: a sensor the user entered"))
        }
        if row.isBackfilled {
            CGMTag(text: NSLocalizedString("From Nightscout", comment: "Statistics CGM Sensors: a sensor named from Nightscout"))
        }
    }
}

/// A sensor's tag: "In use" filled in the accent colour, the others in grey.
private struct CGMTag: View {
    let text: String
    var isAccent = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isAccent ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(isAccent ? Color.accentColor : Color(.systemGray5), in: Capsule())
            .fixedSize()
    }
}

/// The noise by sensor day: day 1 in the stronger colour, the sensors under each day.
private struct CGMNoiseDaysCard: View {
    let sensors: Stat.CGMReport.Sensors
    let units: GlucoseUnits

    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 30

    var body: some View {
        let days = sensors.noiseDays
        let top = sensors.noiseLevels.last ?? 1
        StatsCardHeader(
            verbatim: NSLocalizedString("Noise by sensor day", comment: "Statistics CGM Sensors: the noise by sensor day card"),
            detail: StatsFormatting.unit(units)
        )
        Chart(days) { day in
            BarMark(
                x: .value("Day", String(day.day)),
                y: .value("Noise", day.value),
                width: .ratio(StatsChartMetrics.barWidthRatio)
            )
            .foregroundStyle(day.day == 1 ? CGMChartStyle.emphasis : CGMChartStyle.data)
            .cornerRadius(3)
        }
        .chartYScale(domain: 0 ... top)
        .chartYAxis {
            StatsAxis.levels(sensors.noiseLevels, labels: sensors.noiseLevelLabels)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let day = value.as(String.self), let found = days.first(where: { String($0.day) == day }) {
                        VStack(spacing: 1) {
                            Text(day)
                                .foregroundStyle(Color.primary)
                            Text(verbatim: "\(found.sensors)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                        .monospacedDigit()
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: CGMChartMetrics.plotHeight + labelHeight)
        if let callout = sensors.noiseCallout {
            CGMCalloutView(callout: callout)
        }
        Text(sensors.noiseNote)
            .statsNote()
    }
}
