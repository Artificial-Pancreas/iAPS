import Foundation

/// Errors that can occur during AI food analysis
enum AIFoodAnalysisError: Error, LocalizedError {
    case imageProcessingFailed
    case requestCreationFailed
    case networkError(Error)
    case invalidResponse
    case apiError(Int)
    case responseParsingFailed
    case noApiKey
    case customError(String)
    case creditsExhausted(provider: String)
    case rateLimitExceeded(provider: String)
    case quotaExceeded(provider: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return NSLocalizedString("Failed to process image for analysis", comment: "Error when image processing fails")
        case .requestCreationFailed:
            return NSLocalizedString("Failed to create analysis request", comment: "Error when request creation fails")
        case let .networkError(error):
            return String(
                format: NSLocalizedString("Network error: %@", comment: "Error for network failures"),
                error.localizedDescription
            )
        case .invalidResponse:
            return NSLocalizedString("Invalid response from AI service", comment: "Error for invalid API response")
        case let .apiError(code):
            if code == 400 {
                return NSLocalizedString(
                    "Invalid API request (400). Please check your API key configuration in Food Search Settings.",
                    comment: "Error for 400 API failures"
                )
            } else if code == 403 {
                return NSLocalizedString(
                    "API access forbidden (403). Your API key may be invalid or you've exceeded your quota.",
                    comment: "Error for 403 API failures"
                )
            } else if code == 404 {
                return NSLocalizedString(
                    "AI service not found (404). Please check your API configuration.",
                    comment: "Error for 404 API failures"
                )
            } else {
                return String(format: NSLocalizedString("AI service error (code: %d)", comment: "Error for API failures"), code)
            }
        case .responseParsingFailed:
            return NSLocalizedString("Failed to parse AI analysis results", comment: "Error when response parsing fails")
        case .noApiKey:
            return NSLocalizedString(
                "No API key configured. Please go to Food Search Settings to set up your API key.",
                comment: "Error when API key is missing"
            )
        case let .customError(message):
            return message
        case let .creditsExhausted(provider):
            return String(
                format: NSLocalizedString(
                    "%@ credits exhausted. Please check your account billing or add credits to continue using AI food analysis.",
                    comment: "Error when AI provider credits are exhausted"
                ),
                provider
            )
        case let .rateLimitExceeded(provider):
            return String(
                format: NSLocalizedString(
                    "%@ rate limit exceeded. Please wait a moment before trying again.",
                    comment: "Error when AI provider rate limit is exceeded"
                ),
                provider
            )
        case let .quotaExceeded(provider):
            return String(
                format: NSLocalizedString(
                    "%@ quota exceeded. Please check your usage limits or upgrade your plan.",
                    comment: "Error when AI provider quota is exceeded"
                ),
                provider
            )
        case .timeout:
            return NSLocalizedString(
                "Analysis timed out. Please check your network connection and try again.",
                comment: "Error when AI analysis times out"
            )
        }
    }
}
