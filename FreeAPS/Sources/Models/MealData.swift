import Foundation

struct MealData: Codable {
    var id = UUID()

    var carbs: Decimal = 0
    var fat: Decimal = 0
    var protein: Decimal = 0
    var fiber: Decimal = 0
    var kcal: Decimal = 0
    var servings: Int = 0

    var micronutrients: [MicroNutrient: Decimal] = [:]

    var intervalDays: Double?

    var isAveraged: Bool {
        guard let intervalDays else { return false }
        return intervalDays > 1
    }

    func averaged(_ value: Decimal) -> Decimal {
        guard let intervalDays, intervalDays > 1 else {
            return value
        }

        return value / Decimal(intervalDays)
    }

    func averaged(_ value: Int) -> Decimal {
        averaged(Decimal(value))
    }

    var additionalNutrients: Int {
        let micros = micronutrients.count
        let fat = self.fat > 0 ? 1 : 0
        let protein = self.protein > 0 ? 1 : 0

        return micros + fat + protein
    }
}
