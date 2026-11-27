import Charts
import SwiftUI

extension Stat {
    /// The Daily view (the Days tab), formatted for display. The days, their bars and their numbers come ready from the provider
    /// (`DailyResult`); only strings are built here, the selected day's when it is shown (`card(at:)`).
    struct Daily: Equatable {
        /// the y axis: shares of the day, gridlines at 0, 50 and 100%
        private static let levels: [Double] = [0, 0.5, 1]

        /// The selected day, formatted.
        struct Card: Equatable {
            struct Numbers: Equatable {
                /// "62", "<1"
                let inRange: String
                /// "70–145 mg/dL"
                let inRangeRange: String
                let segments: [BandSegment]
                let tirTitle: String
                let tir: String
                let titrTitle: String
                let titr: String
                let unit: String
                let mean: String
                let cv: String
                /// "Below 70"
                let belowTitle: String
                /// "1 h 05 m"
                let below: String
                let coverage: String
            }

            /// "Mon 27 Oct"
            let title: String
            /// "Day 5 of 7"
            let subtitle: String
            /// nil for a day without readings: "No readings"
            let numbers: Numbers?
        }

        /// "17 Oct – 30 Oct"
        let dateRange: String
        /// a slot for every day, a bar for each with readings: the bands stacked from very low up, fractions of the day's
        /// covered time
        let plot: StatsDayBars.Plot
        /// oldest -> newest, the last one today
        let days: [DailyResult.Day]
        /// by day
        let labels: [StatsDayLabel]
        let legendBands: [GlucoseBand]
        let units: GlucoseUnits
        /// "70–145 mg/dL"
        let inRangeRange: String
        let tirTitle: String
        let titrTitle: String
        /// "Below 70"
        let belowTitle: String

        @MainActor init(_ result: DailyResult, period: StatsPeriod, settings: StatsSettings) {
            typealias Format = StatsFormatting
            let bands = result.summary.bands
            let units = settings.units

            self.units = units
            days = result.days
            labels = result.labels
            dateRange = Format.dateRange(result.summary.window, period: period)
            legendBands = bands.visibleBands
            inRangeRange = Format.inRangeLabel(bands: bands, units: units)
            tirTitle = Format.tirTitle(bands: bands, units: units)
            titrTitle = Format.titrTitle(bands: bands, units: units)
            belowTitle = String(
                format: NSLocalizedString("Below %@", comment: "Statistics Daily: the time below your range, its low end"),
                Format.glucose(bands.low, units: units)
            )

            // the strings come formatted with the result (`StatsDayLabel`): only assembled here; no room above 100%
            // (no dots)
            plot = StatsDayBars.Plot(
                days: result.days.map(\.day),
                labels: result.labels,
                parts: result.days.flatMap { day in
                    day.segments.map {
                        StatsDayBars.Part(
                            day: day.day.start,
                            series: $0.band.rawValue,
                            lower: $0.lower,
                            upper: $0.upper,
                            style: StatsBarStyle(fill: $0.band.color)
                        )
                    }
                },
                levels: Self.levels,
                levelLabels: Self.levels.map { Format.percent(fraction: $0) },
                headroom: 1,
                opaqueFills: true
            )
        }

        /// The selected day's numbers, formatted as the Trace formats that day's: the same values, the same strings.
        @MainActor func card(at index: Int) -> Card {
            typealias Format = StatsFormatting
            let day = days[index]
            let title = labels[index].title
            let subtitle = String(
                format: NSLocalizedString("Day %d of %d", comment: "Statistics Trace, the day picked of the period's days"),
                index + 1,
                days.count
            )
            guard day.hasReadings else {
                return Card(title: title, subtitle: subtitle, numbers: nil)
            }

            let unit = Format.unit(units)
            let numbers = Card.Numbers(
                inRange: Format.percentNumber(.inRange, of: day),
                inRangeRange: inRangeRange,
                segments: day.segments.map { BandSegment(band: $0.band, fraction: $0.upper - $0.lower) },
                tirTitle: tirTitle,
                tir: Format.percent(day.tirPercent),
                titrTitle: titrTitle,
                titr: Format.percent(day.titrPercent),
                unit: unit,
                mean: day.mean.map { Format.glucose($0, units: units) } ?? "–",
                cv: day.cv.map { Format.percent(Int($0.rounded())) } ?? "–",
                belowTitle: belowTitle,
                below: Format.duration(seconds: day.secondsBelowLow),
                coverage: Format.percent(day.coveragePercent)
            )
            return Card(title: title, subtitle: subtitle, numbers: numbers)
        }
    }
}

struct DailyView: View {
    let daily: Stat.Daily
    let selection: DailySelection

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var headlineSize: CGFloat = 28

    var body: some View {
        let index = selection.index(in: daily.plot.dayIntervals)
        let card = index.map { daily.card(at: $0) }
        VStack(spacing: 16) {
            StatsCard { chartCard(index: index) }
            if let index, let card {
                StatsCard { dayCard(card, index: index) }
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder private func chartCard(index: Int?) -> some View {
        StatsCardHeader(title: "Day by day", range: daily.dateRange)

        if let index {
            StatsDayBarsChart(plot: daily.plot, selected: index, selection: selection)
        }

        BandLegend(bands: daily.legendBands)
    }

    // MARK: - The selected day

    @ViewBuilder private func dayCard(_ card: Stat.Daily.Card, index: Int) -> some View {
        StatsStepper(title: card.title, subtitle: card.subtitle, index: index, count: daily.days.count) {
            selection.pick($0, in: daily.plot.dayIntervals)
        }

        if let numbers = card.numbers {
            headline(numbers)
            BandBar(segments: numbers.segments, cornerRadius: 4)
                .frame(height: 12)
            tileGrid(numbers)
        } else {
            Text("No readings")
                .statsEmptyNote()
        }
    }

    private func headline(_ numbers: Stat.Daily.Card.Numbers) -> some View {
        let percent = HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(numbers.inRange)
                .font(.system(size: headlineSize, weight: .bold))
                .monospacedDigit()
            Text(verbatim: "%")
                .font(.title3.weight(.semibold))
        }
        let title = Text("in your range")
            .font(.subheadline.weight(.semibold))
        let range = Text(numbers.inRangeRange)
            .statsFootnote()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                percent
                title
                Spacer(minLength: 8)
                range
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    percent
                    title
                }
                range
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tiles(_ numbers: Stat.Daily.Card.Numbers) -> [StatsTileItem] {
        [
            StatsTileItem(id: 0, title: numbers.tirTitle, value: numbers.tir),
            StatsTileItem(id: 1, title: numbers.titrTitle, value: numbers.titr),
            StatsTileItem(
                id: 2,
                title: NSLocalizedString("Mean", comment: "Statistics, mean glucose"),
                value: numbers.mean,
                unit: numbers.unit
            ),
            StatsTileItem(id: 3, title: NSLocalizedString("CV", comment: ""), value: numbers.cv),
            StatsTileItem(id: 4, title: numbers.belowTitle, value: numbers.below),
            StatsTileItem(
                id: 5,
                title: NSLocalizedString("Coverage", comment: "Statistics Daily, the CGM coverage of the day"),
                value: numbers.coverage
            )
        ]
    }

    private func tileGrid(_ numbers: Stat.Daily.Card.Numbers) -> some View {
        // three columns, two at the larger text sizes
        StatsTileGrid(tiles(numbers), columns: StatTile.columns(dynamicTypeSize, regular: 3))
    }
}
