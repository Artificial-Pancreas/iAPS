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

    // MARK: Vitamins

    case vitaminA_RAE = 320
    case vitaminA_IU = 318
    case vitaminC = 401
    case vitaminD = 328
    case vitaminE = 323
    case vitaminK = 430

    case thiamin = 404 // B1
    case riboflavin = 405 // B2
    case niacin = 406 // B3
    case pantothenicAcid = 410 // B5
    case vitaminB6 = 415
    case folateTotal = 417 // B9
    case vitaminB12 = 418

    // MARK: Minerals

    case calcium = 301
    case iron = 303
    case magnesium = 304
    case phosphorus = 305
    case potassium = 306
    case sodium = 307
    case zinc = 309
    case copper = 312
    case manganese = 315
    case selenium = 317
    case salt = 2047

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

        case .folateTotal,
             .niacin,
             .pantothenicAcid,
             .riboflavin,
             .thiamin,
             .vitaminA_IU,
             .vitaminA_RAE,
             .vitaminB6,
             .vitaminB12,
             .vitaminC,
             .vitaminD,
             .vitaminE,
             .vitaminK:
            return .vitamin

        case .calcium,
             .copper,
             .iron,
             .magnesium,
             .manganese,
             .phosphorus,
             .potassium,
             .salt,
             .selenium,
             .sodium,
             .zinc:
            return .mineral
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
        default:
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
        case vitamin
        case mineral
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

extension USDANutrientCode {
    var microNutrient: MicroNutrient? {
        switch self {
        // Vitamins
        case .vitaminA_IU,
             .vitaminA_RAE: return .vitaminA
        case .vitaminC: return .vitaminC
        case .vitaminD: return .vitaminD
        case .vitaminE: return .vitaminE
        case .vitaminK: return .vitaminK
        case .thiamin: return .vitaminB1
        case .riboflavin: return .vitaminB2
        case .niacin: return .vitaminB3
        case .pantothenicAcid: return .vitaminB5
        case .vitaminB6: return .vitaminB6
        case .folateTotal: return .vitaminB9
        case .vitaminB12: return .vitaminB12

        // Minerals
        case .calcium: return .calcium
        case .iron: return .iron
        case .magnesium: return .magnesium
        case .phosphorus: return .phosphorus
        case .potassium: return .potassium
        case .sodium: return .sodium
        case .zinc: return .zinc
        case .copper: return .copper
        case .manganese: return .manganese
        case .selenium: return .selenium
        case .salt: return .salt

        default:
            return nil
        }
    }
}

extension USDAFoodNutrient {
    func normalizedValue(for micro: MicroNutrient) -> Decimal? {
        guard let value = value else { return nil }

        let decimal = Decimal(value)

        switch unitName?.lowercased() {
        case "ug",
             "µg":
            return decimal / 1000 // → mg
        case "mg":
            return decimal
        case "g":
            return decimal * 1000
        case "iu":
            // Example: Vitamin A IU → µg conversion (rough)
            if micro == .vitaminA {
                return decimal * 0.3 / 1000 // IU → µg → mg
            }
            return decimal
        default:
            return decimal
        }
    }
}
