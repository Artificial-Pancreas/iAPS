import SwiftUI

/// The insulin card on Home: Today, no range of its own (" · Today" after the title, no menu). Tap opens the Statistics
/// Insulin tab on Today.
///
/// The insulin so far, big in the header, and under it, muted, yesterday's insulin by this clock time ("yesterday by
/// 14:35 · 21.2 U"; not without pump data yesterday). The chart: the 7 days before today, each a light bar of the whole
/// day (a complete day's TDD, the basal scaled by its coverage; another as delivered) with a solid part up to this clock
/// time that day, its whole day's total above it ("45", "18.4": `Content.totalText`, rotated, where it fits), a dash
/// without pump data; then today, a wider bar: its outline the mean day of the 7 (over the complete ones), its fill the
/// insulin so far, a small tick on each side of it the usual by this clock time (`InsulinStatsEngine.clockAverage` over
/// the same days: Statistics › Insulin › Today's). "32.5 U daily avg" and "18.0 U usual" labelled on the right, at
/// their heights. Fewer than 7 complete days: "n d avg" and the limited marker.
///
/// Nothing on it moves with the clock: it is as of the read ("by 14:35" is the read's time), so it stays truthful
/// between reads. It changes with a read only: the insulin data, the foreground, midnight
/// (`Home.StateModel.subscribeHomeInsulin`).
struct HomeInsulinCard: View, Equatable {
    /// What the card shows, formatted off the main actor (`Home.Provider.insulinCard`) as of the read's time. Compared
    /// as shown: a result that displays the same doesn't re-render Home. The heights are fractions of the plot's
    /// (`headroom` above the tallest), rounded to `fractionStep`.
    struct Content: Equatable, Sendable {
        /// A past day's bar.
        struct Day: Equatable, Sendable {
            /// "M": the weekday's very short symbol, in the calendar's locale
            let label: String
            /// the whole day: a complete (headline) day's TDD, the basal scaled by its coverage
            /// (`DayInsulin.scaledTotal`: their mean is the mean day); another as delivered (`total`: a day barely
            /// covered isn't extrapolated); nil without pump data (a dash)
            let whole: Double?
            /// its insulin up to this clock time, scaled as `whole` (`DayInsulin.scaledInsulin(hour:passed:)`, or
            /// `deliveredInsulin(hour:passed:)`); nil without pump data
            let byNow: Double?
            /// the whole day's total, above the bar (rotated): "30", "18.4" (`totalText`); nil without pump data
            let wholeText: String?
        }

        /// Today's bar.
        struct Today: Equatable, Sendable {
            /// the fill: so far; nil without pump data today (a dash)
            let soFar: Double?
            /// the outline: the mean day of the past days; nil without a complete one
            let meanDay: Double?
            /// the ticks: the usual by this clock time; nil without a complete day
            let usual: Double?
        }

        /// Yesterday's insulin by this clock time, under so far in the header: "yesterday by 14:35" "21.2 U" (drawn
        /// "yesterday by 14:35 · 21.2 U").
        struct Yesterday: Equatable, Sendable {
            let label: String
            let value: String
        }

        /// A label right of today's bar, at the height of its mark: "41.2" "daily avg" (drawn "41.2 U daily avg").
        struct RailLabel: Equatable, Sendable, Identifiable {
            let id: Int
            let name: String
            let value: String
            let height: Double
        }

        /// the days before today on the chart, and the days the mean day and the usual are over: Statistics › Insulin
        /// › Today's
        static let pastDays = InsulinStatsEngine.usualDays
        /// 1e-3 of the plot's height: well below a pixel
        static let fractionStep = 1E-3
        /// the plot's top above the tallest of the complete days' bars, the mean day and so far
        static let headroom = 1.04

        /// "Insulin"
        let title: String
        /// so far: "17.5", "–"
        let value: String
        /// fewer than `pastDays` complete days: the limited marker
        let isLimited: Bool
        /// yesterday by this clock time, under so far; nil without pump data yesterday
        let yesterday: Yesterday?
        /// the past days, oldest -> newest
        let days: [Day]
        let today: Today
        /// "Today", under today's bar
        let todayLabel: String
        /// "daily avg" (or "5 d avg"), "usual"; the ones with a value
        let rail: [RailLabel]

        /// - Parameters:
        ///   - days: `InsulinStatsService.days(last: pastDays + 1)`: the days before today and today, the last one
        ///   - now: the read's time: each day's insulin and the usual by it
        ///
        /// The plot's top is the tallest of the complete days' bars, the mean day and so far: another day's (as
        /// delivered, not extrapolated) doesn't set it, and is drawn clipped at the top in the rare case it is above
        /// them; only without any of them do the other days set it.
        init(days: [DayInsulin], now: Date, calendar: Calendar) {
            let today = days.last
            let past = Array(days.dropLast().suffix(Self.pastDays))
            let minute = Self.minute(of: now, in: today?.day, calendar: calendar)
            let clock = InsulinClockAverage.clock(of: minute, calendar: calendar)

            // without covered time today's basal is unknown (the Insulin tab's "–")
            let soFar = (today?.coveredSeconds ?? 0) > 0 ? today?.total : nil
            let complete = past.filter(\.isHeadline)
            let meanDay = complete.isEmpty ? nil : complete.reduce(0) { $0 + $1.scaledTotal } / Double(complete.count)
            let usual = InsulinStatsEngine.clockAverage(past)?.value(hour: clock.hour, passed: clock.passed)
            // a complete day scaled (the mean of them is the mean day), another as delivered
            let bars = past.map { day -> (whole: Double, byNow: Double)? in
                guard day.hasData else { return nil }
                return day.isHeadline
                    ? (whole: day.scaledTotal, byNow: day.scaledInsulin(hour: clock.hour, passed: clock.passed))
                    : (whole: day.total, byNow: day.deliveredInsulin(hour: clock.hour, passed: clock.passed))
            }
            // the last past day is yesterday
            let yesterday = bars.last.flatMap { $0?.byNow }
            let completeTop = (complete.map(\.scaledTotal) + [meanDay ?? 0, soFar ?? 0]).max() ?? 0
            let top = (completeTop > 0 ? completeTop : bars.compactMap { $0?.whole }.max() ?? 0) * Self.headroom
            let isLimited = complete.count < Self.pastDays

            let time = Self.clockTime(minute, calendar: calendar)

            title = NSLocalizedString("Insulin", comment: "")
            value = soFar.map { StatsAmount.number($0, digits: 1) } ?? "–"
            self.isLimited = isLimited
            self.yesterday = yesterday.map {
                Yesterday(
                    label: String(
                        format: NSLocalizedString(
                            "yesterday by %@",
                            comment: "Home insulin card: under today's insulin, yesterday's by this clock time, \"14:35\""
                        ),
                        time
                    ),
                    value: StatsAmount.units($0, digits: 1)
                )
            }
            self.days = zip(past, bars).map { day, bar in
                Day(
                    label: Self.weekday(day.day.start, calendar: calendar),
                    whole: bar.map { Self.fraction($0.whole, of: top) },
                    byNow: bar.map { Self.fraction($0.byNow, of: top) },
                    wholeText: bar.map { Self.totalText($0.whole) }
                )
            }
            self.today = Today(
                soFar: soFar.map { Self.fraction($0, of: top) },
                meanDay: meanDay.map { Self.fraction($0, of: top) },
                usual: usual.map { Self.fraction($0, of: top) }
            )
            todayLabel = NSLocalizedString("Today", comment: "")

            var rail: [RailLabel] = []
            if let meanDay {
                rail.append(RailLabel(
                    id: 0,
                    name: isLimited
                        ? String(
                            format: NSLocalizedString(
                                "%d d avg",
                                comment: "Home insulin card: the daily average over fewer than 7 complete days, \"5 d avg\""
                            ),
                            complete.count
                        )
                        : NSLocalizedString(
                            "daily avg",
                            comment: "Home insulin card: the daily average of the last 7 days, \"32.5 U daily avg\""
                        ),
                    value: StatsAmount.number(meanDay, digits: 1),
                    height: Self.fraction(meanDay, of: top)
                ))
            }
            if let usual {
                rail.append(RailLabel(
                    id: 1,
                    name: NSLocalizedString("usual", comment: "Home insulin card: the usual insulin by this clock time"),
                    value: StatsAmount.number(usual, digits: 1),
                    height: Self.fraction(usual, of: top)
                ))
            }
            self.rail = rail
        }

        // MARK: Formatting

        /// The read's time to the minute, inside the read's today (not expected outside it: the read's today is the day
        /// of its time); without days, the day of the time.
        private static func minute(of date: Date, in day: DateInterval?, calendar: Calendar) -> Date {
            let day = day ?? calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 0)
            let lastMinute = calendar.dateInterval(of: .minute, for: day.end.addingTimeInterval(-1))?.start ?? day.start
            let clamped = Swift.min(Swift.max(date, day.start), lastMinute)
            return calendar.dateInterval(of: .minute, for: clamped)?.start ?? clamped
        }

        /// a share of the plot's height, rounded to `fractionStep`
        private static func fraction(_ value: Double, of top: Double) -> Double {
            guard top > 0 else { return 0 }
            return (Swift.min(Swift.max(value / top, 0), 1) / fractionStep).rounded() * fractionStep
        }

        /// a past day's total up to this (by the unrounded total) with a decimal, above it in whole units
        static let totalDecimalLimit = 20.0

        /// "45", "18.4": a past day's total above its bar, without the unit, rounded half away from zero; up to
        /// `totalDecimalLimit` U with a decimal (20.0 U "20.0", 18.44 U "18.4", 0 U "0.0"), above it in whole units
        /// (20.04 U "20", 45.5 U "46")
        static func totalText(_ whole: Double) -> String {
            StatsAmount.number(whole, digits: whole <= totalDecimalLimit ? 1 : 0)
        }

        /// "M": the very short weekday symbol of the date, in the calendar's locale
        static func weekday(_ date: Date, calendar: Calendar) -> String {
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            let index = calendar.component(.weekday, from: date) - 1
            return symbols.indices.contains(index) ? symbols[index] : ""
        }

        /// "14:35", "2:35 PM", in the calendar's time zone
        static func clockTime(_ date: Date, calendar: Calendar) -> String {
            date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone))
        }
    }

    let content: Content
    /// the Statistics Insulin tab on Today
    let open: () -> Void

    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 28
    /// pt the yesterday line is drawn up into the header row's room under so far (the row is at least 44 pt, the value
    /// less tall)
    @ScaledMetric(relativeTo: .caption) private var yesterdayLift: CGFloat = 4
    /// pt between the yesterday line and the chart (the past days' totals at its top)
    private static let yesterdaySpacing: CGFloat = 8
    /// the day labels' row under the plot
    @ScaledMetric(relativeTo: .caption2) private var labelRow: CGFloat = 18
    /// the past days' totals above their bars (`HomeInsulinChart.totalFontSize` at the default size)
    @ScaledMetric(relativeTo: .caption2) private var totalSize: CGFloat = HomeInsulinChart.totalFontSize
    @Environment(\.colorScheme) private var colorScheme

    /// `.equatable()`: Home's re-renders that don't change what it shows skip its body; by what it shows (the call
    /// site's action is a new closure every time, the same action)
    nonisolated static func == (lhs: HomeInsulinCard, rhs: HomeInsulinCard) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                // the row is 44 pt tall (`HomeCardMetrics`): the space above and below it is mostly in it
                .padding(.top, 8)
            Button(action: open) {
                chart
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Insulin · Today", so far with its unit; under it, its trailing edge under the unit's, yesterday by now
    private var header: some View {
        VStack(alignment: .soFarTrailing, spacing: 0) {
            HomeCardHeader(title: content.title, rangeLabel: StatsFormatting.label(.today), open: open) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(content.value)
                            .font(.system(size: valueSize, weight: .bold))
                            .monospacedDigit()
                        Text(NSLocalizedString("U", comment: ""))
                            .font(.system(size: valueSize * 17 / 28, weight: .semibold))
                    }
                    .alignmentGuide(.soFarTrailing) { $0[.trailing] }
                    if content.isLimited {
                        LimitedDataMarker(note: nil, font: .footnote)
                            .padding(.leading, 3)
                    }
                }
                .lineLimit(1)
            }
            if let yesterday = content.yesterday {
                let value = Text(yesterday.value).fontWeight(.semibold).foregroundStyle(.primary)
                // up into the row's room under so far (the row is taller than the value): close under it
                Text("\(Text(yesterday.label)) · \(value)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .alignmentGuide(.soFarTrailing) { $0[.trailing] }
                    .padding(.top, -yesterdayLift)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: open)
                    // clear of the past days' totals at the chart's top: the card grows by it, the chart as tall
                    // (without the line, the header row's own room under so far is enough)
                    .padding(.bottom, Self.yesterdaySpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        let content = self.content
        let totalSize = self.totalSize
        let palette = HomeInsulinChart.Palette(
            insulin: Color(.insulin),
            wholeDay: Color(.insulin).opacity(colorScheme == .dark ? 0.4 : 0.3),
            meanDayFill: Color(.insulin).opacity(colorScheme == .dark ? 0.16 : 0.1),
            label: Color(.label),
            secondary: Color(.secondaryLabel),
            card: colorScheme == .dark ? IAPSconfig.previewBackgroundDark : IAPSconfig.previewBackgroundLight,
            baseline: Color(.systemGray4),
            dash: Color(.systemGray3)
        )
        return Canvas { context, size in
            HomeInsulinChart.draw(content, in: &context, size: size, palette: palette, totalSize: totalSize)
        }
        .frame(maxWidth: .infinity)
        .frame(height: HomeInsulinChart.plotHeight + labelRow)
    }
}

private extension HorizontalAlignment {
    /// the trailing edge of so far's unit in the header: the yesterday line's under it
    enum SoFarTrailing: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.trailing]
        }
    }

    static var soFarTrailing: HorizontalAlignment {
        HorizontalAlignment(SoFarTrailing.self)
    }
}

/// The card's chart, drawn (`HomeInsulinCard.chart`'s canvas): the past days' bars from the left (their totals rotated
/// above them), today's wider bar, the rail's labels right of it, the day labels under the baseline. No y axis.
enum HomeInsulinChart {
    /// The colours, resolved by the canvas (light and dark).
    struct Palette {
        let insulin: Color
        /// a past day's whole day
        let wholeDay: Color
        /// today's outline's fill
        let meanDayFill: Color
        /// the usual's ticks, the mean day's line across the fill, the values
        let label: Color
        /// the names, the day labels, the past days' totals, the leaders
        let secondary: Color
        /// the halo around the mean day's line: the card's background
        let card: Color
        let baseline: Color
        /// a day without pump data
        let dash: Color
    }

    /// pt: the plot, from the top to the baseline: the bars' 84 pt and `topInset` above them
    static let plotHeight: CGFloat = 109
    /// pt above a bar of the plot's full height: a past day's total rotated above it (`totalLabelBottom`; a bar is at
    /// most 1 / `Content.headroom` of the full height, so its total has this and a little more: 24.2 pt above the
    /// tallest bar's top less `totalGap`). The longest total that fits there at the default size: one with a decimal
    /// ("18.8", 22.3 pt long; the tallest bar only on a card of low totals) and three digits ("100"–"999", 19.2 pt);
    /// four ("1000", 25.7 pt) are skipped
    static let topInset: CGFloat = 25
    /// pt between a bar's top and its total above it
    static let totalGap: CGFloat = 4
    /// pt: the past days' totals at the default size (a step under caption2's 11, scaled with it), muted
    static let totalFontSize: CGFloat = 10
    /// the usual's ticks beside today's bar: their length, their thickness, and their distance from its edges
    static let usualTickLength: CGFloat = 4
    static let usualTickThickness: CGFloat = 1.5
    static let usualTickGap: CGFloat = 1.5
    /// today's bar, and the space before it
    static let todayWidth: CGFloat = 28
    static let todayGap: CGFloat = 12
    /// a past day's bar at most, and its share of its slot
    static let barWidth: CGFloat = 16
    static let barShare: CGFloat = 0.58
    /// from today's bar to the rail's labels: the usual's right tick, then the leaders
    static let leaderSpace: CGFloat = 18
    /// pt clear between the usual's right tick and a leader's start: the leader at the usual's height, in line with the
    /// tick, doesn't read as one line with it
    static let leaderClearance: CGFloat = 3
    /// a leader's start right of today's bar: past the usual's right tick, `leaderClearance` after it
    static let leaderStart: CGFloat = usualTickGap + usualTickLength + leaderClearance
    /// the rail's labels at most this share of the width (a longer name cut with "…")
    static let railShare: CGFloat = 0.45
    /// pt: the least a bar is drawn, in the insulin colour: a day with pump data but no insulin (or next to none)
    /// isn't a "no pump data" dash
    static let stubHeight: CGFloat = 1
    /// pt: today's fill's top this close below the outline's top (or above it) hides the outline's stroke: the mean day
    /// is then drawn as a line across the fill
    static let meanDayLineReach: CGFloat = 2

    /// pt above the baseline: a share of the plot's height (`topInset` left above a full one)
    static func height(_ fraction: Double) -> CGFloat {
        CGFloat(fraction) * (plotHeight - topInset)
    }

    /// A bar's height above the baseline: `height(fraction)`, at least `stubHeight`; `isStub` when it is under that
    /// (drawn as the stub, in the insulin colour).
    static func barHeight(_ fraction: Double) -> (height: CGFloat, isStub: Bool) {
        let drawn = height(fraction)
        return drawn < stubHeight ? (stubHeight, true) : (drawn, false)
    }

    /// The mean day drawn as a line across today's fill: so far reaches within `meanDayLineReach` below the mean day,
    /// or past it (the outline's stroke would merge with the fill).
    static func drawsMeanDayLine(_ today: HomeInsulinCard.Content.Today) -> Bool {
        guard let soFar = today.soFar, let meanDay = today.meanDay else { return false }
        return height(soFar) >= height(meanDay) - meanDayLineReach
    }

    /// The usual's two ticks at `y` (its height's y): one left of today's bar, one right of it, `usualTickGap` outside
    /// its edges, `usualTickLength` long, `usualTickThickness` thick, centred on `y`.
    static func usualTicks(barX: CGFloat, barWidth: CGFloat, y: CGFloat) -> [CGRect] {
        let top = y - usualTickThickness / 2
        return [
            CGRect(
                x: barX - usualTickGap - usualTickLength,
                y: top,
                width: usualTickLength,
                height: usualTickThickness
            ),
            CGRect(x: barX + barWidth + usualTickGap, y: top, width: usualTickLength, height: usualTickThickness)
        ]
    }

    /// Where a past day's total (rotated, reading bottom to top) ends at the bottom, its y: `totalGap` above the bar's
    /// top; nil when it doesn't fit: its thickness wider than the day's slot (less 1 pt, so two never touch), or its
    /// length above the canvas's top.
    /// - Parameters:
    ///   - barTop: the bar's top, y
    ///   - size: the total's text, unrotated (its width is its length upright)
    static func totalLabelBottom(barTop: CGFloat, size: CGSize, slot: CGFloat) -> CGFloat? {
        guard size.height <= slot - 1 else { return nil }
        let bottom = barTop - totalGap
        return bottom - size.width >= 0 ? bottom : nil
    }

    /// The rail's label centres, in the order given: top to bottom by their true heights, each at its true y, pushed
    /// down below the one above it by `gap` and not above `minY`; the last one pulled up to `maxY` when it is below,
    /// the ones above it with it.
    static func railPositions(_ ys: [CGFloat], gap: CGFloat, minY: CGFloat, maxY: CGFloat) -> [CGFloat] {
        let order = ys.indices.sorted { (ys[$0], $0) < (ys[$1], $1) }
        var placed = ys
        var previous: CGFloat?
        for index in order {
            let y = Swift.max(minY, previous.map { Swift.max(ys[index], $0 + gap) } ?? ys[index])
            placed[index] = y
            previous = y
        }
        if let last = order.last, placed[last] > maxY {
            placed[last] = maxY
            for k in order.indices.dropLast().reversed() {
                placed[order[k]] = Swift.min(placed[order[k]], placed[order[k + 1]] - gap)
            }
        }
        return placed
    }

    static func draw(
        _ content: HomeInsulinCard.Content,
        in context: inout GraphicsContext,
        size: CGSize,
        palette: Palette,
        totalSize: CGFloat = totalFontSize
    ) {
        let plot = plotHeight
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        func y(_ fraction: Double) -> CGFloat {
            plot - height(fraction)
        }
        /// a bar from the baseline up to `top`
        func bar(x: CGFloat, width: CGFloat, top: CGFloat, radius: CGFloat) -> Path? {
            guard plot - top > 0 else { return nil }
            return Path(roundedRect: CGRect(x: x, y: top, width: width, height: plot - top), cornerRadius: radius)
        }
        /// in the label colour, with a thin halo of the card's background: seen over the fill and the outline
        func haloed(_ path: Path) {
            context.stroke(path, with: .color(palette.card), lineWidth: 2)
            context.fill(path, with: .color(palette.label))
        }
        /// the stub of a bar under `stubHeight`, from the baseline
        func stub(x: CGFloat, width: CGFloat) {
            context.fill(
                Path(CGRect(x: x, y: plot - stubHeight, width: width, height: stubHeight)),
                with: .color(palette.insulin)
            )
        }

        // the rail's labels, one line each, the value before its name ("32.5 U daily avg"): their width leaves the bars
        // theirs, a longer name cut with "…" (the value always shown; a canvas's text has no line limit: drawn at a
        // point, it isn't wrapped)
        let maxLabelWidth = size.width * railShare
        let unit = NSLocalizedString(" U", comment: "Insulin unit")
        func railText(_ name: String, value: String) -> GraphicsContext.ResolvedText {
            let valueText = Text(value + unit).fontWeight(.semibold).foregroundStyle(palette.label)
            let nameText = Text(name).foregroundStyle(palette.secondary)
            return context.resolve(Text("\(valueText) \(nameText)").font(.caption2).monospacedDigit())
        }
        let railTexts = content.rail.map { label in
            var name = label.name
            var text = railText(name, value: label.value)
            while text.measure(in: unbounded).width > maxLabelWidth, name.isNotEmpty {
                name.removeLast()
                text = railText(name.trimmingCharacters(in: .whitespaces) + "…", value: label.value)
            }
            return text
        }
        let railSizes = railTexts.map { $0.measure(in: unbounded) }
        let labelsWidth = railSizes.map(\.width).max() ?? 0
        let railWidth = content.rail.isEmpty ? 0 : leaderSpace + labelsWidth
        let barsWidth = Swift.max(size.width - railWidth, todayWidth + todayGap + 1)
        let slot = (barsWidth - todayWidth - todayGap) / CGFloat(Swift.max(content.days.count, 1))
        let width = Swift.min(barWidth, slot * barShare)
        let todayX = barsWidth - todayWidth

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: plot + 0.5))
        baseline.addLine(to: CGPoint(x: barsWidth, y: plot + 0.5))
        context.stroke(baseline, with: .color(palette.baseline), lineWidth: 1)

        var dashes = Path()
        func dash(at x: CGFloat, half: CGFloat) {
            dashes.move(to: CGPoint(x: x - half, y: plot - 1))
            dashes.addLine(to: CGPoint(x: x + half, y: plot - 1))
        }

        // the past days: light the whole day, solid by this clock time that day
        for (index, day) in content.days.enumerated() {
            let centre = CGFloat(index) * slot + slot / 2
            if let whole = day.whole, let byNow = day.byNow {
                let x = centre - width / 2
                if barHeight(whole).isStub {
                    // pump data, (next to) no insulin
                    stub(x: x, width: width)
                } else {
                    if let path = bar(x: x, width: width, top: y(whole), radius: 2) {
                        context.fill(path, with: .color(palette.wholeDay))
                    }
                    if let path = bar(x: x, width: width, top: y(byNow), radius: 2) {
                        context.fill(path, with: .color(palette.insulin))
                    }
                }
                // the whole day's total above it, rotated to read bottom to top, where it fits
                if let text = day.wholeText {
                    let resolved = context.resolve(
                        Text(text).font(.system(size: totalSize)).monospacedDigit().foregroundStyle(palette.secondary)
                    )
                    let textSize = resolved.measure(in: unbounded)
                    let barTop = barHeight(whole).isStub ? plot - stubHeight : y(whole)
                    if let bottom = totalLabelBottom(barTop: barTop, size: textSize, slot: slot) {
                        var rotated = context
                        rotated.translateBy(x: centre, y: bottom)
                        rotated.rotate(by: .degrees(-90))
                        rotated.draw(resolved, at: .zero, anchor: .leading)
                    }
                }
            } else {
                dash(at: centre, half: Swift.max(Swift.min(4, width / 2 - 1), 1))
            }
            context.draw(
                context.resolve(Text(day.label).font(.caption2).foregroundStyle(palette.secondary)),
                at: CGPoint(x: centre, y: plot + 3),
                anchor: .top
            )
        }

        // today: the outline the mean day, the fill so far, the ticks the usual by now
        let today = content.today
        if let meanDay = today.meanDay,
           let path = bar(x: todayX + 0.5, width: todayWidth - 1, top: y(meanDay), radius: 3)
        {
            context.fill(path, with: .color(palette.meanDayFill))
            context.stroke(path, with: .color(palette.insulin), lineWidth: 1)
        }
        if let soFar = today.soFar {
            if barHeight(soFar).isStub {
                stub(x: todayX, width: todayWidth)
            } else if let path = bar(x: todayX, width: todayWidth, top: y(soFar), radius: 3) {
                context.fill(path, with: .color(palette.insulin))
            }
        } else {
            dash(at: todayX + todayWidth / 2, half: 4)
        }
        context.stroke(dashes, with: .color(palette.dash), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        // at or past the mean day (or within a stroke's reach below it): the outline's top across the fill, so the mean
        // day stays seen
        if drawsMeanDayLine(today), let meanDay = today.meanDay {
            haloed(Path(CGRect(x: todayX, y: y(meanDay) - 0.75, width: todayWidth, height: 1.5)))
        }
        // the usual: a small tick on each side of the bar, outside it (on the card's background: no halo)
        if let usual = today.usual {
            var ticks = Path()
            for tick in usualTicks(barX: todayX, barWidth: todayWidth, y: y(usual)) {
                ticks.addRoundedRect(in: tick, cornerSize: CGSize(width: 0.75, height: 0.75))
            }
            context.fill(ticks, with: .color(palette.label))
        }
        context.draw(
            context.resolve(Text(content.todayLabel).font(.caption2.weight(.bold)).foregroundStyle(palette.label)),
            at: CGPoint(x: todayX + todayWidth / 2, y: plot + 3),
            anchor: .top
        )

        // the rail: each label at its mark's height, pushed apart, a leader to the true height
        guard railTexts.isNotEmpty else { return }
        let gap = railSizes.map(\.height).max() ?? 0
        let marks = content.rail.map { y($0.height) }
        let placed = railPositions(marks, gap: gap, minY: gap / 2, maxY: plot - gap / 2)
        let barEnd = todayX + todayWidth
        let labelX = barEnd + leaderSpace
        var leaders = Path()
        for index in railTexts.indices {
            leaders.move(to: CGPoint(x: barEnd + leaderStart, y: marks[index]))
            leaders.addLine(to: CGPoint(x: barEnd + leaderStart + 2, y: marks[index]))
            leaders.addLine(to: CGPoint(x: labelX - 3, y: placed[index]))
        }
        context.stroke(leaders, with: .color(palette.secondary.opacity(0.7)), lineWidth: 0.8)
        for index in railTexts.indices {
            context.draw(railTexts[index], at: CGPoint(x: labelX, y: placed[index]), anchor: .leading)
        }
    }
}
