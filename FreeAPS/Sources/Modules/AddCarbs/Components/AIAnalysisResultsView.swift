import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var state: FoodSearchStateModel
    let onFoodItemSelected: (AIFoodItem) -> Void
    let onCompleteMealSelected: (AIFoodItem) -> Void

    @State private var clearedResults: [FoodAnalysisResult] = []
    @State private var clearedResultsViewState: SearchResultsState?

    private var visibleSections: [FoodAnalysisResult] {
        state.searchResults.filter({ !state.resultsView.isSectionDeleted($0.id) })
    }

    private var allFoodItems: [AnalysedFoodItem] {
        visibleSections.flatMap(\.foodItemsDetailed)
    }

    private var nonDeletedItemCount: Int {
        allFoodItems.filter { !state.resultsView.isDeleted($0) }.count
    }

    private var totalCalories: Decimal {
        allFoodItems.reduce(0) { sum, item in
            guard !state.resultsView.isDeleted(item) else { return sum }
            let portion = state.resultsView.portionSize(for: item)
            return sum + (item.caloriesInPortion(portion: portion) ?? 0)
        }
    }

    private var totalCarbs: Decimal {
        allFoodItems.reduce(0) { sum, item in
            guard !state.resultsView.isDeleted(item) else { return sum }
            let portion = state.resultsView.portionSize(for: item)
            return sum + (item.carbsInPortion(portion: portion) ?? 0)
        }
    }

    private var totalProtein: Decimal {
        allFoodItems.reduce(0) { sum, item in
            guard !state.resultsView.isDeleted(item) else { return sum }
            let portion = state.resultsView.portionSize(for: item)
            return sum + (item.proteinInPortion(portion: portion) ?? 0)
        }
    }

    private var totalFat: Decimal {
        allFoodItems.reduce(0) { sum, item in
            guard !state.resultsView.isDeleted(item) else { return sum }
            let portion = state.resultsView.portionSize(for: item)
            return sum + (item.fatInPortion(portion: portion) ?? 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Loading indicator
            if state.isLoading {
                loadingBanner()
            }
            // Error message (only when not loading)
            else if let latestSearchError = state.latestSearchError {
                errorMessageBanner(message: latestSearchError, icon: state.latestSearchIcon)
            }

            // Undo button (shown after clearing, regardless of empty/non-empty state)
            if clearedResultsViewState != nil {
                undoButton
            }

            // Always show results if available, otherwise show empty state
            if state.searchResults.isEmpty {
                noSearchesView
            } else {
                searchResultsView
            }
        }
        .onChange(of: state.searchResults) { _, newValue in
            if clearedResultsViewState != nil, !newValue.isEmpty {
                withAnimation(.easeOut(duration: 0.2)) {
                    clearedResults = []
                    clearedResultsViewState = nil
                }
            }
        }
    }

    private var undoButton: some View {
        HStack(alignment: .center) {
            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Restore cleared results and state
                    state.searchResults = clearedResults
                    if let savedState = clearedResultsViewState {
                        state.resultsView.editedItems = savedState.editedItems
                        state.resultsView.deletedSections = savedState.deletedSections
                        state.resultsView.collapsedSections = savedState.collapsedSections
                    }

                    clearedResults = []
                    clearedResultsViewState = nil
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13))
                    Text("Undo Clear")
                        .font(.subheadline)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemGray5))
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemGray6).opacity(0.5),
                    Color(.systemGray6).opacity(0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.2)),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func loadingBanner() -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func errorMessageBanner(message: String, icon: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon ?? "exclamationmark.circle")
                .font(.system(size: 18))
                .foregroundColor(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.latestSearchError = nil
                    state.latestSearchIcon = nil
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var searchResultsView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text("\(nonDeletedItemCount) \(nonDeletedItemCount == 1 ? "Food Item" : "Food Items")")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    // Clear All button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            // Save current state for undo
                            clearedResults = state.searchResults
                            clearedResultsViewState = SearchResultsState()
                            clearedResultsViewState?.editedItems = state.resultsView.editedItems
                            clearedResultsViewState?.deletedSections = state.resultsView.deletedSections
                            clearedResultsViewState?.collapsedSections = state.resultsView.collapsedSections

                            // Clear everything
                            state.searchResults = []
                            state.resultsView.clear()
                            state.latestSearchError = nil
                            state.latestSearchIcon = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 13))
                            Text("Clear All")
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(.systemGray5))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    if nonDeletedItemCount > 0 {
                        Button(action: {
                            let mealName = nonDeletedItemCount == 1 ?
                                allFoodItems.first(where: { !state.resultsView.isDeleted($0) })?.name ?? "Meal" :
                                "Complete Meal"

                            let totalMeal = AIFoodItem(
                                name: mealName,
                                brand: nil,
                                calories: totalCalories,
                                carbs: totalCarbs,
                                protein: totalProtein,
                                fat: totalFat,
                                imageURL: nonDeletedItemCount == 1 ? allFoodItems
                                    .first(where: { !state.resultsView.isDeleted($0) })?
                                    .imageURL : nil,
                                source: state.searchResults.first?.source ?? .ai
                            )
                            onCompleteMealSelected(totalMeal)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(nonDeletedItemCount == 1 ? "Add" : "Add All")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                if nonDeletedItemCount > 1 {
                    // Nutrition badges in a card-like container
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            NutritionBadge(
                                value: totalCarbs,
                                label: "carbs",
                                color: NutritionBadgeConfig.carbsColor
                            )
                            .id("carbs-\(totalCarbs)")
                            .transition(.scale.combined(with: .opacity))

                            if totalProtein != 0 {
                                NutritionBadge(
                                    value: totalProtein,
                                    label: "protein",
                                    color: NutritionBadgeConfig.proteinColor
                                )
                                .id("protein-\(totalProtein)")
                                .transition(.scale.combined(with: .opacity))
                            }

                            if totalFat != 0 {
                                NutritionBadge(
                                    value: totalFat,
                                    label: "fat",
                                    color: NutritionBadgeConfig.fatColor
                                )
                                .id("fat-\(totalFat)")
                                .transition(.scale.combined(with: .opacity))
                            }
                            NutritionBadge(
                                value: totalCalories,
                                unit: "kcal",
                                color: NutritionBadgeConfig.caloriesColor
                            )
                            .id("calories-\(totalCalories)")
                            .transition(.scale.combined(with: .opacity))
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: totalCarbs)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: totalProtein)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: totalFat)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: totalCalories)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemGray6).opacity(0.5),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color.gray.opacity(0.2)),
                alignment: .bottom
            )
            List {
                ForEach(visibleSections) { analysisResult in
                    AnalysisResultListSection(
                        analysisResult: analysisResult,
                        state: state,
                        onFoodItemSelected: onFoodItemSelected
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .scrollContentBackground(.hidden)
        }
    }

    private var noSearchesView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.title)
                .foregroundColor(.orange)

            Text(NSLocalizedString("No Foods Found", comment: "Title when no food search results"))
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Text(NSLocalizedString(
                    "Check your spelling and try again",
                    comment: "Primary suggestion when no food search results"
                ))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString(
                    "Try simpler terms like \"bread\" or \"apple\", or scan a barcode",
                    comment: "Secondary suggestion when no food search results"
                ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Helpful suggestions
            VStack(spacing: 4) {
                Text("💡 Search Tips:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text("• Use simple, common food names")
                    Text("• Try brand names (e.g., \"Cheerios\")")
                    Text("• Check spelling carefully")
                    Text("• Use the barcode scanner for packaged foods")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

class SearchResultsState: ObservableObject {
    @Published var editedItems: [String: EditableFoodItem] = [:]
    @Published var deletedSections: Set<UUID> = []
    @Published var collapsedSections: Set<UUID> = []

    static var empty: SearchResultsState {
        SearchResultsState()
    }

    struct EditableFoodItem: Identifiable {
        let id = UUID()
        let original: AnalysedFoodItem
        var portionSize: Decimal
        var isDeleted: Bool = false

        init(from foodItem: AnalysedFoodItem) {
            original = foodItem
            portionSize = foodItem.portionEstimateSize ?? 0
        }
    }

    // Public accessor for current edited state
    var currentEditedItems: [EditableFoodItem] {
        editedItems.values.filter { !$0.isDeleted }
    }

    // Helper to get current portion size for a food item
    func portionSize(for foodItem: AnalysedFoodItem) -> Decimal {
        let key = foodItem.id.uuidString
        return editedItems[key]?.portionSize ?? foodItem.portionEstimateSize ?? 0
    }

    // Helper to check if item is deleted
    func isDeleted(_ foodItem: AnalysedFoodItem) -> Bool {
        let key = foodItem.id.uuidString
        return editedItems[key]?.isDeleted ?? false
    }

    // Update portion size for an item
    func updatePortion(for foodItem: AnalysedFoodItem, to newPortion: Decimal) {
        let key = foodItem.id.uuidString
        if editedItems[key] == nil {
            editedItems[key] = EditableFoodItem(from: foodItem)
        }
        editedItems[key]?.portionSize = newPortion
    }

    // Mark item as deleted
    func deleteItem(_ foodItem: AnalysedFoodItem) {
        let key = foodItem.id.uuidString
        if editedItems[key] == nil {
            editedItems[key] = EditableFoodItem(from: foodItem)
        }
        editedItems[key]?.isDeleted = true
    }

    // Undelete an item
    func undeleteItem(_ foodItem: AnalysedFoodItem) {
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

    // Clear all state
    func clear() {
        editedItems.removeAll()
        deletedSections.removeAll()
        collapsedSections.removeAll()
    }
}

private extension FoodItemSource {
    var icon: String {
        switch self {
        case .ai:
            return "photo"
        case .aiText:
            return "text.bubble"
        case .search:
            return "magnifyingglass"
        case .barcode:
            return "barcode"
        case .manual:
            return "pencil"
        }
    }
}

private extension FoodAnalysisResult {
    var title: String {
        switch source {
        case .manual: NSLocalizedString("Manual entry", comment: "Section with manualy entered foods")
        case .barcode: NSLocalizedString("Barcode scan", comment: "Section with bar code scan results")
        case .search: NSLocalizedString("Online database search", comment: "Section with online database search results")
        case .ai,
             .aiText: briefDescription ?? textQuery ?? NSLocalizedString(
                "AI Results",
                comment: "Section with AI food analysis results, when details are unavailable"
            )
        case nil: ""
        }
    }
}

private enum NutritionBadgeConfig {
    static let caloriesColor = Color.red
    static let carbsColor = Color.orange
    static let proteinColor = Color.green
    static let fatColor = Color.blue
    static let fiberColor = Color.purple
    static let sugarsColor = Color.purple
}

// Unified nutrition badge used throughout the file
private struct NutritionBadge: View {
    let value: Decimal
    let unit: String?
    let label: String?
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    init(value: Decimal, unit: String? = nil, label: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.label = label
        self.color = color
    }

    private var backgroundOpacity: Double {
        colorScheme == .dark ? 0.25 : 0.15
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(Double(value), specifier: unit == "kcal" || value > 20 ? "%.0f" : "%.1f")")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize()
            if let unit = unit {
                Text(unit)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            if let label = label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.lowercase)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(backgroundOpacity))
        .cornerRadius(8)
    }
}

private struct ConfidenceBadge: View {
    let level: AIConfidenceLevel

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundOpacity: Double {
        colorScheme == .dark ? 0.2 : 0.4
    }

    private var textColor: Color {
        colorScheme == .dark ? level.color : .primary.opacity(0.75)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain")
                .font(.system(size: 14))

            Text(level.description)
                .font(.caption)
                .fontWeight(.regular)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(level.color.opacity(backgroundOpacity))
        .foregroundColor(textColor)
        .cornerRadius(6)
    }
}

private struct AnalysisResultListSection: View {
    let analysisResult: FoodAnalysisResult
    @ObservedObject var state: FoodSearchStateModel
    let onFoodItemSelected: (AIFoodItem) -> Void

    @State private var showInfoPopup = false

    private var preferredInfoHeight: CGFloat {
        var base: CGFloat = 420
        if let desc = analysisResult.overallDescription, !desc.isEmpty { base += 60 }
        if let diabetes = analysisResult.diabetesConsiderations, !diabetes.isEmpty { base += 60 }
        if let notes = analysisResult.notes, !notes.isEmpty { base += 60 }
        return min(max(base, 400), 640)
    }

    private var nonDeletedItemCount: Int {
        analysisResult.foodItemsDetailed.filter { !state.resultsView.isDeleted($0) }.count
    }

    var body: some View {
        Group {
            // Section Header Row
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Collapse/Expand button (left side)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.resultsView.toggleSectionCollapsed(analysisResult.id)
                        }
                    }) {
                        Image(
                            systemName: state.resultsView
                                .isSectionCollapsed(analysisResult.id) ? "chevron.right" : "chevron.down"
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Title (tappable to collapse/expand)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.resultsView.toggleSectionCollapsed(analysisResult.id)
                        }
                    }) {
                        Text(analysisResult.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Info button (only for AI sources)
                    if analysisResult.source == .ai || analysisResult.source == .aiText {
                        Button(action: {
                            showInfoPopup = true
                        }) {
                            HStack(spacing: 0) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                if let icon = analysisResult.source?.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        if let icon = analysisResult.source?.icon {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .background(Color(.systemGray5))
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.resultsView.deleteSection(analysisResult.id)
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
            .sheet(isPresented: $showInfoPopup) {
                SectionInfoPopup(analysisResult: analysisResult)
                    .presentationDetents([.height(preferredInfoHeight), .large])
                    .presentationDragIndicator(.visible)
            }

            // Food Items
            if !state.resultsView.isSectionCollapsed(analysisResult.id) {
                ForEach(Array(analysisResult.foodItemsDetailed.enumerated()), id: \.element.name) { index, foodItem in
                    Group {
                        if state.resultsView.isDeleted(foodItem) {
                            DeletedFoodItemRow(
                                foodItem: foodItem,
                                onUndelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        state.resultsView.undeleteItem(foodItem)
                                    }
                                },
                                isFirst: index == 0,
                                isLast: index == analysisResult.foodItemsDetailed.count - 1
                            )
                        } else {
                            FoodItemRow(
                                foodItem: foodItem,
                                portionSize: state.resultsView.portionSize(for: foodItem),
                                onPortionChange: { newPortion in
                                    state.resultsView.updatePortion(for: foodItem, to: newPortion)
                                },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        state.resultsView.deleteItem(foodItem)
                                    }
                                },
                                onSelect: {
                                    let currentPortion = state.resultsView.portionSize(for: foodItem)
                                    let selectedFood = AIFoodItem(
                                        name: foodItem.name,
                                        brand: foodItem.brand,
                                        calories: foodItem.caloriesInPortion(portion: currentPortion) ?? 0,
                                        carbs: foodItem.carbsInPortion(portion: currentPortion) ?? 0,
                                        protein: foodItem.proteinInPortion(portion: currentPortion) ?? 0,
                                        fat: foodItem.fatInPortion(portion: currentPortion) ?? 0,
                                        imageURL: foodItem.imageURL,
                                        source: foodItem.source
                                    )
                                    onFoodItemSelected(selectedFood)
                                },
                                isFirst: index == 0,
                                isLast: index == analysisResult.foodItemsDetailed.count - 1,
                                showSelectButton: false
                            )
                        }
                    }
                    .listRowSeparator(index == analysisResult.foodItemsDetailed.count - 1 ? .hidden : .visible)
                }
            }
        }
    }
}

struct DeletedFoodItemRow: View {
    let foodItem: AnalysedFoodItem
    let onUndelete: () -> Void
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(foodItem.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary.opacity(0.4))
                    .strikethrough(true, color: .primary.opacity(0.3))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("Removed from meal")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
            }

            Spacer()

            Button(action: onUndelete) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                    Text("Undo")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .padding(.top, isFirst ? 8 : 0)
        .padding(.bottom, isLast ? 8 : 0)
        .background(Color(.systemGray6))
    }
}

private struct SectionInfoPopup: View {
    let analysisResult: FoodAnalysisResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                if let title = analysisResult.briefDescription, !title.isEmpty {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                }

                // Description
                if let description = analysisResult.overallDescription, !description.isEmpty {
                    InfoCard(icon: "text.quote", title: "Description", content: description, color: .gray, embedIcon: true)
                        .padding(.horizontal)
                }

                // Diabetes Recommendations
                if let diabetesInfo = analysisResult.diabetesConsiderations, !diabetesInfo.isEmpty {
                    InfoCard(
                        icon: "cross.case.fill",
                        title: "Diabetes Recommendations",
                        content: diabetesInfo,
                        color: .blue,
                        embedIcon: true
                    )
                    .padding(.horizontal)
                }

                // Notes
                if let notes = analysisResult.notes, !notes.isEmpty {
                    InfoCard(icon: "note.text", title: "Notes", content: notes, color: .gray, embedIcon: true)
                        .padding(.horizontal)
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
    }
}

private struct FoodItemInfoPopup: View {
    let foodItem: AnalysedFoodItem
    let portionSize: Decimal

    // Helper functions to avoid type inference issues
    private func shouldShowStandardServing(_ item: AnalysedFoodItem) -> Bool {
        let hasDescription = item.standardServing != nil && !(item.standardServing?.isEmpty ?? true)
        let hasSize = item.standardServingSize != nil
        return hasDescription || hasSize
    }

    @ViewBuilder private func standardServingContent(
        foodItem: AnalysedFoodItem,
        portionSize _: Decimal,
        unit _: String
    ) -> some View {
        if let servingDescription = foodItem.standardServing, !servingDescription.isEmpty {
            Text(servingDescription)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private func standardServingTitle(foodItem: AnalysedFoodItem, unit: String) -> String {
        if let servingSize = foodItem.standardServingSize {
            let formattedSize = String(format: "%.0f", Double(truncating: servingSize as NSNumber))
            return "Standard Serving - \(formattedSize) \(unit)"
        }
        return "Standard Serving"
    }

    var body: some View {
        let amount = String(format: "%.0f", Double(truncating: portionSize as NSNumber))
        let unit = NSLocalizedString((foodItem.units ?? .grams).localizedAbbreviation, comment: "")

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(foodItem.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .padding(.horizontal)
                if let visualCues = foodItem.visualCues, !visualCues.isEmpty {
                    InfoCard(icon: "eye.fill", title: "Visual Cues", content: visualCues, color: .blue, embedIcon: true)
                        .padding(.horizontal)
                }

                // Portion badge with source icon and confidence on same row
                HStack(spacing: 8) {
                    // Portion badge (neutral style matching food row)
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .opacity(0.3)

                        HStack(spacing: 3) {
                            Text("\(amount)")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.primary)
                            Text(unit)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .opacity(0.4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray4))
                    .cornerRadius(10)

                    Spacer()

                    // Source icon and confidence on the right
                    HStack(spacing: 8) {
                        // Confidence badge (if AI source)
                        if foodItem.source == .ai || foodItem.source == .aiText, let confidence = foodItem.confidence {
                            ConfidenceBadge(level: confidence)
                        }

                        // Source icon
                        if let icon = foodItem.source?.icon {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    // Header row
                    HStack {
                        Spacer()
                        Text("This portion")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)

                        Text("Per 100\(unit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Divider()

                    DetailedNutritionRow(
                        label: "Carbs",
                        portionValue: foodItem.carbsInPortion(portion: portionSize),
                        per100Value: foodItem.carbsPer100,
                        unit: "g"
                    )
                    Divider()
                    DetailedNutritionRow(
                        label: "Protein",
                        portionValue: foodItem.proteinInPortion(portion: portionSize),
                        per100Value: foodItem.proteinPer100,
                        unit: "g"
                    )
                    Divider()
                    DetailedNutritionRow(
                        label: "Fat",
                        portionValue: foodItem.fatInPortion(portion: portionSize),
                        per100Value: foodItem.fatPer100,
                        unit: "g"
                    )

                    // Optional additional nutrition
                    if let fiberPer100 = foodItem.fiberPer100, fiberPer100 > 0 {
                        Divider()
                        DetailedNutritionRow(
                            label: "Fiber",
                            portionValue: fiberPer100 / 100 * portionSize,
                            per100Value: fiberPer100,
                            unit: "g"
                        )
                    }
                    if let sugarsPer100 = foodItem.sugarsPer100, sugarsPer100 > 0 {
                        Divider()
                        DetailedNutritionRow(
                            label: "Sugar",
                            portionValue: sugarsPer100 / 100 * portionSize,
                            per100Value: sugarsPer100,
                            unit: "g"
                        )
                    }
                    Divider()
                    DetailedNutritionRow(
                        label: "Calories",
                        portionValue: foodItem.caloriesInPortion(portion: portionSize),
                        per100Value: foodItem.caloriesPer100,
                        unit: "kcal"
                    )
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal)

                // Standard serving information
                if shouldShowStandardServing(foodItem) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(standardServingTitle(foodItem: foodItem, unit: unit), systemImage: "chart.bar.doc.horizontal")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        standardServingContent(foodItem: foodItem, portionSize: portionSize, unit: unit)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                // Metadata sections (preparation, visual cues, notes)
                VStack(alignment: .leading, spacing: 12) {
                    if let preparation = foodItem.preparationMethod, !preparation.isEmpty {
                        InfoCard(icon: "flame.fill", title: "Preparation", content: preparation, color: .orange, embedIcon: true)
                    }
                    if let notes = foodItem.assessmentNotes, !notes.isEmpty {
                        InfoCard(icon: "note.text", title: "Notes", content: notes, color: .gray, embedIcon: true)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
    }
}

private struct NutritionRow: View {
    let label: String
    let value: Decimal?
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
            Spacer()
            if let value = value, value > 0 {
                HStack(spacing: 2) {
                    Text("\(Double(value), specifier: "%.1f")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(unit)
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }
}

private struct DetailedNutritionRow: View {
    let label: String
    let portionValue: Decimal?
    let per100Value: Decimal?
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Per portion value
            if let value = portionValue, value > 0 {
                HStack(spacing: 2) {
                    Text("\(Double(value), specifier: "%.1f")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(width: 90, alignment: .trailing)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 90, alignment: .trailing)
            }

            // Per 100g/ml value
            if let value = per100Value, value > 0 {
                HStack(spacing: 2) {
                    Text("\(Double(value), specifier: "%.1f")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(width: 90, alignment: .trailing)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let icon: String
    let title: String
    let content: String
    let color: Color
    let embedIcon: Bool

    init(icon: String, title: String, content: String, color: Color, embedIcon: Bool = false) {
        self.icon = icon
        self.title = title
        self.content = content
        self.color = color
        self.embedIcon = embedIcon
    }

    var body: some View {
        if embedIcon {
            HStack(alignment: .center, spacing: 0) {
                // Icon section with darker background
                ZStack(alignment: .center) {
                    color.opacity(0.25)
                        .cornerRadius(12, corners: [.topLeft, .bottomLeft])

                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                }
                .frame(width: 40)

                // Content section
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(color.opacity(0.08))
            .cornerRadius(12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.08))
            .cornerRadius(12)
        }
    }
}

// Helper for rounded corners on specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    // Helper for conditional view modifiers
    @ViewBuilder func when<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Food Item Row

struct FoodItemRow: View {
    let foodItem: AnalysedFoodItem
    let portionSize: Decimal
    let onPortionChange: ((Decimal) -> Void)?
    let onDelete: (() -> Void)?
    let onSelect: () -> Void
    let isFirst: Bool
    let isLast: Bool
    let showSelectButton: Bool

    @State private var showItemInfo = false
    @State private var showPortionAdjuster = false
    @State private var sliderMultiplier: Double = 1.0
    private var hasNutritionInfo: Bool {
        foodItem.caloriesPer100 != nil || foodItem.carbsPer100 != nil || foodItem.proteinPer100 != nil || foodItem
            .fatPer100 != nil
    }

    private var baseServingSize: Decimal {
        foodItem.standardServingSize ?? 100
    }

    // Helper to determine if confidence badge should be shown
    private var shouldShowConfidence: Bool {
        (foodItem.source == .ai || foodItem.source == .aiText) && foodItem.confidence != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Row Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(foodItem.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Select button (when in search results mode)
                    if showSelectButton {
                        Button(action: onSelect) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Select")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Source icon with confidence badge (if AI)
                    if !showSelectButton {
                        HStack(spacing: 0) {
                            // Confidence badge (if AI source)
                            if shouldShowConfidence, let confidence = foodItem.confidence {
                                ConfidenceBadge(level: confidence)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    PortionSizeBadge(
                        value: portionSize,
                        color: .orange,
                        icon: "scalemass.fill",
                        foodItem: foodItem
                    )

                    if let servingSize = foodItem.standardServingSize {
                        Text("\(Double(portionSize / servingSize), specifier: "%.1f")× serving")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .opacity(0.7)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                showItemInfo = true
            }
            .onLongPressGesture {
                if onPortionChange != nil {
                    showPortionAdjuster = true
                }
            }
            .sheet(isPresented: $showItemInfo) {
                FoodItemInfoPopup(foodItem: foodItem, portionSize: portionSize)
                    .presentationDetents([.height(preferredItemInfoHeight(for: foodItem)), .large])
                    .presentationDragIndicator(.visible)
            }

            // Compact nutrition info
            HStack(spacing: 6) {
                if let carbs = foodItem.carbsInPortion(portion: portionSize) {
                    NutritionBadge(value: carbs, label: "carbs", color: NutritionBadgeConfig.carbsColor)
                }
                if let protein = foodItem.proteinInPortion(portion: portionSize), protein > 0 {
                    NutritionBadge(value: protein, label: "protein", color: NutritionBadgeConfig.proteinColor)
                }
                if let fat = foodItem.fatInPortion(portion: portionSize), fat > 0 {
                    NutritionBadge(value: fat, label: "fat", color: NutritionBadgeConfig.fatColor)
                }
                if let calories = foodItem.caloriesInPortion(portion: portionSize), calories > 0 {
                    NutritionBadge(value: calories, unit: "kcal", color: NutritionBadgeConfig.caloriesColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, isFirst ? 8 : 0)
        .padding(.bottom, isLast ? 8 : 0)
        .background(Color(.systemGray6))
        .when(onDelete != nil) { view in
            view.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    onDelete?()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .when(onPortionChange != nil) { view in
            view.swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    showPortionAdjuster = true
                } label: {
                    Label("Edit Portion", systemImage: "slider.horizontal.3")
                }
                .tint(.orange)
            }
        }
        .when(onPortionChange != nil) { view in
            view.sheet(isPresented: $showPortionAdjuster) {
                PortionAdjusterView(
                    currentPortion: portionSize,
                    foodItem: foodItem,
                    sliderMultiplier: $sliderMultiplier,
                    onSave: { newPortion in
                        onPortionChange?(newPortion)
                        showPortionAdjuster = false
                    },
                    onReset: foodItem.portionEstimateSize != nil ? {
                        if let original = foodItem.portionEstimateSize {
                            onPortionChange?(original)
                            showPortionAdjuster = false
                        }
                    } : nil,
                    onCancel: {
                        showPortionAdjuster = false
                    }
                )
                .presentationDetents([.height(
                    hasNutritionInfo ? (foodItem.portionEstimateSize != nil ? 420 : 400) :
                        (foodItem.portionEstimateSize != nil ? 340 : 300)
                )])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: portionSize) { _, newValue in
            // Update multiplier when portion size changes externally
            if baseServingSize > 0 {
                sliderMultiplier = Double(newValue / baseServingSize)
            }
        }
        .onAppear {
            // Calculate initial multiplier based on current portion size
            if baseServingSize > 0 {
                sliderMultiplier = Double(portionSize / baseServingSize)
            }
        }
    }

    private func preferredItemInfoHeight(for item: AnalysedFoodItem) -> CGFloat {
        var base: CGFloat = 480
        if let notes = item.assessmentNotes, !notes.isEmpty { base += 40 }
        if let prep = item.preparationMethod, !prep.isEmpty { base += 30 }
        if let cues = item.visualCues, !cues.isEmpty { base += 30 }
        if (item.standardServing != nil && !item.standardServing!.isEmpty) ||
            item.standardServingSize != nil { base += 40 }
        return min(max(base, 460), 680)
    }
}

extension FoodItemRow {
    private struct PortionSizeBadge: View {
        let value: Decimal
        let color: Color
        let icon: String
        let foodItem: AnalysedFoodItem

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            HStack(spacing: 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .opacity(0.3)
                }
                HStack(spacing: 2) {
                    Text("\(Double(value), specifier: "%.0f")")
                        .font(.system(size: 15, weight: .bold))
                    Text(NSLocalizedString((foodItem.units ?? .grams).localizedAbbreviation, comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.4)
                }
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemGray4))
            .cornerRadius(8)
        }
    }

    private struct PortionAdjusterView: View {
        let currentPortion: Decimal
        let foodItem: AnalysedFoodItem
        @Binding var sliderMultiplier: Double
        let onSave: (Decimal) -> Void
        let onReset: (() -> Void)?
        let onCancel: () -> Void

        private var baseServingSize: Decimal {
            foodItem.standardServingSize ?? 100
        }

        private var unit: String {
            (foodItem.units ?? .grams).localizedAbbreviation
        }

        var calculatedPortion: Decimal {
            baseServingSize * Decimal(sliderMultiplier)
        }

        private func resetSliderToOriginal() {
            if let original = foodItem.portionEstimateSize, baseServingSize > 0 {
                sliderMultiplier = Double(original / baseServingSize)
            }
        }

        var body: some View {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(foodItem.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .padding(.top)

                VStack(spacing: 8) {
                    Text("\(Double(calculatedPortion), specifier: "%.0f") \(unit)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.orange)

                    Text("\(sliderMultiplier, specifier: "%.2f")× serving")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    Slider(value: $sliderMultiplier, in: 0.25 ... 5.0, step: 0.25)
                        .tint(.orange)

                    HStack {
                        Text("0.25x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("5x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Display nutritional information if available
                    if hasNutritionInfo {
                        HStack(spacing: 8) {
                            if let carbs = foodItem.carbsInPortion(portion: calculatedPortion), carbs > 0 {
                                NutritionBadge(value: carbs, label: "carbs", color: NutritionBadgeConfig.carbsColor)
                                    .frame(maxWidth: .infinity)
                            }
                            if let protein = foodItem.proteinInPortion(portion: calculatedPortion), protein > 0 {
                                NutritionBadge(value: protein, label: "protein", color: NutritionBadgeConfig.proteinColor)
                                    .frame(maxWidth: .infinity)
                            }
                            if let fat = foodItem.fatInPortion(portion: calculatedPortion), fat > 0 {
                                NutritionBadge(value: fat, label: "fat", color: NutritionBadgeConfig.fatColor)
                                    .frame(maxWidth: .infinity)
                            }
                            if let calories = foodItem.caloriesInPortion(portion: calculatedPortion), calories > 0 {
                                NutritionBadge(value: calories, unit: "kcal", color: NutritionBadgeConfig.caloriesColor)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                // Show reset button if original portion size is available
                if let original = foodItem.portionEstimateSize {
                    Button(action: resetSliderToOriginal) {
                        HStack {
                            Text("Reset to \(Double(original), specifier: "%.0f") \(unit)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(10)

                    Button("Apply") {
                        onSave(calculatedPortion)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }

        private var hasNutritionInfo: Bool {
            foodItem.caloriesPer100 != nil || foodItem.carbsPer100 != nil || foodItem.proteinPer100 != nil || foodItem
                .fatPer100 != nil
        }
    }
}

// MARK: - Text Search Results Sheet

struct TextSearchResultsSheet: View {
    let searchResult: FoodAnalysisResult
    let onFoodItemSelected: (AnalysedFoodItem) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header card with search info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)

                        if let query = searchResult.textQuery {
                            Text("Results for \"\(query)\"")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Search Results")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    Text(
                        "\(searchResult.foodItemsDetailed.count) \(searchResult.foodItemsDetailed.count == 1 ? "result" : "results") found"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Color.blue.opacity(0.08)
                )

                // Results list
                List {
                    ForEach(Array(searchResult.foodItemsDetailed.enumerated()), id: \.element.id) { index, foodItem in
                        if foodItem.name.isNotEmpty {
                            FoodItemRow(
                                foodItem: foodItem,
                                portionSize: foodItem.portionEstimateSize ?? foodItem.standardServingSize ?? 100,
                                onPortionChange: nil,
                                onDelete: nil,
                                onSelect: {
                                    onFoodItemSelected(foodItem)
                                },
                                isFirst: index == 0,
                                isLast: index == searchResult.foodItemsDetailed.count - 1,
                                showSelectButton: true
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color(.systemGray6))
                            .listRowSeparator(index == searchResult.foodItemsDetailed.count - 1 ? .hidden : .visible)
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color(.systemGroupedBackground))
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
    }
}
