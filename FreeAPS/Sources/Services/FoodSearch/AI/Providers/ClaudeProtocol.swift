import Foundation

struct ClaudeProtocol: AIProviderProtocol {
    private let url = URL(string: "https://api.anthropic.com/v1/messages")!

    let model: ClaudeModel
    let apiKey: String

    var timeoutsConfig: ModelTimeoutsConfig { model.timeoutsConfig }

    var numberOfRetries: Int { 1 }

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
            temperature: model.temperature,
            messages: messages
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
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
                debug(.service, "Claude API error \(httpResponse.statusCode): \(message) [type: \(type)]")

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
                debug(.service, "Claude API error \(httpResponse.statusCode) (response body not decodable as error JSON)")
            }

            if httpResponse.statusCode == 429 {
                throw AIFoodAnalysisError.rateLimitExceeded(provider: "Claude")
            } else if httpResponse.statusCode == 402 {
                throw AIFoodAnalysisError.creditsExhausted(provider: "Claude")
            } else if httpResponse.statusCode == 403 {
                throw AIFoodAnalysisError.quotaExceeded(provider: "Claude")
            }

            throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            print("Claude returned an empty response body")
            throw AIFoodAnalysisError.invalidResponse
        }
    }

    func extractResponse(
        data: Data,
        telemetryCallback _: ((String) -> Void)?
    ) throws -> String {
        let claudeResponse: ClaudeMessagesResponse
        do {
            claudeResponse = try JSONDecoder().decode(ClaudeMessagesResponse.self, from: data)
        } catch {
            debug(.service, "Failed to decode Claude response: \(error): \(String(decoding: data, as: UTF8.self))")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        guard let contentItems = claudeResponse.content, !contentItems.isEmpty else {
            debug(.service, "Claude response contains no content items: \(String(decoding: data, as: UTF8.self))")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        guard let text = contentItems
            .first(where: { ($0.type == nil || $0.type == "text") && ($0.text?.isEmpty == false) })?
            .text
        else {
            debug(.service, "Claude response has no text content block: \(String(decoding: data, as: UTF8.self))")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        return text
    }
}

// MARK: - Claude / Anthropic Codable Models (Request/Response/Error)

// Request
private struct ClaudeMessagesRequest: Encodable {
    let model: ClaudeModel
    let max_tokens: Int
    let temperature: Double?
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
