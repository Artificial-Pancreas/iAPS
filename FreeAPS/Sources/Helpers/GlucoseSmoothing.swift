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
    private static let minimumSmoothedValue: Double = 1

    /// - Parameter glucose: **newest -> oldest**
    static func smooth(_ glucose: [BloodGlucose], using smoother: GlucoseSmoother) -> [BloodGlucose] {
        guard glucose.isNotEmpty else { return glucose }

        // algorithms work oldest -> newest
        var result = Array(glucose.reversed())
        let samples = result.map {
            GlucoseSample(date: $0.dateString, value: Double($0.glucose), sessionStart: $0.sessionStartDate)
        }

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
                result[segment.lowerBound + offset].setSmoothedValue(max(value, minimumSmoothedValue))
            }
        }

        return result.reversed()
    }

    /// Splits `samples` (oldest -> newest) into runs no more than `maximumGap` apart and belonging to
    /// one CGM session.
    static func segments(of samples: [GlucoseSample], maximumGap: TimeInterval) -> [Range<Int>] {
        guard samples.isNotEmpty else { return [] }

        var segments: [Range<Int>] = []
        var start = 0

        for index in 1 ..< samples.count {
            let gap = samples[index].date.timeIntervalSince(samples[index - 1].date)
            if gap > maximumGap || isNewSession(from: samples[index - 1], to: samples[index]) {
                segments.append(start ..< index)
                start = index
            }
        }
        segments.append(start ..< samples.count)

        return segments
    }

    private static func isNewSession(from previous: GlucoseSample, to next: GlucoseSample) -> Bool {
        !BloodGlucose.isSameSession(previous.sessionStart, next.sessionStart)
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
