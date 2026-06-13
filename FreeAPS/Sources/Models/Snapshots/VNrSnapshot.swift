import CoreData
import Foundation

// a snapshot (DTO) of a CoreData VNr entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct VNrSnapshot: Sendable {
    let date: Date?
    let dev: String?
    let nr: String?
}

extension VNrSnapshot {
    static func create(from record: VNr) -> VNrSnapshot {
        VNrSnapshot(
            date: record.date,
            dev: record.dev,
            nr: record.nr
        )
    }
}
