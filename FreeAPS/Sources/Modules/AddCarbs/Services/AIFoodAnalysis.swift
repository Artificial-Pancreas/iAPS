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

    private init() {}

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

    var isAiTextAnalysisConfigured: Bool {
        switch UserDefaults.standard.aiTextProvider {
        case .aiModel(.claude):
            return !UserDefaults.standard.claudeAPIKey.isEmpty
        case .aiModel(.gemini):
            return !UserDefaults.standard.googleGeminiAPIKey.isEmpty
        case .aiModel(.openAI):
            return !UserDefaults.standard.openAIAPIKey.isEmpty
        }
    }

    var isBarcodeSearchConfigured: Bool {
        switch UserDefaults.standard.barcodeSearchProvider {
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
    ) async throws -> FoodItemGroup {
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
        let base64Image = try await ImageCompression.getImageBase64(
            for: image,
            aggressiveImageCompression: providerImpl.needAggressiveImageCompression,
            maxSize: UserDefaults.standard.shouldSendSmallerImagesToAI ? 1024 : aiModel.maxImageDimension
        )
        let analysisPrompt = try AIPrompts.getAnalysisPrompt(.image(image), responseSchema: AIAnalysisResult.schemaVisual)

        // Track processing time
        let startTime = Date()

        do {
            let result: FoodItemGroup = try await providerImpl.analyzeImage(
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

    func executeTextSearch(
        _ query: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup {
        telemetryCallback?("🤖 Connecting to \(UserDefaults.standard.textSearchProvider.description) …")
        switch UserDefaults.standard.textSearchProvider {
        case .usdaFoodData:
            return try await USDAFoodDataService.shared.analyzeText(prompt: query, telemetryCallback: telemetryCallback)
        case .openFoodFacts:
            return try await OpenFoodFactsService.shared.analyzeText(prompt: query, telemetryCallback: telemetryCallback)
        }
    }

    func executeImageSearch(
        _ query: String,
        telemetryCallback: ((String) -> Void)?
    ) async -> [String] {
        let result = try? await OpenFoodFactsService.shared.analyzeText(prompt: query, telemetryCallback: telemetryCallback)
        return result?.foodItemsDetailed.compactMap(\.imageURL) ?? []
    }

    func analyzeFoodQuery(
        _ query: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup {
        telemetryCallback?("🤖 Connecting to \(UserDefaults.standard.textSearchProvider.description) …")
        switch UserDefaults.standard.aiTextProvider {
        case let .aiModel(model):
            let providerImpl = try getAIImplementation(for: model, telemetryCallback: telemetryCallback)
            let analysisPrompt = try AIPrompts.getAnalysisPrompt(.query(query), responseSchema: AIAnalysisResult.schemaText)

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
        }
    }

    func analyzeBarcode(
        _ barcode: String,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> FoodItemGroup {
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
}
