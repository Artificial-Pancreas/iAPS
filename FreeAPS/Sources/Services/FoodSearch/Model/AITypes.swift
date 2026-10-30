import Foundation
import UIKit

enum AIProvider: Hashable {
    case openAI
    case gemini
    case claude

    var requiresAPIKey: Bool {
        switch self {
        case .claude,
             .gemini,
             .openAI:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .claude:
            return "Anthropic Claude"
        case .gemini:
            return "Google Gemini"
        case .openAI:
            return "OpenAI GPT"
        }
    }
}

/// Lifecycle status for a model that is no longer part of the vendor's current lineup.
/// Such models are hidden from the pickers unless already selected. With a `shutdownDate` the
/// vendor has formally deprecated the model; without one it is merely legacy (still listed as
/// active or access-limited by the vendor) and the UI must not call it deprecated.
struct AIModelDeprecation: Hashable {
    /// The day the vendor has announced the model stops being served, when published.
    let shutdownDate: Date?

    /// Legacy: out of the current lineup with no announced shutdown date (vendor "not sooner than"
    /// dates, or access limited to existing users).
    static let noDate = AIModelDeprecation(shutdownDate: nil)

    /// Deprecated with a vendor-announced shutdown date (year, month, day in UTC).
    static func shutdown(_ year: Int, _ month: Int, _ day: Int) -> AIModelDeprecation {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return AIModelDeprecation(shutdownDate: Calendar(identifier: .gregorian).date(from: components))
    }

    var isPastShutdown: Bool {
        guard let shutdownDate else { return false }
        return Date() >= shutdownDate
    }
}

protocol AIModelBase {
    var fast: Bool { get }

    /// Non-nil when the vendor has deprecated the model or dropped it from the current lineup.
    var deprecation: AIModelDeprecation? { get }

    var temperature: Double? { get }

    var rawValue: String { get }

    var timeoutsConfig: ModelTimeoutsConfig { get }

    var defaultImageETA: TimeInterval { get }

    var defaultTextETA: TimeInterval { get }

    var provider: AIProvider { get }

    var maxImageDimension: Int { get }
}

enum OpenAIModel: String, AIModelBase, CaseIterable, Encodable {
    // Current lineup (OpenAI models page, Oct 2026)
    case gpt_6_astra = "gpt-6-astra"
    case gpt_6_1_sol = "gpt-6.1-sol"
    case gpt_6_1_terra = "gpt-6.1-terra"
    case gpt_6_luna = "gpt-6-luna"
    // Deprecated / no longer in the current lineup
    case gpt_4o = "gpt-4o"
    case gpt_4o_mini = "gpt-4o-mini"
    case gpt_5 = "gpt-5"
    case gpt_5_mini = "gpt-5-mini"
    case gpt_5_1 = "gpt-5.1"
    case gpt_5_2 = "gpt-5.2"
    case gpt_5_4 = "gpt-5.4"

    static let defaultModel: OpenAIModel = .gpt_6_1_sol

    var fast: Bool {
        switch self {
        case .gpt_6_astra: false
        case .gpt_6_1_sol: false
        case .gpt_6_1_terra: true
        case .gpt_6_luna: true
        case .gpt_4o: false
        case .gpt_4o_mini: true
        case .gpt_5: false
        case .gpt_5_mini: true
        case .gpt_5_1: false
        case .gpt_5_2: false
        case .gpt_5_4: false
        }
    }

    /// Shutdown dates from https://developers.openai.com/api/docs/deprecations (Oct 2026).
    var deprecation: AIModelDeprecation? {
        switch self {
        case .gpt_6_1_sol,
             .gpt_6_1_terra,
             .gpt_6_astra,
             .gpt_6_luna:
            nil
        case .gpt_4o: .shutdown(2027, 1, 14)
        case .gpt_4o_mini: .shutdown(2027, 1, 14)
        case .gpt_5: .shutdown(2026, 12, 11)
        case .gpt_5_mini: .shutdown(2026, 12, 11)
        case .gpt_5_1: .shutdown(2027, 4, 1)
        case .gpt_5_2: .noDate // no longer listed on the models page; no base-model shutdown date yet
        case .gpt_5_4: .noDate // same as 5.2
        }
    }

    var temperature: Double? {
        switch self {
        case .gpt_6_astra: nil
        case .gpt_6_1_sol: nil
        case .gpt_6_1_terra: nil
        case .gpt_6_luna: nil
        case .gpt_4o: 0.01
        case .gpt_4o_mini: 0.01
        case .gpt_5: nil
        case .gpt_5_mini: nil
        case .gpt_5_1: 0.01
        case .gpt_5_2: 0.01
        case .gpt_5_4: 0.01
        }
    }

    var displayName: String {
        switch self {
        case .gpt_6_astra: "6 Astra"
        case .gpt_6_1_sol: "6.1 Sol"
        case .gpt_6_1_terra: "6.1 Terra"
        case .gpt_6_luna: "6 Luna"
        case .gpt_4o: "4o"
        case .gpt_4o_mini: "4o mini"
        case .gpt_5: "5"
        case .gpt_5_mini: "5 mini"
        case .gpt_5_1: "5.1"
        case .gpt_5_2: "5.2"
        case .gpt_5_4: "5.4"
        }
    }

    /// `reasoning.effort` for the Responses API. Reasoning tokens count against
    /// `max_output_tokens`, so food analysis asks for the lowest level every current model
    /// accepts ("low"; "minimal" and "none" are rejected by some GPT-6 models). Nil for GPT-4o.
    var reasoningEffort: String? {
        isReasoningModel ? "low" : nil
    }

    /// Reasoning-family models (GPT-5 and later): JSON output is requested via the `text.format`
    /// option, streaming is off, and the longer request timeouts apply.
    var isReasoningModel: Bool {
        switch self {
        case .gpt_4o: false
        case .gpt_4o_mini: false
        case .gpt_5,
             .gpt_5_1,
             .gpt_5_2,
             .gpt_5_4,
             .gpt_5_mini,
             .gpt_6_1_sol,
             .gpt_6_1_terra,
             .gpt_6_astra,
             .gpt_6_luna:
            true
        }
    }

    var defaultImageETA: TimeInterval {
        switch self {
        case .gpt_6_astra: 50
        case .gpt_6_1_sol: 45
        case .gpt_6_1_terra: 30
        case .gpt_6_luna: 25
        case .gpt_4o: 35
        case .gpt_4o_mini: 25
        case .gpt_5: 40
        case .gpt_5_mini: 30
        case .gpt_5_1: 45
        case .gpt_5_2: 50
        case .gpt_5_4: 50
        }
    }

    var defaultTextETA: TimeInterval {
        switch self {
        case .gpt_6_astra: 15
        case .gpt_6_1_sol: 15
        case .gpt_6_1_terra: 10
        case .gpt_6_luna: 10
        case .gpt_4o: 10
        case .gpt_4o_mini: 10
        case .gpt_5: 15
        case .gpt_5_mini: 10
        case .gpt_5_1: 15
        case .gpt_5_2: 15
        case .gpt_5_4: 15
        }
    }

    var timeoutsConfig: ModelTimeoutsConfig {
        if isReasoningModel {
            return ModelTimeoutsConfig(
                requestTimeoutInterval: 120,
                timeoutIntervalForRequest: 150,
                timeoutIntervalForResource: 180
            )
        } else {
            return ModelTimeoutsConfig(
                requestTimeoutInterval: 120,
                timeoutIntervalForRequest: 90,
                timeoutIntervalForResource: 120
            )
        }
    }

    var provider: AIProvider { .openAI }

    var maxImageDimension: Int { 2048 }
}

enum GeminiModel: String, AIModelBase, CaseIterable, Encodable {
    // Current stable lineup (Gemini models page, Oct 2026). Preview models are intentionally not offered.
    case gemini_4_argon = "gemini-4-argon"
    case gemini_3_8_flash = "gemini-3.8-flash"
    case gemini_3_6_flash = "gemini-3.6-flash"
    case gemini_3_5_flash_lite = "gemini-3.5-flash-lite"
    // Deprecated: still served, but Google limits access to users who have used them before.
    case gemini_2_5_pro = "gemini-2.5-pro"
    case gemini_2_5_flash = "gemini-2.5-flash"

    static let defaultModel: GeminiModel = .gemini_3_8_flash

    var fast: Bool {
        switch self {
        case .gemini_4_argon: false
        case .gemini_3_8_flash: true
        case .gemini_3_6_flash: true
        case .gemini_3_5_flash_lite: true
        case .gemini_2_5_pro: false
        case .gemini_2_5_flash: true
        }
    }

    /// From https://ai.google.dev/gemini-api/docs/deprecations (Oct 2026): the 2.5 models have no
    /// shutdown date but are access-limited to existing users.
    var deprecation: AIModelDeprecation? {
        switch self {
        case .gemini_3_5_flash_lite,
             .gemini_3_6_flash,
             .gemini_3_8_flash,
             .gemini_4_argon:
            nil
        case .gemini_2_5_pro: .noDate
        case .gemini_2_5_flash: .noDate
        }
    }

    /// Google strongly recommends leaving sampling at its defaults on Gemini 3 and later; the
    /// old near-zero temperature was tuned for 2.5 and is kept only there.
    var temperature: Double? {
        switch self {
        case .gemini_3_5_flash_lite,
             .gemini_3_6_flash,
             .gemini_3_8_flash,
             .gemini_4_argon:
            nil
        case .gemini_2_5_pro: 0.01
        case .gemini_2_5_flash: 0.01
        }
    }

    /// Gemini 3 and later think by default ("medium" on the current models) and the thought
    /// tokens count against `maxOutputTokens`, so food analysis asks for the lowest level the
    /// model accepts. Nil for 2.5, which uses the legacy thinking budget instead.
    var thinkingLevel: String? {
        switch self {
        case .gemini_4_argon: "LOW"
        case .gemini_3_8_flash: "LOW"
        case .gemini_3_6_flash: "MINIMAL"
        case .gemini_3_5_flash_lite: "MINIMAL"
        case .gemini_2_5_pro: nil
        case .gemini_2_5_flash: nil
        }
    }

    var displayName: String {
        switch self {
        case .gemini_4_argon: "4 Argon"
        case .gemini_3_8_flash: "3.8 Flash"
        case .gemini_3_6_flash: "3.6 Flash"
        case .gemini_3_5_flash_lite: "3.5 Flash-Lite"
        case .gemini_2_5_pro: "2.5 Pro"
        case .gemini_2_5_flash: "2.5 Flash"
        }
    }

    var defaultImageETA: TimeInterval {
        switch self {
        case .gemini_4_argon: 45
        case .gemini_3_8_flash: 30
        case .gemini_3_6_flash: 30
        case .gemini_3_5_flash_lite: 25
        case .gemini_2_5_pro: 40
        case .gemini_2_5_flash: 30
        }
    }

    var defaultTextETA: TimeInterval {
        switch self {
        case .gemini_4_argon: 15
        case .gemini_3_8_flash: 10
        case .gemini_3_6_flash: 10
        case .gemini_3_5_flash_lite: 10
        case .gemini_2_5_pro: 15
        case .gemini_2_5_flash: 10
        }
    }

    var timeoutsConfig: ModelTimeoutsConfig {
        ModelTimeoutsConfig(
            requestTimeoutInterval: 120,
            timeoutIntervalForRequest: 150,
            timeoutIntervalForResource: 180
        )
    }

    var provider: AIProvider { .gemini }

    var maxImageDimension: Int { 2048 }
}

enum ClaudeModel: String, AIModelBase, CaseIterable, Encodable {
    // Current lineup (Claude models overview, Oct 2026)
    case opus_5_5 = "claude-opus-5-5"
    case sonnet_5_5 = "claude-sonnet-5-5"
    case haiku_5_5 = "claude-haiku-5-5"
    // Deprecated or legacy
    case sonnet_4_5 = "claude-sonnet-4-5"
    case haiku_4_5 = "claude-haiku-4-5"
    case sonnet_4_6 = "claude-sonnet-4-6"
    case opus_4_6 = "claude-opus-4-6"

    static let defaultModel: ClaudeModel = .sonnet_5_5

    var fast: Bool {
        switch self {
        case .opus_5_5: false
        case .sonnet_5_5: false
        case .haiku_5_5: true
        case .sonnet_4_5: false
        case .sonnet_4_6: false
        case .opus_4_6: false
        case .haiku_4_5: true
        }
    }

    /// From https://platform.claude.com/docs/en/about-claude/model-deprecations (Oct 2026).
    /// Sonnet 4.5 retires on 2026-11-30; the 4.6 models and Haiku 4.5 are legacy with
    /// "not sooner than" dates only, so no shutdown date is recorded for them.
    var deprecation: AIModelDeprecation? {
        switch self {
        case .haiku_5_5,
             .opus_5_5,
             .sonnet_5_5:
            nil
        case .sonnet_4_5: .shutdown(2026, 11, 30)
        case .haiku_4_5: .noDate
        case .sonnet_4_6: .noDate
        case .opus_4_6: .noDate
        }
    }

    /// Claude 4.7 and later reject a non-default `temperature`, and the parameter is removed in
    /// API version 2026-10-21, so the current models send none.
    var temperature: Double? {
        switch self {
        case .haiku_5_5,
             .opus_5_5,
             .sonnet_5_5:
            nil
        case .sonnet_4_5: 0.01
        case .sonnet_4_6: 0.01
        case .opus_4_6: 0.01
        case .haiku_4_5: 0.01
        }
    }

    /// `output_config.effort`. Thinking is adaptive and cannot be turned off on the 5.5 models,
    /// and thinking tokens count against `max_tokens`, so food analysis runs at "low". The 4.6
    /// models accept effort too; Sonnet 4.5 and Haiku 4.5 reject the parameter.
    var effort: String? {
        switch self {
        case .haiku_5_5,
             .opus_4_6,
             .opus_5_5,
             .sonnet_4_6,
             .sonnet_5_5:
            "low"
        case .sonnet_4_5: nil
        case .haiku_4_5: nil
        }
    }

    var displayName: String {
        switch self {
        case .opus_5_5: "Opus 5.5"
        case .sonnet_5_5: "Sonnet 5.5"
        case .haiku_5_5: "Haiku 5.5"
        case .sonnet_4_5: "Sonnet 4.5"
        case .sonnet_4_6: "Sonnet 4.6"
        case .opus_4_6: "Opus 4.6"
        case .haiku_4_5: "Haiku 4.5"
        }
    }

    var defaultImageETA: TimeInterval {
        switch self {
        case .opus_5_5: 70
        case .sonnet_5_5: 55
        case .haiku_5_5: 35
        case .sonnet_4_5: 55
        case .sonnet_4_6: 55
        case .opus_4_6: 100
        case .haiku_4_5: 40
        }
    }

    var defaultTextETA: TimeInterval {
        switch self {
        case .opus_5_5: 20
        case .sonnet_5_5: 15
        case .haiku_5_5: 10
        case .sonnet_4_5: 15
        case .sonnet_4_6: 15
        case .opus_4_6: 20
        case .haiku_4_5: 10
        }
    }

    var timeoutsConfig: ModelTimeoutsConfig {
        ModelTimeoutsConfig(
            requestTimeoutInterval: 120,
            timeoutIntervalForRequest: 150,
            timeoutIntervalForResource: 180
        )
    }

    var provider: AIProvider { .claude }

    var maxImageDimension: Int { 1568 }
}

enum AIModel {
    case openAI(OpenAIModel)
    case gemini(GeminiModel)
    case claude(ClaudeModel)

    var fast: Bool {
        switch self {
        case let .openAI(model): model.fast
        case let .gemini(model): model.fast
        case let .claude(model): model.fast
        }
    }

    var displayName: String {
        switch self {
        case let .openAI(model): model.displayName
        case let .gemini(model): model.displayName
        case let .claude(model): model.displayName
        }
    }

    var provider: AIProvider {
        switch self {
        case .openAI: return .openAI
        case .gemini: return .gemini
        case .claude: return .claude
        }
    }

    var deprecation: AIModelDeprecation? {
        switch self {
        case let .openAI(model): model.deprecation
        case let .gemini(model): model.deprecation
        case let .claude(model): model.deprecation
        }
    }

    var isDeprecated: Bool {
        deprecation != nil
    }

    /// The model to fall back to when a stored selection names a model this build no longer knows.
    static func defaultModel(for provider: AIProvider) -> AIModel {
        switch provider {
        case .openAI: .openAI(OpenAIModel.defaultModel)
        case .gemini: .gemini(GeminiModel.defaultModel)
        case .claude: .claude(ClaudeModel.defaultModel)
        }
    }

    /// All models this build knows, grouped by provider in the order the pickers show them.
    static let allCases: [AIModel] = GeminiModel.allCases.map(AIModel.gemini)
        + OpenAIModel.allCases.map(AIModel.openAI)
        + ClaudeModel.allCases.map(AIModel.claude)

    var description: String {
        switch self {
        case let .openAI(model): "\(model.provider.displayName) \(model.displayName)"
        case let .gemini(model): "\(model.provider.displayName) \(model.displayName)"
        case let .claude(model): "\(model.provider.displayName) \(model.displayName)"
        }
    }

    var defaultImageETA: TimeInterval {
        switch self {
        case let .openAI(model): model.defaultImageETA
        case let .gemini(model): model.defaultImageETA
        case let .claude(model): model.defaultImageETA
        }
    }

    var defaultTextETA: TimeInterval {
        switch self {
        case let .openAI(model): model.defaultTextETA
        case let .gemini(model): model.defaultTextETA
        case let .claude(model): model.defaultTextETA
        }
    }

    var maxImageDimension: Int {
        switch self {
        case let .openAI(model): model.maxImageDimension
        case let .gemini(model): model.maxImageDimension
        case let .claude(model): model.maxImageDimension
        }
    }
}

enum ImageSearchProvider {
    case aiModel(AIModel)

    var providerName: String {
        switch self {
        case let .aiModel(model): model.provider.displayName
        }
    }

    var modelName: String? {
        switch self {
        case let .aiModel(model): model.displayName
        }
    }

    var description: String {
        if let model = modelName {
            "\(providerName) (\(model))"
        } else {
            providerName
        }
    }

    var fast: Bool? {
        switch self {
        case let .aiModel(model): model.fast
        }
    }

    static let allCases: [ImageSearchProvider] = AIModel.allCases.map { .aiModel($0) }

    static let defaultProvider: ImageSearchProvider = .aiModel(.gemini(GeminiModel.defaultModel))

    var deprecation: AIModelDeprecation? {
        switch self {
        case let .aiModel(model): model.deprecation
        }
    }

    var isDeprecated: Bool {
        deprecation != nil
    }

    /// What a picker should offer: every non-deprecated choice, plus `current` when it is
    /// deprecated so an existing selection stays visible (and keeps its warning badge).
    static func pickerCases(current: ImageSearchProvider) -> [ImageSearchProvider] {
        allCases.filter { !$0.isDeprecated || $0 == current }
    }

    /// Same-provider fallback for a stored value this build cannot parse (a model that was
    /// removed, typically). Falls back to that provider's default model, then to `defaultProvider`.
    static func resolve(rawValue: String) -> ImageSearchProvider {
        if let parsed = ImageSearchProvider(rawValue: rawValue) {
            return parsed
        }
        if let provider = AIModel.provider(fromRawValue: Self.modelRawValue(from: rawValue)) {
            return .aiModel(AIModel.defaultModel(for: provider))
        }
        return defaultProvider
    }

    private static func modelRawValue(from rawValue: String) -> String {
        let parts = rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        return parts.count > 1 && parts[0] == "aiModel" ? parts[1] : ""
    }
}

enum AITextProvider {
    case aiModel(AIModel)

    var providerName: String {
        switch self {
        case let .aiModel(model): model.provider.displayName
        }
    }

    var modelName: String? {
        switch self {
        case let .aiModel(model): model.displayName
        }
    }

    var description: String {
        if let model = modelName {
            "\(providerName) (\(model))"
        } else {
            providerName
        }
    }

    var fast: Bool? {
        switch self {
        case let .aiModel(model): model.fast
        }
    }

    static let allCases: [AITextProvider] = AIModel.allCases.map { .aiModel($0) }

    static let defaultProvider: AITextProvider = .aiModel(.gemini(GeminiModel.defaultModel))

    var deprecation: AIModelDeprecation? {
        switch self {
        case let .aiModel(model): model.deprecation
        }
    }

    var isDeprecated: Bool {
        deprecation != nil
    }

    /// What a picker should offer: every non-deprecated choice, plus `current` when it is
    /// deprecated so an existing selection stays visible (and keeps its warning badge).
    static func pickerCases(current: AITextProvider) -> [AITextProvider] {
        allCases.filter { !$0.isDeprecated || $0 == current }
    }

    /// Same-provider fallback for a stored value this build cannot parse (a model that was
    /// removed, typically). Falls back to that provider's default model, then to `defaultProvider`.
    static func resolve(rawValue: String) -> AITextProvider {
        if let parsed = AITextProvider(rawValue: rawValue) {
            return parsed
        }
        if let provider = AIModel.provider(fromRawValue: Self.modelRawValue(from: rawValue)) {
            return .aiModel(AIModel.defaultModel(for: provider))
        }
        return defaultProvider
    }

    private static func modelRawValue(from rawValue: String) -> String {
        let parts = rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        return parts.count > 1 && parts[0] == "aiModel" ? parts[1] : ""
    }
}

enum TextSearchProvider {
    case usdaFoodData
    case openFoodFacts

    var providerName: String {
        switch self {
        case .usdaFoodData: "USDA Food Data"
        case .openFoodFacts: "OpenFoodFacts"
        }
    }

    var description: String {
        providerName
    }

    static let allCases: [TextSearchProvider] = [
        .usdaFoodData,
        .openFoodFacts
    ]

    static let defaultProvider: TextSearchProvider = .usdaFoodData
}

enum BarcodeSearchProvider {
    case openFoodFacts

    var providerName: String {
        switch self {
        case .openFoodFacts: "OpenFoodFacts"
        }
    }

    var description: String {
        providerName
    }

    static let allCases: [BarcodeSearchProvider] = [
        .openFoodFacts
    ]

    static let defaultProvider: BarcodeSearchProvider = .openFoodFacts
}

// MARK: - String serialization for AIModel and providers

extension AIModel: RawRepresentable, Codable {
    public typealias RawValue = String

    /// The provider segment of a serialized model ("openAI/gpt-4o" -> .openAI), or nil when unknown.
    static func provider(fromRawValue rawValue: String) -> AIProvider? {
        switch rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) {
        case "openAI": .openAI
        case "gemini": .gemini
        case "claude": .claude
        default: nil
        }
    }

    public init?(rawValue: String) {
        // Expect at least a provider segment, with an optional tail that the model enum parses.
        let parts = rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let provider = parts.first else { return nil }
        let tail = parts.count > 1 ? parts[1] : ""
        switch provider {
        case "openAI":
            guard let m = OpenAIModel(rawValue: tail) else { return nil }
            self = .openAI(m)
        case "gemini":
            guard let m = GeminiModel(rawValue: tail) else { return nil }
            self = .gemini(m)
        case "claude":
            guard let m = ClaudeModel(rawValue: tail) else { return nil }
            self = .claude(m)
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case let .openAI(m):
            return "openAI/\(m.rawValue)"
        case let .gemini(m):
            return "gemini/\(m.rawValue)"
        case let .claude(m):
            return "claude/\(m.rawValue)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = AIModel(rawValue: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid AIModel string: \(string)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ImageSearchProvider: RawRepresentable, Codable {
    public typealias RawValue = String

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first else { return nil }
        let tail = parts.count > 1 ? parts[1] : ""
        switch head {
        case "aiModel":
            guard let model = AIModel(rawValue: tail) else { return nil }
            self = .aiModel(model)
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case let .aiModel(model):
            return "aiModel/\(model.rawValue)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = ImageSearchProvider(rawValue: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ImageSearchProvider string: \(string)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension AITextProvider: RawRepresentable, Codable {
    public typealias RawValue = String

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let head = parts.first else { return nil }
        let tail = parts.count > 1 ? parts[1] : ""
        switch head {
        case "aiModel":
            guard let model = AIModel(rawValue: tail) else { return nil }
            self = .aiModel(model)
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case let .aiModel(model):
            return "aiModel/\(model.rawValue)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = AITextProvider(rawValue: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ImageSearchProvider string: \(string)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension TextSearchProvider: RawRepresentable, Codable {
    public typealias RawValue = String

    public init?(rawValue: String) {
        if rawValue == "usdaFoodData" {
            self = .usdaFoodData
            return
        }
        if rawValue == "openFoodFacts" {
            self = .openFoodFacts
            return
        }
        return nil
    }

    public var rawValue: String {
        switch self {
        case .usdaFoodData:
            return "usdaFoodData"
        case .openFoodFacts:
            return "openFoodFacts"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = TextSearchProvider(rawValue: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid TextSearchProvider string: \(string)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension BarcodeSearchProvider: RawRepresentable, Codable {
    public typealias RawValue = String

    public init?(rawValue: String) {
        if rawValue == "openFoodFacts" {
            self = .openFoodFacts
            return
        }
        return nil
    }

    public var rawValue: String {
        switch self {
        case .openFoodFacts:
            return "openFoodFacts"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = BarcodeSearchProvider(rawValue: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid BarcodeSearchProvider string: \(string)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Hashable & Identifiable for provider enums

extension ImageSearchProvider: Hashable, Identifiable {
    public var id: String { rawValue }

    public static func == (lhs: ImageSearchProvider, rhs: ImageSearchProvider) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension AITextProvider: Hashable, Identifiable {
    public var id: String { rawValue }

    public static func == (lhs: AITextProvider, rhs: AITextProvider) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension TextSearchProvider: Hashable, Identifiable {
    public var id: String { rawValue }

    public static func == (lhs: TextSearchProvider, rhs: TextSearchProvider) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension BarcodeSearchProvider: Hashable, Identifiable {
    public var id: String { rawValue }

    public static func == (lhs: BarcodeSearchProvider, rhs: BarcodeSearchProvider) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

struct ModelTimeoutsConfig {
    let requestTimeoutInterval: TimeInterval
    let timeoutIntervalForRequest: TimeInterval
    let timeoutIntervalForResource: TimeInterval
}

enum AnalysisRequest {
    case image(_ image: UIImage, _ comment: String?)
    case query(_ query: String)

    var image: UIImage? {
        switch self {
        case let .image(image, _): image
        case .query: nil
        }
    }
}

enum NutritionAuthority: String {
    case US_USDA
    case EU_EFSA
    case UK_COFID
    case CA_HEALTH
    case AU_NZ_FSANZ
    case JP_MHLW
    case INTL_WHO_FAO

    var description: String {
        switch self {
        case .US_USDA: "United States (USDA / FDA)"
        case .EU_EFSA: "European Union (EFSA / EU labeling)"
        case .UK_COFID: "United Kingdom (CoFID / NHS)"
        case .CA_HEALTH: "Canada (Health Canada)"
        case .AU_NZ_FSANZ: "Australia & New Zealand (FSANZ)"
        case .JP_MHLW: "Japan (MHLW)"
        case .INTL_WHO_FAO: "International (WHO / FAO / Codex)"
        }
    }

    var descriptionForAI: String {
        switch self {
        case .US_USDA: "United States Department of Agriculture (USDA), FDA Nutrition Facts"
        case .EU_EFSA: "European Food Safety Authority (EFSA), EU food labeling standards"
        case .UK_COFID: "UK Composition of Foods Integrated Dataset (CoFID), NHS"
        case .CA_HEALTH: "Health Canada, Canadian Nutrition Facts Table"
        case .AU_NZ_FSANZ: "Food Standards Australia New Zealand (FSANZ)"
        case .JP_MHLW: "Ministry of Health, Labour and Welfare (MHLW), Japanese Food Labeling Standards"
        case .INTL_WHO_FAO: "World Health Organization (WHO), FAO, Codex Alimentarius"
        }
    }

    static let allCases: [NutritionAuthority] = [
        //        .INTL_WHO_FAO,
        .US_USDA,
        .EU_EFSA,
        .UK_COFID,
        .CA_HEALTH,
        .AU_NZ_FSANZ,
        .JP_MHLW
    ]

    static var localDefault: NutritionAuthority {
        guard let countryCode = Locale.current.region?.identifier.uppercased()
        else {
            return .INTL_WHO_FAO
        }

        switch countryCode {
        case "US":
            return .US_USDA

        case "GB":
            return .UK_COFID

        case "CA":
            return .CA_HEALTH

        case "AU",
             "NZ":
            return .AU_NZ_FSANZ

        case "JP":
            return .JP_MHLW

        // EU / EEA / Switzerland
        case
            "AT",
            "BE",
            "BG",
            "CH",
            "CY",
            "CZ",
            "DE",
            "DK",
            "EE",
            "ES",
            "FI",
            "FR",
            "GR",
            "HR",
            "HU",
            "IE",
            "IS",
            "IT",
            "LI",
            "LT",
            "LU",
            "LV",
            "MT",
            "NL",
            "NO",
            "PL",
            "PT",
            "RO",
            "SE",
            "SI",
            "SK":
            return .EU_EFSA

        default:
            return .EU_EFSA
        }
    }
}
