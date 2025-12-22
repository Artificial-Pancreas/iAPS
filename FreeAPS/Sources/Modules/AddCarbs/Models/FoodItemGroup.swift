import Foundation

struct FoodItemGroup: Identifiable, Equatable {
    let id = UUID()
    let foodItemsDetailed: [FoodItemDetailed]
    let briefDescription: String?
    let overallDescription: String?
    let diabetesConsiderations: String?
    let source: FoodItemSource?
    var barcode: String? = nil
    var textQuery: String? = nil

    static func == (lhs: FoodItemGroup, rhs: FoodItemGroup) -> Bool {
        lhs.id == rhs.id
    }

    var totalCalories: Decimal {
        foodItemsDetailed.compactMap(\.caloriesInThisPortion).reduce(0, +)
    }

    var totalCarbs: Decimal {
        foodItemsDetailed.compactMap(\.carbsInThisPortion).reduce(0, +)
    }

    var totalFat: Decimal {
        foodItemsDetailed.compactMap(\.fatInThisPortion).reduce(0, +)
    }

    var totalProtein: Decimal {
        foodItemsDetailed.compactMap(\.proteinInThisPortion).reduce(0, +)
    }
}
