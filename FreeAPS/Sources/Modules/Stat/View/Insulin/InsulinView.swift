import Charts
import SwiftUI

/// The IOB card's colours: the AGP's for the percentiles (as the Glucose AGP), the warning colour below zero.
enum IOBChartStyle {
    /// 10–90%
    static let outer = translucent(.statsAGP, light: StatsChartMetrics.outerBand.light, dark: StatsChartMetrics.outerBand.dark)
    /// 25–75%
    static let inner = translucent(.statsAGP, light: 0.40, dark: 0.48)
    /// Today's usual: 25–75%, lighter under today's line
    static let usual = translucent(.statsAGP, light: 0.20, dark: 0.30)
    static let median = Color(.statsAGPMedian)
    /// the region below zero
    static let negativeRegion = translucent(.statsWarning, light: 0.09, dark: 0.16)
    /// its key in the legend: a little stronger, to read at 8 pt
    static let negativeKey = translucent(.statsWarning, light: 0.18, dark: 0.30)

    /// The colour at an opacity per appearance; one instance each, so the plots compare equal.
    private static func translucent(_ resource: ColorResource, light: CGFloat, dark: CGFloat) -> Color {
        Color(UIColor { traits in
            UIColor(resource: resource).resolvedColor(with: traits)
                .withAlphaComponent(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

struct InsulinView: View {
    let insulin: Stat.Insulin
    let daySelection: DailySelection
    let hourSelection: HourSelection
    /// "Show Today": the Today period
    let showToday: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let today = insulin.today {
            InsulinTodayView(today: today, hourSelection: hourSelection)
        } else {
            VStack(spacing: 16) {
                StatsCard { InsulinTotalCard(insulin: insulin) }
                StatsCard { basal }
                StatsCard { InsulinIOBCard(card: insulin.iobCard) }
                StatsCard { InsulinNegativeIOBCard(card: insulin.negativeCard) }
                    .id(StatsFocus.negativeIOB)
                InsulinDays(insulin: insulin, selection: daySelection, showToday: showToday)
                StatsCard { hourChart }
                StatsCard { InsulinHourReadout(readouts: insulin.hourReadouts, selection: hourSelection) }
                StatsCard { vsChart }
            }
        }
    }

    // MARK: - Basal

    @ViewBuilder private var basal: some View {
        Text("Basal")
            .statsSectionTitle()
        let tiles = [
            StatsTileItem(
                id: 0,
                title: NSLocalizedString(
                    "vs scheduled",
                    comment: "Statistics Insulin day: the basal as a share of the schedule"
                ),
                value: insulin.basalVsScheduled
            ),
            StatsTileItem(
                id: 1,
                title: NSLocalizedString("Scheduled", comment: "Statistics Insulin: the scheduled basal"),
                value: insulin.scheduled,
                unit: NSLocalizedString("U per day", comment: "Statistics Insulin: the unit of a daily amount")
            ),
            StatsTileItem(
                id: 2,
                title: NSLocalizedString("Zero basal", comment: "Statistics Insulin: the time at zero basal"),
                value: insulin.zeroBasal,
                unit: NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count")
            )
        ]
        // three across, two at the larger text sizes (the negative IOB is the Negative IOB card's)
        StatsTileGrid(tiles, columns: StatTile.columns(dynamicTypeSize, regular: 3))
        if let note = insulin.profileAssumedNote {
            Text(note)
                .statsNote()
        }
    }

    // MARK: - By hour

    @ViewBuilder private var hourChart: some View {
        StatsCardHeader(title: "By hour of day", detail: insulin.dateRange)
        StatsHourBarsChart(plot: insulin.hourPlot, selection: hourSelection)
        StatsChartLegend(items: insulin.hourLegend)
    }

    @ViewBuilder private var vsChart: some View {
        StatsCardHeader(
            title: "Basal vs scheduled",
            detail: NSLocalizedString("by hour", comment: "Statistics Insulin: the basal vs scheduled chart")
        )
        StatsHourBarsChart(plot: insulin.vsPlot, selection: hourSelection, plotHeight: 130)
        StatsChartLegend(items: insulin.vsLegend)
    }
}

// MARK: - Total daily dose

private struct InsulinTotalCard: View {
    let insulin: Stat.Insulin

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatsCardHeader(title: "Total daily dose", range: insulin.dateRange)
            Text(insulin.daysWithData)
                .statsFootnote()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }

        VStack(alignment: .leading, spacing: 2) {
            StatsHeadlineNumber(
                value: insulin.tdd,
                unit: NSLocalizedString("U", comment: ""),
                caption: NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count"),
                limitedNote: insulin.limitedNote
            )
            if insulin.needsCompleteDay {
                Text(Stat.Insulin.noCompleteDay)
                    .statsFootnote()
            }
        }

        if insulin.split.isNotEmpty {
            StatsSplitBar(segments: insulin.split)
                .frame(height: 28)
        }

        StatsPartRows(rows: insulin.rows)
    }
}

// MARK: - Day by day

/// The day chart and the selected day's card: re-rendered when the day picked changes, the rest of the tab isn't.
private struct InsulinDays: View {
    let insulin: Stat.Insulin
    let selection: DailySelection
    let showToday: () -> Void

    var body: some View {
        let index = selection.index(in: insulin.dayPlot.dayIntervals)
        let card = index.map { insulin.card(at: $0) }
        StatsCard {
            StatsCardHeader(title: "Day by day", detail: insulin.dateRange)
            if let index {
                StatsDayBarsChart(plot: insulin.dayPlot, selected: index, selection: selection)
            }
            StatsChartLegend(items: insulin.dayLegend)
        }
        if let index, let card {
            StatsCard { dayCard(card, index: index) }
        }
    }

    @ViewBuilder private func dayCard(_ card: Stat.Insulin.DayCard, index: Int) -> some View {
        let days = insulin.dayPlot.dayIntervals
        StatsStepper(title: card.title, index: index, count: days.count) { selection.pick($0, in: days) }

        if card.hasData {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.total)
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("U")
                        .font(.headline)
                    if card.soFar {
                        Text("so far")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(card.notes, id: \.self) { note in
                    Text(note)
                        .statsFootnote()
                }
            }
            if card.split.isNotEmpty {
                StatsSplitBar(segments: card.split, cornerRadius: 4)
                    .frame(height: 12)
            }
            StatsPartRows(rows: card.rows, unitHeader: NSLocalizedString("U", comment: ""))
            VStack(spacing: 0) {
                StatsValueRow(
                    key: .none,
                    name: NSLocalizedString(
                        "vs scheduled",
                        comment: "Statistics Insulin day: the basal as a share of the schedule"
                    ),
                    value: card.vsScheduled
                )
                if card.profileAssumed {
                    Text("Profile assumed")
                        .statsFootnote()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 24)
                        .padding(.bottom, 4)
                }
                Divider()
                StatsValueRow(
                    key: .none,
                    name: NSLocalizedString("Zero basal", comment: "Statistics Insulin: the time at zero basal"),
                    value: card.zeroBasal
                )
                Divider()
                StatsValueRow(
                    key: .none,
                    name: NSLocalizedString("Negative IOB", comment: "Statistics Insulin: the time with a negative IOB"),
                    value: card.negativeIOB
                )
                Divider()
                StatsValueRow(
                    key: .none,
                    name: NSLocalizedString("Lowest IOB", comment: "Statistics Insulin day: the lowest IOB below zero"),
                    value: card.lowestIOB
                )
            }
        } else {
            Text("No pump data")
                .statsEmptyNote()
        }

        // today has the Today period's view
        if insulin.days[index].isToday {
            StatsShowTodayButton(action: showToday)
        }
    }
}

// MARK: - The selected hour

/// The stepper through the hours (around midnight too) and the selected hour's numbers: the alternative to picking on
/// the charts. Re-rendered when the selection moves, the rest of the tab isn't.
private struct InsulinHourReadout: View {
    let readouts: [Stat.Insulin.HourReadout]
    let selection: HourSelection

    var body: some View {
        if readouts.indices.contains(selection.hour) {
            let readout = readouts[selection.hour]
            VStack(alignment: .leading, spacing: 4) {
                StatsStepper(hourTitle: readout.time, subtitle: readout.subtitle, selection: selection)
                VStack(spacing: 0) {
                    StatsDividedRows(readout.rows) { row in
                        StatsValueRow(key: row.key, name: row.name, value: row.value, emphasized: row.emphasized)
                    }
                    Divider()
                    StatsValueRow(
                        key: .none,
                        name: NSLocalizedString(
                            "Basal vs scheduled",
                            comment: "Statistics Insulin: the basal as a share of the schedule"
                        ),
                        value: readout.vsScheduled
                    )
                    Divider()
                    StatsValueRow(
                        key: .none,
                        name: NSLocalizedString(
                            "Zero basal · per day",
                            comment: "Statistics Insulin by hour: the time at zero basal"
                        ),
                        value: readout.zeroBasal
                    )
                    Divider()
                    StatsValueRow(
                        key: .none,
                        name: NSLocalizedString(
                            "Negative IOB · per day",
                            comment: "Statistics Insulin by hour: the time with a negative IOB"
                        ),
                        value: readout.negativeIOB
                    )
                }
            }
        }
    }
}

// MARK: - Today

/// The Today period: today so far against the usual by now, by hour, the basal so far and the boluses.
private struct InsulinTodayView: View {
    let today: Stat.Insulin.Today
    let hourSelection: HourSelection

    var body: some View {
        VStack(spacing: 16) {
            StatsCard { InsulinTodayTotalCard(today: today) }
            StatsCard { hourChart }
            StatsCard { basal }
            StatsCard { InsulinIOBCard(card: today.iobCard) }
            StatsCard { InsulinNegativeIOBCard(card: today.negativeCard) }
                .id(StatsFocus.negativeIOB)
            StatsCard { boluses }
        }
    }

    // MARK: By hour

    @ViewBuilder private var hourChart: some View {
        StatsCardHeader(title: "By hour of day", detail: NSLocalizedString("so far", comment: ""))
        StatsHourBarsChart(plot: today.hourPlot, selection: hourSelection)
        StatsChartLegend(items: today.hourLegend)
        InsulinTodayHourReadout(readouts: today.hourReadouts, selection: hourSelection)
    }

    // MARK: Basal so far

    @ViewBuilder private var basal: some View {
        Text("Basal so far")
            .statsSectionTitle()
        let tiles = [
            StatsTileItem(
                id: 0,
                title: NSLocalizedString(
                    "vs scheduled",
                    comment: "Statistics Insulin day: the basal as a share of the schedule"
                ),
                value: today.vsScheduled,
                unit: today.scheduledSoFar
            ),
            StatsTileItem(
                id: 1,
                title: NSLocalizedString("Zero basal", comment: "Statistics Insulin: the time at zero basal"),
                value: today.zeroBasal,
                unit: NSLocalizedString("so far", comment: "")
            )
        ]
        // the negative IOB is the Negative IOB card's
        StatsTileGrid(tiles, columns: 2)
        if today.profileAssumed {
            Text("Profile assumed")
                .statsFootnote()
        }
    }

    // MARK: Boluses

    @ViewBuilder private var boluses: some View {
        Text("Boluses")
            .statsSectionTitle()
        if today.boluses.isEmpty, today.smbCount == nil {
            Text("No boluses so far")
                .statsEmptyNote(minHeight: 60)
        } else {
            VStack(spacing: 0) {
                StatsDividedRows(today.boluses) { bolus in
                    bolusRow(time: bolus.time, name: bolus.name, units: bolus.units)
                }
                if let count = today.smbCount {
                    if today.boluses.isNotEmpty {
                        Divider()
                    }
                    // the SMBs, counted: no time of their own
                    bolusRow(time: "–", name: count, units: today.smbTotal)
                }
            }
        }
    }

    private func bolusRow(time: String, name: String, units: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(time)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(name)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(units)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
        }
        .frame(minHeight: 44)
    }
}

/// Insulin so far: the total, the usual by now and the difference, the split and the parts with their usual.
private struct InsulinTodayTotalCard: View {
    let today: Stat.Insulin.Today

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    var body: some View {
        StatsCardHeader(title: "Insulin so far", range: today.dateRange)

        if today.hasData {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(today.total)
                        .font(.system(size: size, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("U")
                        .font(.title3.weight(.semibold))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    (Text(today.usualTitle + " ").foregroundStyle(.secondary) + Text(today.usual).fontWeight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let difference = today.difference {
                        Text(difference)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.subheadline)
                if today.needsCompleteDay {
                    Text(Stat.Insulin.noCompleteDay)
                        .statsFootnote()
                }
            }

            if today.split.isNotEmpty {
                StatsSplitBar(segments: today.split)
                    .frame(height: 28)
            }

            StatsPartRows(rows: today.rows, unitHeader: NSLocalizedString("U", comment: ""))
        } else {
            Text("No pump data")
                .statsEmptyNote()
        }
    }
}

/// The stepper through today's hours and the selected one's insulin against the usual in it: the alternative to
/// picking on the chart. Re-rendered when the selection moves, the rest of the view isn't.
private struct InsulinTodayHourReadout: View {
    let readouts: [Stat.Insulin.Today.HourReadout]
    let selection: HourSelection

    var body: some View {
        if readouts.indices.contains(selection.hour) {
            let readout = readouts[selection.hour]
            VStack(alignment: .leading, spacing: 4) {
                StatsStepper(hourTitle: readout.time, subtitle: readout.subtitle, selection: selection)
                VStack(spacing: 0) {
                    StatsDividedRows(readout.rows) { row in
                        StatsValueRow(key: row.key, name: row.name, value: row.value, emphasized: row.emphasized)
                    }
                }
            }
        }
    }
}

// MARK: - IOB

/// The IOB card: the IOB by time of day, the time below zero shaded (`Stat.Insulin.IOBCard`).
private struct InsulinIOBCard: View {
    let card: Stat.Insulin.IOBCard

    var body: some View {
        StatsCardHeader(title: "Insulin on board", detail: card.detail)
        if card.plot.isEmpty {
            if card.note == nil {
                Text("No IOB data")
                    .statsEmptyNote()
            }
        } else {
            InsulinIOBChart(plot: card.plot)
                .equatable()
                .frame(height: 210)
            StatsChartLegend(items: card.legend)
        }
        if let note = card.note {
            Text(note)
                .statsNote()
        }
    }
}

/// The marks: the region below zero, the bands, the median or the days' lines, today's line (blue, below zero in the
/// warning colour), now. Equatable: re-rendered only when the plot changes.
private struct InsulinIOBChart: View, Equatable {
    let plot: Stat.Insulin.IOBCard.Plot

    nonisolated static func == (lhs: InsulinIOBChart, rhs: InsulinIOBChart) -> Bool {
        lhs.plot == rhs.plot
    }

    var body: some View {
        let plot = self.plot
        Chart {
            RectangleMark(
                xStart: .value("Start", Stat.Insulin.IOBCard.Plot.domain.lowerBound),
                xEnd: .value("End", Stat.Insulin.IOBCard.Plot.domain.upperBound),
                yStart: .value("Lowest", plot.yDomain.lowerBound),
                yEnd: .value("Zero", 0.0)
            )
            .foregroundStyle(IOBChartStyle.negativeRegion)

            ForEach(Array(plot.outer.enumerated()), id: \.offset) { _, band in
                AreaMark(
                    x: .value("Time", band.minute),
                    yStart: .value("10th percentile", band.lower),
                    yEnd: .value("90th percentile", band.upper),
                    series: .value("Segment", "outer \(band.segment)")
                )
                .foregroundStyle(IOBChartStyle.outer)
            }

            ForEach(Array(plot.inner.enumerated()), id: \.offset) { _, band in
                AreaMark(
                    x: .value("Time", band.minute),
                    yStart: .value("25th percentile", band.lower),
                    yEnd: .value("75th percentile", band.upper),
                    series: .value("Segment", "inner \(band.segment)")
                )
                .foregroundStyle(plot.isUsual ? IOBChartStyle.usual : IOBChartStyle.inner)
            }

            RuleMark(y: .value("Zero", 0.0))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.secondary)

            ForEach(Array(plot.median.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.minute),
                    y: .value("Median", point.value),
                    series: .value("Segment", "median \(point.series)")
                )
                .lineStyle(
                    plot.isUsual
                        ? StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        : StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .foregroundStyle(plot.isUsual ? Color.secondary : IOBChartStyle.median)
            }

            ForEach(Array(plot.dayLines.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.minute),
                    y: .value("IOB", point.value),
                    series: .value("Day", "day \(point.series)")
                )
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(IOBChartStyle.median)
            }

            ForEach(Array(plot.todayAbove.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.minute),
                    y: .value("IOB", point.value),
                    series: .value("Stretch", "above \(point.series)")
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color(.insulin))
            }

            ForEach(Array(plot.todayBelow.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.minute),
                    y: .value("IOB", point.value),
                    series: .value("Stretch", "below \(point.series)")
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color(.statsWarning))
            }

            if let now = plot.now {
                RuleMark(x: .value("Now", now))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("now")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: Stat.Insulin.IOBCard.Plot.domain)
        .chartYScale(domain: plot.yDomain)
        .chartXAxis {
            StatsAxis.minutes(Stat.AGP.Plot.gridMinutes.map { Double($0) }, ticks: plot.xTicks) { Int($0) }
        }
        .chartYAxis {
            StatsAxis.levels(plot.levels, labels: plot.levelLabels)
        }
        .chartLegend(.hidden)
    }
}

/// The Negative IOB card (`Stat.Insulin.NegativeIOBCard`): the time below zero, the tiles, the minutes by hour hanging
/// from the top (below zero is down).
private struct InsulinNegativeIOBCard: View {
    let card: Stat.Insulin.NegativeIOBCard

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 34

    var body: some View {
        Text("Negative IOB")
            .statsSectionTitle()

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.headline)
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(card.headlineUnit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = card.limitedNote {
                    LimitedDataMarker(note: note, font: .title3)
                        .padding(.leading, 4)
                }
            }
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }

        // two across (7–90 d), Today's one alone
        StatsTileGrid(card.tiles, columns: 2) { tile in
            StatTile(title: tile.title, value: tile.value, unit: tile.unit, style: .compact)
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("By hour of day")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(card.hourDetail)
                    .statsFootnote()
            }
            StatsHourBarsChart(plot: card.hourPlot, plotHeight: 110)
            if card.hourLegend.isNotEmpty {
                StatsChartLegend(items: card.hourLegend)
            }
        }
    }
}
