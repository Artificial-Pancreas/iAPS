import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Micronutrient entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct MicronutrientSnapshot: Sendable, Hashable {
    let id: UUID
    let name: String?
    let type: String
    let amount: Decimal?
    let unit: String?
//    let entries: Set<PresetMicronutrient>
}

extension MicronutrientSnapshot {
    static func create(from record: Micronutrient) -> MicronutrientSnapshot {
        MicronutrientSnapshot(
            id: record.id,
            name: record.name,
            type: record.type,
            amount: record.amount?.decimalValue,
            unit: record.unit,
        )
    }
}
