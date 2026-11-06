import Foundation

extension USDAFoodDataService: TextAnalysisService {
    func analyzeText(
        prompt: String,
        telemetryCallback _: (@Sendable(String) -> Void)?
    ) async throws -> FoodItemGroup {
        let products = try await searchProducts(query: prompt, pageSize: 25)
        var result = OpenFoodFactsProduct.createFoodItemGroup(products: products, confidence: nil, source: .search)
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
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        session = URLSession(configuration: config)
    }

    private func searchProducts(query: String, pageSize: Int = 15) async throws -> [OpenFoodFactsProduct] {
        guard let url = URL(string: "\(baseURL)/foods/search") else {
            throw OpenFoodFactsError.invalidURL
        }

        let apiKey = UserDefaults.standard.usdaAPIKey.isEmpty ? "DEMO_KEY" : UserDefaults.standard.usdaAPIKey

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey"),
            URLQueryItem(name: "sortBy", value: "dataType.keyword"),
            URLQueryItem(name: "sortOrder", value: "asc"),
            URLQueryItem(name: "requireAllWords", value: "false")
        ]

        guard let finalURL = components.url else {
            throw OpenFoodFactsError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        do {
            try Task.checkCancellation()

            let (data, response) = try await session.data(for: request)

            saveDebugDataToTempFile(description: "USDA response", fileName: "usda-response.json", data: data)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenFoodFactsError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                print("USDA HTTP error \(httpResponse.statusCode)")
                throw OpenFoodFactsError.serverError(httpResponse.statusCode)
            }

            let searchResponse: USDASearchResponse
            do {
                searchResponse = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            } catch {
                print("Failed to decode USDA search response: \(error)")
                throw OpenFoodFactsError.decodingError(error)
            }

            try Task.checkCancellation()

            return searchResponse.foods.compactMap { Task.isCancelled ? nil : convertUSDAFoodToProduct($0) }

        } catch {
            if error is CancellationError { return [] }
            if let urlError = error as? URLError, urlError.code == .cancelled { return [] }
            throw OpenFoodFactsError.networkError(error)
        }
    }

    private func convertUSDAFoodToProduct(
        _ foodData: USDAFood
    ) -> OpenFoodFactsProduct? {
        // energy in kcal whatever the row's unit, sugars the total (`USDAMacronutrients`)
        let macros = USDAMacronutrients(foodData.foodNutrients ?? [])
        let carbs = macros.carbs
        let protein = macros.protein
        let fat = macros.fat
        let fiber = macros.fiber
        let sugars = macros.sugars
        let energy = macros.energy

        // one per substance (vitamin A and folate are listed twice)
        let micronutrients = USDAFoodNutrient.micronutrients(foodData.foodNutrients ?? [])

        print("USDA FINAL MICROS:", micronutrients)

        guard carbs > 0 ||
            protein > 0 ||
            fat > 0 ||
            energy > 0
        else {
            return nil
        }

        let nutriments = Nutriments(
            carbohydrates: carbs,
            proteins: protein > 0 ? protein : nil,
            fat: fat > 0 ? fat : nil,
            calories: energy > 0 ? energy : nil,
            sugars: sugars > 0 ? sugars : nil,
            fiber: fiber > 0 ? fiber : nil,
            energy: energy > 0 ? energy : nil,
            micronutrient: micronutrients
        )

        return OpenFoodFactsProduct(
            id: String(foodData.fdcId),
            productName: cleanUSDADescription(foodData.description),
            brands: "USDA FoodData Central",
            categories: categorizeUSDAFood(foodData.description),
            nutriments: nutriments,
            servingSize: "100g",
            servingQuantity: 100.0,
            imageURL: nil,
            imageFrontURL: nil,
            code: String(foodData.fdcId)
        )
    }

    private func cleanUSDADescription(_ description: String) -> String {
        var cleaned = description

        let removals = [
            ", raw", ", cooked", ", boiled", ", steamed",
            ", NFS", ", NS as to form", ", not further specified",
            "USDA Commodity", "Food and Nutrition Service",
            ", UPC: ", "\\b\\d{5,}\\b"
        ]

        for removal in removals {
            if removal.starts(with: "\\") {
                cleaned = cleaned.replacingOccurrences(of: removal, with: "", options: .regularExpression)
            } else {
                cleaned = cleaned.replacingOccurrences(of: removal, with: "")
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleaned.isEmpty {
            cleaned =
                String(cleaned.prefix(1)).uppercased()
                    + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? "USDA Food Item" : cleaned
    }

    private func categorizeUSDAFood(_ description: String) -> String? {
        let lowercased = description.lowercased()

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

extension USDAFoodNutrient {
    var resolvedMicroNutrient: MicroNutrient? {
        // First try USDA numeric codes
        if let micro = nutrientCode?.microNutrient {
            return micro
        }

        // Fallback to nutrient names
        guard let name = nutrientName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return nil
        }

        switch name {
        // Vitamins

        case "vitamin c, total ascorbic acid":
            return .vitaminC

        // not "vitamin a, iu": no factor turns it into µg RAE (`USDANutrientCode.microNutrient`)
        case "vitamin a, rae":
            return .vitaminA

        // the IU only without the µg (`substancePriority`)
        case "vitamin d (d2 + d3)",
             "vitamin d (d2 + d3), international units":
            return .vitaminD

        // as FoodData Central names it (SR Legacy, Foundation, Survey; mg). Not "vitamin e, added" (a part of it),
        // nor Foundation's plain "vitamin e" (id 2068, mg), the alpha-tocopherol row is read
        case "vitamin e (alpha-tocopherol)":
            return .vitaminE

        case "vitamin k (phylloquinone)":
            return .vitaminK

        case "thiamin":
            return .vitaminB1

        case "riboflavin":
            return .vitaminB2

        case "niacin":
            return .vitaminB3

        case "pantothenic acid":
            return .vitaminB5

        case "vitamin b-6":
            return .vitaminB6

        case "folate, dfe",
             "folate, total":
            return .vitaminB9

        case "vitamin b-12":
            return .vitaminB12

        // Minerals

        case "calcium, ca":
            return .calcium

        case "iron, fe":
            return .iron

        case "magnesium, mg":
            return .magnesium

        case "phosphorus, p":
            return .phosphorus

        case "potassium, k":
            return .potassium

        case "zinc, zn":
            return .zinc

        case "copper, cu":
            return .copper

        case "manganese, mn":
            return .manganese

        case "selenium, se":
            return .selenium

        case "iodine, i":
            return .iodine

        // as salt (`normalizedValue(for:)` converts it)
        case "sodium, na":
            return .salt

        default:
            return nil
        }
    }
}
