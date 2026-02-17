import Foundation

struct MealDaySummary: Identifiable {
    let id = UUID()
    let date: Date
    let kcal: Double
    let carbs: Double
    let fat: Double
    let protein: Double
    let servings: Int
}
