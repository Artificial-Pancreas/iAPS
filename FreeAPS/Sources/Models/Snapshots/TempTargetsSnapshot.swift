import CoreData
import Foundation

// a snapshot (DTO) of a CoreData TempTargets entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct TempTargetsSnapshot: Sendable {
    let id: String?
    let date: Date?
    let startDate: Date?
    let active: Bool
    let duration: Decimal?
    let hbt: Double
}

extension TempTargetsSnapshot {
    static func create(from tt: TempTargets) -> TempTargetsSnapshot {
        TempTargetsSnapshot(
            id: tt.id,
            date: tt.date,
            startDate: tt.startDate,
            active: tt.active,
            duration: tt.duration?.decimalValue,
            hbt: tt.hbt,
        )
    }
}
