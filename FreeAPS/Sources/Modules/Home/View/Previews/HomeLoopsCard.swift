import SwiftUI

/// The Loops card on Home, below the stats bar, the last 24 hours (`Home.loopsRange`, its name muted after the title):
/// the share of the loops due that ran (`HomeLoopStats`: per slot, a failed loop retried counts once), a timeline
/// of the range (a column per half hour of the clock, yesterday's dimmed, a tick at midnight with today's share under
/// it; the gaps of 15 min or more marked), the loops that ran and the CGM readings (plain counts, not per slot), the
/// longest gap; as of its last read (the header shows the loop status). Tap opens the Loops screen (`LoopHistory`),
/// whose share is the same.
struct HomeLoopsCard: View, Equatable {
    /// What the card shows, formatted once per result (`Home.StateModel`). Compared as shown: strings, and the strip's
    /// geometry rounded to `fractionStep`, so a result that displays the same doesn't re-render Home.
    struct Content: Equatable, Sendable {
        /// 1e-3 of the strip: about 0.35 pt on a phone, below a pixel at 2x
        static let fractionStep = 1E-3
        /// the shortest longest gap the card shows ("Max gap" is absent below it, also while ongoing)
        static let minGapShown: TimeInterval = .minutes(10)

        /// "24 h"
        let range: String
        let isEmpty: Bool
        /// "97.3", "100", "–" (no readings)
        let percent: String
        let hasPercent: Bool
        /// "1,234 loops · 1,440 readings" (`counts(loops:readings:)`): the "Success" records in the window (every loop
        /// that ran, not per slot) and the CGM readings in it (exact duplicates once, not thinned: a 1-minute CGM's
        /// every one)
        let counts: String
        /// "2 h 5 min"; nil without a gap of `minGapShown` or more
        let maxGap: String?
        /// today's columns, and those before midnight (dimmed)
        let columns: [LoopStripColumns.Column]
        let pastColumns: [LoopStripColumns.Column]
        let gapMarks: [LoopStripGapMarks.Mark]
        /// midnight on the strip (a fraction of it), with today's share under it ("Today 97.3%", the share in the
        /// primary colour); nil when the strip is today only (or none of it)
        let todayMark: Double?
        /// today's share under the tick: "97.3%"; nil without today's slots ("Today" alone)
        let todayPercent: String?

        @MainActor init(_ stats: HomeLoopStats) {
            range = StatsFormatting.label(stats.period)
            isEmpty = stats.isEmpty
            if let value = stats.percent {
                percent = Self.percent(value)
                hasPercent = true
            } else {
                percent = "–"
                hasPercent = false
            }
            counts = Self.counts(loops: stats.successfulLoops, readings: stats.readings)
            maxGap = Self.shownGap(stats).map { HomeLoopsCard.duration($0.duration) }

            let window = stats.window
            let columns = Self.columns(stats)
            let todayStart = window.duration > 0 ? stats.todayStart.timeIntervalSince(window.start) / window.duration : 0
            self.columns = columns.filter { $0.x >= Self.rounded(todayStart) }
            pastColumns = columns.filter { $0.x < Self.rounded(todayStart) }
            gapMarks = Self.gapMarks(stats)
            todayMark = todayStart > 0 && todayStart <= 1 ? Self.rounded(todayStart) : nil
            todayPercent = stats.todaySlots.percent.map { Self.percent($0) + "%" }
        }

        /// A reading changes the card before the next loop (which reads it too) only through the ongoing gap: once the
        /// newest loop start is as far back as the first gap the card shows (`minGapShown`, an ongoing one counting from
        /// `HomeLoopStats.Config.longGap`). Not without a loop start: no gap runs. (A reading adds a slot, which its
        /// loop fills: read with the loop.)
        /// - Parameter newestStart: the last result's (`HomeLoopStats.newestStart`)
        static func readingMayChange(newestStart: Date?, now: Date) -> Bool {
            guard let newestStart else { return false }
            return now.timeIntervalSince(newestStart) >= Swift.min(minGapShown, HomeLoopStats.Config.longGap)
        }

        /// the longest gap, once it is `minGapShown` long
        private static func shownGap(_ stats: HomeLoopStats) -> LoopGap? {
            guard let gap = stats.longestGap, gap.duration >= minGapShown else { return nil }
            return gap
        }

        // MARK: Formatting

        /// one decimal, "100" from 99.95 on: `shownPercent` formatted
        nonisolated static func percent(_ value: Double) -> String {
            let shown = shownPercent(value)
            guard shown < 100 else { return "100" }
            return shown.formatted(.number.precision(.fractionLength(1)).rounded(rule: .toNearestOrAwayFromZero))
        }

        /// The value `percent` shows: one decimal, half away from zero, 100 from 99.95 on (what a colour bin is chosen
        /// by: 94.96, shown "95.0", is 95).
        nonisolated static func shownPercent(_ value: Double) -> Double {
            guard value < 99.95 else { return 100 }
            return (value * 10).rounded(.toNearestOrAwayFromZero) / 10
        }

        /// "1 loop", "1,234 loops"
        nonisolated static func loops(_ count: Int) -> String {
            count == 1
                ? NSLocalizedString("1 loop", comment: "Home Loops card: loops counted")
                : String(format: NSLocalizedString("%@ loops", comment: "Home Loops card: loops counted"), count.formatted())
        }

        /// "1 reading", "1,440 readings"
        nonisolated static func readings(_ count: Int) -> String {
            count == 1
                ? NSLocalizedString("1 reading", comment: "Home Loops card: CGM readings counted")
                : String(
                    format: NSLocalizedString("%@ readings", comment: "Home Loops card: CGM readings counted"),
                    count.formatted()
                )
        }

        /// "1,234 loops · 1,440 readings": the card's counts (`counts`)
        nonisolated static func counts(loops count: Int, readings readingCount: Int) -> String {
            loops(count) + " · " + readings(readingCount)
        }

        /// "1,234 of 1,300 loops": the slots that succeeded, of the slots (the loops due): the Loops screen's
        nonisolated static func loops(_ successes: Int, of slots: Int) -> String {
            slots == 1
                ? String(
                    format: NSLocalizedString("%@ of 1 loop", comment: "Home Loops card: the loops that ran, of 1 due"),
                    successes.formatted()
                )
                : String(
                    format: NSLocalizedString(
                        "%1$@ of %2$@ loops",
                        comment: "Home Loops card: the loops that ran, of those due (\"1,234 of 1,300 loops\")"
                    ),
                    successes.formatted(),
                    slots.formatted()
                )
        }

        private static func rounded(_ fraction: Double) -> Double {
            (fraction / fractionStep).rounded() * fractionStep
        }

        /// The buckets with slots, as fractions of the window (the strip's width) and of the strip's height.
        private static func columns(_ stats: HomeLoopStats) -> [LoopStripColumns.Column] {
            let window = stats.window
            guard window.duration > 0 else { return [] }
            return stats.buckets.compactMap { bucket in
                guard let fraction = bucket.fraction else { return nil }
                return LoopStripColumns.Column(
                    x: rounded(bucket.interval.start.timeIntervalSince(window.start) / window.duration),
                    width: rounded(bucket.interval.duration / window.duration),
                    height: rounded(fraction)
                )
            }
        }

        /// The gaps of 15 min or more, from the loop that was due (a cadence after the last one) to the next one, or
        /// to now; cut at the window's start.
        private static func gapMarks(_ stats: HomeLoopStats) -> [LoopStripGapMarks.Mark] {
            let window = stats.window
            guard window.duration > 0 else { return [] }
            let position = { (date: Date) -> Double in
                min(max(date.timeIntervalSince(window.start) / window.duration, 0), 1)
            }
            return stats.markedGaps.map { gap in
                LoopStripGapMarks.Mark(
                    start: rounded(position(gap.start.addingTimeInterval(gap.loopInterval))),
                    end: gap.ongoing ? 1 : rounded(position(gap.end))
                )
            }
        }
    }

    let content: Content
    /// the Loops screen
    let open: () -> Void

    @ScaledMetric(relativeTo: .title) private var percentSize: CGFloat = 28

    /// `.equatable()`: Home's re-renders that don't change what it shows skip its body; by what it shows (the call
    /// site's action is a new closure every time, the same action while this is the same)
    nonisolated static func == (lhs: HomeLoopsCard, rhs: HomeLoopsCard) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeCardHeader(
                title: NSLocalizedString("Loops", comment: "Home Loops card title"),
                rangeLabel: content.range,
                open: open
            ) {
                if !content.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(content.percent)
                            .font(.system(size: percentSize, weight: .bold))
                        if content.hasPercent {
                            Text(verbatim: "%")
                                .font(.system(size: percentSize * 17 / 28, weight: .semibold))
                        }
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            // the row is 44 pt tall (`HomeCardMetrics`): the space above and below it is mostly in it
            .padding(.top, 8)
            Button(action: open) {
                details
                    .padding(.top, 4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Parts

    @ViewBuilder private var details: some View {
        if content.isEmpty {
            Text("No loops")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                strip
                numbers
            }
        }
    }

    /// The timeline: a column per half hour on the track (yesterday's dimmed), the gaps marked over them, the tick at
    /// midnight over it, today's share under the strip starting 3 pt past the tick (ending 3 pt before it where it
    /// doesn't fit after it: just after midnight).
    private var strip: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                LoopStripColumns(columns: content.pastColumns)
                    .fill(Color(.statsLoopColumnDim))
                LoopStripColumns(columns: content.columns)
                    .fill(Color(.statsLoopColumn))
                LoopStripGapMarks(marks: content.gapMarks)
                    .fill(Color(.statsLoopGap))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .background(Color(.statsLoopTrack))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                if let mark = content.todayMark {
                    LoopStripTick(position: mark)
                        .fill(Color(.statsLoopTick))
                        .padding(.vertical, -3)
                }
            }
            if let mark = content.todayMark {
                MarkLabelLayout(position: mark, gap: LoopStripTick.width / 2 + 3) {
                    todayLabel
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    /// "Today 97.3%" as one text (one baseline): "Today" muted, the share in the primary colour
    private var todayLabel: Text {
        guard let percent = content.todayPercent else {
            return Text("Today").foregroundStyle(.secondary)
        }
        // "Today %@": the share's run keeps its own colour over the muted rest
        return Text(
            "Today \(Text(verbatim: percent).foregroundStyle(.primary))",
            comment: "Home Loops card: today's share under the midnight tick (\"97.3%\")"
        )
        .foregroundStyle(.secondary)
    }

    /// "1,234 loops · 1,440 readings" and "Max gap 2 h 5 min" (when there is one) on one line, or one under the other
    /// (large text).
    @ViewBuilder private var numbers: some View {
        if let maxGap = content.maxGap {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    counts
                    Spacer(minLength: 0)
                    maxGapView(maxGap)
                }
                VStack(alignment: .leading, spacing: 2) {
                    counts
                    maxGapView(maxGap)
                }
            }
        } else {
            counts
        }
    }

    private var counts: some View {
        Text(content.counts)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func maxGapView(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Max gap")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    // MARK: - Durations

    /// "25 min", "2 h", "2 h 5 min": whole minutes, rounded
    nonisolated static func duration(_ interval: TimeInterval) -> String {
        let (hours, minutes) = hoursAndMinutes(interval)
        guard hours > 0 else {
            return String(format: NSLocalizedString("%d min", comment: "Home Loops card duration, minutes"), minutes)
        }
        guard minutes > 0 else {
            return String(format: NSLocalizedString("%d h", comment: "Home Loops card duration, whole hours"), hours)
        }
        return String(
            format: NSLocalizedString("%1$d h %2$d min", comment: "Home Loops card duration, hours and minutes"),
            hours,
            minutes
        )
    }

    /// whole minutes, rounded, split into hours and minutes
    private nonisolated static func hoursAndMinutes(_ interval: TimeInterval) -> (hours: Int, minutes: Int) {
        let total = max(0, Int((interval / 60).rounded()))
        return (total / 60, total % 60)
    }
}

/// The strip's columns: from the bottom, `height` of the strip (at least 2 pt), a 1 pt gap after each.
struct LoopStripColumns: Shape {
    struct Column: Equatable, Sendable {
        /// fractions of the strip's width
        let x: Double
        let width: Double
        /// a fraction of the strip's height
        let height: Double
    }

    let columns: [Column]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for column in columns {
            let height = max(2, column.height * rect.height)
            path.addRect(CGRect(
                x: rect.minX + column.x * rect.width,
                y: rect.maxY - height,
                width: max(1, column.width * rect.width - 1),
                height: height
            ))
        }
        return path
    }
}

/// The strip's midnight: `width` wide, centred on its position, the full height.
struct LoopStripTick: Shape {
    nonisolated static let width: CGFloat = 2

    /// a fraction of the width
    let position: Double

    func path(in rect: CGRect) -> Path {
        let x = rect.minX + min(max(position, 0), 1) * rect.width
        return Path(
            roundedRect: CGRect(x: x - Self.width / 2, y: rect.minY, width: Self.width, height: rect.height),
            cornerRadius: Self.width / 2
        )
    }
}

/// One label beside a mark at a fraction of the width: starting `gap` right of it, or, where it doesn't fit there,
/// ending `gap` left of it (`labelX`); never sliding under the mark.
struct MarkLabelLayout: Layout {
    /// a fraction of the width
    let position: Double
    /// from the mark's centre to the label's near edge
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let label = subviews.first else { return }
        let size = label.sizeThatFits(.unspecified)
        let width = min(size.width, bounds.width)
        let x = Self.labelX(position: position, gap: gap, labelWidth: width, in: bounds.width)
        label.place(
            at: CGPoint(x: bounds.minX + x, y: bounds.minY),
            proposal: ProposedViewSize(width: width, height: size.height)
        )
    }

    /// The label's leading x: `gap` right of the mark; where it would pass the end, `gap` left of it (its trailing edge
    /// there); where neither side has the room (a label wider than both), kept inside the width.
    nonisolated static func labelX(position: Double, gap: CGFloat, labelWidth: CGFloat, in width: CGFloat) -> CGFloat {
        let mark = width * CGFloat(min(max(position, 0), 1))
        let right = mark + gap
        if right + labelWidth <= width {
            return right
        }
        let left = mark - gap - labelWidth
        if left >= 0 {
            return left
        }
        return min(max(0, right), max(0, width - labelWidth))
    }
}

/// The strip's gap marks, the strip's full height, at least 3 pt wide.
struct LoopStripGapMarks: Shape {
    struct Mark: Equatable, Sendable {
        /// fractions of the strip's width
        let start: Double
        let end: Double
    }

    let marks: [Mark]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for mark in marks {
            var start = mark.start * rect.width
            var end = mark.end * rect.width
            if end - start < 3 {
                let middle = (start + end) / 2
                start = middle - 1.5
                end = middle + 1.5
            }
            start = max(0, start)
            end = min(rect.width, end)
            guard start < end else { continue }
            path.addRect(CGRect(x: rect.minX + start, y: rect.minY, width: end - start, height: rect.height))
        }
        return path
    }
}
