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
            portionSize = foodItem.portionSize ?? 0
        }
    }

    // Public accessor for current edited state
    var currentEditedItems: [EditableFoodItem] {
        editedItems.values.filter { !$0.isDeleted }
    }

    // Helper to get current portion size for a food item
    func portionSize(for foodItem: FoodItemDetailed) -> Decimal {
        let key = foodItem.id.uuidString
        return editedItems[key]?.portionSize ?? foodItem.portionSize ?? 0
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
}
