import CoreData
import Foundation

// a snapshot (DTO) of a CoreData TDD entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct TDDSnapshot: Sendable {
    let tdd: Decimal?
    let timestamp: Date?
}

extension TDDSnapshot {
    static func create(from tdd: TDD) -> TDDSnapshot {
        TDDSnapshot(
            tdd: tdd.tdd?.decimalValue,
            timestamp: tdd.timestamp,
        )
    }
}

extension Collection where Element == TDDSnapshot {
    /// One TDD value per 24-hour window, walking newest -> oldest.
    /// Expects the collection ordered newest -> oldest (as `fetchTDD` returns).
    /// Always yields at least one sample (0 when empty) so callers can divide by count.
    func dailyTDDSamples() -> [Decimal] {
        var time = first?.timestamp ?? .distantPast
        var samples: [Decimal] = [first?.tdd ?? 0]
        for event in self {
            if (event.timestamp ?? .distantFuture) <= time.subtractingTimeInterval(.hours(24)) {
                samples.append(event.tdd ?? 0)
                time = event.timestamp ?? .distantPast
            }
        }
        return samples
    }

    /// Time-adjusted average daily TDD over the sampled 24h windows.
    var averageDailyTDD: Decimal {
        let samples = dailyTDDSamples()
        return samples.reduce(0, +) / Decimal(samples.count)
    }
}
