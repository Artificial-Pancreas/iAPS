import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Meals entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct MealsSnapshot: Sendable {
    let id: String?
    let date: Date?
    let createdAt: Date?
    let actualDate: Date?
    let enteredBy: String?
    let carbs: Decimal?
    let fat: Decimal?
    let protein: Decimal?
    let fiber: Decimal?
    let note: String?
    let fpuID: String?
    let savedToFile: Bool
    let micronutrient: [MicronutrientSnapshot]
}

extension MealsSnapshot {
    static func create(from meal: Meals) -> MealsSnapshot {
        MealsSnapshot(
            id: meal.id,
            date: meal.date,
            createdAt: meal.createdAt,
            actualDate: meal.actualDate,
            enteredBy: meal.enteredBy,
            carbs: meal.carbs?.decimalValue,
            fat: meal.fat?.decimalValue,
            protein: meal.protein?.decimalValue,
            fiber: meal.fiber?.decimalValue,
            note: meal.note,
            fpuID: meal.fpuID,
            savedToFile: meal.savedToFile,
            micronutrient: (meal.micronutrient as? Set<Micronutrient>)?.map { MicronutrientSnapshot.create(from: $0) } ?? []
        )
    }
}

extension MealsSnapshot {
    var micronutrientTotals: [MicroNutrient: Decimal] {
        let micronutrients = micronutrient

        return Dictionary(
            uniqueKeysWithValues: micronutrients.compactMap { item -> (MicroNutrient, Decimal)? in
                guard let nutrient = MicroNutrient(rawValue: item.type), let amount = item.amount else {
                    return nil
                }

                return (
                    nutrient,
                    amount as Decimal
                )
            }
        )
    }

    var micronutrientValues: [MicronutrientValue] {
        let items = micronutrient

        return items.compactMap { item -> MicronutrientValue? in
            guard let substance = MicroNutrient(rawValue: item.type), let amount = item.amount else {
                return nil
            }

            return MicronutrientValue(
                substance: substance,
                amount: amount,
                amountPer100: 0
            )
        }
        .sorted { $0.name < $1.name }
    }
}
