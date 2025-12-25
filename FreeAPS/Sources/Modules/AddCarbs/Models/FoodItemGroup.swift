import Foundation

struct FoodItemGroup: Identifiable, Equatable {
    let id: UUID
    let foodItemsDetailed: [FoodItemDetailed]
    let briefDescription: String?
    let overallDescription: String?
    let diabetesConsiderations: String?
    let source: FoodItemSource
    var barcode: String?
    var textQuery: String?

    init(
        id: UUID? = nil,
        foodItemsDetailed: [FoodItemDetailed],
        briefDescription: String? = nil,
        overallDescription: String? = nil,
        diabetesConsiderations: String? = nil,
        source: FoodItemSource,
        barcode: String? = nil,
        textQuery: String? = nil
    ) {
        self.id = id ?? UUID()
        self.foodItemsDetailed = foodItemsDetailed
        self.briefDescription = briefDescription
        self.overallDescription = overallDescription
        self.diabetesConsiderations = diabetesConsiderations
        self.source = source
        self.barcode = barcode
        self.textQuery = textQuery
    }

    func copyWithItems(_ items: [FoodItemDetailed]) -> Self {
        Self.init(
            id: id,
            foodItemsDetailed: items,
            briefDescription: briefDescription,
            overallDescription: overallDescription,
            diabetesConsiderations: diabetesConsiderations,
            source: source
        )
    }

    func copyWithItemPrepended(_ item: FoodItemDetailed) -> Self {
        guard !foodItemsDetailed.contains(where: { $0.id == item.id }) else {
            return self
        }
        return copyWithItems([item] + foodItemsDetailed)
    }

    static func == (lhs: FoodItemGroup, rhs: FoodItemGroup) -> Bool {
        lhs.id == rhs.id &&
            lhs.foodItemsDetailed == rhs.foodItemsDetailed &&
            lhs.briefDescription == rhs.briefDescription &&
            lhs.overallDescription == rhs.overallDescription &&
            lhs.diabetesConsiderations == rhs.diabetesConsiderations
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
