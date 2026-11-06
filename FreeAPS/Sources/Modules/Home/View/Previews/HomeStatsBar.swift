import SwiftUI

/// The stats bar's result: the summary of its range (the same call the Statistics Overview makes) and the last 90 days'
/// (the GMI line, `Home.gmiPeriod`), formatted once. It holds only what is shown (`HomeStatsBar.Content`), not the
/// summaries, so a new summary that displays the same doesn't re-render Home (`Home.StateModel` assigns it only when it
/// changed). See `Content` for what that covers.
struct HomeStatsSnapshot: Equatable {
    let period: StatsPeriod
    let settings: Stat.StatsSettings
    let content: HomeStatsBar.Content

    @MainActor init(_ summary: GlucoseSummary, gmi: GlucoseSummary?, period: StatsPeriod, settings: Stat.StatsSettings) {
        self.period = period
        self.settings = settings
        content = HomeStatsBar.Content(summary, gmi: gmi, period: period, settings: settings)
    }
}

/// The stats card on Home: the band bar of its range (Today or 24 h, muted after the title), the in-range percent, the
/// mean and CV, and the GMI of the last 90 days. A long-press picks the range (`HomeStatsRangeMenu`, the card's
/// `.contextMenu` in `HomeRootView`); a tap opens the Statistics Overview.
struct HomeStatsBar: View {
    /// What the card shows, formatted. The numbers are the Overview's (`Stat.Overview`), so the two never differ.
    ///
    /// Compared as shown: strings, and the bar's fractions rounded to `fractionStep`. So a new summary with the same
    /// numbers is equal: the minute ticks of a stall in Today until the coverage drops below 70% (the limited mark; the
    /// percent itself isn't shown), a reading that changes no shown value, and the GMI line while its value and days
    /// stay. Not the 24 h range while stalled: its start moves on with E every minute, so the covered time and the
    /// fractions change (by about 60 s / 24 h, 7e-4, for the bands at its start and end) and the bar is redrawn at most
    /// of those ticks.
    struct Content: Equatable {
        /// 1e-3 of the bar: about 0.35 pt on a phone, below a pixel at 2x
        static let fractionStep = 1E-3

        /// The GMI of the last 90 days, under the bar on the left: "90-day GMI 6.8 %", "37-day GMI 6.8 %".
        struct GMILine: Equatable {
            /// "90-day GMI", "37-day GMI": the days with readings of the 90
            let title: String
            /// "6.8", "51"
            let value: String
            /// "%", "mmol/mol"
            let unit: String
        }

        /// the range of this result
        let period: StatsPeriod
        let isEmpty: Bool
        /// CGM coverage below 70% (`GlucoseSummary.isLimited`): the numbers are provisional, a mark beside them (the
        /// Overview, which the tap opens, says why)
        let isLimited: Bool
        /// "72", "<1"
        let inRangePercent: String
        /// "70–145 mg/dL", in the header after the title and the range
        let inRangeRange: String
        /// "70–145": the header's detail where `inRangeRange` doesn't fit
        let inRangeBounds: String
        let segments: [BandSegment]
        let mean: String
        /// "31%"
        let cv: String
        /// nil: hidden (fewer than 14 days with readings in the 90, `gmiLine`), or not read yet
        let gmi: GMILine?

        /// - Parameter gmi: the summary of `Home.gmiPeriod` (the GMI line); nil: no line
        @MainActor init(
            _ summary: GlucoseSummary,
            gmi: GlucoseSummary? = nil,
            period: StatsPeriod,
            settings: Stat.StatsSettings
        ) {
            let overview = Stat.Overview(summary, period: period, settings: settings)
            self.period = period
            isEmpty = summary.isEmpty
            isLimited = overview.isLimited
            inRangePercent = overview.inRangePercent
            inRangeRange = overview.inRangeRange
            inRangeBounds = StatsFormatting.label(.inRange, bands: summary.bands, units: settings.units) ?? ""
            // a band rounded to 0 still gets the bar's minimum width
            segments = overview.segments.map {
                BandSegment(band: $0.band, fraction: ($0.fraction / Self.fractionStep).rounded() * Self.fractionStep)
            }
            mean = overview.mean
            cv = overview.cv
            self.gmi = Self.gmiLine(gmi, settings: settings)
        }

        /// The GMI line of the last 90 days' summary: its GMI in the Overview's format and HbA1c unit
        /// (`StatsFormatting.a1c`), with the days with readings (a reading starts in the day,
        /// `GlucoseStatsEngine.dayCounts`), 90 at most. Hidden by the Overview's A1c rule (`a1cNeedsMoreDays`): fewer than
        /// 14 days with readings, where the Overview marks its GMI as limited; and without readings.
        @MainActor static func gmiLine(_ summary: GlucoseSummary?, settings: Stat.StatsSettings) -> GMILine? {
            guard let summary, !summary.a1cNeedsMoreDays, let percent = summary.gmiPercent else { return nil }
            let days = Swift.min(summary.daysWithData, Home.gmiPeriod.calendarDayCount ?? summary.daysWithData)
            return GMILine(
                title: String(
                    format: NSLocalizedString(
                        "%d-day GMI",
                        comment: "Home stats bar: the GMI of the days with readings of the last 90 (\"90-day GMI\")"
                    ),
                    days
                ),
                value: StatsFormatting.a1c(percent, unit: settings.hbA1cUnit),
                unit: StatsFormatting.a1cUnit(settings.hbA1cUnit)
            )
        }
    }

    let content: Content
    /// the card's range setting: its header's range, its long-press menu's pick
    let range: StatsPeriod
    /// the Statistics Overview on the card's range
    let open: () -> Void

    @ScaledMetric(relativeTo: .title) private var percentSize: CGFloat = 28

    /// a pick of another range, up to its read: the numbers dimmed
    private var isStale: Bool { content.period != range }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                // the row is 44 pt tall (`HomeCardMetrics`): the space above and below it is mostly in it
                .padding(.top, 8)
            Button(action: open) {
                details
                    .opacity(isStale ? HomeCardStale.opacity : 1)
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

    // MARK: - Header

    /// "In range · 24 h · 70–180 mg/dL", "72%"
    private var header: some View {
        HomeCardHeader(
            title: Self.inRangeTitle,
            rangeLabel: StatsFormatting.label(range),
            detail: content.inRangeRange,
            shortDetail: content.inRangeBounds,
            open: open,
            isStale: isStale
        ) {
            if !content.isEmpty {
                inRangePercent
            }
        }
    }

    /// "72%", the limited mark after it
    private var inRangePercent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(content.inRangePercent)
                .font(.system(size: percentSize, weight: .bold))
            Text(verbatim: "%")
                .font(.system(size: percentSize * 17 / 28, weight: .semibold))
            if content.isLimited {
                limitedMark
                    .padding(.leading, 3)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    // MARK: - Details

    @ViewBuilder private var details: some View {
        if content.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No readings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let gmi = content.gmi {
                    gmiLine(gmi)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                bar
                numbers
            }
        }
    }

    private var bar: some View {
        BandBar(segments: content.segments, cornerRadius: 5)
            .frame(height: 14)
    }

    /// The GMI line on the left, the mean and CV on the right; one under the other when they don't fit (large text).
    private var numbers: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let gmi = content.gmi {
                    gmiLine(gmi)
                }
                Spacer(minLength: 0)
                averages
            }
            VStack(alignment: .leading, spacing: 4) {
                if let gmi = content.gmi {
                    gmiLine(gmi)
                }
                averages
            }
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    /// "Mean 128 · CV 31%"
    private var averages: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            number(NSLocalizedString("Mean", comment: "Statistics, mean glucose"), content.mean)
            number(NSLocalizedString("CV", comment: ""), content.cv)
        }
    }

    private func number(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    /// "90-day GMI 6.8 %"
    private func gmiLine(_ gmi: Content.GMILine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(gmi.title)
                .foregroundStyle(.secondary)
            Text(gmi.value)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(gmi.unit)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    // MARK: - Parts

    /// The Overview's mark: the card is a button (it opens the Overview, whose marks say why), so the mark alone
    private var limitedMark: some View {
        LimitedDataMarker(note: nil, font: .subheadline)
    }

    @MainActor private static var inRangeTitle: String { StatsFormatting.name(.inRange) }
}

/// The stats bar's long-press menu (the card's `.contextMenu`, `HomeRootView`): its range, Today or 24 h.
struct HomeStatsRangeMenu: View {
    /// the card's range setting
    let range: StatsPeriod
    let select: @MainActor @Sendable(StatsPeriod) -> Void

    // explicit: the synthesized memberwise init drops `@Sendable` from `select` in this target (Swift 5 mode, targeted
    // concurrency), so passing a `@Sendable` closure to it warns
    init(range: StatsPeriod, select: @escaping @MainActor @Sendable(StatsPeriod) -> Void) {
        self.range = range
        self.select = select
    }

    var body: some View {
        Section("Range") {
            Picker("Range", selection: Binding(get: { [range] in range }, set: select)) {
                ForEach(StatsPeriod.homeStatsRanges) { period in
                    Text(StatsFormatting.label(period)).tag(period)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}
