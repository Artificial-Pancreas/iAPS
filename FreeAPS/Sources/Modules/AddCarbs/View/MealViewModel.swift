import Foundation
import SwiftUI

final class MealViewModel: ObservableObject {
    @Published var items: [FoodItemDetailed] = []

    var mealNutritionValues: NutritionValues {
        nutritionValues(for: items)
    }

    var mealMicronutrientValues: [MicroNutrient: Decimal] {
        micronutrientValues(for: items)
    }

    var aggregatedNutrition: AggregatedNutrition {
        AggregatedNutrition(
            macros: mealNutritionValues,
            micros: mealMicronutrientValues
        )
    }

    // MARK: - Public Mutations

    func addItem(_ item: FoodItemDetailed) {
        items.append(item)
    }

    func removeItem(_ item: FoodItemDetailed) {
        items.removeAll { $0.id == item.id }
    }

    func updateItem(_ item: FoodItemDetailed) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func clear() {
        items.removeAll()
    }

    // MARK: - Macro Aggregation

    func nutritionValues(for items: [FoodItemDetailed]) -> NutritionValues {
        var values: NutritionValues = [:]

        for nutrient in NutrientType.allCases {
            let sum = items.reduce(Decimal(0)) {
                $0 + ($1.nutrientInThisPortion(nutrient) ?? 0)
            }

            if sum > 0 || nutrient.isPrimary {
                values[nutrient] = sum
            }
        }

        return values
    }

    // MARK: - Micro Aggregation

    func micronutrientValues(for items: [FoodItemDetailed]) -> [MicroNutrient: Decimal] {
        var result: [MicroNutrient: Decimal] = [:]

        for item in items {
            for micro in item.micronutrients {
                let value: Decimal

                switch item.nutrition {
                case let .per100(_, portion):
                    value = micro.amountPer100 / 100 * portion

                case let .perServing(_, multiplier):
                    value = micro.amount * multiplier
                }

                result[micro.substance, default: 0] += value
            }
        }

        return result
    }

    var totalCalories: Decimal {
        mealNutritionValues.calories
    }

    var hasData: Bool {
        !items.isEmpty
    }

    func total(of nutrient: NutrientType) -> Decimal {
        mealNutritionValues[nutrient] ?? 0
    }

    func total(of micronutrient: MicroNutrient) -> Decimal {
        mealMicronutrientValues[micronutrient] ?? 0
    }
}
