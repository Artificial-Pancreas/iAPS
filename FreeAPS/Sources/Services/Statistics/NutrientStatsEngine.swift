import Foundation

/// Fiber or a micronutrient, as the Nutrients screen shows them: fiber first, then `MicroNutrient.allCases` (the app's
/// order).
enum StatsNutrient: Hashable, Sendable, Identifiable {
    case fiber
    case micro(MicroNutrient)

    /// The groups the Nutrients screen shows without a reference (fiber, then the vitamins, then the minerals).
    enum Group: Sendable {
        case fiber
        case vitamin
        case mineral
    }

    static let all: [StatsNutrient] = [.fiber] + MicroNutrient.allCases.map { .micro($0) }

    var id: String {
        switch self {
        case .fiber: return "fiber"
        case let .micro(nutrient): return nutrient.rawValue
        }
    }

    var group: Group {
        switch self {
        case .fiber: return .fiber
        case let .micro(nutrient): return nutrient.type == .vitamin ? .vitamin : .mineral
        }
    }

    /// The unit shown and compared with the reference intake: the EFSA table's. The app stores the amounts in
    /// `MicroNutrient.unit` (the food databases are normalised to it), which is the table's for all but B7 and B9: stored
    /// in mg, in µg in the table (`storedScale`).
    var unit: String {
        switch self {
        case .fiber: return "g"
        case .micro(.vitaminB7),
             .micro(.vitaminB9): return MicroNutrient.vitaminB12.unit
        case let .micro(nutrient): return nutrient.unit
        }
    }

    /// a stored amount × this = the amount in `unit`
    var storedScale: Double {
        switch self {
        case .micro(.vitaminB7),
             .micro(.vitaminB9): return 1000
        case .fiber,
             .micro: return 1
        }
    }

    /// Salt's reference is a limit (5 g a day): the only one marked above it. Every other nutrient is a plain share of
    /// its reference intake (iron, iodine, vitamin A and D too).
    var isLimit: Bool {
        self == .micro(.salt)
    }

    /// A reference that depends on neither sex nor age, shown without `NutrientReferences` too: salt's limit.
    var fixedReference: Double? {
        // the table's salt limit is the same for every age and sex
        isLimit ? EFSAReferenceIntakes.value(for: .salt, age: 30, sex: .woman).value : nil
    }

    /// An entry's amount in `unit`; 0 when it isn't listed.
    func amount(in point: MealPoint) -> Double {
        switch self {
        case .fiber: return point.fiber
        case let .micro(nutrient): return (point.micronutrients[nutrient] ?? 0) * storedScale
        }
    }
}

/// The EFSA reference intakes (`EFSAReferenceIntakes`) for the user's sex and age, in each nutrient's
/// `StatsNutrient.unit`. None without both (no default person): the Nutrients screen then
/// shows the amounts alone, salt with its limit (`StatsNutrient.fixedReference`).
struct NutrientReferences: Sendable, Equatable {
    /// What the references depend on in the settings: refreshed when it changes.
    struct Demographics: Sendable, Equatable {
        /// `FreeAPSSettings.sexSetting`: 0 woman, 1 man, 2 other, 3 not set (the default)
        let sexSetting: Int
        /// `FreeAPSSettings.birthDate`; `.distantPast` until set
        let birthDate: Date

        init(sexSetting: Int, birthDate: Date) {
            self.sexSetting = sexSetting
            self.birthDate = birthDate
        }

        init(_ settings: FreeAPSSettings) {
            sexSetting = settings.sexSetting
            birthDate = settings.birthDate
        }
    }

    /// Who the values are for: the table has values for women and men only.
    enum Person: Sendable, Equatable {
        case woman
        case man
    }

    let person: Person
    /// in whole years
    let age: Int
    /// by nutrient, in its unit
    let intakes: [StatsNutrient: Double]

    /// nil when the sex isn't set (woman or man: "other" and "not set", the default, count as not set) or the
    /// birth date isn't (`.distantPast`, or an age outside 0...120)
    init?(_ demographics: Demographics, now: Date, calendar: Calendar) {
        let person: Person
        let sex = Sex.savedSettings(demographics.sexSetting)
        switch sex {
        case .woman: person = .woman
        case .man: person = .man
        case .other,
             .secret: return nil
        }
        // the age as Settings › Sharing's (`DemographicsSharing.age`: the birth day to today)
        guard let age = DemographicsSharing.age(birthDate: demographics.birthDate, now: now, calendar: calendar),
              (0 ... 120).contains(age)
        else { return nil }

        self.person = person
        self.age = age
        var intakes: [StatsNutrient: Double] = [
            .fiber: EFSAReferenceIntakes.value(for: MacroNutrient.fiber, age: age, sex: sex).value
        ]
        for nutrient in MicroNutrient.allCases {
            intakes[.micro(nutrient)] = EFSAReferenceIntakes.value(for: nutrient, age: age, sex: sex).value
        }
        self.intakes = intakes
    }
}

/// A day of the Nutrients screen (`NutrientStatsEngine.day`).
struct DayNutrients: Sendable, Equatable {
    /// the whole calendar day
    let day: DateInterval
    let isToday: Bool
    /// its entries (its Meals entries and its nutrient-only ones, `MealPoint.isNutrientOnly`), and those with nutrient
    /// data (`MealPoint.hasNutrientData`)
    let entries: Int
    let entriesWithData: Int
    /// g: all its carbs, and those of the entries with nutrient data
    let carbs: Double
    let carbsWithData: Double
    /// by nutrient, in its unit: Σ of the entries with nutrient data (one that doesn't list it adds 0); empty without one
    let amounts: [StatsNutrient: Double]
    /// in the averages: a complete day (not today) with carbs, whose entries with nutrient data carry at least 80% of
    /// them. A supplement alone, or on a day of fat and protein only, isn't counted; on a day with food it adds its
    /// nutrients.
    let isCounted: Bool
    /// the entries, oldest -> newest: the day card's
    let points: [MealPoint]

    var hasData: Bool { entriesWithData > 0 }

    /// of its carbs, 0...1: those of the entries with nutrient data; 0 without carbs
    var carbShareWithData: Double {
        carbs > 0 ? carbsWithData / carbs : 0
    }
}

/// The Nutrients screen's numbers, over the counted days (`DayNutrients.isCounted`).
struct NutrientSummary: Sendable, Equatable {
    /// the complete days of the period (today excluded): N of "Days with nutrient data n of N"
    let completeDays: Int
    /// n: the complete days counted
    let countedDays: Int
    /// by nutrient, in its unit, per counted day; empty without one
    let perDay: [StatsNutrient: Double]
    /// an entry of the period (today included) has nutrient data
    let periodHasData: Bool
    /// an entry of the last 90 days has nutrient data: the Carbs card's Fiber tile and its way to the Nutrients screen
    /// (as `MealSummary.logsFatOrProtein`)
    let logsNutrients: Bool

    /// Too few days counted for the averages to stand for the period: fewer than 3, or than 70% of its complete days.
    var isLimited: Bool {
        // ⌈0.7 × N⌉ in whole numbers: no floating-point rounding at a whole 0.7 × N
        countedDays > 0 && countedDays < Swift.max(3, (7 * completeDays + 9) / 10)
    }
}

/// The Nutrients screen of a period: its days and its summary.
struct NutrientPeriod: Sendable, Equatable {
    let summary: NutrientSummary
    /// oldest -> newest, the last one today (`MealPeriod.days`')
    let days: [DayNutrients]
}

/// A nutrient's row: its amount per day and the share of its reference intake.
struct NutrientRow: Sendable, Equatable {
    let nutrient: StatsNutrient
    /// in its unit
    let amount: Double
    /// % of the reference intake (salt: of the limit, always); nil without references
    let percent: Double?
    /// salt above its limit as shown (`NutrientStatsEngine.isOverLimit`)
    let isOverLimit: Bool
}

/// The fiber, vitamins and minerals of the Meals tab, as pure functions: no Core Data, no `Date()`, no global calendar.
enum NutrientStatsEngine {
    /// A complete day counts when its entries with nutrient data carry at least this share of its carbs.
    static let countedCarbShare = 0.8

    /// A food of the last `MealStatsEngine.fatOrProteinDays` days (up to `now`) has nutrient data: an entry with carbs
    /// (a supplement alone, or fat and protein only, never makes a day count, so it doesn't turn the Nutrients on).
    /// Independent of the period, as `MealStatsEngine.logsFatOrProtein`.
    static func logsNutrients(_ points: [MealPoint], now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        let start = StatsClock.dayStart(MealStatsEngine.fatOrProteinDays - 1, before: today, calendar: calendar) ?? today
        return points.contains {
            $0.actualDate >= start && $0.actualDate <= now && $0.carbs > 0 && $0.hasNutrientData
        }
    }

    /// The nutrient-only entries (`MealPoint.isNutrientOnly`), deduplicated as `MealStatsEngine.clean`'s. Oldest ->
    /// newest.
    static func nutrientOnly(_ points: [MealPoint]) -> [MealPoint] {
        MealStatsEngine.deduplicated(points).filter(\.isNutrientOnly)
    }

    /// A day's sums, from its Meals entries (`MealStatsEngine.period`'s, cleaned) and its nutrient-only ones.
    static func day(_ day: DayMeals, nutrientOnly: [MealPoint] = []) -> DayNutrients {
        let points = (day.entries + nutrientOnly).sorted { $0.actualDate < $1.actualDate }
        let withData = points.filter(\.hasNutrientData)
        let carbsWithData = withData.reduce(0) { $0 + $1.carbs }
        var amounts: [StatsNutrient: Double] = [:]
        if withData.isNotEmpty {
            for nutrient in StatsNutrient.all {
                amounts[nutrient] = withData.reduce(0) { $0 + nutrient.amount(in: $1) }
            }
        }
        // a little room for the sums' rounding: 40 of 50 g is 80%
        let counted = !day.isToday && withData.isNotEmpty && day.carbs > 0
            && carbsWithData + 1E-9 >= countedCarbShare * day.carbs
        return DayNutrients(
            day: day.day,
            isToday: day.isToday,
            entries: points.count,
            entriesWithData: withData.count,
            carbs: day.carbs,
            carbsWithData: carbsWithData,
            amounts: amounts,
            isCounted: counted,
            points: points
        )
    }

    /// The period's days and the averages over the counted ones.
    /// - Parameters:
    ///   - days: `MealPeriod.days`
    ///   - points: the rows `MealStatsEngine.period` was given (any order, duplicates included): their nutrient-only
    ///     entries up to `now` join their days
    ///   - logsNutrients: `logsNutrients` of the last 90 days
    static func period(_ days: [DayMeals], points: [MealPoint], now: Date, logsNutrients: Bool) -> NutrientPeriod {
        let supplements = nutrientOnly(points).filter { $0.actualDate <= now }
        let shown = days.map { meals in
            day(meals, nutrientOnly: supplements.filter { meals.day.start <= $0.actualDate && $0.actualDate < meals.day.end })
        }
        let counted = shown.filter(\.isCounted)
        var perDay: [StatsNutrient: Double] = [:]
        if counted.isNotEmpty {
            for nutrient in StatsNutrient.all {
                perDay[nutrient] = counted.reduce(0) { $0 + ($1.amounts[nutrient] ?? 0) } / Double(counted.count)
            }
        }
        return NutrientPeriod(
            summary: NutrientSummary(
                completeDays: shown.filter { !$0.isToday }.count,
                countedDays: counted.count,
                perDay: perDay,
                periodHasData: shown.contains(where: \.hasData),
                logsNutrients: logsNutrients
            ),
            days: shown
        )
    }

    /// A nutrient's reference in its unit: the user's (`NutrientReferences`), or one that needs no demographics
    /// (salt's limit); nil without either.
    static func reference(of nutrient: StatsNutrient, references: NutrientReferences?) -> Double? {
        references?.intakes[nutrient] ?? nutrient.fixedReference
    }

    /// Every nutrient's row: with references by the share of its reference, the largest first (ties in the app's
    /// order); without, in the app's order (fiber, the vitamins, the minerals), only salt with its share of the limit.
    /// A nutrient missing from `amounts` is 0.
    static func rows(_ amounts: [StatsNutrient: Double], references: NutrientReferences?) -> [NutrientRow] {
        let rows = StatsNutrient.all.map { nutrient -> NutrientRow in
            let amount = amounts[nutrient] ?? 0
            let percent = reference(of: nutrient, references: references).flatMap { intake -> Double? in
                intake > 0 ? amount / intake * 100 : nil
            }
            return NutrientRow(
                nutrient: nutrient,
                amount: amount,
                percent: percent,
                isOverLimit: isOverLimit(nutrient, percent: percent)
            )
        }
        guard references != nil else { return rows }
        return rows.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.percent ?? -1
                let right = rhs.element.percent ?? -1
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }

    /// A share of the reference as shown: in whole percent, rounded half away from zero.
    static func shownPercent(_ percent: Double) -> Int {
        Int(percent.rounded())
    }

    /// Salt above its limit, as shown: its percent shown above 100 (5.02 g is "100%", at the limit, not above it).
    static func isOverLimit(_ nutrient: StatsNutrient, percent: Double?) -> Bool {
        guard nutrient.isLimit, let percent else { return false }
        return shownPercent(percent) > 100
    }

    /// The day chart's y axis: 0 and three equal steps of 1, 2, 2.5 or 5 × a power of ten, the top a little above
    /// `maximum` (the largest bar, the average and the reference).
    static func axisLevels(maximum: Double) -> [Double] {
        let step = niceStep(Swift.max(maximum, 0) * 1.04 / 3)
        return (0 ... 3).map { step * Double($0) }
    }

    /// The smallest of 1, 2, 2.5, 5, 10 × a power of ten that is at least `value`; 1 for none.
    static func niceStep(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let power = pow(10, log10(value).rounded(.down))
        for multiple in [1, 2, 2.5, 5] where multiple * power >= value - 1E-9 * power {
            return multiple * power
        }
        return 10 * power
    }
}
