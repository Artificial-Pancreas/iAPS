import CoreML
import CryptoKit
import Foundation
import LoopKit
import Network
import os.log
import SwiftUI
import UIKit
import Vision

struct OpenAIProtocol: AIProviderProtocol {
    private let apiURL = URL(string: "https://api.openai.com/v1/responses")!

    let model: OpenAIModel
    let apiKey: String

    var timeoutsConfig: ModelTimeoutsConfig { model.timeoutsConfig }

    var numberOfRetries: Int { 1 }

    var needAggressiveImageCompression: Bool { model.needAggressiveImageCompression }

    func buildRequest(
        prompt: String,
        images: [String],
        telemetryCallback _: ((String) -> Void)?
    ) throws -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        print("🔍 OpenAI Final Prompt Debug:")
        print("   Analysis prompt length: \(prompt.count) characters")
        print("   First 100 chars of analysis prompt: \(String(prompt.prefix(100)))")

        let textPart = OpenAIResponsesContent.input_text(text: prompt)
        let imageParts = images.map {
            OpenAIResponsesContent.input_image(imageURL: "data:image/jpeg;base64,\($0)")
        }

        let inputMessages: [OpenAIResponsesMessage] = [
            OpenAIResponsesMessage(role: "user", content: [textPart] + imageParts)
        ]

        var textOptions: OpenAIResponsesTextOptions?
        var stream: Bool?
        if model.isGPT5 {
            textOptions = OpenAIResponsesTextOptions(format: .init(type: "json_object"))
            stream = false // Ensure complete response (no streaming)
        }

        let body = OpenAIResponsesRequest(
            model: model,
            input: inputMessages,
            max_output_tokens: 6000,
            temperature: model.temperature,
            text: textOptions,
            stream: stream
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
        // Decode error response JSON at the top of non-200 error block
        if httpResponse.statusCode != 200 {
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                let message = apiError.error.message ?? "Unknown error"
                let code = apiError.error.code ?? apiError.error.type ?? ""
                print("❌ OpenAI API Error: code=\(code), message=\(message)")

                switch code {
                case "insufficient_quota":
                    throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
                case "rate_limit_exceeded":
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
                case "invalid_api_key":
                    throw AIFoodAnalysisError.customError("Invalid OpenAI API key. Please check your configuration.")
                case "model_not_found":
                    throw AIFoodAnalysisError.customError(
                        "Model not found."
                    )
                default:
                    // Fallback to message inspection for unknown codes
                    if message.localizedCaseInsensitiveContains("quota") {
                        throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
                    } else if message.localizedCaseInsensitiveContains("rate limit") {
                        throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
                    } else if message.localizedCaseInsensitiveContains("invalid"),
                              message.localizedCaseInsensitiveContains("key")
                    {
                        throw AIFoodAnalysisError.customError("Invalid OpenAI API key. Please check your configuration.")
                    } else if message.localizedCaseInsensitiveContains("model"),
                              message.localizedCaseInsensitiveContains("not found")
                    {
                        throw AIFoodAnalysisError.customError(
                            "Model not found."
                        )
                    }
                }
            } else {
                print("❌ OpenAI: Error data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            }

            // Handle HTTP status codes for common credit/quota issues
            if httpResponse.statusCode == 429 {
                throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
            } else if httpResponse.statusCode == 402 {
                throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
            } else if httpResponse.statusCode == 403 {
                throw AIFoodAnalysisError.quotaExceeded(provider: "OpenAI")
            }

            // Generic API error for unhandled cases
            throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
        }
    }

    func extractResponse(
        data: Data,
        telemetryCallback: ((String) -> Void)?
    ) throws -> String {
        let decoder = JSONDecoder()
        let responsesPayload = try decoder.decode(OpenAIResponsesResponse.self, from: data)

        guard let content = extractContent(from: responsesPayload), !content.isEmpty else {
            print("❌ \(model): Could not extract content from /responses payload (struct)")
            print("❌ \(model): Response payload: \(responsesPayload)")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        // Add detailed logging like Gemini
        print("🔧 \(model): Received content length: \(content.count)")

        if content.isEmpty {
            print("❌ \(model): Empty content received")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        // Enhanced JSON extraction from GPT-4's response (like Claude service)
        telemetryCallback?("⚡ Processing AI analysis results …")

        return content
    }

    // Unified content extraction for /responses
    // Priority order:
    // 1) output_text (string)
    // 2) output (array of segments with type/text)
    // 3) content (array) with items that may contain text or nested message content
    private func extractContent(from payload: OpenAIResponsesResponse) -> String? {
        // Case 1: output_text
        if let outputText = payload.output_text, !outputText.isEmpty {
            return outputText
        }

        // Case 2: output array of messages with nested content
        if let output = payload.output, !output.isEmpty {
            var parts: [String] = []
            for message in output {
                if let items = message.content {
                    for item in items {
                        if let t = item.text, item.type == nil || item.type == "output_text" {
                            parts.append(t)
                        }
                    }
                }
            }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }

        // Case 3: content array
        if let contentArr = payload.content, !contentArr.isEmpty {
            let parts = contentArr.compactMap { $0.text ?? $0.message?.content }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }

        return nil
    }
}

// Request
private struct OpenAIResponsesRequest: Encodable {
    let model: OpenAIModel
    let input: [OpenAIResponsesMessage]
    let max_output_tokens: Int
    let temperature: Double?
    let text: OpenAIResponsesTextOptions?
    let stream: Bool?
}

private struct OpenAIResponsesTextOptions: Encodable {
    struct Format: Encodable { let type: String }
    let format: Format
}

private struct OpenAIResponsesMessage: Encodable {
    let role: String
    let content: [OpenAIResponsesContent]
}

private enum OpenAIResponsesContent: Encodable {
    case input_text(text: String)
    case input_image(imageURL: String)

    enum CodingKeys: String, CodingKey { case type, text, image_url }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .input_text(text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .input_image(imageURL):
            try container.encode("input_image", forKey: .type)
            try container.encode(imageURL, forKey: .image_url)
        }
    }
}

// Response
private struct OpenAIResponsesResponse: Decodable {
    let output_text: String?
    let output: [OpenAIResponsesMessageOutput]?
    let content: [OpenAIResponsesContentItem]?
}

private struct OpenAIResponsesMessageOutput: Decodable {
    let id: String?
    let type: String? // e.g., "message"
    let status: String?
    let role: String?
    let content: [OpenAIResponsesOutputContent]?
}

private struct OpenAIResponsesOutputContent: Decodable {
    let type: String? // e.g., "output_text"
    let text: String?
}

private struct OpenAIResponsesContentItem: Decodable {
    let type: String?
    let text: String?
    let message: OpenAIResponsesMessagePayload?
}

private struct OpenAIResponsesMessagePayload: Decodable {
    let content: String?
}

// Error Response
private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
        let type: String?
        let param: String?
        let code: String?
    }

    let error: APIError
}
