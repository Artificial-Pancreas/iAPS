import Foundation

extension FoodItemDetailed {
    static func fromPreset(preset: Presets) -> FoodItemDetailed? {
        guard let foodName = preset.dish, !foodName.isEmpty, foodName != "Empty" else {
            return nil
        }
        guard let foodID = preset.foodID else {
            return nil
        }

        let mealUnits = preset.mealUnits.map { MealUnits(rawValue: $0) ?? .grams } ?? .grams
        let nutritionPer100 = preset.per100

        let carbs = (preset.carbs as Decimal?) ?? 0
        let fat = (preset.fat as Decimal?) ?? 0
        let protein = (preset.protein as Decimal?) ?? 0

        let nutritionValues: [NutrientType: Decimal] = [
            .carbs: carbs,
            .fat: fat,
            .fiber: (preset.fiber as Decimal?) ?? 0,
            .protein: protein,
            .sugars: (preset.sugars as Decimal?) ?? 0
        ]

        let micronutrients: [MicronutrientValue] = (preset.micronutrients ?? [])
            .compactMap { entry in
                guard
                    let substanceName = entry.micronutrients.name,
                    let unit = entry.micronutrients.unit,
                    let amount = entry.amount?.decimalValue
                else { return nil }

                guard let micro = MicroNutrient(coreDataName: substanceName) else { return nil }

                let amountPer100: Decimal
                if preset.per100 {
                    amountPer100 = amount
                } else if let portion = preset.portionSize?.decimalValue, portion > 0 {
                    amountPer100 = amount / portion * 100
                } else {
                    amountPer100 = amount
                }

                return MicronutrientValue(
                    substance: micro,
                    amount: amount,
                    amountPer100: amountPer100
                )
            }
            .sorted { $0.name < $1.name }

        return FoodItemDetailed(
            id: foodID,
            name: foodName,
            nutrition: nutritionPer100 ?
                .per100(values: nutritionValues, portionSize: (preset.portionSize as Decimal?) ?? 100) :
                .perServing(values: nutritionValues, servingsMultiplier: 1),
            micronutrients: preset.micronutrientValuesTyped(),
            standardServing: preset.standardServing,
            standardServingSize: preset.standardServingSize as Decimal?,
            units: mealUnits,
            glycemicIndex: preset.glycemicIndex as Decimal?,
            imageURL: preset.imageURL,
            standardName: preset.standardName,
            tags: preset.tags?.lowercased().split(separator: ",", omittingEmptySubsequences: true).map(String.init),
            source: .database
        )
    }

    func updatePreset(preset: Presets) {
        let food = self

        preset.foodID = food.id
        let foodNutrition: NutritionValues
        switch food.nutrition {
        case let .perServing(nutrition, _):
            foodNutrition = nutrition
            preset.per100 = false
            preset.portionSize = nil
        case let .per100(nutrition, portionSize):
            foodNutrition = nutrition
            preset.per100 = true
            preset.portionSize = NSDecimalNumber(decimal: max(portionSize, 0))
        }

        preset.carbs = foodNutrition[.carbs].map { NSDecimalNumber(decimal: max($0, 0)) }
        preset.fat = foodNutrition[.fat].map { NSDecimalNumber(decimal: max($0, 0)) }
        preset.protein = foodNutrition[.protein].map { NSDecimalNumber(decimal: max($0, 0)) }
        preset.fiber = foodNutrition[.fiber].map { NSDecimalNumber(decimal: max($0, 0)) }
        preset.sugars = foodNutrition[.sugars].map { NSDecimalNumber(decimal: max($0, 0)) }

        preset.glycemicIndex = food.glycemicIndex.map { NSDecimalNumber(decimal: $0) }
        preset.standardServing = food.standardServing
        preset.standardServingSize = food.standardServingSize.map { NSDecimalNumber(decimal: $0) }
        preset.imageURL = food.imageURL
        preset.mealUnits = (food.units ?? .grams).rawValue

        preset.standardName = food.standardName
        if let tags = food.tags {
            preset.tags = tags.map { tag in tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: ",")
        } else {
            preset.tags = nil
        }

        preset.dish = food.name
    }
}
