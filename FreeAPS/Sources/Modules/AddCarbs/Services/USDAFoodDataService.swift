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
    ) async throws -> FoodAnalysisResult {
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

            // Parse USDA response with detailed error handling
            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🇺🇸 USDA: Invalid JSON response format")
                throw OpenFoodFactsError
                    .decodingError(NSError(
                        domain: "USDA",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"]
                    ))
            }

            // Check for API errors in response
            if let error = jsonResponse["error"] as? [String: Any],
               let code = error["code"] as? String,
               let message = error["message"] as? String
            {
                print("🇺🇸 USDA: API error - \(code): \(message)")
                throw OpenFoodFactsError.serverError(400)
            }

            guard let foods = jsonResponse["foods"] as? [[String: Any]] else {
                print("🇺🇸 USDA: No foods array in response")
                throw OpenFoodFactsError.noData
            }

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
    private func convertUSDAFoodToProduct(_ foodData: [String: Any]) -> OpenFoodFactsProduct? {
        guard let fdcId = foodData["fdcId"] as? Int,
              let description = foodData["description"] as? String
        else {
            print("🇺🇸 USDA: Missing fdcId or description for food item")
            return nil
        }

        // Extract nutrition data from USDA food nutrients with comprehensive mapping
        var carbs: Decimal = 0
        var protein: Decimal = 0
        var fat: Decimal = 0
        var fiber: Decimal = 0
        var sugars: Decimal = 0
        var energy: Decimal = 0

        // Track what nutrients we found for debugging
        var foundNutrients: [String] = []

        if let foodNutrients = foodData["foodNutrients"] as? [[String: Any]] {
            print("🇺🇸 USDA: Found \(foodNutrients.count) nutrients for '\(description)'")

            for nutrient in foodNutrients {
                // Debug: print the structure of the first few nutrients
                if foundNutrients.count < 3 {
                    print("🇺🇸 USDA: Nutrient structure: \(nutrient)")
                }

                // Try different possible field names for nutrient number
                var nutrientNumber: Int?
                if let number = nutrient["nutrientNumber"] as? Int {
                    nutrientNumber = number
                } else if let number = nutrient["nutrientId"] as? Int {
                    nutrientNumber = number
                } else if let numberString = nutrient["nutrientNumber"] as? String,
                          let number = Int(numberString)
                {
                    nutrientNumber = number
                } else if let numberString = nutrient["nutrientId"] as? String,
                          let number = Int(numberString)
                {
                    nutrientNumber = number
                }

                guard let nutrientNum = nutrientNumber else {
                    continue
                }

                // Handle both Double and String values from USDA API
                var value: Decimal = 0
                if let doubleValue = nutrient["value"] as? Double {
                    value = Decimal(doubleValue)
                } else if let stringValue = nutrient["value"] as? String,
                          let parsedValue = Decimal(from: stringValue)
                {
                    value = parsedValue
                } else if let doubleValue = nutrient["amount"] as? Double {
                    value = Decimal(doubleValue)
                } else if let stringValue = nutrient["amount"] as? String,
                          let parsedValue = Decimal(from: stringValue)
                {
                    value = parsedValue
                } else {
                    continue
                }

                // Comprehensive USDA nutrient number mapping
                switch nutrientNum {
                // Carbohydrates - multiple possible sources
                case 205: // Carbohydrate, by difference (most common)
                    carbs = value
                    foundNutrients.append("carbs-205")
                case 1005: // Carbohydrate, by summation
                    if carbs == 0 { carbs = value }
                    foundNutrients.append("carbs-1005")
                case 1050: // Carbohydrate, other
                    if carbs == 0 { carbs = value }
                    foundNutrients.append("carbs-1050")

                // Protein - multiple possible sources
                case 203: // Protein (most common)
                    protein = value
                    foundNutrients.append("protein-203")
                case 1003: // Protein, crude
                    if protein == 0 { protein = value }
                    foundNutrients.append("protein-1003")

                // Fat - multiple possible sources
                case 204: // Total lipid (fat) (most common)
                    fat = value
                    foundNutrients.append("fat-204")
                case 1004: // Total lipid, crude
                    if fat == 0 { fat = value }
                    foundNutrients.append("fat-1004")

                // Fiber - multiple possible sources
                case 291: // Fiber, total dietary (most common)
                    fiber = value
                    foundNutrients.append("fiber-291")
                case 1079: // Fiber, crude
                    if fiber == 0 { fiber = value }
                    foundNutrients.append("fiber-1079")

                // Sugars - multiple possible sources
                case 269: // Sugars, total including NLEA (most common)
                    sugars = value
                    foundNutrients.append("sugars-269")
                case 1010: // Sugars, total
                    if sugars == 0 { sugars = value }
                    foundNutrients.append("sugars-1010")
                case 1063: // Sugars, added
                    if sugars == 0 { sugars = value }
                    foundNutrients.append("sugars-1063")

                // Energy/Calories - multiple possible sources
                case 208: // Energy (kcal) (most common)
                    energy = value
                    foundNutrients.append("energy-208")
                case 1008: // Energy, gross
                    if energy == 0 { energy = value }
                    foundNutrients.append("energy-1008")
                case 1062: // Energy, metabolizable
                    if energy == 0 { energy = value }
                    foundNutrients.append("energy-1062")

                default:
                    break
                }
            }
        } else {
            print("🇺🇸 USDA: No foodNutrients array found in food data for '\(description)'")
            print("🇺🇸 USDA: Available keys in foodData: \(Array(foodData.keys))")
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
