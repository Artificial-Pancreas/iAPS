
import Foundation
import SwiftData

@Model final class MealDaySummary {
    @Attribute(.unique) var date: Date
    var kcal: Double
    var carbs: Double
    var fat: Double
    var protein: Double
    var servings: Int

    init(
        date: Date,
        kcal: Double,
        carbs: Double,
        fat: Double,
        protein: Double,
        servings: Int
    ) {
        self.date = date
        self.kcal = kcal
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.servings = servings
    }
}
