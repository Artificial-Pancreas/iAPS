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
                // Show saved foods inline with header
                VStack(spacing: 0) {
                    HStack {
                        Text("Saved Foods")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        // Add New button
                        Button(action: {
                            state.showNewSavedFoodEntry = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                Text("New")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.blue)
                        }
                        .padding(.trailing, 8)

                        // Done button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                state.showSavedFoods = false
                            }
                        }) {
                            Text("Done")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))

                    Divider()

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
                ForEach(state.searchResultsState.searchResults) { analysisResult in
                    FoodItemGroupListSection(
                        analysisResult: analysisResult,
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
            VStack(spacing: 20) {
                // Main capabilities
                VStack(spacing: 12) {
                    // Saved Foods Card (always visible)
                    Group {
                        if let savedFoods = state.savedFoods, !savedFoods.foodItemsDetailed.isEmpty {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    state.showSavedFoods = true
                                }
                            }) {
                                CapabilityCard(
                                    icon: FoodItemSource.database.icon,
                                    iconColor: .orange,
                                    title: "Saved Foods",
                                    description: "Quick access to your frequently used foods",
                                    isDisabled: false
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            CapabilityCard(
                                icon: FoodItemSource.database.icon,
                                iconColor: .orange,
                                title: "Saved Foods",
                                description: "No saved foods",
                                isDisabled: true
                            )
                        }
                    }

                    CapabilityCard(
                        icon: FoodItemSource.aiText.icon,
                        iconColor: .blue,
                        title: "Text Search",
                        description: "Search databases or describe food for AI analysis",
                        isDisabled: false
                    )

                    // Barcode Scanner Card
                    Button(action: {
                        state.foodSearchRoute = .barcodeScanner
                    }) {
                        CapabilityCard(
                            icon: FoodItemSource.barcode.icon,
                            iconColor: .blue,
                            title: "Barcode Scanner",
                            description: "Scan packaged foods for nutrition information",
                            isDisabled: false
                        )
                    }
                    .buttonStyle(.plain)

                    // Photo Analysis Card
                    Button(action: {
                        state.foodSearchRoute = .camera
                    }) {
                        CapabilityCard(
                            icon: "camera.fill",
                            iconColor: .purple,
                            title: "Photo Analysis",
                            description: "Snap a picture for AI-powered nutrition analysis. Long-press to choose from library.",
                            isDisabled: false
                        )
                    }
                    .buttonStyle(.plain)

                    // Manual Entry Card
                    Button(action: {
                        state.showManualEntry = true
                    }) {
                        CapabilityCard(
                            icon: FoodItemSource.manual.icon,
                            iconColor: .green,
                            title: "Manual Entry",
                            description: "Enter nutrition information manually",
                            isDisabled: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                // Photography tips
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.metering.center.weighted")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                        Text("Photography Tips")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TipRow(icon: "light.max", text: "Use good lighting for best results")
                        TipRow(icon: "arrow.up.left.and.arrow.down.right", text: "Include the full plate or package in frame")
                        TipRow(icon: "hand.point.up.left.fill", text: "Place a reference object (coin, hand) for scale")
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.horizontal)
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
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

// MARK: - Constants

private enum FoodTags {
    static let favorites = "⭐️"
}

// MARK: - Empty State Components

private struct CapabilityCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(isDisabled ? 0.05 : 0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor.opacity(isDisabled ? 0.3 : 1.0))
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isDisabled ? .secondary : .primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(isDisabled ? 0.6 : 1.0))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground).opacity(isDisabled ? 0.5 : 1.0))
        )
    }
}

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

// MARK: - Food Item Editor Sheet

private struct FoodItemEditorSheet: View {
    let existingItem: FoodItemDetailed?
    let title: String
    let onSave: (FoodItemDetailed) -> Void
    let onCancel: () -> Void
    let allowServingMultiplierEdit: Bool // New parameter to control slider visibility
    let allExistingTags: Set<String> // All tags from other saved foods

    @State private var nutritionMode: NutritionEntryMode = .perServing
    @State private var portionSizeOrMultiplier: Decimal = 1
    @State private var editedName: String = ""
    @State private var editedCarbs: Decimal = 0
    @State private var editedProtein: Decimal = 0
    @State private var editedFat: Decimal = 0
    @State private var editedFiber: Decimal?
    @State private var editedSugars: Decimal?
    @State private var editedServingSize: Decimal?
    @State private var editedCalories: Decimal?
    @State private var sliderMultiplier: Double = 1.0
    @State private var editedTags: Set<String> = []
    @State private var showingAddNewTag = false
    @State private var newTagText: String = ""

    @FocusState private var focusedField: NutritionField?

    enum NutritionField: Hashable {
        case carbs
        case protein
        case fat
        case fiber
        case sugars
        case servingSize
        case calories
        case name
    }

    enum NutritionEntryMode: String, CaseIterable, Hashable {
        case perServing = "Per Serving"
        case per100g = "Per 100g"
        case per100ml = "Per 100ml"

        var nutritionType: NutritionEntryType {
            switch self {
            case .perServing: return .perServing
            case .per100g,
                 .per100ml: return .per100
            }
        }

        var unit: MealUnits {
            switch self {
            case .per100g,
                 .perServing: return .grams
            case .per100ml: return .milliliters
            }
        }
    }

    enum NutritionEntryType {
        case perServing
        case per100
    }

    private var nutritionType: NutritionEntryType {
        nutritionMode.nutritionType
    }

    private var selectedUnit: MealUnits {
        nutritionMode.unit
    }

    private var canSave: Bool {
        editedCarbs >= 0 && editedProtein >= 0 && editedFat >= 0
    }

    init(
        existingItem: FoodItemDetailed?,
        title: String? = nil,
        allowServingMultiplierEdit: Bool = false,
        allExistingTags: Set<String> = [],
        onSave: @escaping (FoodItemDetailed) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingItem = existingItem
        // Use provided title, or default based on whether editing existing item
        self.title = title ?? (existingItem != nil ? "Edit Food" : "Add Food Manually")
        self.allowServingMultiplierEdit = allowServingMultiplierEdit
        self.allExistingTags = allExistingTags
        self.onSave = onSave
        self.onCancel = onCancel

        // Initialize state from existing item if provided
        if let item = existingItem {
            _editedName = State(initialValue: item.name)
            _editedTags = State(initialValue: Set(item.tags ?? []))

            switch item.nutrition {
            case let .per100(values):
                // Determine mode based on units
                let mode: NutritionEntryMode = (item.units ?? .grams) == .milliliters ? .per100ml : .per100g
                _nutritionMode = State(initialValue: mode)
                _editedCarbs = State(initialValue: values.carbs ?? 0)
                _editedProtein = State(initialValue: values.protein ?? 0)
                _editedFat = State(initialValue: values.fat ?? 0)
                _editedFiber = State(initialValue: values.fiber)
                _editedSugars = State(initialValue: values.sugars)
                _editedCalories = State(initialValue: values.calories)
                _portionSizeOrMultiplier = State(initialValue: item.portionSize ?? 100)
                _sliderMultiplier = State(initialValue: Double(item.portionSize ?? 100))

            case let .perServing(values):
                _nutritionMode = State(initialValue: .perServing)
                _editedCarbs = State(initialValue: values.carbs ?? 0)
                _editedProtein = State(initialValue: values.protein ?? 0)
                _editedFat = State(initialValue: values.fat ?? 0)
                _editedFiber = State(initialValue: values.fiber)
                _editedSugars = State(initialValue: values.sugars)
                _editedCalories = State(initialValue: values.calories)
                _portionSizeOrMultiplier = State(initialValue: item.servingsMultiplier ?? 1)
                _sliderMultiplier = State(initialValue: Double(item.servingsMultiplier ?? 1))
            }

            _editedServingSize = State(initialValue: item.standardServingSize)
        }
    }

    private func autoGeneratedName() -> String {
        let carbs = editedCarbs
        let protein = editedProtein
        let fat = editedFat

        let total = carbs + protein + fat
        guard total > 0 else { return "Food" }

        // Calculate percentages
        let carbPercent = (carbs / total) * 100
        let proteinPercent = (protein / total) * 100
        let fatPercent = (fat / total) * 100

        // Low-carb check (important for diabetes)
        if carbPercent < 10 {
            if proteinPercent > 50 { return "Lean Protein" }
            if fatPercent > 60 { return "Fatty Food" }
            return "Low-Carb Food"
        }

        // Dominant macro (>50%)
        if carbPercent > 50 {
            if carbPercent > 80 { return "Starchy Food" }
            return "Carb Food"
        }

        if proteinPercent > 50 {
            if fatPercent < 10 { return "Lean Protein" }
            return "Protein Food"
        }

        if fatPercent > 50 {
            return "Fatty Food"
        }

        // Balanced
        if carbPercent > 30 && proteinPercent > 30 {
            return "Mixed Food"
        }

        return "Food"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Nutrition Mode Picker at the top (3-way)
                VStack(spacing: 12) {
                    Picker("Nutrition Type", selection: $nutritionMode) {
                        ForEach(NutritionEntryMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .onChange(of: nutritionMode) { oldMode, newMode in
                        handleNutritionModeChange(from: oldMode, to: newMode)
                    }
                }

                FoodItemNutritionEditor(
                    nutritionMode: $nutritionMode,
                    portionSizeOrMultiplier: $portionSizeOrMultiplier,
                    sliderMultiplier: $sliderMultiplier,
                    editedCarbs: $editedCarbs,
                    editedProtein: $editedProtein,
                    editedFat: $editedFat,
                    editedFiber: $editedFiber,
                    editedSugars: $editedSugars,
                    editedServingSize: $editedServingSize,
                    editedCalories: $editedCalories,
                    allowServingMultiplierEdit: allowServingMultiplierEdit,
                    focusedField: $focusedField
                )

                // Editable food name with favorite tag
                VStack(alignment: .leading, spacing: 8) {
                    Text("Food Name")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        TextField(autoGeneratedName(), text: $editedName)
                            .font(.body)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .name)

                        if !allExistingTags.isEmpty || existingItem?.source == .database {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if editedTags.contains(FoodTags.favorites) {
                                        editedTags.remove(FoodTags.favorites)
                                    } else {
                                        editedTags.insert(FoodTags.favorites)
                                    }
                                }
                            }) {
                                Text(FoodTags.favorites)
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                                    .foregroundColor(editedTags.contains(FoodTags.favorites) ? .white : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(
                                                editedTags.contains(FoodTags.favorites) ? Color.purple.opacity(0.75) : Color
                                                    .purple.opacity(0.08)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(
                                                editedTags.contains(FoodTags.favorites) ? Color.clear : Color.purple
                                                    .opacity(0.35),
                                                lineWidth: 1.0
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Collapsible tags section (only show if editing a saved food or creating one for the saved foods list)
                if !allExistingTags.isEmpty || existingItem?.source == .database {
                    CollapsibleTagsSection(
                        selectedTags: $editedTags,
                        allExistingTags: allExistingTags,
                        showingAddNewTag: $showingAddNewTag
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Action buttons at bottom
                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(10)

                    Button("Save") {
                        saveFoodItem()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canSave ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundColor(canSave ? .white : .secondary)
                    .cornerRadius(10)
                    .disabled(!canSave)
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only show keyboard toolbar when a field is actually focused
                if focusedField != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            focusedField = nil
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        // Ensure keyboard dismisses when sheet loses focus
        .onDisappear {
            focusedField = nil
        }
        .alert("Add New Tag", isPresented: $showingAddNewTag) {
            TextField("Tag name", text: $newTagText)
                .autocapitalization(.none)
            Button("Cancel", role: .cancel) {
                newTagText = ""
            }
            Button("Add") {
                let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !trimmed.isEmpty, trimmed != FoodTags.favorites {
                    editedTags.insert(trimmed)
                }
                newTagText = ""
            }
        } message: {
            Text("Enter a tag name (e.g., breakfast, snack, low-carb)")
        }
    }

    private func handleNutritionModeChange(from oldMode: NutritionEntryMode, to newMode: NutritionEntryMode) {
        // Skip if modes are the same
        guard oldMode.nutritionType != newMode.nutritionType else {
            return
        }

        switch (oldMode.nutritionType, newMode.nutritionType) {
        case (.per100, .perServing):
            // Switching from per100 to perServing
            // Calculate new per-serving values based on current portion size
            let currentPortionSize = portionSizeOrMultiplier
            let scaleFactor = currentPortionSize / 100

            editedCarbs = round(editedCarbs * scaleFactor, to: 1)
            editedProtein = round(editedProtein * scaleFactor, to: 1)
            editedFat = round(editedFat * scaleFactor, to: 1)
            editedFiber = editedFiber.map { round($0 * scaleFactor, to: 1) }
            editedSugars = editedSugars.map { round($0 * scaleFactor, to: 1) }

            // Scale calories if they exist
            editedCalories = editedCalories.map { round($0 * scaleFactor, to: 0) }

            // Set serving size to current portion size
            editedServingSize = currentPortionSize

            // Set multiplier to 1 (always for perServing mode in this context)
            portionSizeOrMultiplier = 1
            sliderMultiplier = 1.0

        case (.perServing, .per100):
            // Switching from perServing to per100
            if let servingSize = editedServingSize, servingSize > 0 {
                // We have a serving size - do reverse conversion
                let scaleFactor = 100 / servingSize

                editedCarbs = round(editedCarbs * scaleFactor, to: 1)
                editedProtein = round(editedProtein * scaleFactor, to: 1)
                editedFat = round(editedFat * scaleFactor, to: 1)
                editedFiber = editedFiber.map { round($0 * scaleFactor, to: 1) }
                editedSugars = editedSugars.map { round($0 * scaleFactor, to: 1) }

                // Scale calories if they exist
                editedCalories = editedCalories.map { round($0 * scaleFactor, to: 0) }

                // Set portion size to the serving size
                portionSizeOrMultiplier = servingSize
                sliderMultiplier = Double(servingSize)
            } else {
                // No serving size available - just set default portion size
                portionSizeOrMultiplier = 100
                sliderMultiplier = 100.0
            }

        default:
            // Handle switches between per100g and per100ml (same nutrition type)
            break
        }
    }

    // Helper function to round Decimal to specified number of decimal places
    private func round(_ value: Decimal, to places: Int) -> Decimal {
        var rounded = value
        var result = Decimal()
        NSDecimalRound(&result, &rounded, places, .plain)
        return result
    }

    private func saveFoodItem() {
        // Use auto-generated name if user hasn't entered one
        let finalName = editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
            autoGeneratedName() : editedName

        let nutritionValues = NutritionValues(
            calories: editedCalories,
            carbs: editedCarbs,
            fat: editedFat,
            fiber: editedFiber,
            protein: editedProtein,
            sugars: editedSugars
        )

        // Convert tags to array, ensuring favorites is always first if present
        let tagsArray: [String]? = {
            guard !editedTags.isEmpty else { return nil }
            var result = Array(editedTags)
            // Sort so favorites comes first, then alphabetically
            result.sort { tag1, tag2 in
                if tag1 == FoodTags.favorites { return true }
                if tag2 == FoodTags.favorites { return false }
                return tag1 < tag2
            }
            return result
        }()

        let foodItem: FoodItemDetailed

        // If editing existing item, preserve its properties
        if let existingItem = existingItem {
            switch nutritionMode.nutritionType {
            case .per100:
                foodItem = FoodItemDetailed(
                    id: existingItem.id, // Preserve ID
                    name: finalName,
                    nutritionPer100: nutritionValues,
                    portionSize: portionSizeOrMultiplier,
                    confidence: existingItem.confidence,
                    brand: existingItem.brand,
                    standardServing: existingItem.standardServing,
                    standardServingSize: editedServingSize,
                    units: selectedUnit,
                    preparationMethod: existingItem.preparationMethod,
                    visualCues: existingItem.visualCues,
                    glycemicIndex: existingItem.glycemicIndex,
                    assessmentNotes: existingItem.assessmentNotes,
                    imageURL: existingItem.imageURL,
                    tags: tagsArray,
                    source: existingItem.source
                )
            case .perServing:
                foodItem = FoodItemDetailed(
                    id: existingItem.id, // Preserve ID
                    name: finalName,
                    nutritionPerServing: nutritionValues,
                    servingsMultiplier: portionSizeOrMultiplier,
                    confidence: existingItem.confidence,
                    brand: existingItem.brand,
                    standardServing: existingItem.standardServing,
                    standardServingSize: editedServingSize,
                    units: selectedUnit,
                    preparationMethod: existingItem.preparationMethod,
                    visualCues: existingItem.visualCues,
                    glycemicIndex: existingItem.glycemicIndex,
                    assessmentNotes: existingItem.assessmentNotes,
                    imageURL: existingItem.imageURL,
                    tags: tagsArray,
                    source: existingItem.source
                )
            }
        } else {
            // Creating new item
            switch nutritionMode.nutritionType {
            case .per100:
                foodItem = FoodItemDetailed(
                    name: finalName,
                    nutritionPer100: nutritionValues,
                    portionSize: portionSizeOrMultiplier,
                    confidence: nil,
                    brand: nil,
                    standardServing: nil,
                    standardServingSize: editedServingSize,
                    units: selectedUnit,
                    preparationMethod: nil,
                    visualCues: nil,
                    glycemicIndex: nil,
                    assessmentNotes: nil,
                    imageURL: nil,
                    tags: tagsArray,
                    source: .manual
                )
            case .perServing:
                foodItem = FoodItemDetailed(
                    name: finalName,
                    nutritionPerServing: nutritionValues,
                    servingsMultiplier: portionSizeOrMultiplier,
                    confidence: nil,
                    brand: nil,
                    standardServing: nil,
                    standardServingSize: editedServingSize,
                    units: selectedUnit,
                    preparationMethod: nil,
                    visualCues: nil,
                    glycemicIndex: nil,
                    assessmentNotes: nil,
                    imageURL: nil,
                    tags: tagsArray,
                    source: .manual
                )
            }
        }

        onSave(foodItem)
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Food Item Nutrition Editor

private struct FoodItemNutritionEditor: View {
    @Binding var nutritionMode: FoodItemEditorSheet.NutritionEntryMode
    @Binding var portionSizeOrMultiplier: Decimal
    @Binding var sliderMultiplier: Double
    @Binding var editedCarbs: Decimal
    @Binding var editedProtein: Decimal
    @Binding var editedFat: Decimal
    @Binding var editedFiber: Decimal?
    @Binding var editedSugars: Decimal?
    @Binding var editedServingSize: Decimal?
    @Binding var editedCalories: Decimal?
    let allowServingMultiplierEdit: Bool
    @FocusState.Binding var focusedField: FoodItemEditorSheet.NutritionField?

    @State private var showAllNutrients: Bool = false

    init(
        nutritionMode: Binding<FoodItemEditorSheet.NutritionEntryMode>,
        portionSizeOrMultiplier: Binding<Decimal>,
        sliderMultiplier: Binding<Double>,
        editedCarbs: Binding<Decimal>,
        editedProtein: Binding<Decimal>,
        editedFat: Binding<Decimal>,
        editedFiber: Binding<Decimal?>,
        editedSugars: Binding<Decimal?>,
        editedServingSize: Binding<Decimal?>,
        editedCalories: Binding<Decimal?>,
        allowServingMultiplierEdit: Bool = false,
        focusedField: FocusState<FoodItemEditorSheet.NutritionField?>.Binding
    ) {
        _nutritionMode = nutritionMode
        _portionSizeOrMultiplier = portionSizeOrMultiplier
        _sliderMultiplier = sliderMultiplier
        _editedCarbs = editedCarbs
        _editedProtein = editedProtein
        _editedFat = editedFat
        _editedFiber = editedFiber
        _editedSugars = editedSugars
        _editedServingSize = editedServingSize
        _editedCalories = editedCalories
        self.allowServingMultiplierEdit = allowServingMultiplierEdit
        _focusedField = focusedField

        // Auto-expand if there are optional nutrients
        let hasOptionalNutrients = (editedFiber.wrappedValue != nil && editedFiber.wrappedValue! > 0) ||
            (editedSugars.wrappedValue != nil && editedSugars.wrappedValue! > 0) ||
            (editedServingSize.wrappedValue != nil && editedServingSize.wrappedValue! > 0) ||
            (editedCalories.wrappedValue != nil && editedCalories.wrappedValue! > 0)

        _showAllNutrients = State(initialValue: hasOptionalNutrients)
    }

    private var unit: String {
        nutritionMode == .perServing ? "serving" : nutritionMode.unit.localizedAbbreviation
    }

    private var nutritionType: FoodItemEditorSheet.NutritionEntryType {
        nutritionMode.nutritionType
    }

    // Calculate calories from macros
    private var calculatedCalories: Decimal {
        (editedCarbs * 4) + (editedProtein * 4) + (editedFat * 9)
    }

    // Use manually edited calories if available, otherwise use calculated
    private var displayedCalories: Decimal {
        // If we have a calories value (whether from food item or manual entry), use it
        // Only fall back to calculated if there's no value at all
        if let calories = editedCalories {
            return calories
        } else {
            return calculatedCalories
        }
    }

    private var sliderRange: ClosedRange<Double> {
        switch nutritionType {
        case .per100:
            return 10.0 ... 600.0
        case .perServing:
            return 0.25 ... 10.0
        }
    }

    private var sliderStep: Double.Stride {
        switch nutritionType {
        case .per100:
            return 5.0
        case .perServing:
            return 0.25
        }
    }

    private var sliderMinLabel: String {
        switch nutritionType {
        case .per100:
            return "10\(nutritionMode.unit.localizedAbbreviation)"
        case .perServing:
            return "0.25×"
        }
    }

    private var sliderMaxLabel: String {
        switch nutritionType {
        case .per100:
            return "600\(nutritionMode.unit.localizedAbbreviation)"
        case .perServing:
            return "10×"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Portion Size/Multiplier Slider
                // Show for per100 mode always, or for perServing mode when allowServingMultiplierEdit is true
                if nutritionType == .per100 || (nutritionType == .perServing && allowServingMultiplierEdit) {
                    VStack(spacing: 12) {
                        switch nutritionType {
                        case .per100:
                            Text(
                                "\(Double(portionSizeOrMultiplier), specifier: "%.0f") \(nutritionMode.unit.localizedAbbreviation)"
                            )
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.orange)
                        case .perServing:
                            Text("\(Double(portionSizeOrMultiplier), specifier: "%.2f")× servings")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.orange)
                        }

                        Slider(value: $sliderMultiplier, in: sliderRange, step: sliderStep)
                            .tint(.orange)
                            .padding(.horizontal)
                            .onChange(of: sliderMultiplier) { _, newValue in
                                portionSizeOrMultiplier = Decimal(newValue)
                            }

                        HStack {
                            Text(sliderMinLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(sliderMaxLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                }

                // Nutrition Table with Editable values
                VStack(spacing: 8) {
                    // Header row
                    HStack(spacing: 8) {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("This portion")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 95, alignment: .trailing)

                        Text(nutritionType == .perServing ? "Per serving" : "Per 100\(nutritionMode.unit.localizedAbbreviation)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Divider()

                    FoodItemNutritionRow(
                        label: "Carbs",
                        portionValue: calculatePortionValue(baseValue: editedCarbs),
                        baseValue: $editedCarbs,
                        unit: "g",
                        focusedField: $focusedField,
                        fieldTag: .carbs
                    )
                    Divider()
                    FoodItemNutritionRow(
                        label: "Protein",
                        portionValue: calculatePortionValue(baseValue: editedProtein),
                        baseValue: $editedProtein,
                        unit: "g",
                        focusedField: $focusedField,
                        fieldTag: .protein
                    )
                    Divider()
                    FoodItemNutritionRow(
                        label: "Fat",
                        portionValue: calculatePortionValue(baseValue: editedFat),
                        baseValue: $editedFat,
                        unit: "g",
                        focusedField: $focusedField,
                        fieldTag: .fat
                    )

                    // Optional nutrients
                    if showAllNutrients {
                        Divider()
                        // Editable calories row (with auto-calculation when not manually edited)
                        FoodItemCaloriesRow(
                            label: "Calories",
                            portionValue: calculatePortionValue(baseValue: displayedCalories),
                            baseValue: $editedCalories,
                            calculatedValue: calculatedCalories,
                            unit: "kcal",
                            isCalculated: editedCalories == nil,
                            focusedField: $focusedField,
                            fieldTag: .calories
                        )

                        Divider()
                        FoodItemNutritionRow(
                            label: "Fiber",
                            portionValue: calculatePortionValue(baseValue: editedFiber ?? 0),
                            baseValue: Binding(
                                get: { editedFiber ?? 0 },
                                set: { editedFiber = $0 > 0 ? $0 : nil }
                            ),
                            unit: "g",
                            focusedField: $focusedField,
                            fieldTag: .fiber
                        )

                        Divider()
                        FoodItemNutritionRow(
                            label: "Sugar",
                            portionValue: calculatePortionValue(baseValue: editedSugars ?? 0),
                            baseValue: Binding(
                                get: { editedSugars ?? 0 },
                                set: { editedSugars = $0 > 0 ? $0 : nil }
                            ),
                            unit: "g",
                            focusedField: $focusedField,
                            fieldTag: .sugars
                        )

                        Divider()
                        FoodItemServingSizeRow(
                            servingSize: Binding(
                                get: { editedServingSize ?? 0 },
                                set: { editedServingSize = $0 > 0 ? $0 : nil }
                            ),
                            unit: nutritionMode.unit.localizedAbbreviation,
                            focusedField: $focusedField,
                            fieldTag: .servingSize
                        )
                    }

                    // Button to reveal optional nutrients
                    if !showAllNutrients {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllNutrients = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Show All Nutrients")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func calculatePortionValue(baseValue: Decimal) -> Decimal {
        switch nutritionType {
        case .per100:
            return baseValue / 100 * portionSizeOrMultiplier
        case .perServing:
            return baseValue * portionSizeOrMultiplier
        }
    }

    private func endEditing() {
        #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// Helper view for food item nutrition rows
private struct FoodItemNutritionRow: View {
    let label: String
    let portionValue: Decimal
    @Binding var baseValue: Decimal
    let unit: String
    @FocusState.Binding var focusedField: FoodItemEditorSheet.NutritionField?
    let fieldTag: FoodItemEditorSheet.NutritionField

    @State private var textValue: String = ""

    private var textBinding: Binding<String> {
        Binding(
            get: {
                // When focused or if there's text, use the text value
                // Otherwise show empty for 0 values
                if textValue.isEmpty, baseValue == 0 {
                    return ""
                }
                return textValue
            },
            set: { newValue in
                textValue = newValue
                // Convert to Decimal, treating empty as 0
                if let decimal = Decimal(string: newValue) {
                    baseValue = decimal
                } else if newValue.isEmpty {
                    baseValue = 0
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Per portion value (calculated, read-only)
            HStack(spacing: 2) {
                Text("\(Double(portionValue), specifier: "%.1f")")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 28, alignment: .leading)
            }
            .frame(width: 95, alignment: .trailing)

            // Base value (editable) - wrapped with keyboard dismissal
            HStack(spacing: 4) {
                TextField("0", text: textBinding)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: fieldTag)
                    .onAppear {
                        // Initialize text value from baseValue
                        if baseValue > 0 {
                            textValue = String(describing: baseValue)
                        }
                    }
                    .onChange(of: baseValue) { _, newValue in
                        // Update text when baseValue changes externally
                        if newValue > 0 {
                            textValue = String(describing: newValue)
                        } else {
                            textValue = ""
                        }
                    }

                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 28, alignment: .leading)
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }
}

// Helper view for food item calories row (editable with auto-calculation option)
private struct FoodItemCaloriesRow: View {
    let label: String
    let portionValue: Decimal
    @Binding var baseValue: Decimal?
    let calculatedValue: Decimal
    let unit: String
    let isCalculated: Bool
    @FocusState.Binding var focusedField: FoodItemEditorSheet.NutritionField?
    let fieldTag: FoodItemEditorSheet.NutritionField

    @State private var textValue: String = ""

    private var textBinding: Binding<String> {
        Binding(
            get: {
                // When there's text, use it
                // Otherwise show empty for nil/0 values
                if textValue.isEmpty, baseValue == nil || baseValue == 0 {
                    return ""
                }
                return textValue
            },
            set: { newValue in
                textValue = newValue
                // Convert to Decimal, treating empty as nil
                if let decimal = Decimal(string: newValue), decimal > 0 {
                    baseValue = decimal
                } else if newValue.isEmpty {
                    baseValue = nil
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.8))

                // Show formula indicator if auto-calculated
                if isCalculated {
                    Image(systemName: "function")
                        .font(.system(size: 11))
                        .foregroundColor(.blue.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Per portion value (calculated, read-only)
            HStack(spacing: 2) {
                Text("\(Int(truncating: portionValue as NSNumber))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 28, alignment: .leading)
            }
            .frame(width: 95, alignment: .trailing)

            // Base value (editable) - wrapped with keyboard dismissal
            HStack(spacing: 4) {
                TextField(
                    calculatedValue > 0 ? "\(Int(truncating: calculatedValue as NSNumber))" : "0",
                    text: textBinding
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: fieldTag)
                .onAppear {
                    // Initialize text value from baseValue
                    if let value = baseValue, value > 0 {
                        textValue = String(Int(truncating: value as NSNumber))
                    }
                }
                .onChange(of: baseValue) { _, newValue in
                    // Update text when baseValue changes externally
                    if let value = newValue, value > 0 {
                        textValue = String(Int(truncating: value as NSNumber))
                    } else {
                        textValue = ""
                    }
                }

                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 28, alignment: .leading)
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }
}

// Helper view for food item serving size row
private struct FoodItemServingSizeRow: View {
    @Binding var servingSize: Decimal
    let unit: String
    @FocusState.Binding var focusedField: FoodItemEditorSheet.NutritionField?
    let fieldTag: FoodItemEditorSheet.NutritionField

    @State private var textValue: String = ""

    private var textBinding: Binding<String> {
        Binding(
            get: {
                // When there's text, use it
                // Otherwise show empty for 0 values
                if textValue.isEmpty, servingSize == 0 {
                    return ""
                }
                return textValue
            },
            set: { newValue in
                textValue = newValue
                // Convert to Decimal, treating empty as 0
                if let decimal = Decimal(string: newValue), decimal > 0 {
                    servingSize = decimal
                } else if newValue.isEmpty {
                    servingSize = 0
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Serving Size")
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Empty space for "per portion" column
            Spacer()
                .frame(width: 95, alignment: .trailing)

            // Serving size value (editable) - wrapped with keyboard dismissal
            HStack(spacing: 4) {
                TextField("optional", text: textBinding)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: fieldTag)
                    .onAppear {
                        // Initialize text value from servingSize
                        if servingSize > 0 {
                            textValue = String(describing: servingSize)
                        }
                    }
                    .onChange(of: servingSize) { _, newValue in
                        // Update text when servingSize changes externally
                        if newValue > 0 {
                            textValue = String(describing: newValue)
                        } else {
                            textValue = ""
                        }
                    }

                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 28, alignment: .leading)
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }
}

// MARK: - Time Picker Sheet

private struct TimePickerSheet: View {
    @Binding var selectedTime: Date?
    @Binding var isPresented: Bool
    @State private var pickerDate = Date()

    // Computed property that adjusts the date to ensure the time is within ±12 hours of now
    private var adjustedMealTime: Date {
        let now = Date()
        let calendar = Calendar.current

        // Get the time components from the picker
        let timeComponents = calendar.dateComponents([.hour, .minute], from: pickerDate)

        // Create a date with today's date and the selected time
        guard let todayWithSelectedTime = calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: now
        ) else {
            return pickerDate
        }

        // Calculate the time difference in seconds
        let timeDifference = todayWithSelectedTime.timeIntervalSince(now)
        let twelveHoursInSeconds: TimeInterval = 12 * 60 * 60

        // If the selected time is more than 12 hours in the future, it was probably meant for yesterday
        if timeDifference > twelveHoursInSeconds {
            return calendar.date(byAdding: .day, value: -1, to: todayWithSelectedTime) ?? todayWithSelectedTime
        }
        // If the selected time is more than 12 hours in the past, it was probably meant for tomorrow
        else if timeDifference < -twelveHoursInSeconds {
            return calendar.date(byAdding: .day, value: 1, to: todayWithSelectedTime) ?? todayWithSelectedTime
        }
        // Otherwise, use today with the selected time
        else {
            return todayWithSelectedTime
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Time picker (wheel style for time only)
                DatePicker(
                    "Select Time",
                    selection: $pickerDate,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 12) {
                    // Reset to "now" button
                    if selectedTime != nil {
                        Button(action: {
                            selectedTime = nil
                            isPresented = false
                        }) {
                            Text("Use Now")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }

                    // Set time button
                    Button(action: {
                        selectedTime = adjustedMealTime
                        isPresented = false
                    }) {
                        Text("Set Time")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Meal Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            // Initialize picker with current selected time or now
            pickerDate = selectedTime ?? Date()
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

extension ConfidenceLevel {
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

private extension FoodItemGroup {
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

private struct TotalNutritionBadge: View {
    let value: Decimal
    let unit: String?
    let label: String?
    let color: Color

    init(value: Decimal, unit: String? = nil, label: String? = nil, color: Color) {
        self.value = value
        self.unit = unit
        self.label = label
        self.color = color
    }

    var body: some View {
        VStack {
            HStack(spacing: 3) {
                // Larger, bolder text for totals
                Text("\(Double(value), specifier: "%.0f")")
                    .font(.system(size: 17, weight: .bold, design: .rounded)) // Larger
                    .foregroundColor(.primary)

                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                if let label = label {
                    Text(label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10) // More padding
        .padding(.vertical, 8)
        .background(color.opacity(0.2)) // Stronger color
        .cornerRadius(10) // Slightly larger radius
    }
}

private struct ConfidenceBadge: View {
    let level: ConfidenceLevel

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

private struct FoodItemGroupListSection: View {
    let analysisResult: FoodItemGroup
    @ObservedObject var state: FoodSearchStateModel
    let selectedTime: Date?
    let onPersist: (FoodItemDetailed) -> Void
    let savedFoodIds: Set<UUID>
    let allExistingTags: Set<String>

    @State private var showInfoPopup = false

    private var preferredInfoHeight: CGFloat {
        var base: CGFloat = 420
        if let desc = analysisResult.overallDescription, !desc.isEmpty { base += 60 }
        if let diabetes = analysisResult.diabetesConsiderations, !diabetes.isEmpty { base += 60 }
        return min(max(base, 400), 640)
    }

    private var nonDeletedItemCount: Int {
        analysisResult.foodItemsDetailed.filter { !state.searchResultsState.isDeleted($0) }.count
    }

    private func saveSectionAsFoodItem() {
        let nonDeletedItems = analysisResult.foodItemsDetailed.filter { !state.searchResultsState.isDeleted($0) }

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
        let sectionName = analysisResult.briefDescription ?? analysisResult.textQuery ?? analysisResult.title

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
            assessmentNotes: "Saved from section totals",
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
                            state.searchResultsState.toggleSectionCollapsed(analysisResult.id)
                        }
                    }) {
                        Image(
                            systemName: state.searchResultsState
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
                            state.searchResultsState.toggleSectionCollapsed(analysisResult.id)
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
                    if analysisResult.source.isAI {
                        Button(action: {
                            showInfoPopup = true
                        }) {
                            HStack(spacing: 0) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                Image(systemName: analysisResult.source.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Image(systemName: analysisResult.source.icon)
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
                        state.searchResultsState.deleteSection(analysisResult.id)
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
            .contextMenu {
                Button {
                    saveSectionAsFoodItem()
                } label: {
                    Label("Save as Food Item", systemImage: "square.and.arrow.down")
                }

                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.searchResultsState.deleteSection(analysisResult.id)
                    }
                } label: {
                    Label("Remove from meal", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showInfoPopup) {
                SectionInfoPopup(analysisResult: analysisResult)
                    .presentationDetents([.height(preferredInfoHeight), .large])
                    .presentationDragIndicator(.visible)
            }

            // Food Items
            if !state.searchResultsState.isSectionCollapsed(analysisResult.id) {
                ForEach(Array(analysisResult.foodItemsDetailed.enumerated()), id: \.element.id) { index, foodItem in
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
                                isLast: index == analysisResult.foodItemsDetailed.count - 1
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
                                isLast: index == analysisResult.foodItemsDetailed.count - 1
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

private struct SectionInfoPopup: View {
    let analysisResult: FoodItemGroup

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

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
    }
}

private struct FoodItemInfoPopup: View {
    let foodItem: FoodItemDetailed
    let portionSize: Decimal

    // Helper to extract nutrition values
    private var nutritionValues: NutritionValues? {
        switch foodItem.nutrition {
        case let .per100(values):
            return values
        case let .perServing(values):
            return values
        }
    }

    private var isPerServing: Bool {
        if case .perServing = foodItem.nutrition {
            return true
        }
        return false
    }

    // Helper functions to avoid type inference issues
    private func shouldShowStandardServing(_ item: FoodItemDetailed) -> Bool {
        let hasDescription = item.standardServing != nil && !(item.standardServing?.isEmpty ?? true)
        let hasSize = item.standardServingSize != nil
        return hasDescription || hasSize
    }

    @ViewBuilder private func standardServingContent(
        foodItem: FoodItemDetailed,
        portionSize _: Decimal,
        unit _: String
    ) -> some View {
        if let servingDescription = foodItem.standardServing, !servingDescription.isEmpty {
            Text(servingDescription)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private func standardServingTitle(foodItem: FoodItemDetailed, unit: String) -> String {
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
                // Title and image
                HStack(alignment: .top, spacing: 12) {
                    Text(foodItem.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Product image (if available)
                    FoodItemLargeImage(imageURL: foodItem.imageURL)
                }
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
                            switch foodItem.nutrition {
                            case .per100:
                                Text("\(amount)")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(unit)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .opacity(0.4)
                            case .perServing:
                                Text("\(amount)")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(portionSize == 1 ? "serving" : "servings")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .opacity(0.4)
                            }
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
                        if foodItem.source.isAI, let confidence = foodItem.confidence {
                            ConfidenceBadge(level: confidence)
                        }

                        // Source icon
                        Image(systemName: foodItem.source.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    // Header row
                    HStack(spacing: 8) {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("This portion")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)

                        Text(isPerServing ? "Per serving" : "Per 100\(unit)")
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
                        portionValue: foodItem.carbsInThisPortion,
                        per100Value: nutritionValues?.carbs,
                        unit: "g"
                    )
                    Divider()
                    DetailedNutritionRow(
                        label: "Protein",
                        portionValue: foodItem.proteinInThisPortion,
                        per100Value: nutritionValues?.protein,
                        unit: "g"
                    )
                    Divider()
                    DetailedNutritionRow(
                        label: "Fat",
                        portionValue: foodItem.fatInThisPortion,
                        per100Value: nutritionValues?.fat,
                        unit: "g"
                    )

                    // Optional additional nutrition
                    if let fiber = nutritionValues?.fiber, fiber > 0 {
                        Divider()
                        DetailedNutritionRow(
                            label: "Fiber",
                            portionValue: isPerServing ?
                                (foodItem.servingsMultiplier.map { fiber * $0 }) :
                                (foodItem.portionSize.map { fiber / 100 * $0 }),
                            per100Value: fiber,
                            unit: "g"
                        )
                    }
                    if let sugars = nutritionValues?.sugars, sugars > 0 {
                        Divider()
                        DetailedNutritionRow(
                            label: "Sugar",
                            portionValue: isPerServing ?
                                (foodItem.servingsMultiplier.map { sugars * $0 }) :
                                (foodItem.portionSize.map { sugars / 100 * $0 }),
                            per100Value: sugars,
                            unit: "g"
                        )
                    }
                    Divider()
                    DetailedNutritionRow(
                        label: "Calories",
                        portionValue: foodItem.caloriesInThisPortion,
                        per100Value: nutritionValues?.calories,
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
                        .frame(width: 24, alignment: .leading)
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
                        .frame(width: 24, alignment: .leading)
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

// MARK: - Food Item Thumbnail

/// Reusable component for displaying food item product images (60x60 - for list rows)
/// Supports both HTTP(S) URLs and file:// URLs
private struct FoodItemThumbnail: View {
    let imageURL: String?

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if isLoading {
                loadingPlaceholder()
            } else if loadFailed {
                placeholderImage()
            } else {
                Color.clear
                    .frame(width: 60, height: 60)
            }
        }
        .task(id: imageURL) {
            guard let imageURL = imageURL else { return }

            isLoading = true
            loadFailed = false

            if let image = await FoodImageStorageManager.shared.loadImage(from: imageURL) {
                loadedImage = image
                loadFailed = false
            } else {
                loadedImage = nil
                loadFailed = true
            }

            isLoading = false
        }
    }

    private func loadingPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 60)
            .overlay(
                ProgressView()
                    .controlSize(.small)
            )
    }

    private func placeholderImage() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            )
    }
}

/// Reusable component for displaying food item product images (80x80 - for sheets/popups)
/// Supports both HTTP(S) URLs and file:// URLs
private struct FoodItemLargeImage: View {
    let imageURL: String?

    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isLoading {
                loadingPlaceholder()
            } else if loadFailed {
                placeholderImage()
            } else {
                Color.clear
                    .frame(width: 80, height: 80)
            }
        }
        .task(id: imageURL) {
            guard let imageURL = imageURL else { return }

            isLoading = true
            loadFailed = false

            if let image = await FoodImageStorageManager.shared.loadImage(from: imageURL) {
                loadedImage = image
                loadFailed = false
            } else {
                loadedImage = nil
                loadFailed = true
            }

            isLoading = false
        }
    }

    private func loadingPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: 80, height: 80)
            .overlay(
                ProgressView()
                    .controlSize(.small)
            )
    }

    private func placeholderImage() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            )
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
    let foodItem: FoodItemDetailed
    let portionSize: Decimal
    let onPortionChange: ((Decimal) -> Void)?
    let onDelete: (() -> Void)?
    let onPersist: ((FoodItemDetailed) -> Void)?
    let onUpdate: ((FoodItemDetailed) -> Void)?
    let savedFoodIds: Set<UUID>
    let allExistingTags: Set<String>
    let isFirst: Bool
    let isLast: Bool

    @State private var showItemInfo = false
    @State private var showPortionAdjuster = false
    @State private var showEditSheet = false
    @State private var sliderMultiplier: Double = 1.0

    private var isSaved: Bool {
        savedFoodIds.contains(foodItem.id)
    }

    private var hasNutritionInfo: Bool {
        switch foodItem.nutrition {
        case let .per100(values):
            return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
        case let .perServing(values):
            return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
        }
    }

    private var isManualEntry: Bool {
        foodItem.source == .manual
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Row Content
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(foodItem.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if foodItem.source.isAI, let confidence = foodItem.confidence {
                            HStack(spacing: 0) {
                                ConfidenceBadge(level: confidence)
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

                        // Only show serving multiplier for per100 items
                        if case .per100 = foodItem.nutrition {
                            if let servingSize = foodItem.standardServingSize {
                                Text("\(Double(portionSize / servingSize), specifier: "%.1f")× serving")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .opacity(0.7)
                            }
                        }
                    }
                }

                // Product image thumbnail (if available) - on the right
                FoodItemThumbnail(imageURL: foodItem.imageURL)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                showItemInfo = true
            }
            .contextMenu {
                if onPortionChange != nil {
                    if isManualEntry {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Edit Food", systemImage: "pencil")
                        }
                    } else {
                        Button {
                            showPortionAdjuster = true
                        } label: {
                            Label("Edit Portion", systemImage: "slider.horizontal.3")
                        }
                    }
                }

                if foodItem.source != .database {
                    if isSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.secondary)
                    } else if let onPersist = onPersist {
                        Button {
                            onPersist(foodItem)
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                }

                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove from meal", systemImage: "trash")
                    }
                }
            }
            .sheet(isPresented: $showItemInfo) {
                FoodItemInfoPopup(foodItem: foodItem, portionSize: portionSize)
                    .presentationDetents([.height(preferredItemInfoHeight(for: foodItem)), .large])
                    .presentationDragIndicator(.visible)
            }

            // Compact nutrition info
            HStack(spacing: 6) {
                switch foodItem.nutrition {
                case .per100:
                    NutritionBadge(
                        value: foodItem.carbsInPortion(portion: portionSize) ?? 0,
                        label: "carbs",
                        color: NutritionBadgeConfig.carbsColor
                    )
                    NutritionBadge(
                        value: foodItem.proteinInPortion(portion: portionSize) ?? 0,
                        label: "protein",
                        color: NutritionBadgeConfig.proteinColor
                    )
                    NutritionBadge(
                        value: foodItem.fatInPortion(portion: portionSize) ?? 0,
                        label: "fat",
                        color: NutritionBadgeConfig.fatColor
                    )
                    NutritionBadge(
                        value: foodItem.caloriesInPortion(portion: portionSize) ?? 0,
                        unit: "kcal",
                        color: NutritionBadgeConfig.caloriesColor
                    )
                case .perServing:
                    NutritionBadge(
                        value: foodItem.carbsInServings(multiplier: portionSize) ?? 0,
                        label: "carbs",
                        color: NutritionBadgeConfig.carbsColor
                    )
                    NutritionBadge(
                        value: foodItem.proteinInServings(multiplier: portionSize) ?? 0,
                        label: "protein",
                        color: NutritionBadgeConfig.proteinColor
                    )
                    NutritionBadge(
                        value: foodItem.fatInServings(multiplier: portionSize) ?? 0,
                        label: "fat",
                        color: NutritionBadgeConfig.fatColor
                    )
                    NutritionBadge(
                        value: foodItem.caloriesInServings(multiplier: portionSize) ?? 0,
                        unit: "kcal",
                        color: NutritionBadgeConfig.caloriesColor
                    )
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
                if isManualEntry {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                } else {
                    Button {
                        showPortionAdjuster = true
                    } label: {
                        Label("Edit Portion", systemImage: "slider.horizontal.3")
                    }
                    .tint(.orange)
                }
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
                    onReset: {
                        switch foodItem.nutrition {
                        case .per100:
                            return foodItem.portionSize != nil
                        case .perServing:
                            return foodItem.servingsMultiplier != nil
                        }
                    }() ? {
                        switch foodItem.nutrition {
                        case .per100:
                            if let original = foodItem.portionSize {
                                onPortionChange?(original)
                                showPortionAdjuster = false
                            }
                        case .perServing:
                            if let original = foodItem.servingsMultiplier {
                                onPortionChange?(original)
                                showPortionAdjuster = false
                            }
                        }
                    } : nil,
                    onCancel: {
                        showPortionAdjuster = false
                    }
                )
                .presentationDetents([.height({
                    let hasReset: Bool
                    switch foodItem.nutrition {
                    case .per100:
                        hasReset = foodItem.portionSize != nil
                    case .perServing:
                        hasReset = foodItem.servingsMultiplier != nil
                    }
                    return hasNutritionInfo ? (hasReset ? 420 : 400) : (hasReset ? 340 : 300)
                }())])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            FoodItemEditorSheet(
                existingItem: foodItem,
                title: "Edit Food",
                allowServingMultiplierEdit: true, // Allow editing multiplier for foods in the main list
                allExistingTags: allExistingTags,
                onSave: { editedItem in
                    onUpdate?(editedItem)
                    showEditSheet = false
                },
                onCancel: {
                    showEditSheet = false
                }
            )
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: portionSize) { _, newValue in
            // Update multiplier when portion size changes externally
            switch foodItem.nutrition {
            case .per100:
                // For per100, slider directly represents grams/ml
                sliderMultiplier = Double(newValue)
            case .perServing:
                // For perServing, slider represents multiplier
                sliderMultiplier = Double(newValue)
            }
        }
        .onAppear {
            // Calculate initial multiplier based on current portion size
            switch foodItem.nutrition {
            case .per100:
                // For per100, slider directly represents grams/ml
                sliderMultiplier = Double(portionSize)
            case .perServing:
                // For perServing, slider represents multiplier
                sliderMultiplier = Double(portionSize)
            }
        }
    }

    private func preferredItemInfoHeight(for item: FoodItemDetailed) -> CGFloat {
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
        let foodItem: FoodItemDetailed

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            HStack(spacing: 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .opacity(0.3)
                }
                HStack(spacing: 2) {
                    switch foodItem.nutrition {
                    case .per100:
                        Text("\(Double(value), specifier: "%.0f")")
                            .font(.system(size: 15, weight: .bold))
                        Text(NSLocalizedString((foodItem.units ?? .grams).localizedAbbreviation, comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.4)
                    case .perServing:
                        Text("\(Double(value), specifier: "%.1f")")
                            .font(.system(size: 15, weight: .bold))
                        Text(value == 1 ? "serving" : "servings")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.4)
                    }
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
        let foodItem: FoodItemDetailed
        @Binding var sliderMultiplier: Double
        let onSave: (Decimal) -> Void
        let onReset: (() -> Void)?
        let onCancel: () -> Void

        private var isPerServing: Bool {
            if case .perServing = foodItem.nutrition {
                return true
            }
            return false
        }

        private var unit: String {
            switch foodItem.nutrition {
            case .per100:
                return (foodItem.units ?? .grams).localizedAbbreviation
            case .perServing:
                return "serving"
            }
        }

        var calculatedPortion: Decimal {
            switch foodItem.nutrition {
            case .per100:
                // For per100, slider directly controls grams/ml
                return Decimal(sliderMultiplier)
            case .perServing:
                // For perServing, slider controls multiplier
                return Decimal(sliderMultiplier)
            }
        }

        private func resetSliderToOriginal() {
            switch foodItem.nutrition {
            case .per100:
                if let original = foodItem.portionSize {
                    sliderMultiplier = Double(original)
                }
            case .perServing:
                if let original = foodItem.servingsMultiplier {
                    sliderMultiplier = Double(original)
                }
            }
        }

        private func formattedServingMultiplier(_ value: Decimal) -> String {
            let doubleValue = Double(truncating: value as NSNumber)
            return String(format: "%.2f×", doubleValue)
        }

        private var sliderRange: ClosedRange<Double> {
            switch foodItem.nutrition {
            case .per100:
                10.0 ... 600.0
            case .perServing:
                0.25 ... 10.0
            }
        }

        private var sliderStep: Double.Stride {
            switch foodItem.nutrition {
            case .per100:
                5.0
            case .perServing:
                0.25
            }
        }

        private var sliderMinLabel: String {
            switch foodItem.nutrition {
            case .per100:
                return "10\(unit)"
            case .perServing:
                return "0.25x"
            }
        }

        private var sliderMaxLabel: String {
            switch foodItem.nutrition {
            case .per100:
                return "600\(unit)"
            case .perServing:
                return "10x"
            }
        }

        var body: some View {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Text(foodItem.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Product image (if available)
                    FoodItemLargeImage(imageURL: foodItem.imageURL)
                }
                .padding(.horizontal)
                .padding(.top)

                VStack(spacing: 8) {
                    switch foodItem.nutrition {
                    case .per100:
                        Text("\(Double(calculatedPortion), specifier: "%.0f") \(unit)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.orange)
                    case .perServing:
                        Text(formattedServingMultiplier(calculatedPortion))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }

                VStack(spacing: 12) {
                    Slider(value: $sliderMultiplier, in: sliderRange, step: sliderStep)
                        .tint(.orange)

                    HStack {
                        Text(sliderMinLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(sliderMaxLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Display nutritional information if available
                    if hasNutritionInfo {
                        HStack(spacing: 8) {
                            switch foodItem.nutrition {
                            case .per100:
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
                            case .perServing:
                                if let carbs = foodItem.carbsInServings(multiplier: calculatedPortion), carbs > 0 {
                                    NutritionBadge(value: carbs, label: "carbs", color: NutritionBadgeConfig.carbsColor)
                                        .frame(maxWidth: .infinity)
                                }
                                if let protein = foodItem.proteinInServings(multiplier: calculatedPortion), protein > 0 {
                                    NutritionBadge(value: protein, label: "protein", color: NutritionBadgeConfig.proteinColor)
                                        .frame(maxWidth: .infinity)
                                }
                                if let fat = foodItem.fatInServings(multiplier: calculatedPortion), fat > 0 {
                                    NutritionBadge(value: fat, label: "fat", color: NutritionBadgeConfig.fatColor)
                                        .frame(maxWidth: .infinity)
                                }
                                if let calories = foodItem.caloriesInServings(multiplier: calculatedPortion), calories > 0 {
                                    NutritionBadge(value: calories, unit: "kcal", color: NutritionBadgeConfig.caloriesColor)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                // Show reset button if original portion size or servings multiplier is available
                switch foodItem.nutrition {
                case .per100:
                    if let original = foodItem.portionSize {
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
                case .perServing:
                    if let original = foodItem.servingsMultiplier {
                        Button(action: resetSliderToOriginal) {
                            HStack {
                                Text("Reset to \(Double(original), specifier: "%.2f") \(original == 1 ? "serving" : "servings")")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
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
            switch foodItem.nutrition {
            case let .per100(values):
                return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
            case let .perServing(values):
                return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
            }
        }
    }
}

struct FoodItemsSelectorView: View {
    let searchResult: FoodItemGroup
    let onFoodItemSelected: (FoodItemDetailed) -> Void
    let onFoodItemRemoved: (FoodItemDetailed) -> Void
    let isItemAdded: (FoodItemDetailed) -> Bool
    let onDismiss: () -> Void
    let onImageSearch: (String) async -> [String]
    let onPersist: ((FoodItemDetailed) -> Void)?
    let onDelete: ((FoodItemDetailed) -> Void)?
    let useTransparentBackground: Bool

    var filterText: String = ""
    var showTagCloud: Bool = false

    @State private var selectedTags: Set<String> = []

    // All tags from all food items in this selector
    private var allExistingTags: Set<String> {
        Set(searchResult.foodItemsDetailed.flatMap { $0.tags ?? [] })
    }

    private var displayTitle: String {
        if searchResult.source == .database {
            return "Saved Foods"
        } else if let query = searchResult.textQuery {
            return query
        } else {
            return "Search Results"
        }
    }

    // Extract all unique tags from saved foods, with favorites first
    private var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        var hasFavorites = false

        // First pass: collect all tags
        for foodItem in searchResult.foodItemsDetailed {
            if let tags = foodItem.tags {
                for tag in tags {
                    if tag == FoodTags.favorites {
                        hasFavorites = true
                    }
                    if !seen.contains(tag) {
                        seen.insert(tag)
                        if tag != FoodTags.favorites {
                            result.append(tag)
                        }
                    }
                }
            }
        }

        // Always put favorites first if it exists
        if hasFavorites {
            result.insert(FoodTags.favorites, at: 0)
        }

        return result
    }

    private var filteredFoodItems: [FoodItemDetailed] {
        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = searchResult.foodItemsDetailed

        // Filter by text search
        if !trimmedFilter.isEmpty {
            items = items.filter { foodItem in
                foodItem.name.lowercased().contains(trimmedFilter)
            }
        }

        // Filter by selected tags
        if !selectedTags.isEmpty {
            items = items.filter { foodItem in
                guard let tags = foodItem.tags else { return false }
                // Food item must have ALL selected tags
                return selectedTags.allSatisfy { selectedTag in
                    tags.contains(selectedTag)
                }
            }
        }

        return items
    }

    var body: some View {
        Group {
            if filteredFoodItems.isEmpty && !filterText.isEmpty {
                // Show empty state in ScrollView when no results
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                            .padding(.top, 40)

                        Text("No foods found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .scrollDismissesKeyboard(.immediately)
            } else {
                // Use List for swipe actions support
                List {
                    // Tag cloud section (only for saved foods)
                    if showTagCloud && !allTags.isEmpty {
                        Section {
                            FoodTagCloudView(
                                tags: allTags,
                                selectedTags: $selectedTags
                            )
                            .padding(.vertical, 8)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(useTransparentBackground ? Color.clear : Color(.systemBackground))
                    }

                    ForEach(Array(filteredFoodItems.enumerated()), id: \.element.id) { index, foodItem in
                        if foodItem.name.isNotEmpty {
                            FoodItemsSelectorItemRow(
                                foodItem: foodItem,
                                portionSize: {
                                    // For per-serving nutrition, use servingsMultiplier (default 1.0)
                                    // For per-100 nutrition, use portionSize in grams (default to standardServingSize or 100)
                                    switch foodItem.nutrition {
                                    case .perServing:
                                        return foodItem.servingsMultiplier ?? 1.0
                                    case .per100:
                                        return foodItem.portionSize ?? foodItem.standardServingSize ?? 100
                                    }
                                }(),
                                onAdd: {
                                    onFoodItemSelected(foodItem)
                                },
                                onRemove: {
                                    onFoodItemRemoved(foodItem)
                                },
                                isAdded: isItemAdded(foodItem),
                                isFirst: index == 0,
                                isLast: index == filteredFoodItems.count - 1,
                                useTransparentBackground: useTransparentBackground,
                                onPersist: onPersist,
                                onDelete: onDelete,
                                onImageSearch: onImageSearch,
                                allExistingTags: allExistingTags
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(index == filteredFoodItems.count - 1 ? .hidden : .visible)
                            .listRowBackground(useTransparentBackground ? Color.clear : Color(.systemGray6))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .onChange(of: allExistingTags) { _, newValue in
            // Remove any selected tags that no longer exist
            selectedTags = selectedTags.intersection(newValue)
        }
    }
}

private struct FoodItemsSelectorItemRow: View {
    let foodItem: FoodItemDetailed
    let portionSize: Decimal
    let onAdd: () -> Void
    let onRemove: () -> Void
    let isAdded: Bool
    let isFirst: Bool
    let isLast: Bool
    let useTransparentBackground: Bool
    let onPersist: ((FoodItemDetailed) -> Void)?
    let onDelete: ((FoodItemDetailed) -> Void)?
    let onImageSearch: (String) async -> [String]
    let allExistingTags: Set<String>

    @State private var showItemInfo = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showImageSelector = false
    @State private var isSavingImage = false

    private var hasNutritionInfo: Bool {
        switch foodItem.nutrition {
        case let .per100(values):
            return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
        case let .perServing(values):
            return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Row Content
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Top row: Name + Confidence
                    HStack(spacing: 8) {
                        Text(foodItem.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Confidence badge (if AI source)
                        if foodItem.source.isAI, let confidence = foodItem.confidence {
                            ConfidenceBadge(level: confidence)
                        }
                    }

                    // Middle row: Portion badge + serving multiplier
                    HStack(spacing: 8) {
                        PortionSizeBadge(
                            value: portionSize,
                            color: .orange,
                            icon: "scalemass.fill",
                            foodItem: foodItem
                        )

                        // Only show serving multiplier for per100 items
                        if case .per100 = foodItem.nutrition {
                            if let servingSize = foodItem.standardServingSize {
                                Text("\(Double(portionSize / servingSize), specifier: "%.1f")× serving")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .opacity(0.7)
                            }
                        }
                    }
                }

                // Product image thumbnail (if available) - on the right
                // Make it tappable to open image selector (only for saved foods with onPersist)
                if onPersist != nil {
                    Button(action: {
                        showImageSelector = true
                    }) {
                        if isSavingImage {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    ProgressView()
                                        .controlSize(.small)
                                )
                        } else if foodItem.imageURL != nil {
                            // Has image - show it without any badge (clean look)
                            FoodItemThumbnail(imageURL: foodItem.imageURL)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        } else {
                            // No image - show placeholder with camera icon (only hint for adding)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    VStack(spacing: 2) {
                                        Image(systemName: "camera")
                                            .font(.system(size: 18))
                                            .foregroundColor(.secondary.opacity(0.6))
                                        Text("Add")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.secondary.opacity(0.6))
                                    }
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingImage)
                    .contextMenu {
                        if foodItem.imageURL != nil {
                            Button(role: .destructive) {
                                removeImage()
                            } label: {
                                Label("Remove Image", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    FoodItemThumbnail(imageURL: foodItem.imageURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                showItemInfo = true
            }

            // Compact nutrition info
            HStack(spacing: 6) {
                switch foodItem.nutrition {
                case .per100:
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
                case .perServing:
                    if let carbs = foodItem.carbsInServings(multiplier: portionSize) {
                        NutritionBadge(value: carbs, label: "carbs", color: NutritionBadgeConfig.carbsColor)
                    }
                    if let protein = foodItem.proteinInServings(multiplier: portionSize), protein > 0 {
                        NutritionBadge(value: protein, label: "protein", color: NutritionBadgeConfig.proteinColor)
                    }
                    if let fat = foodItem.fatInServings(multiplier: portionSize), fat > 0 {
                        NutritionBadge(value: fat, label: "fat", color: NutritionBadgeConfig.fatColor)
                    }
                    if let calories = foodItem.caloriesInServings(multiplier: portionSize), calories > 0 {
                        NutritionBadge(value: calories, unit: "kcal", color: NutritionBadgeConfig.caloriesColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if isAdded {
                Button(action: onRemove) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Remove from meal")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemGray5))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Add to Meal")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, isFirst ? 8 : 0)
        .padding(.bottom, isLast ? 8 : 0)
        .background(useTransparentBackground ? Color.clear : Color(.systemGray6))
        .when(onPersist != nil) { view in
            view.swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    showEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
        .when(onDelete != nil) { view in
            view.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .confirmationDialog(
            "Delete Saved Food",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                onDelete?(foodItem)
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: {
            Text(
                "Are you sure you want to permanently delete \"\(foodItem.name)\" from your saved foods? This action cannot be undone."
            )
        }
        .sheet(isPresented: $showItemInfo) {
            FoodItemInfoPopup(foodItem: foodItem, portionSize: portionSize)
                .presentationDetents([.height(preferredItemInfoHeight(for: foodItem)), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImageSelector) {
            ImageSelectorView(
                initialSearchTerm: foodItem.standardName ?? foodItem.name,
                onSave: { selectedImage in
                    handleImageSelection(selectedImage)
                },
                onSearch: onImageSearch
            )
        }
        .sheet(isPresented: $showEditSheet) {
            FoodItemEditorSheet(
                existingItem: foodItem,
                title: "Edit Saved Food",
                allowServingMultiplierEdit: false, // Don't allow editing multiplier for saved foods
                allExistingTags: allExistingTags,
                onSave: handleSave,
                onCancel: {
                    showEditSheet = false
                }
            )
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func handleSave(_ editedItem: FoodItemDetailed) {
        onPersist?(editedItem)
        showEditSheet = false
    }

    /// Handles image selection from the ImageSelectorView
    /// Resizes the image, saves it to storage, and updates the food item
    private func handleImageSelection(_ image: UIImage) {
        guard let onPersist = onPersist else { return }

        isSavingImage = true
        showImageSelector = false

        Task {
            // Save the image and get the file URL
            if let imageURL = await FoodImageStorageManager.shared.saveImage(image, for: foodItem.id) {
                // Update the food item with the new image URL
                let updatedItem = foodItem.withImageURL(imageURL)

                await MainActor.run {
                    onPersist(updatedItem)
                    isSavingImage = false
                }
            } else {
                await MainActor.run {
                    isSavingImage = false
                }
            }
        }
    }

    /// Removes the image from the food item
    private func removeImage() {
        guard let onPersist = onPersist else { return }

        // Update the food item with nil imageURL
        let updatedItem = foodItem.withImageURL(nil)
        onPersist(updatedItem)
    }

    private func preferredItemInfoHeight(for item: FoodItemDetailed) -> CGFloat {
        var base: CGFloat = 480
        if let notes = item.assessmentNotes, !notes.isEmpty { base += 40 }
        if let prep = item.preparationMethod, !prep.isEmpty { base += 30 }
        if let cues = item.visualCues, !cues.isEmpty { base += 30 }
        if (item.standardServing != nil && !item.standardServing!.isEmpty) ||
            item.standardServingSize != nil { base += 40 }
        return min(max(base, 460), 680)
    }

    private struct PortionSizeBadge: View {
        let value: Decimal
        let color: Color
        let icon: String
        let foodItem: FoodItemDetailed

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            HStack(spacing: 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .opacity(0.3)
                }
                HStack(spacing: 2) {
                    switch foodItem.nutrition {
                    case .per100:
                        Text("\(Double(value), specifier: "%.0f")")
                            .font(.system(size: 15, weight: .bold))
                        Text(NSLocalizedString((foodItem.units ?? .grams).localizedAbbreviation, comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.4)
                    case .perServing:
                        Text("\(Double(value), specifier: "%.1f")")
                            .font(.system(size: 15, weight: .bold))
                        Text(value == 1 ? "serving" : "servings")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.4)
                    }
                }
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemGray4))
            .cornerRadius(8)
        }
    }
}

// MARK: - Tag Cloud View

private struct FoodTagCloudView: View {
    let tags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
//            HStack(spacing: 6) {
//
//                Spacer()
//
//                // Clear all button (only show when tags are selected)
//                if !selectedTags.isEmpty {
//                    Button(action: {
//                        withAnimation(.easeInOut(duration: 0.2)) {
//                            selectedTags.removeAll()
//                        }
//                    }) {
//                        HStack(spacing: 3) {
//                            Image(systemName: "xmark.circle.fill")
//                                .font(.system(size: 11))
//                            Text("Clear")
//                                .font(.caption2)
//                                .fontWeight(.medium)
//                        }
//                        .foregroundColor(.secondary)
//                    }
//                    .buttonStyle(.plain)
//                }
//            }

            // Horizontal scrolling tag list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 1) // Tiny padding to prevent clipping
            }
        }
    }
}

// MARK: - Tag Chip

private struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isFavorites: Bool {
        tag == FoodTags.favorites
    }

    private var tagColor: Color {
        if isFavorites {
            return Color.purple
        }
        return stableColor(for: tag)
    }

    var body: some View {
        Button(action: onTap) {
            // Use a fixed-size container with overlay to prevent width changes
            Text(isFavorites ? tag : tag.uppercased())
                .font(.system(size: isFavorites ? 18 : 11, weight: .semibold, design: .default))
                .textCase(isFavorites ? nil : .uppercase)
                .fontDesign(.default)
                .kerning(isFavorites ? 0 : 0.5)
                .foregroundColor(isSelected ? .white : colorScheme == .dark ? .white : .primary)
                .opacity(isSelected ? 1.0 : 0.85) // Subtle opacity change instead of weight change
                .padding(.horizontal, isFavorites ? 8 : 10)
                .padding(.vertical, isFavorites ? 6 : 5)
                .background(
                    RoundedRectangle(cornerRadius: isFavorites ? 8 : 6, style: .continuous)
                        .fill(isSelected ? tagColor.opacity(0.85) : tagColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isFavorites ? 8 : 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : tagColor.opacity(colorScheme == .dark ? 0.45 : 0.35),
                            lineWidth: 1.0
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// Generates a stable, visually consistent color for a given string
    /// Uses a hash of the string to pick a hue, with perceptually adjusted lightness
    private func stableColor(for string: String) -> Color {
        // Generate a stable hash from the string
        var hash: UInt64 = 5381
        for char in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }

        // Use the hash to generate a hue (0-360 degrees)
        let hue = Double(hash % 360) / 360.0

        // Adjust brightness based on hue to maintain perceptual uniformity
        // Yellows and greens appear brighter, blues and purples appear darker
        // This compensates by adjusting brightness per hue
        let baseSaturation: Double = 0.70
        let baseBrightness: Double = colorScheme == .dark ? 0.70 : 0.65

        // Adjust brightness based on hue to compensate for perceptual differences
        // Blues/purples (240-300°) need to be brighter
        // Yellows/greens (60-180°) need to be darker
        let hueInDegrees = hue * 360
        var brightnessAdjustment: Double = 0

        if hueInDegrees >= 240 && hueInDegrees <= 300 {
            // Blue to purple range - boost brightness
            brightnessAdjustment = 0.15
        } else if hueInDegrees >= 180 && hueInDegrees < 240 {
            // Cyan to blue - moderate boost
            brightnessAdjustment = 0.10
        } else if hueInDegrees >= 60 && hueInDegrees <= 120 {
            // Yellow to green - reduce brightness
            brightnessAdjustment = -0.05
        } else if hueInDegrees > 30 && hueInDegrees < 60 {
            // Orange range - slight reduction
            brightnessAdjustment = -0.02
        }

        let adjustedBrightness = min(1.0, max(0.0, baseBrightness + brightnessAdjustment))

        return Color(hue: hue, saturation: baseSaturation, brightness: adjustedBrightness)
    }
}

// MARK: - Flow Layout

/// A layout that arranges its children in a flowing manner, wrapping to new lines as needed
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth, currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))

                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}

// MARK: - Tag Editor View

private struct TagEditorView: View {
    @Binding var selectedTags: Set<String>
    let allExistingTags: Set<String>

    // Combine selected tags and existing tags, with favorites always first
    private var allTags: [String] {
        var tags = selectedTags.union(allExistingTags)
        // Always include favorites in the list
        tags.insert(FoodTags.favorites)

        var result = Array(tags)
        // Sort so favorites comes first, then alphabetically
        result.sort { tag1, tag2 in
            if tag1 == FoodTags.favorites { return true }
            if tag2 == FoodTags.favorites { return false }
            return tag1 < tag2
        }
        return result
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(allTags, id: \.self) { tag in
                TagChip(
                    tag: tag,
                    isSelected: selectedTags.contains(tag),
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Collapsible Tags Section

private struct CollapsibleTagsSection: View {
    @Binding var selectedTags: Set<String>
    let allExistingTags: Set<String>
    @Binding var showingAddNewTag: Bool

    @State private var isExpanded: Bool = false

    // Get non-favorite tags (favorites is handled separately)
    private var nonFavoriteTags: [String] {
        var tags = selectedTags.union(allExistingTags)
        tags.remove(FoodTags.favorites)
        return Array(tags).sorted()
    }

    // Count of selected non-favorite tags
    private var selectedNonFavoriteCount: Int {
        selectedTags.filter { $0 != FoodTags.favorites }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header button to expand/collapse
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))

                    Text("Tags")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    if selectedNonFavoriteCount > 0 {
                        Text("(\(selectedNonFavoriteCount))")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Tags cloud
                    FlowLayout(spacing: 6) {
                        ForEach(nonFavoriteTags, id: \.self) { tag in
                            TagChip(
                                tag: tag,
                                isSelected: selectedTags.contains(tag),
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedTags.contains(tag) {
                                            selectedTags.remove(tag)
                                        } else {
                                            selectedTags.insert(tag)
                                        }
                                    }
                                }
                            )
                        }

                        // Add new tag button at the end of the flow
                        Button(action: {
                            showingAddNewTag = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text("New")
                                    .font(.system(size: 11, weight: .semibold))
                                    .textCase(.uppercase)
                                    .kerning(0.5)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.blue.opacity(0.35), lineWidth: 1.0)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }
}
