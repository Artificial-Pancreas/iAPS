import Foundation

protocol AnalysisServiceBase {}

protocol ImageAnalysisService: Sendable, AnalysisServiceBase {
    func analyzeImage(
        prompt: String,
        images: [String],
        telemetryCallback: (@Sendable(String) -> Void)?
    ) async throws -> FoodItemGroup
}

protocol TextAnalysisService: Sendable, AnalysisServiceBase {
    func analyzeText(
        prompt: String,
        telemetryCallback: (@Sendable(String) -> Void)?
    ) async throws -> FoodItemGroup
}

protocol BarcodeAnalysisService: Sendable, AnalysisServiceBase {
    func analyzeBarcode(
        barcode: String,
        telemetryCallback: (@Sendable(String) -> Void)?
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
    func analyzeImage(
        prompt: String,
        images: [String],
        telemetryCallback: (@Sendable(String) -> Void)?
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
        case .recipePhoto: .aiRecipe
        case nil: .aiPhoto
        }
        return AIAnalysisResult.createFoodItemGroup(
            result: result,
            source: source
        )
    }
}

extension AIAnalysisService: TextAnalysisService {
    func analyzeText(
        prompt: String,
        telemetryCallback: (@Sendable(String) -> Void)?
    ) async throws -> FoodItemGroup {
        let response = try await client.executeQuery(
            prompt: prompt,
            images: [],
            telemetryCallback: telemetryCallback
        )

        let result = try decode(response, as: AIAnalysisResult.self)
        return AIAnalysisResult.createFoodItemGroup(
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
            debug(.service, "Failed to convert cleaned AI JSON string to Data")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        do {
            return try JSONDecoder().decode(type, from: jsonData)
        } catch {
            debug(.service, "Failed to decode AI response JSON: \(error): \(String(decoding: jsonData, as: UTF8.self))")
            throw AIFoodAnalysisError.responseParsingFailed
        }
    }
}
