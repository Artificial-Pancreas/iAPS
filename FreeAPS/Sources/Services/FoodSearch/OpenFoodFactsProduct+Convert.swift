import Foundation

extension OpenFoodFactsProduct {
    static func createFoodItemGroup(
        products: [OpenFoodFactsProduct],
        confidence: ConfidenceLevel?,
        source: FoodItemSource
    ) -> FoodItemGroup {
        let items: [FoodItemDetailed] = products.map { item in
            if let servingQuantity = item.servingQuantity {
                FoodItemDetailed(
                    name: item.productName ?? "Product without name",
                    nutritionPer100: NutritionValues(
                        calories: item.nutriments.calories,
                        carbs: item.nutriments.carbohydrates,
                        fat: item.nutriments.fat,
                        fiber: item.nutriments.fiber,
                        protein: item.nutriments.proteins,
                        sugars: item.nutriments.sugars
                    ),
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
                FoodItemDetailed(
                    name: item.productName ?? "Product without name",
                    nutritionPerServing: NutritionValues(
                        calories: item.nutriments.calories,
                        carbs: item.nutriments.carbohydrates,
                        fat: item.nutriments.fat,
                        fiber: item.nutriments.fiber,
                        protein: item.nutriments.proteins,
                        sugars: item.nutriments.sugars
                    ),
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
