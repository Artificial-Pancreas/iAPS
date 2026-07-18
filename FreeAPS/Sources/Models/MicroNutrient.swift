import Foundation
import SwiftUI

protocol RDITrackable {
    var shouldLimitExcess: Bool { get }
}

enum MicronutrientType: String, CaseIterable, Codable {
    case vitamin
    case mineral
}

/// Only needed for EFSA RDI values
enum MacroNutrient {
    case protein
    case fiber

    var shouldLimitExcess: Bool {
        false
    }
}

extension MacroNutrient: RDITrackable {}

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
    case zinc
    case phosphorus
    case copper
    case manganese
    case selenium
    case iodine
    case salt
}

extension MicroNutrient: RDITrackable {}

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
        case .salt:
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
        guard let match = MicroNutrient.allCases.first(where: { $0.apiKey == apiKey }) else {
            return nil
        }
        self = match
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

    enum SourceUnit: String {
        case g
        case mg
        case ug
        case mcg
        case iu
        case unknown
    }

    /// Converts external nutrition values into the app's canonical unit
    /// defined by `MicroNutrient.unit`.
    ///
    /// Canonical units:
    /// - mg for most nutrients
    /// - µg for selenium, iodine, A, B12, D, K
    /// - g for salt
    func normalized(
        value: Decimal,
        from sourceUnit: SourceUnit
    ) -> Decimal {
        switch sourceUnit {
        case .g:
            switch unit {
            case "mg":
                return value * 1000

            case "ug",
                 "µg":
                return value * 1_000_000

            default:
                return value
            }

        case .mg:
            switch unit {
            case "ug",
                 "µg":
                return value * 1000

            case "g":
                return value / 1000

            default:
                return value
            }

        case .mcg,
             .ug:
            switch unit {
            case "mg":
                return value / 1000

            case "g":
                return value / 1_000_000

            default:
                return value
            }

        case .iu:
            switch self {
            case .vitaminA:
                return (value * 0.3)

            case .vitaminD:
                return (value * 0.025)

            default:
                return value
            }

        case .unknown:
            return value
        }
    }

    var isVitamin: Bool {
        coreDataType == "vitamin"
    }

    var shouldLimitExcess: Bool {
        switch self {
        case .iodine,
             .iron,
             .phosphorus,
             .salt,
             .selenium,
             .vitaminA,
             .vitaminD:
            return true

        default:
            return false
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

enum BiologicalSex: String, Codable, CaseIterable {
    case male
    case female
}

enum AgeGroup: String, Codable, CaseIterable {
    case infant7to11Months
    case child1to3
    case child4to6
    case child7to10
    case child11to14
    case child15to17
    case adult
}

extension AgeGroup {
    static func from(age: Int) -> AgeGroup {
        switch age {
        case 0 ..< 1:
            return .infant7to11Months
        case 1 ... 3:
            return .child1to3
        case 4 ... 6:
            return .child4to6
        case 7 ... 10:
            return .child7to10
        case 11 ... 14:
            return .child11to14
        case 15 ... 17:
            return .child15to17
        default:
            return .adult
        }
    }
}

struct RDIValue: Codable {
    let value: Double
    let unit: String
}

// MARK: - EFSA RDI Database

enum EFSAReferenceIntakes {
    static func value(
        for nutrient: MicroNutrient,
        age: Int,
        sex: Sex
    ) -> RDIValue {
        let group = AgeGroup.from(age: age)

        switch nutrient {
        case .vitaminA:
            switch (group, sex) {
            case (.adult, .man): return .init(value: 750, unit: "µg")
            case (.adult, .woman): return .init(value: 650, unit: "µg")
            case (.child15to17, .man): return .init(value: 750, unit: "µg")
            case (.child15to17, .woman): return .init(value: 650, unit: "µg")
            case (.child11to14, _): return .init(value: 600, unit: "µg")
            case (.child7to10, _): return .init(value: 500, unit: "µg")
            case (.child4to6, _): return .init(value: 400, unit: "µg")
            case (.child1to3, _): return .init(value: 250, unit: "µg")
            case (.infant7to11Months, _): return .init(value: 250, unit: "µg")
            case (.child15to17, .other): return .init(value: 650, unit: "µg")
            case (.child15to17, .secret): return .init(value: 650, unit: "µg")
            case (.adult, .other): return .init(value: 650, unit: "µg")
            case (.adult, .secret): return .init(value: 650, unit: "µg")
            }

        case .vitaminD:
            return .init(value: 15, unit: "µg")

        case .vitaminE:
            switch sex {
            case .man:
                return .init(value: 13, unit: "mg")
            case .woman:
                return .init(value: 11, unit: "mg")
            default:
                return .init(value: 11, unit: "mg")
            }

        case .vitaminK:
            return .init(value: 70, unit: "µg")

        case .vitaminC:
            switch sex {
            case .man: return .init(value: 110, unit: "mg")
            case .woman: return .init(value: 95, unit: "mg")
            default: return .init(value: 95, unit: "mg")
            }

        case .vitaminB1:
            switch sex {
            case .man: return .init(value: 1.2, unit: "mg")
            case .woman: return .init(value: 1.1, unit: "mg")
            default: return .init(value: 1.1, unit: "mg")
            }

        case .vitaminB2:
            switch sex {
            case .man: return .init(value: 1.6, unit: "mg")
            case .woman: return .init(value: 1.3, unit: "mg")
            default: return .init(value: 1.3, unit: "mg")
            }

        case .vitaminB3:
            switch sex {
            case .man: return .init(value: 16, unit: "mg")
            case .woman: return .init(value: 14, unit: "mg")
            default: return .init(value: 14, unit: "mg")
            }

        case .vitaminB6:
            switch sex {
            case .man: return .init(value: 1.7, unit: "mg")
            case .woman: return .init(value: 1.6, unit: "mg")
            default: return .init(value: 1.6, unit: "mg")
            }

        case .vitaminB9:
            return .init(value: 330, unit: "µg")

        case .vitaminB12:
            return .init(value: 4, unit: "µg")

        case .vitaminB7:
            return .init(value: 40, unit: "µg")

        case .vitaminB5:
            return .init(value: 5, unit: "mg")

        // MARK: Minerals

        case .potassium:
            return .init(value: 3500, unit: "mg")

        case .calcium:
            switch group {
            case .adult:
                return .init(value: 950, unit: "mg")
            case .child15to17:
                return .init(value: 1150, unit: "mg")
            case .child11to14:
                return .init(value: 1150, unit: "mg")
            case .child7to10:
                return .init(value: 900, unit: "mg")
            case .child4to6:
                return .init(value: 800, unit: "mg")
            case .child1to3:
                return .init(value: 450, unit: "mg")
            case .infant7to11Months:
                return .init(value: 280, unit: "mg")
            }

        case .phosphorus:
            return .init(value: 550, unit: "mg")

        case .magnesium:
            switch sex {
            case .man: return .init(value: 350, unit: "mg")
            case .woman: return .init(value: 300, unit: "mg")
            default: return .init(value: 300, unit: "mg")
            }

        case .iron:
            switch sex {
            case .man: return .init(value: 11, unit: "mg")
            case .woman: return .init(value: 16, unit: "mg")
            default: return .init(value: 16, unit: "mg")
            }

        case .zinc:
            switch sex {
            case .man: return .init(value: 9.4, unit: "mg")
            case .woman: return .init(value: 7.5, unit: "mg")
            default: return .init(value: 7.5, unit: "mg")
            }

        case .copper:
            return .init(value: 1.3, unit: "mg")

        case .manganese:
            return .init(value: 3, unit: "mg")

        case .selenium:
            switch sex {
            case .man: return .init(value: 70, unit: "µg")
            case .woman: return .init(value: 60, unit: "µg")
            default: return .init(value: 60, unit: "µg")
            }

        /* case .chromium:
            return .init(value: 40, unit: "µg")

        case .molybdenum:
            return .init(value: 65, unit: "µg") */

        case .iodine:
            return .init(value: 150, unit: "µg")

        case .salt:
            return .init(value: 5, unit: "g")

            /* case .fluoride:
             switch sex {
             case .male:
                 return .init(value: 3.4, unit: "mg")
             case .female:
                 return .init(value: 2.9, unit: "mg")
             } */
        }
    }

    /// Macro API
    static func value(
        for nutrient: MacroNutrient,
        age: Int,
        sex: Sex
    ) -> RDIValue {
        let group = AgeGroup.from(age: age)

        switch nutrient {
        case .protein:
            switch (group, sex) {
            case (.adult, .man):
                return .init(value: 62, unit: "g")

            case (.adult, .woman):
                return .init(value: 52, unit: "g")

            default:
                return .init(value: 52, unit: "g")
            }

        case .fiber:
            switch group {
            case .adult:
                return .init(value: 25, unit: "g")

            case .child11to14:
                return .init(value: 21, unit: "g")

            default:
                return .init(value: 16, unit: "g")
            }
        }
    }
}

// MARK: - Daily Percentage Calculation

enum MicronutrientProgress {
    /// Micros
    static func progress(
        nutrient: MicroNutrient,
        amount: Double,
        age: Int,
        sex: Sex
    ) -> NutrientProgress {
        let reference = EFSAReferenceIntakes.value(
            for: nutrient,
            age: age,
            sex: sex
        )

        guard reference.value > 0 else {
            return NutrientProgress(
                percent: 0,
                color: .secondary
            )
        }

        let percent = (amount / reference.value) * 100

        return NutrientProgress(
            percent: percent,
            color: NutrientProgressColor.color(
                nutrient: nutrient,
                percent: percent
            )
        )
    }

    /// Macros overload
    static func progress(
        nutrient: MacroNutrient,
        amount: Double,
        age: Int,
        sex: Sex
    ) -> NutrientProgress {
        let reference = EFSAReferenceIntakes.value(
            for: nutrient,
            age: age,
            sex: sex
        )

        let percent = (amount / reference.value) * 100

        return NutrientProgress(
            percent: percent,
            color: NutrientProgressColor.color(
                nutrient: nutrient,
                percent: percent
            )
        )
    }
}

enum NutrientProgressColor {
    static func color<T: RDITrackable>(
        nutrient: T,
        percent: Double
    ) -> Color {
        if nutrient.shouldLimitExcess {
            switch percent {
            case 20 ..< 75:
                return .cyan
            case 75 ... 125:
                return .mint
            case 125 ... 200:
                return .yellow
            default:
                return .orange
            }
        }

        switch percent {
        case 0 ..< 25:
            return .orange
        case 25 ..< 75:
            return .mint
        default:
            return .green
        }
    }
}

struct Individual {
    var age: Int
    var sex: Sex
}

extension Individual {
    static let `default` = Individual(age: 35, sex: .woman)
}

struct NutrientProgress {
    let percent: Double
    let color: Color
}
