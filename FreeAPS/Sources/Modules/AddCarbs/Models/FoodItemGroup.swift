import Foundation

struct FoodItemGroup: Identifiable, Equatable {
    let id: UUID
    let foodItems: [FoodItemDetailed]
    let briefDescription: String?
    let overallDescription: String?
    let diabetesConsiderations: String?
    let source: FoodItemSource
    var barcode: String?
    var textQuery: String?

    init(
        id: UUID? = nil,
        foodItems: [FoodItemDetailed],
        briefDescription: String? = nil,
        overallDescription: String? = nil,
        diabetesConsiderations: String? = nil,
        source: FoodItemSource,
        barcode: String? = nil,
        textQuery: String? = nil
    ) {
        self.id = id ?? UUID()
        self.foodItems = foodItems
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
            foodItems: items,
            briefDescription: briefDescription,
            overallDescription: overallDescription,
            diabetesConsiderations: diabetesConsiderations,
            source: source,
            barcode: barcode,
            textQuery: textQuery
        )
    }

    func copyWithItemPrepended(_ item: FoodItemDetailed) -> Self {
        guard !foodItems.contains(where: { $0.id == item.id }) else {
            return self
        }
        return copyWithItems([item] + foodItems)
    }

    static func == (lhs: FoodItemGroup, rhs: FoodItemGroup) -> Bool {
        lhs.id == rhs.id &&
            lhs.foodItems == rhs.foodItems &&
            lhs.briefDescription == rhs.briefDescription &&
            lhs.overallDescription == rhs.overallDescription &&
            lhs.diabetesConsiderations == rhs.diabetesConsiderations &&
            lhs.source == rhs.source &&
            lhs.barcode == rhs.barcode &&
            lhs.textQuery == rhs.textQuery
    }
}

extension FoodItemGroup {
    var title: String {
        switch source {
        case .manual: NSLocalizedString("Manual entry", comment: "Section with manualy entered foods")
        case .database: NSLocalizedString("Saved Foods", comment: "Section with saved foods")
        case .barcode: NSLocalizedString("Barcode scan", comment: "Section with bar code scan results")
        case .search: NSLocalizedString("Online database search", comment: "Section with online database search results")
        case .aiMenu,
             .aiPhoto,
             .aiRecipe,
             .aiText:
            briefDescription ?? textQuery ?? NSLocalizedString(
                "AI Results",
                comment: "Section with AI food analysis results, when details are unavailable"
            )
        }
    }
}
