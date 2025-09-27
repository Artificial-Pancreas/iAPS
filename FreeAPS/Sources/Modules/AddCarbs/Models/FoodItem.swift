import Foundation

struct FoodItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let carbs: Decimal
    let fat: Decimal
    let protein: Decimal
    let source: String
    let imageURL: String?
}

extension FoodItem {
    func toAIFoodItem() -> AIFoodItem {
        AIFoodItem(
            name: name,
            brand: source,
            calories: Double(truncating: carbs as NSNumber) * 4 +
                Double(truncating: protein as NSNumber) * 4 +
                Double(truncating: fat as NSNumber) * 9,
            carbs: Double(truncating: carbs as NSNumber),
            protein: Double(truncating: protein as NSNumber),
            fat: Double(truncating: fat as NSNumber),
            imageURL: imageURL
        )
    }
}
