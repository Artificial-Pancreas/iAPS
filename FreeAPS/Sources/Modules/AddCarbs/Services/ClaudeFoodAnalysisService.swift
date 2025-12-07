import CoreML
import CryptoKit
import Foundation
import LoopKit
import Network
import os.log
import SwiftUI
import UIKit
import Vision

struct ClaudeProtocol: AIProviderProtocol {
    private let url = URL(string: "https://api.anthropic.com/v1/messages")!

    let model: ClaudeModel
    let apiKey: String

    var timeoutsConfig: ModelTimeoutsConfig { model.timeoutsConfig }

    var numberOfRetries: Int { 1 }

    var needAggressiveImageCompression: Bool { model.needAggressiveImageCompression }

    func buildRequest(
        prompt: String,
        images: [String],
        telemetryCallback _: ((String) -> Void)?
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let textPart = ClaudeContent.text(text: prompt)
        let imageParts = images.map {
            ClaudeContent.image(
                source: ClaudeImageSource(type: "base64", media_type: "image/jpeg", data: $0)
            )
        }

        let messages: [ClaudeMessage] = [
            ClaudeMessage(
                role: "user",
                content: [textPart] + imageParts
            )
        ]

        let body = ClaudeMessagesRequest(
            model: model,
            max_tokens: 8000,
            temperature: 0.01,
            messages: messages
        )

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        } catch {
            throw AIFoodAnalysisError.requestCreationFailed
        }

        return request
    }

    func handleErrorResponse(
        httpResponse: HTTPURLResponse,
        data: Data,
        telemetryCallback _: ((String) -> Void)?
    ) throws {
        guard httpResponse.statusCode == 200 else {
            if let apiError = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
                let message = apiError.error.message
                let type = apiError.error.type ?? ""
                print("❌ Claude API Error: type=\(type), message=\(message)")

                // Handle common Claude errors with specific error types
                if message.localizedCaseInsensitiveContains("credit") || message
                    .localizedCaseInsensitiveContains("billing") || message.localizedCaseInsensitiveContains("usage")
                {
                    throw AIFoodAnalysisError.creditsExhausted(provider: "Claude")
                } else if message.localizedCaseInsensitiveContains("rate_limit") || message
                    .localizedCaseInsensitiveContains("rate limit")
                {
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "Claude")
                } else if message.localizedCaseInsensitiveContains("quota") || message.localizedCaseInsensitiveContains("limit") {
                    throw AIFoodAnalysisError.quotaExceeded(provider: "Claude")
                } else if message
                    .localizedCaseInsensitiveContains("authentication") ||
                    (message.localizedCaseInsensitiveContains("invalid") && message.localizedCaseInsensitiveContains("key"))
                {
                    throw AIFoodAnalysisError.customError("Invalid Claude API key. Please check your configuration.")
                }
            } else {
                print("❌ Claude: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            }

            // Handle HTTP status codes for common credit/quota issues
            if httpResponse.statusCode == 429 {
                throw AIFoodAnalysisError.rateLimitExceeded(provider: "Claude")
            } else if httpResponse.statusCode == 402 {
                throw AIFoodAnalysisError.creditsExhausted(provider: "Claude")
            } else if httpResponse.statusCode == 403 {
                throw AIFoodAnalysisError.quotaExceeded(provider: "Claude")
            }

            throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
        }

        // Enhanced data validation like Gemini
        guard !data.isEmpty else {
            print("❌ Claude: Empty response data")
            throw AIFoodAnalysisError.invalidResponse
        }
    }

    func extractResponse(
        data: Data,
        telemetryCallback _: ((String) -> Void)?
    ) throws -> String {
        let decoder = JSONDecoder()
        let claudeResponse = try decoder.decode(ClaudeMessagesResponse.self, from: data)

        guard let contentItems = claudeResponse.content, !contentItems.isEmpty else {
            print("❌ Claude: Invalid response structure - no content items")
            if let raw = String(data: data, encoding: .utf8) {
                print("❌ Claude: Raw response: \(raw)")
            }
            throw AIFoodAnalysisError.responseParsingFailed
        }

        // Extract first text segment from content
        guard let text = contentItems.first(where: { ($0.type == nil || $0.type == "text") && ($0.text?.isEmpty == false) })?
            .text
        else {
            print("❌ Claude: No text content in response")
            if let raw = String(data: data, encoding: .utf8) {
                print("❌ Claude: Raw response: \(raw)")
            }
            throw AIFoodAnalysisError.responseParsingFailed
        }

        print("🔧 Claude: Received text length: \(text.count)")

        return text
    }
}

// MARK: - Claude / Anthropic Codable Models (Request/Response/Error)

// Request
private struct ClaudeMessagesRequest: Encodable {
    let model: ClaudeModel
    let max_tokens: Int
    let temperature: Double
    let messages: [ClaudeMessage]
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: [ClaudeContent]
}

private enum ClaudeContent: Encodable {
    case text(text: String)
    case image(source: ClaudeImageSource)

    enum CodingKeys: String, CodingKey { case type, text, source }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        }
    }
}

private struct ClaudeImageSource: Encodable {
    let type: String // "base64"
    let media_type: String // e.g., "image/jpeg"
    let data: String // base64-encoded image
}

// Response
private struct ClaudeMessagesResponse: Decodable {
    let content: [ClaudeMessageContent]?
}

private struct ClaudeMessageContent: Decodable {
    let type: String?
    let text: String?
}

// Error Response
private struct ClaudeErrorResponse: Decodable {
    struct APIError: Decodable {
        let type: String?
        let message: String
        let code: String?
    }

    let error: APIError
}
