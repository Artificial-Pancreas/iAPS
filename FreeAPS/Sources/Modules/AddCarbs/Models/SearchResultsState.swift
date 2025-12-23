import Foundation

class SearchResultsState: ObservableObject {
    @Published var searchResults: [FoodItemGroup] = []

    @Published var editedItems: [String: EditableFoodItem] = [:]
    @Published var deletedSections: Set<UUID> = []
    @Published var collapsedSections: Set<UUID> = []

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
            // Initialize with the appropriate value based on nutrition type
            switch foodItem.nutrition {
            case .per100:
                portionSize = foodItem.portionSize ?? 0
            case .perServing:
                portionSize = foodItem.servingsMultiplier ?? 0
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

    // Mark item as deleted
    func deleteItem(_ foodItem: FoodItemDetailed) {
        let key = foodItem.id.uuidString
        if editedItems[key] == nil {
            editedItems[key] = EditableFoodItem(from: foodItem)
        }
        editedItems[key]?.isDeleted = true
    }

    // Undelete an item
    func undeleteItem(_ foodItem: FoodItemDetailed) {
        let key = foodItem.id.uuidString
        editedItems[key]?.isDeleted = false
    }

    // Hard delete an item (permanently removes it from search results)
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

    // Delete entire section
    func deleteSection(_ sectionId: UUID) {
        deletedSections.insert(sectionId)
    }

    // Check if section is deleted
    func isSectionDeleted(_ sectionId: UUID) -> Bool {
        deletedSections.contains(sectionId)
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
        deletedSections.removeAll()
        collapsedSections.removeAll()
    }

    // MARK: - Computed Properties

    var visibleSections: [FoodItemGroup] {
        searchResults.filter { !isSectionDeleted($0.id) }
    }

    var nonDeletedItems: [FoodItemDetailed] {
        visibleSections.flatMap(\.foodItemsDetailed).filter { !isDeleted($0) }
    }

    var nonDeletedItemCount: Int {
        nonDeletedItems.count
    }

    var hasVisibleContent: Bool {
        // Only deleted sections count as removing content (item deletions can be undone)
        !visibleSections.isEmpty
    }
}
