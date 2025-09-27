import Foundation

extension OpenFoodFactsProduct {
    func toFoodItem() -> FoodItem {
        FoodItem(
            name: productName ?? "Unknown",
            carbs: Decimal(nutriments.carbohydrates),
            fat: Decimal(nutriments.fat ?? 0),
            protein: Decimal(nutriments.proteins ?? 0),
            source: brands ?? "OpenFoodFacts",
            imageURL: imageURL ?? imageFrontURL
        )
    }
}
