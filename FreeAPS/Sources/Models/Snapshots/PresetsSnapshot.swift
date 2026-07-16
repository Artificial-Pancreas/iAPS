import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Presets entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct PresetsSnapshot: Sendable {
    let foodID: UUID?
    let dish: String?
    let standardName: String?
    let carbs: Decimal?
    let fat: Decimal?
    let protein: Decimal?
    let fiber: Decimal?
    let sugars: Decimal?
    let glycemicIndex: Decimal?
    let mealUnits: String?
    let per100: Bool
    let portionSize: Decimal?
    let standardServing: String?
    let standardServingSize: Decimal?
    let imageURL: String?
    let tags: String?
//    let micronutrient: Set<PresetMicronutrient>?
}

extension PresetsSnapshot {
    static func create(from record: Presets) -> PresetsSnapshot {
        PresetsSnapshot(
            foodID: record.foodID,
            dish: record.dish,
            standardName: record.standardName,
            carbs: record.carbs?.decimalValue,
            fat: record.fat?.decimalValue,
            protein: record.protein?.decimalValue,
            fiber: record.fiber?.decimalValue,
            sugars: record.sugars?.decimalValue,
            glycemicIndex: record.glycemicIndex?.decimalValue,
            mealUnits: record.mealUnits,
            per100: record.per100,
            portionSize: record.portionSize?.decimalValue,
            standardServing: record.standardServing,
            standardServingSize: record.standardServingSize?.decimalValue,
            imageURL: record.imageURL,
            tags: record.tags,
        )
    }
}
