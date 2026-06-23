import CoreData
import Foundation

// a snapshot (DTO) of a CoreData OverrideHistory entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct OverrideHistorySnapshot: Sendable, Equatable {
    let date: Date?
    let duration: Double
    let target: Double
}

extension OverrideHistorySnapshot {
    static func create(from record: OverrideHistory) -> OverrideHistorySnapshot {
        OverrideHistorySnapshot(
            date: record.date,
            duration: record.duration,
            target: record.target
        )
    }
}
