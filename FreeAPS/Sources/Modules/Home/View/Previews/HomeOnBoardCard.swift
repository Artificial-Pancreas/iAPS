import Charts
import SwiftUI

/// The On board card on Home: the last 24 hours on one time axis, in lanes from the top: glucose (its toggle, with
/// readings), carbs on board (its toggle, with carbs: a COB above 0) and insulin on board (always), each with its own
/// grid and values on the trailing side, the hours under them; the time with a negative IOB in the last 24 hours below.
/// Not a link but its lanes and its Negative IOB row: a tap on the glucose lane opens Statistics › Glucose on the Day
/// tab's 24 hours, on insulin on board Statistics › Insulin on Today, on carbs on board Statistics › Meals on Today, on
/// the Negative IOB row Statistics › Insulin at 7 d on the Negative IOB card; a long-press picks the lanes
/// (`HomeOnBoardMenu`, the card's `.contextMenu` in `HomeRootView`). As of
/// its last build (`Home.StateModel.refreshOnBoard`: a loop or a suggestion, a reading, the glucose settings, the
/// foreground, a time change), no clock.
struct HomeOnBoardCard: View, Equatable {
    enum Lane: Hashable, Sendable {
        case glucose
        case cob
        case iob
    }

    /// A CGM reading as the card takes it: mg/dL
    struct Reading: Equatable, Sendable {
        let date: Date
        let mgdl: Int
    }

    struct Point: Equatable, Sendable {
        let date: Date
        let value: Double
    }

    struct GlucosePoint: Equatable, Sendable {
        let date: Date
        let mgdl: Int
        let band: GlucoseBand
    }

    /// A value on a lane's trailing side (and its gridline or dashed rule), in the lane's units: U, g, mg/dL
    struct AxisLabel: Equatable, Sendable {
        let value: Double
        let text: String
    }

    /// Every 2 h, on the even clock hours (`Content.hourTicks`): the lanes' vertical gridlines and the hour under them
    struct HourTick: Equatable, Sendable {
        let date: Date
        /// of the window, 0 ... 1
        let fraction: Double
        /// "08"
        let label: String
    }

    /// What the card shows, built once per refresh (`Home.StateModel`). Every lane is there, the toggles pick the shown
    /// ones in the view (`lanes`), so a toggle needs no rebuild.
    struct Content: Equatable, Sendable {
        static let duration: TimeInterval = .hours(24)
        /// a row or a reading at most this far ahead of the clock ends the window (`window(now:newest:)`)
        static let futureTolerance: TimeInterval = .minutes(5)
        /// the card shows with more IOB rows than this in the window (`hasRows`)
        static let minimumRows = 3

        /// the last 24 hours, up to the build's minute or a newer row or reading (`window(now:newest:)`)
        let window: DateInterval
        /// the IOB rows in the window
        let rowCount: Int
        /// the readings in the window, oldest -> newest, at most one per 5 min (`thinned`)
        let glucose: [GlucosePoint]
        /// mg/dL
        let glucoseDomain: ClosedRange<Double>
        /// the in-range band's edges (`StatsBands.low`, `high`: the dots' colours' bands, the Statistics'), dashed; one
        /// when they are the same (the bands allow it): the views' ids are the values
        let glucoseLevels: [AxisLabel]
        /// oldest -> newest
        let cob: [Point]
        /// a COB above 0 in the window: without, no carbs lane (and its toggle disabled)
        let hasCarbs: Bool
        let cobDomain: ClosedRange<Double>
        let cobLabels: [AxisLabel]
        /// oldest -> newest, a point at each zero crossing (the area above 0 and the red one below meet there)
        let iob: [Point]
        let iobDomain: ClosedRange<Double>
        let iobLabels: [AxisLabel]
        let hourTicks: [HourTick]
        /// "1 h 25 min", "0 min"
        let negativeIOB: String

        /// - Parameters:
        ///   - iob: the loop's `Reasons` rows (any order), also the ones up to 7.5 min before the window (the negative
        ///     IOB at its start, `negativeIOBSeconds`); the card shows with more than 3 in the window (`hasRows`)
        ///   - readings: the CGM readings (any order)
        ///   - bands: the dots' colours and the dashed rules at the in-range band's edges (the Statistics bands, as the
        ///     main chart's)
        @MainActor init(
            iob rows: [IOBData],
            readings: [Reading],
            bands: StatsBands,
            units: GlucoseUnits,
            now: Date,
            calendar: Calendar
        ) {
            let newest = [rows.map(\.date).max(), readings.map(\.date).max()].compactMap { $0 }
            let window = Self.window(now: now, newest: newest)
            self.window = window
            let inWindow = { (date: Date) in date >= window.start && date <= window.end }

            let allRows = rows.sorted { $0.date < $1.date }
            let sortedRows = allRows.filter { inWindow($0.date) }
            rowCount = sortedRows.count
            let iobRows = sortedRows.map { Point(date: $0.date, value: Self.double($0.iob)) }
            let cobRows = sortedRows.map { Point(date: $0.date, value: Self.double($0.cob)) }

            // glucose: the dots thinned, the domain from every reading
            let windowReadings = readings.filter { inWindow($0.date) }.sorted { $0.date < $1.date }
            glucose = Self.thinned(windowReadings).map {
                GlucosePoint(date: $0.date, mgdl: $0.mgdl, band: bands.band($0.mgdl))
            }
            glucoseDomain = Self.glucoseDomain(windowReadings.map(\.mgdl), inRange: bands.low ... bands.high)
            glucoseLevels = Self.levels(bands).map {
                AxisLabel(value: Double($0), text: StatsFormatting.glucose($0, units: units))
            }

            // carbs on board
            cob = cobRows
            hasCarbs = Self.hasCarbs(cobRows.map(\.value))
            cobDomain = Self.cobDomain(cobRows.map(\.value))
            cobLabels = Self.labels(
                Self.ticks(cobDomain),
                unit: NSLocalizedString(" g", comment: "gram of carbs")
            )

            // insulin on board
            iob = Self.iobSeries(iobRows)
            iobDomain = Self.iobDomain(iobRows.map(\.value))
            iobLabels = Self.labels(
                Self.ticks(iobDomain),
                unit: NSLocalizedString(" U", comment: "Insulin unit")
            )

            hourTicks = Self.hourTicks(window, calendar: calendar)

            // every row: one before the window stands for the time up to the next one, its part inside counts
            let negativeSeconds = Self.negativeIOBSeconds(
                allRows.map { IOBPoint(time: $0.date, iob: Self.double($0.iob)) },
                window: window
            )
            negativeIOB = HomeLoopsCard.duration(negativeSeconds)
        }

        // MARK: Window

        /// The last 24 hours up to now to the minute (a loop's and its suggestion's builds seconds apart are the same
        /// card), or up to the newest row or reading when that is later (a reading a little ahead of the clock), at most
        /// `futureTolerance` ahead (a date further ahead moves nothing, its row or reading is left out).
        static func window(now: Date, newest: [Date]) -> DateInterval {
            let minute = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
            let latest = minute.addingTimeInterval(futureTolerance)
            let end = Swift.max(minute, newest.filter { $0 <= latest }.max() ?? minute)
            return DateInterval(start: end.addingTimeInterval(-duration), end: end)
        }

        /// The card shows with more than 3 IOB rows in its window: not when the loop stopped long enough ago that the
        /// readings moved the window past its rows (flat lanes).
        var hasRows: Bool {
            rowCount > Self.minimumRows
        }

        /// At most one dot per 5 min (a 1-minute CGM's 1440 a day as 288): from the newest back, a reading at least
        /// 4.5 min before the last one kept (`FrequentGlucoseFiltering`, the stream oref gets), so every reading of a
        /// 5-minute CGM stays and the newest is always there.
        /// - Parameter readings: oldest -> newest
        /// - Returns: oldest -> newest
        static func thinned(_ readings: [Reading]) -> [Reading] {
            var kept: [Reading] = []
            for reading in readings.reversed() {
                if let last = kept.last,
                   last.date.timeIntervalSince(reading.date) < FrequentGlucoseFiltering.fiveMinuteInterval
                {
                    continue
                }
                kept.append(reading)
            }
            return kept.reversed()
        }

        // MARK: Lanes

        /// The lanes shown, from the top: glucose when on and with readings, carbs on board when on and with carbs,
        /// insulin on board always.
        static func lanes(showGlucose: Bool, showCOB: Bool, hasReadings: Bool, hasCarbs: Bool) -> [Lane] {
            var lanes: [Lane] = []
            if showGlucose, hasReadings {
                lanes.append(.glucose)
            }
            if showCOB, hasCarbs {
                lanes.append(.cob)
            }
            lanes.append(.iob)
            return lanes
        }

        func lanes(showGlucose: Bool, showCOB: Bool) -> [Lane] {
            Self.lanes(showGlucose: showGlucose, showCOB: showCOB, hasReadings: !glucose.isEmpty, hasCarbs: hasCarbs)
        }

        /// The in-range band's edges, mg/dL: low and high, one when they are the same.
        static func levels(_ bands: StatsBands) -> [Int] {
            bands.low == bands.high ? [bands.low] : [bands.low, bands.high]
        }

        /// Carbs in the window: a COB above 0 in a row (0 throughout: no carbs lane, its toggle disabled).
        static func hasCarbs(_ values: [Double]) -> Bool {
            values.contains { $0 > 0 }
        }

        /// A lane's height (pt) among the shown ones: insulin on board taller the fewer lanes there are
        static func height(of lane: Lane, in lanes: [Lane]) -> CGFloat {
            switch lane {
            case .glucose: return 56
            case .cob: return lanes.contains(.glucose) ? 40 : 48
            case .iob:
                switch lanes.count {
                case 3: return 64
                case 2: return 76
                default: return 104
                }
            }
        }

        // MARK: Domains and values

        /// The IOB chart's: min(0, lowest × 1.3) ... highest × 1.1, at least 1 U tall, 0 always inside (all below zero:
        /// up to 0 at least, the areas' base)
        static func iobDomain(_ values: [Double]) -> ClosedRange<Double> {
            let lowest = Swift.min(values.min() ?? 0, 0)
            let lower = Swift.min(0, lowest * 1.3)
            let upper = Swift.max(0, (values.max() ?? 0) * 1.1, lower + 1)
            return lower ... upper
        }

        /// 0 ... highest × 1.1, at least 10 g (a lane without carbs is flat at 0, not stretched)
        static func cobDomain(_ values: [Double]) -> ClosedRange<Double> {
            0 ... Swift.max(10, (values.max() ?? 0) * 1.1)
        }

        /// mg/dL: min(low − 10, lowest × 0.9) ... max(high + 20, highest × 1.05), so the in-range band's rules are
        /// always inside (70–180: 60 ... 200 at least)
        /// - Parameter inRange: the in-range band, `StatsBands.low ... high`
        static func glucoseDomain(_ values: [Int], inRange: ClosedRange<Int>) -> ClosedRange<Double> {
            let floor = Double(inRange.lowerBound - 10)
            let ceiling = Double(inRange.upperBound + 20)
            let lower = Swift.min(floor, values.min().map { Double($0) * 0.9 } ?? floor)
            let upper = Swift.max(ceiling, values.max().map { Double($0) * 1.05 } ?? ceiling)
            return lower ... upper
        }

        /// About three round values inside the domain (Swift Charts' `.automatic(desiredCount: 3)`): a step of 1, 2,
        /// 2.5 or 5 × 10ⁿ, the first one at or above (domain span) / 2.5
        static func ticks(_ domain: ClosedRange<Double>) -> [Double] {
            let span = domain.upperBound - domain.lowerBound
            guard span > 0, span.isFinite else { return [] }
            let step = niceStep(span / 2.5)
            var ticks: [Double] = []
            var value = (domain.lowerBound / step - 1E-9).rounded(.up) * step
            while value <= domain.upperBound + 1E-9 {
                let rounded = (value * 1000).rounded() / 1000
                // never -0 ("-0")
                ticks.append(rounded == 0 ? 0 : rounded)
                value += step
            }
            return ticks
        }

        static func niceStep(_ raw: Double) -> Double {
            let magnitude = pow(10, log10(raw).rounded(.down))
            for multiple in [1, 2, 2.5, 5, 10] where multiple * magnitude >= raw - 1E-9 {
                return multiple * magnitude
            }
            return 10 * magnitude
        }

        /// The values, the unit on the top one: "0", "1", "2 U"
        static func labels(_ ticks: [Double], unit: String) -> [AxisLabel] {
            ticks.enumerated().map { index, value in
                let text = value.formatted(.number.precision(.fractionLength(0 ... 2)))
                return AxisLabel(value: value, text: index == ticks.count - 1 ? text + unit : text)
            }
        }

        /// The rows' IOB with a point at 0 where it crosses zero (by the straight line between two rows)
        static func iobSeries(_ rows: [Point]) -> [Point] {
            var series: [Point] = []
            for row in rows {
                if let last = series.last, last.value * row.value < 0 {
                    let share = last.value / (last.value - row.value)
                    let date = last.date.addingTimeInterval(row.date.timeIntervalSince(last.date) * share)
                    series.append(Point(date: date, value: 0))
                }
                series.append(row)
            }
            return series
        }

        /// Every 2 hours back from the newest even clock hour in the window, "00" ... "22": 2 hours apart also over a DST
        /// change, where the hours before it are then odd (spring forward: … 23, 01, 04, 06 …; fall back: … 22, 00, 01,
        /// 03 …), so the newest ones are always even.
        static func hourTicks(_ window: DateInterval, calendar: Calendar) -> [HourTick] {
            guard window.duration > 0,
                  var date = calendar.dateInterval(of: .hour, for: window.end)?.start
            else { return [] }
            // the even clock hour at or before the end: at most two back (one more over a skipped hour)
            for _ in 0 ..< 3 where calendar.component(.hour, from: date) % 2 != 0 {
                date = date.addingTimeInterval(-.hours(1))
            }
            var ticks: [HourTick] = []
            while date >= window.start {
                ticks.append(HourTick(
                    date: date,
                    fraction: date.timeIntervalSince(window.start) / window.duration,
                    label: String(format: "%02d", calendar.component(.hour, from: date))
                ))
                date = date.addingTimeInterval(-.hours(2))
            }
            return ticks.reversed()
        }

        /// The time with a negative IOB in the window, s: the Statistics' rule (`InsulinStatsEngine.iobSpans`: a row
        /// stands for the time up to the next one, at most 7.5 min, else 5 min; the newest not past the window's end),
        /// cut at the window
        static func negativeIOBSeconds(_ points: [IOBPoint], window: DateInterval) -> TimeInterval {
            InsulinStatsEngine.iobSpans(points, now: window.end)
                .filter(\.isNegative)
                .reduce(0) { total, span in
                    let start = Swift.max(span.interval.start, window.start)
                    let end = Swift.min(span.interval.end, window.end)
                    return total + Swift.max(0, end.timeIntervalSince(start))
                }
        }

        private static func double(_ value: Decimal) -> Double {
            NSDecimalNumber(decimal: value).doubleValue
        }
    }

    let content: Content
    /// the long-press menu's toggles (`FreeAPSSettings.homeOnBoardGlucose`, `homeOnBoardCOB`)
    let showGlucose: Bool
    let showCOB: Bool
    /// the Negative IOB row: Statistics › Insulin's Negative IOB card
    let openNegativeIOB: @MainActor @Sendable() -> Void
    /// the lanes: Statistics › Glucose's Day tab, Insulin, Meals
    let openGlucose: @MainActor @Sendable() -> Void
    let openInsulin: @MainActor @Sendable() -> Void
    let openMeals: @MainActor @Sendable() -> Void

    // explicit: the synthesized memberwise init drops `@Sendable` from the closures in this target (Swift 5 mode,
    // targeted concurrency), so passing `@Sendable` closures to it warns
    init(
        content: Content,
        showGlucose: Bool,
        showCOB: Bool,
        openNegativeIOB: @escaping @MainActor @Sendable() -> Void,
        openGlucose: @escaping @MainActor @Sendable() -> Void,
        openInsulin: @escaping @MainActor @Sendable() -> Void,
        openMeals: @escaping @MainActor @Sendable() -> Void
    ) {
        self.content = content
        self.showGlucose = showGlucose
        self.showCOB = showCOB
        self.openNegativeIOB = openNegativeIOB
        self.openGlucose = openGlucose
        self.openInsulin = openInsulin
        self.openMeals = openMeals
    }

    @Environment(\.colorScheme) private var colorScheme
    /// the trailing values' column, the same in every lane so the lanes line up
    @ScaledMetric(relativeTo: .caption2) private var axisWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption2) private var hourRowHeight: CGFloat = 16
    /// between the lanes: a lane's top value and the bottom one of the lane above (half a label each way) don't meet
    /// at a large text size
    @ScaledMetric(relativeTo: .caption2) private var laneGap: CGFloat = 10

    /// `.equatable()`: by what it shows (the call site's actions, the `open…` ones too, are new closures every time)
    nonisolated static func == (lhs: HomeOnBoardCard, rhs: HomeOnBoardCard) -> Bool {
        lhs.content == rhs.content && lhs.showGlucose == rhs.showGlucose && lhs.showCOB == rhs.showCOB
    }

    var body: some View {
        let lanes = content.lanes(showGlucose: showGlucose, showCOB: showCOB)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                // the row is 44 pt tall (`HomeCardMetrics`): the space above and below it is mostly in it
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    VStack(spacing: laneGap) {
                        ForEach(lanes, id: \.self) { lane in
                            laneRow(lane)
                                .frame(height: Content.height(of: lane, in: lanes))
                        }
                    }
                    hourRow
                }
                footer
            }
            .padding(.top, 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Parts

    /// "On board", the other cards' header height
    private var header: some View {
        Text("On board")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: HomeCardMetrics.headerMinHeight, alignment: .leading)
    }

    /// The lane's chart, its values in the trailing column (positioned on the chart's plot). A button, the whole lane
    /// its target: Statistics on the lane's topic (a plain tap; the long-press stays the card's menu).
    private func laneRow(_ lane: Lane) -> some View {
        Button(action: open(lane)) {
            switch lane {
            case .glucose: laneRow(glucoseChart, labels: content.glucoseLevels)
            case .cob: laneRow(cobChart, labels: content.cobLabels)
            case .iob: laneRow(iobChart, labels: content.iobLabels)
            }
        }
        .buttonStyle(.plain)
    }

    private func open(_ lane: Lane) -> @MainActor @Sendable() -> Void {
        switch lane {
        case .glucose: return openGlucose
        case .cob: return openMeals
        case .iob: return openInsulin
        }
    }

    private func laneRow<ChartView: View>(_ chart: ChartView, labels: [AxisLabel]) -> some View {
        HStack(spacing: 0) {
            chart
                .chartXScale(domain: content.window.start ... content.window.end)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                // no mark past the plot (an IOB line at the domain's edge, a dot's half) into the lane next to it
                .chartPlotStyle { plot in
                    plot.clipped()
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plot = proxy.plotFrame.map({ geometry[$0] }) {
                            ForEach(labels, id: \.value) { label in
                                if let y = proxy.position(forY: label.value) {
                                    Text(label.text)
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                        .frame(width: axisWidth - 4, alignment: .leading)
                                        .position(x: plot.maxX + 4 + (axisWidth - 4) / 2, y: plot.minY + y)
                                }
                            }
                        }
                    }
                }
            Color.clear
                .frame(width: axisWidth)
        }
        // the values' column too
        .contentShape(Rectangle())
    }

    private var gridColor: Color {
        Color(uiColor: colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray5)
    }

    /// the lane's own vertical gridlines, every 2 h: none crosses the gaps between the lanes
    @ChartContentBuilder private var hourGrid: some ChartContent {
        ForEach(content.hourTicks, id: \.date) { tick in
            RuleMark(x: .value("Time", tick.date))
                .foregroundStyle(gridColor)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    @ChartContentBuilder private func valueGrid(_ labels: [AxisLabel]) -> some ChartContent {
        ForEach(labels, id: \.value) { label in
            RuleMark(y: .value("Value", label.value))
                .foregroundStyle(gridColor)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    /// The readings as dots in their band's colour (the Statistics', `GlucoseBand.color`), the in-range band's edges
    /// dashed (no gridlines across).
    private var glucoseChart: some View {
        Chart {
            hourGrid
            ForEach(content.glucoseLevels, id: \.value) { level in
                RuleMark(y: .value("Glucose", level.value))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            // by index: two readings can share a time
            ForEach(content.glucose.indices, id: \.self) { index in
                PointMark(
                    x: .value("Time", content.glucose[index].date),
                    y: .value("Glucose", Double(content.glucose[index].mgdl))
                )
                .foregroundStyle(content.glucose[index].band.color)
                .symbolSize(5)
            }
        }
        .chartYScale(domain: content.glucoseDomain)
    }

    /// As the COB chart was: LoopYellow with its gradient, at 0.8.
    private var cobChart: some View {
        Chart {
            hourGrid
            valueGrid(content.cobLabels)
            ForEach(content.cob.indices, id: \.self) { index in
                AreaMark(
                    x: .value("Time", content.cob[index].date),
                    y: .value("COB", content.cob[index].value)
                )
                .foregroundStyle(Color(.loopYellow).gradient)
                .opacity(0.8)
            }
        }
        .chartYScale(domain: content.cobDomain)
    }

    /// As the IOB chart was: the area above 0 in the insulin colour, full at the top to 0.4, red below 0, a thin line.
    private var iobChart: some View {
        Chart {
            hourGrid
            valueGrid(content.iobLabels)
            ForEach(content.iob.indices, id: \.self) { index in
                let point = content.iob[index]
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("IOB", 0),
                    yEnd: .value("IOB", Swift.max(0, point.value))
                )
                .foregroundStyle(by: .value("Part", "IOB > 0"))
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("IOB", 0),
                    yEnd: .value("IOB", Swift.min(0, point.value))
                )
                .foregroundStyle(by: .value("Part", "IOB < 0"))
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("IOB", point.value)
                )
                .foregroundStyle(by: .value("Part", "Line IOB > 0"))
                .lineStyle(StrokeStyle(lineWidth: 0.8))
            }
        }
        .chartForegroundStyleScale(
            [
                "IOB > 0": LinearGradient(
                    gradient: Gradient(colors: [
                        Color.insulin.opacity(1),
                        Color.insulin.opacity(0.4)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ),
                "IOB < 0": LinearGradient(
                    gradient: Gradient(colors: [
                        Color.red.opacity(1),
                        Color.red.opacity(1)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ),
                "Line IOB > 0": LinearGradient(
                    gradient: Gradient(colors: [
                        Color.insulin.opacity(1),
                        Color.insulin.opacity(1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            ]
        )
        .chartYScale(domain: content.iobDomain)
    }

    /// The even hours under the lanes, on the plot's width (the trailing column stays free).
    private var hourRow: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
                ForEach(content.hourTicks, id: \.date) { tick in
                    Text(tick.label)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .position(x: tick.fraction * geometry.size.width, y: geometry.size.height / 2)
                }
            }
            Color.clear
                .frame(width: axisWidth)
        }
        .frame(height: hourRowHeight)
        .padding(.top, 2)
    }

    /// A red swatch and "Negative IOB 1 h 25 min": the last 24 hours. A button: Statistics › Insulin at 7 d on the
    /// Negative IOB card; its target reaches past the row (the row's height stays the card's).
    private var footer: some View {
        Button(action: openNegativeIOB) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Negative IOB")
                        .foregroundStyle(.secondary)
                    Text(content.negativeIOB)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                }
                .lineLimit(1)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.vertical, -8)
        }
        .buttonStyle(.plain)
    }
}

/// The On board card's long-press menu (the card's `.contextMenu`, `HomeRootView`): the glucose and the carbs on board
/// lanes (insulin on board always). The carbs toggle is disabled, still showing its setting, while the card has no
/// carbs (`HomeOnBoardCard.Content.hasCarbs`).
struct HomeOnBoardMenu: View {
    let showGlucose: Bool
    let showCOB: Bool
    let hasCarbs: Bool
    let setShowGlucose: @MainActor @Sendable(Bool) -> Void
    let setShowCOB: @MainActor @Sendable(Bool) -> Void

    // explicit: the synthesized memberwise init drops `@Sendable` from the closures in this target (`HomeOnBoardCard`)
    init(
        showGlucose: Bool,
        showCOB: Bool,
        hasCarbs: Bool,
        setShowGlucose: @escaping @MainActor @Sendable(Bool) -> Void,
        setShowCOB: @escaping @MainActor @Sendable(Bool) -> Void
    ) {
        self.showGlucose = showGlucose
        self.showCOB = showCOB
        self.hasCarbs = hasCarbs
        self.setShowGlucose = setShowGlucose
        self.setShowCOB = setShowCOB
    }

    var body: some View {
        Section("Show") {
            Toggle("Glucose", isOn: Binding(get: { [showGlucose] in showGlucose }, set: setShowGlucose))
            Toggle("Carbs on board", isOn: Binding(get: { [showCOB] in showCOB }, set: setShowCOB))
                .disabled(!hasCarbs)
        }
    }
}
