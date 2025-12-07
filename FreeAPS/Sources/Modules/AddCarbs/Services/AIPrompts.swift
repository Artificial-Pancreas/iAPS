import Foundation
import UIKit

enum AnalysisRequest {
    case image(_ image: UIImage)
    case query(_ query: String)

    var image: UIImage? {
        switch self {
        case let .image(image): image
        case .query: nil
        }
    }
}

enum AIPrompts {
    static func getAnalysisPrompt(
        _ request: AnalysisRequest,
        responseSchema: [(String, Any)],
    ) -> String {
        do {
            let selectedPrompt = try getStandardAnalysisPrompt(
                request,
                responseSchema: responseSchema,
            )
            let promptLength = selectedPrompt.count

            print("🎯 AI Analysis Prompt Selection:")
            //    print("   Advanced Dosing Enabled: \(isAdvancedEnabled)")
            print("   Prompt Length: \(promptLength) characters")
            //    print("   Prompt Type: \(isAdvancedEnabled ? "ADVANCED (with FPU calculations)" : "STANDARD (basic diabetes analysis)")")
            print("   First 100 chars of selected prompt: \(String(selectedPrompt.prefix(100)))")

            return selectedPrompt
        } catch {
            return ""
        }
    }
}

private enum PromptLoader {
    static func loadTextResource(named fileName: String) -> String {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            assertionFailure("Missing resource \(fileName)")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            assertionFailure("Failed to load \(fileName): \(error)")
            return ""
        }
    }
}

private let prompt_0_header: String = PromptLoader.loadTextResource(named: "ai/standard/0_header.txt")
private let prompt_1_preferences: String = PromptLoader.loadTextResource(named: "ai/standard/1_user_preferences.txt")

private let prompt_3_standards: String = PromptLoader.loadTextResource(named: "ai/standard/3_standards.txt")

private let prompt_5a_photo_instructions: String = PromptLoader
    .loadTextResource(named: "ai/standard/5a_photo_instructions.txt")

private let prompt_5b_text_instructions: String = PromptLoader
    .loadTextResource(named: "ai/standard/5b_text_instructions.txt")

private let prompt_7_response_schema: String = PromptLoader.loadTextResource(named: "ai/standard/7_response_schema.txt")

private let prompt_8_footer: String = PromptLoader
    .loadTextResource(named: "ai/standard/8_footer.txt")

/// Standard analysis prompt for basic diabetes management (used when Advanced Dosing is OFF)
private func getStandardAnalysisPrompt(
    _ request: AnalysisRequest,
    responseSchema: [(String, Any)],
) throws -> String {
    let instructions = switch request {
    case .image: prompt_5a_photo_instructions
    case let .query(textQuery): prompt_5b_text_instructions.replacingOccurrences(of: "(query)", with: textQuery)
    }

    let schemaJson = PlainJSONFromPairs(responseSchema)

    var schema = renderPlainJSON(schemaJson)
    let languageCode = UserDefaults.standard.userPreferredLanguageForAI ?? Locale.current.region?.identifier

    if let languageForAI = getLanguageForAI(languageCode: languageCode) {
        schema = schema.replacingOccurrences(of: "(language)", with: "\(languageForAI)")
    } else {
        schema = schema.replacingOccurrences(of: "(language)", with: "")
    }
    let responseSchema = prompt_7_response_schema.replacingOccurrences(of: "(schema)", with: schema)

    let regionCode = UserDefaults.standard.userPreferredRegionForAI ?? Locale.preferredLanguages.first
    let userPreferences: String = makePreferencesBlock(regionCode: regionCode)

    return prompt_0_header + "\n\n" +
        userPreferences + "\n\n" +
        prompt_3_standards + "\n\n" +
        instructions + "\n\n" +
        responseSchema + "\n\n" +
        prompt_8_footer
}

private func getLanguageForAI(languageCode: String?) -> String? {
    guard let languageCode else { return nil }
    let locale = Locale.current

    let rawLang = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)

    let languageTag = rawLang.isEmpty ? "en-US" : rawLang
    let primaryLanguageCode = languageTag.split(separator: "-").first.map(String.init) ?? "en"
    let languageName = locale.localizedString(forLanguageCode: primaryLanguageCode) ?? primaryLanguageCode

    return "\(languageName) (\(languageTag))"
}

private func makePreferencesBlock(regionCode: String?) -> String {
    let locale = Locale.current

    let systemRegion = Locale.current.identifier
    let rawRegion = regionCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let effectiveRegion = rawRegion.isEmpty ? systemRegion : rawRegion
    let regionName = locale.localizedString(forRegionCode: effectiveRegion) ?? effectiveRegion

    let regionForAI =
        effectiveRegion.isNotEmpty ?
        "\(regionName) (\(effectiveRegion))" : regionName

    let nutritionAuthority = UserDefaults.standard.userPreferredNutritionAuthorityForAI

    return prompt_1_preferences
        .replacingOccurrences(of: "(nutrition_authority)", with: nutritionAuthority.descriptionForAI)
        .replacingOccurrences(of: "(region)", with: regionForAI)
}

// MARK: just to encode an [(string, any)] and preserve the order of fields in the schema, since swift doesn't seem to have anything for this ¯\_(ツ)_/¯

private enum PlainJSON {
    case object([(String, PlainJSON)])
    case array([PlainJSON])
    case string(String)
}

private func renderPlainJSON(_ node: PlainJSON, indent: String = "") -> String {
    let nextIndent = indent + "  "
    switch node {
    case let .string(s):
        return "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    case let .array(items):
        if items.isEmpty { return "[]" }
        var lines: [String] = ["["]
        for (idx, item) in items.enumerated() {
            let rendered = renderPlainJSON(item, indent: nextIndent)
            let suffix = idx == items.count - 1 ? "" : ","
            lines.append(nextIndent + rendered + suffix)
        }
        lines.append(indent + "]")
        return lines.joined(separator: "\n")
    case let .object(pairs):
        if pairs.isEmpty { return "{}" }
        var lines: [String] = ["{"]
        for (idx, pair) in pairs.enumerated() {
            let keyEscaped = pair.0.replacingOccurrences(of: "\"", with: "\\\"")
            let valueRendered = renderPlainJSON(pair.1, indent: nextIndent)
            let suffix = idx == pairs.count - 1 ? "" : ","
            lines.append(nextIndent + "\"" + keyEscaped + "\": " + valueRendered + suffix)
        }
        lines.append(indent + "}")
        return lines.joined(separator: "\n")
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue _: Int) { nil }
}

private func PlainJSONFromPairs(_ pairs: [(String, Any)]) -> PlainJSON {
    var out: [(String, PlainJSON)] = []
    out.reserveCapacity(pairs.count)
    for (k, v) in pairs {
        if let j = PlainJSONValue(from: v) {
            out.append((k, j))
        }
    }
    return .object(out)
}

private func PlainJSONValue(from value: Any) -> PlainJSON? {
    switch value {
    case let s as String:
        return .string(s)
    case let pairs as [(String, Any)]:
        return PlainJSONFromPairs(pairs)
    case let arr as [Any]:
        let mapped = arr.compactMap { PlainJSONValue(from: $0) }
        return .array(mapped)
    default:
        return nil
    }
}
