import Foundation

extension AIAnalysisResult {
    static func createFoodItemGroup(
        result: AIAnalysisResult,
        source: FoodItemSource
    ) -> FoodItemGroup {
        let items: [FoodItemDetailed] = result.foodItemsDetailed.map { item in
            let confidence: ConfidenceLevel? = switch item.confidence {
            case .high: .high
            case .medium: .medium
            case .low: .low
            case nil: nil
            }
            return FoodItemDetailed(
                name: item.name,
                nutritionPer100: NutritionValues(
                    calories: item.caloriesPer100,
                    carbs: item.carbsPer100,
                    fat: item.fatPer100,
                    fiber: item.fiberPer100,
                    protein: item.proteinPer100,
                    sugars: item.sugarsPer100,
                ),
                portionSize: item.portionEstimateSize ?? 100,
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
            foodItemsDetailed: items,
            briefDescription: result.briefDescription,
            overallDescription: result.overallDescription,
            diabetesConsiderations: result.diabetesConsiderations,
            source: source
        )
    }
}
