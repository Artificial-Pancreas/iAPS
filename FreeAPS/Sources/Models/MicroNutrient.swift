import Foundation

enum MicronutrientType: String, CaseIterable, Codable {
    case vitamin
    case mineral
}

enum MicroNutrient: String, CaseIterable, Codable, Identifiable {
    var id: String { rawValue }

    // MARK: - Vitamins

    case vitaminA
    case vitaminB1
    case vitaminB2
    case vitaminB3
    case vitaminB5
    case vitaminB6
    case vitaminB7
    case vitaminB9
    case vitaminB12
    case vitaminC
    case vitaminD
    case vitaminE
    case vitaminK

    // MARK: - Minerals

    case calcium
    case iron
    case magnesium
    case potassium
    case sodium
    case zinc
    case phosphorus
    case copper
    case manganese
    case selenium
    case iodine
    case salt
}

extension MicroNutrient {
    var displayName: String {
        switch self {
        case .vitaminA: return "Vitamin A"
        case .vitaminB1: return "Vitamin B1 (Thiamine)"
        case .vitaminB2: return "Vitamin B2 (Riboflavin)"
        case .vitaminB3: return "Vitamin B3 (Niacin)"
        case .vitaminB5: return "Vitamin B5 (Pantothenic Acid)"
        case .vitaminB6: return "Vitamin B6"
        case .vitaminB7: return "Vitamin B7 (Biotin)"
        case .vitaminB9: return "Vitamin B9 (Folate)"
        case .vitaminB12: return "Vitamin B12"
        case .vitaminC: return "Vitamin C"
        case .vitaminD: return "Vitamin D"
        case .vitaminE: return "Vitamin E"
        case .vitaminK: return "Vitamin K"

        case .calcium: return "Calcium"
        case .iron: return "Iron"
        case .magnesium: return "Magnesium"
        case .potassium: return "Potassium"
        case .sodium: return "Sodium"
        case .zinc: return "Zinc"
        case .phosphorus: return "Phosphorus"
        case .copper: return "Copper"
        case .manganese: return "Manganese"
        case .selenium: return "Selenium"
        case .iodine: return "Iodine"
        case .salt: return "Salt"
        }
    }

    var codingKey: String {
        switch self {
        case .vitaminA: return "vitamin_a_per_100"
        case .vitaminB1: return "vitamin_b1_per_100"
        case .vitaminB2: return "vitamin_b2_per_100"
        case .vitaminB3: return "vitamin_b3_per_100"
        case .vitaminB5: return "vitamin_b5_per_100"
        case .vitaminB6: return "vitamin_b6_per_100"
        case .vitaminB7: return "vitamin_b7_per_100"
        case .vitaminB9: return "vitamin_b9_per_100"
        case .vitaminB12: return "vitamin_b12_per_100"
        case .vitaminC: return "vitamin_c_per_100"
        case .vitaminD: return "vitamin_d_per_100"
        case .vitaminE: return "vitamin_e_per_100"
        case .vitaminK: return "vitamin_k_per_100"

        case .calcium: return "calcium_per_100"
        case .iron: return "iron_per_100"
        case .magnesium: return "magnesium_per_100"
        case .potassium: return "potassium_per_100"
        case .sodium: return "sodium_per_100"
        case .zinc: return "zinc_per_100"
        case .phosphorus: return "phosphorus_per_100"
        case .copper: return "copper_per_100"
        case .manganese: return "manganese_per_100"
        case .selenium: return "selenium_per_100"
        case .iodine: return "iodine_per_100"
        case .salt: return "salt_per_100"
        }
    }

    var unit: String {
        switch self {
        case .iodine,
             .selenium,
             .vitaminA,
             .vitaminB12,
             .vitaminD,
             .vitaminK:
            return "µg"
        case .salt,
             .sodium:
            return "g"
        default:
            return "mg"
        }
    }

    var type: MicronutrientType {
        switch self {
        case .vitaminA,
             .vitaminB1,
             .vitaminB2,
             .vitaminB3,
             .vitaminB5,
             .vitaminB6,
             .vitaminB7,
             .vitaminB9,
             .vitaminB12,
             .vitaminC,
             .vitaminD,
             .vitaminE,
             .vitaminK:
            return .vitamin

        default:
            return .mineral
        }
    }

    var apiKey: String {
        switch self {
        case .vitaminA: return "vitamin_a"
        case .vitaminB1: return "thiamin"
        case .vitaminB2: return "riboflavin"
        case .vitaminB3: return "niacin"
        case .vitaminB5: return "pantothenic_acid"
        case .vitaminB6: return "vitamin_b6"
        case .vitaminB7: return "biotin"
        case .vitaminB9: return "folate"
        case .vitaminB12: return "vitamin_b12"
        case .vitaminC: return "vitamin_c"
        case .vitaminD: return "vitamin_d"
        case .vitaminE: return "vitamin_e"
        case .vitaminK: return "vitamin_k"

        case .calcium: return "calcium"
        case .iron: return "iron"
        case .magnesium: return "magnesium"
        case .potassium: return "potassium"
        case .sodium: return "sodium"
        case .zinc: return "zinc"
        case .phosphorus: return "phosphorus"
        case .copper: return "copper"
        case .manganese: return "manganese"
        case .selenium: return "selenium"
        case .iodine: return "iodine"
        case .salt: return "salt"
        }
    }

    init?(apiKey: String) {
        self = MicroNutrient.allCases.first {
            $0.apiKey == apiKey
        } ?? .vitaminC
    }

    var coreDataName: String {
        displayName
    }

    var coreDataType: String {
        switch self {
        case .vitaminA,
             .vitaminB1,
             .vitaminB2,
             .vitaminB3,
             .vitaminB5,
             .vitaminB6,
             .vitaminB7,
             .vitaminB9,
             .vitaminB12,
             .vitaminC,
             .vitaminD,
             .vitaminE,
             .vitaminK:
            return "vitamin"
        default:
            return "mineral"
        }
    }

    var dimension: Dimension {
        switch unit {
        case "g":
            return UnitMass.grams
        case "mg":
            return UnitMass.milligrams
        case "ug",
             "µg":
            return UnitMass.micrograms
        case "ml":
            return UnitVolume.milliliters
        default:
            return UnitMass.grams
        }
    }

    init?(coreDataName: String) {
        let normalized = coreDataName
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let match = MicroNutrient.allCases.first(where: {
            $0.displayName.lowercased() == normalized
        }) else {
            return nil
        }

        self = match
    }
}
