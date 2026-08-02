import Foundation

/// A period without CGM readings.
struct GlucoseGap: Identifiable, Equatable, Hashable, Sendable {
    /// last reading before the gap
    let start: Date
    /// first reading after the gap (or "now" for an ongoing gap)
    let end: Date
    /// the gap is still growing
    let ongoing: Bool

    var id: Date { start }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var summary: String {
        let text = String(
            format: NSLocalizedString("No readings for %@", comment: "CGM gap"),
            duration.minutesText
        )
        guard ongoing else { return text }
        return text + ", " + NSLocalizedString("ongoing", comment: "CGM gap is still growing")
    }
}

extension GlucoseGap {
    static func detect(
        in glucose: [BloodGlucose],
        allowOneMinuteLoop: Bool,
        now: Date = Date()
    ) -> [GlucoseGap] {
        GapDetection
            .detect(in: glucose.map(\.dateString), allowOneMinuteLoop: allowOneMinuteLoop, now: now)
            .map { GlucoseGap(start: $0.start, end: $0.end, ongoing: $0.ongoing) }
    }
}
