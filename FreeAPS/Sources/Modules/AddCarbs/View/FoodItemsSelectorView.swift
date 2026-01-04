import Foundation
import SwiftUI

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

    // Extract tags that exist in foods matching the currently selected tags
    // This creates a progressive filtering experience
    private var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        var hasFavorites = false

        // Get foods that match currently selected tags (or all foods if nothing selected)
        let matchingFoods: [FoodItemDetailed]
        if selectedTags.isEmpty {
            matchingFoods = searchResult.foodItemsDetailed
        } else {
            matchingFoods = searchResult.foodItemsDetailed.filter { foodItem in
                guard let tags = foodItem.tags else { return false }
                // Food item must have ALL selected tags
                return selectedTags.allSatisfy { selectedTag in
                    tags.contains(selectedTag)
                }
            }
        }

        // Collect all tags from matching foods
        for foodItem in matchingFoods {
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
            HStack(alignment: .center, spacing: 12) {
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

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(foodItem.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: isAdded ? onRemove : onAdd) {
                            Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(isAdded ? .green : .accentColor)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        if case .per100 = foodItem.nutrition {
                            NutritionBadgePlain(value: portionSize, unit: "g", label: "", color: .primary)
                        } else {
                            VStack {}
                                .frame(maxWidth: .infinity)
                        }

                        switch foodItem.nutrition {
                        case .per100:
                            if let carbs = foodItem.carbsInPortion(portion: portionSize) {
                                NutritionBadgePlainStacked(value: carbs, label: "carbs", color: NutritionBadgeConfig.carbsColor)
                                    .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                            if let protein = foodItem.proteinInPortion(portion: portionSize), protein > 0 {
                                NutritionBadgePlainStacked(
                                    value: protein,
                                    label: "protein",
                                    color: NutritionBadgeConfig.proteinColor
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                            if let fat = foodItem.fatInPortion(portion: portionSize), fat > 0 {
                                NutritionBadgePlainStacked(value: fat, label: "fat", color: NutritionBadgeConfig.fatColor)
                                    .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                            if let kcal = foodItem.caloriesInPortion(portion: portionSize), kcal > 0 {
                                NutritionBadgePlainStacked(value: kcal, label: "kcal", color: NutritionBadgeConfig.caloriesColor)
                                    .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                        case .perServing:
                            if let carbs = foodItem.carbsInServings(multiplier: portionSize) {
                                NutritionBadgePlainStacked(value: carbs, label: "carbs", color: NutritionBadgeConfig.carbsColor)
                                    .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                            if let protein = foodItem.proteinInServings(multiplier: portionSize), protein > 0 {
                                NutritionBadgePlainStacked(
                                    value: protein,
                                    label: "protein",
                                    color: NutritionBadgeConfig.proteinColor
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                            if let fat = foodItem.fatInServings(multiplier: portionSize), fat > 0 {
                                NutritionBadgePlainStacked(value: fat, label: "fat", color: NutritionBadgeConfig.fatColor)
                                    .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                            if let kcal = foodItem.fatInServings(multiplier: portionSize), kcal > 0 {
                                NutritionBadgePlainStacked(value: kcal, label: "kcal", color: NutritionBadgeConfig.caloriesColor)
                                    .frame(maxWidth: .infinity)
                            } else {
                                VStack {}
                                    .frame(maxWidth: .infinity)
                            }
                        }

//                        if case .per100 = foodItem.nutrition {
//                            PortionSizeBadge(
//                                value: portionSize,
//                                color: .orange,
//                                icon: "scalemass.fill",
//                                foodItem: foodItem
//                            )
//                        }
                    }
                    .padding(.trailing, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                showItemInfo = true
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
