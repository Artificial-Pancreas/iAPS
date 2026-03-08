import Foundation

extension OpenFoodFactsProduct {
    static func createFoodItemGroup(
        products: [OpenFoodFactsProduct],
        confidence: ConfidenceLevel?,
        source: FoodItemSource
    ) -> FoodItemGroup {
        let items: [FoodItemDetailed] = products.map { item in
            var nutritionValues: NutritionValues = [:]
            if let carbs = item.nutriments.carbohydrates { nutritionValues[.carbs] = carbs }
            if let fat = item.nutriments.fat { nutritionValues[.fat] = fat }
            if let protein = item.nutriments.proteins { nutritionValues[.protein] = protein }
            if let fiber = item.nutriments.fiber { nutritionValues[.fiber] = fiber }
            if let sugars = item.nutriments.sugars { nutritionValues[.sugars] = sugars }

            if let servingQuantity = item.servingQuantity {
                return FoodItemDetailed(
                    name: item.productName ?? "Product without name",
                    nutritionPer100: nutritionValues,
                    portionSize: servingQuantity,
                    confidence: confidence,
                    brand: item.brands,
                    standardServing: item.servingSize,
                    standardServingSize: item.servingQuantity,
                    units: MealUnits.grams,
                    imageURL: item.imageURL,
                    source: source
                )
            } else {
                return FoodItemDetailed(
                    name: item.productName ?? "Product without name",
                    nutritionPerServing: nutritionValues,
                    servingsMultiplier: 1,
                    confidence: confidence,
                    brand: item.brands,
                    standardServing: item.servingSize,
                    standardServingSize: item.servingQuantity,
                    units: MealUnits.grams,
                    imageURL: item.imageURL,
                    source: source
                )
            }
        }

        return FoodItemGroup(
            foodItemsDetailed: items,
            briefDescription: nil,
            overallDescription: nil,
            diabetesConsiderations: nil,
            source: source
        )
    }
}
