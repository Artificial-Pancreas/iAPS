import CoreData
import Foundation

// a snapshot (DTO) of a CoreData LoopStatRecord entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct LoopStatRecordSnapshot: Sendable {
    let start: Date?
    let end: Date?
    let duration: Double
    let interval: Double
    let loopStatus: String?
    let error: String?
}

extension LoopStatRecordSnapshot {
    static func create(from record: LoopStatRecord) -> LoopStatRecordSnapshot {
        LoopStatRecordSnapshot(
            start: record.start,
            end: record.end,
            duration: record.duration,
            interval: record.interval,
            loopStatus: record.loopStatus,
            error: record.error,
        )
    }
}
