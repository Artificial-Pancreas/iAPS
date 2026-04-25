import Foundation

struct GeminiProtocol: AIProviderProtocol {
    private let baseURLTemplate = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

    let model: GeminiModel
    let apiKey: String

    var timeoutsConfig: ModelTimeoutsConfig { model.timeoutsConfig }

    var numberOfRetries: Int { 1 }

    func buildRequest(
        prompt: String,
        images: [String],
        telemetryCallback _: ((String) -> Void)?
    ) throws -> URLRequest {
        let baseURL = baseURLTemplate.replacingOccurrences(of: "{model}", with: model.rawValue)

        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw AIFoodAnalysisError.requestCreationFailed
        }

        let userTextPart = GeminiPart(text: prompt)
        let imageParts = images.map {
            GeminiPart(inline_data: GeminiInlineData(mime_type: "image/jpeg", data: $0))
        }

        let geminiRequest = GeminiGenerateContentRequest(
            contents: [GeminiContent(parts: [userTextPart] + imageParts)],
            generationConfig: GeminiGenerationConfig(
                temperature: model.temperature,
                topP: 0.95,
                topK: 8,
                maxOutputTokens: 8000
            )
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(geminiRequest)
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
            if let apiError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                let message = apiError.error.message
                let status = apiError.error.status ?? ""
                debug(.service, "Gemini API error \(httpResponse.statusCode): \(message) [status: \(status)]")

                if message.localizedCaseInsensitiveContains("quota") ||
                    message.localizedCaseInsensitiveContains("QUOTA_EXCEEDED") ||
                    status.localizedCaseInsensitiveContains("QUOTA_EXCEEDED")
                {
                    throw AIFoodAnalysisError.quotaExceeded(provider: "Google Gemini")
                } else if message.localizedCaseInsensitiveContains("RATE_LIMIT_EXCEEDED") ||
                    message.localizedCaseInsensitiveContains("rate limit") ||
                    status.localizedCaseInsensitiveContains("RATE_LIMIT_EXCEEDED")
                {
                    throw AIFoodAnalysisError.rateLimitExceeded(provider: "Google Gemini")
                } else if message.localizedCaseInsensitiveContains("PERMISSION_DENIED") ||
                    message.localizedCaseInsensitiveContains("API_KEY_INVALID") ||
                    status.localizedCaseInsensitiveContains("PERMISSION_DENIED")
                {
                    throw AIFoodAnalysisError
                        .customError("Invalid Google Gemini API key. Please check your configuration.")
                } else if message.localizedCaseInsensitiveContains("RESOURCE_EXHAUSTED") ||
                    status.localizedCaseInsensitiveContains("RESOURCE_EXHAUSTED")
                {
                    throw AIFoodAnalysisError.creditsExhausted(provider: "Google Gemini")
                }
            } else {
                debug(.service, "Gemini API error \(httpResponse.statusCode) (response body not decodable as error JSON)")
            }

            if httpResponse.statusCode == 429 {
                throw AIFoodAnalysisError.rateLimitExceeded(provider: "Google Gemini")
            } else if httpResponse.statusCode == 403 {
                throw AIFoodAnalysisError.quotaExceeded(provider: "Google Gemini")
            }

            throw AIFoodAnalysisError.apiError(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            debug(.service, "Gemini returned an empty response body")
            throw AIFoodAnalysisError.invalidResponse
        }
    }

    func extractResponse(
        data: Data,
        telemetryCallback _: ((String) -> Void)?
    ) throws -> String {
        let geminiResponse: GeminiGenerateContentResponse
        do {
            geminiResponse = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        } catch {
            debug(.service, "Failed to decode Gemini response: \(error)\n\(String(decoding: data, as: UTF8.self))")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        guard let firstCandidate = geminiResponse.candidates?.first else {
            debug(.service, "Gemini response contains no candidates: \(String(decoding: data, as: UTF8.self))")
            throw AIFoodAnalysisError.responseParsingFailed
        }

        let parts: [GeminiPartResponse] = firstCandidate.content?.parts ?? []
        let text = parts
            .compactMap(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            debug(
                .service,
                "Gemini candidates produced no text content (finishReason: \(firstCandidate.finishReason ?? "nil")): \(String(decoding: data, as: UTF8.self))"
            )
            throw AIFoodAnalysisError.responseParsingFailed
        }

        return text
    }
}

// Request payload
private struct GeminiGenerateContentRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String?
    let inline_data: GeminiInlineData?

    init(text: String) {
        self.text = text
        inline_data = nil
    }

    init(inline_data: GeminiInlineData) {
        text = nil
        self.inline_data = inline_data
    }
}

private struct GeminiInlineData: Encodable {
    let mime_type: String
    let data: String
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double?
    let topP: Double
    let topK: Int
    let maxOutputTokens: Int
}

// Response payload
private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContentResponse?
    let finishReason: String?
}

private struct GeminiContentResponse: Decodable {
    let parts: [GeminiPartResponse]?
}

private struct GeminiPartResponse: Decodable {
    let text: String?
}

// Error payload
private struct GeminiErrorResponse: Decodable {
    struct APIError: Decodable {
        let code: Int?
        let message: String
        let status: String?
    }

    let error: APIError
}
