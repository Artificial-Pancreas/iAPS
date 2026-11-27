import Foundation

// MARK: - The CGMs to name

/// A CGM the user can name for Unknown readings: a recorded session's, or one iAPS knows
/// (`KnownPlugins.cgmIdForStatistics`). An entered session takes its fields (`CGMUnknownInference.sessions`).
struct CGMChoice: Sendable, Hashable, Identifiable {
    enum Family: Sendable, Hashable {
        /// FreeStyle Libre: 1-minute readings possible, 14–15 days
        case libre
        /// Dexcom: 5-minute readings, 10 days (the G7 with its 12 h grace)
        case dexcom
        case other
    }

    /// `KnownPlugins.cgmIdForStatistics` (the source app for AppGroup)
    let cgmId: String
    let name: String
    /// the manager's `pluginIdentifier`
    let plugin: String
    /// from the sensor start, as a recorded session's (`KnownPlugins.cgmExpirationByPluginIdentifier`); nil if unknown
    let expectedLife: TimeInterval?
    /// from the sensor start to its first reading; nil when not known (no sensor start is inferred from a gap)
    let warmup: TimeInterval?
    let family: Family
    /// a recorded session's CGM
    let isRecorded: Bool

    var id: String { cgmId }

    /// The CGMs iAPS knows, by `KnownPlugins.cgmIdForStatistics`: their manager's plugin and title, the life a recorded
    /// session gets, the warm-up.
    static let known: [CGMChoice] = [
        CGMChoice(
            cgmId: "dexcomG7", name: "Dexcom G7", plugin: "G7CGMManager",
            expectedLife: .days(10.5), warmup: .minutes(30), family: .dexcom, isRecorded: false
        ),
        CGMChoice(
            cgmId: "dexcomG6", name: "Dexcom G6", plugin: "DexG6Transmitter",
            expectedLife: .days(10), warmup: .hours(2), family: .dexcom, isRecorded: false
        ),
        CGMChoice(
            cgmId: "dexcomG5", name: "Dexcom G5", plugin: "DexG5Transmitter",
            expectedLife: nil, warmup: .hours(2), family: .dexcom, isRecorded: false
        ),
        CGMChoice(
            cgmId: "libre3", name: "FreeStyle Libre 3 / 3+", plugin: "LibreLoopCGMManager",
            expectedLife: .days(14), warmup: .hours(1), family: .libre, isRecorded: false
        ),
        CGMChoice(
            cgmId: "libreTransmitter", name: "FreeStyle Libre", plugin: "LibreTransmitterManagerV3",
            expectedLife: .days(14), warmup: .hours(1), family: .libre, isRecorded: false
        ),
        CGMChoice(
            cgmId: "eversense", name: "Eversense", plugin: "EversenseKit",
            expectedLife: .days(180), warmup: nil, family: .other, isRecorded: false
        ),
        CGMChoice(
            cgmId: "enlite", name: "Medtronic Enlite", plugin: "Minimed500",
            expectedLife: .days(6), warmup: .hours(2), family: .other, isRecorded: false
        ),
        CGMChoice(
            cgmId: "xdrip", name: "xDrip4iOS", plugin: "AppGroupCGM",
            expectedLife: nil, warmup: nil, family: .other, isRecorded: false
        ),
        CGMChoice(
            cgmId: "glucoseDirect", name: "Glucose Direct", plugin: "AppGroupCGM",
            expectedLife: nil, warmup: nil, family: .other, isRecorded: false
        ),
        CGMChoice(
            cgmId: "nightscout", name: "Nightscout", plugin: "NightscoutRemoteCGM",
            expectedLife: nil, warmup: nil, family: .other, isRecorded: false
        ),
        CGMChoice(
            cgmId: "simulator", name: "CGM Simulator", plugin: "MockCGMManager",
            expectedLife: nil, warmup: nil, family: .other, isRecorded: false
        )
    ]

    /// The choices: the recorded sessions' CGMs first (newest first, each once, by its newest session's name, plugin
    /// and life; the known one's warm-up and family), then the known ones not among them. A session without a CGM id
    /// (AppGroup before its source is known) names none.
    static func choices(recorded sessions: [CGMSessionRecord]) -> [CGMChoice] {
        var choices: [CGMChoice] = []
        for session in CGMSessionRules.ordered(sessions).reversed() where session.source == .recorded {
            guard let cgmId = session.cgmId, !choices.contains(where: { $0.cgmId == cgmId }) else { continue }
            let known = Self.known.first { $0.cgmId == cgmId }
            choices.append(CGMChoice(
                cgmId: cgmId,
                name: session.name.isEmpty ? known?.name ?? cgmId : session.name,
                plugin: session.plugin,
                expectedLife: session.expectedLife ?? known?.expectedLife,
                warmup: known?.warmup,
                family: known?.family ?? .other,
                isRecorded: true
            ))
        }
        return choices + known.filter { known in !choices.contains { $0.cgmId == known.cgmId } }
    }
}

// MARK: - The probable sensors

/// A run of Unknown readings that is probably one sensor (`CGMUnknownInference.sensors`), with the CGM it suggests.
struct CGMProbableSensor: Sendable, Equatable, Identifiable {
    enum Confidence: Sendable, Equatable {
        /// only a Libre reads every minute
        case likely
        /// a Libre 2 can read every 5 minutes, a G6 can be restarted past 10 days, a sensor can stop early
        case possible
    }

    enum Reason: Sendable, Equatable {
        /// 1-minute readings
        case oneMinute
        /// longer than any Dexcom (`CGMUnknownInference.libreLength`)
        case longerThanADexcom
        /// about 10 days of 5-minute readings (`CGMUnknownInference.dexcomLength`)
        case dexcomLength
        /// none of its own: the neighbouring sensor's with the same cadence
        case neighbour
    }

    struct Suggestion: Sendable, Equatable {
        let cgmId: String
        let confidence: Confidence
        let reason: Reason
    }

    /// its first reading (unique among the sensors)
    var id: Date { first }
    let first: Date
    let last: Date
    let readings: Int
    /// the median distance between its readings, s
    let cadence: TimeInterval
    /// from the reading before it (any CGM's, a recorded one's too) to its first; nil without one
    let gapBefore: TimeInterval?
    var suggestion: Suggestion?
    /// its first reading is at the start of the readings read (the 90 days): it began earlier, its start isn't known
    var isCut = false

    var length: TimeInterval { last.timeIntervalSince(first) }
    /// `GlucoseStatsEngine.oneMinuteMedianLimit`
    var isOneMinute: Bool { cadence <= GlucoseStatsEngine.oneMinuteMedianLimit }
}

/// The user's answer to "Which CGM was this?" for the Unknown readings.
enum CGMUnknownAnswer: Sendable, Equatable {
    /// one CGM for every Unknown reading
    case one(CGMChoice)
    /// one CGM until the date, another from it
    case switched(at: Date, before: CGMChoice, after: CGMChoice)
    /// by sensor (`CGMProbableSensor.id`); a sensor without one stays Unknown
    case bySensor([Date: CGMChoice])
}

/// Which CGM the Unknown readings (the ones no recorded session covers) probably were: the runs that are probably one
/// sensor each, the CGM each suggests, and the entered sessions an answer makes. Only suggestions, never applied on
/// their own: a Libre 2 can read every 5 minutes and a G6 can be restarted past 10 days. Pure.
enum CGMUnknownInference {
    /// A gap this long always splits the readings: the shortest warm-up (the G7's 30 min), so a sensor change with
    /// one is never inside a run. A longer dropout splits too (`joins` joins it again). The only gap that splits
    /// 1-minute readings: they jump after a dropout of a few minutes, and a Libre started ahead, without a gap, makes
    /// a run longer than one lasts (`splitLong`).
    static let splitGap: TimeInterval = .minutes(30)
    /// A gap of this many cadences or more (a 5-minute sensor's one missed reading and more) splits 5-minute readings
    /// where the level steps (`levelStep`): a sensor started ahead (pre-soaked, or an overlap) can come back within
    /// minutes, but its readings jump (`isOneSensor` joins a dropout inside one sensor again).
    static let stepGapCadences: Double = 2
    /// A level step, mg/dL: about the sensor-change step the smoothing PR saw (+25), off both the last level and its
    /// trend's continuation, so a meal rise or a fall across the gap isn't one.
    static let levelStep: Double = 25
    /// The level each side of a gap: the median of this many readings.
    static let levelReadings = 3
    /// The trend before a gap: the least-squares slope of this long of readings, at most `trendRateLimit` either way.
    static let trendWindow: TimeInterval = .minutes(15)
    /// mg/dL a minute: glucose rarely moves faster for long, so a noisy slope isn't carried far.
    static let trendRateLimit: Double = 3
    /// The cadence each side of a gap: the median of up to this many distances (at least `cadenceMinimumDistances`).
    static let cadenceDistances = 10
    static let cadenceMinimumDistances = 3
    /// Two runs are joined across a gap shorter than this (`isOneSensor`): the longest warm-up of a 5-minute CGM (the
    /// G6's and the G5's 2 h), and twice a Libre's hour, so a phone left behind for an hour is a dropout. The life
    /// check keeps two real sensors apart: together they are longer than one lasts.
    static let joinGap: TimeInterval = .hours(2)
    /// A run, or two joined, is at most a sensor's life and this: a Libre 3 Plus or 2 Plus lasts 15 days, a day over
    /// the 14 a Libre's sessions record; a sensor's readings run a little past its life (the G7's grace, a late
    /// change).
    static let lifeSlack: TimeInterval = .days(1)
    /// The longest any sensor lasts (a Libre 3 Plus or 2 Plus; a Dexcom at most 10.5 days): a run longer than this
    /// and `lifeSlack` is two sensors without a gap between them (an overlap), split at its largest gap or step.
    static let longestLife: TimeInterval = .days(15)
    /// A 5-minute run without a suggestion of its own, joined, is at most this and `lifeSlack`: a Dexcom's life (the
    /// G7's 10.5 days with its grace). A 5-minute Libre over 11 days has a suggestion of its own.
    static let fiveMinuteLife: TimeInterval = .days(10.5)
    /// A run shorter than this is no sensor: a dropout's few readings (its readings stay with the session before).
    static let minimumRun: TimeInterval = .hours(2)
    /// A run of 5-minute readings longer than this suggests a Libre: no Dexcom lasts longer (the G7 at most 10.5 d with
    /// its grace, the G6 10 d), unless a G6 was restarted.
    static let libreLength: TimeInterval = .days(11)
    /// A run of 5-minute readings this long or longer (up to `libreLength`) suggests a Dexcom: its 10 days, a few hours
    /// either way, and a day short for a sensor changed early.
    static let dexcomLength: TimeInterval = .days(9)
    /// A run of 1-minute readings suggests this, unless a Libre (or an AppGroup source) was recorded: LibreLoop
    /// forwards every minute.
    static let defaultLibre = "libre3"
    /// The plugin of an AppGroup CGM (xDrip4iOS, Glucose Direct): a recorded one is what 1-minute readings suggest
    /// when no Libre was recorded, a Libre read through that app.
    static let appGroupPlugin = "AppGroupCGM"
    /// A Dexcom-length run suggests this, unless a Dexcom was recorded: the G6 is discontinued.
    static let defaultDexcom = "dexcomG7"
    /// Two sensor starts within this are the same sensor (`BloodGlucose.sessionTolerance`, the readings' rule).
    static let tolerance = BloodGlucose.sessionTolerance
    /// The readings each side of an entered session's start `joinedEntered` looks at: a gap up to `joinGap` and an hour
    /// of readings past it (a 5-minute cadence's `cadenceDistances`, the trend), or the later sensor's warm-up (up to
    /// 2 h) and an hour of its first readings.
    static let joinReach: TimeInterval = .hours(3)

    // MARK: The runs

    /// The probable sensors of the Unknown readings, oldest first.
    /// - Parameters:
    ///   - unknown: the readings no recorded session covers, any order
    ///   - allReadings: every reading's time (the recorded CGMs' too), ascending: a sensor's gap before it
    ///   - choices: the CGMs to suggest from (`CGMChoice.choices`): a recorded one of a family first
    ///   - readFrom: where the readings read begin (the 90 days): a sensor whose first reading is there began earlier
    static func sensors(
        _ unknown: [GlucosePoint],
        allReadings: [Date],
        choices: [CGMChoice],
        readFrom: Date? = nil
    ) -> [CGMProbableSensor] {
        let points = GlucoseStatsEngine.clean(unknown.filter { Double($0.mgdl) > CGMStatsEngine.errorCodeLimit })
        guard points.count > 1 else { return [] }

        // split at the gaps that may be a sensor change
        var runs: [Range<Int>] = []
        var runStart = 0
        for index in 1 ..< points.count where splits(points, at: index, from: runStart) {
            runs.append(runStart ..< index)
            runStart = index
        }
        runs.append(runStart ..< points.count)
        // longer than any sensor lasts: two without a gap between them
        runs = runs.flatMap { splitLong(points, $0) }

        func span(_ run: Range<Int>) -> TimeInterval {
            points[run.upperBound - 1].time.timeIntervalSince(points[run.lowerBound].time)
        }
        var kept = runs.filter { span($0) >= minimumRun }.map { run in
            (run: run, suggestion: ownSuggestion(points, run, choices: choices))
        }

        // a dropout that is no sensor change (`joins`): joined again
        var merged: [(run: Range<Int>, suggestion: CGMProbableSensor.Suggestion?)] = []
        for next in kept {
            if let previous = merged.last, joins(points, previous.run, next.run, previous.suggestion, next.suggestion, choices) {
                let run = previous.run.lowerBound ..< next.run.upperBound
                merged[merged.count - 1] = (run, ownSuggestion(points, run, choices: choices))
            } else {
                merged.append(next)
            }
        }
        kept = merged

        var sensors = kept.map { entry -> CGMProbableSensor in
            let first = points[entry.run.lowerBound].time
            let before = allReadings.partitionIndex { $0 >= first }
            let gapBefore = before > 0 ? first.timeIntervalSince(allReadings[before - 1]) : nil
            return CGMProbableSensor(
                first: first,
                last: points[entry.run.upperBound - 1].time,
                readings: entry.run.count,
                cadence: medianDistance(points, entry.run) ?? .minutes(5),
                gapBefore: gapBefore,
                suggestion: entry.suggestion,
                isCut: gapBefore == nil && readFrom.map { first.timeIntervalSince($0) < splitGap } ?? false
            )
        }

        // without one of its own: the nearest sensor's with the same cadence (by the gap between them)
        let own = sensors.map(\.suggestion)
        for index in sensors.indices where own[index] == nil {
            let sensor = sensors[index]
            let candidates = sensors.indices.filter { other in
                other != index && own[other] != nil && sensors[other].isOneMinute == sensor.isOneMinute
            }
            let nearest = candidates.min { distance(sensors[$0], sensor) < distance(sensors[$1], sensor) }
            if let nearest, let suggestion = own[nearest] {
                sensors[index].suggestion = CGMProbableSensor.Suggestion(
                    cgmId: suggestion.cgmId,
                    confidence: .possible,
                    reason: .neighbour
                )
            }
        }
        return sensors
    }

    /// Whether a run ends before `index`: a gap of `splitGap`; a change of cadence, over any gap (a CGM switched to);
    /// in 5-minute readings, a gap of `stepGapCadences` or more with a level step.
    private static func splits(_ points: [GlucosePoint], at index: Int, from runStart: Int) -> Bool {
        func distance(_ at: Int) -> TimeInterval {
            points[at].time.timeIntervalSince(points[at - 1].time)
        }
        let gap = distance(index)
        guard gap < splitGap else { return true }
        let before = runStart ..< index
        let after = index ..< points.count
        let limit = GlucoseStatsEngine.oneMinuteMedianLimit
        // the distances either side in different cadences first: the medians only then
        let hasNeighbours = index - 2 >= runStart && index + 1 < points.count
        if hasNeighbours, (distance(index - 1) <= limit) != (distance(index + 1) <= limit),
           cadenceChanges(points, before: before, after: after)
        {
            return true
        }
        // longer than the distance before it, and than a minute's two: the run's cadence only then
        let previous = index - 2 >= runStart ? distance(index - 1) : nil
        guard gap >= stepGapCadences * .minutes(1), previous.map({ gap > $0 * 1.5 }) ?? true else { return false }
        let recent = Swift.max(runStart, index - cadenceDistances - 1) ..< index
        let cadence = medianDistance(points, recent) ?? .minutes(5)
        // 1-minute readings: only at `splitGap`
        guard cadence > limit else { return false }
        return gap >= stepGapCadences * cadence && hasLevelStep(points, before: before, after: after)
    }

    /// A run longer than `longestLife` and `lifeSlack` split, again and again, at its largest gap (of
    /// `stepGapCadences` or more), else at its largest level step (the medians of `levelReadings` either side),
    /// leaving each part `minimumRun` at least.
    static func splitLong(_ points: [GlucosePoint], _ run: Range<Int>) -> [Range<Int>] {
        guard run.count > 1,
              points[run.upperBound - 1].time.timeIntervalSince(points[run.lowerBound].time) > longestLife + lifeSlack
        else { return [run] }
        let first = points[run.lowerBound].time
        let last = points[run.upperBound - 1].time
        let candidates = (run.lowerBound + 1 ..< run.upperBound).filter { index in
            points[index - 1].time.timeIntervalSince(first) >= minimumRun &&
                last.timeIntervalSince(points[index].time) >= minimumRun
        }
        guard candidates.isNotEmpty else { return [run] }
        let cadence = medianDistance(points, run) ?? .minutes(5)
        func gap(_ index: Int) -> TimeInterval {
            points[index].time.timeIntervalSince(points[index - 1].time)
        }
        var at = candidates.max { gap($0) < gap($1) }!
        if gap(at) < stepGapCadences * cadence {
            func step(_ index: Int) -> Double {
                let before = points[Swift.max(run.lowerBound, index - levelReadings) ..< index].map { Double($0.mgdl) }
                let after = points[index ..< Swift.min(run.upperBound, index + levelReadings)].map { Double($0.mgdl) }
                guard let one = CGMStatsEngine.median(before), let other = CGMStatsEngine.median(after) else { return 0 }
                return abs(other - one)
            }
            at = candidates.max { step($0) < step($1) }!
        }
        return splitLong(points, run.lowerBound ..< at) + splitLong(points, at ..< run.upperBound)
    }

    /// The level after the gap off the level before it and off its trend's continuation, by `levelStep` or more.
    static func hasLevelStep(_ points: [GlucosePoint], before: Range<Int>, after: Range<Int>) -> Bool {
        guard !before.isEmpty, !after.isEmpty else { return false }
        let last = points[before.upperBound - 1]
        let first = points[after.lowerBound]
        let beforeValues = points[Swift.max(before.lowerBound, before.upperBound - levelReadings) ..< before.upperBound]
            .map { Double($0.mgdl) }
        let afterValues = points[after.lowerBound ..< Swift.min(after.upperBound, after.lowerBound + levelReadings)]
            .map { Double($0.mgdl) }
        guard let levelBefore = CGMStatsEngine.median(beforeValues), let levelAfter = CGMStatsEngine.median(afterValues)
        else { return false }
        let trendFrom = last.time.addingTimeInterval(-trendWindow)
        var trendStart = before.upperBound - 1
        while trendStart > before.lowerBound, points[trendStart - 1].time >= trendFrom {
            trendStart -= 1
        }
        let rate = slope(Array(points[trendStart ..< before.upperBound]))
            .map { Swift.min(Swift.max($0, -trendRateLimit), trendRateLimit) } ?? 0
        let predicted = levelBefore + rate * first.time.timeIntervalSince(last.time) / 60
        return Swift.min(abs(levelAfter - levelBefore), abs(levelAfter - predicted)) >= levelStep
    }

    /// 1-minute readings on one side of the gap and 5-minute ones on the other (`GlucoseStatsEngine.cadence`), each
    /// side's from up to `cadenceDistances` distances.
    static func cadenceChanges(_ points: [GlucosePoint], before: Range<Int>, after: Range<Int>) -> Bool {
        let beforeRun = Swift.max(before.lowerBound, before.upperBound - cadenceDistances - 1) ..< before.upperBound
        let afterRun = after.lowerBound ..< Swift.min(after.upperBound, after.lowerBound + cadenceDistances + 1)
        guard beforeRun.count > cadenceMinimumDistances, afterRun.count > cadenceMinimumDistances,
              let one = medianDistance(points, beforeRun), let other = medianDistance(points, afterRun)
        else { return false }
        let limit = GlucoseStatsEngine.oneMinuteMedianLimit
        return (one <= limit) != (other <= limit)
    }

    /// Two neighbouring runs are one sensor: the same suggestion (or one without), and `isOneSensor` with the
    /// suggested CGM's life and warm-up.
    private static func joins(
        _ points: [GlucosePoint],
        _ one: Range<Int>,
        _ other: Range<Int>,
        _ oneSuggestion: CGMProbableSensor.Suggestion?,
        _ otherSuggestion: CGMProbableSensor.Suggestion?,
        _ choices: [CGMChoice]
    ) -> Bool {
        if let a = oneSuggestion?.cgmId, let b = otherSuggestion?.cgmId, a != b {
            return false
        }
        let suggested = (oneSuggestion ?? otherSuggestion).flatMap { suggestion in
            choices.first { $0.cgmId == suggestion.cgmId }
        }
        return isOneSensor(
            points,
            before: one,
            after: other,
            length: points[other.upperBound - 1].time.timeIntervalSince(points[one.lowerBound].time),
            life: suggested?.expectedLife,
            warmup: suggested?.warmup
        )
    }

    /// The readings either side of a gap are one sensor's: the same cadence, a gap shorter than `joinGap`, together
    /// (`length`) within the CGM's life and `lifeSlack` (without one a Libre's `longestLife` at 1 minute, a Dexcom's
    /// `fiveMinuteLife` at 5: two real sensors are longer than one lasts), and no level step unless the gap is shorter
    /// than the CGM's warm-up (`splitGap` without one). A new sensor needs its warm-up before its first reading unless
    /// it was started ahead (pre-soaked, an overlap), and then the two are longer than one lasts; one started ahead of
    /// a sensor that ended early is taken for one sensor: fragments would invent sensor changes.
    /// - Parameters:
    ///   - before: the readings before the gap (the run's, or its last ones)
    ///   - after: the readings after it
    ///   - length: from the earlier sensor's start, or first reading, to the later one's last reading
    static func isOneSensor(
        _ points: [GlucosePoint],
        before: Range<Int>,
        after: Range<Int>,
        length: TimeInterval,
        life: TimeInterval?,
        warmup: TimeInterval?
    ) -> Bool {
        guard let oneCadence = medianDistance(points, before), let otherCadence = medianDistance(points, after) else {
            return false
        }
        let limit = GlucoseStatsEngine.oneMinuteMedianLimit
        guard (oneCadence <= limit) == (otherCadence <= limit) else { return false }
        let gap = points[after.lowerBound].time.timeIntervalSince(points[before.upperBound - 1].time)
        guard gap < joinGap else { return false }
        let life = life ?? (oneCadence <= limit ? longestLife : fiveMinuteLife)
        guard length <= life + lifeSlack else { return false }
        return gap < (warmup ?? splitGap) || !hasLevelStep(points, before: before, after: after)
    }

    /// A run's own suggestion: 1-minute readings a Libre (likely); 5-minute ones longer than `libreLength` a Libre, from
    /// `dexcomLength` a Dexcom (possible); none for a shorter run.
    private static func ownSuggestion(
        _ points: [GlucosePoint],
        _ run: Range<Int>,
        choices: [CGMChoice]
    ) -> CGMProbableSensor.Suggestion? {
        let length = points[run.upperBound - 1].time.timeIntervalSince(points[run.lowerBound].time)
        let oneMinute = (medianDistance(points, run) ?? .minutes(5)) <= GlucoseStatsEngine.oneMinuteMedianLimit
        if oneMinute, let libre = preferredOneMinute(choices) {
            return .init(cgmId: libre, confidence: .likely, reason: .oneMinute)
        }
        if length > libreLength, let libre = preferred(.libre, choices: choices) {
            return .init(cgmId: libre, confidence: .possible, reason: .longerThanADexcom)
        }
        if length >= dexcomLength, let dexcom = preferred(.dexcom, choices: choices) {
            return .init(cgmId: dexcom, confidence: .possible, reason: .dexcomLength)
        }
        return nil
    }

    /// The CGM of a family to suggest: the newest recorded one, else the default (`defaultLibre`, `defaultDexcom`),
    /// else the family's first choice.
    static func preferred(_ family: CGMChoice.Family, choices: [CGMChoice]) -> String? {
        let ofFamily = choices.filter { $0.family == family }
        if let recorded = ofFamily.first(where: \.isRecorded) {
            return recorded.cgmId
        }
        let fallback = family == .libre ? defaultLibre : defaultDexcom
        return ofFamily.first { $0.cgmId == fallback }?.cgmId ?? ofFamily.first?.cgmId
    }

    /// The CGM 1-minute readings suggest: a recorded Libre, else a recorded AppGroup source (a Libre read through
    /// xDrip4iOS or Glucose Direct), else `preferred(.libre)`.
    static func preferredOneMinute(_ choices: [CGMChoice]) -> String? {
        if let recorded = choices.first(where: { $0.isRecorded && $0.family == .libre }) {
            return recorded.cgmId
        }
        if let appGroup = choices.first(where: { $0.isRecorded && $0.plugin == appGroupPlugin }) {
            return appGroup.cgmId
        }
        return preferred(.libre, choices: choices)
    }

    /// The median distance between consecutive readings of the run, s; nil with fewer than two.
    static func medianDistance(_ points: [GlucosePoint], _ run: Range<Int>) -> TimeInterval? {
        guard run.count > 1 else { return nil }
        return CGMStatsEngine.median(zip(run.dropLast(), run.dropFirst()).map {
            points[$1].time.timeIntervalSince(points[$0].time)
        })
    }

    /// The least-squares slope, mg/dL a minute; nil with fewer than two readings or no time between them.
    private static func slope(_ points: [GlucosePoint]) -> Double? {
        guard points.count > 1, let origin = points.first?.time else { return nil }
        let xs = points.map { $0.time.timeIntervalSince(origin) / 60 }
        let ys = points.map { Double($0.mgdl) }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        return sxy / sxx
    }

    /// The time between two sensors, s.
    private static func distance(_ one: CGMProbableSensor, _ other: CGMProbableSensor) -> TimeInterval {
        one.first < other.first ? other.first.timeIntervalSince(one.last) : one.first.timeIntervalSince(other.last)
    }

    // MARK: The answer's sessions

    /// A sensor's start for an entered session of the CGM: a recorded sensor's of the same CGM that started where the
    /// run did (from the CGM's warm-up before its first reading to just after it, with the tolerance, never before the
    /// reading before it: the same sensor, recorded later); else the first reading less the CGM's warm-up, when the gap
    /// before the run holds it (readings begin when the warm-up ends); else the first reading. Without a recorded one, none
    /// for a sensor cut at the start of the readings read (`isCut`): it began before them.
    static func sensorStart(_ sensor: CGMProbableSensor, _ choice: CGMChoice, recorded: [CGMSessionRecord]) -> Date? {
        let warmup = choice.warmup ?? 0
        // never before the reading before it
        let from = Swift.max(
            sensor.first.addingTimeInterval(-warmup - tolerance),
            sensor.gapBefore.map { sensor.first.addingTimeInterval(-$0 + 1) } ?? .distantPast
        )
        if let own = recorded.compactMap({ $0.cgmId == choice.cgmId ? $0.sensorStart : nil })
            .first(where: { $0 >= from && $0 <= sensor.first.addingTimeInterval(tolerance) })
        {
            return own
        }
        guard !sensor.isCut else { return nil }
        if let warmup = choice.warmup, let gap = sensor.gapBefore, gap >= warmup {
            // after the reading before it, which stays the old sensor's (`[start, end)`)
            return sensor.first.addingTimeInterval(-Swift.min(warmup, gap - 1))
        }
        return sensor.first
    }

    /// The entered sessions an answer makes, by start, closed, covering the Unknown readings:
    /// - one session per probable sensor, from its sensor start (`sensorStart`) to the next one's; the first from the
    ///   first Unknown reading (if earlier), the last to just after the last one. The readings between two sensors (a
    ///   run too short for one) go with the sensor before them. Without a probable sensor, one session over them all,
    ///   its sensor start not known.
    /// - A switch date splits the session it falls in: before it the first CGM's, from it the second's (its sensor
    ///   start the date, when the date falls among a sensor's readings).
    /// - By sensor, a sensor without a CGM leaves its time Unknown. A session without an Unknown reading is left out
    ///   (a switch date in a gap).
    /// - Parameters:
    ///   - unknownTimes: the Unknown readings' times, ascending
    ///   - recorded: the recorded sessions: a run starting with a recorded sensor is that sensor (`sensorStart`)
    static func sessions(
        for answer: CGMUnknownAnswer,
        sensors: [CGMProbableSensor],
        unknownTimes: [Date],
        recorded: [CGMSessionRecord],
        newID: () -> UUID = { UUID() }
    ) -> [CGMSessionRecord] {
        guard let firstTime = unknownTimes.first, let lastTime = unknownTimes.last else { return [] }
        let end = lastTime.addingTimeInterval(1)

        struct Piece {
            var start: Date
            var sensorStart: Date?
            var choice: CGMChoice?
            var oneMinute: Bool
            /// its sensor's first reading; nil without probable sensors
            var first: Date?
        }
        func choice(_ sensor: CGMProbableSensor) -> CGMChoice? {
            switch answer {
            case let .one(choice): return choice
            case let .switched(at, before, after): return sensor.first < at ? before : after
            case let .bySensor(choices): return choices[sensor.id]
            }
        }

        var pieces: [Piece] = sensors.map { sensor in
            let picked = choice(sensor)
            let started = picked.flatMap { sensorStart(sensor, $0, recorded: recorded) }
            return Piece(
                start: started ?? sensor.first,
                sensorStart: started,
                choice: picked,
                oneMinute: sensor.isOneMinute,
                first: sensor.first
            )
        }
        if pieces.isEmpty {
            let only: CGMChoice?
            switch answer {
            case let .one(choice): only = choice
            case let .switched(_, before, _): only = before
            case .bySensor: only = nil
            }
            let cadence = CGMStatsEngine.median(zip(unknownTimes, unknownTimes.dropFirst()).map { $1.timeIntervalSince($0) })
            pieces = [Piece(
                start: firstTime,
                sensorStart: nil,
                choice: only,
                oneMinute: (cadence ?? .minutes(5)) <= GlucoseStatsEngine.oneMinuteMedianLimit,
                first: nil
            )]
        }
        // the first from the first Unknown reading; the sensor starts kept in order
        pieces[0].start = Swift.min(pieces[0].start, firstTime)
        for index in pieces.indices.dropFirst() {
            pieces[index].start = Swift.max(pieces[index].start, pieces[index - 1].start)
        }

        if case let .switched(at, before, after) = answer, at > pieces[0].start, at < end {
            let index = pieces.lastIndex { $0.start <= at } ?? 0
            // not a sensor whose first reading is from the date on: it is the second CGM's whole
            if pieces[index].start < at, pieces[index].first.map({ $0 < at }) ?? true {
                var later = pieces[index]
                later.start = at
                later.sensorStart = at
                later.choice = after
                pieces[index].choice = before
                pieces.insert(later, at: index + 1)
            }
        }

        var sessions: [CGMSessionRecord] = []
        for (index, piece) in pieces.enumerated() {
            let pieceEnd = index + 1 < pieces.count ? pieces[index + 1].start : end
            guard let choice = piece.choice, piece.start < pieceEnd else { continue }
            // an Unknown reading in it
            let next = unknownTimes.partitionIndex { $0 >= piece.start }
            guard next < unknownTimes.count, unknownTimes[next] < pieceEnd else { continue }
            sessions.append(CGMSessionRecord(
                id: newID(),
                start: piece.start,
                end: pieceEnd,
                CGMSnapshot(
                    plugin: choice.plugin,
                    cgmId: choice.cgmId,
                    name: choice.name,
                    sensorStart: piece.sensorStart,
                    expectedLife: piece.sensorStart == nil ? nil : choice.expectedLife,
                    oneMinute: piece.oneMinute,
                    sensorId: nil
                ),
                source: .entered
            ))
        }
        return sessions
    }

    /// Each sensor's CGM in an entered session: the one holding its first reading (`Change` starts from them).
    static func entered(_ sensors: [CGMProbableSensor], sessions: [CGMSessionRecord]) -> [Date: String] {
        var entered: [Date: String] = [:]
        for sensor in sensors {
            if let cgmId = sessions.last(where: { $0.source == .entered && $0.contains(sensor.first) })?.cgmId {
                entered[sensor.id] = cgmId
            }
        }
        return entered
    }

    // MARK: The entered sessions, read

    /// The sessions with each entered session joined to the entered one before it where an earlier answer split one
    /// sensor that `isOneSensor` keeps whole (sessions made before its rules): the same CGM, touching (within the
    /// tolerance), the later one's sensor start inferred (not a recorded sensor's), and the readings either side of
    /// its start one sensor's, the two together within its life (from the earlier one's sensor start to the later
    /// one's end: a little longer than their readings). The joined session is the earlier one to the later one's end:
    /// its id, sensor start and life; the later one's start is dropped. Never a recorded or a backfilled session, a
    /// change of CGM, or a recorded sensor's start. Unchanged without such a boundary; the store keeps what was
    /// entered.
    /// - Parameter readings: the readings within `joinReach` of each boundary (`joinWindows`), any order; more are fine
    static func joinedEntered(_ sessions: [CGMSessionRecord], readings: [GlucosePoint]) -> [CGMSessionRecord] {
        let ordered = CGMSessionRules.ordered(sessions)
        guard zip(ordered, ordered.dropFirst()).contains(where: { mayJoin($0, $1, among: ordered) }) else {
            return sessions
        }
        let points = GlucoseStatsEngine.clean(readings.filter { Double($0.mgdl) > CGMStatsEngine.errorCodeLimit })
        var joined: [CGMSessionRecord] = []
        for session in ordered {
            if let previous = joined.last, let end = session.end, mayJoin(previous, session, among: ordered),
               continues(previous, session, end: end, points)
            {
                joined[joined.count - 1].end = end
            } else {
                joined.append(session)
            }
        }
        return joined
    }

    /// The readings `joinedEntered` needs: `joinReach` either side of each boundary it may join, overlaps merged, by
    /// start.
    static func joinWindows(_ sessions: [CGMSessionRecord]) -> [DateInterval] {
        let ordered = CGMSessionRules.ordered(sessions)
        var windows: [DateInterval] = []
        for (previous, next) in zip(ordered, ordered.dropFirst()) where mayJoin(previous, next, among: ordered) {
            let window = DateInterval(start: next.start.addingTimeInterval(-joinReach), duration: 2 * joinReach)
            if let last = windows.last, last.end >= window.start {
                windows[windows.count - 1] = DateInterval(start: last.start, end: Swift.max(last.end, window.end))
            } else {
                windows.append(window)
            }
        }
        return windows
    }

    /// Two entered sessions of the same CGM, the later one touching the earlier one, its start inferred
    /// (`hasInferredStart`).
    private static func mayJoin(
        _ previous: CGMSessionRecord,
        _ next: CGMSessionRecord,
        among sessions: [CGMSessionRecord]
    ) -> Bool {
        guard previous.source == .entered, let cgmId = next.cgmId, previous.cgmId == cgmId,
              let end = previous.end, abs(next.start.timeIntervalSince(end)) <= tolerance
        else { return false }
        return hasInferredStart(next, among: sessions)
    }

    /// An entered session whose sensor start (if any) is inferred from its readings: not a recorded sensor's (one of
    /// the recorded sessions among `sessions`, of the same CGM, within the tolerance; `sensorStart` takes it when the
    /// run began there).
    static func hasInferredStart(_ session: CGMSessionRecord, among sessions: [CGMSessionRecord]) -> Bool {
        guard session.source == .entered else { return false }
        guard let sensorStart = session.sensorStart else { return true }
        return !sessions.contains { other in
            other.source == .recorded && other.cgmId == session.cgmId &&
                other.sensorStart.map { abs($0.timeIntervalSince(sensorStart)) <= tolerance } ?? false
        }
    }

    /// The readings either side of the later session's start are one sensor's (`isOneSensor`, the CGM's warm-up and
    /// the sessions' life): those of the earlier session within `joinReach` before it, those of the later one after.
    private static func continues(
        _ previous: CGMSessionRecord,
        _ next: CGMSessionRecord,
        end: Date,
        _ points: [GlucosePoint]
    ) -> Bool {
        let boundary = next.start
        let from = Swift.max(previous.start, boundary.addingTimeInterval(-joinReach))
        let lower = points.partitionIndex { $0.time >= from }
        let middle = points.partitionIndex { $0.time >= boundary }
        let upper = points.partitionIndex { $0.time >= Swift.min(end, boundary.addingTimeInterval(joinReach)) }
        guard lower < middle, middle < upper else { return false }
        let known = CGMChoice.known.first { $0.cgmId == next.cgmId }
        return isOneSensor(
            points,
            before: lower ..< middle,
            after: middle ..< upper,
            length: end.timeIntervalSince(previous.sensorStartOrStart),
            life: previous.expectedLife ?? next.expectedLife ?? known?.expectedLife,
            warmup: known?.warmup
        )
    }
}
