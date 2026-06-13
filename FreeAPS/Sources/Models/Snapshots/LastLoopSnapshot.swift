import CoreData
import Foundation

// a snapshot (DTO) of a CoreData LastLoop entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct LastLoopSnapshot: Sendable {
    let timestamp: Date?
    let cob: Decimal?
    let iob: Decimal?
}

extension LastLoopSnapshot {
    static func create(from record: LastLoop) -> LastLoopSnapshot {
        LastLoopSnapshot(
            timestamp: record.timestamp,
            cob: record.cob?.decimalValue,
            iob: record.iob?.decimalValue
        )
    }
}
