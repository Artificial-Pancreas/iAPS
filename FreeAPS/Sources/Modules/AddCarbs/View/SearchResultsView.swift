import PhotosUI
import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var state: FoodSearchStateModel
    let onContinue: (FoodItemDetailed, Date?) -> Void
    let onHypoTreatment: ((FoodItemDetailed, Date?) -> Void)?
    let onPersist: (FoodItemDetailed) -> Void
    let onDelete: (FoodItemDetailed) -> Void
    let continueButtonLabelKey: LocalizedStringKey
    let hypoTreatmentButtonLabelKey: LocalizedStringKey

    @State private var selectedTime: Date?
    @State private var showTimePicker = false
    @State private var isDownloadingImage = false
    @State private var showNutritionOverrideEditor = false

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
                } else if let latestSearchError = state.latestSearchError {
                    errorMessageBanner(message: latestSearchError, icon: state.latestSearchIcon)
                        .padding(.top, 12)
                        .padding(.horizontal)
                }

                if state.searchResultsState.nonDeletedItemCount > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        mealTotalsView
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5).opacity(0.5))
                            )

                        actionButtonRow
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                }
            }

            if let savedFoods = state.savedFoods, state.showSavedFoods {
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
                        filterText: state.foodSearchText,
                        showTagCloud: true
                    )
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if !state.searchResultsState.hasVisibleContent {
                noSearchesView
                    .transition(.opacity)
                    .scrollDismissesKeyboard(.immediately)
            } else {
                searchResultsView
                    .transition(.opacity)
                    .scrollDismissesKeyboard(.immediately)
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
                .navigationTitle(
                    searchResult.textQuery
                        .map { NSLocalizedString("Results for", comment: "") + " '\($0)'" } ??
                        NSLocalizedString("Search Results", comment: "")
                )
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
                allExistingTags: Set(state.savedFoods?.foodItems.flatMap { $0.tags ?? [] } ?? []),
                showTagsAndFavorite: false, // Don't show tags when adding manually to meal
                onSave: { foodItem in
                    state.addItem(foodItem, group: nil)
                    state.showManualEntry = false
                },
                onCancel: {
                    state.showManualEntry = false
                }
            )
            // .presentationDetents([.height(600), .large])
            // .presentationDragIndicator(.visible)
        }
    }

    private var actionButtonRow: some View {
        HStack(alignment: .center) {
            if state.searchResultsState.nonDeletedItemCount > 0 {
                Button(action: {
                    showTimePicker = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                        Text(
                            selectedTime.map { timeString(for: $0) } ?? NSLocalizedString("Now", comment: "")
                        )
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

                Spacer()

                if let onHypoTreatment = self.onHypoTreatment {
                    Button(action: {
                        let combinedFoodItem = createCombinedFoodItem()
                        onHypoTreatment(combinedFoodItem, selectedTime)
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
                    let combinedFoodItem = createCombinedFoodItem()
                    onContinue(combinedFoodItem, selectedTime)
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
        VStack(spacing: 12) {
            Button(action: {
                showNutritionOverrideEditor = true
            }) {
                HStack(spacing: 8) {
                    ForEach(NutrientType.allCases.filter { $0.isPrimary }) { nutrient in
                        NutritionBadgePlainStacked(
                            value: state.searchResultsState.total(nutrient),
                            localizedLabel: nutrient.localizedLabel,
                            color: nutrient.badgeColor
                        )
                        .id("\(nutrient.rawValue)-\(state.searchResultsState.total(nutrient))")
                        .transition(.scale.combined(with: .opacity))
                        .scaleEffect(1.2)
                    }
                    NutritionBadgePlainStacked(
                        value: state.searchResultsState.totalCalories,
                        localizedLabel: UnitEnergy.kilocalories.symbol,
                        color: NutritionBadgeConfig.caloriesColor
                    )
                    .id("calories-\(state.searchResultsState.totalCalories)")
                    .transition(.scale.combined(with: .opacity))
                    .scaleEffect(1.2)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.searchResultsState.totalCalories)

            // Show adjustments row if any overrides are active - also make it tappable
            if state.searchResultsState.hasNutritionOverrides {
                Button(action: {
                    showNutritionOverrideEditor = true
                }) {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Manual Adjustments")
                                .font(.caption2.smallCaps())
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            ForEach(NutrientType.allCases) { nutrient in
                                if let override = state.searchResultsState.nutritionOverrides[nutrient],
                                   abs(override) >= 0.1
                                {
                                    AdjustmentBadge(
                                        value: override,
                                        localizedLabel: nutrient.localizedLabel,
                                        color: nutrient.badgeColor
                                    )
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button {
                saveMealTotalsAsFoodItem()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
        .sheet(isPresented: $showNutritionOverrideEditor) {
            ManualNutritionOverrideEditor(state: state)
                .presentationDetents([.height(480), .medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func saveMealTotalsAsFoodItem() {
        let allItems = state.searchResultsState.nonDeletedItems
        guard !allItems.isEmpty else { return }

        let savedItem = FoodItemDetailed(
            name: "Complete Meal",
            nutrition: .perServing(values: state.searchResultsState.mealNutritionValues, servingsMultiplier: 1),
            standardServingSize: state.searchResultsState.aggregateServingSize(for: allItems),
            units: .grams,
            source: .manual
        )

        state.newFoodEntryToEdit = savedItem
        state.showNewSavedFoodEntry = true
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
                        onPersist: persistFoodItem,
                        savedFoodIds: Set(state.savedFoods?.foodItems.map(\.id) ?? []),
                        allExistingTags: Set(state.savedFoods?.foodItems.flatMap { $0.tags ?? [] } ?? [])
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
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private func timeString(for date: Date) -> String {
        Self.timeFormatter.string(from: date)
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

    private func createCombinedFoodItem() -> FoodItemDetailed {
        FoodItemDetailed(
            name: NSLocalizedString("Complete Meal", comment: ""),
            nutrition: .perServing(values: state.searchResultsState.mealNutritionValues, servingsMultiplier: 1),
            units: .grams,
            source: .manual
        )
    }

    private func persistFoodItem(_ foodItem: FoodItemDetailed) {
        if let imageURL = foodItem.imageURL, !imageURL.hasPrefix("local://") {
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
        guard let imageURL = foodItem.imageURL, !imageURL.hasPrefix("local://") else {
            return foodItem
        }

        guard let image = await downloadAndResolveImage(imageURL) else {
            return foodItem
        }

        guard let localURL = await FoodImageStorageManager.shared.saveImage(image, for: foodItem.id) else {
            return foodItem
        }

        return foodItem.copy(imageURL: localURL)
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

private struct FoodItemGroupListSection: View {
    let foodItemGroup: FoodItemGroup
    @ObservedObject var state: FoodSearchStateModel
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

    private func saveSectionAsFoodItem() {
        let items = foodItemGroup.foodItems.filter { !$0.deleted }
        guard !items.isEmpty else { return }

        let sectionName = foodItemGroup.briefDescription ?? foodItemGroup.textQuery ?? foodItemGroup.title

        let savedItem = FoodItemDetailed(
            name: sectionName,
            nutrition: .perServing(values: state.searchResultsState.nutritionValues(for: items), servingsMultiplier: 1),
            standardServingSize: state.searchResultsState.aggregateServingSize(for: items),
            units: .grams,
            source: .manual
        )

        state.newFoodEntryToEdit = savedItem
        state.showNewSavedFoodEntry = true
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
                ForEach(Array(foodItemGroup.foodItems.enumerated()), id: \.element.id) { index, foodItem in
                    Group {
                        if foodItem.deleted {
                            DeletedFoodItemRow(
                                foodItem: foodItem,
                                onUndelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        state.searchResultsState.undeleteItem(foodItem)
                                    }
                                },
                                isFirst: index == 0,
                                isLast: index == foodItemGroup.foodItems.count - 1
                            )
                        } else {
                            FoodItemRow(
                                foodItem: foodItem,
                                onPortionChange: { newPortion in
                                    state.searchResultsState.updateExistingItem(foodItem.withPortionSizeOrMultiplier(newPortion))
                                },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        state.searchResultsState.deleteItem(foodItem)
                                    }
                                },
                                onPersist: { foodItem in
                                    state.newFoodEntryToEdit = foodItem
                                    state.showNewSavedFoodEntry = true
                                },
                                savedFoodIds: savedFoodIds,
                                allExistingTags: allExistingTags,
                                isFirst: index == 0,
                                isLast: index == foodItemGroup.foodItems.count - 1
                            )
                        }
                    }
                    .listRowSeparator(index == foodItemGroup.foodItems.count - 1 ? .hidden : .visible)
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
