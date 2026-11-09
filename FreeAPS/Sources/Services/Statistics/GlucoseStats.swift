import Foundation

/// A CGM reading as the statistics use it: the time and the value in mg/dL.
struct GlucosePoint: Sendable, Equatable {
    let time: Date
    let mgdl: Int16
}

/// A reading with the time it stands for: it covers `[time, time + span)`.
struct WeightedPoint: Sendable, Equatable {
    let time: Date
    let mgdl: Int16
    let span: TimeInterval

    var end: Date { time.addingTimeInterval(span) }
}

enum GlucoseBand: Int, CaseIterable, Sendable {
    case veryLow
    case low
    case inRange
    case high
    case veryHigh
}

/// The five glucose bands. Every edge is an integer mg/dL value (readings are integers), upper bounds inclusive:
/// very low `v < 54`, low `54 ≤ v < low`, in range `low ≤ v ≤ high`, high `high < v ≤ 250`, very high `v > 250`.
struct StatsBands: Sendable, Equatable {
    /// very low is `v < veryLowBelow`, mg/dL
    static let veryLowBelow = 54
    /// very high is `v > veryHighAbove`, mg/dL
    static let veryHighAbove = 250

    /// TIR and TITR, mg/dL; mmol users get the edges that display like them (`tirRange`, `titrRange`)
    static let tirMgdl = 70 ... 180
    static let titrMgdl = 70 ... 140

    /// in range is `low ... high`, inclusive
    let low: Int
    let high: Int
    /// 70...180 for mg/dL users; for mmol users the values displayed as 3.9...10.0 (70...181)
    let tirRange: ClosedRange<Int>
    /// 70...140 for mg/dL users; for mmol users the values displayed as 3.9...7.8 (70...141)
    let titrRange: ClosedRange<Int>

    /// From the Statistics low/high settings (mg/dL, fractional for mmol users).
    /// mg/dL users get the settings rounded half up; mmol users get the edges that display like the settings
    /// (`mmolEdges`), and so do their TIR and TITR. The fixed 54 and 250 stay as they are for everyone.
    init(low: Decimal, high: Decimal, units: GlucoseUnits) {
        var lowEdge: Int
        var highEdge: Int
        switch units {
        case .mgdL:
            lowEdge = Self.roundedHalfUp(low)
            highEdge = Self.roundedHalfUp(high)
            tirRange = Self.tirMgdl
            titrRange = Self.titrMgdl
        case .mmolL:
            let edges = Self.mmolEdges(lower: low, upper: high)
            lowEdge = edges.lower
            highEdge = edges.upper
            tirRange = Self.mmolRange(Self.tirMgdl)
            titrRange = Self.mmolRange(Self.titrMgdl)
        }
        // the stored settings can be outside what the settings screen offers (it clamps only what it shows)
        lowEdge = Swift.min(Swift.max(lowEdge, Self.veryLowBelow), Self.veryHighAbove)
        highEdge = Swift.min(Swift.max(highEdge, lowEdge), Self.veryHighAbove)
        self.low = lowEdge
        self.high = highEdge
    }

    func band(_ mgdl: Int) -> GlucoseBand {
        if mgdl < Self.veryLowBelow { return .veryLow }
        if mgdl < low { return .low }
        if mgdl <= high { return .inRange }
        if mgdl <= Self.veryHighAbove { return .high }
        return .veryHigh
    }

    /// The integer mg/dL values of a band, nil when it is empty (`low` at 54, or `high` at 250).
    func range(of band: GlucoseBand) -> ClosedRange<Int>? {
        let lower: Int
        let upper: Int
        switch band {
        case .veryLow:
            lower = 0
            upper = Self.veryLowBelow - 1
        case .low:
            lower = Self.veryLowBelow
            upper = low - 1
        case .inRange:
            lower = low
            upper = high
        case .high:
            lower = high + 1
            upper = Self.veryHighAbove
        case .veryHigh:
            lower = Self.veryHighAbove + 1
            upper = GlucoseHistogram.maxValue
        }
        return lower <= upper ? lower ... upper : nil
    }

    /// The bands to show: zero-width bands are left out of labels, rows and legends (they stay in the arrays, with 0).
    var visibleBands: [GlucoseBand] {
        GlucoseBand.allCases.filter { range(of: $0) != nil }
    }

    /// The mmol/L value a mg/dL value is displayed as: 1 decimal, rounded half up on the exact decimal,
    /// like the app's glucose formatter (`CurrentGlucoseView.mmolLFormatter`).
    static func mmolDisplay(_ mgdl: Int) -> Decimal {
        mmolDisplay(decimal: Decimal(mgdl))
    }

    static func mmolDisplay(decimal mgdl: Decimal) -> Decimal {
        var mmol = mgdl * mmolPerMgdl
        var rounded = Decimal()
        NSDecimalRound(&rounded, &mmol, 1, .plain)
        return rounded
    }

    /// The one mmol edge rule (the bands' low/high, TIR and TITR): the integer mg/dL edges that display like
    /// `lower` and `upper` (mg/dL, fractional), `lower` the smallest value displayed at or above it, `upper` the largest
    /// displayed at or below it. E.g. 10.0 mmol/L -> 181, as 181 is displayed as 10.0; 3.9 -> 70, as 69 is 3.8.
    /// Not clamped, and `lower > upper` is possible for inverted inputs.
    static func mmolEdges(lower: Decimal, upper: Decimal) -> (lower: Int, upper: Int) {
        let lowerDisplay = mmolDisplay(decimal: lower)
        var lowerEdge = searchStart(lower)
        while lowerEdge > searchRange.lowerBound, mmolDisplay(lowerEdge - 1) >= lowerDisplay { lowerEdge -= 1 }
        while lowerEdge < searchRange.upperBound, mmolDisplay(lowerEdge) < lowerDisplay { lowerEdge += 1 }

        let upperDisplay = mmolDisplay(decimal: upper)
        var upperEdge = searchStart(upper)
        while upperEdge < searchRange.upperBound, mmolDisplay(upperEdge + 1) <= upperDisplay { upperEdge += 1 }
        while upperEdge > searchRange.lowerBound, mmolDisplay(upperEdge) > upperDisplay { upperEdge -= 1 }

        return (lowerEdge, upperEdge)
    }

    /// `GlucoseUnits.exchangeRate` built exactly (a Decimal float literal can come out a hair off).
    private static let mmolPerMgdl = Decimal(sign: .plus, exponent: -4, significand: 555)

    private static let searchRange = 0 ... GlucoseHistogram.maxValue

    private static func mmolRange(_ mgdl: ClosedRange<Int>) -> ClosedRange<Int> {
        let edges = mmolEdges(lower: Decimal(mgdl.lowerBound), upper: Decimal(mgdl.upperBound))
        return edges.lower ... Swift.max(edges.lower, edges.upper)
    }

    private static func searchStart(_ mgdl: Decimal) -> Int {
        Swift.min(Swift.max(roundedHalfUp(mgdl), searchRange.lowerBound), searchRange.upperBound)
    }

    private static func roundedHalfUp(_ value: Decimal) -> Int {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

extension StatsBands {
    /// The bands of the low/high settings: the one low/high rule of every glucose colouring (header, Home chart,
    /// Live Activity, calendar), so a value is in range everywhere or nowhere.
    init(settings: FreeAPSSettings) {
        self.init(low: settings.low, high: settings.high, units: settings.units)
    }
}

enum StatsPeriod: String, JSON, CaseIterable, Identifiable, Sendable, Hashable {
    case today
    case last24h
    case days7
    case days14
    case days30
    case days90
    /// By weekday's whole weeks (`StatsTab.weekday`): 4 and 8 weeks, and 13 (Weekly's too)
    case weeks4
    case weeks5
    case weeks8
    case weeks13

    /// the Statistics Overview's periods (the Home cards' ranges once)
    static let homeRanges: [StatsPeriod] = [.today, .last24h, .days7, .days14, .days30, .days90]
    /// the ranges of the stats bar on Home (its range button's)
    static let homeStatsRanges: [StatsPeriod] = [.today, .last24h]
    /// the baselines the Day tab's usual day offers: the last 14, 30 or 90 days
    static let usualDayPeriods: [StatsPeriod] = [.days14, .days30, .days90]
    /// By weekday's periods: whole weeks to yesterday (`GlucoseStatsEngine.weekdayDays`)
    static let weekdayPeriods: [StatsPeriod] = [.weeks4, .weeks8, .weeks13]

    var id: String { rawValue }

    /// The calendar days of an N-day or weekly period (today included); nil for Today and 24 h.
    var calendarDayCount: Int? {
        switch self {
        case .last24h,
             .today: return nil
        case .days7: return 7
        case .days14: return 14
        case .days30: return 30
        case .days90: return 90
        case .weeks4: return 28
        case .weeks5: return 35
        case .weeks8: return 56
        case .weeks13: return 91
        }
    }

    /// The number of weeks of a weekly period.
    var weekCount: Int? {
        switch self {
        case .weeks4: return 4
        case .weeks5: return 5
        case .weeks8: return 8
        case .weeks13: return 13
        default: return nil
        }
    }
}

/// The Home cards' and the Statistics screen's display choices, kept on the phone in `UserDefaults`: UI-only, so not
/// in `FreeAPSSettings` (nor in the settings backup). A missing value, or one the choice doesn't offer (an unknown raw
/// value, another period), reads as the default; a value the choice doesn't offer is never written. Tests pass a
/// `UserDefaults(suiteName:)`.
struct StatsDisplayPreferences {
    /// "iAPS."-prefixed, as `IAPSconfig`'s keys
    enum Key {
        /// the stats bar's range (`StatsPeriod.homeStatsRanges`)
        static let homeStatsRange = "iAPS.stats.home.range"
        /// the stats bar's TITR: the tight part of its in-range segment and its figure ("Show TITR")
        static let homeStatsTITR = "iAPS.stats.home.titr"
        /// the On board card's glucose and carbs-on-board lanes
        static let homeOnBoardGlucose = "iAPS.stats.home.onBoard.glucose"
        static let homeOnBoardCOB = "iAPS.stats.home.onBoard.cob"
        /// the Day tab's usual day: shown, and its baseline (`StatsPeriod.usualDayPeriods`)
        static let usualDayShown = "iAPS.stats.day.usualDay"
        static let usualDayPeriod = "iAPS.stats.day.usualDayPeriod"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Today or 24 h (24 h by default)
    var homeStatsRange: StatsPeriod {
        get { period(Key.homeStatsRange, offered: StatsPeriod.homeStatsRanges) ?? .last24h }
        nonmutating set { setPeriod(newValue, Key.homeStatsRange, offered: StatsPeriod.homeStatsRanges) }
    }

    /// off by default
    var homeStatsTITR: Bool {
        get { defaults.object(forKey: Key.homeStatsTITR) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.homeStatsTITR) }
    }

    /// on by default
    var homeOnBoardGlucose: Bool {
        get { defaults.object(forKey: Key.homeOnBoardGlucose) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.homeOnBoardGlucose) }
    }

    /// on by default
    var homeOnBoardCOB: Bool {
        get { defaults.object(forKey: Key.homeOnBoardCOB) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.homeOnBoardCOB) }
    }

    /// off by default
    var usualDayShown: Bool {
        get { defaults.object(forKey: Key.usualDayShown) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.usualDayShown) }
    }

    /// the last 14, 30 or 90 days (14 by default)
    var usualDayPeriod: StatsPeriod {
        get { period(Key.usualDayPeriod, offered: StatsPeriod.usualDayPeriods) ?? .days14 }
        nonmutating set { setPeriod(newValue, Key.usualDayPeriod, offered: StatsPeriod.usualDayPeriods) }
    }

    private func period(_ key: String, offered: [StatsPeriod]) -> StatsPeriod? {
        guard let raw = defaults.string(forKey: key), let period = StatsPeriod(rawValue: raw),
              offered.contains(period)
        else { return nil }
        return period
    }

    private func setPeriod(_ period: StatsPeriod, _ key: String, offered: [StatsPeriod]) {
        guard offered.contains(period) else { return }
        defaults.set(period.rawValue, forKey: key)
    }
}

enum HbA1cUnit: Sendable {
    case percent
    case mmolPerMol

    /// mmol/mol for mmol/L users, % for mg/dL users; the override setting swaps them.
    static func resolve(units: GlucoseUnits, override: Bool) -> HbA1cUnit {
        (units == .mmolL) != override ? .mmolPerMol : .percent
    }
}

/// Seconds spent at each mg/dL value. Additive (days sum to periods) and independent of the low/high settings.
struct GlucoseHistogram: Sendable, Equatable {
    static let maxValue = 600

    /// index = mg/dL, clamped to 0...600
    private(set) var seconds: [Double] = Array(repeating: 0, count: GlucoseHistogram.maxValue + 1)
    private(set) var totalSeconds: Double = 0
    /// readings whose start falls inside
    private(set) var readingCount: Int = 0
    private(set) var firstReading: Date?
    private(set) var lastReading: Date?
    /// the lowest and highest readings whose start falls inside
    private(set) var minReading: Int?
    private(set) var maxReading: Int?

    init() {}

    mutating func add(_ p: WeightedPoint, seconds: Double, startsInside: Bool) {
        let value = Int(p.mgdl)
        if seconds > 0 {
            self.seconds[Swift.min(Swift.max(value, 0), Self.maxValue)] += seconds
            totalSeconds += seconds
        }
        guard startsInside else { return }
        readingCount += 1
        if firstReading.map({ p.time < $0 }) ?? true { firstReading = p.time }
        if lastReading.map({ p.time > $0 }) ?? true { lastReading = p.time }
        minReading = Swift.min(minReading ?? value, value)
        maxReading = Swift.max(maxReading ?? value, value)
    }

    static func + (l: Self, r: Self) -> Self {
        var sum = l
        for index in sum.seconds.indices where r.seconds[index] != 0 {
            sum.seconds[index] += r.seconds[index]
        }
        sum.totalSeconds += r.totalSeconds
        sum.readingCount += r.readingCount
        sum.firstReading = [l.firstReading, r.firstReading].compactMap { $0 }.min()
        sum.lastReading = [l.lastReading, r.lastReading].compactMap { $0 }.max()
        sum.minReading = [l.minReading, r.minReading].compactMap { $0 }.min()
        sum.maxReading = [l.maxReading, r.maxReading].compactMap { $0 }.max()
        return sum
    }

    func seconds(in range: ClosedRange<Int>) -> Double {
        let lower = Swift.max(range.lowerBound, 0)
        let upper = Swift.min(range.upperBound, Self.maxValue)
        guard lower <= upper else { return 0 }
        return seconds[lower ... upper].reduce(0, +)
    }

    var isEmpty: Bool { totalSeconds == 0 }

    /// time-weighted
    var mean: Double? {
        guard totalSeconds > 0 else { return nil }
        var sum = 0.0
        for (value, weight) in seconds.enumerated() where weight > 0 {
            sum += Double(value) * weight
        }
        return sum / totalSeconds
    }

    /// time-weighted population standard deviation
    var sd: Double? {
        guard totalSeconds > 0, let mean else { return nil }
        var sumOfSquares = 0.0
        for (value, weight) in seconds.enumerated() where weight > 0 {
            sumOfSquares += Double(value) * Double(value) * weight
        }
        return Swift.max(0, sumOfSquares / totalSeconds - mean * mean).squareRoot()
    }

    var min: Int? { minReading }
    var max: Int? { maxReading }

    /// Weighted quantile (`p` in 0...1): every value sits at the weighted-Hazen position `(C - w/2) / W`
    /// (C the cumulative weight up to and including it), linear interpolation in between, clamped at the ends.
    ///
    /// Positions are per distinct mg/dL value, not per reading: equal values are merged into one weight (the histogram
    /// keeps seconds per value). E.g. 100 for 900 s and 200 for 300 s give the median 125, whether the 100 came from
    /// one reading or three (a per-reading Hazen would give 100). That keeps the quantiles a quantile of time, so a day
    /// of 1-minute readings doesn't outweigh a day of 5-minute ones.
    func quantile(_ p: Double) -> Double? {
        guard totalSeconds > 0 else { return nil }
        var cumulative = 0.0
        var previous: (value: Double, position: Double)?
        for (value, weight) in seconds.enumerated() where weight > 0 {
            cumulative += weight
            let position = (cumulative - weight / 2) / totalSeconds
            if p <= position {
                guard let previous else { return Double(value) }
                let fraction = (p - previous.position) / (position - previous.position)
                return previous.value + fraction * (Double(value) - previous.value)
            }
            previous = (Double(value), position)
        }
        return previous?.value
    }
}

/// The time of a pool in each glucose band: the fractions of its covered time and their largest-remainder percents.
struct BandShares: Sendable, Equatable {
    /// A band's part of a bar, as fractions of the covered time: stacked in the given bands' order (`stacked`).
    struct Segment: Sendable, Equatable {
        let band: GlucoseBand
        let lower: Double
        let upper: Double
    }

    /// by `GlucoseBand.rawValue`; fractions of the covered time, 0...1 (all 0 without data)
    let fractions: [Double]
    /// by `GlucoseBand.rawValue`; largest remainder, sums to 100 (all 0 without data)
    let percents: [Int]

    /// The pair must agree: `percents` is the largest remainder of `fractions`. Use `init(fractions:)` or
    /// `init(seconds:total:)`; this one is for test fixtures.
    init(fractions: [Double], percents: [Int]) {
        self.fractions = fractions
        self.percents = percents
    }

    /// The nonzero bands of `bands`, stacked in their order.
    func stacked(_ bands: [GlucoseBand]) -> [Segment] {
        var segments: [Segment] = []
        var lower = 0.0
        for band in bands where fractions[band.rawValue] > 0 {
            let upper = lower + fractions[band.rawValue]
            segments.append(Segment(band: band, lower: lower, upper: upper))
            lower = upper
        }
        return segments
    }
}

extension BandShares {
    init(fractions: [Double]) {
        self.init(fractions: fractions, percents: GlucoseStatsEngine.largestRemainder(fractions))
    }

    /// - Parameters:
    ///   - seconds: by `GlucoseBand.rawValue`, the covered seconds in each band
    ///   - total: the covered seconds; 0 gives all 0
    init(seconds: [Double], total: Double) {
        self.init(fractions: seconds.map { total > 0 ? $0 / total : 0 })
    }
}

/// A value with its time by glucose band (`BandShares`), read band by band.
protocol BandSharesProviding {
    var bandShares: BandShares { get }
}

extension BandSharesProviding {
    func fraction(_ band: GlucoseBand) -> Double { bandShares.fractions[band.rawValue] }
    func percent(_ band: GlucoseBand) -> Int { bandShares.percents[band.rawValue] }
    /// a nonzero band that rounds to 0 is shown as "<1%"
    func isBelowOnePercent(_ band: GlucoseBand) -> Bool { fraction(band) > 0 && percent(band) == 0 }
}

extension BandShares: BandSharesProviding {
    var bandShares: BandShares { self }
}

struct DayAggregate: Sendable, Equatable {
    let day: DateInterval
    let histogram: GlucoseHistogram
}

/// The Glycemia Risk Index (Klonoff et al. 2022) of a histogram (`GlucoseStatsEngine.gri`): 0 best, 100 worst. Always
/// on the standard ranges, never the Statistics low/high settings. The ranges and components are percents of the
/// covered time.
struct GlycemiaRiskIndex: Sendable, Equatable {
    enum Zone: Int, CaseIterable, Sendable {
        case a
        case b
        case c
        case d
        case e
    }

    /// below 54
    let veryLow: Double
    /// 54 up to the bottom of `tirRange`
    let low: Double
    /// above `tirRange` up to 250
    let high: Double
    /// above 250
    let veryHigh: Double
    /// `veryLow + 0.8 × low`
    let hypo: Double
    /// `veryHigh + 0.5 × high`
    let hyper: Double
    /// `3.0 × hypo + 1.6 × hyper`, capped at 100
    let value: Double

    var zone: Zone { GlucoseStatsEngine.griZone(value) }
}

/// Which rule gave E (`GlucoseStatsEngine.effectiveEndRule`).
enum StatsEndRule: Sendable, Equatable {
    /// The data is current: E is the newest reading's end (clipped at the end of today). It stays so up to `stallsAt`,
    /// the newest reading's time + 1.5 of its cadence; after that the data is stalled.
    case current(stallsAt: Date)
    /// The data is stalled, or there are no readings: E is `now` floored to the minute, never before the newest
    /// reading's end (clipped at the end of today).
    case stalled
}

struct GlucoseSummary: Sendable, Equatable, BandSharesProviding {
    /// `[start, E)`
    let window: DateInterval
    /// which rule gave E
    let endRule: StatsEndRule
    let histogram: GlucoseHistogram
    let calendarDays: Int
    let daysWithData: Int
    let bands: StatsBands
    /// of the covered time
    let bandShares: BandShares
    /// fraction of the covered time in `bands.tirRange` (70...180, mmol: 70...181), 0...1.
    /// Never round this for display: use `tirPercent`.
    let tirFraction: Double
    /// fraction of the covered time in `bands.titrRange` (70...140, mmol: 70...141), 0...1.
    /// Never round this for display: use `titrPercent`.
    let titrFraction: Double
    let mean: Double?
    let sd: Double?
    /// percent
    let cv: Double?
    let gmiPercent: Double?
    let eA1cPercent: Double?
    /// covered seconds / window length, 0...1
    let coverage: Double
    /// the rounded value is the one used for display AND for the limited test
    let coveragePercent: Int

    var isLimited: Bool { coveragePercent < 70 }
    var a1cNeedsMoreDays: Bool { daysWithData < 14 }
    /// readings that start inside the window
    var minMax: ClosedRange<Int>? {
        guard let min = histogram.min, let max = histogram.max else { return nil }
        return min ... max
    }

    var firstReading: Date? { histogram.firstReading }
    var lastReading: Date? { histogram.lastReading }
    var isEmpty: Bool { histogram.totalSeconds == 0 }

    /// The TIR every view shows; callers never round `tirFraction` themselves.
    /// When the in-range band is the TIR range (e.g. mg/dL 70-180) it is that band's percent (largest remainder),
    /// so "In range" and "TIR" never show different numbers for the same readings; otherwise the fraction rounded.
    var tirPercent: Int { displayedPercent(tirFraction, of: bands.tirRange) }
    /// The TITR every view shows; callers never round `titrFraction` themselves. Same rule as `tirPercent`.
    var titrPercent: Int { displayedPercent(titrFraction, of: bands.titrRange) }

    /// The fraction of the covered time inside both the in-range band and TITR's range (`bands.titrRange`), 0...1:
    /// the tight part the Home stats bar draws in its in-range segment. Its TITR figure is `titrPercent`, the standard
    /// 70–140 share, so the two differ at the edges where the band doesn't contain 70–140: by the time in 70 up to
    /// `low` (an 80–180 band leaves out 70–79) and in `high` up to 140 (a 70–120 one leaves out 121–140); a band that
    /// misses 70–140 has no tight part. Any band from 70 or below to 140 or above (the default 70–180, mmol 3.9–10.0)
    /// draws exactly the figure.
    var tightInRangeFraction: Double {
        let lower = Swift.max(bands.low, bands.titrRange.lowerBound)
        let upper = Swift.min(bands.high, bands.titrRange.upperBound)
        guard !isEmpty, lower <= upper else { return 0 }
        return histogram.seconds(in: lower ... upper) / histogram.totalSeconds
    }

    private func displayedPercent(_ fraction: Double, of range: ClosedRange<Int>) -> Int {
        range == bands.low ... bands.high ? percent(.inRange) : Int((fraction * 100).rounded())
    }
}

/// AGP percentiles of one time-of-day bin (pooled with its neighbours), mg/dL.
struct AGPBin: Sendable, Equatable {
    let startMinute: Int
    let p5: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p95: Double
    /// the pooled seconds behind the percentiles
    let seconds: Double
}

/// A point of the AGP chart (`GlucoseStatsEngine.agpPlotPoints`): a bin's percentiles at its middle minute, or the
/// midnight edge at minute 0 and 1440; mg/dL, kept inside the glucose axis.
struct AGPPlotPoint: Sendable, Equatable {
    /// the minute of the day, the chart's x: minutes, not dates, so a DST day draws no step
    let minute: Int
    /// the points between two gaps (bins without data); each segment is drawn on its own, so a gap stays a gap
    let segment: Int
    let p5: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p95: Double
}

/// A point of the Day tab's usual-day overlay (`GlucoseStatsEngine.usualDayPoints`): an AGP point at a moment of the
/// shown day; mg/dL, kept inside the Trace's axis.
struct UsualDayPoint: Sendable, Equatable {
    let time: Date
    /// the points between two gaps (of the profile, or a domain edge); each segment is drawn on its own
    let segment: Int
    let p25: Double
    let p50: Double
    let p75: Double
}

struct HourBucket: Sendable, Equatable {
    let hour: Int
    let histogram: GlucoseHistogram
}

/// "When it happens": the clock hour with the largest share of a band group.
struct PeakHour: Sendable, Equatable {
    enum Group: CaseIterable, Sendable {
        /// very low + low
        case below
        case inRange
        /// high + very high
        case above

        /// its bands, very low first
        var bands: [GlucoseBand] {
            switch self {
            case .below: return [.veryLow, .low]
            case .inRange: return [.inRange]
            case .above: return [.high, .veryHigh]
            }
        }
    }

    let group: Group
    let hour: Int
    /// fraction of that hour's covered time, 0...1
    let share: Double
}

/// A clock hour of the Hour-of-day view (`GlucoseStatsEngine.hourOfDayHour`): its column and its band shares, over
/// every day of the period.
struct HourOfDayHour: Sendable, Equatable, BandSharesProviding {
    typealias Segment = BandShares.Segment

    /// 0...23, by the local clock
    let hour: Int
    /// the covered seconds of the readings starting in this clock hour, every day of the period
    let seconds: Double
    /// the nonzero visible bands stacked from very low up, as fractions of the hour's covered time; empty without data
    let segments: [Segment]
    /// of the hour's covered time; all 0 without data
    let bandShares: BandShares

    var hasData: Bool { seconds > 0 }
    /// "{h} hours of data": the covered seconds in hours
    var hoursOfData: Double { seconds / 3600 }
}

struct WeekAggregate: Sendable, Equatable {
    /// from its first day's start to its last day's end (the last week's up to E; just after midnight it ends at the
    /// start of the empty today)
    let days: DateInterval
    /// the start of its last day: today for the last week, also while today is still empty and zero-length
    let lastDay: Date
    /// 7, fewer for a short last week (a day count that isn't a multiple of 7)
    let dayCount: Int
    let histogram: GlucoseHistogram
    let includesToday: Bool

    /// No reading starts in it: shown as "no data". The previous week's last span running past its first midnight is
    /// covered time, not a reading (as a day of the Daily view).
    var isEmpty: Bool { histogram.readingCount == 0 }
}

/// A week of the Weekly view (`GlucoseStatsEngine.weeklyWeek`): its in range and mean as shown, and their difference
/// from the period's as shown (Δ = shown week − shown period).
struct WeeklyWeek: Sendable, Equatable {
    /// How a week compares with the period, by its Δ as shown: a higher in range or a lower mean is better, a Δ of 0
    /// (shown "±0") neither.
    enum Comparison: Sendable, Equatable {
        case better
        case same
        case worse

        init(delta: Decimal, higherIsBetter: Bool) {
            if delta == 0 {
                self = .same
            } else {
                self = (delta > 0) == higherIsBetter ? .better : .worse
            }
        }
    }

    /// from its first day's start to its last day's end (`WeekAggregate.days`)
    let days: DateInterval
    /// the start of its last day (today for the last week)
    let lastDay: Date
    let dayCount: Int
    /// the last week: it ends with today
    let includesToday: Bool
    /// a reading starts in it; without: "no data", no bar, no numbers, and left out of the charts' scale
    let hasData: Bool
    /// the in-range band's largest-remainder percent of the week's own bands; nil without data
    let inRangePercent: Int?
    /// nonzero, rounded to 0: shown as "<1%"
    let inRangeBelowOnePercent: Bool
    /// the mean as shown (`GlucoseStatsEngine.shownMean`): whole mg/dL, or mmol/L to one decimal; nil without data
    let mean: Decimal?
    /// `inRangePercent` − the period's in-range percent, percentage points; nil without data
    let inRangeDelta: Int?
    /// `mean` − the period's mean as shown, in the units shown; nil without data
    let meanDelta: Decimal?

    /// a higher in range is better; nil without data
    var inRangeComparison: Comparison? {
        inRangeDelta.map { Comparison(delta: Decimal($0), higherIsBetter: true) }
    }

    /// a lower mean is better; nil without data
    var meanComparison: Comparison? {
        meanDelta.map { Comparison(delta: $0, higherIsBetter: false) }
    }
}

/// A reading of the Trace, ready to draw (`GlucoseStatsEngine.tracePoints`).
struct TracePoint: Sendable, Equatable {
    let time: Date
    let mgdl: Int
    /// the value drawn: `mgdl` kept inside the glucose axis
    let plotted: Int
    let band: GlucoseBand
}

/// A day of the Trace's day strip (`GlucoseStatsEngine.traceStripDay`).
struct TraceStripDay: Sendable, Equatable {
    /// the start of the calendar day
    let start: Date
    /// a reading starts in it (the previous evening's span running past midnight doesn't count)
    let hasReadings: Bool
    /// of its covered time, 0...1
    let inRangeFraction: Double
}

/// A day of the Daily view (`GlucoseStatsEngine.dailyDay`): its bar, and the numbers of its one-day summary
/// (`GlucoseStatsEngine.daySummary`, the Trace's of that day).
struct DailyDay: Sendable, Equatable, BandSharesProviding {
    /// A band's part of the day's bar, as fractions of the day's covered time: stacked from very low at the bottom up.
    typealias Segment = BandShares.Segment

    /// the whole calendar day (23, 24 or 25 h), also today's (computed up to E): its slot on the chart
    let day: DateInterval
    /// a reading starts in it (the previous evening's span running past midnight doesn't count): without, no bar and
    /// no numbers ("No readings")
    let hasReadings: Bool
    /// the nonzero bands, very low first; empty without readings
    let segments: [Segment]
    /// of the day's one-day summary
    let bandShares: BandShares
    let tirPercent: Int
    let titrPercent: Int
    let mean: Double?
    /// percent
    let cv: Double?
    let coveragePercent: Int
    /// very low + low
    let secondsBelowLow: Double
}

/// The additive numbers of readings pooled by weekday and hour (`GlucoseStatsEngine.weekdayHours`): the covered seconds
/// in each band of the request's bands, the time-weighted sum of the values (clamped as `GlucoseHistogram` clamps them,
/// so the mean is the histogram's), the readings starting in it.
struct WeekdayTally: Sendable, Equatable {
    /// by `GlucoseBand.rawValue`
    private(set) var bandSeconds: [Double] = Array(repeating: 0, count: GlucoseBand.allCases.count)
    /// Σ value × seconds
    private(set) var valueSeconds: Double = 0
    private(set) var seconds: Double = 0
    private(set) var readingCount = 0

    init() {}

    mutating func add(_ p: WeightedPoint, seconds: Double, startsInside: Bool, bands: StatsBands) {
        if seconds > 0 {
            let value = Int(p.mgdl)
            bandSeconds[bands.band(value).rawValue] += seconds
            valueSeconds += Double(Swift.min(Swift.max(value, 0), GlucoseHistogram.maxValue)) * seconds
            self.seconds += seconds
        }
        if startsInside {
            readingCount += 1
        }
    }

    static func + (l: Self, r: Self) -> Self {
        var sum = l
        for index in sum.bandSeconds.indices {
            sum.bandSeconds[index] += r.bandSeconds[index]
        }
        sum.valueSeconds += r.valueSeconds
        sum.seconds += r.seconds
        sum.readingCount += r.readingCount
        return sum
    }

    /// time-weighted
    var mean: Double? {
        seconds > 0 ? valueSeconds / seconds : nil
    }
}

/// A cell of By weekday (a weekday's hour, or its 3-hour block, over the period): its tally, and the days of the
/// weekday a reading starts in it.
struct WeekdayCell: Sendable, Equatable {
    var tally = WeekdayTally()
    var days = 0
}

/// By weekday's readings (`GlucoseStatsEngine.weekdayHours`): the period's whole weeks pooled by weekday and local
/// clock hour, as By hour pools them (a reading's span, clipped to the period, goes to the clock hour and the day it
/// starts in: the repeated hour of a DST change counts twice, the skipped one never).
struct WeekdayHours: Sendable, Equatable {
    /// the period's whole calendar days, oldest -> newest, the last one yesterday (`GlucoseStatsEngine.weekdayDays`)
    let days: [DateInterval]
    /// by `Calendar` weekday − 1 (Sunday 0), then by clock hour 0...23
    let hours: [[WeekdayCell]]
    /// the same by 3-hour block (00–03 … 21–24); its days are those a reading starts in in any of its hours
    let blocks: [[WeekdayCell]]
    /// by `Calendar` weekday − 1: the period's days of it (the same count for every weekday: its weeks)
    let dayCounts: [Int]
    /// by `Calendar` weekday − 1: those a reading starts in
    let daysWithData: [Int]
    /// the oldest reading starting in the period
    let firstReading: Date?
    /// the start of the first of `days` a reading starts in
    let firstDayWithData: Date?
    /// the columns shown: `Calendar` weekdays (1 Sunday … 7 Saturday), the workdays then the weekend, by the calendar
    /// the days and hours are of (`GlucoseStatsEngine.weekdayOrder`)
    let order: [Int]
    /// the weekend's weekdays, at the end of `order`; empty without a weekend
    let weekend: [Int]
    /// the store has a reading before the period (`GlucoseStatistics.weekdayHours` asks when the first day has none): a
    /// first day without readings is then no recording start
    var hasReadingsBefore = false

    /// the period's first day's start to its last day's end
    var window: DateInterval? {
        guard let first = days.first, let last = days.last else { return nil }
        return DateInterval(start: first.start, end: last.end)
    }
}

/// What By weekday's heatmap shows of a pool (`GlucoseStatsEngine.weekdayStep`).
enum WeekdayMetric: CaseIterable, Sendable, Hashable {
    /// the in-range band's percent
    case inRange
    /// very low + low
    case low
    /// the mean
    case mean
}

/// A pool of By weekday as shown (`GlucoseStatsEngine.weekdayPool`): a cell, a weekday, the same hours on the other days,
/// the workdays or the weekend.
struct WeekdayPool: Sendable, Equatable, BandSharesProviding {
    /// covered
    let seconds: Double
    /// readings starting in it
    let readingCount: Int
    /// the days a reading starts in it
    let days: Int
    /// of the covered time; all 0 without data
    let bandShares: BandShares
    /// very low + low: the sum of their percents (so the rows add up to it); nonzero below 1: "<1%"
    let lowPercent: Int
    let lowBelowOnePercent: Bool
    /// high + very high, as `lowPercent`
    let highPercent: Int
    let highBelowOnePercent: Bool
    /// mg/dL, time-weighted; nil without data
    let mean: Double?
    /// a cell with data, but under `GlucoseStatsEngine.weekdayFewHours` per hour of it: hatched, "take it as a hint"
    let isFew: Bool

    var hasData: Bool { seconds > 0 }
}
