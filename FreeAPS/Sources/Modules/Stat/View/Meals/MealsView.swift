import SwiftUI

extension Stat {
    /// The Meals tab, formatted for display. The days, the averages (complete days with entries) and the hours come
    /// ready from the provider (`MealsResult`); only strings and the charts' plots are built here, the selected day's card
    /// when it is shown (`card(at:)`). The fiber, vitamins and minerals in `nutrients`.
    struct Meals: Equatable {
        /// The parts of a day's bar, from the bottom: the carbs, and the carb equivalents of the fat and protein above.
        enum Part: Int, CaseIterable, Sendable {
            case carbs
            case carbEquivalents

            var name: String {
                switch self {
                case .carbs: return NSLocalizedString("Carbs", comment: "")
                case .carbEquivalents: return NSLocalizedString(
                        "Carb equivalents",
                        comment: "Statistics Meals: the carb equivalents of the fat and protein"
                    )
                }
            }

            var style: StatsBarStyle {
                switch self {
                // the outline reaches 3:1 on white (#C77700; in dark mode it is the fill's yellow)
                case .carbs: return StatsBarStyle(fill: Color(.loopYellow), stroke: Color(.statsCarbsOutline))
                // a light fill with the outline, as the mock's
                case .carbEquivalents: return StatsBarStyle(
                        fill: Color(.loopYellow).opacity(0.24),
                        stroke: Color(.statsCarbsOutline)
                    )
                }
            }
        }

        /// A number of the Carbs card (its `limitedNote`: the fiber's).
        typealias Tile = StatsTileItem

        /// An entry of the selected day.
        struct Entry: Equatable, Identifiable {
            let id: Int
            /// "08:12"
            let time: String
            /// "45 g"
            let carbs: String
            /// "fat 22 g · protein 30 g", when fat or protein are logged
            let detail: String?
        }

        /// The selected day, formatted.
        struct DayCard: Equatable {
            /// "Tue 28 Oct", "Today"
            let title: String
            /// "145"
            let carbs: String
            /// today: "so far"
            let soFar: Bool
            /// "4 entries"; nil without one ("No carb entries")
            let entryCount: String?
            let entries: [Entry]
            /// "15 g", when fat or protein are logged (D6)
            let carbEquivalents: String?
        }

        /// A row of the selected hour.
        struct HourRow: Equatable, Identifiable {
            let id: Int
            let name: String
            let value: String
        }

        /// A clock hour, formatted: the stepper's title and subtitle, and its rows.
        struct HourReadout: Equatable {
            /// "12:00–13:00"
            let time: String
            /// "14 days": the days averaged
            let subtitle: String
            /// carbs, entries, per entry, share of carbs
            let rows: [HourRow]
        }

        /// A row of "Most carbs": tapping it selects its hour.
        struct TopHour: Equatable, Identifiable {
            let hour: Int
            /// "12:00–13:00"
            let time: String
            /// "entries on 11 of 14 days · 41 g each"
            let subtitle: String
            /// "28%"
            let percent: String

            var id: Int { hour }
        }

        /// the period computed (Today is 7 d)
        let period: StatsPeriod
        /// the period shown: Today, or `period`
        let shown: StatsPeriod
        /// the Today period's view (`shown` Today); nil for 7–90 d
        let today: Today?
        /// "17 Oct – 30 Oct"
        let dateRange: String
        /// "Days with entries 5 of 6": the count the limited note leaves out (the complete days)
        let daysWithEntries: String
        /// why the headline is provisional (`Stat.Meals.limitedNote`), marked after it; nil when it isn't
        let limitedNote: String?
        /// "145", "–" without a complete day with entries
        let carbs: String
        /// entries only today (none on a complete day): "–" and "No entries on a complete day yet"
        let needsCompleteDay: Bool
        /// entries, per entry, when fat or protein are logged (D6) fat, protein and carb equivalents, and when nutrient
        /// data is logged the fiber
        let tiles: [Tile]
        /// any entry of the last 90 days has fat or protein (D6)
        let logsFatOrProtein: Bool
        let dayPlot: StatsDayBars.Plot
        let dayLegend: [StatsChartLegend.Item]
        /// oldest -> newest, the last one today
        let days: [DayMeals]
        /// by day
        let labels: [StatsDayLabel]
        let hourPlot: StatsHourBars.Plot
        let hourLegend: [StatsChartLegend.Item]
        /// by hour, from 00:00
        let hourReadouts: [HourReadout]
        /// up to 3, the most first
        let topHours: [TopHour]
        /// the Fiber tile, the way to the Nutrients screen and that screen's
        let nutrients: Nutrients

        /// - Parameter references: the Nutrients screen's reference intakes; nil without the sex and the birth date
        @MainActor init(_ result: MealsResult, references: NutrientReferences? = nil) {
            typealias Format = StatsFormatting
            let summary = result.meals.summary
            let logs = summary.logsFatOrProtein

            period = result.period
            shown = result.shown
            today = result.shown == .today ? Today(result) : nil
            days = result.meals.days
            labels = result.labels
            logsFatOrProtein = logs
            dateRange = Format.dateRange(summary.window, period: result.period)
            daysWithEntries = String(
                format: NSLocalizedString(
                    "Days with entries %@",
                    comment: "Statistics Meals: the complete days with carb entries, \"5 of 6\""
                ),
                Format.days(summary.daysWithEntries, of: summary.completeDays)
            )
            needsCompleteDay = summary.carbsPerDay == nil
            limitedNote = Self.limitedNote(summary)
            carbs = summary.carbsPerDay.map { StatsAmount.number($0, digits: 0) } ?? "–"
            let nutrients = Nutrients(result, dateRange: dateRange, references: references)
            self.nutrients = nutrients
            tiles = Self.tiles(summary, fiber: nutrients.fiberTile)

            // day by day
            let dayChart = Self.dayChart(result.meals.days, labels: result.labels, summary: summary, logsFatOrProtein: logs)
            dayPlot = dayChart.plot
            dayLegend = dayChart.legend

            // by time of day
            let hours = result.meals.hours
            let averagedDays = summary.daysWithEntries
            let hourChart = Self.hourChart(hours)
            hourPlot = hourChart.plot
            hourLegend = hourChart.legend
            hourReadouts = hours.map { Self.readout($0, days: averagedDays) }
            topHours = Self.topHours(result.meals.topHours, averagedDays: averagedDays)
        }

        // MARK: - The init's parts

        /// The day chart: the carbs (and the carb equivalents) by day, the carbs per day dashed.
        @MainActor private static func dayChart(
            _ days: [DayMeals],
            labels: [StatsDayLabel],
            summary: MealSummary,
            logsFatOrProtein: Bool
        ) -> (plot: StatsDayBars.Plot, legend: [StatsChartLegend.Item]) {
            let parts = Part.allCases
            let dayValues = days.map { Self.dayValues($0, logsFatOrProtein: logsFatOrProtein) }
            let dayLevels = StatsBarAxis.levels(
                maximum: Swift.max(dayValues.map { $0.reduce(0, +) }.max() ?? 0, summary.carbsPerDay ?? 0),
                unit: Self.dayAxisUnit,
                divisions: 3
            )
            let plot = StatsDayBars.Plot(
                days: days.map(\.day),
                labels: labels,
                values: dayValues,
                styles: parts.map(\.style),
                marked: [],
                levels: dayLevels,
                levelLabels: dayLevels.map { $0 == 0 ? StatsAmount.grams(0) : StatsAmount.number($0, digits: 0) },
                average: summary.carbsPerDay
            )
            var dayLegend = [StatsChartLegend.Item(id: 0, key: .swatch(Part.carbs.style), title: Part.carbs.name)]
            if logsFatOrProtein {
                dayLegend.append(StatsChartLegend.Item(
                    id: 1,
                    key: .swatch(Part.carbEquivalents.style),
                    title: Part.carbEquivalents.name
                ))
            }
            if let perDay = summary.carbsPerDay {
                dayLegend.append(StatsChartLegend.Item(
                    id: 10,
                    key: .dashed,
                    title: String(
                        format: NSLocalizedString("Average %@ g", comment: "Statistics Meals chart legend: the carbs per day"),
                        StatsAmount.number(perDay, digits: 0)
                    )
                ))
            }
            return (plot, dayLegend)
        }

        /// By time of day: the carbs per day by the hour of entry.
        @MainActor private static func hourChart(
            _ hours: [HourMeals]
        ) -> (plot: StatsHourBars.Plot, legend: [StatsChartLegend.Item]) {
            let hourLevels = StatsBarAxis.levels(maximum: hours.map(\.carbsPerDay).max() ?? 0, unit: 10, divisions: 2)
            let plot = StatsHourBars.Plot(
                parts: StatsHourBars.Plot.stacked(hours.map { [$0.carbsPerDay] }, styles: [Part.carbs.style]),
                yDomain: 0 ... (hourLevels.last ?? 1),
                levels: hourLevels,
                levelLabels: hourLevels.map { StatsAmount.grams($0, digits: 0) }
            )
            let legend = [
                StatsChartLegend.Item(
                    id: 0,
                    key: .swatch(Part.carbs.style),
                    title: NSLocalizedString(
                        "Carbs per day, by entry time",
                        comment: "Statistics Meals by time of day: the legend"
                    )
                )
            ]
            return (plot, legend)
        }

        /// The hours with the most carbs.
        @MainActor private static func topHours(_ topHours: [HourMeals], averagedDays: Int) -> [TopHour] {
            typealias Format = StatsFormatting
            return topHours.map { hour in
                TopHour(
                    hour: hour.hour,
                    time: AGP.clockInterval(from: hour.hour * 60, to: (hour.hour + 1) * 60),
                    subtitle: [
                        Self.entriesOn(hour.daysWithEntries, of: averagedDays),
                        String(
                            format: NSLocalizedString("%@ each", comment: "Statistics Meals, most carbs: the carbs per entry"),
                            hour.perEntry.map { StatsAmount.grams($0, digits: 0) } ?? "–"
                        )
                    ].joined(separator: " · "),
                    percent: Format.percent(fraction: hour.share)
                )
            }
        }

        // MARK: - The selected day

        @MainActor func card(at index: Int) -> DayCard {
            let day = days[index]
            let title = day.isToday ? NSLocalizedString("Today", comment: "") : labels[index].title
            let entries = Self.entries(day, logsFatOrProtein: logsFatOrProtein)
            return DayCard(
                title: title,
                carbs: StatsAmount.number(day.carbs, digits: 0 ... 1),
                soFar: day.isToday,
                entryCount: day.hasEntries ? Self.entryCount(day.entries.count) : nil,
                entries: entries,
                carbEquivalents: logsFatOrProtein ? StatsAmount.grams(day.carbEquivalents, digits: 0) : nil
            )
        }

        /// A day's entries: the time, the carbs, and the fat and protein for someone who logs them (D6) when the entry
        /// has either.
        @MainActor static func entries(_ day: DayMeals, logsFatOrProtein: Bool) -> [Entry] {
            day.entries.enumerated().map { offset, entry in
                Entry(
                    id: offset,
                    time: entry.actualDate.formatted(date: .omitted, time: .shortened),
                    carbs: StatsAmount.grams(entry.carbs),
                    detail: logsFatOrProtein && (entry.fat > 0 || entry.protein > 0)
                        ? String(
                            format: NSLocalizedString(
                                "fat %1$@ · protein %2$@",
                                comment: "Statistics Meals day: an entry's fat and protein, with their unit"
                            ),
                            StatsAmount.grams(entry.fat),
                            StatsAmount.grams(entry.protein)
                        )
                        : nil
                )
            }
        }

        // MARK: - Rules (pure)

        /// The day chart's y axis: whole multiples of 60 g (at least one), gridlines in thirds.
        static let dayAxisUnit = 60.0

        /// The carbs and, when fat or protein are logged (D6), the carb equivalents above them.
        static func dayValues(_ day: DayMeals, logsFatOrProtein: Bool) -> [Double] {
            [day.carbs, logsFatOrProtein ? day.carbEquivalents : 0]
        }

        /// The carbs note, without counts (the header says "Days with entries n of N"): when not every complete day has
        /// entries, and there is an average to mark.
        static func limitedNote(_ summary: MealSummary) -> String? {
            guard summary.isLimited, summary.carbsPerDay != nil else { return nil }
            return NSLocalizedString(
                "Carbs weren't logged on every complete day of this period, so the per-day numbers may not represent it.",
                comment: "Statistics limited data: not every complete day has carb entries"
            )
        }

        /// Entries and per entry; fat, protein and carb equivalents only for someone who logs fat or protein (D6), "0 g"
        /// then for a period without; then `fiber` (`Nutrients.fiberTile`: for someone who logs nutrient data).
        static func tiles(_ summary: MealSummary, fiber: Tile? = nil) -> [Tile] {
            let perDay = NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count")
            let gramsPerDay = NSLocalizedString("g per day", comment: "Statistics Meals: the unit of a daily amount")
            let grams = NSLocalizedString("g", comment: "Statistics Meals: grams")
            var tiles = [
                Tile(
                    id: 0,
                    title: NSLocalizedString("Entries", comment: "Statistics Meals: the carb entries"),
                    value: summary.entriesPerDay.map { StatsAmount.number($0, digits: 1) } ?? "–",
                    unit: perDay
                ),
                Tile(
                    id: 1,
                    title: NSLocalizedString("Per entry", comment: "Statistics Meals: the carbs per entry"),
                    value: summary.perEntry.map { StatsAmount.number($0, digits: 0) } ?? "–",
                    unit: grams
                )
            ]
            if summary.logsFatOrProtein {
                tiles += [
                    Tile(
                        id: 2,
                        title: NSLocalizedString("Fat", comment: ""),
                        value: summary.fatPerDay.map { StatsAmount.number($0, digits: 0) } ?? "–",
                        unit: gramsPerDay
                    ),
                    Tile(
                        id: 3,
                        title: NSLocalizedString("Protein", comment: ""),
                        value: summary.proteinPerDay.map { StatsAmount.number($0, digits: 0) } ?? "–",
                        unit: gramsPerDay
                    ),
                    Tile(
                        id: 4,
                        title: Part.carbEquivalents.name,
                        value: summary.carbEquivalentsPerDay.map { StatsAmount.number($0, digits: 0) } ?? "–",
                        unit: gramsPerDay
                    )
                ]
            }
            if let fiber {
                tiles.append(fiber)
            }
            return tiles
        }

        // MARK: - Formatting

        /// "1 entry", "4 entries"
        static func entryCount(_ count: Int) -> String {
            count == 1
                ? NSLocalizedString("1 entry", comment: "Statistics Meals: the entries of a day")
                : String(format: NSLocalizedString("%d entries", comment: "Statistics Meals: the entries of a day"), count)
        }

        /// No complete day with entries (only today has some): the headline's note.
        static var noCompleteDay: String {
            NSLocalizedString(
                "No entries on a complete day yet",
                comment: "Statistics Meals: only today has carb entries, no complete day to average"
            )
        }

        /// "entries on 11 of 14 days", "entries on 1 of 1 day"
        static func entriesOn(_ days: Int, of total: Int) -> String {
            total == 1
                ? String(
                    format: NSLocalizedString(
                        "entries on %d of 1 day",
                        comment: "Statistics Meals: the days with an entry in that hour, of one day averaged"
                    ),
                    days
                )
                : String(
                    format: NSLocalizedString(
                        "entries on %1$d of %2$d days",
                        comment: "Statistics Meals: the days with an entry in that hour, the days averaged"
                    ),
                    days,
                    total
                )
        }

        /// The selected hour's subtitle: the days averaged, "1 day", or without one `noCompleteDay`.
        static func hourDays(_ days: Int) -> String {
            switch days {
            case 0: return noCompleteDay
            case 1: return NSLocalizedString("1 day", comment: "Statistics Meals by time of day: one day averaged")
            default: return String(format: NSLocalizedString("%d days", comment: "Statistics AGP, the days of the period"), days)
            }
        }

        @MainActor private static func readout(_ hour: HourMeals, days: Int) -> HourReadout {
            let time = AGP.clockInterval(from: hour.hour * 60, to: (hour.hour + 1) * 60)
            let carbs = hour.carbs > 0
                ? String(
                    format: NSLocalizedString("%@ g per day", comment: "Statistics Meals: the carbs per day"),
                    StatsAmount.number(hour.carbsPerDay, digits: 0)
                )
                : StatsAmount.grams(0)
            // without a day averaged there is nothing to count
            let entries: String
            switch days {
            case 0:
                entries = "–"
            case 1:
                entries = String(
                    format: NSLocalizedString(
                        "on %d of 1 day",
                        comment: "Statistics Meals by time of day: the days with an entry in that hour, of one day averaged"
                    ),
                    hour.daysWithEntries
                )
            default:
                entries = String(
                    format: NSLocalizedString(
                        "on %1$d of %2$d days",
                        comment: "Statistics Meals by time of day: the days with an entry in that hour, the days averaged"
                    ),
                    hour.daysWithEntries,
                    days
                )
            }
            return HourReadout(
                time: time,
                subtitle: hourDays(days),
                rows: [
                    HourRow(id: 0, name: Part.carbs.name, value: carbs),
                    HourRow(
                        id: 1,
                        name: NSLocalizedString("Entries", comment: "Statistics Meals: the carb entries"),
                        value: entries
                    ),
                    HourRow(
                        id: 2,
                        name: NSLocalizedString("Per entry", comment: "Statistics Meals: the carbs per entry"),
                        value: hour.perEntry.map { StatsAmount.grams($0, digits: 0) } ?? "–"
                    ),
                    HourRow(
                        id: 3,
                        name: NSLocalizedString("Share of carbs", comment: "Statistics Meals by time of day: the hour's share"),
                        value: StatsFormatting.percent(fraction: hour.share)
                    )
                ]
            )
        }
    }
}

struct MealsView: View {
    let meals: Stat.Meals
    let daySelection: DailySelection
    let hourSelection: HourSelection
    /// the Nutrients screen, pushed
    let openNutrients: () -> Void
    /// "Show Today": the Today period
    let showToday: () -> Void

    var body: some View {
        if let today = meals.today {
            MealsTodayView(today: today, nutrients: meals.nutrients, openNutrients: openNutrients)
        } else {
            VStack(spacing: 16) {
                StatsCard { MealsCarbsCard(meals: meals, openNutrients: openNutrients) }
                MealsDays(meals: meals, selection: daySelection, showToday: showToday)
                StatsCard { hourChart }
                StatsCard { MealsHourReadout(readouts: meals.hourReadouts, selection: hourSelection) }
                if meals.topHours.isNotEmpty {
                    StatsCard { topHours }
                }
            }
        }
    }

    // MARK: - By time of day

    @ViewBuilder private var hourChart: some View {
        StatsCardHeader(title: "By time of day", detail: meals.dateRange)
        StatsHourBarsChart(plot: meals.hourPlot, selection: hourSelection)
        StatsChartLegend(items: meals.hourLegend)
    }

    // MARK: - Most carbs

    @ViewBuilder private var topHours: some View {
        Text("Most carbs")
            .statsSectionTitle()
        VStack(spacing: 0) {
            StatsDividedRows(meals.topHours) { hour in
                Button {
                    hourSelection.select(hour.hour)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hour.time)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Text(hour.subtitle)
                                .statsFootnote()
                                .monospacedDigit()
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(hour.percent)
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
    }
}

// MARK: - Carbs

private struct MealsCarbsCard: View {
    let meals: Stat.Meals
    let openNutrients: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatsCardHeader(title: "Carbs", range: meals.dateRange)
            Text(meals.daysWithEntries)
                .statsFootnote()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }

        VStack(alignment: .leading, spacing: 2) {
            StatsHeadlineNumber(
                value: meals.carbs,
                unit: NSLocalizedString("g", comment: "Statistics Meals: grams"),
                caption: NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count"),
                limitedNote: meals.limitedNote
            )
            if meals.needsCompleteDay {
                Text(Stat.Meals.noCompleteDay)
                    .statsFootnote()
            }
        }

        let tiles = meals.tiles
        // two columns, the fat/protein ones three; two at the larger text sizes
        StatsTileGrid(tiles, columns: StatTile.columns(dynamicTypeSize, regular: tiles.count > 2 ? 3 : 2))

        // the way to the Nutrients screen, with the Fiber tile (`Nutrients.logsNutrients`)
        if meals.nutrients.logsNutrients {
            MealsNutrientsRow(subtitle: meals.nutrients.daysWithData, open: openNutrients)
        }
    }
}

/// "Vitamins and minerals": the way to the Nutrients screen, under the Carbs card's numbers.
private struct MealsNutrientsRow: View {
    /// "Nutrient data on 9 of 13 days", Today "Nutrient data on 2 of 3 entries"
    let subtitle: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vitamins and minerals")
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .statsFootnote()
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day by day

/// The day chart and the selected day's card: re-rendered when the day picked changes, the rest of the tab isn't.
private struct MealsDays: View {
    let meals: Stat.Meals
    let selection: DailySelection
    let showToday: () -> Void

    var body: some View {
        let index = selection.index(in: meals.dayPlot.dayIntervals)
        let card = index.map { meals.card(at: $0) }
        StatsCard {
            StatsCardHeader(title: "Day by day", detail: meals.dateRange)
            if let index {
                StatsDayBarsChart(plot: meals.dayPlot, selected: index, selection: selection)
            }
            StatsChartLegend(items: meals.dayLegend)
        }
        if let index, let card {
            StatsCard { dayCard(card, index: index) }
        }
    }

    @ViewBuilder private func dayCard(_ card: Stat.Meals.DayCard, index: Int) -> some View {
        let days = meals.dayPlot.dayIntervals
        StatsStepper(title: card.title, index: index, count: days.count) { selection.pick($0, in: days) }

        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(card.carbs)
                .font(.title.bold())
                .monospacedDigit()
            Text("g")
                .font(.headline)
            if card.soFar {
                Text("so far")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let count = card.entryCount {
                Text(count)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        MealsEntryList(entries: card.entries)

        if let equivalents = card.carbEquivalents {
            StatsValueRow(
                key: .swatch(Stat.Meals.Part.carbEquivalents.style),
                name: NSLocalizedString("Carb equiv.", comment: "Statistics Meals day: the carb equivalents, short"),
                value: equivalents
            )
        }

        // today has the Today period's view
        if meals.days[index].isToday {
            StatsShowTodayButton(action: showToday)
        }
    }
}

/// A day's entries: the time, the carbs, the fat and protein; "No carb entries" without one.
private struct MealsEntryList: View {
    let entries: [Stat.Meals.Entry]

    var body: some View {
        if entries.isEmpty {
            Text("No carb entries")
                .statsEmptyNote(minHeight: 60)
        } else {
            VStack(spacing: 0) {
                StatsDividedRows(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.time)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Text(entry.carbs)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .fixedSize()
                        if let detail = entry.detail {
                            Text(detail)
                                .statsFootnote()
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(minHeight: 40)
                }
            }
        }
    }
}

// MARK: - The selected hour

/// The stepper through the hours and the selected hour's numbers: the alternative to picking on the chart.
private struct MealsHourReadout: View {
    let readouts: [Stat.Meals.HourReadout]
    let selection: HourSelection

    var body: some View {
        if readouts.indices.contains(selection.hour) {
            let readout = readouts[selection.hour]
            VStack(alignment: .leading, spacing: 4) {
                StatsStepper(hourTitle: readout.time, subtitle: readout.subtitle, selection: selection)
                VStack(spacing: 0) {
                    StatsDividedRows(readout.rows) { row in
                        StatsValueRow(key: .none, name: row.name, value: row.value)
                    }
                }
            }
        }
    }
}

// MARK: - Today

extension Stat.Meals {
    /// The Today period: today's entries so far, as of the read (`MealsResult.asOf`). No usual by now: carbs are
    /// compared with nothing here.
    struct Today: Equatable {
        /// "Today, 00:00–14:35"
        let dateRange: String
        /// "95"
        let carbs: String
        /// "3 entries", "No entries"
        let entryCount: String
        /// fat, protein, energy and the carb equivalents, for someone who logs fat or protein (D6); none otherwise
        let tiles: [Tile]
        /// the day card's entries (time, carbs, fat · protein). No bolus column, unlike the mock: nothing links a meal
        /// to its bolus (the boluses are on the Insulin tab's Today)
        let entries: [Entry]

        @MainActor init(_ result: Stat.MealsResult) {
            typealias Meals = Stat.Meals
            let calendar = Calendar.current
            let day = result.meals.days.last(where: \.isToday)
            let logs = result.meals.summary.logsFatOrProtein
            let wholeDay = day?.day ?? calendar.dateInterval(of: .day, for: result.asOf)
                ?? DateInterval(start: calendar.startOfDay(for: result.asOf), duration: .hours(24))
            dateRange = StatsFormatting.dateRange(wholeDay, period: .today, now: result.asOf)
            let carbs = day?.carbs ?? 0
            self.carbs = StatsAmount.number(carbs, digits: 0 ... 1)
            let count = day?.entries.count ?? 0
            entryCount = count == 0
                ? NSLocalizedString("No entries", comment: "Statistics Meals Today: no carb entry so far")
                : Meals.entryCount(count)
            tiles = logs ? Self.tiles(day) : []
            entries = day.map { Meals.entries($0, logsFatOrProtein: logs) } ?? []
        }

        /// Fat, protein, energy (4 kcal a gram of carbs and protein, 9 of fat) and the carb equivalents of today.
        static func tiles(_ day: DayMeals?) -> [Tile] {
            let grams = NSLocalizedString("g", comment: "Statistics Meals: grams")
            let carbs = day?.carbs ?? 0
            let fat = day?.fat ?? 0
            let protein = day?.protein ?? 0
            return [
                Tile(id: 0, title: NSLocalizedString("Fat", comment: ""), value: StatsAmount.number(fat, digits: 0), unit: grams),
                Tile(
                    id: 1,
                    title: NSLocalizedString("Protein", comment: ""),
                    value: StatsAmount.number(protein, digits: 0),
                    unit: grams
                ),
                Tile(
                    id: 2,
                    title: NSLocalizedString("Energy", comment: ""),
                    value: StatsAmount.number(energy(carbs: carbs, fat: fat, protein: protein), digits: 0),
                    unit: NSLocalizedString("kcal", comment: "")
                ),
                Tile(
                    id: 3,
                    title: NSLocalizedString("Carb equiv.", comment: "Statistics Meals day: the carb equivalents, short"),
                    value: StatsAmount.number(day?.carbEquivalents ?? 0, digits: 0),
                    unit: grams
                )
            ]
        }

        /// kcal: 4 a gram of carbs and of protein, 9 of fat
        static func energy(carbs: Double, fat: Double, protein: Double) -> Double {
            4 * (Swift.max(carbs, 0) + Swift.max(protein, 0)) + 9 * Swift.max(fat, 0)
        }
    }
}

/// The Meals tab on Today: the carbs so far with the fat, protein, energy and equivalents, the way to today's vitamins
/// and minerals, and the entries.
private struct MealsTodayView: View {
    let today: Stat.Meals.Today
    let nutrients: Stat.Nutrients
    let openNutrients: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 16) {
            StatsCard { carbsCard }
            StatsCard {
                Text("Entries")
                    .statsSectionTitle()
                MealsEntryList(entries: today.entries)
            }
        }
    }

    @ViewBuilder private var carbsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatsCardHeader(title: "Carbs so far", range: today.dateRange)
            Text(today.entryCount)
                .statsFootnote()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }

        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(today.carbs)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("g")
                .font(.title3.weight(.semibold))
        }

        if today.tiles.isNotEmpty {
            // four across, two at the larger text sizes
            StatsTileGrid(today.tiles, columns: StatTile.columns(dynamicTypeSize, regular: 4))
        }

        // today's vitamins and minerals (the Nutrients screen on Today), for someone who logs nutrient data
        if nutrients.logsNutrients {
            MealsNutrientsRow(subtitle: nutrients.today?.coverage ?? nutrients.daysWithData, open: openNutrients)
        }
    }
}
