import Foundation

struct DetectedGap: Equatable, Hashable, Sendable {
    /// the last occurrence before the gap
    let start: Date
    /// the first occurrence after the gap (or "now" for an ongoing gap)
    let end: Date
    /// the cadence that was expected across the gap
    let interval: TimeInterval
    /// the gap is still growing
    let ongoing: Bool
}

/// Finds the gaps in a series of events that happen every 5 minutes (or every minute, when the
/// 1-minute loop is on and the CGM delivers that often).
///
/// The CGM readings and the loop cycles share that cadence, so the same detection serves both:
/// `GlucoseGap` for the readings, `LoopGap` for the cycles.
enum GapDetection {
    enum Config {
        /// A gap is reported when it exceeds the expected interval by this factor.
        /// It has to stay below 2, so that a single missing occurrence is caught.
        static let tolerance: Double = 1.5
        static let supportedReadingIntervals: [TimeInterval] = [.minutes(1), .minutes(5)]
        static let defaultLoopInterval: TimeInterval = .minutes(5)
        /// How many of the preceding distances define the cadence at a given point.
        /// A change of cadence (a sensor swap) is picked up after half of them.
        static let cadenceWindow = 10
    }

    /// True when the most recent occurrences arrived at a steady cadence, with none missing in between
    /// and the newest one still current.
    /// dates MUST BE newest -> oldest
    static func isComplete(
        _ dates: some Collection<Date>,
        now: Date = Date(),
        readings: Int = 3
    ) -> Bool {
        let recent = Array(dates.prefix(readings))
        guard recent.count == readings, let newest = recent.first else { return false }

        let deltas = zip(recent, recent.dropFirst()).map { $0.timeIntervalSince($1) }
        guard let shortest = deltas.min(), let cadence = nearestSupportedInterval(to: shortest) else { return false }

        let threshold = cadence * Config.tolerance

        return deltas.allSatisfy { $0 <= threshold } && now.timeIntervalSince(newest) <= threshold
    }

    /// oldest -> newest
    static func detect(
        in dates: [Date],
        allowOneMinuteLoop: Bool,
        now: Date = Date()
    ) -> [DetectedGap] {
        let dates = dates.sorted()

        guard dates.count >= 2 else { return [] }

        var gaps: [DetectedGap] = []
        // the distances between the most recent occurrences, gaps included: the median tolerates the
        // occasional outage, and a permanent change of cadence has to be able to move it
        var recentDeltas: [TimeInterval] = []

        for (previous, next) in zip(dates, dates.dropFirst()) {
            let delta = next.timeIntervalSince(previous)
            guard delta > 0 else { continue } // duplicate timestamps

            let interval = expectedInterval(recentDeltas: recentDeltas, allowOneMinuteLoop: allowOneMinuteLoop)
            if delta > interval * Config.tolerance {
                gaps.append(
                    DetectedGap(start: previous, end: next, interval: interval, ongoing: false)
                )
            }

            recentDeltas.append(delta)
            if recentDeltas.count > Config.cadenceWindow {
                recentDeltas.removeFirst()
            }
        }

        // an ongoing gap: the last occurrence is older than the threshold
        let interval = expectedInterval(recentDeltas: recentDeltas, allowOneMinuteLoop: allowOneMinuteLoop)
        if let last = dates.last, now.timeIntervalSince(last) > interval * Config.tolerance {
            gaps.append(
                DetectedGap(start: last, end: now, interval: interval, ongoing: true)
            )
        }

        return gaps
    }

    /// Loops run every 5 minutes unless 1-minute loops are enabled *and* the sensor delivers that often.
    /// Without anything to go by (start of the history) the 5 minutes are the conservative answer.
    private static func expectedInterval(recentDeltas: [TimeInterval], allowOneMinuteLoop: Bool) -> TimeInterval {
        guard allowOneMinuteLoop, let cadence = cadence(recentDeltas) else {
            return Config.defaultLoopInterval
        }
        return min(cadence, Config.defaultLoopInterval)
    }

    /// The median distance between the recent occurrences, snapped to a supported sensor interval.
    private static func cadence(_ deltas: [TimeInterval]) -> TimeInterval? {
        guard deltas.isNotEmpty else { return nil }

        let sorted = deltas.sorted()
        let median = sorted[sorted.count / 2]

        return nearestSupportedInterval(to: median)
    }

    private static func nearestSupportedInterval(to delta: TimeInterval) -> TimeInterval? {
        Config.supportedReadingIntervals.min { abs($0 - delta) < abs($1 - delta) }
    }
}

extension TimeInterval {
    /// "15 min"
    var minutesText: String {
        let minutes = Int((self / 60).rounded())
        return "\(minutes) " + NSLocalizedString("min", comment: "Minutes abbreviation")
    }
}
