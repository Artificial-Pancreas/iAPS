import Foundation

struct OpenAIProtocol: AIProviderProtocol {
    private let apiURL = URL(string: "https://api.openai.com/v1/responses")!

    let model: OpenAIModel
    let apiKey: String

    var timeoutsConfig: ModelTimeoutsConfig { model.timeoutsConfig }

    var numberOfRetries: Int { 1 }

    func buildRequest(
        prompt: String,
        images: [String],
        telemetryCallback _: ((String) -> Void)?
    ) throws -> URLRequest {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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
            stream = false
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
        if httpResponse.statusCode != 200 {
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                let message = apiError.error.message ?? "Unknown error"
                let code = apiError.error.code ?? apiError.error.type ?? ""
                debug(.service, "OpenAI API error \(httpResponse.statusCode): \(message) [code: \(code)]")

                switch code {
                case "insufficient_quota":
                    throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
                case "rate_limit_exceeded":
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
                case "invalid_api_key":
                    throw AIFoodAnalysisError.customError("Invalid OpenAI API key. Please check your configuration.")
                case "model_not_found":
                    throw AIFoodAnalysisError.customError("Model not found.")
                default:
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
                        throw AIFoodAnalysisError.customError("Model not found.")
                    }
                }
            } else {
                debug(.service, "OpenAI API error \(httpResponse.statusCode) (response body not decodable as error JSON)")
            }

            if httpResponse.statusCode == 429 {
                throw AIFoodAnalysisError.rateLimitExceeded(provider: "OpenAI")
            } else if httpResponse.statusCode == 402 {
                throw AIFoodAnalysisError.creditsExhausted(provider: "OpenAI")
            } else if httpResponse.statusCode == 403 {
                throw AIFoodAnalysisError.quotaExceeded(provider: "OpenAI")
            }

            throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
        }
    }

    func extractResponse(
        data: Data,
        telemetryCallback _: ((String) -> Void)?
    ) throws -> String {
        let responsesPayload: OpenAIResponsesResponse
        do {
            responsesPayload = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data)
        } catch {
            debug(.service, "Failed to decode OpenAI response: \(error): \(String(decoding: data, as: UTF8.self))")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        guard let content = extractContent(from: responsesPayload), !content.isEmpty else {
            debug(
                .service,
                "Could not extract text content from OpenAI response payload: \(String(decoding: data, as: UTF8.self))"
            )
            throw AIFoodAnalysisError.responseParsingFailed
        }

        return content
    }

    // Unified content extraction for /responses
    // Priority order:
    // 1) output_text (string)
    // 2) output (array of segments with type/text)
    // 3) content (array) with items that may contain text or nested message content
    private func extractContent(from payload: OpenAIResponsesResponse) -> String? {
        if let outputText = payload.output_text, !outputText.isEmpty {
            return outputText
        }

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
    let type: String?
    let status: String?
    let role: String?
    let content: [OpenAIResponsesOutputContent]?
}

private struct OpenAIResponsesOutputContent: Decodable {
    let type: String?
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
