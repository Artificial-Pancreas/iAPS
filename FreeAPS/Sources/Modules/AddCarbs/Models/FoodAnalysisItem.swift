import Foundation

enum MealUnits: String, Codable {
    case grams
    case milliliters

    var localizedAbbreviation: String {
        switch self {
        case .grams: NSLocalizedString("g", comment: "abbreviation for grams")
        case .milliliters: NSLocalizedString("ml", comment: "abbreviation for milliliters")
        }
    }
}

enum FoodItemSource {
    case ai
    case aiText
    case search
    case barcode
    case manual
}

/// Individual food item analysis with detailed portion assessment
struct AnalysedFoodItem: Identifiable {
    let id = UUID()
    let name: String
    let confidence: AIConfidenceLevel?
    let brand: String?
    let portionEstimate: String?
    let portionEstimateSize: Decimal?
    let standardServing: String?
    let standardServingSize: Decimal?
    let units: MealUnits?
//    let servingsStandard: String?
//    let servingMultiplier: Double
    let preparationMethod: String?
    let visualCues: String?
//    let carbohydrates: Double
//    let calories: Double?
//    let fat: Double?
//    let fiber: Double?
//    let protein: Double?
//    let sugars: Double?
    let glycemicIndex: Decimal?
    let caloriesPer100: Decimal?
    let carbsPer100: Decimal?
    let fatPer100: Decimal?
    let fiberPer100: Decimal?
    let proteinPer100: Decimal?
    let sugarsPer100: Decimal?

    let assessmentNotes: String?

    let imageURL: String?
    let imageFrontURL: String?

    var source: FoodItemSource?

    init(
        name: String,
        confidence: AIConfidenceLevel? = nil,
        brand: String? = nil,
        portionEstimate: String? = nil,
        portionEstimateSize: Decimal? = nil,
        standardServing: String? = nil,
        standardServingSize: Decimal? = nil,
        units: MealUnits? = nil,
        preparationMethod: String? = nil,
        visualCues: String? = nil,
        glycemicIndex: Decimal? = nil,
        caloriesPer100: Decimal? = nil,
        carbsPer100: Decimal? = nil,
        fatPer100: Decimal? = nil,
        fiberPer100: Decimal? = nil,
        proteinPer100: Decimal? = nil,
        sugarsPer100: Decimal? = nil,
        assessmentNotes: String? = nil,
        imageURL: String? = nil,
        imageFrontURL: String? = nil,
        source: FoodItemSource
    ) {
        self.name = name
        self.confidence = confidence
        self.brand = brand
        self.portionEstimate = portionEstimate
        self.portionEstimateSize = portionEstimateSize
        self.standardServing = standardServing
        self.standardServingSize = standardServingSize
        self.units = units
        self.preparationMethod = preparationMethod
        self.visualCues = visualCues
        self.glycemicIndex = glycemicIndex
        self.caloriesPer100 = caloriesPer100
        self.carbsPer100 = carbsPer100
        self.fatPer100 = fatPer100
        self.fiberPer100 = fiberPer100
        self.proteinPer100 = proteinPer100
        self.sugarsPer100 = sugarsPer100
        self.assessmentNotes = assessmentNotes
        self.imageURL = imageURL
        self.imageFrontURL = imageFrontURL
        self.source = source
    }
}

extension AnalysedFoodItem {
    var caloriesInThisPortion: Decimal? {
        guard let portion = portionEstimateSize, let caloriesPer100 = self.caloriesPer100 else { return nil }
        return caloriesPer100 / 100 * portion
    }

    var carbsInThisPortion: Decimal? {
        guard let portion = portionEstimateSize, let carbsPer100 = self.carbsPer100 else { return nil }
        return carbsPer100 / 100 * portion
    }

    var fatInThisPortion: Decimal? {
        guard let portion = portionEstimateSize, let fatPer100 = self.fatPer100 else { return nil }
        return fatPer100 / 100 * portion
    }

    var proteinInThisPortion: Decimal? {
        guard let portion = portionEstimateSize, let proteinPer100 = self.proteinPer100 else { return nil }
        return proteinPer100 / 100 * portion
    }

    func caloriesInPortion(portion: Decimal) -> Decimal? {
        guard let caloriesPer100 = self.caloriesPer100 else { return nil }
        return caloriesPer100 / 100 * portion
    }

    func carbsInPortion(portion: Decimal) -> Decimal? {
        guard let carbsPer100 = self.carbsPer100 else { return nil }
        return carbsPer100 / 100 * portion
    }

    func fatInPortion(portion: Decimal) -> Decimal? {
        guard let fatPer100 = self.fatPer100 else { return nil }
        return fatPer100 / 100 * portion
    }

    func proteinInPortion(portion: Decimal) -> Decimal? {
        guard let proteinPer100 = self.proteinPer100 else { return nil }
        return proteinPer100 / 100 * portion
    }
}

extension AnalysedFoodItem: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let name = try container.decodeTrimmedIfPresent(forKey: .name) ?? "Food item"
        let confidence: AIConfidenceLevel = try container.decode(AIConfidenceLevel.self, forKey: .confidence)
        let brand = try container.decodeTrimmedIfPresent(forKey: .brand)
        let standardServing = try container.decodeTrimmedIfPresent(forKey: .standardServing)
        let standardServingSize = try container.decodeNumberIfPresent(forKey: .standardServingSize)
        let portionEstimate = try container.decodeTrimmedIfPresent(forKey: .portionEstimate)
        let portionEstimateSize = try container.decodeNumberIfPresent(forKey: .portionEstimateSize) ?? standardServingSize
        let units = try container.decodeIfPresent(MealUnits.self, forKey: .units) ?? .grams
//        let servingsStandard = try container.decodeTrimmedIfPresent(forKey: .servingsStandard)
//        let servingMultiplier = try container.decodeNumberIfPresent(forKey: .servingMultiplier) ?? 1.0
        let preparationMethod = try container.decodeTrimmedIfPresent(forKey: .preparationMethod)
        let visualCues = try container.decodeTrimmedIfPresent(forKey: .visualCues)
        let glycemicIndex = try container.decodeNumberIfPresent(forKey: .glycemicIndex)
        let carbsPer100 = try container.decodeNumberIfPresent(forKey: .carbsPer100)
        let caloriesPer100 = try container.decodeNumberIfPresent(forKey: .caloriesPer100)
        let fatPer100 = try container.decodeNumberIfPresent(forKey: .fatPer100)
        let fiberPer100 = try container.decodeNumberIfPresent(forKey: .fiberPer100)
        let proteinPer100 = try container.decodeNumberIfPresent(forKey: .proteinPer100)
        let sugarsPer100 = try container.decodeNumberIfPresent(forKey: .sugarsPer100)
        let assessmentNotes = try container.decodeTrimmedIfPresent(forKey: .assessmentNotes)

        self.name = name
        self.confidence = confidence
        self.brand = brand
        self.portionEstimate = portionEstimate
        self.portionEstimateSize = portionEstimateSize
        self.standardServing = standardServing
        self.standardServingSize = standardServingSize
        self.units = units
//            servingsStandard: servingsStandard,
//            servingMultiplier: servingMultiplier,
        self.preparationMethod = preparationMethod
        self.visualCues = visualCues
        self.glycemicIndex = glycemicIndex
        self.caloriesPer100 = caloriesPer100
        self.carbsPer100 = carbsPer100
        self.fatPer100 = fatPer100
        self.fiberPer100 = fiberPer100
        self.proteinPer100 = proteinPer100
        self.sugarsPer100 = sugarsPer100
        self.assessmentNotes = assessmentNotes
        source = .ai
        imageURL = nil
        imageFrontURL = nil
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case confidence
        case brand
        case portionEstimate = "portion_estimate"
        case portionEstimateSize = "portion_estimate_size"
        case standardServing = "standard_serving"
        case standardServingSize = "standard_serving_size"
        case units
//        case servingsStandard = "serving_standard"
//        case servingMultiplier = "serving_multiplier"
        case preparationMethod = "preparation_method"
        case visualCues = "visual_cues"
//        case carbohydrates
//        case calories
//        case fat
//        case fiber
//        case protein
//        case sugars
        case glycemicIndex = "glycemic_index"
        case caloriesPer100 = "calories_per_100"
        case carbsPer100 = "carbs_per_100"
        case fatPer100 = "fat_per_100"
        case fiberPer100 = "fiber_per_100"
        case proteinPer100 = "protein_per_100"
        case sugarsPer100 = "sugars_per_100"

        case assessmentNotes = "assessment_notes"
    }
}

extension AnalysedFoodItem {
    private static var fields: [(AnalysedFoodItem.CodingKeys, Any)] {
        [
            (.name, "string, required; specific food name"),
            (.confidence, "decimal 0 to 1; required; confidence for this item"),
            (.units, "string enum; one of: 'grams' or 'milliliters'; as appropriate for this meal; do NOT translate;"),
            (.caloriesPer100, "decimal, kilocalories per 100 grams or milliliters"),
            (.carbsPer100, "decimal, grams of carbohydrates per 100 grams or milliliters"),
            (.fatPer100, "decimal, grams of fat per 100 grams or milliliters"),
            (.fiberPer100, "decimal, grams of fiber per 100 grams or milliliters"),
            (.proteinPer100, "decimal, grams of protein per 100 grams or milliliters"),
            (.sugarsPer100, "decimal, grams of sugars per 100 grams or milliliters"),
            (.portionEstimate, "desription of the identified portion; (language)"),
            (.portionEstimateSize, "decimal, exact size of the identified portion; in grams or milliliters; do not include unit"),
            (
                .standardServingSize,
                "decimal, the identified standard serving size in grams or milliliters, if available; do not include unit"
            ),
            (
                .standardServing,
                "description of the identified standard serving, if available, is natural description is available - do NOT add size in grams/milliliters, since you've already specified it above; (language)"
            ),
            (.glycemicIndex, "decimal, glycemic index if available")
        ]
    }

    static var schemaVisual: [(String, Any)] {
        let fields = self.fields + [
            (.visualCues, "visual elements analyzed; (language)"),
            (.preparationMethod, "cooking details observed; (language)"),
            (
                .assessmentNotes,
                "explain how you calculated this specific portion size, what visual references you used for measurement; (language)"
            )
        ]
        return fields.map { key, value in
            (key.rawValue, value)
        }
    }

    static var schemaText: [(String, Any)] {
        let fields = self.fields + [
            //        (.portionEstimateSize,
            //            "decimal, assume the portion matches the standard serving size, in grams or milliliters; do not include unit;"),
//            (.preparationMethod, "cooking details if mentioned")
            (
                .assessmentNotes,
                "explain how you calculated this specific portion size, what references you used; (language)"
            )
        ]
        return fields.map { key, value in
            (key.rawValue, value)
        }
    }
}
