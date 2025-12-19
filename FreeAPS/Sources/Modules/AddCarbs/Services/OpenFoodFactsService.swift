import Foundation
import OSLog

extension OpenFoodFactsService: TextAnalysisService {
    func analyzeText(
        prompt: String,
        telemetryCallback _: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult {
        let products = try await searchProducts(query: prompt, pageSize: 15)
        var result = fromOpenFoodFactsProducts(products: products, confidence: nil, source: .search)
        result.textQuery = prompt
        return result
    }
}

extension OpenFoodFactsService: BarcodeAnalysisService {
    func analyzeBarcode(
        barcode: String,
        telemetryCallback _: ((String) -> Void)?
    ) async throws -> FoodAnalysisResult {
        let item = try await searchProduct(barcode: barcode)
        var result = fromOpenFoodFactsProducts(products: [item], confidence: .high, source: .barcode)
        result.barcode = barcode
        return result
    }
}

/// Service for interacting with the OpenFoodFacts API
/// Provides food search functionality and barcode lookup for carb counting
final class OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    // MARK: - Properties

    private let session: URLSession
    private let baseURL = "https://world.openfoodfacts.org"
    private let userAgent = "Loop-iOS-Diabetes-App/1.0"
    private let log = OSLog(subsystem: "", category: "OpenFoodFactsService")

    private let timeout: TimeInterval = 30.0

    // MARK: - Initialization

    /// Initialize the service
    /// - Parameter session: URLSession to use for network requests (defaults to optimized configuration)
    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            // Create optimized configuration for food database requests
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 2
            config.waitsForConnectivity = true
            config.networkServiceType = .default
            config.allowsCellularAccess = true
            config.httpMaximumConnectionsPerHost = 4
            self.session = URLSession(configuration: config)
        }
    }

    private func searchProducts(query: String, pageSize: Int = 20) async throws -> [OpenFoodFactsProduct] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        // ✅ NEU: Direkter Produkt-Endpoint für Barcodes (wie Loop)
        // Prüfe ob es sich um einen Barcode handelt (nur Zahlen)
        let numericCharacterSet = CharacterSet.decimalDigits
        let isBarcode = trimmedQuery.unicodeScalars.allSatisfy { numericCharacterSet.contains($0) }

        if isBarcode, trimmedQuery.count >= 8 {
            print("🌐 DEBUG: Using DIRECT PRODUCT API for barcode: \(trimmedQuery)")
            let directURLString = "https://world.openfoodfacts.org/api/v2/product/\(trimmedQuery).json"

            guard let directURL = URL(string: directURLString) else {
                throw OpenFoodFactsError.invalidURL
            }

            let request = createRequest(for: directURL)
            let response = try await performRequest(request)

            saveDebugDataToTempFile(
                description: "OpenFoodFacts direct product response",
                fileName: "openfoodfacts_direct_response.json",
                data: response.data
            )

            // Versuche das direkte Produkt-Format zu parsen
            do {
                let directResponse = try JSONDecoder().decode(OpenFoodFactsDirectResponse.self, from: response.data)

                if directResponse.status == 1, let product = directResponse.product {
                    print("✅ DEBUG: Direct product found: \(product.productName ?? "Unknown")")
                    return [product]
                } else {
                    print("ℹ️ DEBUG: Direct product not found (status: \(directResponse.status))")
                    return []
                }
            } catch {
                print("❌ DEBUG: Direct product decoding failed: \(error)")
                // Fallback zur normalen Suche
            }
        }

        // Normale Suche für Text queries
        guard let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw OpenFoodFactsError.invalidURL
        }

        let clampedPageSize = min(max(pageSize, 1), 100)
        let urlString =
            "\(baseURL)/cgi/search.pl?search_terms=\(encodedQuery)&search_simple=1&action=process&json=1&page_size=\(clampedPageSize)"

        print("🌐 DEBUG: Using SEARCH API for query: \(trimmedQuery)")

        guard let url = URL(string: urlString) else {
            throw OpenFoodFactsError.invalidURL
        }

        let request = createRequest(for: url)
        let response = try await performRequest(request)

        saveDebugDataToTempFile(
            description: "OpenFoodFacts direct product response",
            fileName: "openfoodfacts_search_response.json",
            data: response.data
        )

        do {
            _ = try decodeResponse(OpenFoodFactsSearchResponse.self, from: response.data)
        } catch let decodingError as DecodingError {
            print("❌ DECODING FAILED:")
            print(prettyPrintDecodingError(decodingError))

            // Also print a snippet of the raw JSON for context
            if let jsonString = String(data: response.data, encoding: .utf8) {
                let preview = String(jsonString.prefix(500))
                print("📄 JSON Preview (first 500 chars):\n\(preview)")
            }
        } catch {
            print("❌ Other error: \(error.localizedDescription)")
        }
        let searchResponse = try decodeResponse(OpenFoodFactsSearchResponse.self, from: response.data)
        let validProducts = searchResponse.products.filter { $0.hasSufficientNutritionalData }

        print("✅ DEBUG: Found \(validProducts.count) valid products (of \(searchResponse.products.count) total)")
        return validProducts
    }

    struct OpenFoodFactsDirectResponse: Codable {
        let status: Int
        let product: OpenFoodFactsProduct?

        enum CodingKeys: String, CodingKey {
            case status
            case product
        }
    }

    private func decodeResponse<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // ✅ EINFACHE LÖSUNG: Normal decodieren
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            print("❌ DECODING ERROR: \(error)")
            throw error
        }
    }

    func searchProduct(barcode: String) async throws -> OpenFoodFactsProduct {
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBarcode.isEmpty else {
            throw OpenFoodFactsError.invalidBarcode
        }

        guard isValidBarcode(cleanBarcode) else {
            os_log("Invalid barcode format: %{public}@", log: log, type: .error, cleanBarcode)
            throw OpenFoodFactsError.invalidBarcode
        }

        let urlString = "\(baseURL)/api/v0/product/\(cleanBarcode).json"

        guard let url = URL(string: urlString) else {
            os_log("Failed to create URL for barcode: %{public}@", log: log, type: .error, cleanBarcode)
            throw OpenFoodFactsError.invalidURL
        }

        os_log("Looking up product by barcode: %{public}@ at URL: %{public}@", log: log, type: .info, cleanBarcode, urlString)

        let request = createRequest(for: url)
        os_log("Starting barcode request with timeout: %.1f seconds", log: log, type: .info, request.timeoutInterval)
        let response = try await performRequest(request)
        let productResponse = try decodeResponse(OpenFoodFactsProductResponse.self, from: response.data)

        guard let product = productResponse.product else {
            os_log("Product not found for barcode: %{public}@", log: log, type: .info, cleanBarcode)
            throw OpenFoodFactsError.productNotFound
        }

        guard product.hasSufficientNutritionalData else {
            os_log("Product found but lacks sufficient nutritional data: %{public}@", log: log, type: .info, cleanBarcode)
            throw OpenFoodFactsError.productNotFound
        }

        os_log("Successfully found product: %{public}@", log: log, type: .info, product.displayName)

        return product
    }

    func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct? {
        do {
            let product = try await searchProduct(barcode: barcode)
            return product
        } catch OpenFoodFactsError.productNotFound {
            return nil
        } catch {
            throw error
        }
    }

    // MARK: - Private Methods

    private func createRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = timeout
        return request
    }

    private func performRequest(
        _ request: URLRequest,
        retryCount: Int = 0
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let maxRetries = 2

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                os_log("Invalid response type received", log: log, type: .error)
                throw OpenFoodFactsError.networkError(URLError(.badServerResponse))
            }

            switch httpResponse.statusCode {
            case 200:
                return (data, httpResponse)
            case 404:
                throw OpenFoodFactsError.productNotFound
            case 429:
                os_log("Rate limit exceeded", log: log, type: .error)
                throw OpenFoodFactsError.rateLimitExceeded
            case 500 ... 599:
                os_log("Server error: %d", log: log, type: .error, httpResponse.statusCode)

                // Retry server errors
                if retryCount < maxRetries {
                    os_log(
                        "Retrying request due to server error (attempt %d/%d)",
                        log: log,
                        type: .info,
                        retryCount + 1,
                        maxRetries
                    )
                    try await Task.sleep(nanoseconds: UInt64((retryCount + 1) * 1_000_000_000)) // 1s, 2s delay
                    return try await performRequest(request, retryCount: retryCount + 1)
                }

                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            default:
                os_log("Unexpected HTTP status: %d", log: log, type: .error, httpResponse.statusCode)
                throw OpenFoodFactsError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
            }

        } catch let urlError as URLError {
            // Retry timeout and connection errors
            if urlError.code == .timedOut || urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost,
               retryCount < maxRetries
            {
                os_log(
                    "Network error (attempt %d/%d): %{public}@, retrying...",
                    log: log,
                    type: .info,
                    retryCount + 1,
                    maxRetries,
                    urlError.localizedDescription
                )
                try await Task.sleep(nanoseconds: UInt64((retryCount + 1) * 2_000_000_000)) // 2s, 4s delay
                return try await performRequest(request, retryCount: retryCount + 1)
            }

            os_log("Network error: %{public}@", log: log, type: .error, urlError.localizedDescription)
            throw OpenFoodFactsError.networkError(urlError)
        } catch let openFoodFactsError as OpenFoodFactsError {
            throw openFoodFactsError
        } catch {
            os_log("Unexpected error: %{public}@", log: log, type: .error, error.localizedDescription)
            throw OpenFoodFactsError.networkError(error)
        }
    }

    private func decodeResponse<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch let decodingError as DecodingError {
            let detailedError = prettyPrintDecodingError(decodingError)
            os_log("JSON decoding failed:\n%{public}@", log: log, type: .error, detailedError)
            print("❌ DETAILED DECODING ERROR:\n\(detailedError)")

            // Print JSON preview
            if let jsonString = String(data: data, encoding: .utf8) {
                let preview = String(jsonString.prefix(1000))
                print("📄 JSON Preview (first 1000 chars):\n\(preview)")
            }

            throw OpenFoodFactsError.decodingError(decodingError)
        } catch {
            os_log("Decoding error: %{public}@", log: log, type: .error, error.localizedDescription)
            print("❌ OTHER DECODING ERROR: \(error)")
            throw OpenFoodFactsError.decodingError(error)
        }
    }

    private func isValidBarcode(_ barcode: String) -> Bool {
        // Basic barcode validation
        // Should be numeric and between 8-14 digits (covers EAN-8, EAN-13, UPC-A, etc.)
        let numericPattern = "^[0-9]{8,14}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", numericPattern)
        return predicate.evaluate(with: barcode)
    }

    private func prettyPrintDecodingError(_ error: DecodingError) -> String {
        switch error {
        case let .typeMismatch(type, context):
            var output = "Type mismatch for type: \(type)\n"
            output += "  Expected type: \(type)\n"
            output += "  Coding path: \(context.codingPath.map(\.stringValue).joined(separator: " → "))\n"
            output += "  Debug description: \(context.debugDescription)\n"
            if let underlyingError = context.underlyingError {
                output += "  Underlying error: \(underlyingError.localizedDescription)\n"
            }
            return output

        case let .valueNotFound(type, context):
            var output = "Value not found for type: \(type)\n"
            output += "  Expected type: \(type)\n"
            output += "  Coding path: \(context.codingPath.map(\.stringValue).joined(separator: " → "))\n"
            output += "  Debug description: \(context.debugDescription)\n"
            if let underlyingError = context.underlyingError {
                output += "  Underlying error: \(underlyingError.localizedDescription)\n"
            }
            return output

        case let .keyNotFound(key, context):
            var output = "Key '\(key.stringValue)' not found\n"
            output += "  Coding path: \(context.codingPath.map(\.stringValue).joined(separator: " → "))\n"
            output += "  Debug description: \(context.debugDescription)\n"
            if let underlyingError = context.underlyingError {
                output += "  Underlying error: \(underlyingError.localizedDescription)\n"
            }
            return output

        case let .dataCorrupted(context):
            var output = "Data corrupted\n"
            output += "  Coding path: \(context.codingPath.map(\.stringValue).joined(separator: " → "))\n"
            output += "  Debug description: \(context.debugDescription)\n"
            if let underlyingError = context.underlyingError {
                output += "  Underlying error: \(underlyingError.localizedDescription)\n"
            }
            return output

        @unknown default:
            return "Unknown decoding error: \(error.localizedDescription)"
        }
    }
}
