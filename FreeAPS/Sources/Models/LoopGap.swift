import Foundation

/// A period during which the loop didn't run.
struct LoopGap: Identifiable, Equatable, Hashable, Sendable {
    /// the start of the last loop cycle before the gap
    let start: Date
    /// the start of the first loop cycle after the gap (or "now" for an ongoing gap)
    let end: Date
    /// the cadence the loop was expected to run at
    let loopInterval: TimeInterval
    /// the gap is still growing
    let ongoing: Bool

    var id: Date { start }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var skippedLoops: Int {
        max(1, Int((duration / loopInterval).rounded()) - 1)
    }

    var summary: String {
        let loopsText = skippedLoops == 1 ?
            NSLocalizedString("1 skipped loop", comment: "Skipped loop cycles") :
            String(format: NSLocalizedString("%d skipped loops", comment: "Skipped loop cycles"), skippedLoops)

        let text = String(
            format: NSLocalizedString("%@, no loop for %@", comment: "Loop gap"),
            loopsText,
            duration.minutesText
        )
        guard ongoing else { return text }
        return text + ", " + NSLocalizedString("ongoing", comment: "CGM gap is still growing")
    }
}

extension LoopGap {
    var loopEvent: LoopEvent {
        LoopEvent(
            id: "gap-\(start.timeIntervalSince1970)",
            timestamp: end,
            type: .skippedLoops,
            message: summary
        )
    }
}

extension LoopGap {
    static func detect(
        in loopStarts: [Date],
        allowOneMinuteLoop: Bool,
        now: Date = Date()
    ) -> [LoopGap] {
        GapDetection
            .detect(in: loopStarts, allowOneMinuteLoop: allowOneMinuteLoop, now: now)
            .map { LoopGap(start: $0.start, end: $0.end, loopInterval: $0.interval, ongoing: $0.ongoing) }
    }
}
