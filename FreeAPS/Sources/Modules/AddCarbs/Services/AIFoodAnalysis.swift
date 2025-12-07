import CoreML
import CryptoKit
import Foundation
import LoopKit
import Network
import os.log
import SwiftUI
import UIKit
import Vision

class ConfigurableAIService: ObservableObject, @unchecked Sendable {
    static let shared = ConfigurableAIService()

    // private let log = OSLog(category: "ConfigurableAIService")

    // MARK: - Published Properties

//    @Published var textSearchProvider: TextSearchProvider = .defaultProvider
//    @Published var barcodeSearchProvider: BarcodeSearchProvider = .defaultProvider
//    @Published var aiImageSearchProvider: ImageSearchProvider = .defaultProvider

    private init() {
        // Load current settings
//        textSearchProvider = UserDefaults.standard.textSearchProvider
//        barcodeSearchProvider = UserDefaults.standard.barcodeSearchProvider
//        aiImageSearchProvider = UserDefaults.standard.aiImageProvider

        // Google Gemini API key should be configured by user
//        if UserDefaults.standard.googleGeminiAPIKey.isEmpty {
//            print("⚠️ Google Gemini API key not configured - user needs to set up their own key")
//        }
    }

//    func getProviderImplementation(
//        for provider: SearchProvider
//    ) throws -> FoodAnalysisService {
//        switch provider {
//        case .googleGemini: return GoogleGeminiFoodAnalysisService.shared
//        case .openAI: return OpenAIFoodAnalysisService.shared
//        case .claude: return ClaudeFoodAnalysisService.shared
//        case .openFoodFacts,
//             .usdaFoodData:
//            throw AIFoodAnalysisError.invalidResponse
//        }
//    }

    // MARK: - User Settings

    var isImageAnalysisConfigured: Bool {
        switch UserDefaults.standard.aiImageProvider {
        case .aiModel(.claude):
            return !UserDefaults.standard.claudeAPIKey.isEmpty
        case .aiModel(.gemini):
            return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
        case .aiModel(.openAI):
            return !UserDefaults.standard.openAIAPIKey.isEmpty
        }
    }

    var isTextSearchConfigured: Bool {
        switch UserDefaults.standard.textSearchProvider {
        case .aiModel(.claude):
            return !UserDefaults.standard.claudeAPIKey.isEmpty
        case .aiModel(.gemini):
            return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
        case .aiModel(.openAI):
            return !UserDefaults.standard.openAIAPIKey.isEmpty
        case .usdaFoodData:
            return true
        case .openFoodFacts:
            return true
        }
    }

    var isBarcodeSearchConfigured: Bool {
        switch UserDefaults.standard.barcodeSearchProvider {
//        case .aiModel(.claude):
//            return !UserDefaults.standard.claudeAPIKey.isEmpty
//        case .aiModel(.gemini):
//            return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
//        case .aiModel(.openAI):
//            return !UserDefaults.standard.openAIAPIKey.isEmpty
        case .openFoodFacts:
            return true
        }
    }

    // MARK: - Public Methods

    func setAPIKey(_ key: String, for provider: AIProvider) {
        switch provider {
        case .claude:
            UserDefaults.standard.claudeAPIKey = key
        case .gemini:
            UserDefaults.standard.googleGeminiAPIKey = key
        case .openAI:
            UserDefaults.standard.openAIAPIKey = key
        }
    }

    func getAPIKey(for provider: AIProvider) -> String? {
        switch provider {
        case .claude:
            let key = UserDefaults.standard.claudeAPIKey
            return key.isEmpty ? nil : key
        case .gemini:
            let key = UserDefaults.standard.googleGeminiAPIKey
            return key.isEmpty ? nil : key
        case .openAI:
            let key = UserDefaults.standard.openAIAPIKey
            return key.isEmpty ? nil : key
        }
    }

    /// Reset to default Basic Analysis provider (useful for troubleshooting)
    func resetToDefault() {
        UserDefaults.standard.aiImageProvider = .defaultProvider
        UserDefaults.standard.textSearchProvider = .defaultProvider
        UserDefaults.standard.barcodeSearchProvider = .defaultProvider
    }

    /// Analyze food image with telemetry callbacks for progress tracking
    func analyzeFoodImage(
        _ image: UIImage,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult {
        // Check cache first for instant results
        if let cachedResult = imageAnalysisCache.getCachedResult(for: image) {
            telemetryCallback?("📋 Found cached analysis result")
            return cachedResult
        }

//        telemetryCallback?("🎯 Selecting optimal AI provider …")
        // Use parallel processing if enabled
//        if enableParallelProcessing {
//            telemetryCallback?("⚡ Starting parallel provider analysis …")
//            let result = try await analyzeImageWithParallelProviders(image, telemetryCallback: telemetryCallback)
//            imageAnalysisCache.cacheResult(result, for: image)
//            return result
//        }

        telemetryCallback?("🤖 Connecting to \(UserDefaults.standard.aiImageProvider.description) …")
        let providerImpl = switch UserDefaults.standard.aiImageProvider {
        case let .aiModel(model):
            try getAIImplementation(
                for: model,
                telemetryCallback: telemetryCallback
            )
        }

        // Get the AI model for statistics tracking
        let aiModel = switch UserDefaults.standard.aiImageProvider {
        case let .aiModel(model):
            model
        }

        // Use average processing time from statistics, or fall back to default ETA
        if let stats = AIUsageStatistics.getStatistics(model: aiModel, requestType: .image),
           stats.averageSuccessProcessingTime > 0
        {
            let eta = String(format: "%.1f", stats.averageSuccessProcessingTime)
            telemetryCallback?("ETA: \(eta)")
        } else {
            telemetryCallback?("ETA: \(String(format: "%.0f", aiModel.defaultImageETA))")
        }
        telemetryCallback?("MODEL: \(aiModel.description)")

        telemetryCallback?("🖼️ Optimizing your image …")
        let base64Image = try ImageCompression.getImageBase64(
            for: image,
            aggressiveImageCompression: providerImpl.needAggressiveImageCompression,
            telemetryCallback: telemetryCallback
        )
        let analysisPrompt = AIPrompts.getAnalysisPrompt(.image(image), responseSchema: FoodAnalysisResult.schemaVisual)

        // Track processing time
        let startTime = Date()

        do {
            let result: FoodAnalysisResult = try await providerImpl.analyzeImage(
                prompt: analysisPrompt,
                images: [base64Image],
                telemetryCallback: telemetryCallback
            )

            // Record successful request statistics
            let processingTime = Date().timeIntervalSince(startTime)
            AIUsageStatistics.recordRequest(
                model: aiModel,
                requestType: .image,
                processingTime: processingTime,
                success: true,
                foodItemCount: result.foodItemsDetailed.count
            )

//            telemetryCallback?("💾 Caching analysis result …")
//            imageAnalysisCache.cacheResult(result, for: image)

            return result
        } catch {
            // Record failed request statistics
            let processingTime = Date().timeIntervalSince(startTime)
            AIUsageStatistics.recordRequest(
                model: aiModel,
                requestType: .image,
                processingTime: processingTime,
                success: false
            )
            throw error
        }
    }

    func analyzeFoodQuery(
        _ query: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult {
        telemetryCallback?("🤖 Connecting to \(UserDefaults.standard.textSearchProvider.description) …")
        switch UserDefaults.standard.textSearchProvider {
        case let .aiModel(model):
            let providerImpl = try getAIImplementation(for: model, telemetryCallback: telemetryCallback)
            let analysisPrompt = AIPrompts.getAnalysisPrompt(.query(query), responseSchema: FoodAnalysisResult.schemaText)

            // Use average processing time from statistics, or fall back to default ETA
            if let stats = AIUsageStatistics.getStatistics(model: model, requestType: .text),
               stats.averageSuccessProcessingTime > 0
            {
                let eta = String(format: "%.1f", stats.averageSuccessProcessingTime)
                telemetryCallback?("ETA: \(eta)")
            } else {
                telemetryCallback?("ETA: \(String(format: "%.1f", model.defaultTextETA))")
            }

            telemetryCallback?("MODEL: \(model.description)")

            // Track processing time
            let startTime = Date()

            do {
                let result = try await providerImpl.analyzeText(
                    prompt: analysisPrompt,
                    telemetryCallback: telemetryCallback
                )

                // Record successful request statistics
                let processingTime = Date().timeIntervalSince(startTime)
                AIUsageStatistics.recordRequest(
                    model: model,
                    requestType: .text,
                    processingTime: processingTime,
                    success: true,
                    foodItemCount: result.foodItemsDetailed.count
                )

                return result
            } catch {
                // Record failed request statistics
                let processingTime = Date().timeIntervalSince(startTime)
                AIUsageStatistics.recordRequest(
                    model: model,
                    requestType: .text,
                    processingTime: processingTime,
                    success: false
                )
                throw error
            }
        case .usdaFoodData:
            return try await USDAFoodDataService.shared.analyzeText(prompt: query, telemetryCallback: telemetryCallback)
        case .openFoodFacts:
            return try await OpenFoodFactsService.shared.analyzeText(prompt: query, telemetryCallback: telemetryCallback)
        }
    }

    func analyzeBarcode(
        _ barcode: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult {
        telemetryCallback?("🤖 Connecting to \(UserDefaults.standard.barcodeSearchProvider.description) …")
        switch UserDefaults.standard.barcodeSearchProvider {
        case .openFoodFacts:
            let result = try await OpenFoodFactsService.shared.analyzeBarcode(
                barcode: barcode,
                telemetryCallback: telemetryCallback
            )
            return result
        }
    }

    private func getApiKey(
        for model: AIModel,
        telemetryCallback _: ((String) -> Void)?
    ) throws -> String {
        let key: String
        switch model {
        case .gemini:
            key = UserDefaults.standard.googleGeminiAPIKey
            guard !key.isEmpty else {
                print("❌ Google Gemini API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }

        case .openAI:
            key = UserDefaults.standard.openAIAPIKey
            guard !key.isEmpty else {
                print("❌ OpenAI API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }

        case .claude:
            key = UserDefaults.standard.claudeAPIKey
            guard !key.isEmpty else {
                print("❌ Claude API key not configured")
                throw AIFoodAnalysisError.noApiKey
            }
        }
        return key
    }

    private func getAIImplementation(
        for model: AIModel,
        telemetryCallback: ((String) -> Void)?
    ) throws -> AIAnalysisService {
        let apiKey = try getApiKey(for: model, telemetryCallback: telemetryCallback)
        return AIAnalysisService.create(for: model, apiKey: apiKey)
    }

    // MARK: - Text Processing Helper Methods

    /// Centralized list of unwanted prefixes that AI commonly adds to food descriptions
    /// Add new prefixes here as edge cases are discovered - this is the SINGLE source of truth
    static let unwantedFoodPrefixes = [
        "of ",
        "with ",
        "contains ",
        "includes ",
        "featuring ",
        "consisting of ",
        "made of ",
        "composed of ",
        "a plate of ",
        "a bowl of ",
        "a serving of ",
        "a portion of ",
        "some ",
        "several ",
        "multiple ",
        "various ",
        "an ",
        "a ",
        "the ",
        "- ",
        "– ",
        "— ",
        "this is ",
        "there is ",
        "there are ",
        "i see ",
        "appears to be ",
        "looks like "
    ]

    /// Current analysis mode setting
//    @Published var analysisMode = AnalysisMode(rawValue: UserDefaults.standard.analysisMode) ?? .standard

    /// Enable parallel processing for fastest results
//    @Published var enableParallelProcessing: Bool = false

    /// Intelligent caching system for AI analysis results
    private var imageAnalysisCache = ImageAnalysisCache()

    /// Analyze image with network-aware provider strategy
//    func analyzeImageWithParallelProviders(
//        _ image: UIImage,
//        telemetryCallback: ((String) -> Void)?
//    ) async throws -> FoodAnalysisResult {
//        let networkMonitor = NetworkQualityMonitor.shared
//        telemetryCallback?("🌐 Analyzing network conditions …")
//
//        // Get available providers that support AI analysis
//        let availableProviders: [SearchProvider] = [.googleGemini, .openAI, .claude].filter { provider in
//            // Only include providers that have API keys configured
//            switch provider {
//            case .googleGemini:
//                return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
//            case .openAI:
//                return !UserDefaults.standard.openAIAPIKey.isEmpty
//            case .claude:
//                return !UserDefaults.standard.claudeAPIKey.isEmpty
//            default:
//                return false
//            }
//        }
//
//        guard !availableProviders.isEmpty else {
//            throw AIFoodAnalysisError.noApiKey
//        }
//
//        // Check network conditions and decide strategy
//        if networkMonitor.shouldUseParallelProcessing, availableProviders.count > 1 {
//            print("🌐 Good network detected, using parallel processing with \(availableProviders.count) providers")
//            telemetryCallback?("⚡ Starting parallel AI provider analysis …")
//            return try await analyzeImageWithParallelStrategy(
//                image,
//                providers: availableProviders,
//                telemetryCallback: telemetryCallback
//            )
//        } else {
//            print("🌐 Poor network detected, using sequential processing")
//            telemetryCallback?("🔄 Starting sequential AI provider analysis …")
//            return try await analyzeImageWithSequentialStrategy(
//                image,
//                providers: availableProviders,
//                telemetryCallback: telemetryCallback
//            )
//        }
//    }

    /// Parallel strategy for good networks
//    private func analyzeImageWithParallelStrategy(
//        _ image: UIImage,
//        providers: [SearchProvider],
//        telemetryCallback _: ((String) -> Void)?
//    ) async throws -> FoodAnalysisResult {
//        // Use the maximum timeout from all providers, with special handling for GPT-5
//        let timeout = providers.map { provider in
//            max(ConfigurableAIService.optimalTimeout(for: provider), NetworkQualityMonitor.shared.recommendedTimeout)
//        }.max() ?? NetworkQualityMonitor.shared.recommendedTimeout
//
//        return try await withThrowingTaskGroup(of: FoodAnalysisResult.self) { group in
//            // Add timeout wrapper for each provider
//            for provider in providers {
//                group.addTask { [weak self] in
//                    guard let self = self else { throw AIFoodAnalysisError.invalidResponse }
//                    return try await withTimeoutForAnalysis(seconds: timeout) {
//                        let startTime = Date()
//                        do {
//                            let result = try await self.analyzeImageWithSingleProvider(image, provider: provider)
//                            let duration = Date().timeIntervalSince(startTime)
//                            print("✅ \(provider.rawValue) succeeded in \(String(format: "%.1f", duration))s")
//                            return result
//                        } catch {
//                            let duration = Date().timeIntervalSince(startTime)
//                            print(
//                                "❌ \(provider.rawValue) failed after \(String(format: "%.1f", duration))s: \(error.localizedDescription)"
//                            )
//                            throw error
//                        }
//                    }
//                }
//            }
//
//            // Return the first successful result
//            guard let result = try await group.next() else {
//                throw AIFoodAnalysisError.invalidResponse
//            }
//
//            // Cancel remaining tasks since we got our result
//            group.cancelAll()
//
//            return result
//        }
//    }

    /// Sequential strategy for poor networks (photo) - tries providers one by one
//    private func analyzeImageWithSequentialStrategy(
//        _ image: UIImage,
//        providers: [SearchProvider],
//        telemetryCallback: ((String) -> Void)?
//    ) async throws -> FoodAnalysisResult {
//        // Use provider-specific timeout, with special handling for GPT-5
//        let baseTimeout = NetworkQualityMonitor.shared.recommendedTimeout
//        var lastError: Error?
//
//        // Try providers one by one until one succeeds
//        for provider in providers {
//            do {
//                // Use provider-specific timeout for each provider
//                let providerTimeout = max(ConfigurableAIService.optimalTimeout(for: provider), baseTimeout)
//                print("🔄 Trying \(provider.rawValue) sequentially with \(providerTimeout)s timeout...")
//                telemetryCallback?("🤖 Trying \(provider.rawValue) …")
//                let result = try await withTimeoutForAnalysis(seconds: providerTimeout) {
//                    try await self.analyzeImageWithSingleProvider(image, provider: provider)
//                }
//                print("✅ \(provider.rawValue) succeeded in sequential mode")
//                return result
//            } catch {
//                print("❌ \(provider.rawValue) failed in sequential mode: \(error.localizedDescription)")
//                lastError = error
//                // Continue to next provider
//            }
//        }
//
//        // If all providers failed, throw the last error
//        throw lastError ?? AIFoodAnalysisError.invalidResponse
//    }

    /// Analyze photo with a single provider (helper for parallel processing)
//    private func analyzeImageWithSingleProvider(
//        _ image: UIImage,
//        provider: SearchProvider
//    ) async throws -> FoodAnalysisResult {
//        let providerImpl = try getProviderImplementation(for: provider)
//        return try await providerImpl.analyzeFoodImage(
//            image,
//            apiKey: UserDefaults.standard.googleGeminiAPIKey,
//            telemetryCallback: nil
//        )
//    }

    /// Analyze text query with a single provider (helper for parallel processing)
//    private func analyzeQueryWithSingleProvider(
//        _ query: String,
//        provider: SearchProvider
//    ) async throws -> FoodAnalysisResult {
//        let providerImpl = try getProviderImplementation(for: provider)
//        return try await providerImpl.analyzeFoodQuery(
//            query,
//            apiKey: UserDefaults.standard.googleGeminiAPIKey,
//            telemetryCallback: nil
//        )
//    }

    /// Public static method to clean food text - can be called from anywhere
    static func cleanFoodText(_ text: String?) -> String? {
        guard let text = text else { return nil }

        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Keep removing prefixes until none match (handles multiple prefixes)
        var foundPrefix = true
        var iterationCount = 0
        while foundPrefix, iterationCount < 10 { // Prevent infinite loops
            foundPrefix = false
            iterationCount += 1

            for prefix in unwantedFoodPrefixes {
                if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    foundPrefix = true
                    break
                }
            }
        }

        // Capitalize first letter
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? nil : cleaned
    }

    /// Cleans AI description text by removing unwanted prefixes and ensuring proper capitalization
    private func cleanAIDescription(_ description: String?) -> String? {
        Self.cleanFoodText(description)
    }
}

// MARK: - Timeout Helper

/// Timeout wrapper for async operations
func withTimeoutForAnalysis<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the actual operation
        group.addTask {
            try await operation()
        }

        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AIFoodAnalysisError.timeout as Error
        }

        // Return first result (either success or timeout)
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw AIFoodAnalysisError.timeout as Error
        }
        return result
    }
}
