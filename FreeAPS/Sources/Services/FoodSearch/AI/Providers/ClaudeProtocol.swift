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
        responseSchema: AIResponseSchema?,
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

        // Structured outputs are deliberately NOT used: Anthropic caps a schema at 24 optional
        // properties (and at 24 nullable unions in the strict form), and the food item alone has
        // about 40 optional nutrition fields. Making them required would turn "unknown" into 0.
        // Claude follows the example object in the prompt reliably; the schema is kept only for
        // the parameter so the request shape stays uniform across providers.
        _ = responseSchema
        let schema: OrderedJSON? = nil
        let outputFormat = schema.map { ClaudeOutputFormat(type: "json_schema", schema: $0) }
        let outputConfig: ClaudeOutputConfig? = model.effort == nil && outputFormat == nil
            ? nil
            : ClaudeOutputConfig(effort: model.effort, format: outputFormat)

        let body = ClaudeMessagesRequest(
            model: model,
            // Thinking tokens count against this limit on the 5.5 models, so leave headroom.
            max_tokens: 16000,
            temperature: model.temperature,
            output_config: outputConfig,
            messages: messages
        )

        do {
            request.httpBody = try OrderedJSON.encode(body, splicing: [schema])
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

                // A rejected request is a bug on our side (schema, parameters), never a quota problem:
                // report Anthropic's message instead of pattern-matching words like "limit" in it.
                if type == "invalid_request_error" {
                    throw AIFoodAnalysisError.customError("Claude rejected the request: \(message)")
                }

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

        switch claudeResponse.stop_reason {
        case "max_tokens":
            let usage = claudeResponse.usage
            debug(
                .service,
                "Claude output was cut off at max_tokens (output tokens: \(usage?.output_tokens ?? -1), input: \(usage?.input_tokens ?? -1)); the JSON is incomplete"
            )
            throw AIFoodAnalysisError
                .customError("The Claude response was cut off before the analysis was complete. Please try again.")
        case "refusal":
            debug(.service, "Claude declined the request (stop_reason: refusal): \(String(decoding: data, as: UTF8.self))")
            throw AIFoodAnalysisError.customError("Claude declined to analyze this request. Please try another photo or model.")
        default:
            break
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
    let output_config: ClaudeOutputConfig?
    let messages: [ClaudeMessage]
}

private struct ClaudeOutputConfig: Encodable {
    let effort: String?
    let format: ClaudeOutputFormat?
}

private struct ClaudeOutputFormat: Encodable {
    let type: String
    let schema: OrderedJSON
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
    let stop_reason: String?
    let usage: ClaudeUsage?
}

private struct ClaudeUsage: Decodable {
    let input_tokens: Int?
    let output_tokens: Int?
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
