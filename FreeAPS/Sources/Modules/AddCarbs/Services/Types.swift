import Foundation

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

    var description: String {
        switch self {
        case .claude:
            return "Anthropic's Claude AI with excellent reasoning. Requires paid API key from console.anthropic.com."
        case .gemini:
            return "Free API key available at ai.google.dev. Best for detailed food analysis."
        case .openAI:
            return "Requires paid OpenAI API key. Most accurate for complex meals."
        }
    }
}

protocol AIModelBase {
    var needAggressiveImageCompression: Bool { get }

    var fast: Bool { get }

    var rawValue: String { get }

    var timeoutsConfig: ModelTimeoutsConfig { get }

    var defaultImageETA: TimeInterval { get }

    var defaultTextETA: TimeInterval { get }

    var provider: AIProvider { get }
}

enum OpenAIModel: String, AIModelBase, Encodable {
    case gpt_4o = "gpt-4o"
    case gpt_4o_mini = "gpt-4o-mini"
    case gpt_5 = "gpt-5"
    case gpt_5_mini = "gpt-5-mini"
    case gpt_5_1 = "gpt-5.1"
    case gpt_5_2 = "gpt-5.2"

    var fast: Bool {
        switch self {
        case .gpt_4o: false
        case .gpt_4o_mini: true
        case .gpt_5: false
        case .gpt_5_mini: true
        case .gpt_5_1: false
        case .gpt_5_2: false
        }
    }

    var displayName: String {
        switch self {
        case .gpt_4o: "4o"
        case .gpt_4o_mini: "4o mini"
        case .gpt_5: "5"
        case .gpt_5_mini: "5 mini"
        case .gpt_5_1: "5.1"
        case .gpt_5_2: "5.2"
        }
    }

    var needAggressiveImageCompression: Bool {
        switch self {
        case .gpt_4o: false
        case .gpt_4o_mini: false
        case .gpt_5: true
        case .gpt_5_mini: true
        case .gpt_5_1: true
        case .gpt_5_2: true
        }}

    var isGPT5: Bool {
        switch self {
        case .gpt_4o: false
        case .gpt_4o_mini: false
        case .gpt_5: true
        case .gpt_5_mini: true
        case .gpt_5_1: true
        case .gpt_5_2: true
        }
    }

    var defaultImageETA: TimeInterval {
        switch self {
        case .gpt_4o: 35
        case .gpt_4o_mini: 25
        case .gpt_5: 40
        case .gpt_5_mini: 30
        case .gpt_5_1: 45
        case .gpt_5_2: 50
        }
    }

    var defaultTextETA: TimeInterval {
        switch self {
        case .gpt_4o: 10
        case .gpt_4o_mini: 10
        case .gpt_5: 15
        case .gpt_5_mini: 10
        case .gpt_5_1: 15
        case .gpt_5_2: 15
        }
    }

    var timeoutsConfig: ModelTimeoutsConfig {
        if isGPT5 {
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
}

enum GeminiModel: String, AIModelBase, Encodable {
    case gemini_2_5_pro = "gemini-2.5-pro"
    case gemini_2_5_flash = "gemini-2.5-flash"
    case gemini_3_pro_preview = "gemini-3-pro-preview"

    var fast: Bool {
        switch self {
        case .gemini_2_5_pro: false
        case .gemini_2_5_flash: true
        case .gemini_3_pro_preview: false
        }
    }

    var displayName: String {
        switch self {
        case .gemini_2_5_pro: "2.5 Pro"
        case .gemini_2_5_flash: "2.5 Flash"
        case .gemini_3_pro_preview: "3 Pro Preview"
        }
    }

    var needAggressiveImageCompression: Bool {
        switch self {
        case .gemini_2_5_pro: false
        case .gemini_2_5_flash: false
        case .gemini_3_pro_preview: false
        }
    }

    var defaultImageETA: TimeInterval {
        switch self {
        case .gemini_2_5_pro: 40
        case .gemini_2_5_flash: 30
        case .gemini_3_pro_preview: 45
        }
    }

    var defaultTextETA: TimeInterval {
        switch self {
        case .gemini_2_5_pro: 15
        case .gemini_2_5_flash: 10
        case .gemini_3_pro_preview: 15
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
}

enum ClaudeModel: String, AIModelBase, Encodable {
    case sonnet_4_5 = "claude-sonnet-4-5"
    case haiku_4_5 = "claude-haiku-4-5"

    var fast: Bool {
        switch self {
        case .sonnet_4_5: false
        case .haiku_4_5: true
        }
    }

    var displayName: String {
        switch self {
        case .sonnet_4_5: "Sonnet 4.5"
        case .haiku_4_5: "Haiku 4.5"
        }
    }

    var needAggressiveImageCompression: Bool {
        switch self {
        case .sonnet_4_5: return false
        case .haiku_4_5: return false
        }
    }

    var defaultImageETA: TimeInterval {
        switch self {
        case .sonnet_4_5: 55
        case .haiku_4_5: 40
        }
    }

    var defaultTextETA: TimeInterval {
        switch self {
        case .sonnet_4_5: 15
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

    static let allCases: [ImageSearchProvider] = [
        .aiModel(.openAI(.gpt_4o)),
        .aiModel(.openAI(.gpt_4o_mini)),
        .aiModel(.openAI(.gpt_5)),
        .aiModel(.openAI(.gpt_5_mini)),
        .aiModel(.openAI(.gpt_5_1)),
        .aiModel(.openAI(.gpt_5_2)),
        .aiModel(.gemini(.gemini_3_pro_preview)),
        .aiModel(.gemini(.gemini_2_5_pro)),
        .aiModel(.gemini(.gemini_2_5_flash)),
        .aiModel(.claude(.sonnet_4_5)),
        .aiModel(.claude(.haiku_4_5))
    ]

    static let defaultProvider: ImageSearchProvider = .aiModel(.gemini(.gemini_2_5_pro))
}

enum TextSearchProvider {
    case aiModel(AIModel)
    case usdaFoodData
    case openFoodFacts

    var providerName: String {
        switch self {
        case let .aiModel(model): model.provider.displayName
        case .usdaFoodData: "USDA Food Data"
        case .openFoodFacts: "OpenFoodFacts"
        }
    }

    var modelName: String? {
        switch self {
        case let .aiModel(model): model.displayName
        case .usdaFoodData: nil
        case .openFoodFacts: nil
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
        case .usdaFoodData: nil
        case .openFoodFacts: nil
        }
    }

    static let allCases: [TextSearchProvider] = [
        .aiModel(.openAI(.gpt_4o)),
        .aiModel(.openAI(.gpt_4o_mini)),
        .aiModel(.openAI(.gpt_5)),
        .aiModel(.openAI(.gpt_5_mini)),
        .aiModel(.openAI(.gpt_5_1)),
        .aiModel(.openAI(.gpt_5_2)),
        .aiModel(.gemini(.gemini_3_pro_preview)),
        .aiModel(.gemini(.gemini_2_5_pro)),
        .aiModel(.gemini(.gemini_2_5_flash)),
        .aiModel(.claude(.sonnet_4_5)),
        .aiModel(.claude(.haiku_4_5)),
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

    var modelName: String? {
        switch self {
        case .openFoodFacts: nil
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
        case .openFoodFacts: nil
        }
    }

    static let allCases: [BarcodeSearchProvider] = [
        .openFoodFacts
    ]

    static let defaultProvider: BarcodeSearchProvider = .openFoodFacts
}

// MARK: - String serialization for AIModel and providers

extension AIModel: RawRepresentable, Codable {
    public typealias RawValue = String

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
        case .usdaFoodData:
            return "usdaFoodData"
        case .openFoodFacts:
            return "openFoodFacts"
        case let .aiModel(model):
            return "aiModel/\(model.rawValue)"
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
        // Either "openFoodFacts", "usdaFoodData" or "aiModel/<...>"
        if rawValue == "openFoodFacts" {
            self = .openFoodFacts
            return
        }
//        if rawValue == "usdaFoodData" {
//            self = .usdaFoodData
//            return
//        }
//        let parts = rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
//        guard let head = parts.first else { return nil }
//        let tail = parts.count > 1 ? parts[1] : ""
//        switch head {
//        case "aiModel":
//            guard let model = AIModel(rawValue: tail) else { return nil }
//            self = .aiModel(model)
//        default:
//            return nil
//        }
        return nil
    }

    public var rawValue: String {
        switch self {
        case .openFoodFacts:
            return "openFoodFacts"
//        case .usdaFoodData:
//            return "usdaFoodData"
//        case let .aiModel(model):
//            return "aiModel/\(model.rawValue)"
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
