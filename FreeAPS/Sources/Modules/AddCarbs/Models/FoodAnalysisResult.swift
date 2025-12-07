import Foundation

/// Result from AI food analysis with detailed breakdown
struct FoodAnalysisResult: Identifiable, Equatable {
    let id = UUID()
    let imageType: ImageAnalysisType?
    let foodItemsDetailed: [AnalysedFoodItem]
    let briefDescription: String?
    let overallDescription: String?
//    let totalFoodPortions: Int?
//    let totalStandardServings: Double?
//    let servingsStandard: String?
//    let totalCarbohydrates: Double
//    let totalProtein: Double?
//    let totalFat: Double?
//    let totalFiber: Double?
//    let totalCalories: Double?
//    let portionAssessmentMethod: String?
    let diabetesConsiderations: String?
//    let visualAssessmentDetails: String?
    let notes: String?
    let source: FoodItemSource?
    var barcode: String? = nil
    var textQuery: String? = nil

    static func == (lhs: FoodAnalysisResult, rhs: FoodAnalysisResult) -> Bool {
        lhs.id == rhs.id
    }

    // Store original baseline servings for proper scaling calculations
//    let originalServings: Double

    // Advanced dosing fields (optional for backward compatibility)
//    let fatProteinUnits: String?
//    let netCarbsAdjustment: String?
//    let insulinTimingRecommendations: String?
//    let fpuDosingGuidance: String?
//    let exerciseConsiderations: String?
//    let absorptionTimeHours: Double?
//    let absorptionTimeReasoning: String?
//    let mealSizeImpact: String?
//    let individualizationFactors: String?
//    let safetyAlerts: String?

    // Legacy compatibility properties
    var foodItems: [String] {
        foodItemsDetailed.compactMap(\.name)
    }

//    var detailedDescription: String? {
//        overallDescription
//    }

//    var portionSize: String {
//        if foodItemsDetailed.count == 1 {
//            return foodItemsDetailed.first?.portionEstimate ?? "1 serving"
//        } else {
//            // Create concise food summary for multiple items (clean food names)
//            let foodNames = foodItemsDetailed.compactMap(\.name).map { name in
//                // Clean up food names by removing technical terms
//                cleanFoodName(name)
//            }
//            return foodNames.joined(separator: ", ")
//        }
//    }

    // Helper function to clean food names for display
    private func cleanFoodName(_ name: String) -> String {
        var cleaned = name

        // Remove common technical terms while preserving essential info
        let removals = [
            " Breast", " Fillet", " Thigh", " Florets", " Spears",
            " Cubes", " Medley", " Portion"
        ]

        for removal in removals {
            cleaned = cleaned.replacingOccurrences(of: removal, with: "")
        }

        // Capitalize first letter and trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? name : cleaned
    }

//    var servingSizeDescription: String {
//        if foodItemsDetailed.count == 1 {
//            return foodItemsDetailed.first?.portionEstimate ?? "1 serving"
//        } else {
//            // Return the same clean food names for "Based on" text
//            let foodNames = foodItemsDetailed.map { item in
//                cleanFoodName(item.name)
//            }
//            return foodNames.joined(separator: ", ")
//        }
//    }

//    var carbohydrates: Double {
//        totalCarbohydrates
//    }
//
//    var protein: Double? {
//        totalProtein
//    }
//
//    var fat: Double? {
//        totalFat
//    }
//
//    var calories: Double? {
//        totalCalories
//    }
//
//    var fiber: Double? {
//        totalFiber
//    }

//    var servings: Double {
//        foodItemsDetailed.reduce(0) { $0 + $1.servingMultiplier }
//    }

//    var analysisNotes: String? {
//        portionAssessmentMethod
//    }

    var totalCalories: Decimal {
        foodItemsDetailed.compactMap(\.caloriesInThisPortion).reduce(0, +)
    }

    var totalCarbs: Decimal {
        foodItemsDetailed.compactMap(\.carbsInThisPortion).reduce(0, +)
    }

    var totalFat: Decimal {
        foodItemsDetailed.compactMap(\.fatInThisPortion).reduce(0, +)
    }

    var totalProtein: Decimal {
        foodItemsDetailed.compactMap(\.proteinInThisPortion).reduce(0, +)
    }
}

extension FoodAnalysisResult: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let imageType: ImageAnalysisType? = try container
            .decodeIfPresent(ImageAnalysisType.self, forKey: .imageType) ?? .foodPhoto

        let foodItemsDetailed: [AnalysedFoodItem] = try container.decode([AnalysedFoodItem].self, forKey: .foodItemsDetailed)

        let briefDescription: String? = try container.decodeTrimmedIfPresent(forKey: .briefDescription)
        let overallDescription: String? = try container.decodeTrimmedIfPresent(forKey: .overallDescription)

//        let totalFoodPortions: Int? = try container.decodeIfPresent(Int.self, forKey: .totalFoodPortions)
//        let totalStandardServings: Double? = try container.decodeNumberIfPresent(forKey: .totalStandardServings)
//        let servingsStandard: String? = try container.decodeTrimmedIfPresent(forKey: .servingsStandard)

//        let totalCarbohydrates: Double = try container.decodeNumberIfPresent(forKey: .totalCarbohydrates) ??
//            foodItemsDetailed.map(\.carbohydrates).reduce(0, +)
//
//        let totalProtein: Double? = try container.decodeNumberIfPresent(forKey: .totalProtein) ??
//            foodItemsDetailed.compactMap(\.protein).reduce(0, +)
//
//        let totalFat: Double? = try container.decodeNumberIfPresent(forKey: .totalFat) ??
//            foodItemsDetailed.compactMap(\.fat).reduce(0, +)
//
//        let totalFiber: Double? = try container.decodeNumberIfPresent(forKey: .totalFiber) ??
//            foodItemsDetailed.compactMap(\.fiber).reduce(0, +)
//
//        let totalCalories: Double? = try container.decodeNumberIfPresent(forKey: .totalCalories) ??
//            foodItemsDetailed.compactMap(\.calories).reduce(0, +)

//        let portionAssessmentMethod: String? = try container.decodeTrimmedIfPresent(forKey: .portionAssessmentMethod)

        let diabetesConsiderations: String? = try container.decodeTrimmedIfPresent(forKey: .diabetesConsiderations)
//        let visualAssessmentDetails: String? = try container.decodeTrimmedIfPresent(forKey: .visualAssessmentDetails)
        let notes: String? = try container.decodeTrimmedIfPresent(forKey: .notes)

//        let fatProteinUnits: String? = try container.decodeTrimmedIfPresent(forKey: .fatProteinUnits)
//        let netCarbsAdjustment: String? = try container.decodeTrimmedIfPresent(forKey: .netCarbsAdjustment)
//        let insulinTimingRecommendations: String? = try container.decodeTrimmedIfPresent(forKey: .insulinTimingRecommendations)
//        let fpuDosingGuidance: String? = try container.decodeTrimmedIfPresent(forKey: .fpuDosingGuidance)
//        let exerciseConsiderations: String? = try container.decodeTrimmedIfPresent(forKey: .exerciseConsiderations)
//        let absorptionTimeHours: Double? = try container.decodeNumberIfPresent(forKey: .absorptionTimeHours)
//        let absorptionTimeReasoning: String? = try container.decodeTrimmedIfPresent(forKey: .absorptionTimeReasoning)
//        let mealSizeImpact: String? = try container.decodeTrimmedIfPresent(forKey: .mealSizeImpact)
//        let individualizationFactors: String? = try container.decodeTrimmedIfPresent(forKey: .individualizationFactors)
//        let safetyAlerts: String? = try container.decodeTrimmedIfPresent(forKey: .safetyAlerts)

        // Calculate original servings for proper scaling
//        let originalServings = foodItemsDetailed.map(\.servingMultiplier).reduce(0, +)

        self.imageType = imageType
        self.foodItemsDetailed = foodItemsDetailed
        self.briefDescription = briefDescription
        self.overallDescription = overallDescription
//            totalFoodPortions: totalFoodPortions,
//            totalStandardServings: totalStandardServings,
//            servingsStandard: servingsStandard,
//            totalCarbohydrates: totalCarbohydrates,
//            totalProtein: totalProtein,
//            totalFat: totalFat,
//            totalFiber: totalFiber,
//            totalCalories: totalCalories,
//            portionAssessmentMethod: portionAssessmentMethod,
        self.diabetesConsiderations = diabetesConsiderations
//            visualAssessmentDetails: visualAssessmentDetails,
        self.notes = notes
//            originalServings: originalServings,
//            fatProteinUnits: fatProteinUnits,
//            netCarbsAdjustment: netCarbsAdjustment,
//            insulinTimingRecommendations: insulinTimingRecommendations,
//            fpuDosingGuidance: fpuDosingGuidance,
//            exerciseConsiderations: exerciseConsiderations,
//            absorptionTimeHours: absorptionTimeHours,
//            absorptionTimeReasoning: absorptionTimeReasoning,
//            mealSizeImpact: mealSizeImpact,
//            individualizationFactors: individualizationFactors,
//            safetyAlerts: safetyAlerts
        source = imageType == .textSearch ? .aiText : .ai
    }

    // In FoodAnalysisResult
    private enum CodingKeys: String, CodingKey {
        case imageType = "image_type"
        case foodItemsDetailed = "food_items"
        case briefDescription = "brief_description"
        case overallDescription = "overall_description"
//        case totalFoodPortions = "total_food_portions"
//        case totalStandardServings = "total_standard_servings"
//        case servingsStandard = "serving_standard"
//        case totalCarbohydrates = "total_carbohydrates"
//        case totalProtein = "total_protein"
//        case totalFat = "total_fat"
//        case totalFiber = "total_fiber"
//        case totalCalories = "total_calories"
//        case portionAssessmentMethod = "portion_assessment_method"
        case diabetesConsiderations = "diabetes_considerations"
//        case visualAssessmentDetails = "visual_assessment_details"
        case notes // not present in schema; keep for backward-compat if needed

        // Advanced dosing / extras in schema
//        case fatProteinUnits = "fat_protein_units"
//        case netCarbsAdjustment = "net_carbs_adjustment"
//        case insulinTimingRecommendations = "insulin_timing_recommendations"
//        case fpuDosingGuidance = "fpu_dosing_guidance"
//        case exerciseConsiderations = "exercise_considerations"
//        case absorptionTimeHours = "absorption_time_hours"
//        case absorptionTimeReasoning = "absorption_time_reasoning"
//        case mealSizeImpact = "meal_size_impact"
//        case individualizationFactors = "individualization_factors"
//        case safetyAlerts = "safety_alerts"
    }
}

/// Confidence level for AI analysis
enum AIConfidenceLevel: String, JSON, Identifiable, CaseIterable {
    case high
    case medium
    case low

    var id: AIConfidenceLevel { self }
}

extension AIConfidenceLevel {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode numeric confidence first
        if let numeric = try? container.decode(Double.self) {
            if numeric >= 0.8 {
                self = .high
            } else if numeric >= 0.5 {
                self = .medium
            } else {
                self = .low
            }
            return
        }

        // Fallback to string-based confidence values
        if let stringValue = try? container.decode(String.self) {
            switch stringValue.lowercased() {
            case "high":
                self = .high
            case "medium":
                self = .medium
            case "low":
                self = .low
            default:
                // Attempt to parse numeric from string
                if let numericFromString = Double(stringValue) {
                    if numericFromString >= 0.8 {
                        self = .high
                    } else if numericFromString >= 0.5 {
                        self = .medium
                    } else {
                        self = .low
                    }
                } else {
                    self = .medium // Default confidence
                }
            }
            return
        }

        // Default if neither numeric nor string could be decoded
        self = .medium
    }
}

/// Type of image being analyzed
enum ImageAnalysisType: String, JSON, Identifiable, CaseIterable {
    case foodPhoto = "food_photo"
    case menuItem = "menu_item"
    case recipePhoto = "recipe_photo"
    case textSearch = "text_search"

    var id: ImageAnalysisType { self }
}

extension KeyedDecodingContainer {
    func decodeTrimmedNonEmpty(forKey key: Key) throws -> String {
        let raw = try decode(String.self, forKey: key)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected non-empty string after trimming."
            )
        }
        return trimmed
    }

    func decodeTrimmedIfPresent(forKey key: Key) throws -> String? {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func decodeNumber(forKey key: Key, ensuringNonNegative: Bool = true) throws -> Decimal {
        // Try Double directly
        if let double = try? decode(Decimal.self, forKey: key) {
            return ensuringNonNegative ? max(0, double) : double
        }
        // Try Int and convert
        if let intVal = try? decode(Int.self, forKey: key) {
            let converted = Decimal(intVal)
            return ensuringNonNegative ? max(0, converted) : converted
        }
        // Try String and convert
        if let stringVal = try? decode(String.self, forKey: key) {
            let trimmed = stringVal.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Decimal(from: trimmed) {
                return ensuringNonNegative ? max(0, parsed) : parsed
            }
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "String value for key \(key.stringValue) is not a valid Double: \(stringVal)"
            )
        }
        // If value is explicitly null or not present, surface a missing value error
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "No convertible numeric value found for key \(key.stringValue)"
            )
        )
    }

    /// Decode a numeric value if present. Accepts Double, Int, or String representations.
    /// Optionally clamps negatives to 0.
    func decodeNumberIfPresent(forKey key: Key, ensuringNonNegative: Bool = true) throws -> Decimal? {
        // If the key is not present at all, return nil early
        if contains(key) == false { return nil }

        if let double = try? decode(Decimal.self, forKey: key) {
            return ensuringNonNegative ? max(0, double) : double
        }
        if let intVal = try? decode(Int.self, forKey: key) {
            let converted = Decimal(intVal)
            return ensuringNonNegative ? max(0, converted) : converted
        }
        if let stringVal = try? decode(String.self, forKey: key) {
            let trimmed = stringVal.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Decimal(from: trimmed) {
                return ensuringNonNegative ? max(0, parsed) : parsed
            }
            return nil
        }
        return nil
    }
}

extension FoodAnalysisResult {
    private static var fields: [(FoodAnalysisResult.CodingKeys, Any)] {
        [
            //            .servingsStandard: "brief name/description of NUTRITION_AUTHORITY",
            (.briefDescription, "generate a SHORT UI TITLE describing the analyzed food; (language)"),
            (.diabetesConsiderations, "carb sources, GI impact (low/medium/high), timing considerations; (language)")
//            .insulinTimingRecommendations: "Meal type and pre-meal timing (minutes before eating)",
//            .absorptionTimeHours: "absorption hours between 2 and 6",
//            .absorptionTimeReasoning: "Brief timing calculation explanation",
//            .portionAssessmentMethod: "Explain in natural language how you estimated portion sizes using visual references like plate size, utensils, or other objects for scale. Describe your measurement process for each food item and explain how you converted visual portions to serving equivalents. Include your confidence level and what factors affected your accuracy."
        ]
    }

    static var schemaVisual: [(String, Any)] {
        let fields = [
            (.imageType, "string enum: food_photo or menu_item or recipe_photo"),
            (.foodItemsDetailed, AnalysedFoodItem.schemaVisual),
            //      (.visualAssessmentDetails, "Textures, colors, cooking evidence")
            (.overallDescription, "describe what you see on the photo; (language)")
        ] + self.fields

        return fields.map { key, value in
            (key.rawValue, value)
        }
    }

    static var schemaText: [(String, Any)] {
        let fields = [
            (.imageType, "string, always set to: text_search"),
            (.foodItemsDetailed, [AnalysedFoodItem.schemaText]),
            (.overallDescription, "describe what you perceived from the user input; (language)")
        ] + self.fields

        return fields.map { key, value in
            (key.rawValue, value)
        }
    }
}
