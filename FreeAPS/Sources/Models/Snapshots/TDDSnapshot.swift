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
