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

struct NutritionValues: Equatable {
    let calories: Decimal?
    let carbs: Decimal?
    let fat: Decimal?
    let fiber: Decimal?
    let protein: Decimal?
    let sugars: Decimal?
}

enum FoodNutrition: Equatable {
    case per100(NutritionValues)
    case perServing(NutritionValues)
}

struct FoodItemDetailed: Identifiable, Equatable {
    let id: UUID
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

    let source: FoodItemSource

    static func == (lhs: FoodItemDetailed, rhs: FoodItemDetailed) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.confidence == rhs.confidence &&
            lhs.brand == rhs.brand &&
            lhs.portionSize == rhs.portionSize &&
            lhs.servingsMultiplier == rhs.servingsMultiplier &&
            lhs.standardServing == rhs.standardServing &&
            lhs.standardServingSize == rhs.standardServingSize &&
            lhs.units == rhs.units &&
            lhs.preparationMethod == rhs.preparationMethod &&
            lhs.visualCues == rhs.visualCues &&
            lhs.glycemicIndex == rhs.glycemicIndex &&
            lhs.nutrition == rhs.nutrition &&
            lhs.assessmentNotes == rhs.assessmentNotes &&
            lhs.imageURL == rhs.imageURL &&
            lhs.imageFrontURL == rhs.imageFrontURL &&
            lhs.source == rhs.source
    }

    init(
        id: UUID? = nil,
        name: String,
        nutritionPer100: NutritionValues,
        portionSize: Decimal,
        confidence: ConfidenceLevel? = nil,
        brand: String? = nil,
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
        self.id = id ?? UUID()
        self.name = name
        self.confidence = confidence
        self.brand = brand
        self.portionSize = portionSize
        servingsMultiplier = nil
        self.standardServing = standardServing
        self.standardServingSize = standardServingSize
        self.units = units
        self.preparationMethod = preparationMethod
        self.visualCues = visualCues
        self.glycemicIndex = glycemicIndex
        nutrition = .per100(nutritionPer100)
        self.assessmentNotes = assessmentNotes
        self.imageURL = imageURL
        self.imageFrontURL = imageFrontURL
        self.source = source
    }

    init(
        id: UUID? = nil,
        name: String,
        nutritionPerServing: NutritionValues,
        servingsMultiplier: Decimal,
        confidence: ConfidenceLevel? = nil,
        brand: String? = nil,
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
        self.id = id ?? UUID()
        self.name = name
        self.confidence = confidence
        self.brand = brand
        portionSize = nil
        self.servingsMultiplier = servingsMultiplier
        self.standardServing = standardServing
        self.standardServingSize = standardServingSize
        self.units = units
        self.preparationMethod = preparationMethod
        self.visualCues = visualCues
        self.glycemicIndex = glycemicIndex
        nutrition = .perServing(nutritionPerServing)
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
        case let .per100(nutrition):
            return FoodItemDetailed(
                name: name,
                nutritionPer100: nutrition,
                portionSize: newPortion,
                confidence: confidence,
                brand: brand,
                standardServing: standardServing,
                standardServingSize: standardServingSize,
                units: units,
                preparationMethod: preparationMethod,
                visualCues: visualCues,
                glycemicIndex: glycemicIndex,
                assessmentNotes: assessmentNotes,
                imageURL: imageURL,
                imageFrontURL: imageFrontURL,
                source: source
            )
        case let .perServing(nutrition):
            return FoodItemDetailed(
                name: name,
                nutritionPerServing: nutrition,
                servingsMultiplier: newPortion,
                confidence: confidence,
                brand: brand,
                standardServing: standardServing,
                standardServingSize: standardServingSize,
                units: units,
                preparationMethod: preparationMethod,
                visualCues: visualCues,
                glycemicIndex: glycemicIndex,
                assessmentNotes: assessmentNotes,
                imageURL: imageURL,
                imageFrontURL: imageFrontURL,
                source: source
            )
        }
    }
}
