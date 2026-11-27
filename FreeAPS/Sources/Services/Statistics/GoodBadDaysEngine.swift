import Foundation

/// Good vs bad days: the complete days of a period scored by GRI, the best third against the worst, each group's AGP,
/// the hours where the medians differ most, and the glucose rows (`GoodBadDaysEngine.result`).
struct GoodBadDaysResult: Equatable, Sendable {
    /// A complete day with enough CGM data, scored.
    struct ScoredDay: Equatable, Sendable {
        let key: StatsDayKey
        let day: DateInterval
        let gri: GlycemiaRiskIndex
        /// fraction of the covered time in `tirRange` (70...180, mmol: 70...181), 0...1
        let tir: Double
        /// fraction of the covered time below `tirRange` (below 70), 0...1
        let below70: Double
        /// time-weighted, mg/dL
        let mean: Double
        /// TIR of 00:00–06:00 by the clock; nil without readings then
        let nightTIR: Double?
        /// covered seconds / the day's length, 0...1
        let coverage: Double
        /// in the request's bands (the low/high settings), for the day's band bar
        let shares: BandShares
    }

    /// The days of one group and their AGP.
    struct Group: Equatable, Sendable {
        /// oldest -> newest
        let days: [ScoredDay]
        /// the group's AGP (`GlucoseStatsEngine.agp` of its days); empty for a group that isn't shown
        let bins: [AGPBin?]
        /// `bins` on the result's axis; the chart draws the 25–75 % band and the median
        let points: [AGPPlotPoint]

        /// enough days for its band and its rows
        var isShown: Bool { days.count >= GoodBadDaysEngine.minimumDays }
        /// few days: a shown group is marked as limited data
        var isLimited: Bool { days.count < GoodBadDaysEngine.unlimitedDays }
    }

    /// One group's values of a row: over its days with a value, linear interpolation between them.
    struct Values: Equatable, Sendable {
        let median: Double
        let p25: Double
        let p75: Double
        let n: Int
    }

    /// The glucose rows, in their fixed order (they describe the groups; they aren't factors).
    enum GlucoseRowID: CaseIterable, Sendable {
        /// GRI, 0...100
        case gri
        /// a fraction, 0...1
        case tir
        /// a fraction, 0...1
        case below70
        /// mg/dL
        case mean
        /// TIR of 00:00–06:00, a fraction, 0...1
        case nightTIR
    }

    struct GlucoseRow: Equatable, Sendable {
        let id: GlucoseRowID
        /// nil with fewer than `GoodBadDaysEngine.minimumDays` days with a value (or a group that isn't shown)
        let reference: Values?
        let compared: Values?

        var isShown: Bool { reference != nil && compared != nil }
    }

    /// A stretch of clock hours where the medians differ most.
    struct Highlight: Equatable, Sendable {
        /// minutes of the day, whole hours; the end passes 1440 when the stretch wraps past midnight (22:00–02:00 is
        /// 1320..<1560)
        let minutes: Range<Int>
        /// the mean of the stretch's medians (its bins where both groups have data), mg/dL
        let reference: Double
        let compared: Double
        /// Σ|Δ| of its hours, which ranks the stretches
        let weight: Double

        /// the compared group's median is higher here
        var isHigher: Bool { compared > reference }
    }

    /// The best third (the reference) against the worst (the compared group).
    struct Split: Equatable, Sendable {
        /// the best third
        let reference: Group
        /// the worst third
        let compared: Group
        /// the scored days in neither group: the third in between
        let leftOut: Int
        /// at most `GoodBadDaysEngine.highlightLimit`, the largest first; none unless both groups are shown
        let highlights: [Highlight]
        /// `GlucoseRowID.allCases`' order
        let glucoseRows: [GlucoseRow]

        /// both groups are shown: the chart overlays both, the rows show
        var isComparable: Bool { reference.isShown && compared.isShown }
    }

    let period: StatsPeriod?
    /// the first day's start to the last day's end
    let window: DateInterval
    /// one glucose axis for every group's profile (`GlucoseStatsEngine.agpAxis`)
    let axis: ClosedRange<Int>
    /// the days with enough CGM data
    let scored: Int
    /// the days left out with too little CGM data
    let unscored: Int
    let thirds: Split
    /// when a carb entry is a low treatment (`GoodBadDaysEngine.lowTreatmentTimes`), for the meal factors
    let lowTreatmentTimes: [DateInterval]
}

/// Good vs bad days' computation: pure, from the period's complete days (the cache's day aggregates) and the readings.
enum GoodBadDaysEngine {
    /// A day needs this CGM coverage (as `GlucoseSummary.isLimited` rounds it) to be scored: below it, a summary is
    /// limited data, and half a day's GRI would rank against whole ones.
    static let minimumCoveragePercent = 70
    /// A group needs this many days for its band and its rows, and a row this many days with a value in each group:
    /// fewer differ by chance too easily.
    static let minimumDays = 5
    /// A group with fewer days is marked as limited data, as an AGP under 14 days is.
    static let unlimitedDays = 10
    /// The night of the night TIR: 00:00 up to this clock minute (06:00).
    static let nightEndMinute = 6 * 60
    /// An hour is highlighted when its medians differ by at least this, mg/dL: smaller differences are noise.
    static let highlightFloor = 20.0
    /// … and by at least this share of the largest difference, so only the main stretches stand out.
    static let highlightShareOfLargest = 0.5
    /// The stretches kept, the largest first: the caption names the first.
    static let highlightLimit = 2
    /// A carb entry is a low treatment while glucose is below this, mg/dL …
    static let lowTreatmentBelow = 70
    /// … or within this after the low ends.
    static let lowTreatmentAfter: TimeInterval = .minutes(30)

    private typealias Result = GoodBadDaysResult
    private typealias ScoredDay = GoodBadDaysResult.ScoredDay

    /// The groups: the indices of `Profiles.bins`.
    private enum GroupIndex: Int, CaseIterable {
        case best
        case worst
    }

    // MARK: - Result

    /// Everything Good vs bad days shows, from the period's complete days and the readings.
    /// - Parameters:
    ///   - days: the period's complete days (`GlucoseStatsEngine.completeDays`), oldest -> newest, with their histograms
    ///     (the cache's `DayAggregate`s); the scores and groups read only these
    ///   - w: weighed, oldest -> newest, covering the days (the day before them too, for the low treatments of the
    ///     first morning); the profiles and the night TIRs read these
    ///   - bands: the request's, for the days' band bars and `tirRange`; never moves a day between groups
    static func result(
        period: StatsPeriod?,
        days: [DayAggregate],
        readings w: [WeightedPoint],
        bands: StatsBands,
        calendar: Calendar
    ) -> GoodBadDaysResult {
        let window = DateInterval(
            start: days.first?.day.start ?? .distantPast,
            end: Swift.max(days.first?.day.start ?? .distantPast, days.last?.day.end ?? .distantPast)
        )

        // the scores and groups, from the histograms
        let scoredDays = days.indices.compactMap { index -> (index: Int, day: ScoredDay)? in
            score(days[index], nightTIR: nil, bands: bands, calendar: calendar).map { (index, $0) }
        }
        let ranked = scoredDays.sorted { ranksBefore($0.day, $1.day) }
        let k = thirdSize(ranked.count)
        var members = Array(repeating: [GroupIndex](), count: days.count)
        for scoredDay in ranked.prefix(k) {
            members[scoredDay.index].append(.best)
        }
        for scoredDay in ranked.suffix(k) {
            members[scoredDay.index].append(.worst)
        }
        let shownGroups = Set(GroupIndex.allCases.filter { group in
            members.filter { $0.contains(group) }.count >= minimumDays
        })

        // the profiles and the night TIRs, in one pass over the readings
        let profiles = Self.profiles(
            w,
            days: days.map(\.day),
            groups: members.map { $0.filter(shownGroups.contains).map(\.rawValue) },
            groupCount: GroupIndex.allCases.count,
            nightRange: bands.tirRange,
            calendar: calendar
        )
        var withNight: [Int: ScoredDay] = [:]
        for (index, day) in scoredDays {
            withNight[index] = day.withNightTIR(profiles.nightTIR[index])
        }

        let axis = GlucoseStatsEngine.agpAxis(shownGroups.flatMap { profiles.bins[$0.rawValue] })
        func group(_ index: GroupIndex) -> Result.Group {
            let groupDays = members.indices.filter { members[$0].contains(index) }.compactMap { withNight[$0] }
            let bins = shownGroups.contains(index) ? profiles.bins[index.rawValue] : []
            return Result.Group(days: groupDays, bins: bins, points: GlucoseStatsEngine.agpPlotPoints(bins, axis: axis))
        }
        let groups = GroupIndex.allCases.map(group)
        let best = groups[GroupIndex.best.rawValue]
        let worst = groups[GroupIndex.worst.rawValue]
        let scored = scoredDays.count

        return GoodBadDaysResult(
            period: period,
            window: window,
            axis: axis,
            scored: scored,
            unscored: days.count - scored,
            thirds: split(best, worst, leftOut: scored - 2 * k),
            lowTreatmentTimes: lowTreatmentTimes(w)
        )
    }

    private static func split(_ reference: Result.Group, _ compared: Result.Group, leftOut: Int) -> Result.Split {
        let comparable = reference.isShown && compared.isShown
        return Result.Split(
            reference: reference,
            compared: compared,
            leftOut: leftOut,
            highlights: comparable ? highlights(reference: reference.bins, compared: compared.bins) : [],
            glucoseRows: Result.GlucoseRowID.allCases.map { id in
                Result.GlucoseRow(id: id, reference: values(id, of: reference), compared: values(id, of: compared))
            }
        )
    }

    // MARK: - Scores

    /// A day's score from its histogram; nil when its CGM coverage, rounded, is under `minimumCoveragePercent`.
    static func score(
        _ day: DayAggregate,
        nightTIR: Double?,
        bands: StatsBands,
        calendar: Calendar
    ) -> GoodBadDaysResult.ScoredDay? {
        let h = day.histogram
        let total = h.totalSeconds
        let coverage = day.day.duration > 0 ? Swift.min(total / day.day.duration, 1) : 0
        guard Int((coverage * 100).rounded()) >= minimumCoveragePercent,
              let gri = GlucoseStatsEngine.gri(h, bands: bands),
              let mean = h.mean
        else { return nil }
        let tir = bands.tirRange
        return ScoredDay(
            key: StatsDayKey(day.day.start, calendar),
            day: day.day,
            gri: gri,
            tir: h.seconds(in: tir) / total,
            below70: h.seconds(in: 0 ... tir.lowerBound - 1) / total,
            mean: mean,
            nightTIR: nightTIR,
            coverage: coverage,
            shares: BandShares(
                seconds: GlucoseBand.allCases.map { GlucoseStatsEngine.seconds(h, in: $0, bands: bands) },
                total: total
            )
        )
    }

    /// The thirds' order: the lower GRI, then the lower time below 70, the lower mean, the newer day.
    static func ranksBefore(_ a: GoodBadDaysResult.ScoredDay, _ b: GoodBadDaysResult.ScoredDay) -> Bool {
        if a.gri.value != b.gri.value { return a.gri.value < b.gri.value }
        if a.below70 != b.below70 { return a.below70 < b.below70 }
        if a.mean != b.mean { return a.mean < b.mean }
        return a.day.start > b.day.start
    }

    /// The days in each of the best and the worst third of `n` scored days: n / 3 rounded (14 -> 5, 13 -> 4).
    static func thirdSize(_ n: Int) -> Int {
        Int((Double(Swift.max(n, 0)) / 3).rounded())
    }

    // MARK: - Profiles

    /// The groups' clock histograms and the days' night TIRs, in one pass over the readings.
    struct Profiles: Equatable, Sendable {
        /// by group, `GlucoseStatsEngine.agp`'s bins of its days (all nil for a group without days)
        let bins: [[AGPBin?]]
        /// by day: the share of 00:00–06:00 (by the clock) in `nightRange`; nil without readings then
        let nightTIR: [Double?]
    }

    /// Each reading's overlap with each day goes to the groups that day is in, at the reading's clock time, as
    /// `GlucoseStatsEngine.agp(_:calendar:days:)` adds it: a reading across midnight into a day of another group gives
    /// that day its part. The night TIR counts the readings whose clock time is before `nightEndMinute`.
    /// - Parameters:
    ///   - days: oldest -> newest, not overlapping
    ///   - groups: by day, the indices of the groups it is in (below `groupCount`)
    static func profiles(
        _ w: [WeightedPoint],
        days: [DateInterval],
        groups: [[Int]],
        groupCount: Int,
        nightRange: ClosedRange<Int>,
        calendar: Calendar
    ) -> Profiles {
        let binMinutes = GlucoseStatsEngine.agpBinMinutes
        let binCount = StatsClock.minutesPerDay / binMinutes
        let used = Set(groups.joined())
        // only the groups with days get histograms
        var clock = (0 ..< groupCount).map { group -> [GlucoseHistogram] in
            used.contains(group) ? Array(repeating: GlucoseHistogram(), count: binCount) : []
        }
        var nightIn = Array(repeating: 0.0, count: days.count)
        var nightTotal = Array(repeating: 0.0, count: days.count)
        GlucoseStatsEngine.forEachOverlap(w, days: days, calendar: calendar) { point, minute, day, seconds, startsInside in
            if minute < nightEndMinute {
                nightTotal[day] += seconds
                if nightRange.contains(Int(point.mgdl)) {
                    nightIn[day] += seconds
                }
            }
            guard day < groups.count else { return }
            let bin = Swift.min(minute / binMinutes, binCount - 1)
            for group in groups[day] {
                clock[group][bin].add(point, seconds: seconds, startsInside: startsInside)
            }
        }
        return Profiles(
            bins: clock.map { histograms -> [AGPBin?] in
                histograms.isEmpty
                    ? Array(repeating: nil, count: binCount)
                    : GlucoseStatsEngine.agpBins(histograms, binMinutes: binMinutes, poolNeighbours: 1)
            },
            nightTIR: days.indices.map { index -> Double? in
                nightTotal[index] > 0 ? nightIn[index] / nightTotal[index] : nil
            }
        )
    }

    // MARK: - Highlights

    /// Per clock hour, Δ: the mean over its bins where both groups have data of `p50(compared) − p50(reference)`;
    /// nil for an hour without such a bin.
    static func hourDeltas(reference: [AGPBin?], compared: [AGPBin?]) -> [Double?] {
        var sums = Array(repeating: 0.0, count: 24)
        var counts = Array(repeating: 0, count: 24)
        for (r, c) in zip(reference, compared) {
            guard let r, let c else { continue }
            let hour = Swift.min(Swift.max(r.startMinute / 60, 0), 23)
            sums[hour] += c.p50 - r.p50
            counts[hour] += 1
        }
        return (0 ..< 24).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
    }

    /// The hours where the medians differ most: |Δ| (`hourDeltas`) at least `highlightFloor` and at least
    /// `highlightShareOfLargest` of the largest |Δ|. Adjacent hours with Δ of one sign are one stretch, across midnight
    /// too; at most `highlightLimit` stretches, the largest Σ|Δ| first. Equal ones: the longer first, then the earlier
    /// start in the drawn day (00:00 to 24:00; a stretch across midnight starts at its evening hour).
    static func highlights(reference: [AGPBin?], compared: [AGPBin?]) -> [GoodBadDaysResult.Highlight] {
        let deltas = hourDeltas(reference: reference, compared: compared)
        let largest = deltas.compactMap { $0.map(abs) }.max() ?? 0
        let threshold = Swift.max(highlightFloor, largest * highlightShareOfLargest)

        // runs of hours: start, length, Σ|Δ|, the sign
        var runs: [(start: Int, length: Int, weight: Double, isHigher: Bool)] = []
        for hour in 0 ..< 24 {
            guard let delta = deltas[hour], abs(delta) >= threshold else { continue }
            let isHigher = delta > 0
            if let last = runs.last, last.start + last.length == hour, last.isHigher == isHigher {
                runs[runs.count - 1].length += 1
                runs[runs.count - 1].weight += abs(delta)
            } else {
                runs.append((hour, 1, abs(delta), isHigher))
            }
        }
        // a run ending at midnight continues into one starting there
        if runs.count > 1, let first = runs.first, let last = runs.last, first.start == 0, last.start + last.length == 24,
           first.isHigher == last.isHigher
        {
            runs[0] = (last.start, last.length + first.length, last.weight + first.weight, first.isHigher)
            runs.removeLast()
        }

        return runs
            .sorted { a, b in
                if a.weight != b.weight { return a.weight > b.weight }
                if a.length != b.length { return a.length > b.length }
                return a.start < b.start
            }
            .prefix(highlightLimit)
            .map { run in
                let minutes = run.start * 60 ..< (run.start + run.length) * 60
                var referenceSum = 0.0
                var comparedSum = 0.0
                var count = 0
                for (r, c) in zip(reference, compared) {
                    guard let r, let c else { continue }
                    let minute = r.startMinute
                    guard minutes.contains(minute) || minutes.contains(minute + StatsClock.minutesPerDay) else { continue }
                    referenceSum += r.p50
                    comparedSum += c.p50
                    count += 1
                }
                return GoodBadDaysResult.Highlight(
                    minutes: minutes,
                    reference: count > 0 ? referenceSum / Double(count) : 0,
                    compared: count > 0 ? comparedSum / Double(count) : 0,
                    weight: run.weight
                )
            }
    }

    // MARK: - Rows

    private static func values(_ id: GoodBadDaysResult.GlucoseRowID, of group: Result.Group) -> Result.Values? {
        guard group.isShown else { return nil }
        return values(group.days.compactMap { day -> Double? in
            switch id {
            case .gri: return day.gri.value
            case .tir: return day.tir
            case .below70: return day.below70
            case .mean: return day.mean
            case .nightTIR: return day.nightTIR
            }
        })
    }

    /// The median and the IQR of a group's values (linear interpolation between the sorted values); nil with fewer
    /// than `minimumDays` values.
    static func values(_ values: [Double]) -> GoodBadDaysResult.Values? {
        guard values.count >= minimumDays else { return nil }
        let sorted = values.sorted()
        return GoodBadDaysResult.Values(
            median: quantile(sorted, 0.5),
            p25: quantile(sorted, 0.25),
            p75: quantile(sorted, 0.75),
            n: sorted.count
        )
    }

    /// The `p` quantile of sorted values, at position `(n − 1) × p` with linear interpolation; 0 without values.
    static func quantile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        let position = Double(sorted.count - 1) * Swift.min(Swift.max(p, 0), 1)
        let lower = Int(position.rounded(.down))
        guard lower + 1 < sorted.count else { return sorted.last ?? first }
        let fraction = position - Double(lower)
        return sorted[lower] + fraction * (sorted[lower + 1] - sorted[lower])
    }

    // MARK: - Low treatments

    /// When a carb entry counts as a low treatment, oldest first: during a low (the spans of the readings below
    /// `lowTreatmentBelow`, touching ones as one low) or up to `lowTreatmentAfter` after it ends; overlapping times
    /// merged. The meal factors leave out the entries at these times (`isLowTreatment`).
    static func lowTreatmentTimes(_ w: [WeightedPoint]) -> [DateInterval] {
        let lows = StatsIntervals.mergedDroppingEmpty(
            w.filter { Int($0.mgdl) < lowTreatmentBelow }.map { DateInterval(start: $0.time, end: $0.end) }
        )
        return StatsIntervals.mergedKeepingEmpty(lows.map { low in
            DateInterval(start: low.start, end: low.end.addingTimeInterval(lowTreatmentAfter))
        })
    }

    /// An entry at `date` is a low treatment: inside one of `lowTreatmentTimes`, both ends included.
    static func isLowTreatment(_ date: Date, in times: [DateInterval]) -> Bool {
        let index = times.partitionIndex { $0.end >= date }
        return index < times.count && times[index].start <= date
    }
}

private extension GoodBadDaysResult.ScoredDay {
    func withNightTIR(_ nightTIR: Double?) -> Self {
        Self(
            key: key,
            day: day,
            gri: gri,
            tir: tir,
            below70: below70,
            mean: mean,
            nightTIR: nightTIR,
            coverage: coverage,
            shares: shares
        )
    }
}

// MARK: - Factors

/// A row of "What was different on those days": one value per day, in the fixed, grouped order of the cases (not
/// sorted by the size of a difference).
enum GoodBadFactor: CaseIterable, Sendable {
    /// g, the day's carbs
    case carbs
    /// g, the meal (entries within `GoodBadDaysEngine.mealJoinWindow` of its first) with the most carbs
    case largestMeal
    /// the meals with at least `GoodBadDaysEngine.mealMinimumCarbs`
    case meals
    /// the clock minute the last of those meals started
    case lastMeal
    /// g, in the entries from `GoodBadDaysEngine.lateCarbsFromMinute` to midnight
    case lateCarbs
    /// g; only for someone who logs them (`MealStatsEngine.logsFatOrProtein`)
    case fatAndProtein
    /// g, the day before's late carbs
    case lateCarbsEveningBefore
    /// U, `DayInsulin.scaledTotal`
    case totalInsulin
    /// bolus / (basal + SMB + bolus), 0...1
    case bolusShare
    /// of the meals of at least `GoodBadDaysEngine.bolusMealMinimumCarbs`, those without a bolus in time
    /// (`GoodBadDaysEngine.lateBolusShare`), 0...1
    case lateBolus
    /// U
    case smb
    /// of the covered time, 0...1
    case zeroBasal
    /// `DayInsulin.basalVsScheduled`
    case basalVsScheduled
    /// the wear day (1-based) at the day's noon
    case siteDay
    /// an activation in the day: 1, else 0
    case siteChange
    /// the CGM sensor's day (1-based) at the day's noon (`CGMStatsEngine.sensorDay`)
    case sensorDay
    /// a sensor began in the day: 1, else 0
    case sensorChange
    /// the CGM readings' slots the loop succeeded in, 0...1
    case loopSuccess
    /// `GoodBadDaysResult.ScoredDay.coverage`
    case cgmCoverage
    /// on the locale's weekend: 1, else 0
    case weekend
    /// the day before's GRI, when it was scored
    case previousGRI

    /// The groups of rows, in their order.
    enum Section: CaseIterable, Sendable {
        case meals
        case insulin
        /// "What you and the loop did": they follow glucose
        case loopResponse
        case site
        case cgmSensor
        case loopAndCGM
        case calendar
    }

    /// What a value is, for its formatting.
    enum Kind: Sendable {
        case grams
        case units
        /// 0...1
        case fraction
        case count
        /// 0..<1440
        case minuteOfDay
        case wearDay
        /// 1 or 0: the rows show the days with it
        case yesNo
        case gri
    }

    /// Where a row's values come from: a failed read marks only its rows unavailable.
    enum Source: Sendable {
        case meals
        case insulin
        case sessions
        /// the CGM sessions (`CGMSessionStore.sessions`, which logs a failed read and gives none)
        case cgmSessions
        case loops
        case glucose
    }

    var section: Section {
        switch self {
        case .carbs,
             .fatAndProtein,
             .largestMeal,
             .lastMeal,
             .lateCarbs,
             .lateCarbsEveningBefore,
             .meals: return .meals
        case .bolusShare,
             .lateBolus,
             .totalInsulin: return .insulin
        case .basalVsScheduled,
             .smb,
             .zeroBasal: return .loopResponse
        case .siteChange,
             .siteDay: return .site
        case .sensorChange,
             .sensorDay: return .cgmSensor
        case .cgmCoverage,
             .loopSuccess: return .loopAndCGM
        case .previousGRI,
             .weekend: return .calendar
        }
    }

    var kind: Kind {
        switch self {
        case .carbs,
             .fatAndProtein,
             .largestMeal,
             .lateCarbs,
             .lateCarbsEveningBefore: return .grams
        case .meals: return .count
        case .lastMeal: return .minuteOfDay
        case .smb,
             .totalInsulin: return .units
        case .basalVsScheduled,
             .bolusShare,
             .cgmCoverage,
             .lateBolus,
             .loopSuccess,
             .zeroBasal: return .fraction
        case .sensorDay,
             .siteDay: return .wearDay
        case .sensorChange,
             .siteChange,
             .weekend: return .yesNo
        case .previousGRI: return .gri
        }
    }

    var source: Source {
        switch section {
        case .meals: return .meals
        case .insulin,
             .loopResponse: return .insulin
        case .site: return .sessions
        case .cgmSensor: return .cgmSessions
        case .loopAndCGM: return self == .loopSuccess ? .loops : .glucose
        case .calendar: return .glucose
        }
    }
}

/// What the factor rows read besides the glucose (`GoodBadDaysEngine.factors`); nil where a read failed.
struct GoodBadDaysFactorInput: Sendable {
    /// the entries of the period and the day before it, any order (duplicates too, `MealStatsEngine.clean`)
    var meals: [MealPoint]?
    /// an entry of the last 90 days has fat or protein (`MealStatsEngine.logsFatOrProtein`): the fat + protein row
    var logsFatOrProtein = false
    /// the insulin days (`InsulinStatsService.days`) of the period and the day before it (the boluses before its first
    /// day's meals), any order
    var insulin: [DayInsulin]?
    /// the pump sessions (`PatchStatsEngine.sessions`)
    var sessions: [PatchSession]?
    /// the CGM sensors of the effective sessions (recorded, entered, backfilled: `Stat.Provider.goodBadDaysSensors`)
    var sensors: [GoodBadDaysSensor] = []
    /// the loop's slots by day (`HomeLoopStats.Day.slots`)
    var loops: [StatsDayKey: HomeLoopStats.Slots]?
    /// every scored day's GRI, the day before the period's too (`GoodBadDaysGlucose.gri`)
    var gri: [StatsDayKey: Double] = [:]
}

/// A CGM sensor for the sensor rows: its sessions (a CGM switched away and back is the same sensor), and its own start
/// (`CGMSessionRecord.sensorStart`: the wear day counts from it, also when its readings began later, at a switch to it).
struct GoodBadDaysSensor: Equatable, Sendable {
    /// nil when the CGM gave none (an entered session without one, a backfilled one, a sensorless CGM such as
    /// Nightscout or xDrip): the sensor isn't identified, a sensor change could be anywhere in its sessions
    let start: Date?
    /// `[start, end)`, an open one's to the distant future
    let sessions: [DateInterval]
}

/// A factor row: both groups' median and IQR over their days with a value.
struct GoodBadDaysFactorRow: Equatable, Sendable {
    let id: GoodBadFactor
    /// nil with fewer than `GoodBadDaysEngine.minimumDays` days with a value
    let reference: GoodBadDaysResult.Values?
    let compared: GoodBadDaysResult.Values?
    /// a yes/no row: the days with it, of the values' n
    let referenceYes: Int
    let comparedYes: Int
    /// a meal row: both groups' days without a meal entry (no value, never 0 g); the evening before's: those whose day
    /// before had none
    let notLogged: Int
    /// its data couldn't be read
    let unavailable: Bool

    /// 5 days with a value in each group
    var isShown: Bool { reference != nil && compared != nil }
}

extension GoodBadDaysEngine {
    /// Entries starting within this of a meal's first entry are that meal (a main and its dessert entered apart).
    static let mealJoinWindow: TimeInterval = .minutes(30)
    /// A meal counts for "Meals" and "Last meal" with at least this, g: a few grams are a snack or a correction.
    static let mealMinimumCarbs = 5.0
    /// "Late carbs": the entries from this clock minute (21:00) to midnight, the evening's that act overnight.
    static let lateCarbsFromMinute = 21 * 60
    /// The site day and the sensor day are those at this clock hour: the day's middle.
    static let siteDayHour = 12
    /// "Meals with a late or no bolus" counts the meals of at least this, g: smaller ones often get none on purpose.
    static let bolusMealMinimumCarbs = 10.0
    /// A meal's bolus can come this long before its start: a pre-bolus.
    static let bolusLeadTime: TimeInterval = .minutes(30)
    /// A meal's bolus more than this after its start is late: the carbs are absorbing by then.
    static let bolusLateAfter: TimeInterval = .minutes(15)

    /// The thirds' factor rows, in `GoodBadFactor`'s order; none without both groups shown. Low treatments
    /// (`lowTreatmentTimes`) are left out of every meal row; a day without a meal entry has no meal values.
    static func factors(
        _ result: GoodBadDaysResult,
        input: GoodBadDaysFactorInput,
        calendar: Calendar
    ) -> [GoodBadDaysFactorRow] {
        let split = result.thirds
        guard split.isComparable else { return [] }
        let values = dayValues(
            split.reference.days + split.compared.days,
            input: input,
            lowTreatments: result.lowTreatmentTimes,
            calendar: calendar
        )
        return GoodBadFactor.allCases.compactMap { factor in
            row(factor, reference: split.reference.days, compared: split.compared.days, values: values, input: input)
        }
    }

    /// A day's values; `mealsLogged` (a meal entry, low treatments apart) and `previousMealsLogged` (the day before's)
    /// nil when the meals couldn't be read.
    struct FactorDay: Equatable, Sendable {
        var values: [GoodBadFactor: Double] = [:]
        var mealsLogged: Bool?
        var previousMealsLogged: Bool?
    }

    private static func row(
        _ factor: GoodBadFactor,
        reference: [GoodBadDaysResult.ScoredDay],
        compared: [GoodBadDaysResult.ScoredDay],
        values: [StatsDayKey: FactorDay],
        input: GoodBadDaysFactorInput
    ) -> GoodBadDaysFactorRow? {
        if factor == .fatAndProtein, !input.logsFatOrProtein {
            return nil
        }
        let unavailable: Bool
        switch factor.source {
        case .meals: unavailable = input.meals == nil
        case .insulin: unavailable = input.insulin == nil
        case .sessions: unavailable = input.sessions == nil
        case .cgmSessions: unavailable = false
        case .loops: unavailable = input.loops == nil
        case .glucose: unavailable = false
        }
        func group(_ days: [GoodBadDaysResult.ScoredDay]) -> (values: GoodBadDaysResult.Values?, yes: Int) {
            let dayValues = days.compactMap { values[$0.key]?.values[factor] }
            return (self.values(dayValues), dayValues.filter { $0 > 0 }.count)
        }
        let none: (values: GoodBadDaysResult.Values?, yes: Int) = (nil, 0)
        let referenceGroup = unavailable ? none : group(reference)
        let comparedGroup = unavailable ? none : group(compared)
        let notLogged: Int
        switch factor {
        case .lateCarbsEveningBefore:
            notLogged = (reference + compared).filter { values[$0.key]?.previousMealsLogged == false }.count
        default:
            notLogged = factor.section == .meals
                ? (reference + compared).filter { values[$0.key]?.mealsLogged == false }.count
                : 0
        }
        return GoodBadDaysFactorRow(
            id: factor,
            reference: referenceGroup.values,
            compared: comparedGroup.values,
            referenceYes: factor.kind == .yesNo ? referenceGroup.yes : 0,
            comparedYes: factor.kind == .yesNo ? comparedGroup.yes : 0,
            notLogged: notLogged,
            unavailable: unavailable
        )
    }

    /// Every day's values, by its key.
    static func dayValues(
        _ days: [GoodBadDaysResult.ScoredDay],
        input: GoodBadDaysFactorInput,
        lowTreatments: [DateInterval],
        calendar: Calendar
    ) -> [StatsDayKey: FactorDay] {
        // the meal entries, low treatments left out, oldest -> newest
        let entries = input.meals.map { points in
            MealStatsEngine.clean(points).filter { $0.carbs <= 0 || !isLowTreatment($0.actualDate, in: lowTreatments) }
        }
        let insulin = input.insulin.map { days in
            Dictionary(
                days.filter { !$0.isToday && $0.coverageFraction >= InsulinStatsEngine.headlineCoverage }
                    .map { (StatsDayKey($0.day.start, calendar), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        // the boluses that aren't SMBs (a past day keeps only those), oldest -> newest, and the days read (contiguous)
        let pastInsulin = input.insulin?.filter { !$0.isToday } ?? []
        let boluses = pastInsulin.flatMap(\.boluses).filter { !$0.isSMB && $0.units > 0 }.map(\.date).sorted()
        let bolusesRead = pastInsulin.isEmpty ? nil : DateInterval(
            start: pastInsulin.map(\.day.start).min() ?? .distantPast,
            end: pastInsulin.map(\.day.end).max() ?? .distantPast
        )
        let sessions = input.sessions?.filter(\.isActivationKnown)
        // each CGM session with its sensor's start (nil: not identified), by start
        let sensorSessions = input.sensors.flatMap { sensor in sensor.sessions.map { (interval: $0, start: sensor.start) } }
            .sorted { $0.interval.start < $1.interval.start }
        let sensorStarts = input.sensors.compactMap(\.start)
        let weekend = Set(GlucoseStatsEngine.weekend(calendar: calendar, around: days.map(\.day.start).min() ?? Date()))

        var result: [StatsDayKey: FactorDay] = [:]
        for day in days {
            var factorDay = FactorDay()
            func set(_ factor: GoodBadFactor, _ value: Double?) {
                if let value {
                    factorDay.values[factor] = value
                }
            }
            let previousStart = StatsClock.dayStart(1, before: day.day.start, calendar: calendar) ?? day.day.start
            let previous = DateInterval(start: previousStart, end: day.day.start)

            var meals: MealFacts?
            if let entries {
                meals = mealFacts(entries, in: day.day, calendar: calendar)
                factorDay.mealsLogged = meals != nil
                if let meals {
                    set(.carbs, meals.carbs)
                    set(.largestMeal, meals.largest)
                    set(.meals, Double(meals.count))
                    set(.lastMeal, meals.lastStart.map { Double($0) })
                    set(.lateCarbs, meals.late)
                    set(.fatAndProtein, meals.fatAndProtein)
                }
                let previousMeals = mealFacts(entries, in: previous, calendar: calendar)
                factorDay.previousMealsLogged = previousMeals != nil
                set(.lateCarbsEveningBefore, previousMeals?.late)
            }

            if let pump = insulin?[day.key] {
                let delivered = pump.basal + pump.smb + pump.bolus
                set(.totalInsulin, pump.scaledTotal)
                set(.bolusShare, delivered > 0 ? pump.bolus / delivered : nil)
                set(.smb, pump.smb)
                set(.zeroBasal, pump.coveredSeconds > 0 ? pump.zeroBasalSeconds / pump.coveredSeconds : nil)
                set(.basalVsScheduled, pump.basalVsScheduled)
                if let meals, let bolusesRead {
                    set(.lateBolus, lateBolusShare(meals.bolusMealStarts, boluses: boluses, read: bolusesRead))
                }
            }

            let noon = calendar.date(bySettingHour: siteDayHour, minute: 0, second: 0, of: day.day.start) ?? day.day.start
            if let sessions {
                let worn = sessions.first { $0.isWearCounted && $0.activation <= noon && noon < $0.end }
                set(.siteDay, worn.map { Double(PatchStatsEngine.dayIndex(at: noon.timeIntervalSince($0.activation)) + 1) })
                // a day without a session in it says nothing about a change
                let inDay = sessions.filter { $0.activation < day.day.end && $0.end > day.day.start }
                if inDay.isNotEmpty {
                    set(.siteChange, inDay.contains { day.day.start <= $0.activation && $0.activation < day.day.end } ? 1 : 0)
                }
            }

            // the sensor rows only on a day whose sessions are all of identified sensors: none (Unknown) or one without a
            // sensor start says nothing about a change, nor about the sensor at noon
            let inDay = sensorSessions.filter { $0.interval.start < day.day.end && $0.interval.end > day.day.start }
            if inDay.isNotEmpty, inDay.allSatisfy({ $0.start != nil }) {
                // the sensor at noon: the latest starting session holding it; its wear day
                let holding = inDay.last { $0.interval.start <= noon && noon < $0.interval.end }
                set(
                    .sensorDay,
                    holding?.start.flatMap { CGMStatsEngine.sensorDay(of: noon, sensorStarts: [$0]) }.map { Double($0) }
                )
                // a sensor started in the day (a switch to one already running isn't a change)
                set(.sensorChange, sensorStarts.contains { day.day.start <= $0 && $0 < day.day.end } ? 1 : 0)
            }

            if let slots = input.loops?[day.key] {
                // a slot is a CGM reading: none, no share
                let readings = Double(slots.count)
                set(.loopSuccess, readings > 0 ? Double(slots.successes) / readings : nil)
            }
            set(.cgmCoverage, day.coverage)
            set(.weekend, weekend.contains(calendar.component(.weekday, from: day.day.start)) ? 1 : 0)
            set(.previousGRI, input.gri[StatsDayKey(previousStart, calendar)])
            result[day.key] = factorDay
        }
        return result
    }

    /// A day's meals (`entries` oldest -> newest, low treatments left out); nil without an entry: not logged.
    struct MealFacts: Equatable, Sendable {
        /// g
        let carbs: Double
        let largest: Double
        /// the meals of at least `mealMinimumCarbs`
        let count: Int
        /// the last of those meals' start, its clock minute; nil without one
        let lastStart: Int?
        /// g, from `lateCarbsFromMinute`
        let late: Double
        let fatAndProtein: Double
        /// the starts of the meals of at least `bolusMealMinimumCarbs`, oldest -> newest
        let bolusMealStarts: [Date]
    }

    static func mealFacts(_ entries: [MealPoint], in day: DateInterval, calendar: Calendar) -> MealFacts? {
        let first = entries.partitionIndex { $0.actualDate >= day.start }
        let end = entries.partitionIndex { $0.actualDate >= day.end }
        guard first < end else { return nil }
        let inDay = entries[first ..< end]
        // a meal: its start, its carbs
        var meals: [(start: Date, carbs: Double)] = []
        for entry in inDay {
            if let last = meals.last, entry.actualDate.timeIntervalSince(last.start) <= mealJoinWindow {
                meals[meals.count - 1].carbs += entry.carbs
            } else {
                meals.append((entry.actualDate, entry.carbs))
            }
        }
        let counted = meals.filter { $0.carbs >= mealMinimumCarbs }
        return MealFacts(
            carbs: inDay.reduce(0) { $0 + $1.carbs },
            largest: meals.map(\.carbs).max() ?? 0,
            count: counted.count,
            lastStart: counted.last.map { StatsClock.minuteOfDay($0.start, in: calendar.timeZone) },
            late: inDay.filter { StatsClock.minuteOfDay($0.actualDate, in: calendar.timeZone) >= lateCarbsFromMinute }
                .reduce(0) { $0 + $1.carbs },
            fatAndProtein: inDay.reduce(0) { $0 + $1.fat + $1.protein },
            bolusMealStarts: meals.filter { $0.carbs >= bolusMealMinimumCarbs }.map(\.start)
        )
    }

    /// The share of the meals whose first bolus (not an SMB) in [start − `bolusLeadTime`, start + 60 min] came more
    /// than `bolusLateAfter` after the start, or that had none there: the meals without a bolus from `bolusLeadTime`
    /// before the start to `bolusLateAfter` after it (the window's end only tells late from none, which count the
    /// same). Nothing links a meal to its bolus but the time (`MealsView`'s Today: no bolus column). A meal whose
    /// [start − `bolusLeadTime`, start + `bolusLateAfter`] runs out of the days `read` counts only with a bolus in time:
    /// the one it lacks could be outside them. nil without a meal counted.
    /// - Parameters:
    ///   - starts: the meals' starts
    ///   - boluses: ascending
    static func lateBolusShare(_ starts: [Date], boluses: [Date], read: DateInterval) -> Double? {
        var counted = 0
        var late = 0
        for start in starts {
            let from = start.addingTimeInterval(-bolusLeadTime)
            let until = start.addingTimeInterval(bolusLateAfter)
            let first = boluses.partitionIndex { $0 >= from }
            if first < boluses.count, boluses[first] <= until {
                counted += 1
            } else if read.start <= from, until < read.end {
                counted += 1
                late += 1
            }
        }
        return counted > 0 ? Double(late) / Double(counted) : nil
    }
}
