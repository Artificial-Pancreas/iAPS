import Foundation

/// A local quadratic fit at a reading (`CGMStatsEngine.referenceFit`): the fitted level and its slope there.
struct CGMFit: Sendable, Equatable {
    /// mg/dL
    let value: Double
    /// mg/dL per minute
    let slope: Double
    /// the value's variance in units of the readings' (the leave-one-out residual's SD is the noise's × √(1 + it));
    /// only the leave-one-out fits (the noise's) have it
    let variance: Double?
    /// readings on both sides of it went into it: an edge fit, all on one side, extrapolates
    let isCentred: Bool
}

/// Expected against received readings, and the gaps, over the readings' span.
struct CGMCoverage: Sendable, Equatable {
    var received = 0
    /// the readings every dropout is missing, a gap's or not: its expected slots, one cadence apart
    var missing = 0
    /// the gaps (`CGMGap.isGap`)
    var gaps = 0
    /// the gaps' missing slots' time (each one cadence), s
    var gapSeconds: TimeInterval = 0

    static let zero = CGMCoverage()

    var expected: Int { received + missing }
    /// received ÷ expected, 0...1; nil when nothing was expected
    var fraction: Double? { expected > 0 ? Double(received) / Double(expected) : nil }
}

/// A dropout: more than `GapDetection.Config.tolerance` cadences between two readings. It is a gap (`isGap`) when the
/// distance is also over `CGMStatsEngine.gapMinimumDistance`.
struct CGMGap: Sendable, Equatable {
    /// the reading before it
    let start: Date
    /// the reading after it
    let end: Date
    /// the cadence expected across it
    let cadence: TimeInterval
    /// the readings it is missing: the distance in cadences, rounded, less the one that arrived
    let missing: Int

    /// the missing readings' time, s
    var duration: TimeInterval { Double(missing) * cadence }
    /// the wall-clock time from the reading before it to the reading after, s (for display)
    var elapsed: TimeInterval { end.timeIntervalSince(start) }
    /// reported as a gap: over `GapDetection.Config.tolerance` cadences and over `CGMStatsEngine.gapMinimumDistance`
    var isGap: Bool { CGMStatsEngine.isGap(distance: elapsed, cadence: cadence) }
}

/// The noise: the robust SD of the readings around a local fit (`CGMStatsEngine.noise`).
struct CGMNoise: Sendable, Equatable {
    /// mg/dL
    let mgdl: Double
    /// of the level, 0...1
    let fraction: Double
    /// the readings it is of
    let count: Int
}

/// The turns of the 5-minute series (`CGMStatsEngine.turns`): the raw readings' and the reference's (the
/// physiological ones). The difference is the noise-driven turns.
struct CGMReversals: Sendable, Equatable {
    var raw = 0
    var reference = 0
    /// the time each series spans, s
    var rawSeconds: TimeInterval = 0
    var referenceSeconds: TimeInterval = 0

    var rawPerDay: Double? { rawSeconds > 0 ? Double(raw) / rawSeconds * .days(1) : nil }
    var referencePerDay: Double? { referenceSeconds > 0 ? Double(reference) / referenceSeconds * .days(1) : nil }
}

/// The rate-of-change bands, by the absolute slope (`CGMStatsEngine.rateBandEdges`).
enum CGMRateBand: Int, CaseIterable, Sendable {
    /// below 1 mg/dL/min
    case slow
    /// 1 up to 2 mg/dL/min
    case moderate
    /// 2 up to 3 mg/dL/min
    case fast
    /// 3 mg/dL/min or more
    case veryFast

    init(slope: Double) {
        let magnitude = abs(slope)
        let edges = CGMStatsEngine.rateBandEdges
        var band = 0
        while band < edges.count, magnitude >= edges[band] {
            band += 1
        }
        self = CGMRateBand(rawValue: band) ?? .veryFast
    }
}

/// A reading's slope (`CGMStatsEngine.slopes`).
struct CGMSlope: Sendable, Equatable {
    let time: Date
    /// mg/dL per minute
    let rate: Double
}

/// The rate of change: the time in each band, and the fastest rise and fall.
struct CGMRateOfChange: Sendable, Equatable {
    /// the time with a slope in each band (by `CGMRateBand.rawValue`), s
    let bandSeconds: [TimeInterval]
    let fastestRise: CGMSlope?
    let fastestFall: CGMSlope?

    var seconds: TimeInterval { bandSeconds.reduce(0, +) }

    /// of the time with a slope, 0...1
    func share(_ band: CGMRateBand) -> Double {
        seconds > 0 ? bandSeconds[band.rawValue] / seconds : 0
    }
}

/// What the CGM views show for one CGM's readings.
struct CGMStats: Sendable, Equatable {
    /// the readings counted (in the period, valid, one per timestamp)
    let readings: Int
    /// the median distance between readings, 1 or 5 minutes; nil with fewer than two readings
    let cadence: TimeInterval?
    /// from the first reading to the last: the time the coverage is over; nil without readings
    let span: DateInterval?
    let coverage: CGMCoverage
    /// the dropouts that are gaps (`CGMGap.isGap`), oldest -> newest
    let gaps: [CGMGap]
    let noise: CGMNoise?
    /// mg/dL, the SD of the change in consecutive 5-minute deltas; nil with fewer than two changes
    let deltaJitter: Double?
    let reversals: CGMReversals
    /// nil without a reading with a slope
    let rateOfChange: CGMRateOfChange?
    /// by sensor day (1: the first 24 h after a sensor start); none before the first start
    let noiseBySensorDay: [Int: CGMNoise]

    var longestGap: TimeInterval? { gaps.map(\.duration).max() }
    var gapSeconds: TimeInterval { coverage.gapSeconds }
}

/// The noise residuals of a set of readings (`CGMStatsEngine.analysed`), and where each segment's are among them: a
/// sensor's noise takes those of the segments it shares with its CGM's readings.
struct CGMSegmentResiduals: Sendable {
    /// A segment: its first and last reading's times (s since the reference date) and its readings.
    struct Key: Hashable, Sendable {
        let first: Double
        let last: Double
        let count: Int

        init(_ segment: Range<Int>, times: [Double]) {
            first = times[segment.lowerBound]
            last = times[segment.upperBound - 1]
            count = segment.count
        }
    }

    var all = CGMStatsEngine.NoiseResiduals()
    /// by segment, its residuals' indices in `all`
    var ranges: [Key: Range<Int>] = [:]
}

/// The CGM statistics, as pure functions: no Core Data, no `Date()`, no global calendar. mg/dL throughout.
///
/// **Segments.** The readings (`GlucoseStatsEngine.clean`, error codes left out) are weighed as the glucose statistics
/// weigh them (`GlucoseStatsEngine.weigh`: the cadence from the median of the recent distances, 1 or 5 min; `weighed`).
/// A distance over `GapDetection.Config.tolerance` cadences is a dropout; the readings are split at the dropouts and at
/// the sensor starts, and every fit, series and step stays inside one segment.
///
/// **Gaps** are the dropouts over `gapMinimumDistance` as well: what the gap count, the longest and the gap time
/// report. On a 5-minute sensor every dropout is one; on a 1-minute sensor a few skipped readings
/// aren't.
///
/// **Coverage** is over the readings' span (the first to the last reading in the set, never before or after them),
/// so a CGM used for part of the period isn't missing the rest; a CGM that stopped before the period's end shows no
/// trailing gap. Expected = received + each dropout's missing slots, a gap's or not.
///
/// **One CGM at a time:** `stats` of one CGM's readings is that CGM's figures; readings of different CGMs are never
/// pooled.
///
/// **Limits.** The noise is a lower bound on a sensor that filters its readings internally: its noise is
/// autocorrelated, and the local fit follows part of it.
///
/// **Speed.** The per-reading loops are `while` loops over buffers: a Debug build (the app as Xcode runs it) takes
/// about 20 times longer over a `for`-in-range loop and array subscripts, and 90 days of 1-minute readings are
/// millions of fit terms. The segments' fits run in parallel (`eachSegment`); medians are selected, not sorted. The
/// arithmetic, and its order, is that of plain loops one segment after another: the results are the same. `stats`
/// blocks its thread while the fits run: call it off the cooperative pool (a GCD queue) for long inputs.
enum CGMStatsEngine {
    // MARK: - Thresholds

    /// Values at or below this are a CGM's error codes and its LOW sentinel, not glucose
    /// (`GlucoseSmoothing.errorCodeLimit`): left out like the smoothing leaves them out.
    static let errorCodeLimit = GlucoseSmoothing.errorCodeLimit

    /// A dropout is reported as a gap only over this distance between two readings (and over
    /// `GapDetection.Config.tolerance` cadences): a 5-minute sensor's one missed reading, so a 1-minute sensor's one or
    /// few skipped readings aren't counted as gaps; they still lower the coverage.
    static let gapMinimumDistance: TimeInterval = .minutes(5)

    /// The reference's half-width: a fit over ±20 min follows a meal rise yet averages over 8 (5-min) or 40 (1-min)
    /// readings. The smoothing replay also scores against ±15 and ±25.
    static let referenceHalfWidth: TimeInterval = .minutes(20)
    /// The noise fit's half-width (the design's definition): narrow enough that a quadratic follows the glucose.
    static let noiseHalfWidth: TimeInterval = .minutes(15)
    /// The fewest readings a local fit uses (the reading itself is one, except in the leave-one-out fit): a quadratic
    /// has 3 parameters, and one more leaves a residual. A segment's edge reading with fewer gets no fit.
    static let minimumFitReadings = 4
    /// The reweighting passes of the reference fit: two take a spike's weight to zero (LOWESS uses two or three).
    static let robustPasses = 2
    /// A residual of this many times the median absolute residual gets no weight (Tukey's biweight, as in LOWESS).
    static let biweightCutoff: Double = 6
    /// The median absolute residual is at least this, mg/dL: readings are whole mg/dL, so a smaller one is rounding,
    /// and a flat line would otherwise give every reading off it no weight.
    static let residualScaleFloor: Double = 1
    /// MAD × this is the SD of normally distributed values.
    static let madToSD = 1.4826

    /// The resampled series' step: the 5-minute delta is the one oref uses, and it doesn't depend on the cadence.
    static let seriesStep: TimeInterval = .minutes(5)
    /// A turn counts once the move in the new direction reaches this, mg/dL: a flat line's rounding never scores.
    static let turnThreshold: Double = 3

    /// The least-squares slope's window, centred on the reading (half before, half after).
    static let slopeWindow: TimeInterval = .minutes(15)
    /// A slope needs readings in its window spanning at least this (`GlucoseSmoothing.initialSlope`'s minimum): over
    /// less, a trend can't be told from noise.
    static let slopeMinimumSpan: TimeInterval = .minutes(3)
    /// The slope's running sums count the minutes from an origin that moves to the reading once it is this far behind:
    /// the minutes stay small, so adding and dropping readings doesn't lose precision over a long segment.
    static let slopeOriginReach: TimeInterval = .hours(1)
    /// The rate-of-change bands' upper edges, mg/dL/min (absolute): < 1, 1–2, 2–3, ≥ 3.
    static let rateBandEdges: [Double] = [1, 2, 3]

    // MARK: - All of it

    /// The statistics of one CGM's readings over the period.
    /// - Parameters:
    ///   - readings: the CGM's readings (sgv), any order and cadence; the ones in `[period.start, period.end)` up to
    ///     `now` count
    ///   - sensorStarts: the sensor starts, any order (empty: none known); the ones before the period still date the
    ///     sensor days
    static func stats(
        readings: [GlucosePoint],
        sensorStarts: [Date],
        period: DateInterval,
        now: Date
    ) -> CGMStats {
        analysed(readings: readings, sensorStarts: sensorStarts, period: period, now: now).stats
    }

    /// `stats`, with the noise residuals of its segments: its sensors' noise takes those of the segments they share
    /// (`noise(readings:period:now:reusing:)`).
    static func analysed(
        readings: [GlucosePoint],
        sensorStarts: [Date],
        period: DateInterval,
        now: Date
    ) -> (stats: CGMStats, residuals: CGMSegmentResiduals) {
        let starts = sensorStarts.sorted()
        let w = weighed(cleaned(readings, in: period, now: now))
        let segments = Self.segments(w, sensorStarts: starts)
        let dropouts = Self.dropouts(w)

        let (times, values) = timesAndValues(w)
        let reference = robustFits(times: times, values: values, segments: segments, halfWidth: referenceHalfWidth)
        let residuals = noiseResiduals(
            times: times,
            values: values,
            segments: segments,
            referenceWeights: reference.weights
        )

        // the raw readings', and the reference's where it is centred: an edge fit's extrapolation would add turns of
        // its own
        var raw = [Double?](repeating: nil, count: values.count)
        var centred = [Double?](repeating: nil, count: values.count)
        reference.fits.withUnsafeBufferPointer { fits in
            var index = 0
            while index < fits.count {
                raw[index] = values[index]
                if let fit = fits[index], fit.isCentred {
                    centred[index] = fit.value
                }
                index += 1
            }
        }
        let rawSeries = fiveMinuteRuns(times: times, values: raw, segments: segments, nearest: true)
        let referenceSeries = fiveMinuteRuns(times: times, values: centred, segments: segments, nearest: false)
        var reversals = CGMReversals()
        for run in rawSeries {
            reversals.raw += turns(run)
            reversals.rawSeconds += Double(run.count - 1) * seriesStep
        }
        for run in referenceSeries {
            reversals.reference += turns(run)
            reversals.referenceSeconds += Double(run.count - 1) * seriesStep
        }

        let stats = CGMStats(
            readings: w.count,
            cadence: cadence(w, segments: segments),
            span: w.first.flatMap { first in w.last.map { DateInterval(start: first.time, end: $0.time) } },
            coverage: coverage(w, dropouts: dropouts),
            gaps: dropouts.filter(\.isGap),
            noise: noise(residuals.all.residuals, relative: residuals.all.relative),
            deltaJitter: deltaJitter(rawSeries),
            reversals: reversals,
            rateOfChange: rateOfChange(slopes(w, segments: segments), weights: w),
            noiseBySensorDay: noiseBySensorDay(residuals.all, sensorStarts: starts)
        )
        return (stats, residuals)
    }

    /// `stats(…).noise` of readings without sensor starts (a sensor's own), without the rest of `stats`. A segment
    /// that is one of `kept`'s (the same readings: its first and last and their count) has its residuals there: its
    /// fits are the same, a segment's fits never reach past it.
    /// - Parameter kept: the segments' residuals of a set of readings these are part of, cleaned alike (their CGM's,
    ///   `analysed`)
    static func noise(
        readings: [GlucosePoint],
        period: DateInterval,
        now: Date,
        reusing kept: CGMSegmentResiduals? = nil
    ) -> CGMNoise? {
        let w = weighed(cleaned(readings, in: period, now: now))
        let segments = Self.segments(w, sensorStarts: [])
        let (times, values) = timesAndValues(w)
        let keys = segments.map { CGMSegmentResiduals.Key($0, times: times) }
        let missing = segments.indices.filter { kept?.ranges[keys[$0]] == nil }.map { segments[$0] }
        var computed = CGMSegmentResiduals()
        if missing.isNotEmpty {
            let reference = robustFits(times: times, values: values, segments: missing, halfWidth: referenceHalfWidth)
            computed = noiseResiduals(times: times, values: values, segments: missing, referenceWeights: reference.weights)
        }
        // in the segments' order, as one run of them gives them
        var residuals: [Double] = []
        var relative: [Double] = []
        for key in keys {
            let source = kept.flatMap { $0.ranges[key] != nil ? $0 : nil } ?? computed
            guard let range = source.ranges[key] else { continue }
            residuals += source.all.residuals[range]
            relative += source.all.relative[range]
        }
        return noise(residuals, relative: relative)
    }

    /// The readings' times (s since the reference date) and values (mg/dL), for the fits.
    private static func timesAndValues(_ w: [WeightedPoint]) -> (times: [Double], values: [Double]) {
        var times = [Double](repeating: 0, count: w.count)
        var values = [Double](repeating: 0, count: w.count)
        w.withUnsafeBufferPointer { w in
            var index = 0
            while index < w.count {
                times[index] = w[index].time.timeIntervalSinceReferenceDate
                values[index] = Double(w[index].mgdl)
                index += 1
            }
        }
        return (times, values)
    }

    // MARK: - Readings and segments

    /// The readings in `[period.start, period.end)` up to `now`, error codes left out, sorted, one per timestamp
    /// (`GlucoseStatsEngine.clean`; readings already in time order, one per timestamp, as they are read, as they are).
    static func cleaned(_ readings: [GlucosePoint], in period: DateInterval, now: Date) -> [GlucosePoint] {
        var kept: [GlucosePoint] = []
        kept.reserveCapacity(readings.count)
        var isOrdered = true
        readings.withUnsafeBufferPointer { readings in
            var index = 0
            while index < readings.count {
                let point = readings[index]
                let isIn = point.time >= period.start && point.time < period.end && point.time <= now
                if Double(point.mgdl) > errorCodeLimit, isIn {
                    if isOrdered, let last = kept.last, last.time >= point.time {
                        isOrdered = false
                    }
                    kept.append(point)
                }
                index += 1
            }
        }
        return isOrdered ? kept : GlucoseStatsEngine.clean(kept)
    }

    /// `GlucoseStatsEngine.weigh`, with the cadence of a reading without distances before it (the first one, and the
    /// first after more than `GlucoseStatsEngine.cadenceHorizon`) taken from the distances after it, the way `weigh`
    /// takes it from those before (the next `cadenceWindow`, within `cadenceHorizon`), instead of the 5-minute default:
    /// a 1-minute sensor's gap right after an outage would otherwise be weighed at 5 minutes and under-counted.
    /// - Parameter sorted: oldest -> newest, as `cleaned` returns them
    static func weighed(_ sorted: [GlucosePoint]) -> [WeightedPoint] {
        var w = GlucoseStatsEngine.weigh(sorted)
        var index = -1
        while index + 2 < w.count {
            index += 1
            guard index == 0 || w[index].time.timeIntervalSince(w[index - 1].time) > GlucoseStatsEngine.cadenceHorizon
            else { continue }
            var deltas: [TimeInterval] = []
            var next = index
            while next + 1 < w.count, deltas.count < GlucoseStatsEngine.cadenceWindow,
                  w[next].time.timeIntervalSince(w[index].time) <= GlucoseStatsEngine.cadenceHorizon
            {
                deltas.append(w[next + 1].time.timeIntervalSince(w[next].time))
                next += 1
            }
            let cadence = GlucoseStatsEngine.cadence(previousDeltas: deltas)
            let delta = deltas[0]
            let span = delta <= cadence * GapDetection.Config.tolerance ? delta : cadence
            w[index] = WeightedPoint(time: w[index].time, mgdl: w[index].mgdl, span: span)
        }
        return w
    }

    /// A dropout follows reading `index`: the next one is further than its span (`weigh` caps a span at one cadence
    /// when the distance is over the tolerance).
    private static func isDropout(after index: Int, _ w: UnsafeBufferPointer<WeightedPoint>) -> Bool {
        index + 1 < w.count && w[index + 1].time.timeIntervalSince(w[index].time) > w[index].span
    }

    /// The dropout-free runs of one sensor: split at the dropouts and where a sensor starts between two readings (a start at a
    /// reading's time: that reading is the new sensor's).
    /// - Parameters:
    ///   - w: oldest -> newest, as `GlucoseStatsEngine.weigh` returns them
    ///   - sensorStarts: ascending
    static func segments(_ w: [WeightedPoint], sensorStarts: [Date]) -> [Range<Int>] {
        guard w.isNotEmpty else { return [] }
        var segments: [Range<Int>] = []
        var start = 0
        var next = 0
        w.withUnsafeBufferPointer { w in
            var index = 0
            while index + 1 < w.count {
                while next < sensorStarts.count && sensorStarts[next] <= w[index].time {
                    next += 1
                }
                let sensorStarted = next < sensorStarts.count && sensorStarts[next] <= w[index + 1].time
                if sensorStarted || isDropout(after: index, w) {
                    segments.append(start ..< index + 1)
                    start = index + 1
                }
                index += 1
            }
        }
        segments.append(start ..< w.count)
        return segments
    }

    /// The dropouts, gaps or not, oldest -> newest.
    static func dropouts(_ w: [WeightedPoint]) -> [CGMGap] {
        var dropouts: [CGMGap] = []
        w.withUnsafeBufferPointer { w in
            var index = 0
            while index < w.count {
                if isDropout(after: index, w) {
                    let cadence = w[index].span
                    let distance = w[index + 1].time.timeIntervalSince(w[index].time)
                    dropouts.append(CGMGap(
                        start: w[index].time,
                        end: w[index + 1].time,
                        cadence: cadence,
                        missing: Swift.max(Int((distance / cadence).rounded()) - 1, 1)
                    ))
                }
                index += 1
            }
        }
        return dropouts
    }

    /// A distance between two readings that is reported as a gap: over `GapDetection.Config.tolerance` cadences and
    /// over `gapMinimumDistance`.
    static func isGap(distance: TimeInterval, cadence: TimeInterval) -> Bool {
        distance > Swift.max(cadence * GapDetection.Config.tolerance, gapMinimumDistance)
    }

    /// The median distance between consecutive readings of a segment, 1 or 5 minutes
    /// (`GlucoseStatsEngine.cadence`); nil without two readings in a segment.
    static func cadence(_ w: [WeightedPoint], segments: [Range<Int>]) -> TimeInterval? {
        var deltas: [TimeInterval] = []
        deltas.reserveCapacity(w.count)
        w.withUnsafeBufferPointer { w in
            for segment in segments {
                var index = segment.lowerBound + 1
                while index < segment.upperBound {
                    deltas.append(w[index].time.timeIntervalSince(w[index - 1].time))
                    index += 1
                }
            }
        }
        return deltas.isEmpty ? nil : GlucoseStatsEngine.cadence(previousDeltas: deltas)
    }

    // MARK: - Coverage

    /// The coverage over the readings' span: every reading received, each dropout's missing slots, the gaps and
    /// their missing time.
    static func coverage(_ w: [WeightedPoint], dropouts: [CGMGap]) -> CGMCoverage {
        var coverage = CGMCoverage(received: w.count)
        for dropout in dropouts {
            coverage.missing += dropout.missing
            if dropout.isGap {
                coverage.gaps += 1
                coverage.gapSeconds += dropout.duration
            }
        }
        return coverage
    }

    // MARK: - Local fits

    /// The reference: a centred robust local quadratic over ±`halfWidth` at every reading, inside its segment; nil
    /// where the segment has fewer than `minimumFitReadings` readings within reach (its edges, a short segment).
    /// Robust: refitted `robustPasses` times, each reading weighted by Tukey's biweight of its residual, so a spike
    /// doesn't bend the fit (it gets the value of its neighbours' fit).
    /// - Parameters:
    ///   - readings: oldest -> newest, one per timestamp
    ///   - segments: the dropout-free runs (`segments`), the fit never reaches across one's edge
    static func referenceFit(
        _ readings: [GlucosePoint],
        segments: [Range<Int>],
        halfWidth: TimeInterval = referenceHalfWidth
    ) -> [CGMFit?] {
        robustFits(
            times: readings.map(\.time.timeIntervalSinceReferenceDate),
            values: readings.map { Double($0.mgdl) },
            segments: segments,
            halfWidth: halfWidth
        ).fits
    }

    /// `referenceFit`, with the readings' final robustness weights.
    private static func robustFits(
        times: [Double],
        values: [Double],
        segments: [Range<Int>],
        halfWidth: TimeInterval
    ) -> (fits: [CGMFit?], weights: [Double]) {
        var weights = Array(repeating: 1.0, count: times.count)
        var fits = [CGMFit?](repeating: nil, count: times.count)
        times.withUnsafeBufferPointer { times in
            values.withUnsafeBufferPointer { values in
                weights.withUnsafeMutableBufferPointer { weights in
                    fits.withUnsafeMutableBufferPointer { fits in
                        eachSegment(segments) { segment in
                            for pass in 0 ... robustPasses {
                                if pass > 0 {
                                    reweigh(segment, values: values, fits: fits, weights: weights)
                                }
                                localFits(
                                    times: times,
                                    values: values,
                                    weights: UnsafeBufferPointer(weights),
                                    segment: segment,
                                    halfWidth: halfWidth,
                                    leaveOneOut: false,
                                    into: fits
                                )
                            }
                        }
                    }
                }
            }
        }
        return (fits, weights)
    }

    /// `work` for each segment, in parallel (`DispatchQueue.concurrentPerform`, which returns once every one is done):
    /// a segment's fits never reach past it, so each reads and writes its own readings' slots only, and the results
    /// are those of one segment after another.
    private static func eachSegment(_ segments: [Range<Int>], _ work: (Range<Int>) -> Void) {
        DispatchQueue.concurrentPerform(iterations: segments.count) { index in
            work(segments[index])
        }
    }

    /// The biweights of a segment's readings from their residuals to the fits: 0 from `biweightCutoff` median absolute
    /// residuals; 1 for a reading without a fit.
    private static func reweigh(
        _ segment: Range<Int>,
        values: UnsafeBufferPointer<Double>,
        fits: UnsafeMutableBufferPointer<CGMFit?>,
        weights: UnsafeMutableBufferPointer<Double>
    ) {
        var residuals: [Double] = []
        residuals.reserveCapacity(segment.count)
        var index = segment.lowerBound
        while index < segment.upperBound {
            if let fit = fits[index] {
                residuals.append(abs(values[index] - fit.value))
            }
            index += 1
        }
        guard let median = Self.median(residuals) else { return }
        let limit = biweightCutoff * Swift.max(median, residualScaleFloor)
        index = segment.lowerBound
        while index < segment.upperBound {
            if let fit = fits[index] {
                let u = (values[index] - fit.value) / limit
                weights[index] = abs(u) < 1 ? (1 - u * u) * (1 - u * u) : 0
            } else {
                weights[index] = 1
            }
            index += 1
        }
    }

    /// Weighted least-squares quadratics in the minutes from each reading of the segment, over the readings within
    /// ±`halfWidth` (all but the reading itself with `leaveOneOut`); the value and slope at the reading, and with
    /// `leaveOneOut` the value's variance (only the leave-one-out residuals are corrected by it, so the other fits
    /// skip its sums).
    private static func localFits(
        times: UnsafeBufferPointer<Double>,
        values: UnsafeBufferPointer<Double>,
        weights: UnsafeBufferPointer<Double>,
        segment: Range<Int>,
        halfWidth: TimeInterval,
        leaveOneOut: Bool,
        into fits: UnsafeMutableBufferPointer<CGMFit?>
    ) {
        var low = segment.lowerBound
        var high = segment.lowerBound
        var index = segment.lowerBound
        while index < segment.upperBound {
            defer { index += 1 }
            let time = times[index]
            while times[low] < time - halfWidth {
                low += 1
            }
            while high < segment.upperBound, times[high] <= time + halfWidth {
                high += 1
            }
            // Σw x^k (k 0...4), Σw x^k y (k 0...2), Σw² x^k (k 0...4, leave-one-out only): x in minutes
            var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0
            var t0 = 0.0, t1 = 0.0, t2 = 0.0
            var q0 = 0.0, q1 = 0.0, q2 = 0.0, q3 = 0.0, q4 = 0.0
            var used = 0
            var before = false
            var after = false
            // the readings in reach, walked by pointer; the leave-one-out sums in a loop of their own (a Debug build
            // pays for every condition per term)
            var t = times.baseAddress! + low
            var v = values.baseAddress! + low
            var weight = weights.baseAddress! + low
            let end = times.baseAddress! + high
            if leaveOneOut {
                let own = times.baseAddress! + index
                while t < end {
                    let w = weight.pointee
                    if w > 0, t != own {
                        let x = (t.pointee - time) / 60
                        let x2 = x * x
                        let y = v.pointee
                        s0 += w
                        s1 += w * x
                        s2 += w * x2
                        s3 += w * x2 * x
                        s4 += w * x2 * x2
                        t0 += w * y
                        t1 += w * x * y
                        t2 += w * x2 * y
                        let ww = w * w
                        q0 += ww
                        q1 += ww * x
                        q2 += ww * x2
                        q3 += ww * x2 * x
                        q4 += ww * x2 * x2
                        before = before || x < 0
                        after = after || x > 0
                        used += 1
                    }
                    t += 1
                    v += 1
                    weight += 1
                }
            } else {
                while t < end {
                    let w = weight.pointee
                    if w > 0 {
                        let x = (t.pointee - time) / 60
                        let x2 = x * x
                        let y = v.pointee
                        s0 += w
                        s1 += w * x
                        s2 += w * x2
                        s3 += w * x2 * x
                        s4 += w * x2 * x2
                        t0 += w * y
                        t1 += w * x * y
                        t2 += w * x2 * y
                        before = before || x < 0
                        after = after || x > 0
                        used += 1
                    }
                    t += 1
                    v += 1
                    weight += 1
                }
            }
            fits[index] = nil
            guard used >= minimumFitReadings else { continue }
            // the symmetric normal matrix's cofactors; its inverse is them over the determinant
            let c00 = s2 * s4 - s3 * s3
            let c01 = s2 * s3 - s1 * s4
            let c02 = s1 * s3 - s2 * s2
            let c11 = s0 * s4 - s2 * s2
            let c12 = s1 * s2 - s0 * s3
            let det = s0 * c00 + s1 * c01 + s2 * c02
            // readings at fewer than three distinct times: no quadratic
            guard det.isFinite, det > 1E-9 * s0 * s2 * s4 else { continue }
            let value = (c00 * t0 + c01 * t1 + c02 * t2) / det
            let slope = (c01 * t0 + c11 * t1 + c12 * t2) / det
            // the value's weights are m = M⁻¹e₀ against the data: its variance is mᵀ (Σw² x^(j+k)) m
            var variance: Double?
            if leaveOneOut {
                let m0 = c00 / det, m1 = c01 / det, m2 = c02 / det
                variance = m0 * (q0 * m0 + q1 * m1 + q2 * m2)
                    + m1 * (q1 * m0 + q2 * m1 + q3 * m2)
                    + m2 * (q2 * m0 + q3 * m1 + q4 * m2)
            }
            fits[index] = CGMFit(value: value, slope: slope, variance: variance, isCentred: before && after)
        }
    }

    // MARK: - Noise

    /// The readings' noise residuals: raw less the leave-one-out fit, scaled to the noise's SD (÷ √(1 + the fit's
    /// variance)), in mg/dL and of the fitted level; with the readings' times (s since the reference date), ascending.
    struct NoiseResiduals: Sendable, Equatable {
        var times: [Double] = []
        var residuals: [Double] = []
        var relative: [Double] = []
    }

    /// The noise residuals of every reading with a leave-one-out quadratic over ±`noiseHalfWidth`. The readings the
    /// reference gave no weight (spikes) are left out of the fits, so a spike doesn't bend its neighbours'; the others
    /// count in full: a weight that shrinks with a reading's own noise would make the fit's variance smaller than the
    /// correction assumes, and the noise come out low (by about 15 % at 5 minutes).
    private static func noiseResiduals(
        times: [Double],
        values: [Double],
        segments: [Range<Int>],
        referenceWeights: [Double]
    ) -> CGMSegmentResiduals {
        var weights = [Double](repeating: 0, count: referenceWeights.count)
        referenceWeights.withUnsafeBufferPointer { reference in
            var index = 0
            while index < reference.count {
                weights[index] = reference[index] > 0 ? 1 : 0
                index += 1
            }
        }
        var fits = [CGMFit?](repeating: nil, count: times.count)
        times.withUnsafeBufferPointer { times in
            values.withUnsafeBufferPointer { values in
                weights.withUnsafeBufferPointer { weights in
                    fits.withUnsafeMutableBufferPointer { fits in
                        eachSegment(segments) { segment in
                            localFits(
                                times: times,
                                values: values,
                                weights: weights,
                                segment: segment,
                                halfWidth: noiseHalfWidth,
                                leaveOneOut: true,
                                into: fits
                            )
                        }
                    }
                }
            }
        }
        var residuals = CGMSegmentResiduals()
        fits.withUnsafeBufferPointer { fits in
            for segment in segments where !segment.isEmpty {
                let first = residuals.all.residuals.count
                var index = segment.lowerBound
                while index < segment.upperBound {
                    if let fit = fits[index], fit.value > 0 {
                        let residual = (values[index] - fit.value) / (1 + (fit.variance ?? 0)).squareRoot()
                        residuals.all.times.append(times[index])
                        residuals.all.residuals.append(residual)
                        residuals.all.relative.append(residual / fit.value)
                    }
                    index += 1
                }
                residuals.ranges[CGMSegmentResiduals.Key(segment, times: times)] = first ..< residuals.all.residuals.count
            }
        }
        return residuals
    }

    /// The noise of a set of readings: the robust SD (`robustSD`) of their residuals and relative residuals; nil with
    /// fewer than two.
    static func noise(_ residuals: [Double], relative: [Double]) -> CGMNoise? {
        guard residuals.count >= 2, let mgdl = robustSD(residuals), let fraction = robustSD(relative) else { return nil }
        return CGMNoise(mgdl: mgdl, fraction: fraction, count: residuals.count)
    }

    /// `madToSD` × the median absolute deviation from the median; nil without values.
    static func robustSD(_ values: [Double]) -> Double? {
        guard let center = median(values) else { return nil }
        var deviations = [Double](repeating: 0, count: values.count)
        values.withUnsafeBufferPointer { values in
            var index = 0
            while index < values.count {
                deviations[index] = abs(values[index] - center)
                index += 1
            }
        }
        return median(deviations).map { $0 * madToSD }
    }

    /// The median (of an even count, the mean of the middle two); nil without values. Selected, not sorted: the
    /// middle value is the same, in a linear time.
    static func median(_ values: [Double]) -> Double? {
        guard values.isNotEmpty else { return nil }
        var copy = values
        return copy.withUnsafeMutableBufferPointer { values in
            let middle = values.count / 2
            let upper = select(middle, in: values)
            guard values.count.isMultiple(of: 2) else { return upper }
            // the values before the middle are the smaller ones: the largest of them is the one under it
            var lower = values[0]
            var index = 1
            while index < middle {
                lower = Swift.max(lower, values[index])
                index += 1
            }
            return (lower + upper) / 2
        }
    }

    /// The `k`-th smallest of the values (from 0), by quickselect (Hoare's partition, the median of three as the
    /// pivot): the values reordered so that those before `k` are no larger and those after it no smaller.
    private static func select(_ k: Int, in values: UnsafeMutableBufferPointer<Double>) -> Double {
        var low = 0
        var high = values.count - 1
        while low < high {
            let a = values[low], b = values[low + (high - low) / 2], c = values[high]
            let pivot = Swift.max(Swift.min(a, b), Swift.min(Swift.max(a, b), c))
            var i = low
            var j = high
            while i <= j {
                while values[i] < pivot {
                    i += 1
                }
                while values[j] > pivot {
                    j -= 1
                }
                if i <= j {
                    values.swapAt(i, j)
                    i += 1
                    j -= 1
                }
            }
            // [low, j] no larger than the pivot, [i, high] no smaller, between them the pivot
            if k <= j {
                high = j
            } else if k >= i {
                low = i
            } else {
                return values[k]
            }
        }
        return values[k]
    }

    /// The noise by sensor day: each residual in the day of the sensor start before it (`sensorDay`).
    /// - Parameter sensorStarts: ascending
    private static func noiseBySensorDay(_ residuals: NoiseResiduals, sensorStarts: [Date]) -> [Int: CGMNoise] {
        var byDay: [Int: NoiseResiduals] = [:]
        // a run of residuals of one sensor day, added to it at its end
        var run = NoiseResiduals()
        var runDay: Int?
        func addRun() {
            guard let runDay else { return }
            byDay[runDay, default: NoiseResiduals()].residuals += run.residuals
            byDay[runDay, default: NoiseResiduals()].relative += run.relative
            run = NoiseResiduals()
        }
        let starts = sensorStarts.map(\.timeIntervalSinceReferenceDate)
        var next = 0
        var index = 0
        while index < residuals.times.count {
            defer { index += 1 }
            let time = residuals.times[index]
            while next < starts.count, starts[next] <= time {
                next += 1
            }
            guard next > 0 else { continue }
            let day = Int((time - starts[next - 1]) / .days(1)) + 1
            if day != runDay {
                addRun()
                runDay = day
            }
            run.residuals.append(residuals.residuals[index])
            run.relative.append(residuals.relative[index])
        }
        addRun()
        return byDay.compactMapValues { noise($0.residuals, relative: $0.relative) }
    }

    /// The sensor day of a moment: 1 in the 24 h from the last sensor start at or before it, 2 in the next 24 h, ...;
    /// nil before the first start.
    /// - Parameter sensorStarts: ascending
    static func sensorDay(of time: Date, sensorStarts: [Date]) -> Int? {
        let next = sensorStarts.partitionIndex { $0 > time }
        guard next > 0 else { return nil }
        return Int(time.timeIntervalSince(sensorStarts[next - 1]) / .days(1)) + 1
    }

    // MARK: - The 5-minute series

    /// The values resampled onto a 5-minute grid inside each segment, anchored at its first reading (its time plus
    /// multiples of `seriesStep`), so where a sensor's timestamps fall doesn't change the series. With `nearest` (the
    /// raw readings) a grid time takes the reading nearest it as it is when one is within half the segment's cadence,
    /// and is interpolated linearly between the readings around it only where none is: interpolating would average
    /// readings and smooth away the noise the series measures. Without (the smooth reference) it is always
    /// interpolated. A run ends at a segment's end and where a value is missing (nil: a reading without a reference
    /// fit).
    /// - Parameter times: s since the reference date, ascending
    static func fiveMinuteRuns(times: [Double], values: [Double?], segments: [Range<Int>], nearest: Bool) -> [[Double]] {
        var runs: [[Double]] = []
        for segment in segments where !segment.isEmpty {
            let reach = nearest ? (cadence(times: times, segment: segment) ?? seriesStep) / 2 : -1
            times.withUnsafeBufferPointer { times in
                values.withUnsafeBufferPointer { values in
                    var run: [Double] = []
                    let first = times[segment.lowerBound]
                    let last = times[segment.upperBound - 1]
                    var before = segment.lowerBound
                    var step = 0.0
                    while first + step * seriesStep <= last {
                        let grid = first + step * seriesStep
                        step += 1
                        while before + 1 < segment.upperBound, times[before + 1] <= grid {
                            before += 1
                        }
                        let after = before + 1 < segment.upperBound ? before + 1 : before
                        let toBefore = grid - times[before]
                        let toAfter = after > before ? times[after] - grid : .infinity
                        var value: Double?
                        if toBefore == 0 {
                            value = values[before]
                        } else if Swift.min(toBefore, toAfter) <= reach {
                            value = toBefore <= toAfter ? values[before] : values[after]
                        } else if after > before, let from = values[before], let to = values[after] {
                            value = from + (to - from) * toBefore / (times[after] - times[before])
                        }
                        if let value {
                            run.append(value)
                        } else if run.isNotEmpty {
                            runs.append(run)
                            run = []
                        }
                    }
                    if run.isNotEmpty {
                        runs.append(run)
                    }
                }
            }
        }
        return runs
    }

    /// The median distance between a segment's consecutive readings, 1 or 5 minutes (`GlucoseStatsEngine.cadence`);
    /// nil with fewer than two readings.
    private static func cadence(times: [Double], segment: Range<Int>) -> TimeInterval? {
        guard segment.count >= 2 else { return nil }
        var deltas: [TimeInterval] = []
        deltas.reserveCapacity(segment.count - 1)
        times.withUnsafeBufferPointer { times in
            var index = segment.lowerBound + 1
            while index < segment.upperBound {
                deltas.append(times[index] - times[index - 1])
                index += 1
            }
        }
        return GlucoseStatsEngine.cadence(previousDeltas: deltas)
    }

    /// The SD of the change in consecutive 5-minute deltas over the runs, mg/dL; nil with fewer than two changes.
    static func deltaJitter(_ runs: [[Double]]) -> Double? {
        var changes: [Double] = []
        for run in runs where run.count >= 3 {
            for index in 2 ..< run.count {
                changes.append(run[index] - 2 * run[index - 1] + run[index - 2])
            }
        }
        guard changes.count >= 2 else { return nil }
        let mean = changes.reduce(0, +) / Double(changes.count)
        let squares = changes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (squares / Double(changes.count - 1)).squareRoot()
    }

    /// The turns of a series: the direction flips and the move in the new direction reaches `turnThreshold` (the first
    /// direction taken is not a turn).
    static func turns(_ series: [Double]) -> Int {
        guard let first = series.first else { return 0 }
        var direction = 0
        var extreme = first
        var low = first
        var high = first
        var turns = 0
        for value in series.dropFirst() {
            switch direction {
            case 0:
                low = Swift.min(low, value)
                high = Swift.max(high, value)
                if value - low >= turnThreshold {
                    direction = 1
                    extreme = value
                } else if high - value >= turnThreshold {
                    direction = -1
                    extreme = value
                }
            case 1:
                if value > extreme {
                    extreme = value
                } else if extreme - value >= turnThreshold {
                    turns += 1
                    direction = -1
                    extreme = value
                }
            default:
                if value < extreme {
                    extreme = value
                } else if value - extreme >= turnThreshold {
                    turns += 1
                    direction = 1
                    extreme = value
                }
            }
        }
        return turns
    }

    // MARK: - Rate of change

    /// Each reading's least-squares slope over `slopeWindow` centred on it, inside its segment, from running sums as
    /// the window slides (no allocation per reading); nil where the readings in reach span less than
    /// `slopeMinimumSpan`.
    static func slopes(_ w: [WeightedPoint], segments: [Range<Int>]) -> [Double?] {
        var slopes = [Double?](repeating: nil, count: w.count)
        let half = slopeWindow / 2
        w.withUnsafeBufferPointer { w in
            for segment in segments where !segment.isEmpty {
                var sums = SlopeSums(origin: w[segment.lowerBound].time)
                var low = segment.lowerBound
                var high = segment.lowerBound
                var index = segment.lowerBound
                while index < segment.upperBound {
                    defer { index += 1 }
                    let time = w[index].time
                    while high < segment.upperBound, w[high].time.timeIntervalSince(time) <= half {
                        sums.add(w[high], sign: 1)
                        high += 1
                    }
                    while w[low].time.timeIntervalSince(time) < -half {
                        sums.add(w[low], sign: -1)
                        low += 1
                    }
                    if time.timeIntervalSince(sums.origin) > slopeOriginReach {
                        sums = SlopeSums(origin: time)
                        var neighbour = low
                        while neighbour < high {
                            sums.add(w[neighbour], sign: 1)
                            neighbour += 1
                        }
                    }
                    guard w[high - 1].time.timeIntervalSince(w[low].time) >= slopeMinimumSpan else { continue }
                    slopes[index] = sums.slope
                }
            }
        }
        return slopes
    }

    /// A least-squares line's running sums: n, Σx, Σy, Σxy, Σx², x in minutes from `origin`.
    private struct SlopeSums {
        let origin: Date
        private var n = 0.0
        private var x = 0.0
        private var y = 0.0
        private var xy = 0.0
        private var xx = 0.0

        init(origin: Date) {
            self.origin = origin
        }

        /// Adds a reading (`sign` 1) or drops one (-1).
        mutating func add(_ point: WeightedPoint, sign: Double) {
            let px = point.time.timeIntervalSince(origin) / 60
            let py = Double(point.mgdl)
            n += sign
            x += sign * px
            y += sign * py
            xy += sign * px * py
            xx += sign * px * px
        }

        /// mg/dL per minute; nil without two readings at different times
        var slope: Double? {
            guard n >= 2 else { return nil }
            let sxx = xx - x * x / n
            guard sxx > 0 else { return nil }
            return (xy - x * y / n) / sxx
        }
    }

    /// The time in each rate band (each reading's span, `weigh`), and the fastest rise and fall; nil without a slope.
    static func rateOfChange(_ slopes: [Double?], weights w: [WeightedPoint]) -> CGMRateOfChange? {
        var seconds = Array(repeating: 0.0, count: CGMRateBand.allCases.count)
        var rise: CGMSlope?
        var fall: CGMSlope?
        var any = false
        slopes.withUnsafeBufferPointer { slopes in
            w.withUnsafeBufferPointer { w in
                var index = 0
                while index < slopes.count {
                    defer { index += 1 }
                    guard let slope = slopes[index] else { continue }
                    any = true
                    seconds[CGMRateBand(slope: slope).rawValue] += w[index].span
                    if slope > 0, slope > rise?.rate ?? 0 {
                        rise = CGMSlope(time: w[index].time, rate: slope)
                    }
                    if slope < 0, slope < fall?.rate ?? 0 {
                        fall = CGMSlope(time: w[index].time, rate: slope)
                    }
                }
            }
        }
        guard any else { return nil }
        return CGMRateOfChange(bandSeconds: seconds, fastestRise: rise, fastestFall: fall)
    }
}
