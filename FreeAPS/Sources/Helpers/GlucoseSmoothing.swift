import Foundation

struct GlucoseSample: Sendable, Equatable {
    let date: Date
    let value: Double
    let sessionStart: Date?
}

protocol GlucoseSmoother: Sendable {
    /// longest interval between consecutive readings still treated as one continuous series
    var maximumGap: TimeInterval { get }

    /// smooth one gap-free segment.
    /// - Parameter samples: **oldest -> newest**, no gap larger than `maximumGap`, all from one CGM session.
    func smooth(_ samples: [GlucoseSample]) -> [Double]
}

enum GlucoseSmoothing {
    /// Raw values at or below this are not glucose and are never smoothed: error codes (38 is xDrip's
    /// "calibration failed") and 39, the "LOW" sentinel of Dexcom / Nightscout. The bundled oref drops them
    /// from its deltas too (`glucose > 39` in glucose-get-last, `MIN_BG_VALUE = 39` in the autoISF version).
    static let errorCodeLimit: Double = 39

    /// Smoothed values never go below this, so a valid reading cannot be smoothed into something oref drops
    /// (`<= 39`) or treats as a CGM error (`<= 10`, `=== 38` in determine-basal).
    static let minimumSmoothedValue: Double = 40

    /// Anything outside this (NaN, infinite, negative, far above what a CGM reports) is a filter fault, and the
    /// reading stays raw. A small positive undershoot is an overshoot at a turn, and is floored instead.
    private static let plausibleSmoothedValues: ClosedRange<Double> = 0 ... 1000

    /// - Parameter glucose: **newest -> oldest**
    static func smooth(_ glucose: [BloodGlucose], using smoother: GlucoseSmoother) -> [BloodGlucose] {
        guard glucose.isNotEmpty else { return glucose }

        // algorithms work oldest -> newest
        var result = Array(glucose.reversed())

        // Only CGM readings are smoothed. Error codes, fingersticks and calibrations pass through raw
        // and are left out of the series altogether, so they neither split a segment nor pull on the
        // readings around them. Sorted, because the filters run forwards in time; the store already
        // is, unless edited by hand.
        let smoothable = result.indices
            .filter { isSmoothable(result[$0]) }
            .sorted { result[$0].dateString < result[$1].dateString }
        let samples = smoothable.map {
            GlucoseSample(
                date: result[$0].dateString,
                value: Double(result[$0].glucose),
                sessionStart: result[$0].sessionStartDate
            )
        }

        var rejected = 0

        for segment in segments(of: samples, maximumGap: smoother.maximumGap) {
            let smoothed = smoother.smooth(Array(samples[segment]))
            guard smoothed.count == segment.count else {
                warning(
                    .deviceManager,
                    "smoother returned \(smoothed.count) values for \(segment.count) samples, segment left unsmoothed"
                )
                continue
            }
            for (offset, value) in smoothed.enumerated() {
                let sample = segment.lowerBound + offset
                guard plausibleSmoothedValues.contains(value) else {
                    rejected += 1
                    continue // stays raw
                }
                result[smoothable[sample]].setSmoothedValue(max(value, minimumSmoothedValue))
            }
        }

        if rejected > 0 {
            warning(.deviceManager, "smoother returned \(rejected) unusable values, those readings left unsmoothed")
        }

        return result.reversed()
    }

    private static func isSmoothable(_ glucose: BloodGlucose) -> Bool {
        glucose.type == GlucoseType.sgv.rawValue && Double(glucose.glucose) > errorCodeLimit
    }

    /// Splits `samples` (oldest -> newest) into runs no more than `maximumGap` apart and belonging to
    /// one CGM session.
    static func segments(of samples: [GlucoseSample], maximumGap: TimeInterval) -> [Range<Int>] {
        guard samples.isNotEmpty else { return [] }

        var segments: [Range<Int>] = []
        var start = 0
        // The session of the run so far: readings with no session stamp must not bridge two sensors,
        // so each reading is compared with the last stamp seen, not just its neighbour.
        var session = samples[0].sessionStart

        for index in 1 ..< samples.count {
            let gap = samples[index].date.timeIntervalSince(samples[index - 1].date)
            let next = samples[index].sessionStart
            if gap > maximumGap || !BloodGlucose.isSameSession(session, next) {
                segments.append(start ..< index)
                start = index
                session = next
            } else if let next {
                session = next
            }
        }
        segments.append(start ..< samples.count)

        return segments
    }

    /// Least-squares slope, mg/dL per minute, of the valid readings in the first `window` of `samples`
    /// (oldest -> newest). `nil` when they span less than `minimumSpan`, too little to tell a trend
    /// from noise. A two-point difference is far noisier: on a 1-minute sensor it is a minute of noise.
    static func initialSlope(
        of samples: [GlucoseSample],
        window: TimeInterval = .minutes(10),
        minimumSpan: TimeInterval = .minutes(3)
    ) -> Double? {
        let valid = samples.filter { $0.value > errorCodeLimit }
        guard let first = valid.first else { return nil }

        let points = valid.prefix(while: { $0.date.timeIntervalSince(first.date) <= window })
        guard let last = points.last, last.date.timeIntervalSince(first.date) >= minimumSpan else { return nil }

        // minutes since the first valid reading
        let x = points.map { $0.date.timeIntervalSince(first.date) / 60 }
        let y = points.map(\.value)
        let meanX = x.reduce(0, +) / Double(x.count)
        let meanY = y.reduce(0, +) / Double(y.count)

        var sxx = 0.0
        var sxy = 0.0
        for index in x.indices {
            sxx += (x[index] - meanX) * (x[index] - meanX)
            sxy += (x[index] - meanX) * (y[index] - meanY)
        }
        guard sxx > 0 else { return nil }

        return sxy / sxx
    }
}

extension GlucoseSmoothingSettings {
    var smoother: GlucoseSmoother? {
        switch algorithm {
        case .off:
            return nil
        case .savitzkyGolay:
            return SavitzkyGolayFilter(passes: savitzkyGolay.passes.rawValue)
        case .kalman:
            return KalmanFilter(responsiveness: kalman.responsiveness.processNoiseScale)
        case .exponential:
            return ExponentialFilter()
        }
    }
}

private extension BloodGlucose {
    mutating func setSmoothedValue(_ value: Double) {
        glucose = Int(value.rounded())
    }
}
