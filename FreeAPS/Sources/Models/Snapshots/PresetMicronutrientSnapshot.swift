import CoreData
import Foundation

// a snapshot (DTO) of a CoreData PresetMicronutrient entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct PresetMicronutrientSnapshot: Sendable, Hashable {
    let id: UUID
    let amount: Decimal?
    let per100: Bool
    let micronutrient: MicronutrientSnapshot
}

extension PresetMicronutrientSnapshot {
    static func create(from record: PresetMicronutrient) -> PresetMicronutrientSnapshot {
        PresetMicronutrientSnapshot(
            id: record.id,
            amount: record.amount?.decimalValue,
            per100: record.per100,
            micronutrient: MicronutrientSnapshot.create(from: record.micronutrient)
        )
    }
}
