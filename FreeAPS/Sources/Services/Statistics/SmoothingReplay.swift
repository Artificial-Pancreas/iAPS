import Foundation

// MARK: - Candidates

/// A smoothing setting the replay scores: what Settings → CGM → Smoothing can be set to.
enum SmoothingCandidate: Hashable, Sendable, Identifiable {
    case none
    case savitzkyGolay(SavitzkyGolayPasses)
    case kalman(KalmanResponsiveness)
    case exponential

    /// Every setting: none, Savitzky-Golay 1/2/3 passes, Kalman calm/balanced/responsive, exponential.
    static let all: [SmoothingCandidate] = [.none]
        + SavitzkyGolayPasses.allCases.map { SmoothingCandidate.savitzkyGolay($0) }
        + KalmanResponsiveness.allCases.map { SmoothingCandidate.kalman($0) }
        + [SmoothingCandidate.exponential]

    /// The candidate a setting is (the view marks the current one).
    init(_ settings: GlucoseSmoothingSettings) {
        switch settings.algorithm {
        case .off: self = .none
        case .savitzkyGolay: self = .savitzkyGolay(settings.savitzkyGolay.passes)
        case .kalman: self = .kalman(settings.kalman.responsiveness)
        case .exponential: self = .exponential
        }
    }

    /// The setting, as Settings stores it.
    var settings: GlucoseSmoothingSettings {
        var settings = GlucoseSmoothingSettings()
        switch self {
        case .none:
            settings.algorithm = .off
        case let .savitzkyGolay(passes):
            settings.algorithm = .savitzkyGolay
            settings.savitzkyGolay.passes = passes
        case let .kalman(responsiveness):
            settings.algorithm = .kalman
            settings.kalman.responsiveness = responsiveness
        case .exponential:
            settings.algorithm = .exponential
        }
        return settings
    }

    var id: String {
        switch self {
        case .none: return "none"
        case let .savitzkyGolay(passes): return "savitzkyGolay.\(passes.rawValue)"
        case let .kalman(responsiveness): return "kalman.\(responsiveness.rawValue)"
        case .exponential: return "exponential"
        }
    }

    /// The live pipeline's smoother for it (`GlucoseSmoothingSettings.smoother`); nil for none.
    var smoother: GlucoseSmoother? {
        settings.smoother
    }
}

// MARK: - glucose-get-last

/// A reading as oref's `glucose` input carries it (`OpenAPS.glucoseEntries`): the fields `glucose-get-last` reads.
struct OrefGlucoseEntry: Sendable, Equatable {
    /// ms since 1970 (`GlucoseEntry0.date`: the seconds × 1000, truncated)
    let date: Int
    let glucose: Int
    /// "sgv", "cal", ...
    var type: String? = "sgv"
    /// iAPS sends none, so every entry has the newest one's (none)
    var device: String? = nil
}

/// What `glucose-get-last` returns, the fields the replay scores. mg/dL, the deltas per 5 minutes.
struct OrefGlucoseStatus: Sendable, Equatable {
    let glucose: Double
    let delta: Double
    let shortAvgDelta: Double
    let longAvgDelta: Double
    /// the newest entry's, ms since 1970
    let date: Int
    /// the index of the first "cal" entry after the newest; 0 without one
    let lastCal: Int
}

/// A Swift port of the bundled oref0 `lib/glucose-get-last.js` (in `bundle/oref0-bridge.js`, the module
/// `determine-basal.js` requires as `oref0/glucose-get-last.js`), step for step so its doubles are the same:
///
/// - entries with a falsy glucose are dropped; the newest one is `now`, whatever its value (a 38 included);
/// - walking older, the first "cal" entry stops the walk; entries of 39 and below, and of another device, are skipped;
/// - each entry's `avgdelta` is `(now − then) / minutesago × 5`, minutes from the ms dates (not rounded);
/// - `delta` is the mean of those 2.5–7.5 min ago, else `short_avgdelta`; `short_avgdelta` the mean of 2.5–17.5;
///   `long_avgdelta` of 17.5–42.5; the walk stops at the first one more than 42.5 min ago; all bounds exclusive;
/// - every figure is `Math.round(100 × x) / 100`.
///
/// Not ported: `noise` (`Math.round` of a field iAPS doesn't fill) and the `display_time` / `dateString` fallbacks of
/// the date (iAPS always sends `date`). The JS throws on an empty list; this returns nil.
enum GlucoseGetLast {
    /// Values at or below this are not readings (`glucose > 39`).
    static let validAbove = 39
    /// `delta`: the entries more than this and less than `lastDeltaUntil` minutes ago
    static let lastDeltaFrom = 2.5
    static let lastDeltaUntil = 7.5
    /// `short_avgdelta`: from `lastDeltaFrom` to this
    static let shortDeltaUntil = 17.5
    /// `long_avgdelta`: from `shortDeltaUntil` to this; an entry further back ends the walk
    static let longDeltaUntil = 42.5

    /// - Parameter entries: newest -> oldest, as oref gets them
    static func status(_ entries: [OrefGlucoseEntry]) -> OrefGlucoseStatus? {
        let data = entries.filter { $0.glucose != 0 }
        guard let now = data.first else { return nil }
        let nowDate = Double(now.date)

        var lastDeltas: [Double] = []
        var shortDeltas: [Double] = []
        var longDeltas: [Double] = []
        var lastCal = 0

        for index in 1 ..< data.count {
            let then = data[index]
            if then.type == "cal" {
                lastCal = index
                break
            }
            guard then.glucose > validAbove, then.device == now.device else { continue }
            let minutesAgo = (nowDate - Double(then.date)) / 60000
            let avgDelta = Double(now.glucose - then.glucose) / minutesAgo * 5
            if lastDeltaFrom < minutesAgo, minutesAgo < lastDeltaUntil {
                lastDeltas.append(avgDelta)
            }
            if lastDeltaFrom < minutesAgo, minutesAgo < shortDeltaUntil {
                shortDeltas.append(avgDelta)
            }
            if shortDeltaUntil < minutesAgo, minutesAgo < longDeltaUntil {
                longDeltas.append(avgDelta)
            } else if minutesAgo > longDeltaUntil {
                break
            }
        }

        let short = mean(shortDeltas) ?? 0
        let delta = mean(lastDeltas) ?? short
        let long = mean(longDeltas) ?? 0

        return OrefGlucoseStatus(
            glucose: rounded(Double(now.glucose)),
            delta: rounded(delta),
            shortAvgDelta: rounded(short),
            longAvgDelta: rounded(long),
            date: now.date,
            lastCal: lastCal
        )
    }

    /// `reduce((a, b) => a + b) / length`: summed from the first element, in order.
    private static func mean(_ values: [Double]) -> Double? {
        guard let first = values.first else { return nil }
        return values.dropFirst().reduce(first, +) / Double(values.count)
    }

    /// `Math.round(100 * x) / 100`
    static func rounded(_ value: Double) -> Double {
        jsRound(100 * value) / 100
    }

    /// `Math.round`: the nearest integer, halves up (towards +∞), exact for every double (no `x + 0.5` rounding).
    static func jsRound(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let floor = value.rounded(.down)
        return value - floor >= 0.5 ? floor + 1 : floor
    }
}

// MARK: - Results

/// A score of the replay (`SmoothingReplay.score`). Each is of the loop times with a `glucose_status`; the ones against
/// the reference only where the reference has a centred value at the loop time and 5 minutes before it.
enum SmoothingMetric: CaseIterable, Sendable, Hashable {
    /// Turns per day of the delta the loop saw: `CGMStatsEngine.turns` (a flip counts once the move in the new
    /// direction reaches `CGMStatsEngine.turnThreshold`) of the running sum of `delta` over each run of loop times, per
    /// the runs' time. Not `CGMReversals`, which are of the level series: each loop's delta is its own window's, so
    /// a filter that revises the past turns differently here. Count: the turns.
    case reversals
    /// The SD of the change in `delta` from one loop time to the next, within a run (`CGMStatsEngine.deltaJitter` of
    /// the same running sums), mg/dL. Count: the changes' loop times.
    case deltaJitter
    /// The mean |newest value − reference|, mg/dL.
    case levelError
    /// The mean |`delta` − the reference's 5-minute delta| (reference at t less at t − 5 min), mg/dL.
    case deltaError
    /// Of the loop times while the reference moves at least `SmoothingReplay.movingRate` (its 5-minute delta ÷ 5),
    /// the share whose `delta` has the opposite sign, 0...1 (a `delta` of 0 isn't the wrong way). Count: those loop
    /// times.
    case wrongWay
    /// The shift, minutes, that best aligns the newest values with the reference: the least mean squared error of
    /// newest(t) − reference(t − shift) over `SmoothingReplay.lagShifts`, the same loop times for every shift, refined
    /// by a parabola through the best shift and its neighbours. Positive: the loop sees glucose late.
    case lag
    /// The mean newest value − reference while the reference rises at least `SmoothingReplay.fastRate`, mg/dL.
    case riseError
    /// The same while it falls at least that fast.
    case fallError
    /// Per reference dip (`SmoothingReplay.dips`, those the loop times cover): the lowest newest value at the loop
    /// time nearest the reference's lowest point and the loop times either side of it, less that point, mg/dL, the
    /// mean; negative: the loop saw it lower. Not the lowest over a wider window, where raw noise would make no
    /// smoothing look worse than the dip it saw. Count: the dips.
    case nadirMiss
    /// Per dip with a crossing: minutes from the reference crossing below `SmoothingReplay.lowLimit` to the first loop
    /// time from `SmoothingReplay.crossingWindow` before it whose newest value is below the limit, searched up to
    /// `nadirWindow` after the dip's lowest point; the mean. A loop already below the limit when the search starts (a
    /// dip just after another) gets that loop time, earlier than the reference's: seeing a low early is a real result,
    /// not a miss. Count: the dips the loop was below the limit in that window (`SmoothingScores.lowsNotCrossed` the
    /// others).
    case lowCrossingDelay

    /// Needs no reference.
    var isReferenceFree: Bool {
        self == .reversals || self == .deltaJitter
    }
}

/// A score and the count it rests on.
struct SmoothingMeasure: Sendable, Equatable {
    /// nil without anything to score
    let value: Double?
    let count: Int

    static let empty = SmoothingMeasure(value: nil, count: 0)
}

/// A candidate's scores.
struct SmoothingScores: Sendable, Equatable {
    /// every metric
    let measures: [SmoothingMetric: SmoothingMeasure]
    /// the dips with a reference crossing the loop wasn't below the limit for within the search window
    let lowsNotCrossed: Int
    /// the loop times with a `glucose_status`
    let loopTimes: Int

    subscript(_ metric: SmoothingMetric) -> SmoothingMeasure {
        measures[metric] ?? .empty
    }
}

/// A score against no smoothing's.
struct SmoothingChange: Sendable, Equatable {
    /// the candidate's less none's, in the score's unit
    let difference: Double?
    /// the difference over |none's|; nil when none's is 0, and for the scores whose baseline is near 0 or signed (lag,
    /// rise and fall errors, nadir miss, crossing delay), where a ratio means nothing
    let relative: Double?
}

struct SmoothingCandidateResult: Sendable, Equatable, Identifiable {
    let candidate: SmoothingCandidate
    /// against the ±20 min reference
    let scores: SmoothingScores
    /// against none's; empty when none isn't among the candidates
    let changes: [SmoothingMetric: SmoothingChange]

    var id: String {
        candidate.id
    }
}

/// Whether the order of the candidates by a score depends on the reference's width: Savitzky-Golay is itself a local
/// polynomial, so a reference of its own width favours it.
struct SmoothingRankingSensitivity: Sendable, Equatable {
    /// `SmoothingReplay.referenceHalfWidths`
    let halfWidths: [TimeInterval]
    /// best first (the least delta error), one order per half-width
    let deltaErrorOrder: [[SmoothingCandidate]]
    /// best first (the least |lag|), one order per half-width
    let lagOrder: [[SmoothingCandidate]]

    var deltaErrorRankingChanges: Bool {
        Set(deltaErrorOrder).count > 1
    }

    var lagRankingChanges: Bool {
        Set(lagOrder).count > 1
    }
}

struct SmoothingReplayResult: Sendable, Equatable {
    let period: DateInterval
    /// the loop times replayed
    let loopTimes: Int
    /// in the order asked for
    let results: [SmoothingCandidateResult]
    /// the ±20 min reference's own turns per day, of its 5-minute deltas at the loop times as `reversals` counts the
    /// loop's: the physiological ones
    let referenceReversals: SmoothingMeasure
    let sensitivity: SmoothingRankingSensitivity
}

// MARK: - The replay

/// What the loop saw with each smoothing candidate: at every loop time, the `glucose_status` oref was given, rebuilt
/// from the stored readings as the live pipeline built it then, and scored against an after-the-fact reference. No
/// value a filter revises later is scored as if the loop had it. Pure: no Core Data, no `Date()`.
///
/// **The live pipeline** (`BaseGlucoseStorage`): `glucose.json` holds the readings of the last 24 h;
/// `GlucoseSmoothing.smooth` splits the valid ones (above 39) at each smoother's maximum gap and at sensor changes,
/// smooths each segment, keeps a filter's unusable output raw, floors at 40 and rounds; `FrequentGlucoseFiltering`
/// thins the list to one per 4.5 min from the newest; `glucose-get-last` (`GlucoseGetLast`) reads the deltas. Here:
/// - the window is the stored readings in `(t − 24 h, t]` (live: from the store time of the newest less 24 h, seconds
///   later: equal within that edge);
/// - a reading's session start is the `sensorStart` of the CGM session holding it, nil without one, so it never splits
///   (live: `KnownPlugins.sessionStart`, stamped by the CGM, nil for a plugin without one); the reference's segments
///   take `sensorStartOrStart`, as the CGM statistics do;
/// - error codes (39 and below) pass through raw and are thinned with the rest, as live; fingersticks and calibrations,
///   which live are in the list too, aren't in the readings.
///
/// **Exact windows, faster:** only the segments holding an entry `glucose-get-last` reads are smoothed. Savitzky-Golay
/// reads only `savitzkyGolayReach` back (tested equal to the 24 h window). Exponential is causal once a segment is past
/// `exponentialSettling`: one pass over each segment gives every newest value, the same as the 24 h window unless the
/// segment began more than 24 h before (its start then moves with the window: a difference that decays by ~0.78 every
/// 5 minutes, ~1e-30 after 24 h, below the rounding to whole mg/dL; tested equal). Kalman's noise estimate is over its
/// whole segment: the full window, equal to the live one within its store-time edge (above).
///
/// **Loop times:** each valid reading's time, thinned forwards to one per `loopInterval`.
///
/// **Threads:** the loop times run in parallel on `DispatchQueue.concurrentPerform`, which blocks the caller until
/// they are done: call `replay` from a GCD queue or a detached thread, not a task on the cooperative pool.
enum SmoothingReplay {
    // MARK: Thresholds

    /// The live window: `glucose.json` keeps the readings of the last 24 h (`BaseGlucoseStorage.storeGlucose`).
    static let liveWindow: TimeInterval = .hours(24)
    /// The loop times' spacing: oref's stream's (`FrequentGlucoseFiltering.fiveMinuteInterval`), so a 1-minute
    /// sensor isn't 5× the work and a 5-minute one's jittered timestamps don't drop every other reading.
    static let loopInterval = FrequentGlucoseFiltering.fiveMinuteInterval
    /// `glucose-get-last` reads entries up to this far back.
    static let statusLookback: TimeInterval = .minutes(GlucoseGetLast.longDeltaUntil)
    /// Added to the Savitzky-Golay reach, so the strict and inclusive edges of its windows never matter.
    static let reachMargin: TimeInterval = .minutes(1)
    /// The exponential filter isn't causal at a segment's start: it leaves a segment of fewer than 4 readings raw, and
    /// on a fast sensor takes its first trend from the segment's first 10 minutes (`GlucoseSmoothing.initialSlope`).
    /// Until the newest reading's segment is past both (with a margin), its window is smoothed afresh.
    static let exponentialSettling: TimeInterval = .minutes(15)
    static let exponentialSettlingReadings = 4

    /// The reference half-widths: ±20 min (`CGMStatsEngine.referenceHalfWidth`) for the scores, ±15 and ±25 to check
    /// the ranking doesn't hang on it.
    static let referenceHalfWidths: [TimeInterval] = [.minutes(15), CGMStatsEngine.referenceHalfWidth, .minutes(25)]
    /// The half-width the scores are against.
    static let scoringHalfWidth = CGMStatsEngine.referenceHalfWidth

    /// Loop times further apart than this end a run of the delta paths: a missed reading or more (1.5 loops).
    static let runBreak: TimeInterval = .minutes(7.5)
    /// The reference delta's span: oref's delta is a 5-minute one.
    static let referenceDeltaSpan: TimeInterval = .minutes(5)
    /// Glucose is clearly moving from this rate, mg/dL/min (absolute): a delta the other way is wrong.
    static let movingRate: Double = 1
    /// A fast rise or fall from this rate, mg/dL/min (absolute): where lag costs the most.
    static let fastRate: Double = 2
    /// The lag's shifts searched, minutes: a filter can lead a little at a turn, and none lags more than half an hour.
    static let lagShifts: [Double] = (-10 ... 30).map(Double.init)

    /// A dip: the reference below this, mg/dL (the range's low edge) ...
    static let lowLimit = Double(StatsBands.tirMgdl.lowerBound)
    /// ... until it is back at the limit plus this, mg/dL: a reference hovering at the limit is one dip.
    static let lowExitMargin: Double = 5
    /// The loop's lowest value is looked for this far either side of the reference's lowest point.
    static let nadirWindow: TimeInterval = .minutes(30)
    /// The loop's crossing is looked for from this long before the reference's: Savitzky-Golay can cross early.
    static let crossingWindow: TimeInterval = .minutes(30)

    /// The share of the progress the replay takes; the scoring the rest.
    private static let replayProgressShare = 0.9

    // MARK: The whole of it

    /// Replays and scores the candidates over the period.
    /// - Parameters:
    ///   - readings: the stored readings (sgv, the values as stored), any order; the 24 h before the period are needed
    ///     for its first loop times, and those up to 35 min after it for the reference (its ±25 min, and the lag's
    ///     shift of up to 10 min ahead)
    ///   - sessions: the CGM sessions, any order: their sensor starts split the segments
    ///   - candidates: in the order the results keep; none's scores are the changes' baseline
    ///   - isCancelled: checked at every loop time, from several threads
    ///   - progress: the fraction done, 0...1, increasing, ends at 1; called from several threads, one at a time,
    ///     under the replay's lock: it must return quickly and never block (hop to the main actor asynchronously)
    /// - Returns: nil when cancelled
    static func replay(
        readings: [GlucosePoint],
        sessions: [CGMSessionRecord],
        period: DateInterval,
        candidates: [SmoothingCandidate] = SmoothingCandidate.all,
        now: Date,
        isCancelled: @Sendable() -> Bool = { false },
        progress: @escaping @Sendable(Double) -> Void = { _ in }
    ) -> SmoothingReplayResult? {
        guard let snapshots = loopStatuses(
            readings: readings,
            sessions: sessions,
            period: period,
            candidates: candidates,
            now: now,
            isCancelled: isCancelled,
            progress: { progress($0 * replayProgressShare) }
        ) else { return nil }

        let sensorStarts = CGMSessionAttribution.sensorStarts(sessions)
        let widest = referenceHalfWidths.max() ?? scoringHalfWidth
        let start = period.start.addingTimeInterval(-(widest + referenceDeltaSpan + .minutes(lagShifts.max() ?? 0)))
        let end = period.end.addingTimeInterval(widest - .minutes(lagShifts.min() ?? 0))
        let cleaned = CGMStatsEngine.cleaned(readings, in: DateInterval(start: start, end: max(end, start)), now: now)
        let segments = CGMStatsEngine.segments(CGMStatsEngine.weighed(cleaned), sensorStarts: sensorStarts)

        let loopSeconds = snapshots.loopTimes.map(\.timeIntervalSinceReferenceDate)
        var scoresByWidth: [[SmoothingScores]] = []
        var contexts: [ScoringContext] = []
        for halfWidth in referenceHalfWidths {
            guard !isCancelled() else { return nil }
            let reference = SmoothingReference(readings: cleaned, segments: segments, halfWidth: halfWidth)
            let context = ScoringContext(loopSeconds: loopSeconds, reference: reference)
            scoresByWidth.append(snapshots.statuses.map { score(loopSeconds: loopSeconds, statuses: $0, context: context) })
            contexts.append(context)
        }

        let scoring = referenceHalfWidths.firstIndex(of: scoringHalfWidth) ?? 0
        let scores = scoresByWidth[scoring]
        let baseline = candidates.firstIndex(of: .none).map { scores[$0] }
        let results = candidates.indices.map { index in
            SmoothingCandidateResult(
                candidate: candidates[index],
                scores: scores[index],
                changes: baseline.map { changes(scores[index], from: $0) } ?? [:]
            )
        }

        let referenceRuns = deltaPaths(loopSeconds: loopSeconds, deltas: contexts[scoring].referenceDelta)

        let result = SmoothingReplayResult(
            period: period,
            loopTimes: snapshots.loopTimes.count,
            results: results,
            referenceReversals: reversals(referenceRuns),
            sensitivity: SmoothingRankingSensitivity(
                halfWidths: referenceHalfWidths,
                deltaErrorOrder: scoresByWidth.map { scores in order(candidates, scores) { $0[.deltaError].value } },
                lagOrder: scoresByWidth.map { scores in order(candidates, scores) { $0[.lag].value.map(abs) } }
            )
        )
        progress(1)
        return result
    }

    // MARK: Loop statuses

    /// The `glucose_status` of every candidate at every loop time.
    struct Snapshots: Sendable, Equatable {
        /// oldest -> newest
        let loopTimes: [Date]
        /// by candidate, then by loop time; nil where the window gives none
        let statuses: [[OrefGlucoseStatus?]]
    }

    /// The readings in order, with what the pipeline needs of them.
    private struct History {
        /// s since the reference date, ascending, one per timestamp
        let seconds: [Double]
        /// ms since 1970, as oref gets them
        let ms: [Int]
        let values: [Int]
        /// the valid readings (above 39), as the smoothers get them
        let samples: [GlucoseSample]
        let sampleSeconds: [Double]
        /// each reading's index in `samples`; nil for an error code
        let sampleOf: [Int?]

        init(_ points: [GlucosePoint], sessions: [CGMSessionRecord]) {
            let sorted = sessions.sorted { $0.start < $1.start }
            var seconds: [Double] = []
            var ms: [Int] = []
            var values: [Int] = []
            var samples: [GlucoseSample] = []
            var sampleOf: [Int?] = []
            for point in points {
                seconds.append(point.time.timeIntervalSinceReferenceDate)
                ms.append(Int(point.time.timeIntervalSince1970 * 1000))
                values.append(Int(point.mgdl))
                guard Double(point.mgdl) > GlucoseSmoothing.errorCodeLimit else {
                    sampleOf.append(nil)
                    continue
                }
                sampleOf.append(samples.count)
                samples.append(GlucoseSample(
                    date: point.time,
                    value: Double(point.mgdl),
                    sessionStart: Self.sessionStart(at: point.time, sessions: sorted)
                ))
            }
            self.seconds = seconds
            self.ms = ms
            self.values = values
            self.samples = samples
            sampleSeconds = samples.map(\.date.timeIntervalSinceReferenceDate)
            self.sampleOf = sampleOf
        }

        /// The session start stamped on a reading, as the CGM stamps it live: the `sensorStart` of the session holding
        /// it (the latest starting one); nil without one (a CGM that reports none) and outside every session, which
        /// never splits a segment.
        /// - Parameter sessions: by start
        private static func sessionStart(at time: Date, sessions: [CGMSessionRecord]) -> Date? {
            let next = sessions.partitionIndex { $0.start > time }
            guard next > 0, sessions[next - 1].contains(time) else { return nil }
            return sessions[next - 1].sensorStart
        }
    }

    /// How a candidate's values at a loop time are had.
    private enum Method {
        case raw
        /// one causal pass over each segment of the whole history, by sample, with each sample's segment's first
        case causal(GlucoseSmoother, values: [Int?], segmentStart: [Int])
        /// smoothed afresh over the samples in `(t − 24 h, t]` and at most `reach` back
        case window(GlucoseSmoother, reach: TimeInterval)
    }

    /// Every candidate's `glucose_status` at every loop time in the period.
    /// - Parameter trimWindows: false smooths every candidate over the full 24 h window (the tests' check of the trims)
    static func loopStatuses(
        readings: [GlucosePoint],
        sessions: [CGMSessionRecord],
        period: DateInterval,
        candidates: [SmoothingCandidate],
        now: Date,
        trimWindows: Bool = true,
        isCancelled: @Sendable() -> Bool = { false },
        progress: @escaping @Sendable(Double) -> Void = { _ in }
    ) -> Snapshots? {
        let end = min(period.end, now)
        let history = History(
            GlucoseStatsEngine.clean(readings.filter {
                $0.time > period.start.addingTimeInterval(-liveWindow) && $0.time < period.end && $0.time <= end
            }),
            sessions: sessions
        )
        let loops = loopIndices(history, from: period.start.timeIntervalSinceReferenceDate)
        let methods = candidates.map { method($0, history: history, trimWindows: trimWindows) }

        var statuses = [[OrefGlucoseStatus?]](
            repeating: [OrefGlucoseStatus?](repeating: nil, count: loops.count),
            count: candidates.count
        )
        guard loops.isNotEmpty else {
            progress(1)
            return Snapshots(loopTimes: [], statuses: statuses)
        }

        // Loop times are independent: chunks of them run in parallel, each writing its own slots.
        let chunkCount = min(loops.count, ProcessInfo.processInfo.activeProcessorCount * 4)
        let chunkSize = (loops.count + chunkCount - 1) / chunkCount
        let collector = Collector(total: loops.count, progress: progress)
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            // the last chunks can be short or empty
            let range = min(chunk * chunkSize, loops.count) ..< min((chunk + 1) * chunkSize, loops.count)
            var part: [[OrefGlucoseStatus?]] = []
            part.reserveCapacity(range.count)
            for position in range {
                guard !isCancelled() else { break }
                part.append(Self.statuses(at: loops[position], history: history, methods: methods))
                collector.advance()
            }
            collector.store(part, from: range.lowerBound)
        }
        guard !isCancelled() else { return nil }

        for (start, part) in collector.parts {
            for (offset, byCandidate) in part.enumerated() {
                for candidate in byCandidate.indices {
                    statuses[candidate][start + offset] = byCandidate[candidate]
                }
            }
        }
        progress(1)
        return Snapshots(
            loopTimes: loops.map { Date(timeIntervalSinceReferenceDate: history.seconds[$0]) },
            statuses: statuses
        )
    }

    /// The parallel chunks' results and the progress, behind a lock.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private let total: Int
        private let progress: @Sendable(Double) -> Void
        private var done = 0
        private var reported = 0.0
        private(set) var parts: [(start: Int, part: [[OrefGlucoseStatus?]])] = []

        /// Progress is reported in steps of at least this.
        private static let progressStep = 0.01

        init(total: Int, progress: @escaping @Sendable(Double) -> Void) {
            self.total = total
            self.progress = progress
        }

        func advance() {
            lock.lock()
            defer { lock.unlock() }
            done += 1
            let fraction = Double(done) / Double(total)
            guard fraction - reported >= Self.progressStep, fraction < 1 else { return }
            reported = fraction
            progress(fraction)
        }

        func store(_ part: [[OrefGlucoseStatus?]], from start: Int) {
            lock.lock()
            defer { lock.unlock() }
            parts.append((start, part))
        }
    }

    /// The readings the loop ran at: the valid ones from `start` on, one per `loopInterval` (forwards, from the first).
    private static func loopIndices(_ history: History, from start: Double) -> [Int] {
        var loops: [Int] = []
        var last = -Double.infinity
        for index in history.seconds.indices where history.seconds[index] >= start && history.sampleOf[index] != nil {
            guard history.seconds[index] - last >= loopInterval else { continue }
            loops.append(index)
            last = history.seconds[index]
        }
        return loops
    }

    private static func method(_ candidate: SmoothingCandidate, history: History, trimWindows: Bool) -> Method {
        guard let smoother = candidate.smoother else { return .raw }
        guard trimWindows else { return .window(smoother, reach: liveWindow) }
        switch candidate {
        case .exponential:
            let (values, segmentStart) = causalValues(smoother, samples: history.samples)
            return .causal(smoother, values: values, segmentStart: segmentStart)
        case .savitzkyGolay:
            guard let filter = smoother as? SavitzkyGolayFilter else { return .window(smoother, reach: liveWindow) }
            return .window(smoother, reach: savitzkyGolayReach(filter))
        case .kalman,
             .none:
            return .window(smoother, reach: liveWindow)
        }
    }

    /// How far back a Savitzky-Golay filter's values at the entries `glucose-get-last` reads depend on the readings.
    ///
    /// A trimmed window starting at F changes the first pass's values only at the readings within one half-width of F
    /// (their windows slide inwards), and each further pass spreads that by one half-width: `passes` half-widths in
    /// all. The extra half-width is for a segment ending inside the lookback (a gap of over 15 min in the last
    /// 42.5): its last readings take one window over its last two half-widths, which reaches a half-width further
    /// back than a centred one. For the newest reading's segment alone it is margin. So an entry at most
    /// `statusLookback` old keeps its value while F is more than `statusLookback + (passes + 1) × halfWidth` back. The
    /// window starts at the first reading from `maximumGap` further back: if none is there, the gap before F is longer
    /// than the maximum and F starts a segment anyway. 123.5 min with 3 passes.
    static func savitzkyGolayReach(_ filter: SavitzkyGolayFilter) -> TimeInterval {
        statusLookback + Double(filter.passes + 1) * filter.halfWidth + filter.maximumGap + reachMargin
    }

    /// A causal smoother's value at every sample, from one pass over each segment of the whole history (nil where
    /// it stays raw), and the first sample of each sample's segment.
    private static func causalValues(
        _ smoother: GlucoseSmoother,
        samples: [GlucoseSample]
    ) -> (values: [Int?], segmentStart: [Int]) {
        var values = [Int?](repeating: nil, count: samples.count)
        var segmentStart = [Int](repeating: 0, count: samples.count)
        for segment in GlucoseSmoothing.segments(of: samples, maximumGap: smoother.maximumGap) {
            store(smoother.smooth(Array(samples[segment])), segment: segment, offset: 0, into: &values)
            for sample in segment {
                segmentStart[sample] = segment.lowerBound
            }
        }
        return (values, segmentStart)
    }

    /// A segment's smoothed values as `GlucoseSmoothing.smooth` keeps them: none if the count is wrong, each unusable
    /// one raw (nil), the rest floored at 40 and rounded.
    private static func store(_ smoothed: [Double], segment: Range<Int>, offset: Int, into values: inout [Int?]) {
        guard smoothed.count == segment.count else { return }
        for (position, value) in smoothed.enumerated() where GlucoseSmoothing.plausibleSmoothedValues.contains(value) {
            values[segment.lowerBound + position - offset] = Int(max(value, GlucoseSmoothing.minimumSmoothedValue).rounded())
        }
    }

    /// Every candidate's `glucose_status` at the loop time of reading `index`.
    private static func statuses(at index: Int, history: History, methods: [Method]) -> [OrefGlucoseStatus?] {
        let seconds = history.seconds
        let now = seconds[index]
        let windowStart = seconds.partitionIndex { $0 > now - liveWindow }

        // The thinned entries, newest -> oldest, down to the first valid one glucose-get-last stops at.
        var thinned = [index]
        var last = now
        var oldestRead = index
        var position = index - 1
        while position >= windowStart {
            if last - seconds[position] >= FrequentGlucoseFiltering.fiveMinuteInterval {
                thinned.append(position)
                last = seconds[position]
                if history.sampleOf[position] != nil {
                    if Double(history.ms[index] - history.ms[position]) / 60000 > GlucoseGetLast.longDeltaUntil {
                        break
                    }
                    oldestRead = position
                }
            }
            position -= 1
        }

        // The window's samples and segments, shared by the candidates with the same reach and maximum gap (Kalman's).
        var windows: [WindowKey: Window] = [:]
        func window(reach: TimeInterval, maximumGap: TimeInterval) -> Window {
            let key = WindowKey(reach: reach, maximumGap: maximumGap)
            if let window = windows[key] {
                return window
            }
            let window = Self.window(reach: reach, maximumGap: maximumGap, newest: index, history: history)
            windows[key] = window
            return window
        }

        /// a reading's value from a window smoothed now
        func windowed(_ smoother: GlucoseSmoother, reach: TimeInterval) -> (Int) -> Int {
            let smoothed = windowValues(
                smoother,
                window: window(reach: reach, maximumGap: smoother.maximumGap),
                oldestRead: oldestRead,
                history: history
            )
            return { reading in
                history.sampleOf[reading].flatMap { sample in
                    smoothed.values.indices.contains(sample - smoothed.offset)
                        ? smoothed.values[sample - smoothed.offset] : nil
                } ?? history.values[reading]
            }
        }

        return methods.map { method -> OrefGlucoseStatus? in
            let value: (Int) -> Int
            switch method {
            case .raw:
                value = { history.values[$0] }
            case let .causal(smoother, values, segmentStart):
                let newest = history.sampleOf[index] ?? 0
                let first = segmentStart[newest]
                if newest - first + 1 < exponentialSettlingReadings ||
                    history.sampleSeconds[newest] - history.sampleSeconds[first] <= exponentialSettling
                {
                    value = windowed(smoother, reach: liveWindow)
                } else {
                    value = { reading in history.sampleOf[reading].flatMap { values[$0] } ?? history.values[reading] }
                }
            case let .window(smoother, reach):
                value = windowed(smoother, reach: reach)
            }
            return GlucoseGetLast.status(thinned.map { OrefGlucoseEntry(date: history.ms[$0], glucose: value($0)) })
        }
    }

    private struct WindowKey: Hashable {
        let reach: TimeInterval
        let maximumGap: TimeInterval
    }

    /// The samples in `(t − 24 h, t]` at most `reach` back, from sample `first`, split as `GlucoseSmoothing.smooth`
    /// splits them at `maximumGap`.
    private struct Window {
        let first: Int
        let samples: [GlucoseSample]
        let segments: [Range<Int>]
    }

    private static func window(reach: TimeInterval, maximumGap: TimeInterval, newest: Int, history: History) -> Window {
        guard let last = history.sampleOf[newest] else { return Window(first: 0, samples: [], segments: []) }
        let now = history.seconds[newest]
        let first = max(
            history.sampleSeconds.partitionIndex { $0 > now - liveWindow },
            history.sampleSeconds.partitionIndex { $0 >= now - reach }
        )
        guard first <= last else { return Window(first: 0, samples: [], segments: []) }
        let samples = Array(history.samples[first ... last])
        return Window(
            first: first,
            samples: samples,
            segments: GlucoseSmoothing.segments(of: samples, maximumGap: maximumGap)
        )
    }

    /// A smoother's values over a window, by sample from `offset`: only the segments reaching `oldestRead` are
    /// smoothed, nil where a value stays raw.
    private static func windowValues(
        _ smoother: GlucoseSmoother,
        window: Window,
        oldestRead: Int,
        history: History
    ) -> (offset: Int, values: [Int?]) {
        guard window.samples.isNotEmpty else { return (0, []) }
        let read = (history.sampleOf[oldestRead] ?? window.first + window.samples.count - 1) - window.first
        var values = [Int?](repeating: nil, count: window.samples.count)
        for segment in window.segments where segment.upperBound > read {
            store(smoother.smooth(Array(window.samples[segment])), segment: segment, offset: 0, into: &values)
        }
        return (window.first, values)
    }

    // MARK: Scoring

    /// The reference at the loop times, shared by every candidate's scores.
    struct ScoringContext {
        let reference: SmoothingReference
        /// at each loop time, nil without a centred reference
        let referenceValue: [Double?]
        /// the reference at the loop time less 5 minutes before, nil without both
        let referenceDelta: [Double?]
        /// the reference at the loop time less each of `lagShifts`; nil unless it has all of them
        let shifted: [[Double]?]
        /// the reference's dips whose crossing and lowest point, with the windows around them, the loop times span
        let dips: [SmoothingDip]

        init(loopSeconds: [Double], reference: SmoothingReference) {
            self.reference = reference
            referenceValue = loopSeconds.map { reference.value(at: $0) }
            referenceDelta = loopSeconds.indices.map { index in
                guard let now = reference.value(at: loopSeconds[index]),
                      let before = reference.value(at: loopSeconds[index] - referenceDeltaSpan)
                else { return nil }
                return now - before
            }
            shifted = loopSeconds.map { time in
                var values: [Double] = []
                values.reserveCapacity(lagShifts.count)
                for shift in lagShifts {
                    guard let value = reference.value(at: time - .minutes(shift)) else { return nil }
                    values.append(value)
                }
                return values
            }
            // Only the dips the loop times cover with every window the scores look in: the reference also spans the
            // readings around the period, where there are no loop times to score.
            let covered = loopSeconds.first.flatMap { first in loopSeconds.last.map { first ... $0 } }
            dips = SmoothingReplay.dips(reference).filter { dip in
                guard let covered else { return false }
                let from = dip.crossing.map { $0 - crossingWindow } ?? dip.nadirTime - nadirWindow
                return covered.contains(min(from, dip.nadirTime - nadirWindow))
                    && covered.contains(dip.nadirTime + nadirWindow)
            }
        }
    }

    /// A candidate's scores (`SmoothingMetric`) from its statuses at the loop times.
    static func score(loopSeconds: [Double], statuses: [OrefGlucoseStatus?], context: ScoringContext) -> SmoothingScores {
        var measures: [SmoothingMetric: SmoothingMeasure] = [:]

        let runs = deltaPaths(loopSeconds: loopSeconds, deltas: statuses.map { $0?.delta })
        measures[.reversals] = reversals(runs)
        let changes = runs.reduce(0) { $0 + max($1.path.count - 2, 0) }
        measures[.deltaJitter] = SmoothingMeasure(value: CGMStatsEngine.deltaJitter(runs.map(\.path)), count: changes)

        var level = Mean()
        var delta = Mean()
        var wrong = Mean()
        var rise = Mean()
        var fall = Mean()
        for index in statuses.indices {
            guard let status = statuses[index], let reference = context.referenceValue[index] else { continue }
            level.add(abs(status.glucose - reference))
            guard let referenceDelta = context.referenceDelta[index] else { continue }
            delta.add(abs(status.delta - referenceDelta))
            let rate = referenceDelta / referenceDeltaSpan.minutes
            if abs(rate) >= movingRate {
                wrong.add(status.delta * referenceDelta < 0 ? 1 : 0)
            }
            if rate >= fastRate {
                rise.add(status.glucose - reference)
            } else if rate <= -fastRate {
                fall.add(status.glucose - reference)
            }
        }
        measures[.levelError] = level.measure
        measures[.deltaError] = delta.measure
        measures[.wrongWay] = wrong.measure
        measures[.riseError] = rise.measure
        measures[.fallError] = fall.measure
        measures[.lag] = lag(statuses: statuses, shifted: context.shifted)

        let lows = self.lows(loopSeconds: loopSeconds, statuses: statuses, dips: context.dips)
        measures[.nadirMiss] = lows.nadir
        measures[.lowCrossingDelay] = lows.crossing

        return SmoothingScores(
            measures: measures,
            lowsNotCrossed: lows.notCrossed,
            loopTimes: statuses.count(where: { $0 != nil })
        )
    }

    /// A running mean.
    private struct Mean {
        private var sum = 0.0
        private(set) var count = 0

        mutating func add(_ value: Double) {
            sum += value
            count += 1
        }

        var measure: SmoothingMeasure {
            SmoothingMeasure(value: count > 0 ? sum / Double(count) : nil, count: count)
        }
    }

    /// The running sums of the deltas over each run of loop times (consecutive, at most `runBreak` apart, each with a
    /// delta), from 0 before the first: the path the loop's deltas describe, whose turns are the delta's reversals and
    /// whose second differences are the changes in the delta.
    static func deltaPaths(loopSeconds: [Double], deltas: [Double?]) -> [(path: [Double], seconds: Double)] {
        var runs: [(path: [Double], seconds: Double)] = []
        var path: [Double] = []
        var first = 0.0
        var last = 0.0
        func close() {
            if path.count > 1 {
                runs.append((path, last - first))
            }
            path = []
        }
        for index in loopSeconds.indices {
            guard let delta = deltas[index] else {
                close()
                continue
            }
            if path.isNotEmpty, loopSeconds[index] - last > runBreak {
                close()
            }
            if path.isEmpty {
                path = [0]
                first = loopSeconds[index]
            }
            path.append(path[path.count - 1] + delta)
            last = loopSeconds[index]
        }
        close()
        return runs
    }

    /// The turns per day of the paths (`CGMStatsEngine.turns`), over the time the runs span.
    private static func reversals(_ runs: [(path: [Double], seconds: Double)]) -> SmoothingMeasure {
        let turns = runs.reduce(0) { $0 + CGMStatsEngine.turns($1.path) }
        let seconds = runs.reduce(0) { $0 + $1.seconds }
        return SmoothingMeasure(value: seconds > 0 ? Double(turns) / seconds * .days(1) : nil, count: turns)
    }

    /// The `lag`: the shift with the least mean squared error of the newest values against the shifted reference,
    /// refined by a parabola through it and its neighbours (not at the search's ends). Count: the loop times.
    private static func lag(statuses: [OrefGlucoseStatus?], shifted: [[Double]?]) -> SmoothingMeasure {
        var squares = [Double](repeating: 0, count: lagShifts.count)
        var count = 0
        for index in statuses.indices {
            guard let status = statuses[index], let values = shifted[index] else { continue }
            for shift in values.indices {
                let error = status.glucose - values[shift]
                squares[shift] += error * error
            }
            count += 1
        }
        guard count > 0, let best = squares.indices.min(by: { squares[$0] < squares[$1] }) else { return .empty }
        var lag = lagShifts[best]
        if best > 0, best < lagShifts.count - 1 {
            let before = squares[best - 1], at = squares[best], after = squares[best + 1]
            let curvature = before - 2 * at + after
            if curvature > 0 {
                lag += 0.5 * (before - after) / curvature * (lagShifts[best + 1] - lagShifts[best])
            }
        }
        return SmoothingMeasure(value: lag, count: count)
    }

    /// A reference dip below `lowLimit`.
    struct SmoothingDip: Sendable, Equatable {
        /// s since the reference date where the reference crossed the limit (interpolated between the readings either
        /// side); nil when the dip starts where the reference does (a segment's start)
        let crossing: Double?
        /// s since the reference date
        let nadirTime: Double
        /// mg/dL
        let nadir: Double
    }

    /// The reference's dips, at the readings: from the first value below `lowLimit` until one at `lowLimit +
    /// lowExitMargin` or more, inside a run of centred values of one segment.
    static func dips(_ reference: SmoothingReference) -> [SmoothingDip] {
        var dips: [SmoothingDip] = []
        var previous: (time: Double, value: Double, segment: Int)?
        var crossing: Double?
        var nadir: (time: Double, value: Double)?

        func close() {
            if let nadir {
                dips.append(SmoothingDip(crossing: crossing, nadirTime: nadir.time, nadir: nadir.value))
            }
            nadir = nil
            crossing = nil
        }

        for index in reference.times.indices {
            let time = reference.times[index]
            guard let value = reference.values[index] else {
                close()
                previous = nil
                continue
            }
            if let last = previous, last.segment != reference.segment[index] {
                close()
                previous = nil
            }
            if let low = nadir {
                if value < low.value {
                    nadir = (time, value)
                }
                if value >= lowLimit + lowExitMargin {
                    close()
                }
            } else if value < lowLimit {
                nadir = (time, value)
                crossing = previous.map { last in
                    last.time + (last.value - lowLimit) / (last.value - value) * (time - last.time)
                }
            }
            previous = (time, value, reference.segment[index])
        }
        close()
        return dips
    }

    /// The `nadirMiss` and `lowCrossingDelay` over the dips.
    private static func lows(
        loopSeconds: [Double],
        statuses: [OrefGlucoseStatus?],
        dips: [SmoothingDip]
    ) -> (nadir: SmoothingMeasure, crossing: SmoothingMeasure, notCrossed: Int) {
        var nadirs = Mean()
        var delays = Mean()
        var notCrossed = 0
        for dip in dips {
            // the loop time nearest the reference's lowest point, and one either side
            let after = loopSeconds.partitionIndex { $0 >= dip.nadirTime }
            let nearest = after < loopSeconds.count &&
                (after == 0 || loopSeconds[after] - dip.nadirTime < dip.nadirTime - loopSeconds[after - 1])
                ? after : after - 1
            if nearest >= 0 {
                let around = max(nearest - 1, 0) ... min(nearest + 1, loopSeconds.count - 1)
                if let lowest = around.compactMap({ statuses[$0]?.glucose }).min() {
                    nadirs.add(lowest - dip.nadir)
                }
            }

            guard let crossing = dip.crossing else { continue }
            // the first loop time below the limit: crossed then, or already below when the search starts
            var delay: Double?
            var index = loopSeconds.partitionIndex { $0 >= crossing - crossingWindow }
            while index < loopSeconds.count, loopSeconds[index] <= dip.nadirTime + nadirWindow {
                if let status = statuses[index], status.glucose < lowLimit {
                    delay = (loopSeconds[index] - crossing).minutes
                    break
                }
                index += 1
            }
            if let delay {
                delays.add(delay)
            } else {
                notCrossed += 1
            }
        }
        return (nadirs.measure, delays.measure, notCrossed)
    }

    /// The scores whose change is only a difference (`SmoothingChange.relative`).
    private static let differenceOnly: Set<SmoothingMetric> = [.lag, .riseError, .fallError, .nadirMiss, .lowCrossingDelay]

    /// Each score's change from the baseline's.
    private static func changes(_ scores: SmoothingScores, from baseline: SmoothingScores) -> [SmoothingMetric: SmoothingChange] {
        Dictionary(uniqueKeysWithValues: SmoothingMetric.allCases.map { metric in
            let value = scores[metric].value
            let base = baseline[metric].value
            let difference = value.flatMap { value in base.map { value - $0 } }
            let relative = differenceOnly.contains(metric) ? nil
                : difference.flatMap { difference in base.flatMap { $0 != 0 ? difference / abs($0) : nil } }
            return (metric, SmoothingChange(difference: difference, relative: relative))
        })
    }

    /// The candidates by a score, the least first, those without one last; ties in the order given.
    private static func order(
        _ candidates: [SmoothingCandidate],
        _ scores: [SmoothingScores],
        by key: (SmoothingScores) -> Double?
    ) -> [SmoothingCandidate] {
        candidates.indices
            .sorted { (key(scores[$0]) ?? .infinity, $0) < (key(scores[$1]) ?? .infinity, $1) }
            .map { candidates[$0] }
    }
}

// MARK: - The reference

/// The after-the-fact reference: `CGMStatsEngine.referenceFit` (a centred robust local quadratic) of the raw readings,
/// at the readings where it is centred, and linear between two of them in one segment.
struct SmoothingReference: Sendable {
    let halfWidth: TimeInterval
    /// s since the reference date, ascending
    let times: [Double]
    /// nil where a reading has no fit or only an edge one
    let values: [Double?]
    /// each reading's segment, by index
    let segment: [Int]

    /// - Parameters:
    ///   - readings: oldest -> newest, valid, one per timestamp (`CGMStatsEngine.cleaned`)
    ///   - segments: `CGMStatsEngine.segments` of them
    init(readings: [GlucosePoint], segments: [Range<Int>], halfWidth: TimeInterval) {
        self.halfWidth = halfWidth
        times = readings.map(\.time.timeIntervalSinceReferenceDate)
        values = CGMStatsEngine.referenceFit(readings, segments: segments, halfWidth: halfWidth)
            .map { fit in fit.flatMap { $0.isCentred ? $0.value : nil } }
        var segment = [Int](repeating: 0, count: readings.count)
        for (number, range) in segments.enumerated() {
            for index in range {
                segment[index] = number
            }
        }
        self.segment = segment
    }

    /// At a moment: the value at a reading there, else linear between the readings either side when both have one and
    /// are in one segment; nil otherwise.
    func value(at time: Double) -> Double? {
        let next = times.partitionIndex { $0 > time }
        guard next > 0 else { return nil }
        let before = next - 1
        if times[before] == time {
            return values[before]
        }
        guard next < times.count, segment[before] == segment[next],
              let from = values[before], let to = values[next]
        else { return nil }
        return from + (to - from) * (time - times[before]) / (times[next] - times[before])
    }
}
