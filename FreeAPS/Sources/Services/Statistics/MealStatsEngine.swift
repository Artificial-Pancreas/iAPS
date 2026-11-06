import Foundation

/// A `Meals` row as the statistics use it (g).
struct MealPoint: Sendable, Equatable {
    let id: String?
    let actualDate: Date
    let createdAt: Date?
    let carbs: Double
    let fat: Double
    let protein: Double
    let fiber: Double
    /// its `Micronutrient` rows, in the unit stored (`MicroNutrient.unit`), summed by nutrient
    let micronutrients: [MicroNutrient: Double]

    init(
        id: String?,
        actualDate: Date,
        createdAt: Date? = nil,
        carbs: Double,
        fat: Double = 0,
        protein: Double = 0,
        fiber: Double = 0,
        micronutrients: [MicroNutrient: Double] = [:]
    ) {
        self.id = id
        self.actualDate = actualDate
        self.createdAt = createdAt
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.fiber = fiber
        self.micronutrients = micronutrients
    }

    /// Fiber or a micronutrient row: a food from food search or a preset (zero amounts are never stored). A nutrient
    /// it doesn't list is 0 ("not listed").
    var hasNutrientData: Bool {
        fiber > 0 || micronutrients.isNotEmpty
    }

    /// Nutrient data without carbs, fat or protein (a supplement: a vitamin D preset): not a Meals entry
    /// (`MealStatsEngine.clean`), only the Nutrients screen's (`NutrientStatsEngine.nutrientOnly`).
    var isNutrientOnly: Bool {
        carbs <= 0 && fat <= 0 && protein <= 0 && hasNutrientData
    }
}

/// A calendar day of the Meals tab (`MealStatsEngine.period`). Today is "so far".
struct DayMeals: Sendable, Equatable {
    /// the whole calendar day (23, 24 or 25 h)
    let day: DateInterval
    let isToday: Bool
    /// the entries starting in it, oldest -> newest
    let entries: [MealPoint]
    /// g
    let carbs: Double
    let fat: Double
    let protein: Double
    /// g, from the fat and protein with the current factor (`MealStatsEngine.carbEquivalents`)
    let carbEquivalents: Double

    var hasEntries: Bool { entries.isNotEmpty }
    /// In the averages: a complete day (not today) with entries.
    var isAveraged: Bool { !isToday && hasEntries }
}

/// A clock hour of the By-time-of-day chart, by the local hour of the entries, over the averaged days.
struct HourMeals: Sendable, Equatable {
    let hour: Int
    /// g, Σ of the averaged days
    let carbs: Double
    /// g per day: Σ carbs / days with entries, so the 24 hours sum to the headline
    let carbsPerDay: Double
    let entries: Int
    /// "entries on {d} of {N} days": the averaged days with an entry in this hour
    let daysWithEntries: Int
    /// g per entry with carbs; nil without one
    let perEntry: Double?
    /// of the period's carbs, 0...1
    let share: Double
}

/// The Meals tab's headline numbers, over the complete days (today excluded) with entries (D5).
struct MealSummary: Sendable, Equatable {
    /// from the first day's start to the last day's end
    let window: DateInterval
    /// N of "Carb entries on n of N days": the complete days (6 for 7 d)
    let completeDays: Int
    /// n: the complete days with entries
    let daysWithEntries: Int
    /// over those days
    let entries: Int
    /// g, Σ over those days
    let carbs: Double
    /// g per day; nil without a day with entries
    let carbsPerDay: Double?
    let entriesPerDay: Double?
    /// g per entry with carbs; nil without one
    let perEntry: Double?
    let fatPerDay: Double?
    let proteinPerDay: Double?
    let carbEquivalentsPerDay: Double?
    /// any entry in the last 90 days has fat or protein: the fat, protein and equivalent tiles are shown (D6)
    let logsFatOrProtein: Bool
    /// no entry in the period, today included: "No carb entries in this period"
    let isEmpty: Bool

    /// "Carb entries on n of N days"
    var isLimited: Bool { daysWithEntries < completeDays }
}

/// One request's result for the Meals tab.
struct MealPeriod: Sendable, Equatable {
    let summary: MealSummary
    /// oldest -> newest, the last one today
    let days: [DayMeals]
    /// 24, by hour
    let hours: [HourMeals]
    /// "Most carbs": up to `MealStatsEngine.topHourCount` hours with carbs, the most first (ties to the earlier hour)
    let topHours: [HourMeals]
}

/// The meals statistics, as pure functions: no Core Data, no `Date()`, no global calendar.
enum MealStatsEngine {
    /// "Most carbs" shows this many hours.
    static let topHourCount = 3
    /// The fat/protein tiles are shown when an entry of this many days (today included) has fat or protein.
    static let fatOrProteinDays = 90

    /// The entries: `deduplicated`, rows without carbs, fat and protein dropped (a nutrient-only one,
    /// `MealPoint.isNutrientOnly`, is the Nutrients screen's alone). Oldest -> newest.
    static func clean(_ points: [MealPoint]) -> [MealPoint] {
        deduplicated(points).filter { $0.carbs > 0 || $0.fat > 0 || $0.protein > 0 }
    }

    /// Rows with the same non-empty id are one, the one with the earliest `actualDate` (the leftover duplicates of the
    /// old Nightscout save, which dated each copy at its poll). Oldest -> newest.
    static func deduplicated(_ points: [MealPoint]) -> [MealPoint] {
        let sorted = points.sorted {
            ($0.actualDate, $0.createdAt ?? .distantPast, $0.carbs) < ($1.actualDate, $1.createdAt ?? .distantPast, $1.carbs)
        }
        var seen = Set<String>()
        return sorted.filter { point in
            guard let id = point.id, id.isNotEmpty else { return true }
            return seen.insert(id).inserted
        }
    }

    /// g: `(4 × protein + 9 × fat) / 10 × factor`, unrounded (the total `CarbsStorage.storeCarbs` splits into entries;
    /// its per-entry rounding and minimum are left out). 20 g fat and 30 g protein at 0.5 give 15 g.
    static func carbEquivalents(fat: Double, protein: Double, factor: Double) -> Double {
        (4 * Swift.max(protein, 0) + 9 * Swift.max(fat, 0)) / 10 * factor
    }

    /// An entry of the last `fatOrProteinDays` days (up to `now`) has fat or protein (D6). Independent of the period.
    static func logsFatOrProtein(_ points: [MealPoint], now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        let start = StatsClock.dayStart(fatOrProteinDays - 1, before: today, calendar: calendar) ?? today
        return points.contains { $0.actualDate >= start && $0.actualDate <= now && ($0.fat > 0 || $0.protein > 0) }
    }

    /// The whole computation of a period: its days (`InsulinStatsEngine.periodDays`), the averages over the complete
    /// days with entries (today joins them at midnight), the hours and the top hours. Entries after `now` are left out.
    /// - Parameters:
    ///   - points: the rows of the period (any order, duplicates included)
    ///   - fatOrProteinLogged: `logsFatOrProtein` of the last 90 days
    ///   - factor: the current `individualAdjustmentFactor`
    static func period(
        _ period: StatsPeriod,
        points: [MealPoint],
        fatOrProteinLogged: Bool,
        factor: Double,
        now: Date,
        calendar: Calendar
    ) -> MealPeriod {
        let dayIntervals = InsulinStatsEngine.periodDays(period, now: now, calendar: calendar)
        let start = dayIntervals.first?.start ?? calendar.startOfDay(for: now)
        let window = DateInterval(start: start, end: Swift.max(start, dayIntervals.last?.end ?? start))
        let today = calendar.startOfDay(for: now)
        let entries = clean(points).filter { $0.actualDate >= window.start && $0.actualDate <= now }

        var index = 0
        let days = dayIntervals.map { day -> DayMeals in
            var inDay: [MealPoint] = []
            while index < entries.count, entries[index].actualDate < day.end {
                if entries[index].actualDate >= day.start {
                    inDay.append(entries[index])
                }
                index += 1
            }
            let fat = inDay.reduce(0) { $0 + $1.fat }
            let protein = inDay.reduce(0) { $0 + $1.protein }
            return DayMeals(
                day: day,
                isToday: day.start == today,
                entries: inDay,
                carbs: inDay.reduce(0) { $0 + $1.carbs },
                fat: fat,
                protein: protein,
                carbEquivalents: inDay.reduce(0) { $0 + carbEquivalents(fat: $1.fat, protein: $1.protein, factor: factor) }
            )
        }

        let averaged = days.filter(\.isAveraged)
        let count = Double(averaged.count)
        let averagedEntries = averaged.flatMap(\.entries)
        let carbs = averaged.reduce(0) { $0 + $1.carbs }
        let withCarbs = averagedEntries.filter { $0.carbs > 0 }.count
        func perDay(_ value: (DayMeals) -> Double) -> Double? {
            averaged.isEmpty ? nil : averaged.reduce(0) { $0 + value($1) } / count
        }

        let summary = MealSummary(
            window: window,
            completeDays: days.filter { !$0.isToday }.count,
            daysWithEntries: averaged.count,
            entries: averagedEntries.count,
            carbs: carbs,
            carbsPerDay: perDay(\.carbs),
            entriesPerDay: perDay { Double($0.entries.count) },
            perEntry: withCarbs > 0 ? carbs / Double(withCarbs) : nil,
            fatPerDay: perDay(\.fat),
            proteinPerDay: perDay(\.protein),
            carbEquivalentsPerDay: perDay(\.carbEquivalents),
            logsFatOrProtein: fatOrProteinLogged,
            isEmpty: entries.isEmpty
        )

        let timeZone = calendar.timeZone
        let hours = (0 ..< 24).map { hour -> HourMeals in
            var hourCarbs = 0.0
            var hourEntries = 0
            var hourWithCarbs = 0
            var hourDays = 0
            for day in averaged {
                let inHour = day.entries.filter { StatsClock.clockHour($0.actualDate, in: timeZone) == hour }
                guard inHour.isNotEmpty else { continue }
                hourDays += 1
                hourEntries += inHour.count
                hourWithCarbs += inHour.filter { $0.carbs > 0 }.count
                hourCarbs += inHour.reduce(0) { $0 + $1.carbs }
            }
            return HourMeals(
                hour: hour,
                carbs: hourCarbs,
                carbsPerDay: averaged.isEmpty ? 0 : hourCarbs / count,
                entries: hourEntries,
                daysWithEntries: hourDays,
                perEntry: hourWithCarbs > 0 ? hourCarbs / Double(hourWithCarbs) : nil,
                share: carbs > 0 ? hourCarbs / carbs : 0
            )
        }
        let topHours = hours
            .filter { $0.carbs > 0 }
            .sorted { $0.carbs > $1.carbs || ($0.carbs == $1.carbs && $0.hour < $1.hour) }
            .prefix(topHourCount)

        return MealPeriod(summary: summary, days: days, hours: hours, topHours: Array(topHours))
    }
}
