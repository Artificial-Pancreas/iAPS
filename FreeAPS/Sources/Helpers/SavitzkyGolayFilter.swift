import Foundation

/// Savitzky-Golay smoothing: a local least-squares quadratic evaluated at each sample.
///
/// Both the abscissa and the window are real time rather than sample indices, so missed readings and
/// jittery timestamps do not distort the fit, and the response is the same on a 1-minute CGM as on a
/// 5-minute one.
///
/// see also https://github.com/JohanDegraeve/xdripswift/wiki/Libre-value-smoothing
struct SavitzkyGolayFilter: GlucoseSmoother {
    /// Half the window's width, in time: 7 readings at a 5-minute cadence, 33 at a 1-minute one.
    ///
    /// Deliberately not a whole number of readings: on an exact grid 16.25 minutes puts every window edge
    /// 1.25 minutes from the nearest 5-minute reading (15 s from the nearest 1-minute one). The centre and
    /// the edge readings can both be jittered, so a reading stays on the same side of an edge as long as the
    /// two jitters together stay under that margin - a few seconds at either cadence, well over a minute at 5.
    /// At exactly 15 minutes the two outermost readings sat on the edges, and any jitter flipped the window
    /// between 6 and 7 of them.
    let halfWidth: TimeInterval

    let passes: Int

    let maximumGap: TimeInterval

    init(
        halfWidth: TimeInterval = .minutes(16.25),
        passes: Int = 3,
        maximumGap: TimeInterval = .minutes(15)
    ) {
        self.halfWidth = max(halfWidth, 1)
        self.passes = max(passes, 1)
        self.maximumGap = maximumGap
    }

    private static let minimumWindowSamples = 4

    func smooth(_ samples: [GlucoseSample]) -> [Double] {
        var values = samples.map(\.value)
        guard values.count >= Self.minimumWindowSamples else { return values }

        let times = samples.map(\.date.timeIntervalSinceReferenceDate)

        let windows = Self.windows(times: times, halfWidth: halfWidth)

        for _ in 0 ..< passes {
            values = Self.onePass(values, times: times, windows: windows, halfWidth: halfWidth)
        }
        return values
    }

    private struct Window {
        let range: Range<Int>
        let centre: TimeInterval
    }

    /// Slid inwards near either end, so every sample gets a full window evaluated off-centre rather
    /// than a truncated one-sided one.
    private static func windows(times: [TimeInterval], halfWidth: TimeInterval) -> [Window] {
        let count = times.count
        let first = times[0]
        let last = times[count - 1]

        // Shorter than one full window: every sample is fitted to all of them.
        guard last - first > 2 * halfWidth else {
            let window = Window(range: 0 ..< count, centre: (first + last) / 2)
            return Array(repeating: window, count: count)
        }

        var windows: [Window] = []
        windows.reserveCapacity(count)

        var start = 0
        var end = 0

        for index in 0 ..< count {
            // The slid windows take the end sample itself as their edge rather than recomputing it from
            // the centre, where rounding could leave the first or the newest reading out of its own window.
            let centre: TimeInterval
            let lower: TimeInterval
            let upper: TimeInterval
            if times[index] <= first + halfWidth {
                centre = first + halfWidth
                lower = first
                upper = first + 2 * halfWidth
            } else if times[index] >= last - halfWidth {
                centre = last - halfWidth
                lower = last - 2 * halfWidth
                upper = last
            } else {
                centre = times[index]
                lower = centre - halfWidth
                upper = centre + halfWidth
            }
            while start < count, times[start] < lower { start += 1 }
            while end < count, times[end] <= upper { end += 1 }
            // `max` only matters for out-of-order input, where the two edges can cross.
            windows.append(Window(range: start ..< max(start, end), centre: centre))
        }

        return windows
    }

    /// With a real-time abscissa the odd moments no longer vanish, so `y = a + b·x + c·x²` needs the
    /// full 3x3 normal equations. `x` is scaled to roughly [-1, 1] to keep the fourth moment sane.
    private static func onePass(
        _ values: [Double],
        times: [TimeInterval],
        windows: [Window],
        halfWidth: TimeInterval
    ) -> [Double] {
        var smoothed = values

        for (index, window) in windows.enumerated() {
            guard window.range.count >= minimumWindowSamples else { continue }

            var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0
            var t0 = 0.0, t1 = 0.0, t2 = 0.0

            for sample in window.range {
                let x = (times[sample] - window.centre) / halfWidth
                let y = values[sample]
                let x2 = x * x
                s0 += 1
                s1 += x
                s2 += x2
                s3 += x2 * x
                s4 += x2 * x2
                t0 += y
                t1 += x * y
                t2 += x2 * y
            }

            // Adjugate of the symmetric moment matrix [[s0, s1, s2], [s1, s2, s3], [s2, s3, s4]].
            let a00 = s2 * s4 - s3 * s3
            let a01 = s2 * s3 - s1 * s4
            let a02 = s1 * s3 - s2 * s2
            let a11 = s0 * s4 - s2 * s2
            let a12 = s1 * s2 - s0 * s3
            let a22 = s0 * s2 - s1 * s1

            let determinant = s0 * a00 + s1 * a01 + s2 * a02

            // Singular only for near-coincident timestamps; `s0³` makes the bound sample-count free.
            guard determinant > 1E-9 * s0 * s0 * s0 else { continue }

            let a = (a00 * t0 + a01 * t1 + a02 * t2) / determinant
            let b = (a01 * t0 + a11 * t1 + a12 * t2) / determinant
            let c = (a02 * t0 + a12 * t1 + a22 * t2) / determinant

            // Zero away from the ends, where the window is centred on the sample.
            let x = (times[index] - window.centre) / halfWidth
            smoothed[index] = a + b * x + c * x * x
        }

        return smoothed
    }
}
