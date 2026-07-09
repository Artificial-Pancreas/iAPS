import Combine
import CoreData
import OSLog
import SwiftUI
import Swinject

extension AddCarbs {
    struct RootView: BaseView {
        let resolver: Resolver
        let editMode: Bool
        let override: Bool
        let mode: MealMode.Mode
        @StateObject var state: StateModel
        @StateObject var foodSearchState = FoodSearchStateModel()

        @State var dish: String = ""
        @State var isPromptPresented = false
        @State var saved = false
        @State var pushed = false
        @State var button = false

        @State private var showAlert = false
        @State private var presentPresets = false
        @State private var string = ""
        @State private var showMicronutrients = false

        // Food Search States
        @State private var showCancelConfirmation = false

        @State private var newPreset: (
            dish: String,
            carbs: Decimal,
            fat: Decimal,
            protein: Decimal,
            fiber: Decimal,
            micronutrient: [MicronutrientValue]
        ) = ("", 0, 0, 0, 0, [])

        @FetchRequest(
            entity: Presets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "dish", ascending: true)], predicate:
            NSCompoundPredicate(
                andPredicateWithSubpredicates: [
                    NSPredicate(format: "dish != %@", " " as String),
                    NSPredicate(format: "dish != %@", "Empty" as String)
                ]
            )
        ) var carbPresets: FetchedResults<Presets>

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var mainState: Main.StateModel

        init(
            resolver: Resolver,
            editMode: Bool,
            override: Bool,
            mode: MealMode.Mode
        ) {
            self.resolver = resolver
            self.editMode = editMode
            self.override = override
            self.mode = mode
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        private static let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }()

        private func format(_ value: Decimal) -> String {
            Self.formatter.string(from: value as NSNumber) ?? ""
        }

        var body: some View {
            content
                .background(Color(.systemGroupedBackground))
                .compactSectionSpacing()
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: leadingNavItem, trailing: trailingNavItem)
                .sheet(isPresented: $foodSearchState.showingSettings) {
                    FoodSearchSettingsView(state: state)
                }
                .sheet(isPresented: $isPromptPresented) { editView }
                .confirmationDialog(
                    "Discard Meal?",
                    isPresented: $showCancelConfirmation,
                    titleVisibility: .visible,
                    actions: cancelDialogActions,
                    message: { Text("Do you want to discard this meal?") }
                )
                .onAppear(perform: handleOnAppear)
                .onDisappear { mainState.shouldPreventModalDismiss = false }
                .onChange(of: shouldPreventDismiss) { syncDismissState() }
                .onChange(of: foodSearchState.showSavedFoods) { syncDismissState() }
                .onChange(of: carbPresets.count) { updateSavedFoods() }
                .sheet(isPresented: $foodSearchState.showNewSavedFoodEntry) { foodItemEditorSheet }
        }

        @ViewBuilder private var content: some View {
            VStack(spacing: 0) {
                FoodSearchBar(rootState: state, state: foodSearchState)
                    .padding(.horizontal)

                if foodSearchState.showingFoodSearch {
                    foodSearchView
                } else {
                    mealView
                }
            }
        }

        private var foodSearchView: some View {
            FoodSearchView(
                state: foodSearchState,
                onContinue: handleFoodContinue,
                onHypoTreatment: hypoHandler,
                onPersist: saveOrUpdatePreset,
                onDelete: deletePreset,
                continueButtonLabelKey: continueLabel,
                hypoTreatmentButtonLabelKey: "Hypo Treatment"
            )
        }

        @ViewBuilder private var foodItemEditorSheet: some View {
            FoodItemEditorSheet(
                existingItem: foodSearchState.newFoodEntryToEdit,
                title: NSLocalizedString("Add Food Manually", comment: ""),
                allExistingTags: Set(foodSearchState.savedFoods?.foodItems.flatMap { $0.tags ?? [] } ?? []),
                showTagsAndFavorite: true,
                onSave: { foodItem in
                    saveOrUpdatePreset(foodItem)
                    foodSearchState.showNewSavedFoodEntry = false
                    foodSearchState.newFoodEntryToEdit = nil
                },
                onCancel: {
                    foodSearchState.showNewSavedFoodEntry = false
                    foodSearchState.newFoodEntryToEdit = nil
                }
            )
        }

        private var hypoHandler: ((FoodItemDetailed, UIImage?, Date?) -> Void)? {
            guard state.id != nil,
                  state.id != "None",
                  state.carbsRequired != nil else { return nil }

            return { food, _, date in
                button.toggle()
                guard button else { return }

                state.hypoTreatment = true
                state.addAIFood(override, fetch: editMode, food: food, date: date)
            }
        }

        private var navigationTitle: LocalizedStringKey {
            foodSearchState.showSavedFoods ? "Saved Foods" : "Add Meal"
        }

        @ViewBuilder private var leadingNavItem: some View {
            if foodSearchState.showSavedFoods {
                Button(action: {
                    foodSearchState.showNewSavedFoodEntry = true
                }) {
                    Label("New", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.blue)
                }
            }
        }

        private var trailingNavItem: some View {
            Button(action: handleDismissAction) {
                Text(foodSearchState.showSavedFoods ? "Done" : "Cancel")
            }
        }

        private var continueLabel: LocalizedStringKey {
            (state.skipBolus && !override && !editMode) ? "Save" : "Continue"
        }

        @ViewBuilder private func cancelDialogActions() -> some View {
            Button("Discard", role: .destructive) {
                state.hideModal()
                if editMode { state.apsManager.determineBasalSync() }
            }
            Button("Cancel", role: .cancel) {}
        }

        // MARK: - Main Meal Section

        private var mealView: some View {
            Form {
                if let carbsReq = state.carbsRequired,
                   state.carbs < carbsReq
                {
                    Section {
                        HStack {
                            Text("Carbs required")

                            Spacer()

                            Text(
                                (Self.formatter.string(
                                    from: carbsReq as NSNumber
                                ) ?? "") + " g"
                            )
                        }
                    }
                }

                Section {
                    macroRow(
                        title: "Carbs",
                        value: $state.carbs,
                        color: .primary,
                        bold: true,
                        autofocus: true
                    )

                    macroRow(
                        title: "Fat",
                        value: $state.fat,
                        color: .blue
                    )

                    macroRow(
                        title: "Protein",
                        value: $state.protein,
                        color: .green
                    )

                    if state.mealViewMicronutrients {
                        otherNutritionButton
                    }

                    timeRow
                }

                if !empty, !saved {
                    savePresetButton
                }

                if state.carbs > 0,
                   let profile = state.id,
                   profile != "None",
                   state.carbsRequired != nil
                {
                    hypoTreatmentSection
                }

                continueSection
            }
            .sheet(isPresented: $presentPresets) {
                presetView
            }
            .sheet(isPresented: $showMicronutrients) {
                OtherNutritionSheet(
                    fiber: $state.fiber,
                    note: $state.note,
                    micronutrients: $state.micronutrient,
                    formatter: Self.formatter
                )
            }
        }

        // MARK: - Compact Macro Row

        @ViewBuilder private func macroRow(
            title: LocalizedStringKey,
            value: Binding<Decimal>,
            color: Color,
            bold: Bool = false,
            autofocus: Bool = false
        ) -> some View {
            HStack {
                Text(title)
                    .foregroundStyle(color)
                    .fontWeight(bold ? .semibold : .regular)

                Spacer()

                DecimalTextField(
                    "0",
                    value: value,
                    formatter: Self.formatter,
                    autofocus: autofocus,
                    liveEditing: true
                )

                Text("g")
                    .foregroundStyle(.secondary)
            }
        }

        private var otherNutritionButton: some View {
            Button {
                showMicronutrients = true
            } label: {
                HStack {
                    Label("Other", systemImage: "ellipsis.circle")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(otherNutritionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private var otherNutritionSummary: String {
            let hasFiber = state.fiber > 0
            let microCount = state.micronutrient.count

            switch (hasFiber, microCount > 0) {
            case (false, false):
                return state.note

            case (true, false):
                return "Fiber"

            case (false, true):
                return "\(microCount) micros"

            case (true, true):
                return "Fiber • \(microCount)"
            }
        }

        // MARK: - Time Row

        private var timeRow: some View {
            HStack {
                Text("Time")

                Spacer()

                if !pushed {
                    Button {
                        pushed = true
                    } label: {
                        Text("Now")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 5)

                } else {
                    Button {
                        state.date = state.date.addingTimeInterval(
                            -15.minutes.timeInterval
                        )
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .tint(.blue)
                    .buttonStyle(.borderless)

                    DatePicker(
                        "Time",
                        selection: $state.date,
                        displayedComponents: [.hourAndMinute]
                    )
                    .controlSize(.mini)
                    .labelsHidden()

                    Button {
                        state.date = state.date.addingTimeInterval(
                            15.minutes.timeInterval
                        )
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .tint(.blue)
                    .buttonStyle(.borderless)
                }
            }
        }

        private var savePresetButton: some View {
            Button {
                saveAsPreset()
            } label: {
                Text("Save as preset")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .listRowBackground(Color(.systemGroupedBackground))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }

        // MARK: - Hypo Section

        private var hypoTreatmentSection: some View {
            Section {
                Button {
                    state.hypoTreatment = true

                    button.toggle()

                    if button {
                        state.add(override, fetch: editMode)
                    }

                } label: {
                    Text("Hypo Treatment")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color(.orange).opacity(0.9))
            .tint(.white)
        }

        // MARK: - Continue Section

        private var continueSection: some View {
            Section {
                Button {
                    button.toggle()

                    if button {
                        state.add(override, fetch: editMode)
                    }

                } label: {
                    Text(
                        (
                            (state.skipBolus && !override && !editMode)
                                || state.carbs <= 0
                        )
                            ? "Save"
                            : "Continue"
                    )
                }
                .disabled(empty)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(
                !empty
                    ? Color(.systemBlue)
                    : Color(.systemGray4)
            )
            .tint(.white)
        }

        private struct OtherNutritionSheet: View {
            @Binding var fiber: Decimal
            @Binding var note: String
            @Binding var micronutrients: [MicronutrientValue]

            let formatter: NumberFormatter

            @Environment(\.dismiss) private var dismiss

            var body: some View {
                NavigationStack {
                    Form {
                        Section("Note") {
                            TextField("Meal", text: $note)
                        }

                        Section("Fiber") {
                            HStack {
                                Text("Fiber")

                                Spacer()

                                DecimalTextField(
                                    "0",
                                    value: $fiber,
                                    formatter: formatter,
                                    autofocus: false,
                                    liveEditing: true
                                )

                                Text("g")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        MicronutrientSection(
                            values: $micronutrients,
                            formatter: formatter
                        )
                    }
                    .navigationTitle("Other")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }

        // MARK: - Micronutrient Section

        private struct MicronutrientSection: View {
            @Binding var values: [MicronutrientValue]

            let formatter: NumberFormatter

            @State private var selected = MicroNutrient.allCases.first!
            @State private var amount: Decimal = 0

            private var sortedNutrients: [MicroNutrient] {
                MicroNutrient.allCases.sorted {
                    $0.displayName < $1.displayName
                }
            }

            var body: some View {
                Section("Micronutrients") {
                    Picker("Nutrient", selection: $selected) {
                        ForEach(sortedNutrients, id: \.self) { nutrient in

                            Text(nutrient.displayName)
                                .tag(nutrient)
                        }
                    }

                    HStack {
                        Text("Amount")

                        Spacer()

                        DecimalTextField(
                            "0",
                            value: $amount,
                            formatter: formatter,
                            autofocus: false,
                            liveEditing: true
                        )

                        Text(selected.unit)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        addOrUpdate()

                    } label: {
                        Text("Add Micronutrient")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(amount <= 0)
                }

                if !values.isEmpty {
                    Section("Added") {
                        ForEach(
                            values.sorted { $0.name < $1.name }
                        ) { value in

                            HStack {
                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(value.name)

                                    Text(
                                        value.substance.coreDataType
                                            .capitalized
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(value.formattedAmount)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }

            private func addOrUpdate() {
                var dict = Dictionary(
                    uniqueKeysWithValues: values.map {
                        ($0.substance, $0)
                    }
                )

                dict[selected] = MicronutrientValue(
                    substance: selected,
                    amount: amount,
                    amountPer100: 0
                )

                values = dict.values
                    .filter {
                        $0.amount > 0 || $0.amountPer100 > 0
                    }
                    .sorted {
                        $0.name < $1.name
                    }

                amount = 0
            }

            private func delete(at offsets: IndexSet) {
                let sortedValues = values.sorted {
                    $0.name < $1.name
                }

                let substancesToDelete = offsets.map {
                    sortedValues[$0].substance
                }

                values.removeAll {
                    substancesToDelete.contains($0.substance)
                }
            }
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Fat").foregroundColor(.blue)
                Spacer()
                DecimalTextField(
                    "0",
                    value: $state.fat,
                    formatter: Self.formatter,
                    autofocus: false,
                    liveEditing: true
                )
                Text("grams").foregroundColor(.secondary)
            }
            HStack {
                Text("Protein").foregroundColor(.green)
                Spacer()
                DecimalTextField(
                    "0",
                    value: $state.protein,
                    formatter: Self.formatter,
                    autofocus: false,
                    liveEditing: true
                )
                Text("grams").foregroundColor(.secondary)
            }
        }

        private var otherSummary: some View {
            let hasFiber = state.fiber > 0
            let microCount = state.micronutrient.count

            return Text(summaryText(hasFiber: hasFiber, microCount: microCount))
        }

        private func summaryText(
            hasFiber: Bool,
            microCount: Int
        ) -> String {
            switch (hasFiber, microCount > 0) {
            case (false, false):
                return state.note

            case (true, false):
                return "Fiber"

            case (false, true):
                return "\(microCount) micros"

            case (true, true):
                return "Fiber • \(microCount)"
            }
        }

        @ViewBuilder private func macroRow(
            title: LocalizedStringKey,
            value: Binding<Decimal>,
            color: Color,
            bold: Bool = false
        ) -> some View {
            HStack {
                Text(title)
                    .foregroundStyle(color)
                    .fontWeight(bold ? .semibold : .regular)

                Spacer()

                DecimalTextField(
                    "0",
                    value: value,
                    formatter: Self.formatter,
                    autofocus: false,
                    liveEditing: true
                )

                Text("grams")
                    .foregroundStyle(.secondary)
            }
        }

        // MARK: - Helper Functions

        private var meal: Bool {
            mode == .meal
        }

        private var hasUnsavedFoodSearchResults: Bool {
            foodSearchState.showingFoodSearch && foodSearchState.searchResultsState.nonDeletedItems.isNotEmpty
        }

        // Opens an edit-and-save View
        private func saveAsPreset() {
            foodSearchState.newFoodEntryToEdit = FoodItemDetailed(
                name: "New",
                nutrition: .perServing(
                    values: [
                        .carbs: state.carbs,
                        .protein: state.protein,
                        .fat: state.fat,
                        .fiber: state.fiber
                    ],
                    servingsMultiplier: 1.0
                ),
                micronutrient: state.micronutrient,
                source: .manual
            )

            foodSearchState.showNewSavedFoodEntry = true
            saved.toggle()
        }

        private func handleFoodContinue(_ food: FoodItemDetailed, _: UIImage?, date: Date?) {
            button.toggle()
            guard button else { return }

            state.hypoTreatment = false
            state.addAIFood(override, fetch: editMode, food: food, date: date)
        }

        private func handleOnAppear() {
            syncDismissState()

            state.loadEntries(editMode)
            addMissingFoodIDs()
            updateSavedFoods()

            guard !meal else { return }

            switch mode {
            case .image:
                if state.ai {
                    showFoodSearch(.camera)
                }
            case .barcode:
                showFoodSearch(.barcodeScanner)
            case .presets:
                foodSearchState.showingFoodSearch = true
                foodSearchState.showSavedFoods = true
            default:
                break
            }
        }

        private func syncDismissState() {
            mainState.shouldPreventModalDismiss = shouldPreventDismiss
        }

        private func showFoodSearch(_ route: FoodSearchRoute) {
            foodSearchState.foodSearchRoute = route
            foodSearchState.showingFoodSearch = true
        }

        // Transform Presets to FoodItemDetailed
        private func transformPresetsToFoodItems(_ presets: FetchedResults<Presets>) -> [FoodItemDetailed] {
            presets.compactMap { preset -> FoodItemDetailed? in
                FoodItemDetailed.fromPreset(preset: preset)
            }
        }

        private func addMissingFoodIDs() {
            let noId = carbPresets.filter { $0.foodID == nil }
            if noId.isNotEmpty {
                for preset in noId {
                    preset.foodID = UUID()
                }
                do {
                    try moc.save()
                } catch {
                    print("Couldn't save presets after adding IDs: \(error.localizedDescription)")
                }
            }
        }

        // Update savedFoods when presets change
        private func updateSavedFoods() {
            let foodItems = transformPresetsToFoodItems(carbPresets)
            foodSearchState.savedFoods = FoodItemGroup(
                foodItems: foodItems,
                briefDescription: nil,
                overallDescription: nil,
                diabetesConsiderations: nil,
                source: .database,
                barcode: nil,
                textQuery: nil
            )
        }

        // MARK: - Food Search Section

        private func saveOrUpdatePreset(_ food: FoodItemDetailed) {
            guard food.name.isNotEmpty else { return }

            let existingPreset = carbPresets.first(where: { preset in
                preset.foodID == food.id
            })

            let preset = existingPreset ?? Presets(context: moc)

            food.updatePreset(preset: preset)

            do {
                try moc.save()
                updateSavedFoods()
            } catch {
                print("Couldn't save " + (preset.dish ?? "new preset."))
            }
        }

        private func deletePreset(_ food: FoodItemDetailed) {
            // Find preset by food ID
            if let presetToDelete = carbPresets.first(where: { preset in
                preset.foodID == food.id
            }) {
                moc.delete(presetToDelete)
                do {
                    try moc.save()
                } catch {
                    debug(.apsManager, "Couldn't delete meal preset for food: \(food.name).")
                }
            }
        }

        private var empty: Bool {
            state.carbs <= 0 &&
                state.fat <= 0 &&
                state.protein <= 0 &&
                state.fiber <= 0 &&
                state.micronutrient.allSatisfy { $0.amount <= 0 }
        }

        private var presetView: some View {
            Form {
                Section {} header: { back }

                if !empty {
                    Section {
                        Button {
                            addfromCarbsView()
                        }
                        label: {
                            HStack {
                                Text("Save as Preset")
                                Spacer()
                                Text(
                                    "[Carbs: \(format(state.carbs)), Fat: \(format(state.fat)), Protein: \(format(state.protein))]"
                                )
                            }
                        }.frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color(.systemBlue)).tint(.white)
                    }
                    header: { Text("Save") }
                }

                let filtered = carbPresets.filter { !($0.dish ?? "").isEmpty && ($0.dish ?? "Empty") != "Empty" }
                    .removeDublicates()
                if filtered.count > 4 {
                    Section {
                        TextField("Search", text: $string)
                    } header: { Text("Search") }
                }
                let data = string.isEmpty ? filtered : carbPresets
                    .filter { ($0.dish ?? "").localizedCaseInsensitiveContains(string) }

                Section {
                    ForEach(data, id: \.self) { preset in
                        presetsList(for: preset)
                    }.onDelete(perform: delete)
                } header: {
                    HStack {
                        Text("Saved Food")
                        Button {
                            state.presetToEdit = Presets(context: moc)
                            newPreset = (NSLocalizedString("New", comment: ""), 0, 0, 0, 0, [])
                            state.edit = true
                        } label: { Image(systemName: "plus").font(.system(size: 22)) }
                            .buttonStyle(.borderless).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .sheet(isPresented: $state.edit, content: { editView })
            .environment(\.colorScheme, colorScheme)
        }

        private var back: some View {
            Button { reset() }
            label: { Image(systemName: "chevron.backward").font(.system(size: 22)).padding(5) }
                .foregroundStyle(.primary)
                .buttonBorderShape(.circle)
                .buttonStyle(.borderedProminent)
                .tint(colorScheme == .light ? Color.white.opacity(0.5) : Color(.systemGray5))
                .offset(x: -10)
        }

        @ViewBuilder private func presetsList(for preset: Presets) -> some View {
            let dish = preset.dish ?? ""

            if !preset.hasChanges {
                HStack {
                    VStack(alignment: .leading) {
                        Text(dish)
                        HStack {
                            Text("Carbs")
                            Text("\(preset.carbs ?? 0)")
                            Spacer()
                            Text("Fat")
                            Text("\(preset.fat ?? 0)")
                            Spacer()
                            Text("Protein")
                            Text("\(preset.protein ?? 0)")
                        }.foregroundStyle(.secondary).font(.caption).padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.selection = preset
                        state.addU(state.selection)
                        reset()
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            state.edit = true
                            state.presetToEdit = preset
                            update()
                        } label: {
                            Label("Edit", systemImage: "pencil.line")
                        }
                    }
                }
            }
        }

        private func delete(at offsets: IndexSet) {
            for index in offsets {
                let preset = carbPresets[index]
                moc.delete(preset)
            }
            do {
                try moc.save()
            } catch {
                debug(.apsManager, "Couldn't delete meal preset at \(offsets).")
            }
        }

        private func save() {
            if let preset = state.presetToEdit {
                preset.dish = newPreset.dish
                preset.carbs = newPreset.carbs as NSDecimalNumber
                preset.fat = newPreset.fat as NSDecimalNumber
                preset.protein = newPreset.protein as NSDecimalNumber
                preset.fiber = newPreset.fiber as NSDecimalNumber

                try? preset.replaceMicronutrients(
                    with: newPreset.micronutrient.map {
                        (
                            name: $0.substance.coreDataName,
                            type: $0.substance.coreDataType,
                            unit: $0.substance.unit,
                            amount: $0.amount,
                            per100: false
                        )
                    },
                    context: moc
                )

            } else if !disabled {
                let preset = Presets(context: moc)
                preset.foodID = UUID()
                preset.carbs = newPreset.carbs as NSDecimalNumber
                preset.fat = newPreset.fat as NSDecimalNumber
                preset.protein = newPreset.protein as NSDecimalNumber
                preset.fiber = newPreset.fiber as NSDecimalNumber
                preset.dish = newPreset.dish
                preset.per100 = false

                try? preset.replaceMicronutrients(
                    with: newPreset.micronutrient.map {
                        (
                            name: $0.substance.coreDataName,
                            type: $0.substance.coreDataType,
                            unit: $0.substance.unit,
                            amount: $0.amount,
                            per100: false
                        )
                    },
                    context: moc
                )
            }

            if moc.hasChanges {
                do {
                    try moc.save()
                } catch {
                    debug(.apsManager, "Failed to save \(moc.updatedObjects)")
                }
            }

            state.edit = false
            isPromptPresented.toggle()
        }

        private func update() {
            newPreset.dish = state.presetToEdit?.dish ?? ""
            newPreset.carbs = (state.presetToEdit?.carbs ?? 0) as Decimal
            newPreset.fat = (state.presetToEdit?.fat ?? 0) as Decimal
            newPreset.protein = (state.presetToEdit?.protein ?? 0) as Decimal
            newPreset.fiber = (state.presetToEdit?.fiber ?? 0) as Decimal
            newPreset.micronutrient = state.presetToEdit?.micronutrientValuesTyped() ?? []
        }

        private func addfromCarbsView() {
            newPreset = (
                state.note,
                state.carbs.rounded(to: 1),
                state.fat.rounded(to: 1),
                state.protein.rounded(to: 1),
                state.fiber.rounded(to: 1),
                state.micronutrient
            )

            state.edit = true
        }

        private func reset() {
            presentPresets = false
            string = ""
        }

        private var disabled: Bool {
            let isDefaultName = newPreset.dish == NSLocalizedString("New", comment: "")
            let hasNoMacros = newPreset.carbs + newPreset.fat + newPreset.protein <= 0
            let hasNoMicros = newPreset.micronutrient.isEmpty

            return newPreset.dish.isEmpty || (isDefaultName && hasNoMacros && hasNoMicros)
        }

        /// Determines if the view should prevent interactive dismissal (swipe down)
        private var shouldPreventDismiss: Bool {
            // Prevent dismiss if showing saved foods OR if there are unsaved changes
            if foodSearchState.showSavedFoods {
                return true // Block swipe when saved foods are shown
            } else if hasUnsavedFoodSearchResults {
                return true // Block swipe when there are unsaved food search results
            } else {
                return false // Allow swipe in other cases
            }
        }

        /// Handles the dismiss action from the Cancel/Done button
        private func handleDismissAction() {
            // If showing saved foods, just close them
            if foodSearchState.showSavedFoods {
                withAnimation(.easeInOut(duration: 0.3)) {
                    foodSearchState.showSavedFoods = false
                }
                return
            }

            // If there are unsaved food search results, show confirmation
            if hasUnsavedFoodSearchResults {
                showCancelConfirmation = true
                return
            }

            // Otherwise, just dismiss
            state.hideModal()
            if editMode { state.apsManager.determineBasalSync() }
        }

        private var editView: some View {
            Form {
                Section {
                    HStack {
                        TextField("", text: $newPreset.dish)
                    }
                    HStack {
                        Text("Carbs").foregroundStyle(.secondary)
                        Spacer()
                        DecimalTextField("0", value: $newPreset.carbs, formatter: Self.formatter, liveEditing: true)
                    }
                    HStack {
                        Text("Fat").foregroundStyle(.secondary)
                        Spacer()
                        DecimalTextField("0", value: $newPreset.fat, formatter: Self.formatter, liveEditing: true)
                    }
                    HStack {
                        Text("Protein").foregroundStyle(.secondary)
                        Spacer()
                        DecimalTextField("0", value: $newPreset.protein, formatter: Self.formatter, liveEditing: true)
                    }
                } header: { Text("Saved Food") }

                Section {
                    Button { save() }
                    label: { Text("Save") }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(!disabled ? Color(.systemBlue) : Color(.systemGray4))
                        .tint(.white)
                        .disabled(disabled)
                }
            }.environment(\.colorScheme, colorScheme)
        }
    }

    private struct MicronutrientEntrySheet: View {
        @Binding var values: [MicronutrientValue]

        let formatter: NumberFormatter

        @Environment(\.dismiss) private var dismiss

        @State private var selected = MicroNutrient.allCases.first!
        @State private var amount: Decimal = 0

        private var sortedNutrients: [MicroNutrient] {
            MicroNutrient.allCases.sorted { $0.displayName < $1.displayName }
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Picker("Nutrient", selection: $selected) {
                            ForEach(sortedNutrients, id: \.self) { nutrient in
                                Text(nutrient.displayName)
                                    .tag(nutrient)
                            }
                        }

                        HStack {
                            Text("Amount")
                            Spacer()

                            DecimalTextField(
                                "0",
                                value: $amount,
                                formatter: formatter,
                                autofocus: false,
                                liveEditing: true
                            )

                            Text(selected.unit)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            addOrUpdate()
                        } label: {
                            Text("Add Micronutrient")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(amount <= 0)
                    }

                    if !values.isEmpty {
                        Section("Added") {
                            ForEach(values.sorted { $0.name < $1.name }) { value in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(value.name)
                                        Text(value.substance.coreDataType.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(value.formattedAmount)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onDelete(perform: delete)
                        }
                    }
                }
                .navigationTitle("Micronutrients")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }

        private func addOrUpdate() {
            var dict = Dictionary(
                uniqueKeysWithValues: values.map { ($0.substance, $0) }
            )

            dict[selected] = MicronutrientValue(
                substance: selected,
                amount: amount,
                amountPer100: 0
            )

            values = dict.values
                .filter { $0.amount > 0 || $0.amountPer100 > 0 }
                .sorted { $0.name < $1.name }

            amount = 0
        }

        private func delete(at offsets: IndexSet) {
            let sortedValues = values.sorted { $0.name < $1.name }
            let substancesToDelete = offsets.map { sortedValues[$0].substance }

            values.removeAll { substancesToDelete.contains($0.substance) }
        }
    }
}
