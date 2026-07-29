import Foundation

/// Kalman smoother: a local level-and-trend model run forwards, then refined backwards (RTS).
///
/// The state is `[glucose, rate]`, with the rate decaying toward zero so an unsupported trend cannot
/// extrapolate indefinitely. Δt enters both the transition and the process noise, so the response is the
/// same on a 1-minute CGM as on a 5-minute one, and a dropout is just a large step with correspondingly
/// large uncertainty - no windowing, no invented data.
struct KalmanFilter: GlucoseSmoother {
    /// Multiplier on the process noise. Higher follows the readings more closely and lags less at a
    /// turning point; lower is smoother. 1 corresponds to the AndroidAPS tuning.
    let responsiveness: Double

    let maximumGap: TimeInterval

    init(responsiveness: Double = 1, maximumGap: TimeInterval = .minutes(60)) {
        self.responsiveness = max(responsiveness, 0.01)
        self.maximumGap = maximumGap
    }

    /// The RTS pass needs a step on either side to be worth running.
    private static let minimumSamples = 3

    /// Rate decays with this time constant, making the trend mean-reverting rather than constant-velocity.
    private static let rateDecay: Double = 30 // minutes

    /// Process noise per 5 minutes: an independent random walk in glucose and in rate. Deliberately
    /// diagonal, matching the tuning these values came from; the textbook form would add a
    /// glucose/rate cross term and change what the defaults mean.
    private static let processNoiseGlucose: Double = 1.0
    private static let processNoiseRate: Double = 0.35

    /// Measurement noise (variance, mg/dL²), before the per-batch estimate refines it.
    private static let measurementNoiseInitial: Double = 25 // ~5 mg/dL
    /// ~4 mg/dL, what AndroidAPS calls "an excellent sensor".
    private static let measurementNoiseMin: Double = 16
    private static let measurementNoiseMax: Double = 225 // ~15 mg/dL, a poor one
    private static let measurementNoiseEffectiveMax: Double = 400

    /// Below this many usable readings the noise estimate is not worth trusting.
    private static let minimumNoiseSamples = 30

    /// Turns a median absolute deviation into a standard deviation, for Gaussian noise.
    private static let madToSigma = 1.4826

    /// Residuals beyond this many standard deviations start to be treated as suspect.
    private static let outlierSigma: Double = 2

    private static let maximumRate: Double = 4 // mg/dL/min

    private static let minimumGlucoseVariance: Double = 0.1
    private static let maximumGlucoseVariance: Double = 400
    private static let minimumRateVariance: Double = 0.001
    private static let maximumRateVariance: Double = 4

    /// xDrip reports this instead of a reading when calibration fails. Other sources send nothing at all.
    private static let errorValue: Double = 38

    func smooth(_ samples: [GlucoseSample]) -> [Double] {
        let values = samples.map(\.value)
        guard values.count >= Self.minimumSamples else { return values }

        let intervals = Self.intervals(of: samples)
        let q = (
            glucose: Self.processNoiseGlucose * responsiveness,
            rate: Self.processNoiseRate * responsiveness
        )

        let r = Self.estimateMeasurementNoise(values, intervals: intervals) ?? Self.measurementNoiseInitial

        let forward = Self.forwardPass(values, intervals: intervals, q: q, r: r)
        var smoothed = Self.backwardPass(forward, intervals: intervals)

        for index in values.indices where values[index] <= Self.errorValue {
            smoothed[index] = values[index]
        }

        return smoothed
    }

    /// Minutes between each sample and the one before it; `[0]` is unused.
    private static func intervals(of samples: [GlucoseSample]) -> [Double] {
        var intervals = [Double](repeating: 0, count: samples.count)
        for index in 1 ..< samples.count {
            let minutes = samples[index].date.timeIntervalSince(samples[index - 1].date) / 60
            // Coincident or out-of-order timestamps would make the transition singular.
            intervals[index] = max(minutes, 0.1)
        }
        return intervals
    }

    // MARK: - forward pass

    /// Filtered and predicted state at one sample. The predictions are kept because the backward pass  needs them.
    private struct Step {
        var x0 = 0.0, x1 = 0.0 // filtered [glucose, rate]
        var p00 = 0.0, p01 = 0.0, p11 = 0.0 // filtered covariance (symmetric)
        var xPred0 = 0.0, xPred1 = 0.0
        var pPred00 = 0.0, pPred01 = 0.0, pPred11 = 0.0
    }

    private static func forwardPass(
        _ values: [Double],
        intervals: [Double],
        q: (glucose: Double, rate: Double),
        r: Double
    ) -> [Step] {
        var states = [Step](repeating: Step(), count: values.count)

        // Two-point initialisation: seed the rate from the first interval rather than assuming zero,
        // which would otherwise take several readings to shake off.
        var x0 = values[0]
        var x1 = ((values[1] - values[0]) / intervals[1]).clamped(to: -maximumRate ... maximumRate)
        var p00 = 16.0, p01 = 0.0, p11 = 1.0

        states[0] = Step(x0: x0, x1: x1, p00: p00, p01: p01, p11: p11)

        // The last three readings' surprise directions, used to tell a spike from a real move.
        var recentSigns: [Int] = []

        for index in 1 ..< values.count {
            let dt = intervals[index]

            p00 = p00.clamped(to: minimumGlucoseVariance ... maximumGlucoseVariance)
            p11 = p11.clamped(to: minimumRateVariance ... maximumRateVariance)

            let base = predict(x0: x0, x1: x1, p00: p00, p01: p01, p11: p11, dt: dt, q: q)

            let z = values[index]

            // An error code is not a measurement: predict, do not update.
            guard z > errorValue else {
                x0 = base.x0
                x1 = base.x1
                p00 = base.p00
                p01 = base.p01
                p11 = base.p11
                states[index] = Step(
                    x0: x0, x1: x1, p00: p00, p01: p01, p11: p11,
                    xPred0: base.x0, xPred1: base.x1,
                    pPred00: base.p00, pPred01: base.p01, pPred11: base.p11
                )
                continue
            }

            let innovation = z - base.x0
            let normalised = innovation / (base.p00 + r).squareRoot()
            let surprise = abs(normalised)

            // A run of same-signed surprises means the model is wrong, not that the reading is bad.
            let sign = normalised > 0 ? 1 : (normalised < 0 ? -1 : 0)
            recentSigns.append(surprise > outlierSigma ? sign : 0)
            if recentSigns.count > 3 { recentSigns.removeFirst() }
            let trending = sign != 0 && recentSigns.filter { $0 == sign }.count >= 2

            // Trust the reading less the further out it is (Huber-style), with a ceiling so a single
            // wild value cannot make the filter deaf.
            let rEffective = min(
                r * (1 + max(0, surprise - outlierSigma)),
                min(r + 100, measurementNoiseEffectiveMax)
            )

            // ...but when it is a real move, loosen the model instead so the filter can keep up.
            let qScale = trending ? max(surprise, 1).clamped(to: 1 ... 3) : 1
            let predicted = qScale > 1
                ? predict(
                    x0: x0, x1: x1, p00: p00, p01: p01, p11: p11, dt: dt,
                    q: (glucose: q.glucose * min(qScale, 2), rate: q.rate * qScale)
                )
                : base

            let updated = update(predicted, z: z, r: rEffective)
            x0 = updated.x0
            x1 = updated.x1
            p00 = updated.p00
            p01 = updated.p01
            p11 = updated.p11

            states[index] = Step(
                x0: x0, x1: x1, p00: p00, p01: p01, p11: p11,
                xPred0: predicted.x0, xPred1: predicted.x1,
                pPred00: predicted.p00, pPred01: predicted.p01, pPred11: predicted.p11
            )
        }

        return states
    }

    private typealias Gaussian = (x0: Double, x1: Double, p00: Double, p01: Double, p11: Double)

    /// `F = [[1, dt], [0, decay]]`, so `P' = F·P·Fᵀ + Q`.
    private static func predict(
        x0: Double, x1: Double,
        p00: Double, p01: Double, p11: Double,
        dt: Double,
        q: (glucose: Double, rate: Double)
    ) -> Gaussian {
        let decay = exp(-dt / rateDecay)
        let scale = dt / 5 // the process noise is quoted per 5 minutes

        return (
            x0: x0 + x1 * dt,
            x1: x1 * decay,
            p00: max(p00 + 2 * dt * p01 + dt * dt * p11 + q.glucose * scale, minimumGlucoseVariance),
            p01: decay * (p01 + dt * p11),
            p11: max(decay * decay * p11 + q.rate * scale, minimumRateVariance)
        )
    }

    /// Scalar measurement of the first state, so the gain is just `P[·,0] / (P₀₀ + R)`.
    private static func update(_ predicted: Gaussian, z: Double, r: Double) -> Gaussian {
        let s = predicted.p00 + r
        guard s > 1E-9 else { return predicted }

        let k0 = predicted.p00 / s
        let k1 = predicted.p01 / s
        let innovation = z - predicted.x0

        return (
            x0: predicted.x0 + k0 * innovation,
            x1: (predicted.x1 + k1 * innovation).clamped(to: -maximumRate ... maximumRate),
            p00: max(predicted.p00 * (1 - k0), minimumGlucoseVariance),
            p01: predicted.p01 * (1 - k0),
            p11: max(predicted.p11 - k1 * predicted.p01, minimumRateVariance)
        )
    }

    // MARK: - backward pass

    /// Rauch-Tung-Striebel: replays the forward estimates knowing what came after them. Only the mean
    /// is propagated - the gain needs the forward covariances, and nothing downstream wants the
    /// smoothed ones.
    private static func backwardPass(_ states: [Step], intervals: [Double]) -> [Double] {
        var smoothed = states.map(\.x0)

        // The newest sample is the one point with no future to learn from; it stays as filtered.
        var xs0 = states[states.count - 1].x0
        var xs1 = states[states.count - 1].x1

        for index in stride(from: states.count - 2, through: 0, by: -1) {
            let next = states[index + 1]
            let gain = smootherGain(states[index], next: next, dt: intervals[index + 1])

            let d0 = xs0 - next.xPred0
            let d1 = xs1 - next.xPred1

            let new0 = states[index].x0 + gain.g00 * d0 + gain.g01 * d1
            let new1 = states[index].x1 + gain.g10 * d0 + gain.g11 * d1
            xs0 = new0
            xs1 = new1
            smoothed[index] = xs0
        }

        return smoothed
    }

    /// `C = P·Fᵀ·P_pred⁻¹`
    private static func smootherGain(
        _ state: Step,
        next: Step,
        dt: Double
    ) -> (g00: Double, g01: Double, g10: Double, g11: Double) {
        let determinant = next.pPred00 * next.pPred11 - next.pPred01 * next.pPred01
        guard abs(determinant) > 1E-10 else { return (0, 0, 0, 0) }

        let decay = exp(-dt / rateDecay)

        // P·Fᵀ
        let a = state.p00 + dt * state.p01
        let b = decay * state.p01
        let c = state.p01 + dt * state.p11
        let d = decay * state.p11

        return (
            g00: (a * next.pPred11 - b * next.pPred01) / determinant,
            g01: (b * next.pPred00 - a * next.pPred01) / determinant,
            g10: (c * next.pPred11 - d * next.pPred01) / determinant,
            g11: (d * next.pPred00 - c * next.pPred01) / determinant
        )
    }

    // MARK: - measurement noise

    /// Measurement noise taken straight from the readings: how far each one sits off the straight line
    /// through its two neighbours.
    ///
    /// Deliberately *not* estimated from the filter's own innovations, which is what AndroidAPS does.
    /// That is circular - the innovations depend on the R being estimated -
    /// and it also applies a symmetric trimmed mean to `ν²`, which is chi-squared and so strongly
    /// right-skewed that trimming both tails under-reads its mean by ~42%. Together those pin the
    /// estimate at its floor for every realistic sensor, which makes the whole mechanism inert.
    private static func estimateMeasurementNoise(_ values: [Double], intervals: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }

        var residuals: [Double] = []
        residuals.reserveCapacity(values.count)

        for index in 1 ..< (values.count - 1) {
            // An error code is not a measurement, and it would poison its neighbours' residuals too.
            guard values[index - 1] > errorValue, values[index] > errorValue, values[index + 1] > errorValue
            else { continue }

            let span = intervals[index] + intervals[index + 1]
            guard span > 0 else { continue }
            let weight = intervals[index] / span

            let interpolated = values[index - 1] + weight * (values[index + 1] - values[index - 1])
            // Scaled so every residual has the same variance whatever the spacing either side.
            let scale = (1 + (1 - weight) * (1 - weight) + weight * weight).squareRoot()
            residuals.append((values[index] - interpolated) / scale)
        }

        guard residuals.count >= minimumNoiseSamples else { return nil }

        // Median absolute deviation, so real curvature and outliers do not read as noise.
        let centre = median(residuals)
        let sigma = madToSigma * median(residuals.map { abs($0 - centre) })

        return (sigma * sigma).clamped(to: measurementNoiseMin ... measurementNoiseMax)
    }

    private static func median(_ values: [Double]) -> Double {
        guard values.isNotEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
