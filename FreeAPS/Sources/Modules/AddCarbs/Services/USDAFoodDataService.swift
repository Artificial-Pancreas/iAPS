import CoreML
import CryptoKit
import Foundation
import LoopKit
import Network
import os.log
import SwiftUI
import UIKit
import Vision

extension USDAFoodDataService: TextAnalysisService {
    func analyzeText(
        prompt: String,
        telemetryCallback _: ((String) -> Void)?
    ) async throws -> FoodItemGroup {
        let products = try await searchProducts(query: prompt, pageSize: 15)
        var result = fromOpenFoodFactsProducts(products: products, confidence: nil, source: .search)
        result.textQuery = prompt
        return result
    }
}

/// Service for accessing USDA FoodData Central API for comprehensive nutrition data
final class USDAFoodDataService {
    static let shared = USDAFoodDataService()

    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private let session: URLSession

    private let timeout: TimeInterval = 10.0

    private init() {
        // Create optimized URLSession configuration for USDA API
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        session = URLSession(configuration: config)
    }

    /// Search for food products using USDA FoodData Central API
    /// - Parameter query: Search query string
    /// - Returns: Array of OpenFoodFactsProduct for compatibility with existing UI
    private func searchProducts(query: String, pageSize: Int = 15) async throws -> [OpenFoodFactsProduct] {
        print("🇺🇸 Starting USDA FoodData Central search for: '\(query)'")

        guard let url = URL(string: "\(baseURL)/foods/search") else {
            throw OpenFoodFactsError.invalidURL
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: "DEMO_KEY"), // USDA provides free demo access
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey"),
            // Get comprehensive nutrition data from multiple sources
            URLQueryItem(name: "sortBy", value: "dataType.keyword"),
            URLQueryItem(name: "sortOrder", value: "asc"),
            URLQueryItem(name: "requireAllWords", value: "false") // Allow partial matches for better results
        ]

        guard let finalURL = components.url else {
            throw OpenFoodFactsError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        do {
            // Check for task cancellation before making request
            try Task.checkCancellation()

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                print("🇺🇸 USDA: HTTP error \(httpResponse.statusCode)")
                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            }

            // Decode USDA response using Codable
            let decoder = JSONDecoder()
            let searchResponse: USDASearchResponse

            do {
                searchResponse = try decoder.decode(USDASearchResponse.self, from: data)
            } catch {
                print("🇺🇸 USDA: Decoding error - \(error)")
                throw OpenFoodFactsError.decodingError(error)
            }

            let foods = searchResponse.foods
            print("🇺🇸 USDA: Raw API returned \(foods.count) food items")

            // Check for task cancellation before processing results
            try Task.checkCancellation()

            // Convert USDA foods to OpenFoodFactsProduct format for UI compatibility
            let products = foods.compactMap { foodData -> OpenFoodFactsProduct? in
                // Check for cancellation during processing to allow fast cancellation
                if Task.isCancelled {
                    return nil
                }
                return convertUSDAFoodToProduct(foodData)
            }

            print("🇺🇸 USDA search completed: \(products.count) valid products found (filtered from \(foods.count) raw items)")
            return products

        } catch {
            print("🇺🇸 USDA search failed: \(error)")

            // Handle task cancellation gracefully
            if error is CancellationError {
                print("🇺🇸 USDA: Task was cancelled (expected behavior during rapid typing)")
                return []
            }

            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("🇺🇸 USDA: URLSession request was cancelled (expected behavior during rapid typing)")
                return []
            }

            throw OpenFoodFactsError.networkError(error)
        }
    }

    /// Convert USDA food data to OpenFoodFactsProduct for UI compatibility
    private func convertUSDAFoodToProduct(_ foodData: USDAFood) -> OpenFoodFactsProduct? {
        let fdcId = foodData.fdcId
        let description = foodData.description

        // Extract nutrition data from USDA food nutrients with comprehensive mapping
        var carbs: Decimal = 0
        var protein: Decimal = 0
        var fat: Decimal = 0
        var fiber: Decimal = 0
        var sugars: Decimal = 0
        var energy: Decimal = 0

        // Track what nutrients we found for debugging
        var foundNutrients: [String] = []

        if let foodNutrients = foodData.foodNutrients {
            print("🇺🇸 USDA: Found \(foodNutrients.count) nutrients for '\(description)'")

            for nutrient in foodNutrients {
                // Debug: print the structure of the first few nutrients
                if foundNutrients.count < 3 {
                    print(
                        "🇺🇸 USDA: Nutrient - Code: \(nutrient.nutrientCode?.rawValue ?? -1), Name: \(nutrient.nutrientName ?? "nil"), Value: \(nutrient.value ?? 0)"
                    )
                }

                guard let nutrientCode = nutrient.nutrientCode,
                      let value = nutrient.value
                else {
                    continue
                }

                let decimalValue = Decimal(value)

                // Use the enum to handle nutrients by category with priority
                switch nutrientCode.category {
                case .carbohydrate:
                    if carbs == 0 || nutrientCode.priority < foundNutrientPriority(for: .carbohydrate) {
                        carbs = decimalValue
                        foundNutrients.append("carbs-\(nutrientCode.rawValue)")
                    }

                case .protein:
                    if protein == 0 || nutrientCode.priority < foundNutrientPriority(for: .protein) {
                        protein = decimalValue
                        foundNutrients.append("protein-\(nutrientCode.rawValue)")
                    }

                case .fat:
                    if fat == 0 || nutrientCode.priority < foundNutrientPriority(for: .fat) {
                        fat = decimalValue
                        foundNutrients.append("fat-\(nutrientCode.rawValue)")
                    }

                case .fiber:
                    if fiber == 0 || nutrientCode.priority < foundNutrientPriority(for: .fiber) {
                        fiber = decimalValue
                        foundNutrients.append("fiber-\(nutrientCode.rawValue)")
                    }

                case .sugar:
                    if sugars == 0 || nutrientCode.priority < foundNutrientPriority(for: .sugar) {
                        sugars = decimalValue
                        foundNutrients.append("sugars-\(nutrientCode.rawValue)")
                    }

                case .energy:
                    if energy == 0 || nutrientCode.priority < foundNutrientPriority(for: .energy) {
                        energy = decimalValue
                        foundNutrients.append("energy-\(nutrientCode.rawValue)")
                    }
                }
            }
        } else {
            print("🇺🇸 USDA: No foodNutrients array found in food data for '\(description)'")
        }

        // Log what we found for debugging
        if foundNutrients.isEmpty {
            print("🇺🇸 USDA: No recognized nutrients found for '\(description)' (fdcId: \(fdcId))")
        } else {
            print("🇺🇸 USDA: Found nutrients for '\(description)': \(foundNutrients.joined(separator: ", "))")
        }

        // Enhanced data quality validation
        let hasUsableNutrientData = carbs > 0 || protein > 0 || fat > 0 || energy > 0
        if !hasUsableNutrientData {
            print(
                "🇺🇸 USDA: Skipping '\(description)' - no usable nutrient data (carbs: \(carbs), protein: \(protein), fat: \(fat), energy: \(energy))"
            )
            return nil
        }

        // Create nutriments object with comprehensive data
        let nutriments = Nutriments(
            carbohydrates: carbs,
            proteins: protein > 0 ? protein : nil,
            fat: fat > 0 ? fat : nil,
            calories: energy > 0 ? energy : nil,
            sugars: sugars > 0 ? sugars : nil,
            fiber: fiber > 0 ? fiber : nil,
            energy: energy > 0 ? energy : nil
        )

        // Create product with USDA data
        return OpenFoodFactsProduct(
            id: String(fdcId),
            productName: cleanUSDADescription(description),
            brands: "USDA FoodData Central",
            categories: categorizeUSDAFood(description),
            nutriments: nutriments,
            servingSize: "100g", // USDA data is typically per 100g
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: String(fdcId)
        )
    }

    /// Helper to determine the priority of an already-found nutrient (for now, always returns max priority)
    private func foundNutrientPriority(for _: USDANutrientCode.NutrientCategory) -> Int {
        // This could be enhanced to track actual priorities if needed
        // For now, we only replace if we haven't found anything yet (handled by == 0 check)
        Int.max
    }

    /// Clean up USDA food descriptions for better readability
    private func cleanUSDADescription(_ description: String) -> String {
        var cleaned = description

        // Remove common USDA technical terms and codes
        let removals = [
            ", raw", ", cooked", ", boiled", ", steamed",
            ", NFS", ", NS as to form", ", not further specified",
            "USDA Commodity", "Food and Nutrition Service",
            ", UPC: ", "\\b\\d{5,}\\b" // Remove long numeric codes
        ]

        for removal in removals {
            if removal.starts(with: "\\") {
                // Handle regex patterns
                cleaned = cleaned.replacingOccurrences(
                    of: removal,
                    with: "",
                    options: .regularExpression
                )
            } else {
                cleaned = cleaned.replacingOccurrences(of: removal, with: "")
            }
        }

        // Capitalize properly and trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure first letter is capitalized
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? "USDA Food Item" : cleaned
    }

    /// Categorize USDA food items based on their description
    private func categorizeUSDAFood(_ description: String) -> String? {
        let lowercased = description.lowercased()

        // Define category mappings based on common USDA food terms
        let categories: [String: [String]] = [
            "Fruits": ["apple", "banana", "orange", "berry", "grape", "peach", "pear", "plum", "cherry", "melon", "fruit"],
            "Vegetables": ["broccoli", "carrot", "spinach", "lettuce", "tomato", "onion", "pepper", "cucumber", "vegetable"],
            "Grains": ["bread", "rice", "pasta", "cereal", "oat", "wheat", "barley", "quinoa", "grain"],
            "Dairy": ["milk", "cheese", "yogurt", "butter", "cream", "dairy"],
            "Protein": ["chicken", "beef", "pork", "fish", "egg", "meat", "turkey", "salmon", "tuna"],
            "Nuts & Seeds": ["nut", "seed", "almond", "peanut", "walnut", "cashew", "sunflower"],
            "Beverages": ["juice", "beverage", "drink", "soda", "tea", "coffee"],
            "Snacks": ["chip", "cookie", "cracker", "candy", "chocolate", "snack"]
        ]

        for (category, keywords) in categories {
            if keywords.contains(where: { lowercased.contains($0) }) {
                return category
            }
        }

        return nil
    }
}

// MARK: - USDA API Response Models

/// USDA Nutrient identification codes
/// Based on USDA FoodData Central nutrient database
enum USDANutrientCode: Int {
    // MARK: Carbohydrates

    /// Carbohydrate, by difference (most common)
    case carbohydrateByDifference = 205
    /// Carbohydrate, by summation
    case carbohydrateBySummation = 1005
    /// Carbohydrate, other
    case carbohydrateOther = 1050

    // MARK: Protein

    /// Protein (most common)
    case protein = 203
    /// Protein, crude
    case proteinCrude = 1003

    // MARK: Fat

    /// Total lipid (fat) (most common)
    case totalLipidFat = 204
    /// Total lipid, crude
    case totalLipidCrude = 1004

    // MARK: Fiber

    /// Fiber, total dietary (most common)
    case fiberTotalDietary = 291
    /// Fiber, crude
    case fiberCrude = 1079

    // MARK: Sugars

    /// Sugars, total including NLEA (most common)
    case sugarsTotalIncludingNLEA = 269
    /// Sugars, total
    case sugarsTotal = 1010
    /// Sugars, added
    case sugarsAdded = 1063

    // MARK: Energy/Calories

    /// Energy (kcal) (most common)
    case energyKcal = 208
    /// Energy, gross
    case energyGross = 1008
    /// Energy, metabolizable
    case energyMetabolizable = 1062

    /// Category of the nutrient for easier grouping
    var category: NutrientCategory {
        switch self {
        case .carbohydrateByDifference,
             .carbohydrateBySummation,
             .carbohydrateOther:
            return .carbohydrate
        case .protein,
             .proteinCrude:
            return .protein
        case .totalLipidCrude,
             .totalLipidFat:
            return .fat
        case .fiberCrude,
             .fiberTotalDietary:
            return .fiber
        case .sugarsAdded,
             .sugarsTotal,
             .sugarsTotalIncludingNLEA:
            return .sugar
        case .energyGross,
             .energyKcal,
             .energyMetabolizable:
            return .energy
        }
    }

    /// Priority within its category (lower is higher priority)
    var priority: Int {
        switch self {
        // Primary values (most common/preferred)
        case .carbohydrateByDifference,
             .energyKcal,
             .fiberTotalDietary,
             .protein,
             .sugarsTotalIncludingNLEA,
             .totalLipidFat:
            return 1
        // Secondary values (summation/alternative)
        case .carbohydrateBySummation,
             .energyGross,
             .fiberCrude,
             .proteinCrude,
             .sugarsTotal,
             .totalLipidCrude:
            return 2
        // Tertiary values (other/less common)
        case .carbohydrateOther,
             .energyMetabolizable,
             .sugarsAdded:
            return 3
        }
    }

    enum NutrientCategory {
        case carbohydrate
        case protein
        case fat
        case fiber
        case sugar
        case energy
    }
}

/// Root response from USDA FoodData Central search API
struct USDASearchResponse: Codable {
    let foods: [USDAFood]
    let totalHits: Int?
    let currentPage: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case foods
        case totalHits
        case currentPage
        case totalPages
    }
}

/// USDA Food item from search results
struct USDAFood: Codable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let brandName: String?
    let ingredients: String?
    let foodNutrients: [USDAFoodNutrient]?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?

    enum CodingKeys: String, CodingKey {
        case fdcId
        case description
        case dataType
        case brandOwner
        case brandName
        case ingredients
        case foodNutrients
        case servingSize
        case servingSizeUnit
        case householdServingFullText
    }
}

/// Nutrient information from USDA food item
struct USDAFoodNutrient: Codable {
    let nutrientId: Int?
    let nutrientNumber: String?
    let nutrientName: String?
    let value: Double?
    let unitName: String?

    enum CodingKeys: String, CodingKey {
        case nutrientId
        case nutrientNumber
        case nutrientName
        case value
        case unitName
    }

    /// Get the nutrient number as an integer, handling both String and Int formats
    var nutrientNumberAsInt: Int? {
        if let nutrientId = nutrientId {
            return nutrientId
        }
        if let nutrientNumber = nutrientNumber, let intValue = Int(nutrientNumber) {
            return intValue
        }
        return nil
    }

    /// Get the nutrient as a typed enum value
    var nutrientCode: USDANutrientCode? {
        guard let number = nutrientNumberAsInt else { return nil }
        return USDANutrientCode(rawValue: number)
    }
}
