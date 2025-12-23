import PhotosUI
import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var state: FoodSearchStateModel
    let onFoodItemSelected: (FoodItemDetailed, Date?) -> Void
    let onCompleteMealSelected: ([FoodItemDetailed], Date?) -> Void
    let addButtonLabelKey: LocalizedStringKey = "" // TODO: not used currently
    let addAllButtonLabelKey: LocalizedStringKey

    @State private var clearedResultsViewState: SearchResultsState?
    @State private var selectedTime: Date?
    @State private var showTimePicker = false
    @State private var showManualEntry = false

    private var nonDeletedItemCount: Int {
        state.searchResultsState.nonDeletedItemCount
    }

    private var hasVisibleContent: Bool {
        state.searchResultsState.hasVisibleContent
    }

    private var totalCalories: Decimal {
        state.searchResultsState.visibleSections.flatMap(\.foodItemsDetailed).reduce(0) { sum, item in
            guard !state.searchResultsState.isDeleted(item) else { return sum }
            let portion = state.searchResultsState.portionSize(for: item)
            switch item.nutrition {
            case .per100:
                return sum + (item.caloriesInPortion(portion: portion) ?? 0)
            case .perServing:
                return sum + (item.caloriesInServings(multiplier: portion) ?? 0)
            }
        }
    }

    private var totalCarbs: Decimal {
        state.searchResultsState.visibleSections.flatMap(\.foodItemsDetailed).reduce(0) { sum, item in
            guard !state.searchResultsState.isDeleted(item) else { return sum }
            let portion = state.searchResultsState.portionSize(for: item)
            switch item.nutrition {
            case .per100:
                return sum + (item.carbsInPortion(portion: portion) ?? 0)
            case .perServing:
                return sum + (item.carbsInServings(multiplier: portion) ?? 0)
            }
        }
    }

    private var totalProtein: Decimal {
        state.searchResultsState.visibleSections.flatMap(\.foodItemsDetailed).reduce(0) { sum, item in
            guard !state.searchResultsState.isDeleted(item) else { return sum }
            let portion = state.searchResultsState.portionSize(for: item)
            switch item.nutrition {
            case .per100:
                return sum + (item.proteinInPortion(portion: portion) ?? 0)
            case .perServing:
                return sum + (item.proteinInServings(multiplier: portion) ?? 0)
            }
        }
    }

    private var totalFat: Decimal {
        state.searchResultsState.visibleSections.flatMap(\.foodItemsDetailed).reduce(0) { sum, item in
            guard !state.searchResultsState.isDeleted(item) else { return sum }
            let portion = state.searchResultsState.portionSize(for: item)
            switch item.nutrition {
            case .per100:
                return sum + (item.fatInPortion(portion: portion) ?? 0)
            case .perServing:
                return sum + (item.fatInServings(multiplier: portion) ?? 0)
            }
        }
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
                            state.addItem(selectedItem)
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
                            withAnimation(.easeInOut(duration: 0.3)) {
                                state.showSavedFoods = false
                            }
                        },
                        filterText: state.filterText
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
            let hasNewVisibleContent = !state.searchResultsState.visibleSections.isEmpty &&
                !state.searchResultsState.visibleSections.flatMap(\.foodItemsDetailed)
                .filter { !state.searchResultsState.isDeleted($0) }.isEmpty

            if clearedResultsViewState != nil, hasNewVisibleContent {
                withAnimation(.easeOut(duration: 0.2)) {
                    clearedResultsViewState = nil
                }
            }
        }
        .sheet(item: $state.latestTextSearch) { searchResult in
            NavigationStack {
                FoodItemsSelectorView(
                    searchResult: searchResult,
                    onFoodItemSelected: { selectedItem in
                        state.addItem(selectedItem)
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
                        state.latestTextSearch = nil
                    },
                    useTransparentBackground: true
                )
                .navigationTitle(searchResult.textQuery == nil ? "Search Results" : "Results for '\(searchResult.textQuery!)'")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            state.latestTextSearch = nil
                        }
                    }
                }
            }
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showManualEntry) {
            ManualFoodEntrySheet(
                onSave: { foodItem in
                    state.addItem(foodItem)
                    showManualEntry = false
                },
                onCancel: {
                    showManualEntry = false
                }
            )
            .presentationDetents([.height(600), .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var actionButtonRow: some View {
        HStack(alignment: .center) {
            // Manual Entry button
            Button(action: {
                showManualEntry = true
            }) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemGray5))
                    )
            }
            .buttonStyle(.plain)

            if state.savedFoods?.foodItemsDetailed.count ?? 0 > 0 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.showSavedFoods = true
                    }
                }) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.systemGray5))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if nonDeletedItemCount > 0 {
                // Time picker button
                Button(action: {
                    showTimePicker = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                        Text(selectedTime == nil ? "now" : timeString(for: selectedTime!))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.secondary)
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

            if hasVisibleContent {
                Button(action: {
                    let foodItems = state.searchResultsState.visibleSections.flatMap(\.foodItemsDetailed)
                        .filter { !state.searchResultsState.isDeleted($0) }
                        .map { $0.withPortion(state.searchResultsState.portionSize(for: $0)) }
                    onCompleteMealSelected(foodItems, selectedTime)
                }) {
                    Text(addAllButtonLabelKey)
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

            } else {
                Spacer()
                Button(action: {
                    state.showingFoodSearch = false
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .medium))
                        Text("Back")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemGray5))
                    )
                }
                .buttonStyle(.plain)
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
                        clearedResultsViewState?.deletedSections = state.searchResultsState.deletedSections
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
                    value: totalCarbs,
                    label: "carbs",
                    color: NutritionBadgeConfig.carbsColor
                )
                .id("carbs-\(totalCarbs)")
                .transition(.scale.combined(with: .opacity))

                TotalNutritionBadge(
                    value: totalProtein,
                    label: "protein",
                    color: NutritionBadgeConfig.proteinColor
                )
                .id("protein-\(totalProtein)")
                .transition(.scale.combined(with: .opacity))

                TotalNutritionBadge(
                    value: totalFat,
                    label: "fat",
                    color: NutritionBadgeConfig.fatColor
                )
                .id("fat-\(totalFat)")
                .transition(.scale.combined(with: .opacity))

                TotalNutritionBadge(
                    value: totalCalories,
                    label: "kcal",
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
                        state.searchResultsState.deletedSections = savedState.deletedSections
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
                ForEach(state.searchResultsState.visibleSections) { analysisResult in
                    AnalysisResultListSection(
                        analysisResult: analysisResult,
                        state: state,
                        onFoodItemSelected: onFoodItemSelected,
                        selectedTime: selectedTime
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
                // Three main capabilities
                VStack(spacing: 12) {
                    CapabilityCard(
                        icon: "text.magnifyingglass",
                        iconColor: .blue,
                        title: "Text Search",
                        description: "Search databases or describe food for AI analysis"
                    )

                    // Barcode Scanner Card
                    Button(action: {
                        state.foodSearchRoute = .barcodeScanner
                    }) {
                        CapabilityCard(
                            icon: "barcode.viewfinder",
                            iconColor: .blue,
                            title: "Barcode Scanner",
                            description: "Scan packaged foods for nutrition information"
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
                            description: "Snap a picture for AI-powered nutrition analysis. Long-press to choose from library."
                        )
                    }
                    .buttonStyle(.plain)

                    // Manual Entry Card
                    Button(action: {
                        showManualEntry = true
                    }) {
                        CapabilityCard(
                            icon: "pencil",
                            iconColor: .green,
                            title: "Manual Entry",
                            description: "Enter nutrition information manually"
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
}

// MARK: - Empty State Components

private struct CapabilityCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
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

// MARK: - Manual Food Entry Sheet

private struct ManualFoodEntrySheet: View {
    let onSave: (FoodItemDetailed) -> Void
    let onCancel: () -> Void

    @State private var editedPortionSize: Decimal = 100
    @State private var editedName: String = ""
    @State private var editedCaloriesPer100: Decimal?
    @State private var editedCarbsPer100: Decimal = 0
    @State private var editedProteinPer100: Decimal = 0
    @State private var editedFatPer100: Decimal = 0
    @State private var editedFiberPer100: Decimal?
    @State private var editedSugarsPer100: Decimal?
    @State private var editedServingSize: Decimal?

    private var canSave: Bool {
        editedCarbsPer100 >= 0 && editedProteinPer100 >= 0 && editedFatPer100 >= 0
    }

    private func autoGeneratedName() -> String {
        let carbs = editedCarbsPer100
        let protein = editedProteinPer100
        let fat = editedFatPer100

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
                EditableFoodItemInfoPopup(
                    portionSize: $editedPortionSize,
                    editedName: $editedName,
                    editedCaloriesPer100: $editedCaloriesPer100,
                    editedCarbsPer100: $editedCarbsPer100,
                    editedProteinPer100: $editedProteinPer100,
                    editedFatPer100: $editedFatPer100,
                    editedFiberPer100: $editedFiberPer100,
                    editedSugarsPer100: $editedSugarsPer100,
                    editedServingSize: $editedServingSize,
                    allowNutritionEditing: true
                )

                // Editable food name at bottom
                VStack(alignment: .leading, spacing: 8) {
                    Text("Food Name (Optional)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    TextField(autoGeneratedName(), text: $editedName)
                        .font(.body)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }
                .padding(.top, 12)
                .padding(.bottom, 8)

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
            .navigationTitle("Add Food Manually")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func saveFoodItem() {
        // Calculate calories from macros
        let calculatedCalories = (editedCarbsPer100 * 4) + (editedProteinPer100 * 4) + (editedFatPer100 * 9)

        // Use auto-generated name if user hasn't entered one
        let finalName = editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
            autoGeneratedName() : editedName

        // Use edited serving size if provided, otherwise nil
        let finalServingSize = editedServingSize

        let nutritionValues = NutritionValues(
            calories: calculatedCalories,
            carbs: editedCarbsPer100,
            fat: editedFatPer100,
            fiber: editedFiberPer100,
            protein: editedProteinPer100,
            sugars: editedSugarsPer100
        )

        let foodItem = FoodItemDetailed(
            name: finalName,
            nutrition: .per100(nutritionValues),
            confidence: nil,
            brand: nil,
            portionSize: editedPortionSize,
            standardServing: nil,
            standardServingSize: finalServingSize,
            units: .grams,
            preparationMethod: nil,
            visualCues: nil,
            glycemicIndex: nil,
            assessmentNotes: nil,
            imageURL: nil,
            imageFrontURL: nil,
            source: .manual
        )

        onSave(foodItem)
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

private extension FoodItemSource {
    var icon: String {
        switch self {
        case .aiPhoto:
            return "photo"
        case .aiMenu:
            return "photo" // TODO: better icon?
        case .aiReceipe:
            return "photo" // TODO: better icon?
        case .aiText:
            return "text.bubble"
        case .search:
            return "magnifyingglass"
        case .barcode:
            return "barcode"
        case .manual:
            return "pencil"
        case .database:
            return "archivebox.fill" // TODO: better icon?
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

private struct AnalysisResultListSection: View {
    let analysisResult: FoodItemGroup
    @ObservedObject var state: FoodSearchStateModel
    let onFoodItemSelected: (FoodItemDetailed, Date?) -> Void
    let selectedTime: Date?

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
                    if analysisResult.source?.isAI == true {
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
                                .frame(width: 44, height: 44)
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
                        state.searchResultsState.deleteSection(analysisResult.id)
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.searchResultsState.deleteSection(analysisResult.id)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    // TODO: Implement save functionality
                } label: {
                    Label("Save (TODO)", systemImage: "square.and.arrow.down")
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
                                onSelect: {
                                    let currentPortion = state.searchResultsState.portionSize(for: foodItem)
                                    onFoodItemSelected(
                                        foodItem.withPortion(currentPortion),
                                        selectedTime
                                    )
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

// MARK: - Editable Food Item Info Popup

private struct EditableFoodItemInfoPopup: View {
    @Binding var portionSize: Decimal
    @Binding var editedName: String
    @Binding var editedCaloriesPer100: Decimal?
    @Binding var editedCarbsPer100: Decimal
    @Binding var editedProteinPer100: Decimal
    @Binding var editedFatPer100: Decimal
    @Binding var editedFiberPer100: Decimal?
    @Binding var editedSugarsPer100: Decimal?
    @Binding var editedServingSize: Decimal?

    let allowNutritionEditing: Bool

    @State private var sliderMultiplier: Double = 1.0
    @State private var showAllNutrients: Bool = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name
        case carbs
        case protein
        case fat
        case fiber
        case sugars
        case servingSize
    }

    private var baseServingSize: Decimal {
        editedServingSize ?? 100
    }

    private var unit: String {
        MealUnits.grams.localizedAbbreviation
    }

    private var hasOptionalNutrients: Bool {
        (editedFiberPer100 != nil && editedFiberPer100! > 0) ||
            (editedSugarsPer100 != nil && editedSugarsPer100! > 0) ||
            (editedServingSize != nil && editedServingSize! > 0)
    }

    // Calculate calories from macros: Carbs (4 kcal/g) + Protein (4 kcal/g) + Fat (9 kcal/g)
    private var calculatedCaloriesPer100: Decimal {
        (editedCarbsPer100 * 4) + (editedProteinPer100 * 4) + (editedFatPer100 * 9)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Portion Size Slider
                VStack(spacing: 12) {
                    Text("\(Double(portionSize), specifier: "%.0f") \(unit)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.orange)

                    Slider(value: $sliderMultiplier, in: 0.25 ... 5.0, step: 0.25)
                        .tint(.orange)
                        .padding(.horizontal)

                    HStack {
                        Text("0.25x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("5x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .onChange(of: sliderMultiplier) { _, newValue in
                    portionSize = baseServingSize * Decimal(newValue)
                }

                // Nutrition Table with Editable Per100 values
                VStack(spacing: 8) {
                    // Header row
                    HStack(spacing: 8) {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("This portion")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)

                        Text("Per 100\(unit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Divider()

                    EditableDetailedNutritionRow(
                        label: "Carbs",
                        portionValue: editedCarbsPer100 / 100 * portionSize,
                        per100Value: $editedCarbsPer100,
                        unit: "g",
                        isEditable: allowNutritionEditing,
                        focusedField: $focusedField,
                        field: .carbs
                    )
                    Divider()
                    EditableDetailedNutritionRow(
                        label: "Protein",
                        portionValue: editedProteinPer100 / 100 * portionSize,
                        per100Value: $editedProteinPer100,
                        unit: "g",
                        isEditable: allowNutritionEditing,
                        focusedField: $focusedField,
                        field: .protein
                    )
                    Divider()
                    EditableDetailedNutritionRow(
                        label: "Fat",
                        portionValue: editedFatPer100 / 100 * portionSize,
                        per100Value: $editedFatPer100,
                        unit: "g",
                        isEditable: allowNutritionEditing,
                        focusedField: $focusedField,
                        field: .fat
                    )

                    // Optional: Fiber (only show if toggled or has value)
                    if showAllNutrients {
                        Divider()
                        EditableDetailedNutritionRow(
                            label: "Fiber",
                            portionValue: (editedFiberPer100 ?? 0) / 100 * portionSize,
                            per100Value: Binding(
                                get: { editedFiberPer100 ?? 0 },
                                set: { editedFiberPer100 = $0 > 0 ? $0 : nil }
                            ),
                            unit: "g",
                            isEditable: allowNutritionEditing,
                            focusedField: $focusedField,
                            field: .fiber
                        )
                    }

                    // Optional: Sugars (only show if toggled or has value)
                    if showAllNutrients {
                        Divider()
                        EditableDetailedNutritionRow(
                            label: "Sugar",
                            portionValue: (editedSugarsPer100 ?? 0) / 100 * portionSize,
                            per100Value: Binding(
                                get: { editedSugarsPer100 ?? 0 },
                                set: { editedSugarsPer100 = $0 > 0 ? $0 : nil }
                            ),
                            unit: "g",
                            isEditable: allowNutritionEditing,
                            focusedField: $focusedField,
                            field: .sugars
                        )
                    }

                    Divider()
                    // Display-only calculated calories (read-only)
                    CalculatedCaloriesRow(
                        label: "Calories",
                        portionValue: calculatedCaloriesPer100 / 100 * portionSize,
                        per100Value: calculatedCaloriesPer100,
                        unit: "kcal"
                    )

                    // Optional: Serving Size (only show if toggled)
                    if showAllNutrients {
                        Divider()
                        EditableServingSizeRow(
                            servingSize: Binding(
                                get: { editedServingSize ?? 0 },
                                set: { editedServingSize = $0 > 0 ? $0 : nil }
                            ),
                            unit: unit,
                            isEditable: allowNutritionEditing,
                            focusedField: $focusedField,
                            field: .servingSize
                        )
                    }

                    // Button to reveal optional nutrients (disappears after clicked)
                    if allowNutritionEditing && !showAllNutrients {
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
        .onAppear {
            if baseServingSize > 0 {
                sliderMultiplier = Double(portionSize / baseServingSize)
            }
            // Auto-expand if food already has optional nutrients
            if hasOptionalNutrients {
                showAllNutrients = true
            }
        }
    }

    // Auto-generate food name based on macros
    private var autoGeneratedName: String {
        let carbs = editedCarbsPer100
        let protein = editedProteinPer100
        let fat = editedFatPer100

        // Calculate total macros
        let total = carbs + protein + fat

        guard total > 0 else { return "Custom Food" }

        // Calculate percentages
        let carbPercent = (carbs / total) * 100
        let proteinPercent = (protein / total) * 100
        let fatPercent = (fat / total) * 100

        // Determine dominant macro (>50%)
        if carbPercent > 50 {
            if proteinPercent > 20 {
                return "Carb & Protein Meal"
            } else if fatPercent > 20 {
                return "Carb & Fat Snack"
            } else {
                return "High-Carb Food"
            }
        } else if proteinPercent > 50 {
            if carbPercent > 20 {
                return "Protein & Carb Meal"
            } else if fatPercent > 20 {
                return "Protein & Fat Meal"
            } else {
                return "High-Protein Food"
            }
        } else if fatPercent > 50 {
            if carbPercent > 20 {
                return "Fat & Carb Snack"
            } else if proteinPercent > 20 {
                return "Fat & Protein Meal"
            } else {
                return "High-Fat Food"
            }
        }

        // Balanced macros - check if any are very low
        if carbPercent < 10 && proteinPercent > 25 && fatPercent > 25 {
            return "Low-Carb Meal"
        } else if fatPercent < 10 && carbPercent > 25 && proteinPercent > 25 {
            return "Low-Fat Meal"
        } else if proteinPercent < 10 && carbPercent > 25 && fatPercent > 25 {
            return "Low-Protein Snack"
        }

        // If nothing specific matches, it's balanced
        return "Balanced Meal"
    }
}

// Helper view for editable detailed nutrition rows
private struct EditableDetailedNutritionRow: View {
    let label: String
    let portionValue: Decimal
    @Binding var per100Value: Decimal
    let unit: String
    let isEditable: Bool

    var focusedField: FocusState<EditableFoodItemInfoPopup.Field?>.Binding
    let field: EditableFoodItemInfoPopup.Field

    @State private var editText: String = ""

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
                    .frame(width: 24, alignment: .leading)
            }
            .frame(width: 80, alignment: .trailing)

            // Per 100g/ml value (editable if enabled)
            if isEditable {
                HStack(spacing: 4) {
                    TextField("0", text: $editText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .focused(focusedField, equals: field)
                        .onChange(of: editText) { _, newValue in
                            if newValue.isEmpty {
                                // User cleared the field, set to 0
                                per100Value = 0
                            } else if let decimal = Decimal(string: newValue) {
                                per100Value = decimal
                            }
                        }
                        .onAppear {
                            // Only show value if it's greater than 0, otherwise leave empty
                            editText = per100Value > 0 ? "\(per100Value)" : ""
                        }

                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(width: 100, alignment: .trailing)
                .padding(.leading, 8)
            } else {
                HStack(spacing: 2) {
                    Text("\(Double(per100Value), specifier: "%.1f")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 24, alignment: .leading)
                }
                .frame(width: 100, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// Helper view for displaying calculated (read-only) calories
private struct CalculatedCaloriesRow: View {
    let label: String
    let portionValue: Decimal
    let per100Value: Decimal
    let unit: String

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
                    .frame(width: 24, alignment: .leading)
            }
            .frame(width: 80, alignment: .trailing)

            // Per 100g/ml value (calculated, read-only)
            HStack(spacing: 4) {
                Text("\(Double(per100Value), specifier: "%.1f")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(width: 100, alignment: .trailing)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// Helper view for editable serving size row
private struct EditableServingSizeRow: View {
    @Binding var servingSize: Decimal
    let unit: String
    let isEditable: Bool

    var focusedField: FocusState<EditableFoodItemInfoPopup.Field?>.Binding
    let field: EditableFoodItemInfoPopup.Field

    @State private var editText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("Serving Size")
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Empty space for "per portion" column (N/A for serving size)
            Spacer()
                .frame(width: 80, alignment: .trailing)

            // Serving size value (editable if enabled)
            if isEditable {
                HStack(spacing: 4) {
                    TextField("optional", text: $editText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .focused(focusedField, equals: field)
                        .onChange(of: editText) { _, newValue in
                            if newValue.isEmpty {
                                // User cleared the field, set to 0
                                servingSize = 0
                            } else if let decimal = Decimal(string: newValue) {
                                servingSize = decimal
                            }
                        }
                        .onAppear {
                            // Only show value if it's greater than 0, otherwise leave empty
                            editText = servingSize > 0 ? "\(servingSize)" : ""
                        }

                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(width: 100, alignment: .trailing)
                .padding(.leading, 8)
            } else {
                HStack(spacing: 2) {
                    if servingSize > 0 {
                        Text("\(Double(servingSize), specifier: "%.1f")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                            .frame(width: 24, alignment: .leading)
                    } else {
                        Text("—")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(width: 100, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
                    if let imageURLString = foodItem.imageURL, let imageURL = URL(string: imageURLString) {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        ProgressView()
                                            .controlSize(.small)
                                    )
                            case let .success(image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 24))
                                            .foregroundColor(.secondary)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
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
                        if foodItem.source?.isAI == true, let confidence = foodItem.confidence {
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

/// Reusable component for displaying food item product images
private struct FoodItemThumbnail: View {
    let imageURL: String?

    var body: some View {
        if let imageURLString = imageURL, let imageURL = URL(string: imageURLString) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            ProgressView()
                                .controlSize(.small)
                        )
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        )
                @unknown default:
                    EmptyView()
                }
            }
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
    let foodItem: FoodItemDetailed
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
        switch foodItem.nutrition {
        case let .per100(values):
            return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
        case let .perServing(values):
            return values.calories != nil || values.carbs != nil || values.protein != nil || values.fat != nil
        }
    }

    private var baseServingSize: Decimal {
        switch foodItem.nutrition {
        case .per100:
            return foodItem.standardServingSize ?? 100
        case .perServing:
            return 1
        }
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
                                if foodItem.source?.isAI == true, let confidence = foodItem.confidence {
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
                    Button {
                        showPortionAdjuster = true
                    } label: {
                        Label("Edit Portion", systemImage: "slider.horizontal.3")
                    }
                }

                if onDelete != nil {
                    Button(role: .destructive) {
                        onDelete?()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Button {
                    // TODO: Implement save functionality
                } label: {
                    Label("Save (TODO)", systemImage: "square.and.arrow.down")
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

        private var baseServingSize: Decimal {
            switch foodItem.nutrition {
            case .per100:
                return foodItem.standardServingSize ?? 100
            case .perServing:
                return 1
            }
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
                return baseServingSize * Decimal(sliderMultiplier)
            case .perServing:
                return Decimal(sliderMultiplier)
            }
        }

        private func resetSliderToOriginal() {
            switch foodItem.nutrition {
            case .per100:
                if let original = foodItem.portionSize, baseServingSize > 0 {
                    sliderMultiplier = Double(original / baseServingSize)
                }
            case .perServing:
                if let original = foodItem.servingsMultiplier {
                    sliderMultiplier = Double(original)
                }
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
                    if let imageURLString = foodItem.imageURL, let imageURL = URL(string: imageURLString) {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        ProgressView()
                                            .controlSize(.small)
                                    )
                            case let .success(image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 24))
                                            .foregroundColor(.secondary)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                VStack(spacing: 8) {
                    switch foodItem.nutrition {
                    case .per100:
                        Text("\(Double(calculatedPortion), specifier: "%.0f") \(unit)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.orange)

                        if foodItem.standardServingSize != nil {
                            Text("\(sliderMultiplier, specifier: "%.2f")× serving")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    case .perServing:
                        Text("\(Double(calculatedPortion), specifier: "%.2f") \(calculatedPortion == 1 ? "serving" : "servings")")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.orange)
                    }
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

// MARK: - Text Search Results Sheet

struct FoodItemsSelectorView: View {
    let searchResult: FoodItemGroup
    let onFoodItemSelected: (FoodItemDetailed) -> Void
    let onFoodItemRemoved: (FoodItemDetailed) -> Void
    let isItemAdded: (FoodItemDetailed) -> Bool
    let onDismiss: () -> Void
    var useTransparentBackground: Bool = false
    var filterText: String = ""

    private var displayTitle: String {
        if searchResult.source == .database {
            return "Saved Foods"
        } else if let query = searchResult.textQuery {
            return query
        } else {
            return "Search Results"
        }
    }

    private var filteredFoodItems: [FoodItemDetailed] {
        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedFilter.isEmpty else {
            return searchResult.foodItemsDetailed
        }

        return searchResult.foodItemsDetailed.filter { foodItem in
            foodItem.name.lowercased().contains(trimmedFilter)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(filteredFoodItems.enumerated()), id: \.element.id) { index, foodItem in
                    if foodItem.name.isNotEmpty {
                        TextSearchFoodItemRow(
                            foodItem: foodItem,
                            portionSize: foodItem.portionSize ?? foodItem.standardServingSize ?? 100,
                            onAdd: {
                                onFoodItemSelected(foodItem)
                            },
                            onRemove: {
                                onFoodItemRemoved(foodItem)
                            },
                            isAdded: isItemAdded(foodItem),
                            isFirst: index == 0,
                            isLast: index == filteredFoodItems.count - 1,
                            useTransparentBackground: useTransparentBackground
                        )

                        if index != filteredFoodItems.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }

                // Show a message if filter returns no results
                if filteredFoodItems.isEmpty && !filterText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                            .padding(.top, 40)

                        Text("No foods found")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - Text Search Food Item Row

private struct TextSearchFoodItemRow: View {
    let foodItem: FoodItemDetailed
    let portionSize: Decimal
    let onAdd: () -> Void
    let onRemove: () -> Void
    let isAdded: Bool
    let isFirst: Bool
    let isLast: Bool
    let useTransparentBackground: Bool

    @State private var showItemInfo = false

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
                        if foodItem.source?.isAI == true, let confidence = foodItem.confidence {
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
                FoodItemThumbnail(imageURL: foodItem.imageURL)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                showItemInfo = true
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

            // Add button row (full width)
            if isAdded {
                Button(action: onRemove) {
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Remove")
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
