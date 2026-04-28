import Foundation

enum NutrientType: String, Equatable, Identifiable, CaseIterable {
    case carbs
    case protein
    case fat
    case fiber
    case sugars

    var id: NutrientType { self }
}

typealias NutritionValues = [NutrientType: Decimal]

struct AggregatedNutrition {
    let macros: NutritionValues
    let micros: [MicroNutrient: Decimal]

    func value(for macro: NutrientType) -> Decimal {
        macros[macro] ?? 0
    }

    func value(for micro: MicroNutrient) -> Decimal {
        micros[micro] ?? 0
    }
}

extension AggregatedNutrition {
    var macroDisplay: [DisplayNutrient] {
        NutrientType.allCases.compactMap { type in
            guard let value = macros[type], value > 0 || type.isPrimary else { return nil }

            return DisplayNutrient(
                name: type.localizedLabel,
                value: value,
                unit: "g",
                isPrimary: type.isPrimary
            )
        }
    }

    var microDisplay: [DisplayNutrient] {
        micros
            .filter { $0.value > 0 }
            .sorted { $0.key.displayName < $1.key.displayName }
            .map { key, value in
                DisplayNutrient(
                    name: key.displayName,
                    value: value,
                    unit: key.unit,
                    isPrimary: false
                )
            }
    }
}

struct DisplayNutrient: Identifiable {
    let id = UUID()
    let name: String
    let value: Decimal
    let unit: String
    let isPrimary: Bool
}

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
    case aiRecipe
    case aiText
    case search
    case barcode
    case manual
    case database

    var isAI: Bool {
        switch self {
        case .aiMenu,
             .aiPhoto,
             .aiRecipe,
             .aiText: true
        default: false
        }
    }
}

extension FoodItemSource {
    var icon: String {
        switch self {
        case .aiPhoto:
            return "camera.viewfinder"
        case .aiMenu:
            return "list.clipboard"
        case .aiRecipe:
            return "book.fill"
        case .aiText:
            return "character.bubble"
        case .search:
            return "magnifyingglass.circle"
        case .barcode:
            return "barcode.viewfinder"
        case .manual:
            return "square.and.pencil"
        case .database:
            return "archivebox.fill"
        }
    }
}

enum ConfidenceLevel: String, Codable, Identifiable, CaseIterable {
    case high
    case medium
    case low

    var id: ConfidenceLevel { self }
}

extension NutrientType {
    var localizedLabel: String {
        switch self {
        case .carbs: NSLocalizedString("Carbs", comment: "")
        case .fat: NSLocalizedString("Fat", comment: "")
        case .fiber: NSLocalizedString("Fiber", comment: "")
        case .protein: NSLocalizedString("Protein", comment: "")
        case .sugars: NSLocalizedString("Sugars", comment: "")
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
    case per100(values: [NutrientType: Decimal], portionSize: Decimal)
    case perServing(values: [NutrientType: Decimal], servingsMultiplier: Decimal)
}

extension FoodNutrition {
    var values: NutritionValues {
        switch self {
        case let .per100(v, _): v
        case let .perServing(v, _): v
        }
    }

    var isEmpty: Bool { values.isEmpty }

    var isNotEmpty: Bool { !isEmpty }
}

extension NutritionValues {
    var calories: Decimal {
        ((self[.carbs] ?? 0) * 4) + ((self[.protein] ?? 0) * 4) + ((self[.fat] ?? 0) * 9)
    }
}

struct FoodItemDetailed: Identifiable, Equatable {
    let id: UUID
    let name: String
    let standardName: String?
    let confidence: ConfidenceLevel?
    let brand: String?
    let standardServing: String?
    let standardServingSize: Decimal?
    let units: MealUnits?
    let preparationMethod: String?
    let visualCues: String?
    let glycemicIndex: Decimal?

    let nutrition: FoodNutrition

    let micronutrients: [MicronutrientValue]

    let assessmentNotes: String?

    let imageURL: String?

    let tags: [String]?

    let source: FoodItemSource

    let deleted: Bool

    static func == (lhs: FoodItemDetailed, rhs: FoodItemDetailed) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.confidence == rhs.confidence &&
            lhs.brand == rhs.brand &&
            lhs.standardServing == rhs.standardServing &&
            lhs.standardServingSize == rhs.standardServingSize &&
            lhs.units == rhs.units &&
            lhs.preparationMethod == rhs.preparationMethod &&
            lhs.visualCues == rhs.visualCues &&
            lhs.glycemicIndex == rhs.glycemicIndex &&
            lhs.standardName == rhs.standardName &&
            lhs.nutrition == rhs.nutrition &&
            lhs.micronutrients == rhs.micronutrients &&
            lhs.assessmentNotes == rhs.assessmentNotes &&
            lhs.imageURL == rhs.imageURL &&
            lhs.tags == rhs.tags &&
            lhs.source == rhs.source &&
            lhs.deleted == rhs.deleted
    }

    init(
        id: UUID? = nil,
        name: String,
        nutrition: FoodNutrition,
        micronutrients: [MicronutrientValue] = [],
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
        source: FoodItemSource,
        deleted: Bool = false
    ) {
        self.id = id ?? UUID()
        self.name = name
        self.standardName = standardName
        self.confidence = confidence
        self.brand = brand
        self.standardServing = standardServing
        self.standardServingSize = standardServingSize
        self.units = units
        self.preparationMethod = preparationMethod
        self.visualCues = visualCues
        self.glycemicIndex = glycemicIndex
        self.nutrition = nutrition
        self.micronutrients = micronutrients
        self.assessmentNotes = assessmentNotes
        self.imageURL = imageURL
        self.tags = tags
        self.source = source
        self.deleted = deleted
    }
}

extension FoodItemDetailed {
    func nutrientInThisPortion(_ nutrient: NutrientType) -> Decimal? {
        switch nutrition {
        case let .per100(per100, portion):
            guard let nutrientPer100 = per100[nutrient] else { return nil }
            return nutrientPer100 / 100 * portion
        case let .perServing(perServing, multiplier):
            guard let nutrientPerServing = perServing[nutrient] else { return nil }
            return nutrientPerServing * multiplier
        }
    }

    var caloriesInThisPortion: Decimal {
        switch nutrition {
        case let .per100(per100, portionSize):
            return per100.calories / 100 * portionSize
        case let .perServing(perServing, multiplier):
            return perServing.calories * multiplier
        }
    }

    func copy(
        id: UUID? = nil,
        name: String? = nil,
        nutrition: FoodNutrition? = nil,
        micronutrients: [MicronutrientValue]? = nil,
        confidence: ConfidenceLevel?? = nil,
        brand: String?? = nil,
        standardServing: String?? = nil,
        standardServingSize: Decimal?? = nil,
        units: MealUnits?? = nil,
        preparationMethod: String?? = nil,
        visualCues: String?? = nil,
        glycemicIndex: Decimal?? = nil,
        assessmentNotes: String?? = nil,
        imageURL: String?? = nil,
        standardName: String?? = nil,
        tags: [String]?? = nil,
        source: FoodItemSource? = nil,
        deleted: Bool? = nil
    ) -> FoodItemDetailed {
        FoodItemDetailed(
            id: id ?? self.id,
            name: name ?? self.name,
            nutrition: nutrition ?? self.nutrition,
            micronutrients: micronutrients ?? self.micronutrients,
            confidence: confidence ?? self.confidence,
            brand: brand ?? self.brand,
            standardServing: standardServing ?? self.standardServing,
            standardServingSize: standardServingSize ?? self.standardServingSize,
            units: units ?? self.units,
            preparationMethod: preparationMethod ?? self.preparationMethod,
            visualCues: visualCues ?? self.visualCues,
            glycemicIndex: glycemicIndex ?? self.glycemicIndex,
            assessmentNotes: assessmentNotes ?? self.assessmentNotes,
            imageURL: imageURL ?? self.imageURL,
            standardName: standardName ?? self.standardName,
            tags: tags ?? self.tags,
            source: source ?? self.source,
            deleted: deleted ?? self.deleted
        )
    }

    var isPerServing: Bool {
        if case .perServing = nutrition { return true }
        return false
    }

    var hasNutritionValues: Bool {
        nutrition.isNotEmpty
    }

    // used to display nutrition previews while changing the portion size with the slider, before saving the changes in the food-editing views
    func nutrientInPortionOrServings(_ nutrient: NutrientType, portionOrMultiplier: Decimal) -> Decimal? {
        switch nutrition {
        case let .per100(per100, _):
            guard let nutrientPer100 = per100[nutrient] else { return nil }
            return nutrientPer100 / 100 * portionOrMultiplier
        case let .perServing(perServing, _):
            guard let nutrientPerServing = perServing[nutrient] else { return nil }
            return nutrientPerServing * portionOrMultiplier
        }
    }

    // used to display nutrition previews while changing the portion size with the slider, before saving the changes in the food-editing views
    func caloriesInPortionOrServings(portionOrMultiplier: Decimal) -> Decimal? {
        switch nutrition {
        case let .per100(per100, _):
            return per100.calories / 100 * portionOrMultiplier
        case let .perServing(perServing, _):
            return perServing.calories * portionOrMultiplier
        }
    }

    // used to display the value in the UI
    var portionSizeOrMultiplier: Decimal {
        switch nutrition {
        case let .per100(_, portionSize): portionSize
        case let .perServing(_, multiplier): multiplier
        }
    }

    // a helper for updating a food item from UI - we have a single slider for both cases
    func withPortionSizeOrMultiplier(_ portionOrMultiplier: Decimal) -> FoodItemDetailed {
        let newNutrition: FoodNutrition =
            switch nutrition {
        case let .per100(per100, _):
            .per100(values: per100, portionSize: portionOrMultiplier)
        case let .perServing(perServing, _):
            .perServing(values: perServing, servingsMultiplier: portionOrMultiplier)
        }
        return copy(
            nutrition: newNutrition
        )
    }

    func micronutrientInThisPortion(_ nutrient: MicroNutrient) -> Decimal? {
        guard let value = micronutrients.first(where: { $0.substance == nutrient }) else {
            return nil
        }

        switch nutrition {
        case let .per100(_, portion):
            return value.amountPer100 / 100 * portion

        case let .perServing(_, multiplier):
            return value.amount * multiplier
        }
    }

    func micronutrientInPortionOrServings(
        _ nutrient: MicroNutrient,
        portionOrMultiplier: Decimal
    ) -> Decimal? {
        guard let value = micronutrients.first(where: { $0.substance == nutrient }) else {
            return nil
        }

        switch nutrition {
        case .per100:
            return value.amountPer100 / 100 * portionOrMultiplier

        case .perServing:
            return value.amount * portionOrMultiplier
        }
    }

    var micronutrientTotals: [MicroNutrient: Decimal] {
        Dictionary(
            uniqueKeysWithValues: micronutrients.map {
                ($0.substance, micronutrientInThisPortion($0.substance) ?? 0)
            }
        )
    }

    /*
     func micronutrient(_ nutrient: MicroNutrient) -> Decimal? {
         micronutrients?[nutrient]
     }

     var micronutrientList: [MicronutrientValue] {
         (micronutrients ?? [:]).map {
             MicronutrientValue(
                 substance: $0.key,
                 amount: $0.value,
                 amountPer100: $0.value
             )
         }
         .sorted { $0.name < $1.name }
     }*/
}

/*
 struct FullNutrition {
     let macros: FoodNutrition
     let micros: [MicroNutrient: Decimal]
 }
 */
