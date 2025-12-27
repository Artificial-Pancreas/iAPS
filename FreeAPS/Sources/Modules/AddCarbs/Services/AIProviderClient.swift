import Foundation

struct AIProviderClient: Sendable {
    private let proto: AIProviderProtocol

    init(proto: AIProviderProtocol) {
        self.proto = proto
    }

    func executeQuery(
        prompt: String,
        images: [String],
        telemetryCallback: ((String) -> Void)?
    ) async throws -> String {
        telemetryCallback?("📡 Preparing API request …")

        var urlRequest: URLRequest = try proto.buildRequest(
            prompt: prompt,
            images: images,
            telemetryCallback: telemetryCallback
        )

        urlRequest.timeoutInterval = proto.timeoutsConfig.requestTimeoutInterval
        print("🔧 Timeout - \(urlRequest.timeoutInterval)s, Prompt: \(prompt.count) chars")

        telemetryCallback?("🌐 Sending request …")
        do {
            telemetryCallback?("⏳ Waiting for response from AI …")

            #if DEBUG
                if let promptData = prompt.data(using: .utf8) {
                    saveDebugDataToTempFile(description: "AI prompt", fileName: "ai-prompt.txt", data: promptData)
                }
            #endif

            let (data, response): (Data, URLResponse) = try await performRequestWithRetry(
                request: urlRequest,
                telemetryCallback: telemetryCallback
            )

            saveDebugDataToTempFile(description: "AI response", fileName: "ai-response.txt", data: data)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                throw AIFoodAnalysisError.invalidResponse
            }

            try proto.handleErrorResponse(httpResponse: httpResponse, data: data, telemetryCallback: telemetryCallback)

            guard !data.isEmpty else {
                print("❌ Empty response data")
                throw AIFoodAnalysisError.invalidResponse
            }

            telemetryCallback?("🔍 Parsing AI response …")

            let content = try proto.extractResponse(data: data, telemetryCallback: telemetryCallback)

            telemetryCallback?("⚡ Processing AI analysis results …")

            return content
        } catch let error as AIFoodAnalysisError {
            throw error
        } catch {
            throw AIFoodAnalysisError.networkError(error)
        }
    }

    private func createSession() -> URLSession {
        let timeouts = proto.timeoutsConfig
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeouts.timeoutIntervalForRequest
        config.timeoutIntervalForResource = timeouts.timeoutIntervalForResource
        return URLSession(configuration: config)
    }

    private func performRequest(
        request: URLRequest,
        attempt: Int,
        maxRetries: Int,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> (Data, URLResponse) {
        do {
            print("🔧 Attempt \(attempt)/\(maxRetries)")
            if attempt != 1 {
                telemetryCallback?("🔄 Attempt \(attempt)/\(maxRetries) …")
            }

            let session = createSession()

            do {
                let (data, response) = try await session.data(for: request)

                print("🔧 Request succeeded on attempt \(attempt)")
                return (data, response)
            } catch {
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    print("⚠️ Request timed out")
                    throw AIFoodAnalysisError.timeout // makes performRequestWithRetry handle it
                }
                throw error
            }
        } catch AIFoodAnalysisError.timeout {
            print("⚠️ Timeout")
            throw AIFoodAnalysisError.timeout
        } catch {
            print("❌ Non-timeout error: \(error)")
            // For non-timeout errors, fail immediately
            throw error
        }
    }

    private func performRequestWithRetry(
        request: URLRequest,
        telemetryCallback: ((String) -> Void)?
    ) async throws -> (Data, URLResponse) {
        let maxRetries = proto.numberOfRetries
        var lastError: Error?

        for attempt in 1 ... maxRetries {
            do {
                return try await performRequest(
                    request: request,
                    attempt: attempt,
                    maxRetries: maxRetries,
                    telemetryCallback: telemetryCallback
                )

            } catch AIFoodAnalysisError.timeout {
                print("⚠️ Debug - Timeout on attempt \(attempt)")
                lastError = AIFoodAnalysisError.timeout

                if attempt < maxRetries {
                    let backoffDelay = Double(attempt) * 2.0 // 2s, 4s backoff
                    telemetryCallback?("⏳ retry in \(Int(backoffDelay))s …")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                }
            } catch {
                print("❌ Debug - Non-timeout error on attempt \(attempt): \(error)")
                // For non-timeout errors, fail immediately
                throw error
            }
        }

        print("❌ Debug - All retry attempts failed")

        throw AIFoodAnalysisError
            .customError("requests timed out consistently. Last error: \(lastError?.localizedDescription ?? "unknown")")
    }
}

protocol AIProviderProtocol: Sendable {
    var needAggressiveImageCompression: Bool { get }

    var numberOfRetries: Int { get }

    var timeoutsConfig: ModelTimeoutsConfig { get }

    func buildRequest(
        prompt: String,
        images: [String],
        telemetryCallback: ((String) -> Void)?
    ) throws -> URLRequest

    func handleErrorResponse(
        httpResponse: HTTPURLResponse,
        data: Data,
        telemetryCallback: ((String) -> Void)?
    ) throws

    func extractResponse(
        data: Data,
        telemetryCallback: ((String) -> Void)?
    ) throws -> String
}
