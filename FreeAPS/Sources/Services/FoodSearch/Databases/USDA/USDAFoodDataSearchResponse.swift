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

    case sugarsTotalIncludingNLEA = 269
    case sugarsTotal = 1010
    case sugarsAdded = 1063

    case energyKcal = 208
    case energyGross = 1008
    case energyMetabolizable = 1062

    // MARK: Vitamins

    case vitaminA_RAE = 320
    case vitaminA_IU = 318

    case vitaminC = 401
    case vitaminD = 328
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

        case .sugarsAdded,
             .sugarsTotal,
             .sugarsTotalIncludingNLEA:
            return .sugar

        case .energyGross,
             .energyKcal,
             .energyMetabolizable:
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
             .vitaminE,
             .vitaminK:
            return .vitamin

        default:
            return .mineral
        }
    }

    var microNutrient: MicroNutrient? {
        switch self {
        case .vitaminA_IU,
             .vitaminA_RAE:
            return .vitaminA

        case .vitaminC:
            return .vitaminC

        case .vitaminD:
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

        // sodium -> salt conversion
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
}

// MARK: - Normalization

extension USDAFoodNutrient {
    func normalizedValue(
        for micro: MicroNutrient
    ) -> Decimal? {
        guard let value else {
            return nil
        }

        let decimal = Decimal(value)

        switch unitName?.lowercased() {
        case "g":
            return micro.normalized(
                value: decimal,
                from: .g
            )

        case "mg":
            return micro.normalized(
                value: decimal,
                from: .mg
            )

        case "mcg",
             "ug",
             "µg":
            return micro.normalized(
                value: decimal,
                from: .ug
            )

        case "iu":
            return micro.normalized(
                value: decimal,
                from: .iu
            )

        default:
            return decimal
        }
    }
}
