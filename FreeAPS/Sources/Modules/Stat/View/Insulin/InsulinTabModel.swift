import SwiftUI

extension Stat {
    /// The Insulin tab, formatted for display. The days, the summary (rule a) and the hours come ready from the provider
    /// (`InsulinResult`, `InsulinStatsService`); only strings and the charts' plots are built here, the selected day's
    /// card when it is shown (`card(at:)`).
    struct Insulin: Equatable {
        /// basal, SMB, bolus: U and % of the total.
        typealias Row = InsulinPartRow

        /// The selected day, formatted.
        struct DayCard: Equatable {
            /// "Tue 28 Oct", "Today"
            let title: String
            /// a bolus, a temp or covered time in it: without, "No pump data"
            let hasData: Bool
            /// "38.2"; "–" without covered time (the basal is unknown)
            let total: String
            /// today: "so far"
            let soFar: Bool
            /// "Pump data for 13 h 05 m of 24 h" (a past day not covered in full), "Not in the average" (under half)
            let notes: [String]
            let split: [StatsSplitBar.Segment]
            let rows: [Row]
            let vsScheduled: String
            let zeroBasal: String
            let negativeIOB: String
            /// "−0.42 U": the day's lowest IOB below zero, "–" without
            let lowestIOB: String
            /// some of its covered time is before the oldest basal schedule: "Profile assumed"
            let profileAssumed: Bool
        }

        /// A row of the selected hour.
        struct HourRow: Equatable, Identifiable {
            let id: Int
            let key: StatsChartLegend.Key
            let name: String
            /// "0.71 U", "–"
            let value: String
            var emphasized = false
        }

        /// A clock hour, formatted: the stepper's title and subtitle, and its rows.
        struct HourReadout: Equatable {
            /// "14:00–15:00"
            let time: String
            /// "6 days · 6 hours of data"
            let subtitle: String
            /// basal, scheduled basal, SMB, bolus, total
            let rows: [HourRow]
            let vsScheduled: String
            let zeroBasal: String
            /// the time below zero in the hour, per day of IOB time: "4 m", "–" without IOB rows
            let negativeIOB: String
        }

        /// the period computed (Today's 7 d: its label; its days the 7 before today and today)
        let period: StatsPeriod
        /// the period shown: Today, or `period`
        let shown: StatsPeriod
        /// the Today period's view (`shown` Today); nil for 7–90 d
        let today: Today?
        /// "17 Oct – 30 Oct"
        let dateRange: String
        /// "Days with pump data 5 of 7": the count the limited note leaves out
        let daysWithData: String
        /// why the headline is provisional (`Stat.Insulin.limitedNote`), marked after it; nil when it isn't
        let limitedNote: String?
        /// "38.2", "–" without a complete day
        let tdd: String
        /// no complete day yet (rule a): "–" and "Needs one complete day"
        let needsCompleteDay: Bool
        let split: [StatsSplitBar.Segment]
        let rows: [Row]
        let basalVsScheduled: String
        let scheduled: String
        let zeroBasal: String
        /// the IOB by time of day, after the Basal card
        let iobCard: IOBCard
        /// the time below zero, after the IOB card
        let negativeCard: NegativeIOBCard
        /// "Profile assumed before 22 Oct: the oldest known basal schedule is used"
        let profileAssumedNote: String?
        let dayPlot: StatsDayBars.Plot
        let dayLegend: [StatsChartLegend.Item]
        /// oldest -> newest, the last one today
        let days: [DayInsulin]
        /// by day
        let labels: [StatsDayLabel]
        let hourPlot: StatsHourBars.Plot
        let hourLegend: [StatsChartLegend.Item]
        let vsPlot: StatsHourBars.Plot
        let vsLegend: [StatsChartLegend.Item]
        /// by hour, from 00:00
        let hourReadouts: [HourReadout]

        /// - Parameter calendar: the read's (Today's clock hours)
        @MainActor init(_ result: InsulinResult, calendar: Calendar = .current) {
            typealias Format = StatsFormatting
            let summary = result.insulin.summary
            let parts = InsulinPart.allCases

            period = result.period
            shown = result.shown
            today = result.shown == .today ? Today(result, calendar: calendar) : nil
            days = result.insulin.days
            labels = result.labels
            dateRange = Format.dateRange(summary.window, period: result.period)
            daysWithData = String(
                format: NSLocalizedString(
                    "Days with pump data %@",
                    comment: "Statistics Insulin: the days with pump data, \"5 of 7\""
                ),
                Format.days(summary.daysWithData, of: summary.calendarDays)
            )
            needsCompleteDay = summary.needsCompleteDay
            limitedNote = Self.limitedNote(summary)
            tdd = summary.tdd.map { StatsAmount.number($0, digits: 1) } ?? "–"

            let means = [summary.basal, summary.smb, summary.bolus]
            split = StatsSplitBar.segments(means.map { $0 ?? 0 }, styles: parts.map(\.style))
            rows = parts.map { part in
                Row(
                    part: part,
                    value: means[part.rawValue].map { StatsAmount.units($0, digits: 1) } ?? "–",
                    percent: summary.tdd == nil ? "–" : Format.percent(summary.splitPercents[part.rawValue])
                )
            }

            basalVsScheduled = summary.basalVsScheduledPercent.map { Format.percent($0) } ?? "–"
            scheduled = summary.scheduledPerDay.map { StatsAmount.number($0, digits: 1) } ?? "–"
            zeroBasal = summary.zeroBasalSecondsPerDay.map { Format.duration(seconds: $0) } ?? "–"
            let dayTitles = result.labels.map(\.title)
            iobCard = Self.iobCard(period: result.insulin.days, titles: dayTitles)
            negativeCard = Self.negativeCard(period: result.insulin.days, titles: dayTitles, summary: summary)
            profileAssumedNote = Self.profileAssumedNote(summary)

            // day by day
            let dayChart = Self.dayChart(result.insulin.days, labels: result.labels, summary: summary)
            dayPlot = dayChart.plot
            dayLegend = dayChart.legend

            // by hour
            let hours = result.insulin.hours
            let headlineDays = summary.headlineDays
            let hourChart = Self.hourChart(hours)
            hourPlot = hourChart.plot
            hourLegend = hourChart.legend
            vsPlot = Self.vsPlot(hours)
            vsLegend = Self.vsLegend
            hourReadouts = Self.hourReadouts(hours, days: result.insulin.days, headlineDays: headlineDays)
        }

        // MARK: - The init's parts

        /// "Profile assumed before 22 Oct: …"; nil when no time is before the oldest basal schedule.
        @MainActor private static func profileAssumedNote(_ summary: InsulinSummary) -> String? {
            summary.profileAssumedBefore.map { date in
                String(
                    format: NSLocalizedString(
                        "Profile assumed before %@: the oldest known basal schedule is used",
                        comment: "Statistics Insulin: the date of the oldest basal schedule known"
                    ),
                    date.formatted(.dateTime.day().month(.abbreviated))
                )
            }
        }

        /// The day chart: the parts stacked by day, the TDD dashed, a dot above a partial day.
        @MainActor private static func dayChart(
            _ days: [DayInsulin],
            labels: [StatsDayLabel],
            summary: InsulinSummary
        ) -> (plot: StatsDayBars.Plot, legend: [StatsChartLegend.Item]) {
            let parts = InsulinPart.allCases
            let dayValues = days.map(Self.dayValues)
            let dayLevels = StatsBarAxis.levels(
                maximum: Swift.max(dayValues.map { $0.reduce(0, +) }.max() ?? 0, summary.tdd ?? 0),
                unit: Self.dayAxisUnit,
                divisions: 3
            )
            let marked = days.map(Self.isPartial)
            let plot = StatsDayBars.Plot(
                days: days.map(\.day),
                labels: labels,
                values: dayValues,
                styles: parts.map(\.style),
                marked: marked,
                levels: dayLevels,
                levelLabels: dayLevels.map { $0 == 0 ? StatsAmount.withUnits("0") : StatsAmount.number($0, digits: 0) },
                average: summary.tdd
            )
            var dayLegend = parts.map { StatsChartLegend.Item(id: $0.rawValue, key: .swatch($0.style), title: $0.name) }
            if let tdd = summary.tdd {
                dayLegend.append(StatsChartLegend.Item(
                    id: 10,
                    key: .dashed,
                    title: String(
                        format: NSLocalizedString("Average %@ U", comment: "Statistics Insulin chart legend: the TDD"),
                        StatsAmount.number(tdd, digits: 1)
                    )
                ))
            }
            if marked.contains(true) {
                dayLegend.append(StatsChartLegend.Item(
                    id: 11,
                    key: .dot,
                    title: NSLocalizedString("Partial pump data", comment: "Statistics Insulin chart legend: the dot above a day")
                ))
            }
            return (plot, dayLegend)
        }

        /// By hour: the parts stacked by hour, the scheduled basal as steps.
        @MainActor private static func hourChart(
            _ hours: [InsulinHourSummary]
        ) -> (plot: StatsHourBars.Plot, legend: [StatsChartLegend.Item]) {
            let parts = InsulinPart.allCases
            let hourValues = hours.map { [$0.basal ?? 0, $0.smb, $0.bolus] }
            let hourLevels = StatsBarAxis.levels(
                maximum: hours.map { Swift.max($0.total, $0.scheduled ?? 0) }.max() ?? 0,
                unit: 0.5,
                divisions: 2
            )
            let plot = StatsHourBars.Plot(
                parts: StatsHourBars.Plot.stacked(hourValues, styles: parts.map(\.style)),
                steps: hours.map(\.scheduled),
                yDomain: 0 ... (hourLevels.last ?? 1),
                levels: hourLevels,
                levelLabels: hourLevels.map { StatsAmount.number($0, digits: 0 ... 2) }
            )
            let scheduledTitle = NSLocalizedString("Scheduled basal", comment: "Statistics Insulin: the basal schedule")
            let legend = parts.map { StatsChartLegend.Item(id: $0.rawValue, key: .swatch($0.style), title: $0.name) } + [
                StatsChartLegend.Item(id: 10, key: .step, title: scheduledTitle),
                StatsChartLegend.Item(
                    id: 11,
                    key: .none,
                    title: NSLocalizedString("U per hour", comment: "Statistics Insulin by hour: the unit")
                )
            ]
            return (plot, legend)
        }

        /// Basal vs scheduled: its legend (the plot is `vsPlot`).
        @MainActor private static var vsLegend: [StatsChartLegend.Item] {
            [
                StatsChartLegend.Item(
                    id: 0,
                    key: .swatch(Self.moreThanScheduled),
                    title: NSLocalizedString("More than scheduled", comment: "Statistics Insulin: basal above the schedule")
                ),
                StatsChartLegend.Item(
                    id: 1,
                    key: .swatch(Self.lessThanScheduled),
                    title: NSLocalizedString("Less than scheduled", comment: "Statistics Insulin: basal below the schedule")
                )
            ]
        }

        /// The clock hours' readouts, from 00:00.
        @MainActor private static func hourReadouts(
            _ hours: [InsulinHourSummary],
            days: [DayInsulin],
            headlineDays: Int
        ) -> [HourReadout] {
            let negativeHours = InsulinStatsEngine.clockAverage(days)?.negativeIOBSeconds?.within
            return hours.map { hour in
                Self.readout(
                    hour,
                    days: headlineDays,
                    negativeIOBSeconds: negativeHours.flatMap { $0.indices.contains(hour.hour) ? $0[hour.hour] : nil }
                )
            }
        }

        // MARK: - The selected day

        /// The selected day's card.
        @MainActor func card(at index: Int) -> DayCard {
            typealias Format = StatsFormatting
            let day = days[index]
            let title = day.isToday ? NSLocalizedString("Today", comment: "") : labels[index].title
            let covered = day.coveredSeconds > 0
            let values = [covered ? day.basal : nil, day.smb, day.bolus]
            let total = covered ? day.total : nil
            let percents = GlucoseStatsEngine.largestRemainder(values.map { $0 ?? 0 })

            var notes: [String] = []
            if day.hasData, !day.isToday {
                if Self.isPartial(day) {
                    notes.append(String(
                        format: NSLocalizedString(
                            "Pump data for %1$@ of %2$d h",
                            comment: "Statistics Insulin day: the time the pump data covers, the day's hours"
                        ),
                        Format.duration(seconds: day.coveredSeconds),
                        Int((day.day.duration / 3600).rounded())
                    ))
                }
                if !day.isHeadline {
                    notes.append(NSLocalizedString(
                        "Not in the average",
                        comment: "Statistics Insulin day: covered less than half, left out of the TDD"
                    ))
                }
            }

            let zeroSeconds: Double? = covered ? day.zeroBasalSeconds : nil
            let negativeSeconds: Double? = day.iobSeconds > 0 ? day.negativeIOBSeconds : nil
            return DayCard(
                title: title,
                hasData: day.hasData,
                total: total.map { StatsAmount.number($0, digits: 1) } ?? "–",
                soFar: day.isToday,
                notes: notes,
                split: total == nil ? [] : StatsSplitBar
                    .segments(values.map { $0 ?? 0 }, styles: InsulinPart.allCases.map(\.style)),
                rows: InsulinPart.allCases.map { part in
                    Row(
                        part: part,
                        value: values[part.rawValue].map { StatsAmount.units($0, digits: 1) } ?? "–",
                        percent: total == nil ? "–" : Format.percent(percents[part.rawValue])
                    )
                },
                vsScheduled: (covered ? day.basalVsScheduled : nil).map { Format.percent(fraction: $0) } ?? "–",
                zeroBasal: zeroSeconds.map { Format.duration(seconds: $0) } ?? "–",
                negativeIOB: negativeSeconds.map { Format.duration(seconds: $0) } ?? "–",
                lowestIOB: day.iob.lowest.map { StatsAmount.withUnits(Self.signedIOB($0.iob)) } ?? "–",
                profileAssumed: covered && day.profileAssumed
            )
        }

        // MARK: - Rules (pure)

        /// The day chart's y axis: whole multiples of 15 U (at least one), gridlines in thirds.
        static let dayAxisUnit = 15.0

        /// Basal, SMB, bolus of a day's bar: the basal only when the day has covered time (without, it is unknown),
        /// the boluses always.
        static func dayValues(_ day: DayInsulin) -> [Double] {
            [day.coveredSeconds > 0 ? day.basal : 0, day.smb, day.bolus]
        }

        /// A past day with pump data its coverage doesn't fill (as rounded, the limited rule's): the dot above its bar,
        /// "Pump data for … of 24 h". Today is never partial (it is "so far").
        static func isPartial(_ day: DayInsulin) -> Bool {
            !day.isToday && day.hasData && Int((day.coverageFraction * 100).rounded()) < 100
        }

        /// The pump-data note, without counts (the header says "Days with pump data n of N"): when the summary is
        /// limited and has a headline (with none it reads "Needs one complete day").
        static func limitedNote(_ summary: InsulinSummary) -> String? {
            guard summary.isLimited, !summary.isEmpty, summary.tdd != nil else { return nil }
            return NSLocalizedString(
                "Pump data doesn't cover every complete day of this period, so these numbers may not represent it.",
                comment: "Statistics limited data: the pump data doesn't cover every complete day"
            )
        }

        /// The basal vs scheduled bars: from 100% up or down to each hour's share, the scale symmetric around 100% in
        /// steps of 25 points (at least one, at most 100, a share past it drawn at the edge).
        static func vsPlot(_ hours: [InsulinHourSummary]) -> StatsHourBars.Plot {
            let shares = hours.map { $0.basalVsScheduled.map { $0 * 100 } }
            let span = vsSpan(shares.compactMap { $0 })
            let domain = (100 - span) ... (100 + span)
            let parts = hours.indices.compactMap { index -> StatsHourBars.Part? in
                guard let share = shares[index], share != 100 else { return nil }
                let shown = Swift.min(Swift.max(share, domain.lowerBound), domain.upperBound)
                return StatsHourBars.Part(
                    hour: hours[index].hour,
                    series: 0,
                    lower: Swift.min(shown, 100),
                    upper: Swift.max(shown, 100),
                    style: share > 100 ? moreThanScheduled : lessThanScheduled
                )
            }
            let levels = [domain.lowerBound, 100, domain.upperBound]
            return StatsHourBars.Plot(
                parts: parts,
                yDomain: domain,
                levels: levels,
                levelLabels: levels.map { "\(Int($0.rounded()))%" },
                baseline: 100
            )
        }

        /// The basal vs scheduled scale's half: the largest distance from 100% rounded up to 25 points, 25…100.
        static func vsSpan(_ shares: [Double]) -> Double {
            let largest = shares.map { abs($0 - 100) }.max() ?? 0
            return Swift.min(Swift.max((largest / 25).rounded(.up) * 25, 25), 100)
        }

        static let moreThanScheduled = StatsBarStyle(fill: Color(.insulin))
        static let lessThanScheduled = StatsBarStyle(fill: Color(.statsWarning))

        // MARK: - Formatting

        /// No complete day yet (rule a: today isn't averaged): the headline's note, and the cards' without one.
        static var noCompleteDay: String {
            NSLocalizedString("Needs one complete day", comment: "Statistics Insulin and Meals: no complete day yet")
        }

        /// The selected hour's subtitle: By hour's "6 days · 6 hours of data", with one day "1 day · …", and without a
        /// complete day "Needs one complete day" (the hours are over the headline days).
        static func hourDataNote(hours: Double, days: Int) -> String {
            guard days > 0 else { return noCompleteDay }
            return StatsFormatting.hourDataNote(hours: hours, days: days)
        }

        @MainActor private static func readout(
            _ hour: InsulinHourSummary,
            days: Int,
            negativeIOBSeconds: Double?
        ) -> HourReadout {
            typealias Format = StatsFormatting
            let time = AGP.clockInterval(from: hour.hour * 60, to: (hour.hour + 1) * 60)
            let basal = hour.basal.map { StatsAmount.units($0, digits: 2) } ?? "–"
            let scheduled = hour.scheduled.map { StatsAmount.units($0, digits: 2) } ?? "–"
            let smb = StatsAmount.units(hour.smb, digits: 2)
            let bolus = StatsAmount.units(hour.bolus, digits: 2)
            let hasData = hour.coveredHours > 0 || hour.smb > 0 || hour.bolus > 0
            let vsScheduled = hour.basalVsScheduled.map { Format.percent(fraction: $0) }
            return HourReadout(
                time: time,
                subtitle: hourDataNote(hours: hour.coveredHours, days: days),
                rows: [
                    HourRow(id: 0, key: .swatch(InsulinPart.basal.style), name: InsulinPart.basal.name, value: basal),
                    HourRow(
                        id: 1,
                        key: .step,
                        name: NSLocalizedString("Scheduled basal", comment: "Statistics Insulin: the basal schedule"),
                        value: scheduled
                    ),
                    HourRow(id: 2, key: .swatch(InsulinPart.smb.style), name: InsulinPart.smb.name, value: smb),
                    HourRow(id: 3, key: .swatch(InsulinPart.bolus.style), name: InsulinPart.bolus.name, value: bolus),
                    HourRow(
                        id: 4,
                        key: .none,
                        name: NSLocalizedString("Total", comment: ""),
                        value: hasData ? StatsAmount.units(hour.total, digits: 2) : "–",
                        emphasized: true
                    )
                ],
                vsScheduled: vsScheduled ?? "–",
                zeroBasal: hour.zeroBasalSeconds.map { Format.duration(seconds: $0) } ?? "–",
                negativeIOB: negativeIOBSeconds.map { Format.duration(seconds: $0) } ?? "–"
            )
        }
    }
}
