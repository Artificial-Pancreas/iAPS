import Foundation

func isAIAnalysisProduct(_ foodItem: AIFoodItem) -> Bool {
    if let brand = foodItem.brand, brand.contains("AI") || brand.contains("Analysis") {
        return true
    }
    return foodItem.brand == nil || foodItem.brand == "AI Analysis"
}

extension AIFoodItem {
    func toCarbsEntry(servingSize: Double = 100.0) -> CarbsEntry {
        let scalingFactor = servingSize / 100.0

        return CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            actualDate: Date(),
            carbs: Decimal(carbs * scalingFactor),
            fat: Decimal(fat * scalingFactor),
            protein: Decimal(protein * scalingFactor),
            note: "\(name)\(brand != nil ? " (\(brand!))" : "") - AI detected",
            enteredBy: CarbsEntry.manual,
            isFPU: false
        )
    }
}
