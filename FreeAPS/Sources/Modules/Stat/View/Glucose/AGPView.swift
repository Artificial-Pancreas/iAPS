import Charts
import SwiftUI

extension Stat {
    /// The AGP, formatted for display. The profile, its axis and the numbers come ready from the provider
    /// (`AGPResult`); only strings are built here.
    struct AGP: Equatable {
        /// What the chart draws, and each bin's readout. The marks view compares it to skip its body (`AGPMarks`), so it
        /// holds no selection.
        struct Plot: Equatable, Sendable {
            struct Tick: Equatable, Sendable {
                /// of the day
                let minute: Int
                let label: String
            }

            struct Level: Equatable, Sendable {
                let mgdl: Int
                let label: String
            }

            /// A bin's percentiles, formatted.
            struct Readout: Equatable, Sendable {
                /// "08:30–08:45"
                let time: String
                /// "08:30"
                let start: String
                /// the 5th, 25th, 50th, 75th and 95th percentile; nil for a bin without data
                let values: [String]?
                /// the median as drawn (kept inside the axis), mg/dL; nil without data
                let plottedMedian: Double?
            }

            /// the x axis: the minutes of the day
            static let domain = 0 ... 24 * 60
            /// every 6 hours, the day's end included (it has no label: "00:00" again in 12-hour locales)
            static let gridMinutes = [0, 360, 720, 1080, 1440]

            /// mg/dL
            let axis: ClosedRange<Int>
            let points: [AGPResult.Point]
            /// the in-range band's edges, solid
            let low: Int
            let high: Int
            /// 54, 180 (mmol: 181) and 250 inside the axis, dashed; not where a range edge is
            let dashed: [Int]
            /// the local 00/06/12/18
            let xTicks: [Tick]
            let yLabels: [Level]
            /// by bin, from 00:00
            let readouts: [Readout]
            let unit: String

            /// the solid rules
            var edges: [Int] { low == high ? [low] : [low, high] }

            var binCount: Int { readouts.count }

            /// where a bin is drawn: its middle minute
            func minute(ofBin bin: Int) -> Int {
                GlucoseStatsEngine.agpMiddleMinute(ofBin: bin, binCount: binCount)
            }
        }

        /// A key number.
        typealias Tile = StatsTileItem

        /// "17 Oct – 30 Oct"
        let dateRange: String
        /// "CGM coverage 92%"
        let coverage: String
        /// "Days with data 9 of 14": the count the profile note leaves out ("this period has fewer")
        let daysWithData: String
        /// why the numbers are provisional (CGM coverage below 70%), marked beside the coverage; nil when it isn't
        let coverageNote: String?
        /// why the profile is (`StatsFormatting.profileNote`), marked beside its title; nil when the AGP isn't limited
        /// (`GlucoseStatsEngine.agpIsLimited`)
        let profileNote: String?
        let tiles: [Tile]
        /// "14 days"
        let days: String
        let plot: Plot
        /// "Your range 70–145"
        let legendRange: String

        @MainActor init(_ result: AGPResult, period: StatsPeriod, settings: StatsSettings) {
            typealias Format = StatsFormatting
            let summary = result.summary
            let bands = summary.bands
            let units = settings.units
            let dayCount = period.calendarDayCount ?? 1
            // the Overview's numbers, formatted by it: the AGP shows the same ones for the same period
            let numbers = Overview(summary, period: period, settings: settings)
            let inRangeLabel = Format.label(.inRange, bands: bands, units: units) ?? ""

            dateRange = numbers.dateRange
            coverage = String(
                format: NSLocalizedString("CGM coverage %@", comment: "Statistics, the CGM coverage percent"),
                numbers.coverage
            )
            daysWithData = String(
                format: NSLocalizedString("Days with data %@", comment: "Statistics AGP: the days with readings, \"9 of 14\""),
                numbers.daysWithData
            )
            coverageNote = numbers.coverageNote
            profileNote = Format.profileNote(summary)

            // the Overview's marks on both A1c estimates (fewer than 14 days with readings)
            func a1cTile(id: Int, title: String, value: String) -> Tile {
                Tile(id: id, title: title, value: value, unit: numbers.a1cUnit, limitedNote: numbers.a1cNote)
            }
            tiles = [
                // marked as the Overview's headline is (the coverage)
                Tile(
                    id: 0,
                    title: Format.name(.inRange),
                    value: Format.percent(.inRange, of: summary),
                    note: numbers.inRangeRange,
                    limitedNote: numbers.coverageNote
                ),
                Tile(id: 1, title: numbers.tirTitle, value: numbers.tir),
                Tile(id: 2, title: numbers.titrTitle, value: numbers.titr),
                Tile(
                    id: 3,
                    title: NSLocalizedString("Mean / CV", comment: "Statistics AGP, the mean glucose and the CV in one tile"),
                    value: numbers.mean + " / " + numbers.cv,
                    unit: numbers.unit
                ),
                a1cTile(id: 4, title: NSLocalizedString("GMI", comment: "Glucose management indicator"), value: numbers.gmi),
                a1cTile(id: 5, title: NSLocalizedString("eA1c", comment: "Estimated A1c (ADAG)"), value: numbers.eA1c)
            ]

            days = String(format: NSLocalizedString("%d days", comment: "Statistics AGP, the days of the period"), dayCount)

            let axis = result.axis
            let unit = Format.unit(units)
            plot = Plot(
                axis: axis,
                points: result.points,
                low: bands.low,
                high: bands.high,
                dashed: GlucoseStatsEngine.dashedLevels(bands: bands, axis: axis),
                xTicks: Plot.gridMinutes.dropLast().map { Plot.Tick(minute: $0, label: Self.clockTime($0)) },
                yLabels: GlucoseStatsEngine.labelledLevels(bands: bands, axis: axis)
                    .map { Plot.Level(mgdl: $0, label: Format.glucose($0, units: units)) },
                readouts: result.bins.enumerated().map { index, bin in
                    Self.readout(bin, index: index, binCount: result.bins.count, axis: axis, units: units)
                },
                unit: unit
            )

            legendRange = String(
                format: NSLocalizedString("Your range %@", comment: "Statistics AGP legend: the in-range band"),
                inRangeLabel
            )
        }

        /// "08:30", or "8:30 AM": a minute of the day as the locale shows a time, on no day in particular (UTC, so
        /// no DST)
        static func clockTime(_ minute: Int) -> String {
            Date(timeIntervalSinceReferenceDate: .minutes(minute)).formatted(clockStyle)
        }

        private static let clockStyle: Date.FormatStyle = {
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = TimeZone(secondsFromGMT: 0) ?? style.timeZone
            return style
        }()

        /// "08:30–08:45", or "8:30 – 8:45 AM": two minutes of the day (`clockTime`'s UTC reference day) as the locale
        /// shows a time interval. The day's last bin ends at the next day's 00:00, which the interval format shows with
        /// both dates: it is the interval from 00:00 to its start (the same two times, on one day), its times swapped.
        static func clockInterval(from startMinute: Int, to endMinute: Int) -> String {
            let start = Date(timeIntervalSinceReferenceDate: .minutes(startMinute))
            let dayEnd = 24 * 60
            guard endMinute >= dayEnd else {
                return (start ..< Date(timeIntervalSinceReferenceDate: .minutes(Swift.max(endMinute, startMinute))))
                    .formatted(intervalStyle)
            }
            let midnight = Date(timeIntervalSinceReferenceDate: 0)
            // a moment alone, as the interval format shows each end
            let first = (start ..< start).formatted(intervalStyle)
            let last = (midnight ..< midnight).formatted(intervalStyle)
            let reversed = (midnight ..< Swift.max(start, midnight)).formatted(intervalStyle)
            guard reversed.count > first.count + last.count, reversed.hasPrefix(last), reversed.hasSuffix(first) else {
                return first + " – " + last
            }
            return first + String(reversed.dropFirst(last.count).dropLast(first.count)) + last
        }

        private static let intervalStyle: Date.IntervalFormatStyle = {
            let utc = TimeZone(secondsFromGMT: 0) ?? .current
            var calendar = Calendar.current
            calendar.timeZone = utc
            return Date.IntervalFormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: utc)
        }()

        @MainActor private static func readout(
            _ bin: AGPBin?,
            index: Int,
            binCount: Int,
            axis: ClosedRange<Int>,
            units: GlucoseUnits
        ) -> Plot.Readout {
            typealias Format = StatsFormatting
            let binMinutes = 24 * 60 / Swift.max(binCount, 1)
            let startMinute = index * binMinutes
            let start = clockTime(startMinute)
            let time = clockInterval(from: startMinute, to: startMinute + binMinutes)
            guard let bin else {
                return Plot.Readout(
                    time: time,
                    start: start,
                    values: nil,
                    plottedMedian: nil
                )
            }
            let values = [bin.p5, bin.p25, bin.p50, bin.p75, bin.p95].map { Format.glucose($0, units: units) }
            return Plot.Readout(
                time: time,
                start: start,
                values: values,
                plottedMedian: Swift.min(Swift.max(bin.p50, Double(axis.lowerBound)), Double(axis.upperBound))
            )
        }
    }
}

struct AGPView: View {
    let agp: Stat.AGP
    let selection: AGPSelection

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The chart first, then the selected time's readout, then the numbers.
    var body: some View {
        VStack(spacing: 16) {
            StatsCard { profile }
            StatsCard { keyNumbers }
        }
    }

    // MARK: - Profile

    @ViewBuilder private var profile: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Glucose profile")
                .statsSectionTitle()
            if let profileNote = agp.profileNote {
                LimitedDataMarker(note: profileNote, font: .subheadline)
            }
            Spacer(minLength: 0)
            StatsDateRange(agp.dateRange)
        }

        AGPChart(plot: agp.plot, selection: selection)

        AGPStepper(plot: agp.plot, selection: selection)

        AGPLegend(range: agp.legendRange)
    }

    // MARK: - Key numbers

    @ViewBuilder private var keyNumbers: some View {
        StatsCardHeader(verbatim: agp.days) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(agp.coverage)
                    if let coverageNote = agp.coverageNote {
                        LimitedDataMarker(note: coverageNote)
                    }
                }
                Text(agp.daysWithData)
            }
            .statsFootnote()
        }

        // two rows of three, three rows of two at the larger text sizes
        StatsTileGrid(agp.tiles, columns: StatTile.columns(dynamicTypeSize, regular: 3))
    }
}

// MARK: - Style

private enum AGPStyle {
    /// the 5–95% band
    static func outer(isDark: Bool) -> Color {
        Color(.statsAGP).opacity(StatsChartMetrics.outerBandOpacity(isDark: isDark))
    }

    /// the 25–75% band
    static func inner(isDark: Bool) -> Color {
        Color(.statsAGP).opacity(isDark ? 0.48 : 0.40)
    }

    static var median: Color {
        Color(.statsAGPMedian)
    }
}

// MARK: - Stepper

/// The selected time, 30 minutes back or on (around midnight too): the alternative to picking on the chart.
private struct AGPStepper: View {
    let plot: Stat.AGP.Plot
    let selection: AGPSelection

    /// 30 minutes
    private static let step = 30 / GlucoseStatsEngine.agpBinMinutes

    var body: some View {
        if let bin = selection.bin(on: plot) {
            StatsStepper(
                title: plot.readouts[bin].start,
                subtitle: NSLocalizedString("Selected time", comment: "Statistics AGP, the time picked"),
                canGoBack: true,
                canGoForward: true,
                back: { selection.select(GlucoseStatsEngine.agpStep(bin, by: -Self.step, binCount: plot.binCount)) },
                forward: { selection.select(GlucoseStatsEngine.agpStep(bin, by: Self.step, binCount: plot.binCount)) }
            )
        }
    }
}

// MARK: - Legend

/// The colour key.
private struct AGPLegend: View {
    let range: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let outer = item(StatsFormatting.percentileBand(5, 95)) {
            RoundedRectangle(cornerRadius: 2).fill(AGPStyle.outer(isDark: isDark)).frame(width: 16, height: 10)
        }
        let inner = item(StatsFormatting.percentileBand(25, 75)) {
            RoundedRectangle(cornerRadius: 2).fill(AGPStyle.inner(isDark: isDark)).frame(width: 16, height: 10)
        }
        let median = item(NSLocalizedString("Median", comment: "Statistics AGP, the 50th percentile")) {
            RoundedRectangle(cornerRadius: 2).fill(AGPStyle.median).frame(width: 16, height: 3)
        }
        let yourRange = item(range) {
            Rectangle().fill(GlucoseBand.inRange.color).frame(width: 16, height: 2)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                outer
                inner
                median
                yourRange
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    outer
                    inner
                    median
                }
                yourRange
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func item<Swatch: View>(_ label: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(label)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Chart

/// The chart with its selection: the marks (`AGPMarks`, equatable) aren't re-rendered when the selection moves.
private struct AGPChart: View {
    let plot: Stat.AGP.Plot
    let selection: AGPSelection

    @Environment(\.colorScheme) private var colorScheme
    /// the room above the plot for the selected bin's readout
    @ScaledMetric(relativeTo: .subheadline) private var popoverHeight: CGFloat = 76

    var body: some View {
        AGPMarks(plot: plot, selection: selection, isDark: colorScheme == .dark, popoverHeight: popoverHeight)
            .equatable()
            .frame(height: StatsChartMetrics.curvePlotHeight + popoverHeight)
    }
}

/// The marks: the two percentile bands and the median, as segments between the bins without data. Its inputs don't
/// change while the selection moves, so `.equatable()` skips its body; the selection reaches it only through
/// `AGPSelection`, which only `AGPSelectionLayer` reads.
private struct AGPMarks: View, Equatable {
    let plot: Stat.AGP.Plot
    let selection: AGPSelection
    let isDark: Bool
    let popoverHeight: CGFloat

    nonisolated static func == (lhs: AGPMarks, rhs: AGPMarks) -> Bool {
        lhs.selection === rhs.selection && lhs.isDark == rhs.isDark && lhs.popoverHeight == rhs.popoverHeight
            && lhs.plot == rhs.plot
    }

    var body: some View {
        let plot = self.plot
        let selection = self.selection
        let outer = AGPStyle.outer(isDark: isDark)
        let inner = AGPStyle.inner(isDark: isDark)
        Chart {
            AGPFrameMarks(floor: plot.axis.lowerBound, dashed: plot.dashed)

            ForEach(plot.points, id: \.minute) { point in
                AreaMark(
                    x: .value("Time", point.minute),
                    yStart: .value("5th percentile", point.p5),
                    yEnd: .value("95th percentile", point.p95),
                    series: .value("Segment", "outer \(point.segment)")
                )
                .foregroundStyle(outer)
            }

            ForEach(plot.points, id: \.minute) { point in
                AreaMark(
                    x: .value("Time", point.minute),
                    yStart: .value("25th percentile", point.p25),
                    yEnd: .value("75th percentile", point.p75),
                    series: .value("Segment", "inner \(point.segment)")
                )
                .foregroundStyle(inner)
            }

            AGPFrameMarks.Edges(edges: plot.edges)

            ForEach(plot.points, id: \.minute) { point in
                LineMark(
                    x: .value("Time", point.minute),
                    y: .value("Median", point.p50),
                    series: .value("Segment", "median \(point.segment)")
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(AGPStyle.median)
            }
        }
        .agpFrameAxes(axis: plot.axis, xTicks: plot.xTicks, yLabels: plot.yLabels)
        // the picking: no `chartXSelection` (its gesture takes every drag on the chart, and a vertical one has to reach
        // the scroll view and the sheet's swipe to dismiss); `ChartPicker` writes the minute under the finger into the
        // selection, which nothing here reads (it would re-render the marks on every move)
        .chartOverlay { proxy in
            ZStack {
                ChartPicker(proxy: proxy) { (minute: Int) in
                    selection.select(minute: minute, on: plot)
                }
                AGPSelectionLayer(plot: plot, selection: selection, proxy: proxy, popoverHeight: popoverHeight)
            }
        }
        .padding(.top, popoverHeight)
    }
}

/// The AGP's frame, which Good & bad days' chart draws too: the axis rule and the dashed levels under the data, the
/// range edges (`Edges`) over the bands.
struct AGPFrameMarks: ChartContent {
    /// mg/dL: the axis' floor
    let floor: Int
    /// mg/dL (`GlucoseStatsEngine.dashedLevels`)
    let dashed: [Int]

    var body: some ChartContent {
        RuleMark(y: .value("Axis", Double(floor)))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .foregroundStyle(Color(.systemGray4))

        ForEach(dashed, id: \.self) { level in
            RuleMark(y: .value("Level", Double(level)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
    }

    /// The in-range band's edges, solid, drawn over the bands.
    struct Edges: ChartContent {
        /// mg/dL
        let edges: [Int]

        var body: some ChartContent {
            ForEach(edges, id: \.self) { edge in
                RuleMark(y: .value("Range edge", Double(edge)))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(GlucoseBand.inRange.color)
            }
        }
    }
}

extension View {
    /// The AGP's axes, which Good & bad days' chart has too: the minutes of the day, the glucose axis with its labelled
    /// levels on the leading side; no legend.
    func agpFrameAxes(
        axis: ClosedRange<Int>,
        xTicks: [Stat.AGP.Plot.Tick],
        yLabels: [Stat.AGP.Plot.Level]
    ) -> some View {
        chartXScale(domain: Stat.AGP.Plot.domain)
            .chartYScale(domain: Double(axis.lowerBound) ... Double(axis.upperBound))
            .chartXAxis {
                StatsAxis.minutes(Stat.AGP.Plot.gridMinutes, ticks: xTicks) { $0 }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yLabels.map { Double($0.mgdl) }) { value in
                    AxisValueLabel {
                        Text(value.as(Double.self).flatMap { mgdl in yLabels.first { Double($0.mgdl) == mgdl }?.label } ?? "")
                    }
                }
            }
            .chartLegend(.hidden)
    }
}

/// The selected bin: a rule down through it, the median's dot, and its percentiles above the plot.
private struct AGPSelectionLayer: View {
    let plot: Stat.AGP.Plot
    let selection: AGPSelection
    let proxy: ChartProxy
    let popoverHeight: CGFloat

    @ScaledMetric(relativeTo: .body) private var popoverWidth: CGFloat = 236

    var body: some View {
        let bin = selection.bin(on: plot)
        GeometryReader { geometry in
            if let bin, let plotFrame = proxy.plotFrame.map({ geometry[$0] }),
               let x = proxy.position(forX: plot.minute(ofBin: bin))
            {
                let readout = plot.readouts[bin]
                let centerX = plotFrame.minX + x
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: plotFrame.minY - 2))
                    path.addLine(to: CGPoint(x: centerX, y: plotFrame.maxY))
                }
                .stroke(Color.secondary, lineWidth: 1)

                if let median = readout.plottedMedian, let y = proxy.position(forY: median) {
                    Circle()
                        .fill(AGPStyle.median)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .position(x: centerX, y: plotFrame.minY + y)
                }

                let width = Swift.min(popoverWidth, geometry.size.width)
                popover(readout)
                    .frame(width: width, alignment: .leading)
                    .position(x: StatsPopover.x(center: centerX, width: width, in: geometry.size.width), y: -popoverHeight / 2)
            }
        }
        .allowsHitTesting(false)
    }

    /// "5%", "25%", "Median", "75%", "95%"
    @MainActor private static let percentileLabels: [String] = [
        StatsFormatting.percent(5),
        StatsFormatting.percent(25),
        NSLocalizedString("Median", comment: "Statistics AGP, the 50th percentile"),
        StatsFormatting.percent(75),
        StatsFormatting.percent(95)
    ]

    private func popover(_ readout: Stat.AGP.Plot.Readout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(readout.time + " · " + plot.unit)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
            if let values = readout.values {
                let labels = Self.percentileLabels
                HStack(spacing: 2) {
                    ForEach(values.indices, id: \.self) { index in
                        VStack(spacing: 0) {
                            Text(labels[index])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(values[index])
                                .font(.subheadline.weight(index == 2 ? .bold : .regular))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text("No readings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .statsChartPopover(horizontalPadding: 10)
    }
}
