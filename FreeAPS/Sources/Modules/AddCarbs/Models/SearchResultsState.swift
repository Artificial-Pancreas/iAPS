import Combine
import Foundation

class SearchResultsState: ObservableObject {
    @Published var searchResults: [FoodItemGroup] = []

    @Published var editedItems: [String: EditableFoodItem] = [:]
    @Published var collapsedSections: Set<UUID> = []

    // Nutrition overrides (deltas applied to totals)
    // Empty dict means no overrides; non-nil value for a key means user has entered an override
    @Published var nutritionOverrides: [NutrientType: Decimal] = [:]

    static var empty: SearchResultsState {
        SearchResultsState()
    }

    struct EditableFoodItem: Identifiable {
        let id = UUID()
        let original: FoodItemDetailed
        var portionSize: Decimal
        var isDeleted: Bool = false

        init(from foodItem: FoodItemDetailed) {
            original = foodItem
            switch foodItem.nutrition {
            case .per100:
                portionSize = foodItem.portionSize ?? 100
            case .perServing:
                portionSize = foodItem.servingsMultiplier ?? 1
            }
        }
    }

    // Public accessor for current edited state
    var currentEditedItems: [EditableFoodItem] {
        editedItems.values.filter { !$0.isDeleted }
    }

    // Helper to get current portion size for a food item
    // Note: For perServing items, this returns the servings multiplier
    func portionSize(for foodItem: FoodItemDetailed) -> Decimal {
        let key = foodItem.id.uuidString
        if let edited = editedItems[key] {
            return edited.portionSize
        }
        // Return the appropriate default based on nutrition type
        switch foodItem.nutrition {
        case .per100:
            return foodItem.portionSize ?? 0
        case .perServing:
            return foodItem.servingsMultiplier ?? 0
        }
    }

    // Helper to check if item is deleted
    func isDeleted(_ foodItem: FoodItemDetailed) -> Bool {
        let key = foodItem.id.uuidString
        return editedItems[key]?.isDeleted ?? false
    }

    // Update portion size for an item
    func updatePortion(for foodItem: FoodItemDetailed, to newPortion: Decimal) {
        let key = foodItem.id.uuidString
        if editedItems[key] == nil {
            editedItems[key] = EditableFoodItem(from: foodItem)
        }
        editedItems[key]?.portionSize = newPortion
    }

    func deleteItem(_ foodItem: FoodItemDetailed) {
        if let section = searchResults.first(where: { $0.foodItemsDetailed.contains(where: { $0.id == foodItem.id }) }) {
            // if the food was added from saved foods - hard delete
            if section.source == .database {
                hardDeleteItem(foodItem)
                return
            }
        }

        // otherwise, soft delete
        let key = foodItem.id.uuidString
        if editedItems[key] == nil {
            editedItems[key] = EditableFoodItem(from: foodItem)
        }
        editedItems[key]?.isDeleted = true
    }

    func undeleteItem(_ foodItem: FoodItemDetailed) {
        let key = foodItem.id.uuidString
        editedItems[key]?.isDeleted = false
    }

    // Hard delete an item (permanently removes it from search results) - used when removing a food that was added from Saved Foods, or when adding/deleting from a multiple-choise selector
    func hardDeleteItem(_ foodItem: FoodItemDetailed) {
        // Remove from search results
        for (index, group) in searchResults.enumerated() {
            if group.foodItemsDetailed.contains(where: { $0.id == foodItem.id }) {
                // Create new array without the deleted item
                let updatedFoodItems = group.foodItemsDetailed.filter { $0.id != foodItem.id }

                // If the group is now empty, remove the entire group
                if updatedFoodItems.isEmpty {
                    searchResults.remove(at: index)
                } else {
                    // Create new group with updated items
                    let updatedGroup = FoodItemGroup(
                        foodItemsDetailed: updatedFoodItems,
                        briefDescription: group.briefDescription,
                        overallDescription: group.overallDescription,
                        diabetesConsiderations: group.diabetesConsiderations,
                        source: group.source,
                        barcode: group.barcode,
                        textQuery: group.textQuery
                    )
                    searchResults[index] = updatedGroup
                }
                break
            }
        }

        // Also remove from edited items if it exists
        let key = foodItem.id.uuidString
        editedItems.removeValue(forKey: key)
    }

    // Hard delete entire section (removes from searchResults and cleans up editedItems)
    func deleteSection(_ sectionId: UUID) {
        // Find the section to delete
        guard let sectionIndex = searchResults.firstIndex(where: { $0.id == sectionId }) else {
            return
        }

        let section = searchResults[sectionIndex]

        // Clean up editedItems for all items in this section
        for item in section.foodItemsDetailed {
            let key = item.id.uuidString
            editedItems.removeValue(forKey: key)
        }

        // Remove the section from searchResults
        searchResults.remove(at: sectionIndex)

        // Clean up collapsed state if it exists
        collapsedSections.remove(sectionId)
    }

    /// Updates an existing food item in the search results while preserving portion size/multiplier
    func updateExistingItem(_ updatedItem: FoodItemDetailed) {
        // Find all instances of this item across all search results
        for (groupIndex, group) in searchResults.enumerated() {
            for (itemIndex, existingItem) in group.foodItemsDetailed.enumerated() {
                if existingItem.id == updatedItem.id {
                    // Preserve the current portion size or multiplier
                    let preservedPortion = portionSize(for: existingItem)

                    // Create a new group with the updated item
                    var updatedFoodItems = group.foodItemsDetailed
                    updatedFoodItems[itemIndex] = updatedItem

                    let updatedGroup = FoodItemGroup(
                        foodItemsDetailed: updatedFoodItems,
                        briefDescription: group.briefDescription,
                        overallDescription: group.overallDescription,
                        diabetesConsiderations: group.diabetesConsiderations,
                        source: group.source,
                        barcode: group.barcode,
                        textQuery: group.textQuery
                    )

                    searchResults[groupIndex] = updatedGroup

                    // Update editedItems to preserve the portion with the new item reference
                    let key = updatedItem.id.uuidString
                    if let edited = editedItems[key] {
                        editedItems[key] = EditableFoodItem(from: updatedItem)
                        editedItems[key]?.portionSize = preservedPortion
                        editedItems[key]?.isDeleted = edited.isDeleted
                    } else {
                        // Create new edited item with preserved portion
                        var newEdited = EditableFoodItem(from: updatedItem)
                        newEdited.portionSize = preservedPortion
                        editedItems[key] = newEdited
                    }
                }
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

    func clear() {
        searchResults = []
        editedItems.removeAll()
        collapsedSections.removeAll()
        nutritionOverrides.removeAll()
    }

    // MARK: - Computed Properties

    var nonDeletedItems: [FoodItemDetailed] {
        searchResults.flatMap(\.foodItemsDetailed).filter { !isDeleted($0) }
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
            sum + (item.nutrientInPortionOrServings(nutrient, portionOrMultiplier: portionSize(for: item)) ?? 0)
        }
    }

    func total(_ nutrient: NutrientType) -> Decimal {
        max(baseTotal(nutrient) + (nutritionOverrides[nutrient] ?? 0), 0)
    }

    var baseTotalCalories: Decimal {
        [NutrientType.carbs: baseTotal(.carbs), .protein: baseTotal(.protein), .fat: baseTotal(.fat)].calories
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
                    $0 + ($1.nutrientInPortionOrServings(nutrient, portionOrMultiplier: portionSize(for: $1)) ?? 0) }
            if sum > 0 || nutrient.isPrimary {
                values[nutrient] = sum
            }
        }
        return values
    }

    /// Compute aggregate serving size from a list of items; returns nil if any perServing item lacks a standardServingSize
    func aggregateServingSize(for items: [FoodItemDetailed]) -> Decimal? {
        var total: Decimal = 0
        for item in items {
            let portion = portionSize(for: item)
            switch item.nutrition {
            case .per100:
                total += portion
            case .perServing:
                guard let servingSize = item.standardServingSize else { return nil }
                total += servingSize * portion
            }
        }
        return total
    }
}
