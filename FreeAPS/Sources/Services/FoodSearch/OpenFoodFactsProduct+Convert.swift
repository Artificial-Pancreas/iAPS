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

            let nutrition: FoodNutrition
            if let servingQuantity = item.servingQuantity {
                nutrition = .per100(values: nutritionValues, portionSize: servingQuantity)
            } else {
                nutrition = .perServing(values: nutritionValues, servingsMultiplier: 1)
            }

            return FoodItemDetailed(
                name: item.productName ?? "Product without name",
                nutrition: nutrition,
                confidence: confidence,
                brand: item.brands,
                standardServing: item.servingSize,
                standardServingSize: item.servingQuantity,
                units: MealUnits.grams,
                imageURL: item.imageURL,
                source: source
            )
        }

        return FoodItemGroup(
            foodItems: items,
            briefDescription: nil,
            overallDescription: nil,
            diabetesConsiderations: nil,
            source: source
        )
    }
}
