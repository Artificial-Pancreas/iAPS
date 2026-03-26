import Combine
import Foundation

class SearchResultsState: ObservableObject {
    @Published var searchResults: [FoodItemGroup] = []
    @Published var collapsedSections: Set<UUID> = []

    // Nutrition overrides (deltas applied to totals)
    // Empty dict means no overrides; non-nil value for a key means user has entered an override
    @Published var nutritionOverrides: [NutrientType: Decimal] = [:]

    static var empty: SearchResultsState {
        SearchResultsState()
    }

    func deleteItem(_ foodItem: FoodItemDetailed) {
        if let section = searchResults.first(where: { $0.foodItems.contains(where: { $0.id == foodItem.id }) }),
           section.source == .database
        {
            // if the food was added from saved foods - hard delete
            hardDeleteItem(foodItem)
        } else {
            // otherwise, soft delete
            updateExistingItem(foodItem.copy(deleted: true))
        }
    }

    func undeleteItem(_ foodItem: FoodItemDetailed) {
        updateExistingItem(foodItem.copy(deleted: false))
    }

    // Hard delete an item (permanently removes it from search results) - used when removing a food that was added from Saved Foods, or when adding/deleting from a multiple-choice selector
    func hardDeleteItem(_ foodItem: FoodItemDetailed) {
        for (index, group) in searchResults.enumerated() {
            if group.foodItems.contains(where: { $0.id == foodItem.id }) {
                let updatedFoodItems = group.foodItems.filter { $0.id != foodItem.id }

                if updatedFoodItems.isEmpty {
                    searchResults.remove(at: index)
                } else {
                    searchResults[index] = group.copyWithItems(updatedFoodItems)
                }
                break
            }
        }
    }

    // Hard delete entire section
    func deleteSection(_ sectionId: UUID) {
        guard let sectionIndex = searchResults.firstIndex(where: { $0.id == sectionId }) else {
            return
        }
        searchResults.remove(at: sectionIndex)
        collapsedSections.remove(sectionId)
    }

    func updateExistingItem(_ updatedItem: FoodItemDetailed) {
        for (groupIndex, group) in searchResults.enumerated() {
            if let itemIndex = group.foodItems.firstIndex(where: { $0.id == updatedItem.id }) {
                var updatedFoodItems = group.foodItems
                updatedFoodItems[itemIndex] = updatedItem
                searchResults[groupIndex] = group.copyWithItems(updatedFoodItems)
                return // same item will not be in different groups
            }
        }
    }

    // MARK: - Collapsed sections helpers

    func isSectionCollapsed(_ sectionId: UUID) -> Bool {
        collapsedSections.contains(sectionId)
    }

    func toggleSectionCollapsed(_ sectionId: UUID) {
        if collapsedSections.contains(sectionId) {
            collapsedSections.remove(sectionId)
        } else {
            collapsedSections.insert(sectionId)
        }
    }

    func copy() -> SearchResultsState {
        let snapshot = SearchResultsState()
        snapshot.searchResults = searchResults
        snapshot.collapsedSections = collapsedSections
        snapshot.nutritionOverrides = nutritionOverrides
        return snapshot
    }

    func restore(from snapshot: SearchResultsState) {
        searchResults = snapshot.searchResults
        collapsedSections = snapshot.collapsedSections
        nutritionOverrides = snapshot.nutritionOverrides
    }

    func clear() {
        searchResults = []
        collapsedSections.removeAll()
        nutritionOverrides.removeAll()
    }

    // MARK: - Computed Properties

    var nonDeletedItems: [FoodItemDetailed] {
        searchResults.flatMap(\.foodItems).filter { !$0.deleted }
    }

    var nonDeletedItemCount: Int {
        nonDeletedItems.count
    }

    var hasVisibleContent: Bool {
        !searchResults.isEmpty
    }

    // MARK: - Computed Nutrition Totals

    func baseTotal(_ nutrient: NutrientType) -> Decimal {
        nonDeletedItems.reduce(0) { sum, item in
            sum + (item.nutrientInThisPortion(nutrient) ?? 0)
        }
    }

    func total(_ nutrient: NutrientType) -> Decimal {
        max(baseTotal(nutrient) + (nutritionOverrides[nutrient] ?? 0), 0)
    }

    var totalCalories: Decimal {
        max([NutrientType.carbs: total(.carbs), .protein: total(.protein), .fat: total(.fat)].calories, 0)
    }

    var hasNutritionOverrides: Bool {
        !nutritionOverrides.isEmpty
    }

    // MARK: - Nutrition value builders (for saving food items)

    /// Build nutrition values from meal-level totals (includes manual overrides)
    var mealNutritionValues: NutritionValues {
        var values: NutritionValues = [:]
        for nutrient in NutrientType.allCases {
            let value = total(nutrient)
            if value > 0 || nutrient.isPrimary {
                values[nutrient] = value
            }
        }
        return values
    }

    /// Build nutrition values from a specific subset of items (no overrides applied)
    func nutritionValues(for items: [FoodItemDetailed]) -> NutritionValues {
        var values: NutritionValues = [:]
        for nutrient in NutrientType.allCases {
            let sum = items
                .reduce(Decimal(0)) {
                    $0 + ($1.nutrientInThisPortion(nutrient) ?? 0) }
            if sum > 0 || nutrient.isPrimary {
                values[nutrient] = sum
            }
        }
        return values
    }

    func aggregateServingSize(for items: [FoodItemDetailed]) -> Decimal? {
        var total: Decimal = 0
        for item in items {
            switch item.nutrition {
            case let .per100(_, portionSize):
                total += portionSize
            case let .perServing(_, multiplier):
                guard let servingSize = item.standardServingSize else { return nil }
                total += servingSize * multiplier
            }
        }
        return total
    }
}
