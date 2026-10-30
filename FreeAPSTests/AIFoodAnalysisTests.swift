@testable import FreeAPS
import UIKit
import XCTest

/// Tests for the AI food analysis pipeline: the response schema sent to the providers (offline),
/// and real requests against each configured provider (integration, skipped without keys).
///
/// Integration setup, none of it committed:
/// Every setting below is read from the environment first, then from `NAME=value` lines in a
/// `.temp/ai-tokens.env` file at the repository root (gitignored):
/// - API keys: `IAPS_AI_TEST_CLAUDE_KEY`, `IAPS_AI_TEST_GEMINI_KEY`, `IAPS_AI_TEST_OPENAI_KEY`.
///   A provider without a key is skipped.
/// - Photo: `IAPS_AI_TEST_PHOTO` (path), default `.temp/ai-test-photo.jpg` at the repository root.
/// - Models: `IAPS_AI_TEST_MODELS` = `default` (each provider's default model, the default),
///   `all` (every non-legacy model), or a comma-separated list of serialized models such as
///   `gemini/gemini-3.8-flash,claude/claude-haiku-5-5`.
final class AIFoodAnalysisTests: XCTestCase {
    // MARK: - Response schema (offline)

    func testStrictSchemaRequiresEveryPropertyAndAllowsNullForOptionalOnes() throws {
        let schema = try jsonObject(
            AIResponseSchema(object: AIAnalysisResult.schemaVisual, languageInstruction: "in English")
                .jsonSchema(dialect: .strict)
        )

        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertEqual(Set(required), Set(properties.keys), "strict mode lists every property as required")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)

        let imageType = try XCTUnwrap(properties["image_type"] as? [String: Any])
        XCTAssertEqual(imageType["type"] as? String, "string", "a required enum is a plain string")
        XCTAssertEqual(imageType["enum"] as? [String], ImageAnalysisType.allCases.map(\.rawValue))

        let overall = try XCTUnwrap(properties["overall_description"] as? [String: Any])
        XCTAssertEqual(overall["type"] as? [String], ["string", "null"], "an optional property allows null")
        XCTAssertEqual(overall["description"] as? String, "describe what you see on the photo; in English")

        let items = try XCTUnwrap(properties["food_items"] as? [String: Any])
        XCTAssertEqual(items["type"] as? String, "array")
        let item = try XCTUnwrap(items["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(item["properties"] as? [String: Any])
        let itemRequired = try XCTUnwrap(item["required"] as? [String])
        XCTAssertEqual(Set(itemRequired), Set(itemProperties.keys))
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        XCTAssertEqual((itemProperties["name"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual((itemProperties["carbs_per_100"] as? [String: Any])?["type"] as? [String], ["number", "null"])
        XCTAssertEqual((itemProperties["units"] as? [String: Any])?["enum"] as? [String], ["grams", "milliliters"])
        XCTAssertNotNil(itemProperties[MicroNutrient.allCases[0].codingKey], "micronutrients are part of the schema")
    }

    func testLenientSchemaListsOnlyRequiredProperties() throws {
        let schema = try jsonObject(
            AIResponseSchema(object: AIAnalysisResult.schemaText, languageInstruction: "in English")
                .jsonSchema(dialect: .lenient)
        )

        XCTAssertEqual(schema["required"] as? [String], ["food_items"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNil(properties["image_type"], "text analysis has no image type")
        XCTAssertEqual((properties["overall_description"] as? [String: Any])?["type"] as? String, "string")

        let item = try XCTUnwrap((properties["food_items"] as? [String: Any])?["items"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(item["required"] as? [String])), ["name", "confidence", "units"])
        XCTAssertEqual(
            (try XCTUnwrap(item["properties"] as? [String: Any])["carbs_per_100"] as? [String: Any])?["type"] as? String,
            "number"
        )
    }

    func testSerializedSchemaKeepsDefinitionOrderAndSurvivesEncoding() throws {
        let schema = AIResponseSchema(object: AIAnalysisResult.schemaVisual, languageInstruction: "in English")
            .jsonSchema(dialect: .lenient)
        let text = schema.serialized()
        let positions = try ["\"image_type\"", "\"food_items\"", "\"overall_description\"", "\"brief_description\""]
            .map { try XCTUnwrap(text.range(of: $0)?.lowerBound) }
        XCTAssertEqual(positions, positions.sorted(), "properties must be serialized in definition order")
        XCTAssertTrue(text.contains("\"description\":\"describe what you see on the photo; in English\""))

        struct Body: Encodable {
            let model: String
            let schema: OrderedJSON
        }
        let ordered = OrderedJSON(schema)
        let data = try OrderedJSON.encode(Body(model: "m", schema: ordered), splicing: [ordered])
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decoded["model"] as? String, "m")
        XCTAssertEqual((decoded["schema"] as? [String: Any])?["type"] as? String, "object", "the placeholder was replaced")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("ordered-json:"))
    }

    func testPromptExampleRendersFoodItemsAsArray() throws {
        let prompt = try AIPrompts.getAnalysisPrompt(.query("banana"), responseSchema: AIAnalysisResult.schemaText)
        XCTAssertTrue(prompt.text.contains("\"food_items\": [\n"), "the example object must show food_items as an array")
        XCTAssertFalse(prompt.text.contains("(language)"), "the language placeholder is substituted")
        XCTAssertFalse(prompt.responseSchema.languageInstruction.isEmpty)
    }

    // MARK: - Live providers (integration)

    func testPhotoAnalysisOnConfiguredProviders() async throws {
        let models = try modelsUnderTest()
        let photo = try samplePhoto()
        let base64 = try await ImageCompression.getImageBase64(for: photo, maxSize: 1024)
        let prompt = try AIPrompts.getAnalysisPrompt(.image(photo, nil), responseSchema: AIAnalysisResult.schemaVisual)

        for (model, apiKey) in models {
            await run(model) {
                try await AIAnalysisService.create(for: model, apiKey: apiKey)
                    .analyzeImage(prompt: prompt, images: [base64], telemetryCallback: nil)
            }
        }
    }

    func testTextAnalysisOnConfiguredProviders() async throws {
        let models = try modelsUnderTest()
        let prompt = try AIPrompts.getAnalysisPrompt(
            .query("one medium banana and three small pears"),
            responseSchema: AIAnalysisResult.schemaText
        )

        for (model, apiKey) in models {
            await run(model) {
                try await AIAnalysisService.create(for: model, apiKey: apiKey)
                    .analyzeText(prompt: prompt, telemetryCallback: nil)
            }
        }
    }

    /// Runs one analysis, records its outcome as an activity, and checks the result is usable.
    /// A failure on one model is reported without stopping the others.
    private func run(_ model: AIModel, _ analysis: () async throws -> FoodItemGroup) async {
        let started = Date()
        do {
            let group = try await analysis()
            let seconds = Date().timeIntervalSince(started)
            let names = group.foodItems.map(\.name).joined(separator: ", ")
            print("[\(model.rawValue)] \(String(format: "%.1f", seconds))s: \(group.foodItems.count) item(s): \(names)")

            XCTAssertFalse(group.foodItems.isEmpty, "[\(model.rawValue)] no food items")
            for item in group.foodItems {
                XCTAssertFalse(item.name.isEmpty, "[\(model.rawValue)] item without a name")
            }
            XCTAssertTrue(
                group.foodItems.contains { $0.nutrition.values[.carbs] != nil },
                "[\(model.rawValue)] no item carries carbohydrates"
            )
        } catch {
            XCTFail("[\(model.rawValue)] failed after \(String(format: "%.1f", Date().timeIntervalSince(started)))s: \(error)")
        }
    }

    // MARK: - Configuration

    private func modelsUnderTest() throws -> [(AIModel, String)] {
        let keys = try apiKeys()
        guard !keys.isEmpty else {
            throw XCTSkip("No AI API keys: set IAPS_AI_TEST_*_KEY or create .temp/ai-tokens.env")
        }

        let selection = setting("IAPS_AI_TEST_MODELS") ?? "default"
        let candidates: [AIModel] = switch selection {
        case "default": keys.keys.map { AIModel.defaultModel(for: $0) }
        case "all": AIModel.allCases.filter { !$0.isDeprecated }
        default: try selection.split(separator: ",").map {
                let raw = $0.trimmingCharacters(in: .whitespaces)
                return try XCTUnwrap(AIModel(rawValue: raw), "unknown model '\(raw)' in IAPS_AI_TEST_MODELS")
            }
        }

        let models = candidates.compactMap { model in keys[model.provider].map { (model, $0) } }
        guard !models.isEmpty else {
            throw XCTSkip("No API key for the selected models (\(selection))")
        }
        return models
    }

    private func apiKeys() throws -> [AIProvider: String] {
        var keys: [AIProvider: String] = [:]
        for (provider, name) in [
            (AIProvider.claude, "IAPS_AI_TEST_CLAUDE_KEY"),
            (AIProvider.gemini, "IAPS_AI_TEST_GEMINI_KEY"),
            (AIProvider.openAI, "IAPS_AI_TEST_OPENAI_KEY")
        ] {
            if let key = setting(name) {
                keys[provider] = key
            }
        }
        return keys
    }

    private func samplePhoto() throws -> UIImage {
        let path = setting("IAPS_AI_TEST_PHOTO")
            ?? repositoryRoot.appendingPathComponent(".temp/ai-test-photo.jpg").path
        guard let image = UIImage(contentsOfFile: path) else {
            throw XCTSkip("No sample photo at \(path): set IAPS_AI_TEST_PHOTO or add .temp/ai-test-photo.jpg")
        }
        return image
    }

    /// A test setting: the environment variable, or the same name in `.temp/ai-tokens.env`.
    private func setting(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name] ?? envFileValues[name]
        let trimmed = value?.trimmingCharacters(in: .whitespaces)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// `NAME=value` lines from `.temp/ai-tokens.env`; blank lines and `#` comments are ignored,
    /// surrounding quotes are stripped.
    private lazy var envFileValues: [String: String] = {
        let envFile = repositoryRoot.appendingPathComponent(".temp/ai-tokens.env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].hasPrefix("#") else { continue }
            values[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return values
    }()

    /// FreeAPSTests/<this file> -> repository root.
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func jsonObject(_ value: JSONValue) throws -> [String: Any] {
        let data = Data(value.serialized().utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
