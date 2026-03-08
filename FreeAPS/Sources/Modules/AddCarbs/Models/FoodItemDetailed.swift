import Foundation

enum MealUnits: String, Codable {
    case grams
    case milliliters

    var dimension: Dimension {
        switch self {
        case .grams: UnitMass.grams
        case .milliliters: UnitVolume.milliliters
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

enum NutrientType: String, Equatable, Identifiable, CaseIterable {
    case carbs
    case protein
    case fat
    case fiber
    case sugars

    var id: NutrientType { self }
}

typealias NutritionValues = [NutrientType: Decimal]

extension NutrientType {
    var localizedLabel: String {
        switch self {
        case .carbs: NSLocalizedString("nutrient_carbs", comment: "display label for carbs")
        case .fat: NSLocalizedString("nutrient_fat", comment: "display label for fat")
        case .fiber: NSLocalizedString("nutrient_fiber", comment: "display label for fiber")
        case .protein: NSLocalizedString("nutrient_protein", comment: "display label for protein")
        case .sugars: NSLocalizedString("nutrient_sugars", comment: "display label for sugars")
        }
    }

    var unit: Dimension {
        switch self {
        case .carbs,
             .fat,
             .fiber,
             .protein,
             .sugars:
            UnitMass.grams
        }
    }

    var isMacro: Bool {
        switch self {
        case .carbs,
             .fat,
             .fiber,
             .protein,
             .sugars:
            true
        }
    }

    var isMicro: Bool {
        switch self {
        case .carbs,
             .fat,
             .fiber,
             .protein,
             .sugars:
            false
        }
    }

    var isPrimary: Bool {
        switch self {
        case .carbs,
             .fat,
             .protein: true
        case .fiber,
             .sugars: false
        }
    }
}

enum FoodNutrition: Equatable {
    case per100([NutrientType: Decimal])
    case perServing([NutrientType: Decimal])
}

extension FoodNutrition {
    var isEmpty: Bool {
        switch self {
        case let .per100(values): values.isEmpty
        case let .perServing(values): values.isEmpty
        }
    }

    var isNotEmpty: Bool {
        !isEmpty
    }
}

struct FoodItemDetailed: Identifiable, Equatable {
    let id: UUID
    let name: String
    let standardName: String?
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

    let tags: [String]?

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
            lhs.tags == rhs.tags &&
            lhs.source == rhs.source
    }

    init(
        id: UUID? = nil,
        name: String,
        nutritionPer100: [NutrientType: Decimal],
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
        standardName: String? = nil,
        tags: [String]? = nil,
        source: FoodItemSource
    ) {
        self.id = id ?? UUID()
        self.name = name
        self.standardName = standardName
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
        self.tags = tags
        self.source = source
    }

    init(
        id: UUID? = nil,
        name: String,
        nutritionPerServing: [NutrientType: Decimal],
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
        standardName: String? = nil,
        tags: [String]? = nil,
        source: FoodItemSource
    ) {
        self.id = id ?? UUID()
        self.name = name
        self.standardName = standardName
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
        self.tags = tags
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

    /// Calculates calories from macronutrients using standard conversion factors:
    /// - Carbs: 4 kcal/g
    /// - Protein: 4 kcal/g
    /// - Fat: 9 kcal/g
    private func calculateCaloriesFromMacros(carbs: Decimal?, protein: Decimal?, fat: Decimal?) -> Decimal {
        let carbCals = (carbs ?? 0) * 4
        let proteinCals = (protein ?? 0) * 4
        let fatCals = (fat ?? 0) * 9
        return carbCals + proteinCals + fatCals
    }

    func nutrientInPortion(_ nutrient: NutrientType, portion: Decimal) -> Decimal? {
        guard case let .per100(per100) = nutrition else { return nil }
        guard let nutrientPer100 = per100[nutrient] else { return nil }
        return nutrientPer100 / 100 * portion
    }

    func carbsInPortion(portion: Decimal) -> Decimal? {
        nutrientInPortion(.carbs, portion: portion)
    }

    func fatInPortion(portion: Decimal) -> Decimal? {
        nutrientInPortion(.fat, portion: portion)
    }

    func proteinInPortion(portion: Decimal) -> Decimal? {
        nutrientInPortion(.protein, portion: portion)
    }

    func fiberInPortion(portion: Decimal) -> Decimal? {
        nutrientInPortion(.fiber, portion: portion)
    }

    func sugarsInPortion(portion: Decimal) -> Decimal? {
        nutrientInPortion(.sugars, portion: portion)
    }

    func caloriesInPortion(portion: Decimal) -> Decimal? {
        guard case .per100 = nutrition else { return nil }

        return calculateCaloriesFromMacros(
            carbs: carbsInPortion(portion: portion),
            protein: proteinInPortion(portion: portion),
            fat: fatInPortion(portion: portion)
        )
    }

    // MARK: - Per serving calculations

    func nutrientInServings(_ nutrient: NutrientType, multiplier: Decimal) -> Decimal? {
        guard case let .perServing(perServing) = nutrition else { return nil }
        guard let nutrientPerServing = perServing[nutrient] else { return nil }
        return nutrientPerServing * multiplier
    }

    func carbsInServings(multiplier: Decimal) -> Decimal? {
        nutrientInServings(.carbs, multiplier: multiplier)
    }

    func fatInServings(multiplier: Decimal) -> Decimal? {
        nutrientInServings(.fat, multiplier: multiplier)
    }

    func proteinInServings(multiplier: Decimal) -> Decimal? {
        nutrientInServings(.protein, multiplier: multiplier)
    }

    func fiberInServings(multiplier: Decimal) -> Decimal? {
        nutrientInServings(.fiber, multiplier: multiplier)
    }

    func sugarsInServings(multiplier: Decimal) -> Decimal? {
        nutrientInServings(.sugars, multiplier: multiplier)
    }

    func caloriesInServings(multiplier: Decimal) -> Decimal? {
        guard case .perServing = nutrition else { return nil }

        return calculateCaloriesFromMacros(
            carbs: carbsInServings(multiplier: multiplier),
            protein: proteinInServings(multiplier: multiplier),
            fat: fatInServings(multiplier: multiplier)
        )
    }

    func nutrientInThisPortion(_ nutrient: NutrientType) -> Decimal? {
        switch nutrition {
        case .per100:
            guard let portion = portionSize else { return nil }
            return nutrientInPortion(nutrient, portion: portion)
        case .perServing:
            guard let multiplier = servingsMultiplier else { return nil }
            return nutrientInServings(nutrient, multiplier: multiplier)
        }
    }

    func nutrient(_ nutrient: NutrientType, forPortion portion: Decimal) -> Decimal {
        switch nutrition {
        case .per100:
            return nutrientInPortion(nutrient, portion: portion) ?? 0
        case .perServing:
            return nutrientInServings(nutrient, multiplier: portion) ?? 0
        }
    }

    func calories(forPortion portion: Decimal) -> Decimal {
        switch nutrition {
        case .per100:
            return caloriesInPortion(portion: portion) ?? 0
        case .perServing:
            return caloriesInServings(multiplier: portion) ?? 0
        }
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
                tags: tags,
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
                tags: tags,
                source: source
            )
        }
    }

    func withImageURL(_ newImageURL: String?) -> FoodItemDetailed {
        switch nutrition {
        case let .per100(nutritionValues):
            return FoodItemDetailed(
                id: id,
                name: name,
                nutritionPer100: nutritionValues,
                portionSize: portionSize ?? 100,
                confidence: confidence,
                brand: brand,
                standardServing: standardServing,
                standardServingSize: standardServingSize,
                units: units,
                preparationMethod: preparationMethod,
                visualCues: visualCues,
                glycemicIndex: glycemicIndex,
                assessmentNotes: assessmentNotes,
                imageURL: newImageURL,
                standardName: standardName,
                tags: tags,
                source: source
            )
        case let .perServing(nutritionValues):
            return FoodItemDetailed(
                id: id,
                name: name,
                nutritionPerServing: nutritionValues,
                servingsMultiplier: servingsMultiplier ?? 1,
                confidence: confidence,
                brand: brand,
                standardServing: standardServing,
                standardServingSize: standardServingSize,
                units: units,
                preparationMethod: preparationMethod,
                visualCues: visualCues,
                glycemicIndex: glycemicIndex,
                assessmentNotes: assessmentNotes,
                imageURL: newImageURL,
                standardName: standardName,
                tags: tags,
                source: source
            )
        }
    }

    func withTags(_ newTags: [String]?) -> FoodItemDetailed {
        switch nutrition {
        case let .per100(nutritionValues):
            return FoodItemDetailed(
                id: id,
                name: name,
                nutritionPer100: nutritionValues,
                portionSize: portionSize ?? 100,
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
                standardName: standardName,
                tags: newTags,
                source: source
            )
        case let .perServing(nutritionValues):
            return FoodItemDetailed(
                id: id,
                name: name,
                nutritionPerServing: nutritionValues,
                servingsMultiplier: servingsMultiplier ?? 1,
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
                standardName: standardName,
                tags: newTags,
                source: source
            )
        }
    }
}
