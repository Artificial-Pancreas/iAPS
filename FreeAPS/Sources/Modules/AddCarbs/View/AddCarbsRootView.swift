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
        @State private var newPreset: (dish: String, carbs: Decimal, fat: Decimal, protein: Decimal) = ("", 0, 0, 0)
        // Food Search States
        @State private var foodSearchText = ""
        @State private var isLoading = false
        @State private var errorMessage: String?
        @State private var portionGrams: Decimal = 100.00001
        @State private var selectedFoodImage: UIImage?
        @State private var showCancelConfirmation = false

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

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            VStack(spacing: 0) {
                FoodSearchView.SearchBar(state: foodSearchState).padding(.horizontal)

                if foodSearchState.showingFoodSearch {
                    FoodSearchView(
                        state: foodSearchState,
                        onContinue: { selectedFood, _, date in
                            button.toggle()
                            if button {
                                state.hypoTreatment = false
                                state.addAIFood(override, fetch: editMode, food: selectedFood, date: date)
                            }
                        },
                        onHypoTreatment: state.id != nil && state.id != "None" && state
                            .carbsRequired != nil ? { selectedFood, _, date in
                                button.toggle()
                                if button {
                                    state.hypoTreatment = true
                                    state.addAIFood(override, fetch: editMode, food: selectedFood, date: date)
                                }
                            } : nil,
                        onPersist: { food in
                            saveOrUpdatePreset(food)
                        },
                        onDelete: { food in
                            deletePreset(food)
                        },
                        continueButtonLabelKey: (state.skipBolus && !override && !editMode) ? "Save" : "Continue",
                        hypoTreatmentButtonLabelKey: "Hypo Treatment"
                    )
                } else {
                    mealView
                }
            }
            .compactSectionSpacing()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading:
                NavigationLink(destination: FoodSearchSettingsView()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(PlainButtonStyle())
            )
            .navigationBarItems(trailing: Button("Cancel", action: {
                if hasUnsavedFoodSearchResults {
                    showCancelConfirmation = true
                } else {
                    state.hideModal()
                    if editMode { state.apsManager.determineBasalSync() }
                }
            }))
            .confirmationDialog(
                "Discard Food Search?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    state.hideModal()
                    if editMode { state.apsManager.determineBasalSync() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have an unsaved food item. Are you sure you want to discard it?")
            }
            .onAppear {
                state.loadEntries(editMode)
                addMissingFoodIDs()
                updateSavedFoods() // Initialize savedFoods on appear
                if !meal {
                    switch mode {
                    case .image:
                        foodSearchState.foodSearchRoute = .camera
                        foodSearchState.showingFoodSearch = true
                    case .barcode:
                        foodSearchState.foodSearchRoute = .barcodeScanner
                        foodSearchState.showingFoodSearch = true
                    case .presets:
                        presentPresets.toggle()
                    case .search:
                        foodSearchState.showingFoodSearch = true
                    default:
                        break
                    }
                }
            }
            .onChange(of: carbPresets.count) {
                updateSavedFoods()
            }
        }

        private var mealView: some View {
            Form {
                if let carbsReq = state.carbsRequired, state.carbs < carbsReq {
                    Section {
                        HStack {
                            Text("Carbs required")
                            Spacer()
                            Text((formatter.string(from: carbsReq as NSNumber) ?? "") + " g")
                        }
                    }
                }

                Section {
                    // Saved Food presets
                    mealPresets.padding(.vertical, 9)

                    HStack {
                        Text("Carbs").fontWeight(.semibold)
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.carbs,
                            formatter: formatter,
                            autofocus: false,
                            liveEditing: true
                        )
                        Text("grams").foregroundColor(.secondary)
                    }

                    if state.useFPUconversion {
                        proteinAndFat()
                    }

                    // Summary when combining presets
                    if state.combinedPresets.isNotEmpty {
                        let summary = state.waitersNotepad()
                        if summary.isNotEmpty {
                            HStack {
                                Text("Total")
                                HStack(spacing: 0) {
                                    ForEach(summary, id: \.self) {
                                        Text($0).foregroundStyle(Color.randomGreen()).font(.footnote)
                                        Text($0 == summary[summary.count - 1] ? "" : ", ")
                                    }
                                }.frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }

                    // Time
                    HStack {
                        Text("Time")
                        Spacer()
                        if !pushed {
                            Button {
                                pushed = true
                            } label: { Text("Now") }.buttonStyle(.borderless).foregroundColor(.secondary).padding(.trailing, 5)
                        } else {
                            Button { state.date = state.date.addingTimeInterval(-15.minutes.timeInterval) }
                            label: { Image(systemName: "minus.circle") }.tint(.blue).buttonStyle(.borderless)
                            DatePicker(
                                "Time",
                                selection: $state.date,
                                displayedComponents: [.hourAndMinute]
                            ).controlSize(.mini)
                                .labelsHidden()
                            Button {
                                state.date = state.date.addingTimeInterval(15.minutes.timeInterval)
                            }
                            label: { Image(systemName: "plus.circle") }.tint(.blue).buttonStyle(.borderless)
                        }
                    }
                }
                // Optional Hypo Treatment
                if state.carbs > 0, let profile = state.id, profile != "None", state.carbsRequired != nil {
                    Section {
                        Button {
                            state.hypoTreatment = true
                            button.toggle()
                            if button { state.add(override, fetch: editMode) }
                        }
                        label: {
                            Text("Hypo Treatment")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }.listRowBackground(Color(.orange).opacity(0.9)).tint(.white)
                }

                Section {
                    Button {
                        button.toggle()
                        if button { state.add(override, fetch: editMode) }
                    }
                    label: {
                        Text(
                            ((state.skipBolus && !override && !editMode) || state.carbs <= 0) ? "Save" :
                                "Continue"
                        ) }
                        .disabled(empty)
                        .frame(maxWidth: .infinity, alignment: .center)
                }.listRowBackground(!empty ? Color(.systemBlue) : Color(.systemGray4))
                    .tint(.white)
            }
            .sheet(isPresented: $presentPresets, content: { presetView })
        }

        private var meal: Bool {
            mode == .meal || foodSearchState.mealView
        }

        private var hasUnsavedFoodSearchResults: Bool {
            foodSearchState.showingFoodSearch && foodSearchState.searchResultsState.nonDeletedItems.isNotEmpty
        }

        // MARK: - Helper Functions

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Fat").foregroundColor(.blue)
                Spacer()
                DecimalTextField(
                    "0",
                    value: $state.fat,
                    formatter: formatter,
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
                    formatter: formatter,
                    autofocus: false,
                    liveEditing: true
                )
                Text("grams").foregroundColor(.secondary)
            }
        }

        // Transform Presets to FoodItemDetailed
        private func transformPresetsToFoodItems(_ presets: FetchedResults<Presets>) -> [FoodItemDetailed] {
            presets.compactMap { preset -> FoodItemDetailed? in
                guard let foodName = preset.dish, !foodName.isEmpty, foodName != "Empty" else {
                    return nil
                }
                guard let foodID = preset.foodID else {
                    return nil
                }
                let mealUnits = preset.mealUnits.map { MealUnits(rawValue: $0) ?? .grams } ?? .grams
                let nutritionPer100 = preset.per100

                let carbs = (preset.carbs as Decimal?) ?? 0
                let fat = (preset.fat as Decimal?) ?? 0
                let protein = (preset.protein as Decimal?) ?? 0

                let nutritionValues = NutritionValues(
                    calories: preset.calories as Decimal?,
                    carbs: carbs,
                    fat: fat,
                    fiber: preset.fiber as Decimal?,
                    protein: protein,
                    sugars: preset.sugars as Decimal?
                )

                if nutritionPer100 {
                    return FoodItemDetailed(
                        id: foodID,
                        name: foodName,
                        nutritionPer100: nutritionValues,
                        portionSize: (preset.portionSize as Decimal?) ?? 100,
                        standardServing: preset.standardServing,
                        standardServingSize: preset.standardServingSize as Decimal?,
                        units: mealUnits,
                        glycemicIndex: preset.glycemicIndex as Decimal?,
                        imageURL: preset.imageURL,
                        standardName: preset.standardName,
                        source: .database
                    )
                } else {
                    return FoodItemDetailed(
                        id: foodID,
                        name: foodName,
                        nutritionPerServing: nutritionValues,
                        servingsMultiplier: 1,
                        standardServing: preset.standardServing,
                        standardServingSize: preset.standardServingSize as Decimal?,
                        units: mealUnits,
                        glycemicIndex: preset.glycemicIndex as Decimal?,
                        imageURL: preset.imageURL,
                        standardName: preset.standardName,
                        source: .database
                    )
                }
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
                foodItemsDetailed: foodItems,
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

            preset.foodID = food.id
            let foodNutrition: NutritionValues
            switch food.nutrition {
            case let .perServing(nutrition):
                foodNutrition = nutrition
                preset.per100 = false
            case let .per100(nutrition):
                foodNutrition = nutrition
                preset.per100 = true
            }

            preset.portionSize = food.portionSize.map { NSDecimalNumber(decimal: max($0, 0)) }

            preset.carbs = foodNutrition.carbs.map { NSDecimalNumber(decimal: max($0, 0)) }
            preset.fat = foodNutrition.fat.map { NSDecimalNumber(decimal: max($0, 0)) }
            preset.protein = foodNutrition.protein.map { NSDecimalNumber(decimal: max($0, 0)) }
            preset.fiber = foodNutrition.fiber.map { NSDecimalNumber(decimal: max($0, 0)) }
            preset.sugars = foodNutrition.sugars.map { NSDecimalNumber(decimal: max($0, 0)) }
            preset.calories = foodNutrition.calories.map { NSDecimalNumber(decimal: max($0, 0)) }

            preset.glycemicIndex = food.glycemicIndex.map { NSDecimalNumber(decimal: $0) }
            preset.standardServing = food.standardServing
            preset.standardServingSize = food.standardServingSize.map { NSDecimalNumber(decimal: $0) }
            preset.imageURL = food.imageURL
            preset.mealUnits = (food.units ?? .grams).rawValue

            preset.standardName = food.standardName

            preset.dish = food.name

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
            state.carbs <= 0 && state.fat <= 0 && state.protein <= 0
        }

        private var mealPresets: some View {
            Section {
                HStack {
                    if state.selection == nil {
                        Button { presentPresets.toggle() }
                        label: {
                            HStack {
                                Text(state.selection?.dish ?? NSLocalizedString("Saved Food", comment: ""))
                                Text(">")
                            }
                        }.foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        minusButton
                        Spacer()

                        Button { presentPresets.toggle() }
                        label: {
                            HStack {
                                Text(state.selection?.dish ?? NSLocalizedString("Saved Food", comment: ""))
                                Text(">")
                            }
                        }.foregroundStyle(.secondary)
                        Spacer()
                        plusButton
                    }
                }
            }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }

        private var minusButton: some View {
            Button {
                state.subtract()
                if empty {
                    state.selection = nil
                    state.combinedPresets = []
                }
            }
            label: { Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(state.selection == nil)
        }

        private var plusButton: some View {
            Button {
                state.plus()
            }
            label: { Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(state.selection == nil)
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
                                    "[Carbs: " + (formatter.string(from: state.carbs as NSNumber) ?? "") + ", Fat: " +
                                        (formatter.string(from: state.fat as NSNumber) ?? "") + ", Protein: " +
                                        (formatter.string(from: state.protein as NSNumber) ?? "") + "]"
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
                            newPreset = (NSLocalizedString("New", comment: ""), 0, 0, 0)
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
            } else if !disabled {
                let preset = Presets(context: moc)
                preset.carbs = newPreset.carbs as NSDecimalNumber
                preset.fat = newPreset.fat as NSDecimalNumber
                preset.protein = newPreset.protein as NSDecimalNumber
                preset.dish = newPreset.dish
            }

            if moc.hasChanges {
                do {
                    try moc.save()
                } catch { debug(.apsManager, "Failed to save \(moc.updatedObjects)") }
            }
            state.edit = false
        }

        private func update() {
            newPreset.dish = state.presetToEdit?.dish ?? ""
            newPreset.carbs = (state.presetToEdit?.carbs ?? 0) as Decimal
            newPreset.fat = (state.presetToEdit?.fat ?? 0) as Decimal
            newPreset.protein = (state.presetToEdit?.protein ?? 0) as Decimal
        }

        private func addfromCarbsView() {
            newPreset = (
                NSLocalizedString("New", comment: ""),
                state.carbs.rounded(to: 1),
                state.fat.rounded(to: 1),
                state.protein.rounded(to: 1)
            )
            state.edit = true
        }

        private func reset() {
            presentPresets = false
            string = ""
        }

        private var disabled: Bool {
            (newPreset == (NSLocalizedString("New", comment: ""), 0, 0, 0)) || (newPreset.dish == "") ||
                (newPreset.carbs + newPreset.fat + newPreset.protein <= 0)
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
                        DecimalTextField("0", value: $newPreset.carbs, formatter: formatter, liveEditing: true)
                    }
                    HStack {
                        Text("Fat").foregroundStyle(.secondary)
                        Spacer()
                        DecimalTextField("0", value: $newPreset.fat, formatter: formatter, liveEditing: true)
                    }
                    HStack {
                        Text("Protein").foregroundStyle(.secondary)
                        Spacer()
                        DecimalTextField("0", value: $newPreset.protein, formatter: formatter, liveEditing: true)
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
}

public extension Color {
    static func randomGreen(randomOpacity: Bool = false) -> Color {
        Color(
            red: .random(in: 0 ... 1),
            green: .random(in: 0.4 ... 0.7),
            blue: .random(in: 0.2 ... 1),
            opacity: randomOpacity ? .random(in: 0.8 ... 1) : 1
        )
    }
}
