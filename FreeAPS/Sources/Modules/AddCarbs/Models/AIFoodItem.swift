import Foundation

struct AIFoodItem: Identifiable {
    let id = UUID()
    let name: String
    let brand: String?
    let calories: Decimal
    let carbs: Decimal
    let protein: Decimal
    let fat: Decimal
    let imageURL: String?
    let source: FoodItemSource?
}
