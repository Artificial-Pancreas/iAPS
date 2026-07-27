import Foundation

/// A period without CGM readings.
struct GlucoseGap: Identifiable, Equatable, Hashable, Sendable {
    /// last reading before the gap
    let start: Date
    /// first reading after the gap (or "now" for an ongoing gap)
    let end: Date
    let loopInterval: TimeInterval
    /// the gap is still growing
    let ongoing: Bool

    var id: Date { start }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var skippedLoops: Int {
        max(1, Int((duration / loopInterval).rounded()) - 1)
    }

    var summary: String {
        let minutes = Int((duration / 60).rounded())
        let durationText = "\(minutes) " + NSLocalizedString("min", comment: "Minutes abbreviation")
        let loopsText = skippedLoops == 1 ?
            NSLocalizedString("1 skipped loop", comment: "Skipped loop cycles") :
            String(format: NSLocalizedString("%d skipped loops", comment: "Skipped loop cycles"), skippedLoops)

        let text = String(
            format: NSLocalizedString("No readings for %@ (%@)", comment: "CGM gap"),
            durationText,
            loopsText
        )
        guard ongoing else { return text }
        return text + ", " + NSLocalizedString("ongoing", comment: "CGM gap is still growing")
    }
}

extension GlucoseGap {
    var loopEvent: LoopEvent {
        LoopEvent(
            id: "gap-\(start.timeIntervalSince1970)",
            timestamp: start,
            type: .missedReadings,
            message: summary
        )
    }
}

extension GlucoseGap {
    enum Config {
        /// A gap is reported when it exceeds the loop interval by this factor.
        /// It has to stay below 2, so that a single missing reading is caught.
        static let tolerance: Double = 1.5
        static let supportedReadingIntervals: [TimeInterval] = [.minutes(1), .minutes(5)]
        static let defaultLoopInterval: TimeInterval = .minutes(5)
        /// How many of the preceding distances define the cadence at a given point.
        /// A change of cadence (a sensor swap) is picked up after half of them.
        static let cadenceWindow = 10
    }

    /// Finds the periods without CGM readings in `glucose`.
    ///
    /// The cadence is a local property, not a property of the whole history: a sensor swap changes it
    /// mid-window (and the readings before the swap outnumber the ones after it for a long time), so each
    /// distance is judged against the readings just before it, not against the window as a whole.
    static func detect(
        in glucose: [BloodGlucose],
        allowOneMinuteLoop: Bool,
        now: Date = Date()
    ) -> [GlucoseGap] {
        let dates = glucose
            .map(\.dateString)
            .sorted()

        guard dates.count >= 2 else { return [] }

        var gaps: [GlucoseGap] = []
        // the distances between the most recent readings, gaps included: the median tolerates the
        // occasional outage, and a permanent change of cadence has to be able to move it
        var recentDeltas: [TimeInterval] = []

        for (previous, next) in zip(dates, dates.dropFirst()) {
            let delta = next.timeIntervalSince(previous)
            guard delta > 0 else { continue } // duplicate timestamps

            let loopInterval = loopInterval(recentDeltas: recentDeltas, allowOneMinuteLoop: allowOneMinuteLoop)
            if delta > loopInterval * Config.tolerance {
                gaps.append(
                    GlucoseGap(start: previous, end: next, loopInterval: loopInterval, ongoing: false)
                )
            }

            recentDeltas.append(delta)
            if recentDeltas.count > Config.cadenceWindow {
                recentDeltas.removeFirst()
            }
        }

        // an ongoing gap: the last reading is older than the threshold
        let loopInterval = loopInterval(recentDeltas: recentDeltas, allowOneMinuteLoop: allowOneMinuteLoop)
        if let last = dates.last, now.timeIntervalSince(last) > loopInterval * Config.tolerance {
            gaps.append(
                GlucoseGap(start: last, end: now, loopInterval: loopInterval, ongoing: true)
            )
        }

        return gaps
    }

    /// Loops run every 5 minutes unless 1-minute loops are enabled *and* the sensor delivers that often.
    /// Without readings to go by (start of the history) the 5 minutes are the conservative answer.
    private static func loopInterval(recentDeltas: [TimeInterval], allowOneMinuteLoop: Bool) -> TimeInterval {
        guard allowOneMinuteLoop, let readingInterval = readingInterval(recentDeltas) else {
            return Config.defaultLoopInterval
        }
        return min(readingInterval, Config.defaultLoopInterval)
    }

    /// The median distance between the recent readings, snapped to a supported sensor interval.
    private static func readingInterval(_ deltas: [TimeInterval]) -> TimeInterval? {
        guard deltas.isNotEmpty else { return nil }

        let sorted = deltas.sorted()
        let median = sorted[sorted.count / 2]

        return Config.supportedReadingIntervals.min { abs($0 - median) < abs($1 - median) }
    }
}
