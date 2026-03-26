import Foundation

/// USDA Nutrient identification codes
/// Based on USDA FoodData Central nutrient database
enum USDANutrientCode: Int {
    // MARK: Carbohydrates

    /// Carbohydrate, by difference (most common)
    case carbohydrateByDifference = 205
    /// Carbohydrate, by summation
    case carbohydrateBySummation = 1005
    /// Carbohydrate, other
    case carbohydrateOther = 1050

    // MARK: Protein

    /// Protein (most common)
    case protein = 203
    /// Protein, crude
    case proteinCrude = 1003

    // MARK: Fat

    /// Total lipid (fat) (most common)
    case totalLipidFat = 204
    /// Total lipid, crude
    case totalLipidCrude = 1004

    // MARK: Fiber

    /// Fiber, total dietary (most common)
    case fiberTotalDietary = 291
    /// Fiber, crude
    case fiberCrude = 1079

    // MARK: Sugars

    /// Sugars, total including NLEA (most common)
    case sugarsTotalIncludingNLEA = 269
    /// Sugars, total
    case sugarsTotal = 1010
    /// Sugars, added
    case sugarsAdded = 1063

    // MARK: Energy/Calories

    /// Energy (kcal) (most common)
    case energyKcal = 208
    /// Energy, gross
    case energyGross = 1008
    /// Energy, metabolizable
    case energyMetabolizable = 1062

    /// Category of the nutrient for easier grouping
    var category: NutrientCategory {
        switch self {
        case .carbohydrateByDifference,
             .carbohydrateBySummation,
             .carbohydrateOther:
            return .carbohydrate
        case .protein,
             .proteinCrude:
            return .protein
        case .totalLipidCrude,
             .totalLipidFat:
            return .fat
        case .fiberCrude,
             .fiberTotalDietary:
            return .fiber
        case .sugarsAdded,
             .sugarsTotal,
             .sugarsTotalIncludingNLEA:
            return .sugar
        case .energyGross,
             .energyKcal,
             .energyMetabolizable:
            return .energy
        }
    }

    /// Priority within its category (lower is higher priority)
    var priority: Int {
        switch self {
        // Primary values (most common/preferred)
        case .carbohydrateByDifference,
             .energyKcal,
             .fiberTotalDietary,
             .protein,
             .sugarsTotalIncludingNLEA,
             .totalLipidFat:
            return 1
        // Secondary values (summation/alternative)
        case .carbohydrateBySummation,
             .energyGross,
             .fiberCrude,
             .proteinCrude,
             .sugarsTotal,
             .totalLipidCrude:
            return 2
        // Tertiary values (other/less common)
        case .carbohydrateOther,
             .energyMetabolizable,
             .sugarsAdded:
            return 3
        }
    }

    enum NutrientCategory {
        case carbohydrate
        case protein
        case fat
        case fiber
        case sugar
        case energy
    }
}

/// Root response from USDA FoodData Central search API
struct USDASearchResponse: Codable {
    let foods: [USDAFood]
    let totalHits: Int?
    let currentPage: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case foods
        case totalHits
        case currentPage
        case totalPages
    }
}

/// USDA Food item from search results
struct USDAFood: Codable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let brandName: String?
    let ingredients: String?
    let foodNutrients: [USDAFoodNutrient]?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?

    enum CodingKeys: String, CodingKey {
        case fdcId
        case description
        case dataType
        case brandOwner
        case brandName
        case ingredients
        case foodNutrients
        case servingSize
        case servingSizeUnit
        case householdServingFullText
    }
}

/// Nutrient information from USDA food item
struct USDAFoodNutrient: Codable {
    let nutrientId: Int?
    let nutrientNumber: String?
    let nutrientName: String?
    let value: Double?
    let unitName: String?

    enum CodingKeys: String, CodingKey {
        case nutrientId
        case nutrientNumber
        case nutrientName
        case value
        case unitName
    }

    /// Get the nutrient number as an integer, handling both String and Int formats
    var nutrientNumberAsInt: Int? {
        if let nutrientId = nutrientId {
            return nutrientId
        }
        if let nutrientNumber = nutrientNumber, let intValue = Int(nutrientNumber) {
            return intValue
        }
        return nil
    }

    /// Get the nutrient as a typed enum value
    var nutrientCode: USDANutrientCode? {
        guard let number = nutrientNumberAsInt else { return nil }
        return USDANutrientCode(rawValue: number)
    }
}
