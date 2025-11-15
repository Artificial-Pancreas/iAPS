import Combine
import Foundation

class FoodSearchService {
    static let shared = FoodSearchService()

    private init() {}

    // MARK: - Text Search

    func searchFoodProducts(query: String) async throws -> [FoodItem] {
        print("🔍 Starting search for: '\(query)'")
        let openFoodProducts = try await FoodSearchRouter.shared.searchFoodsByText(query)

        return openFoodProducts.map { openFoodProduct in
            FoodItem(
                name: openFoodProduct.productName ?? "Unknown",
                carbs: Decimal(openFoodProduct.nutriments.carbohydrates),
                fat: Decimal(openFoodProduct.nutriments.fat ?? 0),
                protein: Decimal(openFoodProduct.nutriments.proteins ?? 0),
                source: openFoodProduct.brands ?? "OpenFoodFacts",
                imageURL: openFoodProduct.imageURL ?? openFoodProduct.imageFrontURL
            )
        }
    }

    // MARK: - Barcode Search

    func searchOpenFoodFactsByBarcode(_ barcode: String) async throws -> [FoodItem] {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        print("🌐 OpenFoodFacts API Call: \(urlString)")

        guard let url = URL(string: urlString) else {
            throw NSError(domain: "OpenFoodFactsError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenFoodFactsError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ OpenFoodFacts API Error: Status \(httpResponse.statusCode)")
            return [] // Leeres Array für "nicht gefunden"
        }

        // Parse die Response
        let productResponse = try JSONDecoder().decode(OpenFoodFactsProductResponse.self, from: data)

        if productResponse.status == 1, let product = productResponse.product {
            // Produkt gefunden
            let foodItem = FoodItem(
                name: product.productName ?? "Unknown",
                carbs: Decimal(product.nutriments.carbohydrates),
                fat: Decimal(product.nutriments.fat ?? 0),
                protein: Decimal(product.nutriments.proteins ?? 0),
                source: product.brands ?? "OpenFoodFacts",
                imageURL: product.imageURL ?? product.imageFrontURL
            )
            return [foodItem]
        } else {
            // Kein Produkt gefunden
            print("ℹ️ OpenFoodFacts: No product found for barcode \(barcode)")
            return []
        }
    }

    // MARK: - AI Search with Completion

    func searchFoodProducts(query: String, completion: @escaping ([AIFoodItem]) -> Void) async throws -> [FoodItem] {
        do {
            print("🔍 Starting AI search for: '\(query)'")

            // Use the FoodSearchRouter to handle the search
            let openFoodProducts = try await FoodSearchRouter.shared.searchFoodsByText(query)

            print("✅ AI search completed, found \(openFoodProducts.count) products")

            // Konvertiert OpenFoodFactsProduct zu AIFoodItem
            let aiProducts = openFoodProducts.map { openFoodProduct in
                AIFoodItem(
                    name: openFoodProduct.productName ?? "Unknown",
                    brand: openFoodProduct.brands,
                    calories: 0,
                    carbs: openFoodProduct.nutriments.carbohydrates,
                    protein: openFoodProduct.nutriments.proteins ?? 0,
                    fat: openFoodProduct.nutriments.fat ?? 0,
                    imageURL: openFoodProduct.imageURL ?? openFoodProduct.imageFrontURL
                )
            }

            // Rückgabe der AI-Ergebnisse via Completion Handler
            completion(aiProducts)

            // Konvertiere zu FoodItem für Rückgabe
            return openFoodProducts.map { openFoodProduct in
                FoodItem(
                    name: openFoodProduct.productName ?? "Unknown",
                    carbs: Decimal(openFoodProduct.nutriments.carbohydrates),
                    fat: Decimal(openFoodProduct.nutriments.fat ?? 0),
                    protein: Decimal(openFoodProduct.nutriments.proteins ?? 0),
                    source: openFoodProduct.brands ?? "OpenFoodFacts",
                    imageURL: openFoodProduct.imageURL ?? openFoodProduct.imageFrontURL
                )
            }
        } catch {
            print("❌ AI Search failed: \(error.localizedDescription)")
            completion([])
            return []
        }
    }
}
