import Foundation

protocol AnalysisServiceBase {}

protocol ImageAnalysisService: Sendable, AnalysisServiceBase {
    var needAggressiveImageCompression: Bool { get }

    func analyzeImage(
        prompt: String,
        images: [String],
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup
}

protocol TextAnalysisService: Sendable, AnalysisServiceBase {
    func analyzeText(
        prompt: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup
}

protocol BarcodeAnalysisService: Sendable, AnalysisServiceBase {
    func analyzeBarcode(
        barcode: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup
}

struct AIAnalysisService {
    private let proto: AIProviderProtocol
    private let client: AIProviderClient

    init(_ proto: AIProviderProtocol) {
        self.proto = proto
        client = AIProviderClient(proto: proto)
    }

    static func create(for aiModel: AIModel, apiKey: String) -> AIAnalysisService {
        let proto: AIProviderProtocol = switch aiModel {
        case let .openAI(model): OpenAIProtocol(model: model, apiKey: apiKey)
        case let .gemini(model): GeminiProtocol(model: model, apiKey: apiKey)
        case let .claude(model): ClaudeProtocol(model: model, apiKey: apiKey)
        }
        return AIAnalysisService(proto)
    }
}

extension AIAnalysisService: ImageAnalysisService {
    var needAggressiveImageCompression: Bool { proto.needAggressiveImageCompression }

    func analyzeImage(
        prompt: String,
        images: [String],
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup {
        let response = try await client.executeQuery(
            prompt: prompt,
            images: images,
            telemetryCallback: telemetryCallback
        )

        let result = try decode(response, as: AIAnalysisResult.self)
        let source: FoodItemSource = switch result.imageType {
        case .foodPhoto: .aiPhoto
        case .menuPhoto: .aiMenu
        case .recipePhoto: .aiReceipe
        case nil: .aiPhoto
        }
        return fromAIAnalysis(
            result: result,
            source: source
        )
    }
}

extension AIAnalysisService: TextAnalysisService {
    func analyzeText(
        prompt: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup {
        let response = try await client.executeQuery(
            prompt: prompt,
            images: [],
            telemetryCallback: telemetryCallback
        )

        let result = try decode(response, as: AIAnalysisResult.self)
        return fromAIAnalysis(
            result: result,
            source: .aiText
        )
    }
}

extension AnalysisServiceBase {
    func decode<T: Decodable>(
        _ content: String,
        as type: T.Type
    ) throws -> T {
        // 1. Remove markdown fences and stray backticks
        var cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Remove UTF-8 BOM or invisible junk before first "{"
        if let braceIndex = cleanedContent.firstIndex(of: "{") {
            let prefix = cleanedContent[..<braceIndex]
            if prefix.contains(where: { !$0.isASCII }) {
                cleanedContent = String(cleanedContent[braceIndex...])
            }
        }

        // 3. Extract JSON substring between first "{" and last "}"
        let jsonString: String
        if let jsonStartRange = cleanedContent.range(of: "{"),
           let jsonEndRange = cleanedContent.range(of: "}", options: .backwards),
           jsonStartRange.lowerBound < jsonEndRange.upperBound
        {
            jsonString = String(cleanedContent[jsonStartRange.lowerBound ..< jsonEndRange.upperBound])
        } else {
            jsonString = cleanedContent
        }

        // 4. Fix common issue: remove trailing commas before }
        let fixedJson = jsonString.replacingOccurrences(
            of: ",\\s*}".replacingOccurrences(of: "\\", with: "\\\\"),
            with: "}"
        )

        // 5. Decode
        guard let jsonData = fixedJson.data(using: .utf8) else {
            print("❌ Failed to convert to Data. JSON was:\n\(fixedJson)")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: jsonData)

        } catch {
            print("❌ JSON decode error: \(error)")
            print("❌ JSON content:\n\(fixedJson)")
            throw AIFoodAnalysisError.responseParsingFailed
        }
    }
}

extension TextAnalysisService {
    func fromOpenFoodFactsProducts(
        products: [OpenFoodFactsProduct],
        confidence: ConfidenceLevel?,
        source: FoodItemSource
    ) -> FoodItemGroup {
        let items: [FoodItemDetailed] = products.map { item in
            if let servingQuantity = item.servingQuantity {
                FoodItemDetailed(
                    name: item.productName ?? "Product without name",
                    nutritionPer100: NutritionValues(
                        calories: item.nutriments.calories,
                        carbs: item.nutriments.carbohydrates,
                        fat: item.nutriments.fat,
                        fiber: item.nutriments.fiber,
                        protein: item.nutriments.proteins,
                        sugars: item.nutriments.sugars
                    ),
                    portionSize: servingQuantity,
                    confidence: confidence,
                    brand: item.brands,
                    standardServing: item.servingSize,
                    standardServingSize: item.servingQuantity,
                    units: MealUnits.grams,
                    imageURL: item.imageURL,
                    source: source
                )
            } else {
                FoodItemDetailed(
                    name: item.productName ?? "Product without name",
                    nutritionPerServing: NutritionValues(
                        calories: item.nutriments.calories,
                        carbs: item.nutriments.carbohydrates,
                        fat: item.nutriments.fat,
                        fiber: item.nutriments.fiber,
                        protein: item.nutriments.proteins,
                        sugars: item.nutriments.sugars
                    ),
                    servingsMultiplier: 1,
                    confidence: confidence,
                    brand: item.brands,
                    standardServing: item.servingSize,
                    standardServingSize: item.servingQuantity,
                    units: MealUnits.grams,
                    imageURL: item.imageURL,
                    source: source
                )
            }
        }

        return FoodItemGroup(
            foodItemsDetailed: items,
            briefDescription: nil,
            overallDescription: nil,
            diabetesConsiderations: nil,
            source: source
        )
    }

    func fromAIAnalysis(
        result: AIAnalysisResult,
        source: FoodItemSource
    ) -> FoodItemGroup {
        let items: [FoodItemDetailed] = result.foodItemsDetailed.map { item in
            let confidence: ConfidenceLevel? = switch item.confidence {
            case .high: .high
            case .medium: .medium
            case .low: .low
            case nil: nil
            }
            return FoodItemDetailed(
                name: item.name,
                nutritionPer100: NutritionValues(
                    calories: item.caloriesPer100,
                    carbs: item.carbsPer100,
                    fat: item.fatPer100,
                    fiber: item.fiberPer100,
                    protein: item.proteinPer100,
                    sugars: item.sugarsPer100,
                ),
                portionSize: item.portionEstimateSize ?? 100,
                confidence: confidence,
                brand: item.brand,
                standardServing: item.standardServing,
                standardServingSize: item.standardServingSize,
                units: item.units,
                preparationMethod: item.preparationMethod,
                visualCues: item.visualCues,
                glycemicIndex: item.glycemicIndex,
                assessmentNotes: item.assessmentNotes,
                imageURL: nil,
                standardName: item.standardName,
                source: source
            )
        }

        return FoodItemGroup(
            foodItemsDetailed: items,
            briefDescription: result.briefDescription,
            overallDescription: result.overallDescription,
            diabetesConsiderations: result.diabetesConsiderations,
            source: source
        )
    }
}

// MARK: - AI response

enum AIConfidenceLevel: String, JSON {
    case high
    case medium
    case low
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
    case menuPhoto = "menu_photo"
    case recipePhoto = "recipe_photo"

    var id: ImageAnalysisType { self }
}

struct AnalysiedFoodItem: Identifiable {
    let id = UUID()
    let name: String
    let standardName: String?
    let confidence: AIConfidenceLevel?
    let brand: String?
    let portionEstimateSize: Decimal?
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
}

extension AnalysiedFoodItem: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let name = try container.decodeTrimmedIfPresent(forKey: .name) ?? "Food item"
        let standardName = try container.decodeTrimmedIfPresent(forKey: .standardName)
        let confidence: AIConfidenceLevel = try container.decode(AIConfidenceLevel.self, forKey: .confidence)
        let brand = try container.decodeTrimmedIfPresent(forKey: .brand)
        let standardServing = try container.decodeTrimmedIfPresent(forKey: .standardServing)
        let standardServingSize = try container.decodeNumberIfPresent(forKey: .standardServingSize)
        let portionEstimateSize = try container.decodeNumberIfPresent(forKey: .portionEstimateSize) ?? standardServingSize
        let units = try container.decodeIfPresent(MealUnits.self, forKey: .units) ?? .grams
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
        self.standardName = standardName
        self.confidence = confidence
        self.brand = brand
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
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case standardName = "standard_name"
        case confidence
        case brand
        case portionEstimateSize = "portion_estimate_size"
        case standardServing = "standard_serving"
        case standardServingSize = "standard_serving_size"
        case units
        case preparationMethod = "preparation_method"
        case visualCues = "visual_cues"
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

extension AnalysiedFoodItem {
    private static var fields: [(AnalysiedFoodItem.CodingKeys, Any)] {
        [
            (.name, "string, required; specific food name; (language)"),
            (
                .standardName,
                "string; concise image-search query for this product. Branded/menu item: include the brand + product name. Generic food: use only the common product name. Use only nouns, plus an optional color. Do not use any other adjectives. Never include rawness, doneness, peel/skin state, serving style, cut form, or texture."
            ),
            (.confidence, "decimal 0 to 1; required; confidence for this item"),
            (.units, "string enum; one of: 'grams' or 'milliliters'; as appropriate for this meal; do NOT translate;"),
            (.carbsPer100, "decimal, grams of available / digestible carbohydrates per 100 grams or milliliters"),
            (.fatPer100, "decimal, grams of fat per 100 grams or milliliters"),
            (.fiberPer100, "decimal, grams of fiber per 100 grams or milliliters"),
            (.proteinPer100, "decimal, grams of protein per 100 grams or milliliters"),
            (.sugarsPer100, "decimal, grams of sugars per 100 grams or milliliters"),
            (.portionEstimateSize, "decimal, exact size of the identified portion; in grams or milliliters; do not include unit"),
            (
                .standardServingSize,
                "decimal, the identified standard serving size in grams or milliliters, if available; do not include unit"
            ),
            (
                .standardServing,
                "description of the identified standard serving, if available; if natural description is available - do NOT add size in grams/milliliters; (language)"
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

struct AIAnalysisResult: Identifiable, Equatable {
    let id = UUID()
    let imageType: ImageAnalysisType?
    let foodItemsDetailed: [AnalysiedFoodItem]
    let briefDescription: String?
    let overallDescription: String?
    let diabetesConsiderations: String?

    static func == (lhs: AIAnalysisResult, rhs: AIAnalysisResult) -> Bool {
        lhs.id == rhs.id
    }
}

extension AIAnalysisResult: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let imageType: ImageAnalysisType? = try container
            .decodeIfPresent(ImageAnalysisType.self, forKey: .imageType) ?? .foodPhoto

        let foodItemsDetailed: [AnalysiedFoodItem] = try container
            .decode([AnalysiedFoodItem].self, forKey: .foodItemsDetailed)

        let briefDescription: String? = try container.decodeTrimmedIfPresent(forKey: .briefDescription)
        let overallDescription: String? = try container.decodeTrimmedIfPresent(forKey: .overallDescription)

        let diabetesConsiderations: String? = try container.decodeTrimmedIfPresent(forKey: .diabetesConsiderations)

        self.imageType = imageType
        self.foodItemsDetailed = foodItemsDetailed
        self.briefDescription = briefDescription
        self.overallDescription = overallDescription
        self.diabetesConsiderations = diabetesConsiderations
    }

    private enum CodingKeys: String, CodingKey {
        case imageType = "image_type"
        case foodItemsDetailed = "food_items"
        case briefDescription = "brief_description"
        case overallDescription = "overall_description"
        case diabetesConsiderations = "diabetes_considerations"
    }
}

extension AIAnalysisResult {
    private static var fields: [(AIAnalysisResult.CodingKeys, Any)] {
        [
            (.briefDescription, "generate a SHORT UI TITLE describing the analyzed food; (language)"),
            (.diabetesConsiderations, "carb sources, GI impact (low/medium/high), timing considerations; (language)")
        ]
    }

    static var schemaVisual: [(String, Any)] {
        let fields = [
            (.imageType, "string enum: food_photo or menu_photo or recipe_photo"),
            (.foodItemsDetailed, AnalysiedFoodItem.schemaVisual),
            (.overallDescription, "describe what you see on the photo; (language)")
        ] + self.fields

        return fields.map { key, value in
            (key.rawValue, value)
        }
    }

    static var schemaText: [(String, Any)] {
        let fields = [
            (.foodItemsDetailed, [AnalysiedFoodItem.schemaText]),
            (.overallDescription, "describe what you perceived from the user input; (language)")
        ] + self.fields

        return fields.map { key, value in
            (key.rawValue, value)
        }
    }
}

// MARK: decoding helpers

private extension KeyedDecodingContainer {
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
