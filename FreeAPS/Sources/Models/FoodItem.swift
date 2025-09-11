import Foundation

struct FoodItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let carbs: Decimal
    let fat: Decimal
    let protein: Decimal
    let source: String

    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension FoodItem {
    func toAIFoodItem() -> AIFoodItem {
        AIFoodItem(
            name: name,
            brand: source,
            calories: Double(truncating: carbs as NSNumber) * 4 + Double(truncating: protein as NSNumber) * 4 +
                Double(truncating: fat as NSNumber) * 9,
            carbs: Double(truncating: carbs as NSNumber),
            protein: Double(truncating: protein as NSNumber),
            fat: Double(truncating: fat as NSNumber)
        )
    }
}

extension AIFoodItem {
    func toCarbsEntry(servingSize: Double = 100.0) -> CarbsEntry {
        // Berechne die Nährwerte basierend auf der Portionsgröße
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
