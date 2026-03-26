import Foundation

extension AIAnalysisResult {
    static func createFoodItemGroup(
        result: AIAnalysisResult,
        source: FoodItemSource
    ) -> FoodItemGroup {
        let items: [FoodItemDetailed] = result.foodItems.map { item in
            let confidence: ConfidenceLevel? = switch item.confidence {
            case .high: .high
            case .medium: .medium
            case .low: .low
            case nil: nil
            }

            var nutritionValues: NutritionValues = [:]
            if let carbs = item.carbsPer100 { nutritionValues[.carbs] = carbs }
            if let fat = item.fatPer100 { nutritionValues[.fat] = fat }
            if let protein = item.proteinPer100 { nutritionValues[.protein] = protein }
            if let fiber = item.fiberPer100 { nutritionValues[.fiber] = fiber }
            if let sugars = item.sugarsPer100 { nutritionValues[.sugars] = sugars }

            return FoodItemDetailed(
                name: item.name,
                nutrition: .per100(values: nutritionValues, portionSize: item.portionEstimateSize ?? 100),
                confidence: confidence,
                brand: item.brand,
                standardServing: item.standardServing,
                standardServingSize: item.standardServingSize,
                units: item.units,
                preparationMethod: item.preparationMethod,
                visualCues: item.visualCues,
                glycemicIndex: item.glycemicIndex,
                assessmentNotes: item.assessmentNotes,
                imageURL: nil,
                standardName: item.standardName,
                source: source
            )
        }

        return FoodItemGroup(
            foodItems: items,
            briefDescription: result.briefDescription,
            overallDescription: result.overallDescription,
            diabetesConsiderations: result.diabetesConsiderations,
            source: source
        )
    }
}
