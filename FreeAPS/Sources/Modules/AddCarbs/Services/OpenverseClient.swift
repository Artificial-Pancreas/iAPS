import Foundation

// MARK: - Models

struct OpenverseImageResult: Codable, Identifiable {
    let id: String
    let title: String?
    let creator: String?
    let url: String
    let thumbnail: String?
    let width: Int?
    let height: Int?
    let license: String
    let licenseVersion: String?
    let licenseUrl: String?
    let attribution: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case creator
        case url
        case thumbnail
        case width
        case height
        case license
        case licenseVersion = "license_version"
        case licenseUrl = "license_url"
        case attribution
    }
}

struct OpenverseSearchResponse: Codable {
    let resultCount: Int
    let pageCount: Int
    let results: [OpenverseImageResult]

    enum CodingKeys: String, CodingKey {
        case resultCount = "result_count"
        case pageCount = "page_count"
        case results
    }
}

// MARK: - Client

enum OpenverseClientError: Error {
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    case networkError(Error)
    case httpError(statusCode: Int)
}

actor OpenverseClient {
    static let shared = OpenverseClient()

    private let baseURL = "https://api.openverse.org/v1"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Search for images on Openverse
    /// - Parameters:
    ///   - query: The search term
    ///   - pageSize: Number of results per page (default: 20)
    ///   - page: Page number (default: 1)
    /// - Returns: Array of OpenverseImageResult
    func searchImages(
        query: String,
        pageSize: Int = 20,
        page: Int = 1
    ) async throws -> [OpenverseImageResult] {
        // Build URL with query parameters
        guard var components = URLComponents(string: "\(baseURL)/images/") else {
            throw OpenverseClientError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page))
        ]

        guard let url = components.url else {
            throw OpenverseClientError.invalidURL
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Perform request
        let (data, response) = try await session.data(for: request)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenverseClientError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw OpenverseClientError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode response
        do {
            let searchResponse = try JSONDecoder().decode(OpenverseSearchResponse.self, from: data)

            // Filter results to prefer smaller images (up to 1024x1024)
            let filteredResults = searchResponse.results.filter { result in
                guard let width = result.width, let height = result.height else {
                    return true // Include if dimensions are unknown
                }
                return width <= 1024 && height <= 1024
            }

            // If filtering removed all results, return original results
            return filteredResults.isEmpty ? searchResponse.results : filteredResults
        } catch {
            throw OpenverseClientError.decodingError(error)
        }
    }
}
