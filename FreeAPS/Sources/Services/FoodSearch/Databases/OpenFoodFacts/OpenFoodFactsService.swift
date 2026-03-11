import Foundation

extension OpenFoodFactsService: TextAnalysisService {
    func analyzeText(
        prompt: String,
        telemetryCallback _: (@Sendable(String) -> Void)?
    ) async throws -> FoodItemGroup {
        let products = try await searchProducts(query: prompt, pageSize: 15)
        var result = OpenFoodFactsProduct.createFoodItemGroup(products: products, confidence: nil, source: .search)
        result.textQuery = prompt
        return result
    }
}

extension OpenFoodFactsService: BarcodeAnalysisService {
    func analyzeBarcode(
        barcode: String,
        telemetryCallback _: (@Sendable(String) -> Void)?
    ) async throws -> FoodItemGroup {
        let item = try await searchProduct(barcode: barcode)
        var result = OpenFoodFactsProduct.createFoodItemGroup(products: [item], confidence: .high, source: .barcode)
        result.barcode = barcode
        return result
    }
}

/// Service for interacting with the OpenFoodFacts API
final class OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let session: URLSession
    private let baseURL = "https://world.openfoodfacts.org"
    private let userAgent = "Loop-iOS-Diabetes-App/1.0"
    private let timeout: TimeInterval = 30.0
    private let requestedFields =
        "code,product_name,brands,categories,nutriments,serving_size,serving_quantity,image_url,image_front_url"

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
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

    func searchProducts(query: String, pageSize: Int = 20) async throws -> [OpenFoodFactsProduct] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let numericCharacterSet = CharacterSet.decimalDigits
        let isBarcode = trimmedQuery.unicodeScalars.allSatisfy { numericCharacterSet.contains($0) }

        if isBarcode, trimmedQuery.count >= 8 {
            let directURLString = "https://world.openfoodfacts.org/api/v2/product/\(trimmedQuery).json?fields=\(requestedFields)"

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

            if let directResponse = try? JSONDecoder().decode(OpenFoodFactsDirectResponse.self, from: response.data),
               directResponse.status == 1, let product = directResponse.product
            {
                return [product]
            }
            return []
        }

        guard let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw OpenFoodFactsError.invalidURL
        }

        let clampedPageSize = min(max(pageSize, 1), 100)
        let urlString =
            "\(baseURL)/cgi/search.pl?search_terms=\(encodedQuery)&search_simple=1&action=process&json=1&page_size=\(clampedPageSize)&fields=\(requestedFields)"

        guard let url = URL(string: urlString) else {
            throw OpenFoodFactsError.invalidURL
        }

        let request = createRequest(for: url)
        let response = try await performRequest(request)

        saveDebugDataToTempFile(
            description: "OpenFoodFacts search response",
            fileName: "openfoodfacts_search_response.json",
            data: response.data
        )

        let searchResponse = try decodeResponse(OpenFoodFactsSearchResponse.self, from: response.data)
        return searchResponse.products.filter { $0.hasSufficientNutritionalData }
    }

    struct OpenFoodFactsDirectResponse: Codable {
        let status: Int
        let product: OpenFoodFactsProduct?
    }

    func searchProduct(barcode: String) async throws -> OpenFoodFactsProduct {
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBarcode.isEmpty else {
            throw OpenFoodFactsError.invalidBarcode
        }

        guard isValidBarcode(cleanBarcode) else {
            print("Invalid barcode format: \(cleanBarcode)")
            throw OpenFoodFactsError.invalidBarcode
        }

        let urlString = "\(baseURL)/api/v0/product/\(cleanBarcode).json?fields=\(requestedFields)"

        guard let url = URL(string: urlString) else {
            print("Failed to construct URL for barcode: \(cleanBarcode)")
            throw OpenFoodFactsError.invalidURL
        }

        let request = createRequest(for: url)
        let response = try await performRequest(request)
        let productResponse = try decodeResponse(OpenFoodFactsProductResponse.self, from: response.data)

        guard let product = productResponse.product else {
            print("No product found for barcode: \(cleanBarcode)")
            throw OpenFoodFactsError.productNotFound
        }

        guard product.hasSufficientNutritionalData else {
            print("Product found for barcode \(cleanBarcode) but has insufficient nutritional data")
            throw OpenFoodFactsError.productNotFound
        }

        return product
    }

    func fetchProduct(barcode: String) async throws -> OpenFoodFactsProduct? {
        do {
            return try await searchProduct(barcode: barcode)
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
                print("Expected HTTPURLResponse but got \(type(of: response))")
                throw OpenFoodFactsError.networkError(URLError(.badServerResponse))
            }

            switch httpResponse.statusCode {
            case 200:
                return (data, httpResponse)
            case 404:
                throw OpenFoodFactsError.productNotFound
            case 429:
                print("OpenFoodFacts rate limit exceeded")
                throw OpenFoodFactsError.rateLimitExceeded
            case 500 ... 599:
                print("OpenFoodFacts server error \(httpResponse.statusCode)")
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64((retryCount + 1) * 1_000_000_000))
                    return try await performRequest(request, retryCount: retryCount + 1)
                }
                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            default:
                print("OpenFoodFacts unexpected HTTP status \(httpResponse.statusCode)")
                throw OpenFoodFactsError.networkError(URLError(.init(rawValue: httpResponse.statusCode)))
            }

        } catch let urlError as URLError {
            if urlError.code == .timedOut || urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost,
               retryCount < maxRetries
            {
                print("Network error, retrying (attempt \(retryCount + 1)/\(maxRetries)): \(urlError)")
                try await Task.sleep(nanoseconds: UInt64((retryCount + 1) * 2_000_000_000))
                return try await performRequest(request, retryCount: retryCount + 1)
            }
            print("Network error: \(urlError)")
            throw OpenFoodFactsError.networkError(urlError)
        } catch let openFoodFactsError as OpenFoodFactsError {
            throw openFoodFactsError
        } catch {
            print("Unexpected error during request: \(error)")
            throw OpenFoodFactsError.networkError(error)
        }
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("Failed to decode \(T.self): \(error)")
            throw OpenFoodFactsError.decodingError(error)
        }
    }

    private func isValidBarcode(_ barcode: String) -> Bool {
        let numericPattern = "^[0-9]{8,14}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", numericPattern)
        return predicate.evaluate(with: barcode)
    }
}
