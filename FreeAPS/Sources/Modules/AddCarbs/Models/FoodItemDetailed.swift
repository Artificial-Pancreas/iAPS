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

enum ConfidenceLevel: String, Codable, Identifiable, CaseIterable {
    case high
    case medium
    case low

    var id: ConfidenceLevel { self }
}

struct NutritionValues {
    let calories: Decimal?
    let carbs: Decimal?
    let fat: Decimal?
    let fiber: Decimal?
    let protein: Decimal?
    let sugars: Decimal?
}

enum FoodNutrition {
    case per100(NutritionValues)
    case perServing(NutritionValues)
}

struct FoodItemDetailed: Identifiable {
    let id = UUID()
    let name: String
    let confidence: ConfidenceLevel?
    let brand: String?
    let portionSize: Decimal?
    let servingsMultiplier: Decimal?
    let standardServing: String?
    let standardServingSize: Decimal?
    let units: MealUnits?
    let preparationMethod: String?
    let visualCues: String?
    let glycemicIndex: Decimal?

    let nutrition: FoodNutrition

    let assessmentNotes: String?

    let imageURL: String?
    let imageFrontURL: String?

    var source: FoodItemSource?

    init(
        name: String,
        nutrition: FoodNutrition,
        confidence: ConfidenceLevel? = nil,
        brand: String? = nil,
        portionSize: Decimal? = nil,
        servingsMultiplier: Decimal? = nil,
        standardServing: String? = nil,
        standardServingSize: Decimal? = nil,
        units: MealUnits? = nil,
        preparationMethod: String? = nil,
        visualCues: String? = nil,
        glycemicIndex: Decimal? = nil,
        assessmentNotes: String? = nil,
        imageURL: String? = nil,
        imageFrontURL: String? = nil,
        source: FoodItemSource
    ) {
        self.name = name
        self.confidence = confidence
        self.brand = brand
        self.portionSize = portionSize
        self.servingsMultiplier = servingsMultiplier
        self.standardServing = standardServing
        self.standardServingSize = standardServingSize
        self.units = units
        self.preparationMethod = preparationMethod
        self.visualCues = visualCues
        self.glycemicIndex = glycemicIndex
        self.nutrition = nutrition
        self.assessmentNotes = assessmentNotes
        self.imageURL = imageURL
        self.imageFrontURL = imageFrontURL
        self.source = source
    }
}

extension FoodItemDetailed {
    var caloriesInThisPortion: Decimal? {
        switch nutrition {
        case .per100:
            guard let portion = portionSize else { return nil }
            return caloriesInPortion(portion: portion)
        case .perServing:
            guard let multiplier = servingsMultiplier else { return nil }
            return caloriesInServings(multiplier: multiplier)
        }
    }

    var carbsInThisPortion: Decimal? {
        switch nutrition {
        case .per100:
            guard let portion = portionSize else { return nil }
            return carbsInPortion(portion: portion)
        case .perServing:
            guard let multiplier = servingsMultiplier else { return nil }
            return carbsInServings(multiplier: multiplier)
        }
    }

    var fatInThisPortion: Decimal? {
        switch nutrition {
        case .per100:
            guard let portion = portionSize else { return nil }
            return fatInPortion(portion: portion)
        case .perServing:
            guard let multiplier = servingsMultiplier else { return nil }
            return fatInServings(multiplier: multiplier)
        }
    }

    var proteinInThisPortion: Decimal? {
        switch nutrition {
        case .per100:
            guard let portion = portionSize else { return nil }
            return proteinInPortion(portion: portion)
        case .perServing:
            guard let multiplier = servingsMultiplier else { return nil }
            return proteinInServings(multiplier: multiplier)
        }
    }

    // MARK: - Per 100g/ml calculations

    func caloriesInPortion(portion: Decimal) -> Decimal? {
        guard case let .per100(per100) = nutrition else { return nil }
        guard let caloriesPer100 = per100.calories else { return nil }
        return caloriesPer100 / 100 * portion
    }

    func carbsInPortion(portion: Decimal) -> Decimal? {
        guard case let .per100(per100) = nutrition else { return nil }
        guard let carbsPer100 = per100.carbs else { return nil }
        return carbsPer100 / 100 * portion
    }

    func fatInPortion(portion: Decimal) -> Decimal? {
        guard case let .per100(per100) = nutrition else { return nil }
        guard let fatPer100 = per100.fat else { return nil }
        return fatPer100 / 100 * portion
    }

    func proteinInPortion(portion: Decimal) -> Decimal? {
        guard case let .per100(per100) = nutrition else { return nil }
        guard let proteinPer100 = per100.protein else { return nil }
        return proteinPer100 / 100 * portion
    }

    // MARK: - Per serving calculations

    func caloriesInServings(multiplier: Decimal) -> Decimal? {
        guard case let .perServing(perServing) = nutrition else { return nil }
        guard let caloriesPerServing = perServing.calories else { return nil }
        return caloriesPerServing * multiplier
    }

    func carbsInServings(multiplier: Decimal) -> Decimal? {
        guard case let .perServing(perServing) = nutrition else { return nil }
        guard let carbsPerServing = perServing.carbs else { return nil }
        return carbsPerServing * multiplier
    }

    func fatInServings(multiplier: Decimal) -> Decimal? {
        guard case let .perServing(perServing) = nutrition else { return nil }
        guard let fatPerServing = perServing.fat else { return nil }
        return fatPerServing * multiplier
    }

    func proteinInServings(multiplier: Decimal) -> Decimal? {
        guard case let .perServing(perServing) = nutrition else { return nil }
        guard let proteinPerServing = perServing.protein else { return nil }
        return proteinPerServing * multiplier
    }

    /// Returns a copy of this food item with an updated portion size or servings multiplier
    func withPortion(_ newPortion: Decimal) -> FoodItemDetailed {
        switch nutrition {
        case .per100:
            return FoodItemDetailed(
                name: name,
                nutrition: nutrition,
                confidence: confidence,
                brand: brand,
                portionSize: newPortion,
                servingsMultiplier: servingsMultiplier,
                standardServing: standardServing,
                standardServingSize: standardServingSize,
                units: units,
                preparationMethod: preparationMethod,
                visualCues: visualCues,
                glycemicIndex: glycemicIndex,
                assessmentNotes: assessmentNotes,
                imageURL: imageURL,
                imageFrontURL: imageFrontURL,
                source: source ?? .manual
            )
        case .perServing:
            return FoodItemDetailed(
                name: name,
                nutrition: nutrition,
                confidence: confidence,
                brand: brand,
                portionSize: portionSize,
                servingsMultiplier: newPortion,
                standardServing: standardServing,
                standardServingSize: standardServingSize,
                units: units,
                preparationMethod: preparationMethod,
                visualCues: visualCues,
                glycemicIndex: glycemicIndex,
                assessmentNotes: assessmentNotes,
                imageURL: imageURL,
                imageFrontURL: imageFrontURL,
                source: source ?? .manual
            )
        }
    }
}
