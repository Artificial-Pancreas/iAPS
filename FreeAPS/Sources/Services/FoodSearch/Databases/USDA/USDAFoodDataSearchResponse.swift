import Foundation

// MARK: - USDA Nutrient Codes

enum USDANutrientCode: Int {
    // MARK: Macronutrients

    case carbohydrateByDifference = 205
    case carbohydrateBySummation = 1005
    case carbohydrateOther = 1050

    case protein = 203
    case proteinCrude = 1003

    case totalLipidFat = 204
    case totalLipidCrude = 1004

    case fiberTotalDietary = 291
    case fiberCrude = 1079

    // the total: "Total Sugars" (SR Legacy, Survey; number 269) and "Sugars, Total" (Foundation, 269.3). Not 1010,
    // which is sucrose (it was read as the total), nor the added sugars (1235).
    case sugarsTotalIncludingNLEA = 269
    case sugarsTotal = 2000
    case sugarsTotalFoundation = 1063

    // "Energy" in kcal (number 208, id 1008) or kJ (268, 1062: SR Legacy lists it first as often as not), or by
    // Atwater's factors in kcal (Foundation foods, often instead of 1008): `USDAFoodNutrient.energyKcal` reads the unit
    case energyKcal = 208
    case energy = 1008
    case energyKJ = 268
    case energyKJById = 1062
    case energyAtwaterGeneral = 2047
    case energyAtwaterSpecific = 2048

    // MARK: Vitamins

    case vitaminA_RAE = 320
    case vitaminA_IU = 318

    case vitaminC = 401
    case vitaminD = 328
    case vitaminD_IU = 324
    case vitaminE = 323
    case vitaminK = 430

    case thiamin = 404
    case riboflavin = 405
    case niacin = 406
    case pantothenicAcid = 410
    case vitaminB6 = 415

    case folateTotal = 417
    case folateDFE = 435

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
    case iodine = 314
    case manganese = 315
    case selenium = 317

    // MARK: Categories

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

        case .sugarsTotal,
             .sugarsTotalFoundation,
             .sugarsTotalIncludingNLEA:
            return .sugar

        case .energy,
             .energyAtwaterGeneral,
             .energyAtwaterSpecific,
             .energyKcal,
             .energyKJ,
             .energyKJById:
            return .energy

        case .folateDFE,
             .folateTotal,
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
             .vitaminD_IU,
             .vitaminE,
             .vitaminK:
            return .vitamin

        default:
            return .mineral
        }
    }

    /// The substance stored. Vitamin A in IU isn't: IU counts retinol (0.3 µg) and the carotenoids (≈ 0.05 µg RAE,
    /// less in a mixed food) differently, so no factor turns a food's IU into the µg RAE stored; only the RAE is read.
    /// Vitamin D in IU is (1 IU = 0.025 µg), when the food has no µg row (`substancePriority`).
    var microNutrient: MicroNutrient? {
        switch self {
        case .vitaminA_RAE:
            return .vitaminA

        case .vitaminC:
            return .vitaminC

        case .vitaminD,
             .vitaminD_IU:
            return .vitaminD

        case .vitaminE:
            return .vitaminE

        case .vitaminK:
            return .vitaminK

        case .thiamin:
            return .vitaminB1

        case .riboflavin:
            return .vitaminB2

        case .niacin:
            return .vitaminB3

        case .pantothenicAcid:
            return .vitaminB5

        case .vitaminB6:
            return .vitaminB6

        case .folateDFE,
             .folateTotal:
            return .vitaminB9

        case .vitaminB12:
            return .vitaminB12

        case .calcium:
            return .calcium

        case .iron:
            return .iron

        case .magnesium:
            return .magnesium

        case .phosphorus:
            return .phosphorus

        case .potassium:
            return .potassium

        case .zinc:
            return .zinc

        case .copper:
            return .copper

        case .manganese:
            return .manganese

        case .selenium:
            return .selenium

        case .iodine:
            return .iodine

        // sodium, as salt (`normalizedValue(for:)` converts it)
        case .sodium:
            return .salt

        default:
            return nil
        }
    }
}

// MARK: - Search Response

struct USDASearchResponse: Codable {
    let foods: [USDAFood]
}

// MARK: - Food

struct USDAFood: Codable {
    let fdcId: Int
    let description: String
    let foodNutrients: [USDAFoodNutrient]?
}

// MARK: - Nutrient

struct USDAFoodNutrient: Codable {
    let nutrientId: Int?
    let nutrientNumber: String?
    let nutrientName: String?

    let value: Double?
    let unitName: String?

    var nutrientNumberAsInt: Int? {
        if let nutrientId {
            return nutrientId
        }

        if let nutrientNumber,
           let value = Int(nutrientNumber)
        {
            return value
        }

        return nil
    }

    var nutrientCode: USDANutrientCode? {
        guard let number = nutrientNumberAsInt else {
            return nil
        }

        return USDANutrientCode(rawValue: number)
    }

    /// The value by its shortest description, as Open Food Facts' (`AnyDecodable.decimalValue`): `Decimal(Double)`
    /// turns 0.0006 into 0.0005999999999999998976.
    var decimalValue: Decimal? {
        value.map { Decimal(string: "\($0)") ?? Decimal($0) }
    }
}

// MARK: - Normalization

extension USDAFoodNutrient {
    /// USDA lists sodium (mg), not salt
    var isSodium: Bool {
        if nutrientCode == .sodium {
            return true
        }
        return nutrientName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sodium, na"
    }

    /// The unit, without what follows `_`: what the amount is counted as (`MG_ATE`, vitamin E as alpha-tocopherol
    /// equivalents; `MCG_RE`, `MCG_DFE`, `MG_GAE`) is still mg or µg.
    var baseUnit: String? {
        unitName?.lowercased().split(separator: "_", maxSplits: 1).first.map(String.init)
    }

    /// In `micro.unit`; sodium as the salt it makes (`MicroNutrient.saltPerSodium`). nil in a unit not known (it
    /// would be stored as if in `micro.unit`, sodium × 2.5 as it is), and in IU but for vitamin D (no factor turns
    /// vitamin A's into µg RAE, `USDANutrientCode.microNutrient`; none is single for vitamin E).
    func normalizedValue(
        for micro: MicroNutrient
    ) -> Decimal? {
        guard let decimal = decimalValue else {
            return nil
        }

        let normalized: Decimal

        switch baseUnit {
        case "g":
            normalized = micro.normalized(
                value: decimal,
                from: .g
            )

        case "mg":
            normalized = micro.normalized(
                value: decimal,
                from: .mg
            )

        case "mcg",
             "ug",
             "µg":
            normalized = micro.normalized(
                value: decimal,
                from: .ug
            )

        case "iu":
            guard micro == .vitaminD else {
                return nil
            }
            normalized = micro.normalized(
                value: decimal,
                from: .iu
            )

        default:
            return nil
        }

        guard micro == .salt, isSodium else {
            return normalized
        }
        return normalized * MicroNutrient.saltPerSodium
    }
}

// MARK: - One value per substance

extension USDAFoodNutrient {
    /// Which of a food's rows of one substance is read, the lowest first: folate as DFE (what the reference intakes are
    /// in) before the total, which also lists it; vitamin D in µg before the same in IU.
    var substancePriority: Int {
        if baseUnit == "iu" {
            return 1
        }
        return nutrientCode == .folateTotal || nutrientName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "folate, total" ? 1 : 0
    }

    /// A food's micronutrients, one per substance (`substancePriority`, the first listed among equals), in the stored unit
    /// (`normalizedValue(for:)`). Before, the RAE and the IU of vitamin A, and folate's DFE and total, were all kept, and
    /// summed.
    static func micronutrients(_ nutrients: [USDAFoodNutrient]) -> [MicronutrientValue] {
        var chosen: [MicroNutrient: (priority: Int, index: Int, amount: Decimal)] = [:]
        for (index, nutrient) in nutrients.enumerated() {
            guard let micro = nutrient.resolvedMicroNutrient, let amount = nutrient.normalizedValue(for: micro) else {
                continue
            }
            let priority = nutrient.substancePriority
            if let current = chosen[micro], current.priority <= priority {
                continue
            }
            chosen[micro] = (priority, index, amount)
        }
        return chosen.sorted { $0.value.index < $1.value.index }.map { micro, value in
            MicronutrientValue(substance: micro, amount: value.amount, amountPer100: value.amount)
        }
    }
}

// MARK: - Macronutrients

extension USDAFoodNutrient {
    static let kilojoulesPerKilocalorie: Decimal = 4.184

    /// kcal per 100 g: an energy row in kcal ("Energy" first, then Atwater's specific factors, then the general ones,
    /// which Foundation foods list instead), else one in kJ ÷ 4.184; nil without one above 0. Before, the first energy
    /// row was read whatever its unit: the kJ row, which SR Legacy lists first as often as not, read as kcal.
    static func energyKcal(_ nutrients: [USDAFoodNutrient]) -> Decimal? {
        let rows = nutrients.compactMap { nutrient -> (rank: Int, kcal: Decimal)? in
            guard let code = nutrient.nutrientCode, code.category == .energy,
                  let value = nutrient.decimalValue, value > 0
            else { return nil }
            switch nutrient.baseUnit {
            case "kcal":
                switch code {
                case .energy,
                     .energyKcal: return (0, value)
                case .energyAtwaterSpecific: return (1, value)
                default: return (2, value)
                }
            case "kj":
                return (3, value / kilojoulesPerKilocalorie)
            default:
                return nil
            }
        }
        return rows.min { $0.rank < $1.rank }?.kcal
    }
}

/// A food's macronutrients per 100 g: of each, the first row above 0 in g (`USDANutrientCode.category`), and the
/// energy in kcal (`USDAFoodNutrient.energyKcal`).
struct USDAMacronutrients: Equatable {
    var carbs: Decimal = 0
    var protein: Decimal = 0
    var fat: Decimal = 0
    var fiber: Decimal = 0
    var sugars: Decimal = 0
    var energy: Decimal = 0

    init(_ nutrients: [USDAFoodNutrient]) {
        for nutrient in nutrients {
            guard let code = nutrient.nutrientCode, let value = nutrient.decimalValue,
                  nutrient.baseUnit == nil || nutrient.baseUnit == "g"
            else { continue }
            switch code.category {
            case .carbohydrate:
                if carbs == 0 { carbs = value }
            case .protein:
                if protein == 0 { protein = value }
            case .fat:
                if fat == 0 { fat = value }
            case .fiber:
                if fiber == 0 { fiber = value }
            case .sugar:
                if sugars == 0 { sugars = value }
            case .energy,
                 .mineral,
                 .vitamin:
                break
            }
        }
        energy = USDAFoodNutrient.energyKcal(nutrients) ?? 0
    }
}
