import SwiftUI

// MARK: - Today

extension Stat.Insulin {
    /// The Today period: today so far against the usual by now, the headline days of the 7 before today by the same
    /// clock time (`InsulinStatsEngine.clockAverage` of the days read with it, `InsulinStatsService.today`: Home's insulin
    /// card's; basal scaled by their coverage), as of the read's time (`InsulinResult.asOf`, to its minute). Nothing
    /// moves with the clock: a later read shows a later time.
    struct Today: Equatable {
        /// A bolus of today's list.
        struct Bolus: Equatable, Identifiable {
            let id: Int
            /// "08:12"
            let time: String
            /// "Bolus", "External Insulin"
            let name: String
            /// "4.5 U", "2.35 U"
            let units: String
        }

        /// A clock hour of today: its insulin and the usual in it.
        struct HourReadout: Equatable {
            /// "14:00–15:00"
            let time: String
            /// the current hour: "so far"
            let subtitle: String?
            /// today, the usual
            let rows: [HourRow]
        }

        /// "Today, 00:00–14:35"
        let dateRange: String
        /// a bolus, a temp or covered time today: without, "No pump data"
        let hasData: Bool
        /// "17.5"; "–" without covered time (the basal is unknown)
        let total: String
        /// "Usual by 14:35 · 7 d"
        let usualTitle: String
        /// "18.0 U"; "–" without a complete day
        let usual: String
        /// today's total less the usual by now, by its sign alone: "+1.2 U", "−0.4 U", "±0.0 U"; nil without either
        let difference: String?
        /// no complete day in the 7 before today (rule a): no usual, "Needs one complete day"
        let needsCompleteDay: Bool
        let split: [StatsSplitBar.Segment]
        /// basal, SMB, bolus: today's U and %, the usual by now
        let rows: [Row]
        /// today's hours up to now (the current one outlined), the usual a tick in each hour
        let hourPlot: StatsHourBars.Plot
        let hourLegend: [StatsChartLegend.Item]
        /// by hour, from 00:00
        let hourReadouts: [HourReadout]
        /// the basal as a share of the schedule so far: "92%", "–"
        let vsScheduled: String
        /// "of 12.0 U": the scheduled basal so far; nil without covered time
        let scheduledSoFar: String?
        /// "1 h 05 m", "–"
        let zeroBasal: String
        /// today's IOB so far over the usual, after the Basal so far card
        let iobCard: IOBCard
        /// today's time below zero so far, by hour over the usual, after the IOB card
        let negativeCard: NegativeIOBCard
        /// some of today's covered time is before the oldest basal schedule
        let profileAssumed: Bool
        /// the boluses (not the SMBs), oldest -> newest
        let boluses: [Bolus]
        /// "12 SMBs", nil without one
        let smbCount: String?
        /// "3.4 U": the SMBs' total
        let smbTotal: String

        /// The outline of the current hour: its insulin so far.
        static let currentHourStyle = StatsBarStyle(fill: .clear, stroke: Color(.insulin))
        /// The readout's "Today" row: today's insulin in the hour, its parts stacked in the bars (the insulin colour,
        /// the current hour's outline's; not a part's swatch)
        static let todayHourStyle = StatsBarStyle(fill: Color(.insulin))

        /// - Parameter calendar: the read's: the clock hours of its days
        @MainActor init(_ result: Stat.InsulinResult, calendar: Calendar = .current) {
            typealias Format = StatsFormatting
            typealias Insulin = Stat.Insulin
            let parts = InsulinPart.allCases
            // the read's time to its minute, as shown ("by 14:35")
            let minute = calendar.dateInterval(of: .minute, for: result.asOf)?.start ?? result.asOf
            let day = result.insulin.days.last(where: \.isToday)
            let average = InsulinStatsEngine.clockAverage(result.insulin.days)
            let covered = (day?.coveredSeconds ?? 0) > 0
            // without covered time the basal is unknown (the day card's rule), the boluses are not
            let values: [Double?] = [covered ? day?.basal ?? 0 : nil, day?.smb ?? 0, day?.bolus ?? 0]
            let total = covered ? day?.total : nil
            let usualParts = average?.parts(at: minute, calendar: calendar)
            let usualTotal = average?.value(at: minute, calendar: calendar)

            let wholeDay = day?.day ?? calendar.dateInterval(of: .day, for: minute)
                ?? DateInterval(start: calendar.startOfDay(for: minute), duration: .hours(24))
            dateRange = Format.dateRange(wholeDay, period: .today, now: minute)
            hasData = day?.hasData ?? false
            self.total = total.map { StatsAmount.number($0, digits: 1) } ?? "–"
            usualTitle = String(
                format: NSLocalizedString(
                    "Usual by %1$@ · %2$@",
                    comment: "Statistics Insulin Today: the insulin of the period's complete days by this clock time (\"14:35\", \"7 d\")"
                ),
                minute.formatted(date: .omitted, time: .shortened),
                Format.label(result.period)
            )
            usual = usualTotal.map { StatsAmount.units($0, digits: 1) } ?? "–"
            difference = total.flatMap { total in usualTotal.map { Insulin.signedUnits(total - $0) } }
            needsCompleteDay = average == nil

            let percents = GlucoseStatsEngine.largestRemainder(values.map { $0 ?? 0 })
            split = total == nil ? [] : StatsSplitBar.segments(values.map { $0 ?? 0 }, styles: parts.map(\.style))
            rows = parts.map { part in
                Row(
                    part: part,
                    value: values[part.rawValue].map { StatsAmount.units($0, digits: 1) } ?? "–",
                    percent: total == nil ? "–" : Format.percent(percents[part.rawValue]),
                    usual: usualParts.map { StatsAmount.units($0[part.rawValue], digits: 1) } ?? "–"
                )
            }

            // by hour: the hours before now in full, the current one outlined (its insulin so far), none after it
            let hourChart = Self.hourChart(
                day,
                covered: covered,
                average: average,
                minute: minute,
                wholeDay: wholeDay,
                period: result.period,
                calendar: calendar
            )
            hourPlot = hourChart.plot
            hourLegend = hourChart.legend
            hourReadouts = hourChart.readouts

            // basal so far
            vsScheduled = (covered ? day?.basalVsScheduled : nil).map { Format.percent(fraction: $0) } ?? "–"
            scheduledSoFar = Self.scheduledSoFar(day, covered: covered)
            let zeroSeconds: Double? = covered ? day?.zeroBasalSeconds : nil
            zeroBasal = zeroSeconds.map { Format.duration(seconds: $0) } ?? "–"
            iobCard = Insulin.iobCard(today: result.insulin.days, now: minute, period: result.period, calendar: calendar)
            negativeCard = Insulin.negativeCard(
                today: result.insulin.days,
                average: average,
                now: minute,
                period: result.period,
                calendar: calendar
            )
            profileAssumed = covered && day?.profileAssumed == true

            // the boluses, then the SMBs counted
            let bolusList = Self.boluses(day)
            boluses = bolusList.boluses
            smbCount = bolusList.smbCount
            smbTotal = bolusList.smbTotal
        }

        // MARK: The init's parts

        /// By hour: today's hours up to now (the current one outlined), the usual a tick in each hour, and the hours'
        /// readouts.
        @MainActor private static func hourChart(
            _ day: DayInsulin?,
            covered: Bool,
            average: InsulinClockAverage?,
            minute: Date,
            wholeDay: DateInterval,
            period: StatsPeriod,
            calendar: Calendar
        ) -> (
            plot: StatsHourBars.Plot,
            legend: [StatsChartLegend.Item],
            readouts: [HourReadout]
        ) {
            typealias Format = StatsFormatting
            let parts = InsulinPart.allCases
            let clock = InsulinClockAverage.clock(of: minute, calendar: calendar)
            let currentHour = wholeDay.contains(minute) ? clock.hour : -1
            let hours = (0 ..< 24).map { hour in day?.hours.first { $0.hour == hour } }
            let hourValues = hours.map { h -> [Double] in
                [covered ? h?.basal ?? 0 : 0, h?.smb ?? 0, h?.bolus ?? 0]
            }
            let hourTotals = hourValues.map { $0.reduce(0, +) }
            // no covered time and no insulin: no pump data ("–", as on Home); the current hour's data may be coming while
            // the coverage reaches into the hour before it (its 0 so far, as Home's outline)
            let hourHasData = hours.indices.map { (hours[$0]?.coveredSeconds ?? 0) > 0 || hourTotals[$0] > 0 }
            let lastCoveredHour = hours.lastIndex { ($0?.coveredSeconds ?? 0) > 0 }
            let coverageReachesCurrentHour = (lastCoveredHour ?? -2) >= currentHour - 1
            let shownValues = hourValues.indices.map { $0 < currentHour ? hourValues[$0] : [] }
            var hourParts = StatsHourBars.Plot.stacked(shownValues, styles: parts.map(\.style))
            let currentTotal = hourTotals.indices.contains(currentHour) ? hourTotals[currentHour] : 0
            if currentTotal > 0 {
                hourParts.append(StatsHourBars.Part(
                    hour: currentHour,
                    series: 0,
                    lower: 0,
                    upper: currentTotal,
                    style: Self.currentHourStyle
                ))
            }
            let usualHours = average?.within ?? []
            let shownTotals = hourTotals.indices.map { $0 <= currentHour ? hourTotals[$0] : 0 }
            let hourLevels = StatsBarAxis.levels(
                maximum: Swift.max(shownTotals.max() ?? 0, usualHours.max() ?? 0),
                unit: 0.5,
                divisions: 2
            )
            let plot = StatsHourBars.Plot(
                parts: hourParts,
                usual: usualHours.map { Optional($0) },
                yDomain: 0 ... (hourLevels.last ?? 1),
                levels: hourLevels,
                levelLabels: hourLevels.map { StatsAmount.number($0, digits: 0 ... 2) }
            )
            var hourLegend = parts.map { StatsChartLegend.Item(id: $0.rawValue, key: .swatch($0.style), title: $0.name) }
            if currentTotal > 0 {
                hourLegend.append(StatsChartLegend.Item(
                    id: 9,
                    key: .swatch(Self.currentHourStyle),
                    title: NSLocalizedString(
                        "This hour so far",
                        comment: "Statistics Insulin Today by hour: the outlined bar of the current hour"
                    )
                ))
            }
            if average != nil {
                hourLegend.append(StatsChartLegend.Item(
                    id: 10,
                    key: .tick,
                    title: String(
                        format: NSLocalizedString(
                            "Usual · %@",
                            comment: "Statistics Insulin Today by hour: the usual by hour, over the period (\"7 d\")"
                        ),
                        Format.label(period)
                    )
                ))
            }
            hourLegend.append(StatsChartLegend.Item(
                id: 11,
                key: .none,
                title: NSLocalizedString("U per hour", comment: "Statistics Insulin by hour: the unit")
            ))
            let readouts = (0 ..< 24).map { hour in
                let time = Stat.AGP.clockInterval(from: hour * 60, to: (hour + 1) * 60)
                // the hours before now with pump data, the current one so far; the others (to come, or without pump
                // data) "–"
                let shown = hour < currentHour
                    ? hourHasData[hour]
                    : hour == currentHour && (hourHasData[hour] || coverageReachesCurrentHour)
                let today = shown ? StatsAmount.units(hourTotals[hour], digits: 2) : "–"
                let usual = usualHours.indices.contains(hour) ? StatsAmount.units(usualHours[hour], digits: 2) : "–"
                let todayTitle = NSLocalizedString("Today", comment: "")
                let usualTitle = NSLocalizedString("Usual", comment: "Statistics Insulin Today: the usual insulin")
                return HourReadout(
                    time: time,
                    subtitle: hour == currentHour ? NSLocalizedString("so far", comment: "") : nil,
                    rows: [
                        HourRow(id: 0, key: .swatch(Self.todayHourStyle), name: todayTitle, value: today, emphasized: true),
                        HourRow(id: 1, key: .tick, name: usualTitle, value: usual)
                    ]
                )
            }
            return (plot, hourLegend, readouts)
        }

        /// "of 12.0 U": the scheduled basal so far; nil without covered time.
        @MainActor private static func scheduledSoFar(_ day: DayInsulin?, covered: Bool) -> String? {
            covered ? day.map { day in
                String(
                    format: NSLocalizedString(
                        "of %@",
                        comment: "Statistics Insulin Today: the scheduled basal so far, \"12.0 U\""
                    ),
                    StatsAmount.units(day.scheduled, digits: 1)
                )
            } : nil
        }

        /// The boluses (not the SMBs), then the SMBs counted and their total.
        @MainActor private static func boluses(_ day: DayInsulin?) -> (boluses: [Bolus], smbCount: String?, smbTotal: String) {
            let all = day?.boluses ?? []
            let boluses = all.filter { !$0.isSMB }.enumerated().map { offset, bolus in
                Bolus(
                    id: offset,
                    time: bolus.date.formatted(date: .omitted, time: .shortened),
                    name: bolus.isExternal
                        ? NSLocalizedString("External Insulin", comment: "")
                        : NSLocalizedString("Bolus", comment: "Statistics Insulin: the other boluses"),
                    units: StatsAmount.withUnits(StatsAmount.number(bolus.units, digits: 1 ... 2))
                )
            }
            let smbs = all.filter(\.isSMB).count
            let smbCount: String? = smbs == 0 ? nil : smbs == 1
                ? NSLocalizedString("1 SMB", comment: "Statistics Insulin Today: the SMBs so far")
                : String(format: NSLocalizedString("%d SMBs", comment: "Statistics Insulin Today: the SMBs so far"), smbs)
            return (boluses, smbCount, StatsAmount.units(day?.smb ?? 0, digits: 1))
        }
    }

    /// A difference by its sign alone: "+1.2 U", "−0.4 U", "±0.0 U" when it rounds to 0 (no colour: neither way is
    /// better).
    static func signedUnits(_ value: Double, digits: Int = 1) -> String {
        let magnitude = StatsAmount.number(abs(value), digits: digits)
        let sign = magnitude == StatsAmount.number(0, digits: digits) ? "±" : value > 0 ? "+" : "−"
        return StatsAmount.withUnits(sign + magnitude)
    }
}
