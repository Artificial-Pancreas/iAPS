import Charts
import SwiftUI

extension Stat {
    /// By hour (the Hour-of-day view), formatted for display. The hours, their columns and their percents come ready from
    /// the provider (`HourOfDayResult`); only strings are built here.
    struct HourOfDay: Equatable {
        /// the y axis: shares of the hour, gridlines at 0, 50 and 100%
        private static let levels: [Double] = [0, 0.5, 1]

        /// An hour, formatted: the stepper's title and subtitle, and its bands.
        struct Readout: Equatable {
            /// "08:00–09:00"
            let time: String
            /// "30 days · 12 hours of data"
            let subtitle: String
            /// the visible bands; for an hour without data they only keep the card's height (hidden, "No readings" over
            /// them), their percents "–"
            let rows: [StatsBandRow]
            /// false: "No readings"
            let hasData: Bool
        }

        /// A row of "When it happens": tapping it selects its hour.
        struct Peak: Equatable, Identifiable {
            let group: PeakHour.Group
            let hour: Int
            /// its swatch
            let band: GlucoseBand
            /// "Lows", "Highs", "Most in range"
            let title: String
            /// "below 70 · 12% of that hour"
            let subtitle: String
            /// "03:00–04:00"
            let time: String

            var id: PeakHour.Group { group }
        }

        /// "17 Oct – 30 Oct"
        let dateRange: String
        /// the hours with data, a column each: the bands stacked from very low up, fractions of the hour's covered time
        let plot: StatsHourBars.Plot
        /// by hour, from 00:00
        let readouts: [Readout]
        /// lows, highs, most in range; those whose peak share is 0 left out
        let peaks: [Peak]
        let legendBands: [GlucoseBand]

        @MainActor init(_ result: HourOfDayResult, period: StatsPeriod, settings: StatsSettings) {
            typealias Format = StatsFormatting
            let summary = result.summary
            let bands = summary.bands
            let units = settings.units
            let visible = bands.visibleBands
            let dayCount = period.calendarDayCount ?? 1

            dateRange = Format.dateRange(summary.window, period: period)
            legendBands = visible
            plot = StatsHourBars.Plot(
                parts: result.hours.flatMap { hour in
                    hour.segments.map {
                        StatsHourBars.Part(
                            hour: hour.hour,
                            series: $0.band.rawValue,
                            lower: $0.lower,
                            upper: $0.upper,
                            style: StatsBarStyle(fill: $0.band.color)
                        )
                    }
                },
                yDomain: 0.0 ... 1.0,
                levels: Self.levels,
                levelLabels: Self.levels.map { Format.percent(fraction: $0) },
                opaqueFills: true
            )
            readouts = zip(result.hours, result.labels).map { hour, time in
                Self.readout(hour, time: time, dayCount: dayCount, bands: bands, units: units)
            }

            // as the mock orders them: lows, highs, then the best hour
            let order: [PeakHour.Group] = [.below, .above, .inRange]
            peaks = order.compactMap { group -> Peak? in
                guard let peak = result.peaks.first(where: { $0.group == group }),
                      let index = result.hours.firstIndex(where: { $0.hour == peak.hour })
                else { return nil }
                let shown = GlucoseStatsEngine.peakPercent(peak, of: result.hours[index])
                let percent = Format.percent(shown.percent, belowOne: shown.belowOne)
                let time = result.labels[index]
                switch group {
                case .below:
                    return Peak(
                        group: group,
                        hour: peak.hour,
                        // very low alone when the low band is hidden (low at 54)
                        band: bands.range(of: .low) == nil ? .veryLow : .low,
                        title: NSLocalizedString("Lows", comment: "Statistics By hour, when it happens: below your range"),
                        subtitle: String(
                            format: NSLocalizedString(
                                "below %1$@ · %2$@ of that hour",
                                comment: "Statistics By hour, when it happens: your range's low end, the share of the hour"
                            ),
                            Format.glucose(bands.low, units: units),
                            percent
                        ),
                        time: time
                    )
                case .above:
                    return Peak(
                        group: group,
                        hour: peak.hour,
                        // very high alone when the high band is hidden (high at 250)
                        band: bands.range(of: .high) == nil ? .veryHigh : .high,
                        title: NSLocalizedString("Highs", comment: "Statistics By hour, when it happens: above your range"),
                        subtitle: String(
                            format: NSLocalizedString(
                                "above %1$@ · %2$@ of that hour",
                                comment: "Statistics By hour, when it happens: your range's high end, the share of the hour"
                            ),
                            Format.glucose(bands.high, units: units),
                            percent
                        ),
                        time: time
                    )
                case .inRange:
                    return Peak(
                        group: group,
                        hour: peak.hour,
                        band: .inRange,
                        title: NSLocalizedString(
                            "Most in range",
                            comment: "Statistics By hour, when it happens: the hour most in your range"
                        ),
                        subtitle: String(
                            format: NSLocalizedString(
                                "%@ of that hour in your range",
                                comment: "Statistics By hour, when it happens: the share of the hour"
                            ),
                            percent
                        ),
                        time: time
                    )
                }
            }
        }

        @MainActor private static func readout(
            _ hour: HourOfDayResult.Hour,
            time: String,
            dayCount: Int,
            bands: StatsBands,
            units: GlucoseUnits
        ) -> Readout {
            typealias Format = StatsFormatting
            let visible = bands.visibleBands
            func rows(_ percent: (GlucoseBand) -> String) -> [StatsBandRow] {
                Format.bandRows(visible, bands: bands, units: units, percent: percent)
            }
            guard hour.hasData else {
                return Readout(
                    time: time,
                    subtitle: String(
                        format: NSLocalizedString("%d days", comment: "Statistics AGP, the days of the period"),
                        dayCount
                    ),
                    rows: rows({ _ in "–" }),
                    hasData: false
                )
            }
            func percent(_ band: GlucoseBand) -> String {
                Format.percent(band, of: hour)
            }
            return Readout(
                time: time,
                subtitle: StatsFormatting.hourDataNote(hours: hour.hoursOfData, days: dayCount),
                rows: rows(percent),
                hasData: true
            )
        }
    }
}

struct HourOfDayView: View {
    let hourOfDay: Stat.HourOfDay
    let selection: HourSelection

    /// The chart, the selected hour, then when it happens.
    var body: some View {
        VStack(spacing: 16) {
            StatsCard { chartCard }
            StatsCard { HourOfDayReadout(readouts: hourOfDay.readouts, selection: selection) }
            if hourOfDay.peaks.isNotEmpty {
                StatsCard { peaks }
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder private var chartCard: some View {
        StatsCardHeader(title: "Ranges by hour of day", range: hourOfDay.dateRange)

        StatsHourBarsChart(plot: hourOfDay.plot, selection: selection)

        BandLegend(bands: hourOfDay.legendBands)
    }

    // MARK: - When it happens

    @ViewBuilder private var peaks: some View {
        Text("When it happens")
            .statsSectionTitle()
        VStack(spacing: 0) {
            StatsDividedRows(hourOfDay.peaks) { peak in
                peakRow(peak)
            }
        }
    }

    /// Tapping it selects its hour.
    private func peakRow(_ peak: Stat.HourOfDay.Peak) -> some View {
        Button {
            selection.select(peak.hour)
        } label: {
            HStack(spacing: 10) {
                BandSwatch(band: peak.band)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peak.title)
                        .font(.subheadline.weight(.semibold))
                    Text(peak.subtitle)
                        .statsFootnote()
                        .monospacedDigit()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(peak.time)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The selected hour

/// The stepper through the hours (around midnight too) and the selected hour's bands: the alternative to picking on the
/// chart. Re-rendered when the selection moves, the rest of the view isn't.
private struct HourOfDayReadout: View {
    let readouts: [Stat.HourOfDay.Readout]
    let selection: HourSelection

    var body: some View {
        if readouts.indices.contains(selection.hour) {
            let readout = readouts[selection.hour]
            VStack(alignment: .leading, spacing: 4) {
                StatsStepper(hourTitle: readout.time, subtitle: readout.subtitle, selection: selection)
                // without data the rows are hidden but keep their height, so stepping through an empty hour doesn't move
                // the cards below
                VStack(spacing: 0) {
                    StatsDividedRows(readout.rows) { row in
                        StatsBandRowView(row: row)
                    }
                }
                .opacity(readout.hasData ? 1 : 0)
                .overlay {
                    if !readout.hasData {
                        Text("No readings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
