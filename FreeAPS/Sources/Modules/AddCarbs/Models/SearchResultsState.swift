import Combine
import Foundation

class SearchResultsState: ObservableObject {
    @Published var searchResults: [FoodItemGroup] = []
    @Published var collapsedSections: Set<UUID> = []

    // Nutrition overrides (deltas applied to totals)
    @Published var nutritionOverrides: [NutrientType: Decimal] = [:]
    @Published var micronutrientOverrides: [MicroNutrient: Decimal] = [:]

    static var empty: SearchResultsState {
        SearchResultsState()
    }

    func deleteItem(_ foodItem: FoodItemDetailed) {
        if let section = searchResults.first(where: { $0.foodItems.contains(where: { $0.id == foodItem.id }) }),
           section.source == .database
        {
            hardDeleteItem(foodItem)
        } else {
            updateExistingItem(foodItem.copy(deleted: true))
        }
    }

    func undeleteItem(_ foodItem: FoodItemDetailed) {
        updateExistingItem(foodItem.copy(deleted: false))
    }

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
                return
            }
        }
    }

    // MARK: - Collapsed Sections

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

    // MARK: - Snapshot

    func copy() -> SearchResultsState {
        let snapshot = SearchResultsState()
        snapshot.searchResults = searchResults
        snapshot.collapsedSections = collapsedSections
        snapshot.nutritionOverrides = nutritionOverrides
        snapshot.micronutrientOverrides = micronutrientOverrides
        return snapshot
    }

    func restore(from snapshot: SearchResultsState) {
        searchResults = snapshot.searchResults
        collapsedSections = snapshot.collapsedSections
        nutritionOverrides = snapshot.nutritionOverrides
        micronutrientOverrides = snapshot.micronutrientOverrides
    }

    func clear() {
        searchResults = []
        collapsedSections.removeAll()
        nutritionOverrides.removeAll()
        micronutrientOverrides.removeAll()
    }

    // MARK: - Items

    var nonDeletedItems: [FoodItemDetailed] {
        searchResults.flatMap(\.foodItems).filter { !$0.deleted }
    }

    var nonDeletedItemCount: Int {
        nonDeletedItems.count
    }

    var hasVisibleContent: Bool {
        !searchResults.isEmpty
    }

    // MARK: - Macro Totals

    func baseTotal(_ nutrient: NutrientType) -> Decimal {
        nonDeletedItems.reduce(0) { sum, item in
            sum + (item.nutrientInThisPortion(nutrient) ?? 0)
        }
    }

    func total(_ nutrient: NutrientType) -> Decimal {
        max(baseTotal(nutrient) + (nutritionOverrides[nutrient] ?? 0), 0)
    }

    var totalCalories: Decimal {
        max(
            [
                .carbs: total(.carbs),
                .protein: total(.protein),
                .fat: total(.fat)
            ].calories,
            0
        )
    }

    var hasNutritionOverrides: Bool {
        !nutritionOverrides.isEmpty
    }

    // MARK: - Micronutrient Totals

    func baseTotal(_ micro: MicroNutrient) -> Decimal {
        nonDeletedItems.reduce(0) { sum, item in
            guard let entry = item.micronutrient.first(where: { $0.substance == micro }) else {
                return sum
            }

            let value: Decimal

            switch item.nutrition {
            case let .per100(_, portion):
                value = entry.amountPer100 / 100 * portion

            case let .perServing(_, multiplier):
                value = entry.amount * multiplier
            }

            return sum + value
        }
    }

    func total(_ micro: MicroNutrient) -> Decimal {
        max(baseTotal(micro) + (micronutrientOverrides[micro] ?? 0), 0)
    }

    var hasMicronutrientOverrides: Bool {
        !micronutrientOverrides.isEmpty
    }

    // MARK: - Nutrition Value Builders

    /// Meal-level macro totals, including manual overrides.
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

    /// Meal-level micronutrient totals, including manual overrides.
    var mealMicronutrientValues: [MicroNutrient: Decimal] {
        var values: [MicroNutrient: Decimal] = [:]

        for micro in MicroNutrient.allCases {
            let value = total(micro)

            if value > 0 {
                values[micro] = value
            }
        }

        return values
    }

    /// Combined macro + micro nutrition object.
    var aggregatedNutrition: AggregatedNutrition {
        AggregatedNutrition(
            macros: mealNutritionValues,
            micros: mealMicronutrientValues
        )
    }

    /// Macro values from a specific subset of items, no overrides applied.
    func nutritionValues(for items: [FoodItemDetailed]) -> NutritionValues {
        var values: NutritionValues = [:]

        for nutrient in NutrientType.allCases {
            let sum = items.reduce(Decimal(0)) {
                $0 + ($1.nutrientInThisPortion(nutrient) ?? 0)
            }

            if sum > 0 || nutrient.isPrimary {
                values[nutrient] = sum
            }
        }

        return values
    }

    /// Micronutrient values from a specific subset of items, no overrides applied.
    func micronutrientValues(for items: [FoodItemDetailed]) -> [MicroNutrient: Decimal] {
        var result: [MicroNutrient: Decimal] = [:]

        for item in items {
            for micro in item.micronutrient {
                let value: Decimal

                switch item.nutrition {
                case let .per100(_, portion):
                    value = micro.amountPer100 / 100 * portion

                case let .perServing(_, multiplier):
                    value = micro.amount * multiplier
                }

                result[micro.substance, default: 0] += value
            }
        }

        return result
    }

    func aggregateServingSize(for items: [FoodItemDetailed]) -> Decimal? {
        var total: Decimal = 0

        for item in items {
            switch item.nutrition {
            case let .per100(_, portionSize):
                total += portionSize

            case let .perServing(_, multiplier):
                guard let servingSize = item.standardServingSize else {
                    return nil
                }

                total += servingSize * multiplier
            }
        }

        return total
    }
}
