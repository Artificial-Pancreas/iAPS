import Foundation

/// Exponential smoothing: a weighted blend of first-order exponential smoothing and second-order (Holt)
/// smoothing, which carries a trend term.
///
/// From AndroidAPS's `ExponentialSmoothingPlugin`, constants included. First order responds quickly at the
/// cost of smoothness; Holt follows a sustained rise or fall without lagging behind it, but overshoots when
/// one ends. The blend is a compromise between the two.
///
/// Unlike Savitzky-Golay and the Kalman smoother this is **causal only** - there is no backward pass, so
/// every value is computed from its own past alone and nothing is revised once newer readings arrive.
/// Historical points therefore lag visibly on the chart, where the other two do not.
///
/// One deliberate deviation: AndroidAPS applies its smoothing factors per *reading*, with no notion of
/// elapsed time, so the filter's time constant follows the CGM's cadence rather than the clock (7.2 min at
/// 5-minute readings, 1.4 min at 1-minute ones - five times weaker). Here they are converted to the real
/// interval, leaving 5-minute behaviour unchanged and giving a 1-minute sensor the same response.
///
/// The Holt trend needs more than that conversion to survive a fast sensor - see `beta` in `smooth`.
/// It is the fragile half of the blend: on raw 1-minute readings, Holt alone produces 58 visible
/// reversals against the raw data's 32, where the first-order half alone produces 1.
struct ExponentialFilter: GlucoseSmoother {
    let maximumGap: TimeInterval

    /// AndroidAPS ends its window at the first gap of 12 minutes or more; segmentation does that for us.
    init(maximumGap: TimeInterval = .minutes(12)) {
        self.maximumGap = maximumGap
    }

    /// Weight of the first-order estimate in the blend; the remainder is Holt.
    private static let firstOrderWeight = 0.4
    private static let firstOrderAlpha = 0.5

    /// Holt's level and trend factors. `beta = 1` makes the trend exactly the last change in level,
    /// which is safe only because AndroidAPS always runs on a 5-minute grid. See the cap in `smooth`.
    private static let secondOrderAlpha = 0.4
    private static let secondOrderBeta = 1.0

    /// The interval the factors above are quoted for.
    private static let referenceInterval: Double = 5 // minutes

    private static let minimumSamples = 4

    /// Coincident or out-of-order timestamps are treated as this far apart (0.1 minute, in reference
    /// intervals), as the Kalman smoother does, so the reading still gets a smoothed value.
    private static let minimumStep = 0.1 / referenceInterval

    /// A first interval at least this long (in reference intervals) is a 5-minute sensor's.
    private static let referenceCadenceStep = 0.8

    /// xDrip reports this instead of a reading when calibration fails.
    private static let errorValue: Double = 38

    func smooth(_ samples: [GlucoseSample]) -> [Double] {
        let values = samples.map(\.value)
        var smoothed = values

        // An error code would poison a recursive filter, so - as AndroidAPS does - only the readings newer
        // than the most recent one are smoothed. The rest pass through raw.
        let start = values.lastIndex { $0 <= Self.errorValue }.map { $0 + 1 } ?? 0
        guard values.count - start >= Self.minimumSamples else { return values }

        var level = values[start]
        var holtLevel = values[start]
        var holtTrend = Self.initialTrend(Array(samples[start...]))

        for index in (start + 1) ..< values.count {
            let step = max(Self.step(from: samples[index - 1], to: samples[index]), Self.minimumStep)

            // `1 - alpha` is what survives one reference interval, so it compounds over the real one.
            let alpha1 = 1 - pow(1 - Self.firstOrderAlpha, step)
            let alpha2 = 1 - pow(1 - Self.secondOrderAlpha, step)
            // The trend needs a second bound. Compounding cannot rescale `beta = 1`: nothing survives
            // one interval, so nothing survives a fraction of one either, and it stays pinned at 1
            // while every other factor shrinks. The trend is then the last change divided by the step,
            // which on a 1-minute sensor is a minute of noise scaled up fivefold and then
            // extrapolated - the filter ends up adding jitter rather than removing it (measured on a
            // raw 1-minute Libre 3 day: 32 visible reversals before smoothing, 36 after; 4 with this
            // cap). Capping the weight at the step says the trend cannot be refreshed faster than the
            // reference interval allows. At the reference cadence the cap is 1 and changes nothing, so
            // 5-minute behaviour stays bit-identical.
            let beta = min(step, 1 - pow(1 - Self.secondOrderBeta, step))

            level += alpha1 * (values[index] - level)

            // The trend is held per reference interval, so it is projected over the step and normalised back.
            let previousLevel = holtLevel
            holtLevel = alpha2 * values[index] + (1 - alpha2) * (holtLevel + holtTrend * step)
            holtTrend = beta * (holtLevel - previousLevel) / step + (1 - beta) * holtTrend

            smoothed[index] = Self.firstOrderWeight * level + (1 - Self.firstOrderWeight) * holtLevel
        }

        return smoothed
    }

    /// Elapsed time in reference intervals.
    private static func step(from previous: GlucoseSample, to next: GlucoseSample) -> Double {
        next.date.timeIntervalSince(previous.date) / 60 / referenceInterval
    }

    /// Holt's trend is held per reference interval.
    ///
    /// On a 5-minute sensor this is AndroidAPS's first difference, so its output is unchanged. On a
    /// faster one the first difference, scaled up to 5 minutes, is a minute of noise multiplied by five,
    /// and `beta`'s cap keeps it around for many readings: in simulation the newest value then came out
    /// several times noisier than the raw readings for the first 10-15 minutes of a segment. A slope
    /// fitted over the first minutes does not.
    private static func initialTrend(_ samples: [GlucoseSample]) -> Double {
        let firstStep = step(from: samples[0], to: samples[1])
        if firstStep >= referenceCadenceStep {
            return (samples[1].value - samples[0].value) / firstStep
        }
        return (GlucoseSmoothing.initialSlope(of: samples) ?? 0) * referenceInterval
    }
}
