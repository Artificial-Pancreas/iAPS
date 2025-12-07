import Foundation

protocol AnalysisServiceBase {}

protocol ImageAnalysisService: Sendable, AnalysisServiceBase {
    var needAggressiveImageCompression: Bool { get }

    func analyzeImage(
        prompt: String,
        images: [String],
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult
}

protocol TextAnalysisService: Sendable, AnalysisServiceBase {
    func analyzeText(
        prompt: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult
}

protocol BarcodeAnalysisService: Sendable, AnalysisServiceBase {
    func analyzeBarcode(
        barcode: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult
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
    ) async throws -> FoodAnalysisResult {
        let response = try await client.executeQuery(
            prompt: prompt,
            images: images,
            telemetryCallback: telemetryCallback
        )

        return try decode(response, as: FoodAnalysisResult.self)
    }
}

extension AIAnalysisService: TextAnalysisService {
    func analyzeText(
        prompt: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult {
        let response = try await client.executeQuery(
            prompt: prompt,
            images: [],
            telemetryCallback: telemetryCallback
        )

        return try decode(response, as: FoodAnalysisResult.self)
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
        confidence: AIConfidenceLevel?,
        source: FoodItemSource
    ) -> FoodAnalysisResult {
        let items: [AnalysedFoodItem] = products.map { item in
            AnalysedFoodItem(
                name: item.productName ?? "Product without name",
                confidence: confidence,
                brand: item.brands,
                portionEstimate: item.servingSize,
                portionEstimateSize: item.servingQuantity,
                standardServing: item.servingSize,
                standardServingSize: item.servingQuantity,
                units: MealUnits.grams,
                caloriesPer100: item.nutriments.calories,
                carbsPer100: item.nutriments.carbohydrates,
                fatPer100: item.nutriments.fat,
                fiberPer100: item.nutriments.fiber,
                proteinPer100: item.nutriments.proteins,
                sugarsPer100: item.nutriments.sugars,
                imageURL: item.imageURL,
                imageFrontURL: item.imageFrontURL,
                source: source
            )
        }

        return FoodAnalysisResult(
            imageType: nil,
            foodItemsDetailed: items,
            briefDescription: nil,
            overallDescription: nil,
//            servingsStandard: nil,
//            portionAssessmentMethod: nil,
            diabetesConsiderations: nil,
//            visualAssessmentDetails: nil,
            notes: nil,
//            absorptionTimeHours: nil,
//            absorptionTimeReasoning: nil,
//            mealSizeImpact: nil,
//            safetyAlerts: nil
            source: source
        )
    }
}
