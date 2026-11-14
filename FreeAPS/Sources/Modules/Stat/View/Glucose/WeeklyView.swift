import Charts
import SwiftUI

extension Stat {
    /// Weekly, formatted for display. The weeks, their numbers and their Δ come ready from the provider
    /// (`WeeklyResult`); only strings and the charts' bars are built here.
    struct Weekly: Equatable {
        /// What a chart draws: each week against the period's average, in the units shown. The marks view compares it to
        /// skip its body (`WeeklyMarks`).
        struct Plot: Equatable, Sendable {
            /// A week's bar, from the average to the week (`GlucoseStatsEngine.weeklyBar`).
            struct Bar: Equatable, Sendable, Identifiable {
                /// its week's slot on the x axis
                let slot: String
                let lower: Double
                let upper: Double
                let comparison: WeeklyWeek.Comparison

                var id: String { slot }
            }

            struct Level: Equatable, Sendable {
                let value: Double
                let label: String
                /// the average's, in the middle: no gridline (its dashed rule is there), the label emphasized
                let isAverage: Bool
            }

            struct Tick: Equatable, Sendable {
                let slot: String
                /// "24 Oct": the week's first day
                let label: String
            }

            /// every week, oldest first, also those without data (their slot stays empty)
            let slots: [String]
            /// the weeks with data
            let bars: [Bar]
            /// the period's, as shown
            let average: Double
            /// the average in the middle, the farthest week inside (`GlucoseStatsEngine.weeklyHalfRange`)
            let domain: ClosedRange<Double>
            /// the bottom, the average and the top; a level no value can be (above 100%) is left out
            let levels: [Level]
            /// `GlucoseStatsEngine.weeklyTickWeeks`
            let ticks: [Tick]

            /// The x axis's categories: a week's index, zero-padded ("00" … "12"), so the slots sort as the weeks do
            /// however the chart orders a nominal domain (the domain lists them in order too).
            static func slot(_ week: Int) -> String {
                String(format: "%02d", week)
            }

            /// Many weeks (13): the bars take a part of their slot; a few (5): 16 pt, as the mock.
            var isNarrow: Bool { slots.count > 6 }

            /// the outer levels, with a gridline
            var gridLevels: [Double] { levels.filter { !$0.isAverage }.map(\.value) }
        }

        /// A week of the table: its numbers and their Δ, or "no data".
        struct Row: Equatable, Identifiable {
            struct Values: Equatable {
                /// "72%", "<1%"
                let inRange: String
                /// "+2", "−3", "±0"
                let inRangeDelta: String
                let inRangeComparison: WeeklyWeek.Comparison?
                /// "152", "8.4"
                let mean: String
                /// "+4", "−0.2", "±0"
                let meanDelta: String
                let meanComparison: WeeklyWeek.Comparison?
            }

            /// the week's first day
            let id: Date
            /// "24–30 Oct"
            let title: String
            /// "includes today", "7 days"
            let subtitle: String
            /// nil: "no data"
            let values: Values?
        }

        /// "13 weeks · 31 Jul – 30 Oct"
        let subtitle: String
        /// "In your range 70–145 mg/dL"
        let inRangeTitle: String
        /// "average 72%"
        let inRangeAverage: String
        let inRangePlot: Plot
        /// "Mean glucose · mg/dL"
        let meanTitle: String
        /// "average 152"
        let meanAverage: String
        let meanPlot: Plot
        /// newest first
        let rows: [Row]

        /// The units are the result's: the means and their Δ were computed in them (the settings' when it was asked for).
        @MainActor init(_ result: WeeklyResult, period: StatsPeriod) {
            typealias Format = StatsFormatting
            typealias Engine = GlucoseStatsEngine
            let summary = result.summary
            let units = result.units
            let unit = Format.unit(units)
            let weeks = result.weeks
            let weekCount = period.weekCount ?? weeks.count
            let inRangeRange = Format.inRangeLabel(bands: summary.bands, units: units)

            subtitle = String(
                format: NSLocalizedString(
                    "%1$d weeks · %2$@",
                    comment: "Statistics Weekly: the weeks of the period, its first and last day"
                ),
                weekCount,
                Format.dateRange(summary.window, period: period)
            )

            let averageInRange = Format.percent(.inRange, of: summary)
            inRangeTitle = String(
                format: NSLocalizedString(
                    "In your range %@",
                    comment: "Statistics Weekly chart: the in-range band with its unit"
                ),
                inRangeRange
            )
            inRangeAverage = String(
                format: NSLocalizedString("average %@", comment: "Statistics Weekly chart: the period's value"),
                averageInRange
            )
            inRangePlot = Self.plot(
                values: weeks.map { week in week.inRangePercent.map { Double($0) } },
                comparisons: weeks.map(\.inRangeComparison),
                average: Double(summary.percent(.inRange)),
                step: Engine.weeklyInRangeStep,
                possible: 0 ... 100,
                labels: result.labels,
                // as the header shows it ("<1%" for a sliver)
                averageLabel: averageInRange,
                format: { Format.percent(Int($0.rounded())) }
            )

            let averageMean = result.averageMean.map { Format.glucose(shown: $0, units: units) } ?? "–"
            meanTitle = String(
                format: NSLocalizedString("Mean glucose · %@", comment: "Statistics Weekly chart: the unit"),
                unit
            )
            meanAverage = String(
                format: NSLocalizedString("average %@", comment: "Statistics Weekly chart: the period's value"),
                averageMean
            )
            meanPlot = Self.plot(
                values: weeks.map { week in week.mean.map { NSDecimalNumber(decimal: $0).doubleValue } },
                comparisons: weeks.map(\.meanComparison),
                average: result.averageMean.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0,
                step: Engine.weeklyMeanStep(units: units),
                possible: 0 ... .infinity,
                labels: result.labels,
                averageLabel: averageMean,
                format: { Format.glucose(shown: Decimal($0), units: units) }
            )

            rows = zip(weeks, result.labels).reversed().map { week, label in
                Self.row(week, label: label, units: units)
            }
        }

        /// "+2", "−3" (a minus sign), "±0": a Δ as shown, `magnitude` its size formatted.
        static func signed(_ delta: Decimal, magnitude: String) -> String {
            guard delta != 0 else { return "±0" }
            return (delta > 0 ? "+" : "−") + magnitude
        }

        @MainActor private static func plot(
            values: [Double?],
            comparisons: [WeeklyWeek.Comparison?],
            average: Double,
            step: Double,
            possible: ClosedRange<Double>,
            labels: [WeeklyResult.Label],
            averageLabel: String,
            format: (Double) -> String
        ) -> Plot {
            typealias Engine = GlucoseStatsEngine
            let halfRange = Engine.weeklyHalfRange(values, average: average, step: step)
            let slots = values.indices.map { Plot.slot($0) }
            let bars = values.indices.compactMap { index -> Plot.Bar? in
                guard let value = values[index], let comparison = comparisons[index] else { return nil }
                let bar = Engine.weeklyBar(value, average: average, halfRange: halfRange)
                return Plot.Bar(slot: slots[index], lower: bar.lower, upper: bar.upper, comparison: comparison)
            }
            let bottom = average - halfRange
            let top = average + halfRange
            let levels = [(bottom, false), (average, true), (top, false)]
                .filter { possible.contains($0.0) }
                .map { Plot.Level(value: $0.0, label: $0.1 ? averageLabel : format($0.0), isAverage: $0.1) }
            return Plot(
                slots: slots,
                bars: bars,
                average: average,
                domain: bottom ... Swift.max(top, bottom),
                levels: levels,
                ticks: Engine.weeklyTickWeeks(count: slots.count)
                    .filter { labels.indices.contains($0) }
                    .map { Plot.Tick(slot: slots[$0], label: labels[$0].start) }
            )
        }

        @MainActor private static func row(_ week: WeeklyWeek, label: WeeklyResult.Label, units: GlucoseUnits) -> Row {
            typealias Format = StatsFormatting
            let subtitle = week.includesToday
                ? NSLocalizedString("includes today", comment: "Statistics Weekly: the week ending today")
                : String(format: NSLocalizedString("%d days", comment: "Statistics AGP, the days of the period"), week.dayCount)
            guard week.hasData, let inRangePercent = week.inRangePercent, let inRangeDelta = week.inRangeDelta else {
                return Row(
                    id: week.days.start,
                    title: label.title,
                    subtitle: subtitle,
                    values: nil
                )
            }

            let inRange = Format.percent(inRangePercent, belowOne: week.inRangeBelowOnePercent)
            let mean = week.mean.map { Format.glucose(shown: $0, units: units) } ?? "–"
            let meanMagnitude = week.meanDelta.map { Format.glucose(shown: abs($0), units: units) }
            let meanDelta = week.meanDelta.flatMap { delta in meanMagnitude.map { signed(delta, magnitude: $0) } } ?? "–"
            return Row(
                id: week.days.start,
                title: label.title,
                subtitle: subtitle,
                values: Row.Values(
                    inRange: inRange,
                    inRangeDelta: signed(Decimal(inRangeDelta), magnitude: "\(abs(inRangeDelta))"),
                    inRangeComparison: week.inRangeComparison,
                    mean: mean,
                    meanDelta: meanDelta,
                    meanComparison: week.meanComparison
                )
            )
        }
    }
}

extension WeeklyWeek.Comparison {
    /// the bar's and the Δ's colour; the Δ's sign says it too
    var color: Color {
        switch self {
        case .better: return Color(.statsBetter)
        case .worse: return Color(.statsWorse)
        case .same: return Color(.secondaryLabel)
        }
    }
}

struct WeeklyView: View {
    let weekly: Stat.Weekly

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// the table's number columns
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .footnote) private var deltaWidth: CGFloat = 40

    /// The two charts, then the weeks.
    var body: some View {
        VStack(spacing: 16) {
            StatsCard { charts }
            StatsCard { table }
        }
    }

    // MARK: - Charts

    @ViewBuilder private var charts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Week vs. period average")
                .statsSectionTitle()
            // the dates shown, as the other tabs' (`StatsDateRange`)
            Text(weekly.subtitle)
                .font(.subheadline)
                .monospacedDigit()
        }

        chartHeader(weekly.inRangeTitle, average: weekly.inRangeAverage)
        WeeklyChart(plot: weekly.inRangePlot)

        chartHeader(weekly.meanTitle, average: weekly.meanAverage)
        WeeklyChart(plot: weekly.meanPlot)

        WeeklyLegend()
    }

    /// The chart's title and the period's value: one line, two when they don't fit.
    private func chartHeader(_ title: String, average: String) -> some View {
        let titleText = Text(title)
            .font(.subheadline.weight(.semibold))
        let averageText = Text(average)
            .statsFootnote()
            .monospacedDigit()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                Spacer(minLength: 8)
                averageText
            }
            VStack(alignment: .leading, spacing: 2) {
                titleText
                averageText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Weeks

    @ViewBuilder private var table: some View {
        Text("Weeks")
            .statsSectionTitle()
        VStack(spacing: 0) {
            columns(Text("Week"), Text("In range · Δ"), Text("Mean · Δ"))
                .statsColumnHeader(bottomPadding: 6)
            ForEach(weekly.rows) { row in
                Divider()
                weekRow(row)
            }
        }
    }

    /// the larger text sizes: the numbers on their own line, under the week
    private var stacked: Bool {
        dynamicTypeSize > .large
    }

    /// The week, then the two number columns: on one line, under it at the larger text sizes.
    @ViewBuilder private func columns<Week: View, InRange: View, Mean: View>(
        _ week: Week,
        _ inRange: InRange,
        _ mean: Mean
    ) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 4) {
                week
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    inRange
                        .frame(width: columnWidth, alignment: .trailing)
                    mean
                        .frame(width: columnWidth, alignment: .trailing)
                }
            }
        } else {
            HStack(spacing: 8) {
                week
                    .frame(maxWidth: .infinity, alignment: .leading)
                inRange
                    .frame(width: columnWidth, alignment: .trailing)
                mean
                    .frame(width: columnWidth, alignment: .trailing)
            }
        }
    }

    private func weekRow(_ row: Stat.Weekly.Row) -> some View {
        let week = VStack(alignment: .leading, spacing: 1) {
            Text(row.title)
                .font(.subheadline)
            Text(row.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        return Group {
            if let values = row.values {
                columns(
                    week,
                    cell(values.inRange, delta: values.inRangeDelta, comparison: values.inRangeComparison),
                    cell(values.mean, delta: values.meanDelta, comparison: values.meanComparison)
                )
            } else {
                HStack(spacing: 8) {
                    week
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("no data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 46)
    }

    /// A number and its Δ, coloured by how the week compares (its sign says it too).
    private func cell(_ value: String, delta: String, comparison: WeeklyWeek.Comparison?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(delta)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(comparison?.color ?? Color(.secondaryLabel))
                .frame(minWidth: deltaWidth, alignment: .trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Legend

/// The colour key (each chart's own description says what is drawn).
private struct WeeklyLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                items
            }
            VStack(alignment: .leading, spacing: 4) {
                items
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var items: some View {
        item("Better than average") {
            RoundedRectangle(cornerRadius: 2).fill(WeeklyWeek.Comparison.better.color).frame(width: 10, height: 10)
        }
        item("Worse than average") {
            RoundedRectangle(cornerRadius: 2).fill(WeeklyWeek.Comparison.worse.color).frame(width: 10, height: 10)
        }
        item("Period average") {
            StatsKeyGlyph(key: .dashed, size: .row)
        }
    }

    private func item<Swatch: View>(_ label: LocalizedStringKey, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(label)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Chart

/// A chart: its marks (`WeeklyMarks`, equatable) and the room for the date labels.
private struct WeeklyChart: View {
    let plot: Stat.Weekly.Plot

    /// the room under the plot for the date labels
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 20

    var body: some View {
        WeeklyMarks(plot: plot)
            .equatable()
            .frame(height: 130 + labelHeight)
    }
}

/// The marks: a bar per week with data from the average to the week, coloured by how it compares, and the average's
/// dashed rule. `.equatable()` skips its body while its plot is the same (a refresh with nothing new).
private struct WeeklyMarks: View, Equatable {
    let plot: Stat.Weekly.Plot

    nonisolated static func == (lhs: WeeklyMarks, rhs: WeeklyMarks) -> Bool {
        lhs.plot == rhs.plot
    }

    /// of the slot, with many weeks
    private static let barRatio = StatsChartMetrics.barWidthRatio
    /// with a few weeks
    private static let barWidth: CGFloat = 16

    var body: some View {
        let plot = self.plot
        let width: MarkDimension = plot.isNarrow ? .ratio(Self.barRatio) : .fixed(Self.barWidth)
        Chart {
            ForEach(plot.bars) { bar in
                BarMark(
                    x: .value("Week", bar.slot),
                    yStart: .value("From", bar.lower),
                    yEnd: .value("To", bar.upper),
                    width: width
                )
                .foregroundStyle(bar.comparison.color)
            }

            RuleMark(y: .value("Average", plot.average))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color.primary)
        }
        // every week has its slot, also one without data
        .chartXScale(domain: plot.slots)
        .chartYScale(domain: plot.domain)
        .chartXAxis {
            AxisMarks(values: plot.ticks.map(\.slot)) { value in
                AxisValueLabel {
                    Text(value.as(String.self).flatMap { slot in plot.ticks.first { $0.slot == slot }?.label } ?? "")
                }
            }
        }
        .chartYAxis {
            // gridlines at the top and the bottom; the average has its dashed rule
            AxisMarks(values: plot.gridLevels) { _ in
                AxisGridLine()
            }
            AxisMarks(position: .leading, values: plot.levels.map(\.value)) { value in
                let level = value.index < plot.levels.count ? plot.levels[value.index] : nil
                let isAverage = level?.isAverage ?? false
                AxisValueLabel {
                    Text(level?.label ?? "")
                        .fontWeight(isAverage ? .semibold : .regular)
                        .foregroundStyle(isAverage ? Color.primary : Color.secondary)
                }
            }
        }
        .chartLegend(.hidden)
    }
}
