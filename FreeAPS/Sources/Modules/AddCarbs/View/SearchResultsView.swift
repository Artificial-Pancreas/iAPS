import PhotosUI
import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var state: FoodSearchStateModel
    let onContinue: ([FoodItemDetailed], Date?) -> Void
    let onHypoTreatment: (([FoodItemDetailed], Date?) -> Void)?
    let onPersist: (FoodItemDetailed) -> Void
    let onDelete: (FoodItemDetailed) -> Void
    let continueButtonLabelKey: LocalizedStringKey
    let hypoTreatmentButtonLabelKey: LocalizedStringKey

    @State private var clearedResultsViewState: SearchResultsState?
    @State private var selectedTime: Date?
    @State private var showTimePicker = false
    @State private var isDownloadingImage = false

    private var nonDeletedItemCount: Int {
        state.searchResultsState.nonDeletedItemCount
    }

    private var hasVisibleContent: Bool {
        state.searchResultsState.hasVisibleContent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Only show these elements when NOT showing saved foods inline
            if !(state.savedFoods != nil && state.showSavedFoods) {
                // Loading indicator
                if state.isLoading {
                    loadingBanner()
                        .padding(.top, 12)
                        .padding(.horizontal)
                }
                // Image download indicator
                else if isDownloadingImage {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)

                        Text("Saving image...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .padding(.top, 12)
                    .padding(.horizontal)
                }
                // Error message (only when not loading)
                else if let latestSearchError = state.latestSearchError {
                    errorMessageBanner(message: latestSearchError, icon: state.latestSearchIcon)
                        .padding(.top, 12)
                        .padding(.horizontal)
                }

                // Undo button (shown after clearing, regardless of empty/non-empty state)
                if clearedResultsViewState != nil {
                    undoButton
                }

                VStack(alignment: .leading, spacing: 6) {
                    if hasVisibleContent {
                        mealTotalsView
                    }
                    actionButtonRow
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }

            if let savedFoods = state.savedFoods, state.showSavedFoods {
                // Show saved foods inline
                VStack(spacing: 0) {
                    FoodItemsSelectorView(
                        searchResult: savedFoods,
                        onFoodItemSelected: { selectedItem in
                            state.addItem(selectedItem, group: savedFoods)
                        },
                        onFoodItemRemoved: { removedItem in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.searchResultsState.deleteItem(removedItem)
                            }
                        },
                        isItemAdded: { foodItem in
                            state.searchResultsState.nonDeletedItems.contains(where: { $0.id == foodItem.id })
                        },
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                state.showSavedFoods = false
                            }
                        },
                        onImageSearch: state.searchFoodImages,
                        onPersist: persistFoodItem,
                        onDelete: onDelete,
                        useTransparentBackground: false,
                        filterText: state.filterText,
                        showTagCloud: true
                    )
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if !hasVisibleContent {
                noSearchesView
                    .transition(.opacity)
                    .scrollDismissesKeyboard(.immediately)
            } else {
                searchResultsView
                    .transition(.opacity)
                    .scrollDismissesKeyboard(.immediately)
            }
        }
        .onChange(of: state.searchResultsState.searchResults) {
            // Only clear undo state if we have new visible content
            let hasNewVisibleContent = !state.searchResultsState.searchResults.isEmpty &&
                !state.searchResultsState.searchResults.flatMap(\.foodItemsDetailed)
                .filter { !state.searchResultsState.isDeleted($0) }.isEmpty

            if clearedResultsViewState != nil, hasNewVisibleContent {
                withAnimation(.easeOut(duration: 0.2)) {
                    clearedResultsViewState = nil
                }
            }
        }
        .sheet(item: $state.latestMultipleSelectSearch) { searchResult in
            NavigationStack {
                FoodItemsSelectorView(
                    searchResult: searchResult,
                    onFoodItemSelected: { selectedItem in
                        state.addItem(selectedItem, group: searchResult)
                    },
                    onFoodItemRemoved: { removedItem in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.searchResultsState.hardDeleteItem(removedItem)
                        }
                    },
                    isItemAdded: { foodItem in
                        state.searchResultsState.nonDeletedItems.contains(where: { $0.id == foodItem.id })
                    },
                    onDismiss: {
                        state.latestMultipleSelectSearch = nil
                    },
                    onImageSearch: state.searchFoodImages,
                    onPersist: nil,
                    onDelete: nil,
                    useTransparentBackground: true
                )
                .navigationTitle(searchResult.textQuery == nil ? "Search Results" : "Results for '\(searchResult.textQuery!)'")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            state.latestMultipleSelectSearch = nil
                        }
                    }
                }
            }
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $state.showManualEntry) {
            FoodItemEditorSheet(
                existingItem: nil,
                title: "Add Food Manually",
                allExistingTags: Set(state.savedFoods?.foodItemsDetailed.flatMap { $0.tags ?? [] } ?? []),
                onSave: { foodItem in
                    state.addItem(foodItem, group: nil)
                    state.showManualEntry = false
                },
                onCancel: {
                    state.showManualEntry = false
                }
            )
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $state.showNewSavedFoodEntry) {
            FoodItemEditorSheet(
                existingItem: nil,
                title: "Create Saved Food",
                allExistingTags: Set(state.savedFoods?.foodItemsDetailed.flatMap { $0.tags ?? [] } ?? []),
                onSave: { foodItem in
                    persistFoodItem(foodItem)
                    state.showNewSavedFoodEntry = false
                },
                onCancel: {
                    state.showNewSavedFoodEntry = false
                }
            )
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var actionButtonRow: some View {
        HStack(alignment: .center) {
            if nonDeletedItemCount > 0 {
                // Time picker button
                Button(action: {
                    showTimePicker = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                        Text(selectedTime == nil ? "Now" : timeString(for: selectedTime!))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemGray5))
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            Spacer()

            if hasVisibleContent {
                if let onHypoTreatment = self.onHypoTreatment {
                    Button(action: {
                        let foodItems = state.searchResultsState.searchResults.flatMap(\.foodItemsDetailed)
                            .filter { !state.searchResultsState.isDeleted($0) }
                            .map { $0.withPortion(state.searchResultsState.portionSize(for: $0)) }
                        onHypoTreatment(foodItems, selectedTime)
                    }) {
                        Text(hypoTreatmentButtonLabelKey)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.orange.opacity(0.7))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                Button(action: {
                    let foodItems = state.searchResultsState.searchResults.flatMap(\.foodItemsDetailed)
                        .filter { !state.searchResultsState.isDeleted($0) }
                        .map { $0.withPortion(state.searchResultsState.portionSize(for: $0)) }
                    onContinue(foodItems, selectedTime)
                }) {
                    Text(continueButtonLabelKey)
                        .font(.subheadline)
                        .fontWeight(.semibold)
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
        .sheet(isPresented: $showTimePicker) {
            TimePickerSheet(selectedTime: $selectedTime, isPresented: $showTimePicker)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
    }

    private var mealTotalsView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Meal Totals")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                // Clear All button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // Save current state for undo
                        clearedResultsViewState = SearchResultsState()
                        clearedResultsViewState?.searchResults = state.searchResultsState.searchResults
                        clearedResultsViewState?.editedItems = state.searchResultsState.editedItems
                        clearedResultsViewState?.collapsedSections = state.searchResultsState.collapsedSections

                        // Clear everything
                        state.searchResultsState.clear()
                        state.latestSearchError = nil
                        state.latestSearchIcon = nil
                    }
                }) {
                    Text("Clear All")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                TotalNutritionBadge(
                    value: state.searchResultsState.totalCarbs,
                    label: "carbs",
                    color: NutritionBadgeConfig.carbsColor
                )
                .id("carbs-\(state.searchResultsState.totalCarbs)")
                .transition(.scale.combined(with: .opacity))

                TotalNutritionBadge(
                    value: state.searchResultsState.totalProtein,
                    label: "protein",
                    color: NutritionBadgeConfig.proteinColor
                )
                .id("protein-\(state.searchResultsState.totalProtein)")
                .transition(.scale.combined(with: .opacity))

                TotalNutritionBadge(
                    value: state.searchResultsState.totalFat,
                    label: "fat",
                    color: NutritionBadgeConfig.fatColor
                )
                .id("fat-\(state.searchResultsState.totalFat)")
                .transition(.scale.combined(with: .opacity))

                TotalNutritionBadge(
                    value: state.searchResultsState.totalCalories,
                    label: "kcal",
                    color: NutritionBadgeConfig.caloriesColor
                )
                .id("calories-\(state.searchResultsState.totalCalories)")
                .transition(.scale.combined(with: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.searchResultsState.totalCarbs)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.searchResultsState.totalProtein)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.searchResultsState.totalFat)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.searchResultsState.totalCalories)
        }
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
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
        .contextMenu {
            Button {
                saveMealTotalsAsFoodItem()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func saveMealTotalsAsFoodItem() {
        let allItems = state.searchResultsState.searchResults.flatMap(\.foodItemsDetailed)
            .filter { !state.searchResultsState.isDeleted($0) }

        guard !allItems.isEmpty else { return }

        // Calculate aggregate serving size (sum of all portion sizes for per100, and serving sizes for perServing)
        var aggregateServingSize: Decimal? = 0
        var hasAllServingSizes = true

        for item in allItems {
            let portionSize = state.searchResultsState.portionSize(for: item)

            switch item.nutrition {
            case .per100:
                // For per100, use the portion size directly
                aggregateServingSize? += portionSize

            case .perServing:
                // For perServing, use standardServingSize multiplied by servingsMultiplier
                if let servingSize = item.standardServingSize {
                    aggregateServingSize? += servingSize * portionSize
                } else {
                    // If any perServing item doesn't have a serving size, we can't calculate aggregate
                    hasAllServingSizes = false
                    break
                }
            }
        }

        // If we couldn't calculate complete serving size, set to nil
        if !hasAllServingSizes {
            aggregateServingSize = nil
        }

        // Create nutrition values from totals
        let nutritionValues = NutritionValues(
            calories: state.searchResultsState.totalCalories,
            carbs: state.searchResultsState.totalCarbs,
            fat: state.searchResultsState.totalFat,
            fiber: state.searchResultsState.totalFiber,
            protein: state.searchResultsState.totalProtein,
            sugars: state.searchResultsState.totalSugars
        )

        // Create new food item with per-serving nutrition
        let savedItem = FoodItemDetailed(
            name: "Complete Meal",
            nutritionPerServing: nutritionValues,
            servingsMultiplier: 1,
            confidence: nil,
            brand: nil,
            standardServing: nil,
            standardServingSize: aggregateServingSize,
            units: .grams,
            preparationMethod: nil,
            visualCues: nil,
            glycemicIndex: nil,
            assessmentNotes: nil,
            imageURL: nil,
            tags: nil,
            source: .manual
        )

        onPersist(savedItem)
    }

    private var undoButton: some View {
        HStack(alignment: .center) {
            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Restore cleared results and state
                    if let savedState = clearedResultsViewState {
                        state.searchResultsState.searchResults = savedState.searchResults
                        state.searchResultsState.editedItems = savedState.editedItems
                        state.searchResultsState.collapsedSections = savedState.collapsedSections
                    }

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

            Button(action: {
                state.cancelSearchTask()
            }) {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
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
            List {
                ForEach(state.searchResultsState.searchResults) { foodItemGroup in
                    FoodItemGroupListSection(
                        foodItemGroup: foodItemGroup,
                        state: state,
                        selectedTime: selectedTime,
                        onPersist: persistFoodItem,
                        savedFoodIds: Set(state.savedFoods?.foodItemsDetailed.map(\.id) ?? []),
                        allExistingTags: Set(state.savedFoods?.foodItemsDetailed.flatMap { $0.tags ?? [] } ?? [])
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // Helper function to format time
    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var noSearchesView: some View {
        ScrollView {
            NoSearchesView(state: state)
        }
        .scrollDismissesKeyboard(.immediately)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // utils

    private func persistFoodItem(_ foodItem: FoodItemDetailed) {
        if let imageURL = foodItem.imageURL, let url = URL(string: imageURL), !url.isFileURL {
            Task {
                isDownloadingImage = true
                let updatedItem = await ensureLocalImageURLHelper(for: foodItem)
                await MainActor.run {
                    isDownloadingImage = false
                    onPersist(updatedItem)
                    // Update any existing instances in the meal
                    state.searchResultsState.updateExistingItem(updatedItem)
                }
            }
        } else {
            onPersist(foodItem)
            state.searchResultsState.updateExistingItem(foodItem)
        }
    }

    private func ensureLocalImageURLHelper(for foodItem: FoodItemDetailed) async -> FoodItemDetailed {
        guard let imageURL = foodItem.imageURL else {
            return foodItem
        }

        guard let url = URL(string: imageURL), !url.isFileURL else {
            return foodItem
        }

        guard let image = await downloadAndResolveImage(imageURL) else {
            return foodItem
        }

        guard let localURL = await FoodImageStorageManager.shared.saveImage(image, for: foodItem.id) else {
            return foodItem
        }

        return foodItem.withImageURL(localURL)
    }

    private func downloadAndResolveImage(_ urlString: String) async -> UIImage? {
        if let cached = FoodImageStorageManager.shared.getCachedImage(for: urlString) {
            return cached
        }

        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

extension FoodItemSource {
    var icon: String {
        switch self {
        case .aiPhoto:
            return "camera.viewfinder"
        case .aiMenu:
            return "list.clipboard"
        case .aiReceipe:
            return "book.fill"
        case .aiText:
            return "character.bubble"
        case .search:
            return "magnifyingglass.circle"
        case .barcode:
            return "barcode.viewfinder"
        case .manual:
            return "square.and.pencil"
        case .database:
            return "archivebox.fill"
        }
    }
}

extension FoodItemGroup {
    var title: String {
        switch source {
        case .manual: NSLocalizedString("Manual entry", comment: "Section with manualy entered foods")
        case .database: NSLocalizedString("Saved foods", comment: "Section with saved foods")
        case .barcode: NSLocalizedString("Barcode scan", comment: "Section with bar code scan results")
        case .search: NSLocalizedString("Online database search", comment: "Section with online database search results")
        case .aiMenu,
             .aiPhoto,
             .aiReceipe,
             .aiText:
            briefDescription ?? textQuery ?? NSLocalizedString(
                "AI Results",
                comment: "Section with AI food analysis results, when details are unavailable"
            )
        }
    }
}

private struct FoodItemGroupListSection: View {
    let foodItemGroup: FoodItemGroup
    @ObservedObject var state: FoodSearchStateModel
    let selectedTime: Date?
    let onPersist: (FoodItemDetailed) -> Void
    let savedFoodIds: Set<UUID>
    let allExistingTags: Set<String>

    @State private var showInfoPopup = false

    private var preferredInfoHeight: CGFloat {
        var base: CGFloat = 420
        if let desc = foodItemGroup.overallDescription, !desc.isEmpty { base += 60 }
        if let diabetes = foodItemGroup.diabetesConsiderations, !diabetes.isEmpty { base += 60 }
        return min(max(base, 400), 640)
    }

    private var nonDeletedItemCount: Int {
        foodItemGroup.foodItemsDetailed.filter { !state.searchResultsState.isDeleted($0) }.count
    }

    private func saveSectionAsFoodItem() {
        let nonDeletedItems = foodItemGroup.foodItemsDetailed.filter { !state.searchResultsState.isDeleted($0) }

        guard !nonDeletedItems.isEmpty else { return }

        // Calculate totals for this section
        var totalCarbs: Decimal = 0
        var totalProtein: Decimal = 0
        var totalFat: Decimal = 0
        var totalFiber: Decimal = 0
        var totalSugars: Decimal = 0
        var totalCalories: Decimal = 0

        // Calculate aggregate serving size
        var aggregateServingSize: Decimal? = 0
        var hasAllServingSizes = true

        for item in nonDeletedItems {
            let portionSize = state.searchResultsState.portionSize(for: item)

            switch item.nutrition {
            case let .per100(values):
                // For per100, scale by portion size
                let scale = portionSize / 100
                totalCarbs += (values.carbs ?? 0) * scale
                totalProtein += (values.protein ?? 0) * scale
                totalFat += (values.fat ?? 0) * scale
                if let fiber = values.fiber {
                    totalFiber += fiber * scale
                }
                if let sugars = values.sugars {
                    totalSugars += sugars * scale
                }
                if let calories = values.calories {
                    totalCalories += calories * scale
                }

                // Add portion size to aggregate
                aggregateServingSize? += portionSize

            case let .perServing(values):
                // For perServing, multiply by servings multiplier
                totalCarbs += (values.carbs ?? 0) * portionSize
                totalProtein += (values.protein ?? 0) * portionSize
                totalFat += (values.fat ?? 0) * portionSize
                if let fiber = values.fiber {
                    totalFiber += fiber * portionSize
                }
                if let sugars = values.sugars {
                    totalSugars += sugars * portionSize
                }
                if let calories = values.calories {
                    totalCalories += calories * portionSize
                }

                // Add serving size multiplied by multiplier
                if let servingSize = item.standardServingSize {
                    aggregateServingSize? += servingSize * portionSize
                } else {
                    hasAllServingSizes = false
                }
            }
        }

        // If we couldn't calculate complete serving size, set to nil
        if !hasAllServingSizes {
            aggregateServingSize = nil
        }

        // Create nutrition values from totals
        let nutritionValues = NutritionValues(
            calories: totalCalories > 0 ? totalCalories : nil,
            carbs: totalCarbs,
            fat: totalFat,
            fiber: totalFiber > 0 ? totalFiber : nil,
            protein: totalProtein,
            sugars: totalSugars > 0 ? totalSugars : nil
        )

        // Generate name from section
        let sectionName = foodItemGroup.briefDescription ?? foodItemGroup.textQuery ?? foodItemGroup.title

        // Create new food item with per-serving nutrition
        let savedItem = FoodItemDetailed(
            name: sectionName,
            nutritionPerServing: nutritionValues,
            servingsMultiplier: 1,
            confidence: nil,
            brand: nil,
            standardServing: nil,
            standardServingSize: aggregateServingSize,
            units: .grams,
            preparationMethod: nil,
            visualCues: nil,
            glycemicIndex: nil,
            assessmentNotes: nil,
            imageURL: nil,
            tags: nil,
            source: .manual
        )

        onPersist(savedItem)
    }

    var body: some View {
        Group {
            // Section Header Row
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Collapse/Expand button (left side)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.searchResultsState.toggleSectionCollapsed(foodItemGroup.id)
                        }
                    }) {
                        Image(
                            systemName: state.searchResultsState
                                .isSectionCollapsed(foodItemGroup.id) ? "chevron.right" : "chevron.down"
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
                            state.searchResultsState.toggleSectionCollapsed(foodItemGroup.id)
                        }
                    }) {
                        Text(foodItemGroup.title)
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
                    if foodItemGroup.source.isAI {
                        Button(action: {
                            showInfoPopup = true
                        }) {
                            HStack(spacing: 0) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                Image(systemName: foodItemGroup.source.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Image(systemName: foodItemGroup.source.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
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
                        state.searchResultsState.deleteSection(foodItemGroup.id)
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
            .contextMenu {
                Button {
                    saveSectionAsFoodItem()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }

                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.searchResultsState.deleteSection(foodItemGroup.id)
                    }
                } label: {
                    Label("Remove from meal", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showInfoPopup) {
                SectionInfoPopup(foodItemGroup: foodItemGroup)
                    .presentationDetents([.height(preferredInfoHeight), .large])
                    .presentationDragIndicator(.visible)
            }

            // Food Items
            if !state.searchResultsState.isSectionCollapsed(foodItemGroup.id) {
                ForEach(Array(foodItemGroup.foodItemsDetailed.enumerated()), id: \.element.id) { index, foodItem in
                    Group {
                        if state.searchResultsState.isDeleted(foodItem) {
                            DeletedFoodItemRow(
                                foodItem: foodItem,
                                onUndelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        state.searchResultsState.undeleteItem(foodItem)
                                    }
                                },
                                isFirst: index == 0,
                                isLast: index == foodItemGroup.foodItemsDetailed.count - 1
                            )
                        } else {
                            FoodItemRow(
                                foodItem: foodItem,
                                portionSize: state.searchResultsState.portionSize(for: foodItem),
                                onPortionChange: { newPortion in
                                    state.searchResultsState.updatePortion(for: foodItem, to: newPortion)
                                },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        state.searchResultsState.deleteItem(foodItem)
                                    }
                                },
                                onPersist: onPersist,
                                onUpdate: { updatedItem in
                                    // If this is a saved food, persist it and update all instances
                                    if savedFoodIds.contains(updatedItem.id) {
                                        onPersist(updatedItem)
                                    } else {
                                        // Otherwise just update this instance
                                        state.updateItem(updatedItem)
                                    }
                                },
                                savedFoodIds: savedFoodIds,
                                allExistingTags: allExistingTags,
                                isFirst: index == 0,
                                isLast: index == foodItemGroup.foodItemsDetailed.count - 1
                            )
                        }
                    }
                    .listRowSeparator(index == foodItemGroup.foodItemsDetailed.count - 1 ? .hidden : .visible)
                }
            }
        }
    }
}

private struct DeletedFoodItemRow: View {
    let foodItem: FoodItemDetailed
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
