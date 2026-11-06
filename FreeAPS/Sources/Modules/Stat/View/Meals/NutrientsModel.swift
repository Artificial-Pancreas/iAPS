import SwiftUI

extension Stat {
    /// The Meals tab's fiber, vitamins and minerals, formatted for display: the Carbs card's Fiber tile and its way to the
    /// Nutrients screen, that screen's rows, and a nutrient's chart and selected day when one is shown (`detail(_:)`,
    /// `card(at:for:)`). The days and the averages come ready from the provider (`MealsResult.nutrients`); the reference
    /// intakes from the settings (`NutrientReferences`).
    struct Nutrients: Equatable {
        /// A row's bar: 0–150% of the reference intake, 100% at the tick.
        struct Bar: Equatable {
            /// where 100% sits, of the track
            static let tick = 1 / 1.5

            /// of the track: the amount, or for salt above its limit up to the tick
            let filled: Double
            /// of the track: salt's part above its limit, from the tick (orange)
            let over: Double
        }

        /// A nutrient per day: its name, amount and share of the reference intake.
        struct Row: Equatable, Identifiable {
            let nutrient: StatsNutrient
            let name: String
            /// its other name ("Thiamine"); salt above its limit: "Above the 5 g limit"
            let subtitle: String?
            /// "7.6 g"
            let amount: String
            /// "152%"; nil without references (salt has its limit always)
            let percent: String?
            /// nil without references (salt has its limit always)
            let bar: Bar?
            /// salt above its limit: the percent, the subtitle and the bar's excess in orange
            let isOverLimit: Bool

            var id: StatsNutrient { nutrient }
        }

        /// Rows under a title: one untitled section with references (by the share of the reference); without, fiber,
        /// then "Vitamins" and "Minerals" in the app's order.
        struct NutrientSection: Equatable, Identifiable {
            let id: Int
            let title: String?
            let rows: [Row]
        }

        /// One nutrient's screen: its average, the reference, the day chart.
        struct Detail: Equatable {
            let nutrient: StatsNutrient
            let name: String
            let unit: String
            /// "1.2"; nil without a counted day
            let average: String?
            /// "26% of the 25 g reference intake", "152% of the 5 g limit"; nil without a reference or an average
            let reference: String?
            /// salt's average above its limit
            let isOverLimit: Bool
            /// the counted days solid, the partly logged days and today outlined, the average dashed, the reference solid
            let plot: StatsDayBars.Plot
            let legend: [StatsChartLegend.Item]
        }

        /// An entry of the selected day, with the nutrient's amount in it.
        struct Entry: Equatable, Identifiable {
            let id: Int
            /// "08:12"
            let time: String
            /// "45 g"; nil for a nutrient-only entry (a supplement): no carbs figure, its amount alone
            let carbs: String?
            /// "1.2 g", "not listed", "no nutrient data"
            let value: String
            /// the entry lists the nutrient
            let isListed: Bool
        }

        /// One nutrient on the selected day.
        struct DayCard: Equatable {
            /// "Tue 28 Oct", "Today"
            let title: String
            /// "1.2", "–" without nutrient data
            let amount: String
            let unit: String
            /// today: "so far"
            let soFar: Bool
            /// "26%"; nil without a reference or nutrient data
            let percent: String?
            /// salt above its limit
            let isOverLimit: Bool
            /// "In the average · nutrient data on 3 of 4 entries", "No carb entries", …
            let status: String
            let entries: [Entry]
        }

        /// Today's nutrients so far against the daily reference intakes (the Today period).
        struct Today: Equatable {
            /// "Today, 00:00–14:35"
            let dateRange: String
            /// "Nutrient data on 2 of 3 entries"
            let coverage: String
            /// the period's rules (by the share of the reference, or grouped without references); empty without
            /// nutrient data today
            let sections: [NutrientSection]
            /// without nutrient data today: "No nutrient data so far today", "No carb entries so far today"
            let emptyTitle: String?
            /// what the percentages compare with (`basis`); nil without rows
            let basis: String?
            /// today's index in `days`
            let index: Int
        }

        /// A nutrient's screen on Today: today's amount so far against the reference, today's coverage and entries.
        struct TodayDetail: Equatable {
            let name: String
            /// "26% of the 25 g reference intake", "152% of the 5 g limit"; nil without a reference or nutrient data
            let reference: String?
            /// Today's coverage, as the Nutrients screen's: "Nutrient data on 2 of 3 entries"; without an entry today
            /// "No carb entries so far today". Not the day card's status: that one is the period chart's ("… averaged
            /// from midnight")
            let coverage: String
            /// today's (amount, percent, entries)
            let card: DayCard
        }

        /// "17 Oct – 30 Oct"
        let dateRange: String
        /// the Today period's (`MealsResult.shown` Today); nil for 7–90 d
        let today: Today?
        /// "Days with nutrient data 9 of 13"
        let coverage: String
        /// why the averages are provisional (too few days counted), marked after them; nil when they aren't
        let limitedNote: String?
        /// the sex and the birth date are set: every nutrient against its reference (without, salt alone)
        let hasReferences: Bool
        /// empty without a counted day
        let sections: [NutrientSection]
        /// without a counted day: "No day with enough nutrient data yet", "No nutrient data in this period"
        let emptyTitle: String?
        /// "EFSA reference intakes for a woman, 41 (Settings › …). Salt: …", without references salt's limit alone; nil
        /// without rows
        let basis: String?
        /// the legend's tick: "Reference intake = 100%", without references "Salt limit = 100%"
        let legendTick: String
        /// an entry of the last 90 days has nutrient data: the Carbs card's Fiber tile and the way here
        let logsNutrients: Bool
        /// "Nutrient data on 9 of 13 days": the way here
        let daysWithData: String
        /// the Carbs card's Fiber tile, when nutrient data is logged
        let fiberTile: Meals.Tile?
        /// oldest -> newest, the last one today; with their entries, the nutrient-only ones among them
        let days: [DayNutrients]
        /// by day
        let labels: [StatsDayLabel]
        /// by nutrient, in its unit, per counted day
        let perDay: [StatsNutrient: Double]
        let references: NutrientReferences?

        @MainActor init(_ result: MealsResult, dateRange: String, references: NutrientReferences?) {
            let summary = result.nutrients.summary
            self.dateRange = dateRange
            self.references = references
            days = result.nutrients.days
            labels = result.labels
            perDay = summary.perDay
            hasReferences = references != nil
            logsNutrients = summary.logsNutrients
            legendTick = references == nil
                ? NSLocalizedString("Salt limit = 100%", comment: "Statistics Nutrients legend: the bar's tick, salt's alone")
                : NSLocalizedString("Reference intake = 100%", comment: "Statistics Nutrients legend: the bar's tick")
            coverage = String(
                format: NSLocalizedString(
                    "Days with nutrient data %@",
                    comment: "Statistics Nutrients: the complete days counted, \"9 of 13\""
                ),
                StatsFormatting.days(summary.countedDays, of: summary.completeDays)
            )
            let limitedNote = summary.isLimited ? Self.limitedDataNote : nil
            self.limitedNote = limitedNote
            daysWithData = String(
                format: NSLocalizedString(
                    "Nutrient data on %1$d of %2$d days",
                    comment: "Statistics Meals: the way to the Nutrients screen, the complete days counted of the complete days"
                ),
                summary.countedDays,
                summary.completeDays
            )
            fiberTile = summary.logsNutrients
                ? Meals.Tile(
                    id: 5,
                    title: Self.name(.fiber),
                    value: summary.perDay[.fiber].map { StatsAmount.number($0, digits: 0) } ?? "–",
                    unit: NSLocalizedString("g per day", comment: "Statistics Meals: the unit of a daily amount"),
                    limitedNote: limitedNote
                )
                : nil
            today = result.shown == .today ? Self.makeToday(result, references: references) : nil

            guard summary.countedDays > 0 else {
                sections = []
                emptyTitle = summary.periodHasData ? Self.noCountedDay : NSLocalizedString(
                    "No nutrient data in this period",
                    comment: "Statistics Nutrients: no entry of the period has nutrient data"
                )
                basis = nil
                return
            }
            let rows = NutrientStatsEngine.rows(summary.perDay, references: references)
                .map { Self.row($0, references: references) }
            sections = references == nil ? Self.grouped(rows) : [NutrientSection(id: 0, title: nil, rows: rows)]
            emptyTitle = nil
            basis = Self.basis(references)
        }

        // MARK: - One nutrient

        @MainActor func detail(_ nutrient: StatsNutrient) -> Detail {
            let name = Self.name(nutrient)
            let unit = nutrient.unit
            let average = perDay[nutrient]
            let intake = NutrientStatsEngine.reference(of: nutrient, references: references)
            let referenceColor = nutrient.isLimit ? Color(.statsWarning) : Color(.secondaryLabel)
            let plot = Self.detailPlot(
                nutrient,
                days: days,
                labels: labels,
                average: average,
                intake: intake,
                referenceColor: referenceColor
            )
            let legend = Self.detailLegend(nutrient, name: name, average: average, intake: intake, referenceColor: referenceColor)

            let percent = average.flatMap { average in intake.map { average / $0 * 100 } }
            let reference = percent.map { Self.referenceLine(nutrient, percent: $0, intake: intake ?? 0) }

            return Detail(
                nutrient: nutrient,
                name: name,
                unit: unit,
                average: average.map(Self.number),
                reference: reference,
                isOverLimit: NutrientStatsEngine.isOverLimit(nutrient, percent: percent),
                plot: plot,
                legend: legend
            )
        }

        /// A nutrient's days: the counted ones solid, the others with data outlined, the average dashed, the reference
        /// (or the limit) as a rule.
        @MainActor private static func detailPlot(
            _ nutrient: StatsNutrient,
            days: [DayNutrients],
            labels: [StatsDayLabel],
            average: Double?,
            intake: Double?,
            referenceColor: Color
        ) -> StatsDayBars.Plot {
            let unit = nutrient.unit
            // counted days solid, the others with data outlined (today among them), the ones without none
            let values = days.map { day -> [Double] in
                let amount = day.amounts[nutrient] ?? 0
                return day.isCounted ? [amount, 0] : [0, day.hasData ? amount : 0]
            }
            let highest = values.map { $0.reduce(0, +) }.max() ?? 0
            let levels = NutrientStatsEngine.axisLevels(maximum: Swift.max(highest, intake ?? 0, average ?? 0))
            return StatsDayBars.Plot(
                days: days.map(\.day),
                labels: labels,
                values: values,
                styles: [Self.countedStyle, Self.partStyle],
                marked: [],
                levels: levels,
                levelLabels: levels.map { $0 == 0 ? Self.amount(0, unit: unit) : StatsAmount.number($0, digits: 0 ... 2) },
                average: average,
                reference: intake.map { StatsDayBars.Rule(value: $0, color: referenceColor) }
            )
        }

        /// The counted days, the others, the average, the reference (or the limit).
        @MainActor private static func detailLegend(
            _ nutrient: StatsNutrient,
            name: String,
            average: Double?,
            intake: Double?,
            referenceColor: Color
        ) -> [StatsChartLegend.Item] {
            let unit = nutrient.unit
            var legend = [
                StatsChartLegend.Item(
                    id: 0,
                    key: .swatch(Self.countedStyle),
                    title: String(
                        format: NSLocalizedString(
                            "%@, days in the average",
                            comment: "Statistics Nutrients chart legend: the nutrient's bars of the counted days"
                        ),
                        name
                    )
                ),
                StatsChartLegend.Item(
                    id: 1,
                    key: .swatch(Self.partStyle),
                    title: NSLocalizedString("Not in the average", comment: "")
                )
            ]
            if let average {
                legend.append(StatsChartLegend.Item(
                    id: 10,
                    key: .dashed,
                    title: String(
                        format: NSLocalizedString("Average %@", comment: "Statistics Nutrients chart legend: the amount per day"),
                        Self.amount(average, unit: unit)
                    )
                ))
            }
            if let intake {
                legend.append(StatsChartLegend.Item(
                    id: 11,
                    key: .rule(referenceColor),
                    title: String(
                        format: nutrient.isLimit
                            ? NSLocalizedString("Limit %@", comment: "Statistics Nutrients chart legend: salt's limit per day")
                            : NSLocalizedString(
                                "Reference %@",
                                comment: "Statistics Nutrients chart legend: the reference intake per day"
                            ),
                        Self.referenceAmount(intake, unit: unit)
                    )
                ))
            }
            return legend
        }

        /// The selected day of a nutrient's screen: its amount (the entries with nutrient data), why it is or isn't in
        /// the average, and every entry with that nutrient's amount, "not listed" or "no nutrient data".
        @MainActor func card(at index: Int, for nutrient: StatsNutrient) -> DayCard {
            let day = days[index]
            let entries = day.points
            let title = day.isToday ? NSLocalizedString("Today", comment: "") : labels[index].title
            let unit = nutrient.unit
            let amount: Double? = day.hasData ? day.amounts[nutrient] ?? 0 : nil
            let intake = NutrientStatsEngine.reference(of: nutrient, references: references)
            let percent = amount.flatMap { amount in intake.map { amount / $0 * 100 } }

            let rows = entries.enumerated().map { offset, entry -> Entry in
                let listed = entry.hasNutrientData ? nutrient.amount(in: entry) : 0
                let value: String
                if !entry.hasNutrientData {
                    value = NSLocalizedString(
                        "no nutrient data",
                        comment: "Statistics Nutrients day: an entry without nutrient data"
                    )
                } else if listed > 0 {
                    value = Self.amount(listed, unit: unit)
                } else {
                    value = NSLocalizedString(
                        "not listed",
                        comment: "Statistics Nutrients day: an entry with nutrient data that doesn't list this nutrient"
                    )
                }
                return Entry(
                    id: offset,
                    time: entry.actualDate.formatted(date: .omitted, time: .shortened),
                    carbs: entry.isNutrientOnly ? nil : StatsAmount.grams(entry.carbs),
                    value: value,
                    isListed: listed > 0
                )
            }

            return DayCard(
                title: title,
                amount: amount.map(Self.number) ?? "–",
                unit: unit,
                soFar: day.isToday,
                percent: percent.map { StatsFormatting.percent(NutrientStatsEngine.shownPercent($0)) },
                isOverLimit: NutrientStatsEngine.isOverLimit(nutrient, percent: percent),
                status: Self.status(day),
                entries: rows
            )
        }

        // MARK: - Today

        /// Today so far: every nutrient of today's entries with nutrient data against its daily reference (salt
        /// against its limit), by the period's rules; nil without today among the days (not expected).
        @MainActor private static func makeToday(_ result: MealsResult, references: NutrientReferences?) -> Today? {
            let days = result.nutrients.days
            guard let index = days.lastIndex(where: \.isToday) else { return nil }
            let day = days[index]
            let dateRange = StatsFormatting.dateRange(day.day, period: .today, now: result.asOf)
            let coverage = String(
                format: NSLocalizedString(
                    "Nutrient data on %1$d of %2$@",
                    comment: "Statistics Nutrients Today: today's entries with nutrient data of its entries (\"3 entries\")"
                ),
                day.entriesWithData,
                Meals.entryCount(day.entries)
            )
            guard day.hasData else {
                return Today(
                    dateRange: dateRange,
                    coverage: coverage,
                    sections: [],
                    emptyTitle: day.entries == 0
                        ? NSLocalizedString(
                            "No carb entries so far today",
                            comment: "Statistics Nutrients Today: no entry yet"
                        )
                        : NSLocalizedString(
                            "No nutrient data so far today",
                            comment: "Statistics Nutrients Today: none of today's entries has nutrient data"
                        ),
                    basis: nil,
                    index: index
                )
            }
            let rows = NutrientStatsEngine.rows(day.amounts, references: references).map { row($0, references: references) }
            return Today(
                dateRange: dateRange,
                coverage: coverage,
                sections: references == nil ? grouped(rows) : [NutrientSection(id: 0, title: nil, rows: rows)],
                emptyTitle: nil,
                basis: basis(references),
                index: index
            )
        }

        /// A nutrient's screen on Today; nil on 7–90 d.
        @MainActor func todayDetail(_ nutrient: StatsNutrient) -> TodayDetail? {
            guard let today else { return nil }
            let day = days[today.index]
            let intake = NutrientStatsEngine.reference(of: nutrient, references: references)
            let amount: Double? = day.hasData ? day.amounts[nutrient] ?? 0 : nil
            let percent = amount.flatMap { amount in intake.map { amount / $0 * 100 } }
            return TodayDetail(
                name: Self.name(nutrient),
                reference: percent.map { Self.referenceLine(nutrient, percent: $0, intake: intake ?? 0) },
                coverage: day.entries == 0 ? today.emptyTitle ?? today.coverage : today.coverage,
                card: card(at: today.index, for: nutrient)
            )
        }

        // MARK: - Rules (pure)

        /// "26% of the 25 g reference intake", "152% of the 5 g limit"
        @MainActor static func referenceLine(_ nutrient: StatsNutrient, percent: Double, intake: Double) -> String {
            String(
                format: nutrient.isLimit
                    ? NSLocalizedString(
                        "%1$@ of the %2$@ limit",
                        comment: "Statistics Nutrients: salt per day as a share of its limit, \"152%\", \"5 g\""
                    )
                    : NSLocalizedString(
                        "%1$@ of the %2$@ reference intake",
                        comment: "Statistics Nutrients: the amount per day as a share of the reference intake, \"26%\", \"25 g\""
                    ),
                StatsFormatting.percent(NutrientStatsEngine.shownPercent(percent)),
                referenceAmount(intake, unit: nutrient.unit)
            )
        }

        /// The counted days' bars, solid.
        static let countedStyle = StatsBarStyle(fill: Color(.statsNutrient))
        /// The other days with nutrient data (partly logged, today): a light fill with the outline.
        static let partStyle = StatsBarStyle(fill: Color(.statsNutrient).opacity(0.14), stroke: Color(.statsNutrient))

        /// The averages' note, without counts (the header says "Days with nutrient data n of N").
        static var limitedDataNote: String {
            NSLocalizedString(
                "A day counts when foods with nutrient data make up at least 80% of its carbs. Not enough days of this period do, so the per-day numbers may not represent it.",
                comment: "Statistics limited data: too few days with nutrient data for most of their carbs"
            )
        }

        /// No counted day: the screen's note, and a nutrient's.
        static var noCountedDay: String {
            NSLocalizedString(
                "No day with enough nutrient data yet",
                comment: "Statistics Nutrients: no complete day whose foods with nutrient data make up 80% of its carbs"
            )
        }

        /// "Fiber", "Vitamin B1", "Salt"
        static func name(_ nutrient: StatsNutrient) -> String {
            guard case let .micro(micro) = nutrient else {
                return NSLocalizedString("Fiber", comment: "")
            }
            let comment = "Statistics Nutrients: a vitamin, its other name under it"
            switch micro {
            case .vitaminB1: return NSLocalizedString("Vitamin B1", comment: comment)
            case .vitaminB2: return NSLocalizedString("Vitamin B2", comment: comment)
            case .vitaminB3: return NSLocalizedString("Vitamin B3", comment: comment)
            case .vitaminB5: return NSLocalizedString("Vitamin B5", comment: comment)
            case .vitaminB7: return NSLocalizedString("Vitamin B7", comment: comment)
            case .vitaminB9: return NSLocalizedString("Vitamin B9", comment: comment)
            // the app's names, localized where they are shown elsewhere
            default: return NSLocalizedString(micro.displayName, comment: "")
            }
        }

        /// "Thiamine": the B vitamins' other names
        static func otherName(_ nutrient: StatsNutrient) -> String? {
            let comment = "Statistics Nutrients: a vitamin's other name"
            switch nutrient {
            case .micro(.vitaminB1): return NSLocalizedString("Thiamine", comment: comment)
            case .micro(.vitaminB2): return NSLocalizedString("Riboflavin", comment: comment)
            case .micro(.vitaminB3): return NSLocalizedString("Niacin", comment: comment)
            case .micro(.vitaminB5): return NSLocalizedString("Pantothenic acid", comment: comment)
            case .micro(.vitaminB7): return NSLocalizedString("Biotin", comment: comment)
            case .micro(.vitaminB9): return NSLocalizedString("Folate", comment: comment)
            default: return nil
            }
        }

        /// The amounts as the mock writes them: whole numbers from 10, one decimal from 1, two below; "< 0.01" for one
        /// that two decimals would show as 0 (copper's 0.004 mg).
        static func number(_ value: Double) -> String {
            // `StatsAmount` rounds half away from zero: 0.005 is "0.01"
            guard value <= 0 || value >= 0.005 else {
                return String(
                    format: NSLocalizedString(
                        "< %@",
                        comment: "Statistics Nutrients: an amount above 0 below the smallest one shown, \"0.01\""
                    ),
                    StatsAmount.number(0.01, digits: 2 ... 2)
                )
            }
            let digits = value >= 10 ? 0 : value >= 1 ? 1 : value > 0 ? 2 : 0
            return StatsAmount.number(value, digits: digits ... digits)
        }

        /// "7.6 g", "1,180 mg", "95 µg"
        static func amount(_ value: Double, unit: String) -> String {
            String(
                format: NSLocalizedString("%1$@ %2$@", comment: "Statistics Nutrients: an amount and its unit (g, mg, µg)"),
                number(value),
                unit
            )
        }

        /// A reference intake as the table has it: "5 g", "1.1 mg", "330 µg".
        static func referenceAmount(_ value: Double, unit: String) -> String {
            String(
                format: NSLocalizedString("%1$@ %2$@", comment: "Statistics Nutrients: an amount and its unit (g, mg, µg)"),
                StatsAmount.number(value, digits: 0 ... 1),
                unit
            )
        }

        /// A row's bar: the share of 150%, salt above its limit split at the tick.
        static func bar(percent: Double, isOverLimit: Bool) -> Bar {
            let filled = Swift.min(Swift.max(percent, 0), 150) / 150
            return isOverLimit ? Bar(filled: Bar.tick, over: filled - Bar.tick) : Bar(filled: filled, over: 0)
        }

        @MainActor static func row(_ row: NutrientRow, references: NutrientReferences?) -> Row {
            let name = Self.name(row.nutrient)
            let other = otherName(row.nutrient)
            let unit = row.nutrient.unit
            let amount = Self.amount(row.amount, unit: unit)
            let percent = row.percent.map { StatsFormatting.percent(NutrientStatsEngine.shownPercent($0)) }
            let subtitle = row.isOverLimit
                ? String(
                    format: NSLocalizedString(
                        "Above the %@ limit",
                        comment: "Statistics Nutrients: salt above its limit, \"5 g\""
                    ),
                    Self.referenceAmount(
                        NutrientStatsEngine.reference(of: row.nutrient, references: references) ?? 0,
                        unit: unit
                    )
                )
                : other

            return Row(
                nutrient: row.nutrient,
                name: name,
                subtitle: subtitle,
                amount: amount,
                percent: percent,
                bar: row.percent.map { bar(percent: $0, isOverLimit: row.isOverLimit) },
                isOverLimit: row.isOverLimit
            )
        }

        /// Without references: fiber, then the vitamins, then the minerals, each in the app's order.
        static func grouped(_ rows: [Row]) -> [NutrientSection] {
            [
                NutrientSection(id: 0, title: nil, rows: rows.filter { $0.nutrient.group == .fiber }),
                NutrientSection(
                    id: 1,
                    title: NSLocalizedString("Vitamins", comment: "Statistics Nutrients: a group of rows"),
                    rows: rows.filter { $0.nutrient.group == .vitamin }
                ),
                NutrientSection(
                    id: 2,
                    title: NSLocalizedString("Minerals", comment: "Statistics Nutrients: a group of rows"),
                    rows: rows.filter { $0.nutrient.group == .mineral }
                )
            ]
        }

        /// Where the sex and the birth date are set: the one place that names it (the basis line).
        static var demographicsLocation: String {
            NSLocalizedString(
                "Settings › About You",
                comment: "Statistics Nutrients: where the sex and the birth date are set"
            )
        }

        /// Without references: the button opening the Reference intakes sheet (`ReferenceIntakesSheet`), which sets them.
        static var noReferencesNote: String {
            NSLocalizedString(
                "Set sex and birth date for reference intakes",
                comment: "Statistics Nutrients: without the sex or the birth date, the button that sets them"
            )
        }

        /// "EFSA reference intakes for a woman, 41 (Settings › About You). Salt: the 5 g a day limit.";
        /// without references salt's limit alone.
        static func basis(_ references: NutrientReferences?) -> String {
            let comment = "Statistics Nutrients: what the percentages compare with, the age in years, where it is set"
            switch references?.person {
            case .woman:
                return String(
                    format: NSLocalizedString(
                        "EFSA reference intakes for a woman, %1$d (%2$@). Salt: the 5 g a day limit.",
                        comment: comment
                    ),
                    references?.age ?? 0,
                    demographicsLocation
                )
            case .man:
                return String(
                    format: NSLocalizedString(
                        "EFSA reference intakes for a man, %1$d (%2$@). Salt: the 5 g a day limit.",
                        comment: comment
                    ),
                    references?.age ?? 0,
                    demographicsLocation
                )
            case nil:
                return NSLocalizedString(
                    "Salt: the EFSA limit of 5 g a day.",
                    comment: "Statistics Nutrients: what salt's percentage compares with, without the sex or the birth date"
                )
            }
        }

        /// Why a day is or isn't in the average.
        static func status(_ day: DayNutrients) -> String {
            guard day.entries > 0 else {
                return NSLocalizedString("No carb entries", comment: "Statistics Meals day: no entry")
            }
            guard day.hasData else {
                return NSLocalizedString(
                    "No nutrient data on this day's entries",
                    comment: "Statistics Nutrients day: none of its entries has nutrient data"
                )
            }
            if day.isToday {
                return String(
                    format: NSLocalizedString(
                        "So far · nutrient data on %1$d of %2$@ · averaged from midnight",
                        comment: "Statistics Nutrients day: today, its entries with nutrient data of its entries (\"4 entries\")"
                    ),
                    day.entriesWithData,
                    Meals.entryCount(day.entries)
                )
            }
            if day.isCounted {
                return String(
                    format: NSLocalizedString(
                        "In the average · nutrient data on %1$d of %2$@",
                        comment: "Statistics Nutrients day: its entries with nutrient data of its entries (\"4 entries\")"
                    ),
                    day.entriesWithData,
                    Meals.entryCount(day.entries)
                )
            }
            guard day.carbs > 0 else {
                return NSLocalizedString(
                    "Not in the average · no carbs on this day",
                    comment: "Statistics Nutrients day: a supplement alone, or fat and protein only"
                )
            }
            return String(
                format: NSLocalizedString(
                    "Not in the average · foods with nutrient data are %@ of the carbs",
                    comment: "Statistics Nutrients day: below 80%, the share of its carbs with nutrient data (\"62%\")"
                ),
                "\(Self.shareWithData(day))%"
            )
        }

        /// A day not in the average: the share of its carbs with nutrient data in whole percent, rounded down (79.6% is
        /// "79%", not the 80% it would need).
        static func shareWithData(_ day: DayNutrients) -> Int {
            // a little room for the division's rounding: 29 of 100 g is 29%, not 28.999…
            Int((day.carbShareWithData * 100 + 1E-9).rounded(.down))
        }
    }
}
