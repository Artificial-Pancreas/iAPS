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
    case aiPhoto
    case aiMenu
    case aiReceipe
    case aiText
    case search
    case barcode
    case manual
    case database

    var isAI: Bool {
        switch self {
        case .aiMenu,
             .aiPhoto,
             .aiReceipe,
             .aiText: true
        default: false
        }
    }
}

enum ConfidenceLevel: String, JSON, Identifiable, CaseIterable {
    case high
    case medium
    case low

    var id: ConfidenceLevel { self }
}

struct FoodItemDetailed: Identifiable {
    let id = UUID()
    let name: String
    let confidence: ConfidenceLevel?
    let brand: String?
    let portionSize: Decimal?
    let standardServing: String?
    let standardServingSize: Decimal?
    let units: MealUnits?
    let preparationMethod: String?
    let visualCues: String?
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
        confidence: ConfidenceLevel? = nil,
        brand: String? = nil,
        portionSize: Decimal? = nil,
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
        self.portionSize = portionSize
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

extension FoodItemDetailed {
    var caloriesInThisPortion: Decimal? {
        guard let portion = portionSize else { return nil }
        return caloriesInPortion(portion: portion)
    }

    var carbsInThisPortion: Decimal? {
        guard let portion = portionSize else { return nil }
        return carbsInPortion(portion: portion)
    }

    var fatInThisPortion: Decimal? {
        guard let portion = portionSize else { return nil }
        return fatInPortion(portion: portion)
    }

    var proteinInThisPortion: Decimal? {
        guard let portion = portionSize else { return nil }
        return proteinInPortion(portion: portion)
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

    /// Returns a copy of this food item with an updated portion size
    func withPortion(_ newPortion: Decimal) -> FoodItemDetailed {
        FoodItemDetailed(
            name: name,
            confidence: confidence,
            brand: brand,
            portionSize: newPortion,
            standardServing: standardServing,
            standardServingSize: standardServingSize,
            units: units,
            preparationMethod: preparationMethod,
            visualCues: visualCues,
            glycemicIndex: glycemicIndex,
            caloriesPer100: caloriesPer100,
            carbsPer100: carbsPer100,
            fatPer100: fatPer100,
            fiberPer100: fiberPer100,
            proteinPer100: proteinPer100,
            sugarsPer100: sugarsPer100,
            assessmentNotes: assessmentNotes,
            imageURL: imageURL,
            imageFrontURL: imageFrontURL,
            source: source ?? .manual
        )
    }
}
