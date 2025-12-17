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
        @State private var showingFoodSearch = false
        @State private var foodSearchText = ""
        @State private var searchResults: [FoodItem] = []
        @State private var isLoading = false
        @State private var errorMessage: String?
        @State private var selectedFoodItem: AIFoodItem?
        @State private var portionGrams: Double = 100.00001
        @State private var selectedFoodImage: UIImage?
        @State private var saveAlert = false

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
            if meal {
                normalMealView
            } else {
                shortcuts()
            }
        }

        private var mealView: some View {
            Form {
                // AI Food Search
                state.ai ? foodSearch : nil

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
            .compactSectionSpacing()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel", action: {
                state.hideModal()
                if editMode { state.apsManager.determineBasalSync() }
            }))
            .sheet(isPresented: $presentPresets, content: { presetView })
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(
                    state: foodSearchState,
                    onSelect: { selectedFood, image in
                        handleSelectedFood(selectedFood, image: image)
                    }
                )
            }
            .alert(isPresented: $saveAlert) { alert(food: selectedFoodItem) }
        }

        private var meal: Bool {
            mode == .meal || foodSearchState.mealView
        }

        @ViewBuilder private func shortcuts() -> some View {
            switch mode {
            case .image:
                imageView
            case .barcode:
                barcodeView
            case .presets:
                mealPresetsView
            case .search:
                foodsearchView
            default:
                normalMealView
            }
        }

        private var normalMealView: some View {
            mealView.onAppear {
                state.loadEntries(editMode)
            }
        }

        private var imageView: some View {
            mealView.onAppear {
                state.loadEntries(editMode)
                showingFoodSearch.toggle()
                foodSearchState.navigateToAICamera = true
            }
        }

        private var barcodeView: some View {
            mealView.onAppear {
                state.loadEntries(editMode)
                showingFoodSearch.toggle()
                foodSearchState.navigateToBarcode.toggle()
            }
        }

        private var mealPresetsView: some View {
            mealView.onAppear {
                state.loadEntries(editMode)
                presentPresets.toggle()
            }
        }

        private var foodsearchView: some View {
            mealView.onAppear {
                state.loadEntries(editMode)
                showingFoodSearch.toggle()
            }
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

        // MARK: - Food Search Section

        private var foodSearch: some View {
            Group {
                foodSearchSection

                if let selectedFood = selectedFoodItem {
                    SelectedFoodView(
                        food: selectedFood,
                        foodImage: selectedFoodImage,
                        portionGrams: $portionGrams,
                        onChange: {
                            selectedFoodItem = nil
                            selectedFoodImage = nil
                            showingFoodSearch = true
                        },
                        onTakeOver: { food in
                            state.carbs += portionGrams != 100.00001 ? Decimal(max(food.carbs, 0) / (portionGrams / 100))
                                .rounded(to: 0) : Decimal(max(food.carbs, 0))
                            state.fat += portionGrams != 100.00001 ? Decimal(max(food.fat, 0) / (portionGrams / 100))
                                .rounded(to: 0) : Decimal(max(food.fat, 0))
                            state.protein += portionGrams != 100.00001 ? Decimal(max(food.protein, 0) / (portionGrams / 100))
                                .rounded(to: 0) : Decimal(max(food.protein, 0))
                            selectedFoodImage = nil
                            showingFoodSearch = false
                            if !state.skipSave {
                                saveAlert.toggle()
                            } else {
                                cache(food: selectedFood)
                            }
                        }
                    )
                }
            }
        }

        private var foodSearchSection: some View {
            Section {
                // Search in Food Database
                Button {
                    showingFoodSearch = true
                } label: {
                    HStack {
                        Image(systemName: "network")
                        Text("Search Food Database")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.popUpGray)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            // Settings
            header: {
                HStack {
                    Text("AI Food Search")
                    Spacer()
                    NavigationLink(destination: AISettingsView()) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.blue)
                }
            }
        }

        // Temporarily saved in waiter's notepad (the summary).
        private func cache(food: AIFoodItem) {
            let cache = Presets(context: moc)
            cache.carbs = Decimal(food.carbs) as NSDecimalNumber
            cache.fat = Decimal(food.fat) as NSDecimalNumber
            cache.protein = Decimal(food.protein) as NSDecimalNumber
            cache.dish = (portionGrams != 100.00001) ? food.name + " \(portionGrams)g" : food.name

            if state.selection?.dish != cache.dish {
                state.selection = cache
                state.combinedPresets.append((state.selection, 1))
            } else if state.combinedPresets.last != nil {
                state.combinedPresets[state.combinedPresets.endIndex - 1].portions += 1
            }
        }

        private func addToPresetsIfNew(food: AIFoodItem) {
            let preset = Presets(context: moc)
            preset
                .carbs = (portionGrams != 100.0 || portionGrams != 100.00001) ?
                (Decimal(max(food.carbs * (portionGrams / 100), 0)).rounded(to: 1) as NSDecimalNumber) :
                Decimal(max(food.carbs, 0)) as NSDecimalNumber
            preset
                .fat = (portionGrams != 100.0 || portionGrams != 100.00001) ?
                (Decimal(max(food.fat * (portionGrams / 100), 0)).rounded(to: 1) as NSDecimalNumber) :
                Decimal(max(food.fat, 0)) as NSDecimalNumber
            preset
                .protein = (portionGrams != 100.0 || portionGrams != 100.00001) ?
                (Decimal(max(food.protein * (portionGrams / 100), 0)).rounded(to: 1) as NSDecimalNumber) :
                Decimal(max(food.protein, 0)) as NSDecimalNumber

            if portionGrams != 100.00001 {
                preset.dish = food.name + " \(portionGrams)g"
            } else {
                preset.dish = food.name
            }

            if moc.hasChanges, !carbPresets.compactMap(\.dish).contains(preset.dish), !food.name.isEmpty {
                do {
                    try moc.save()
                    state.selection = preset
                    state.addPresetToNewMeal()
                    selectedFoodItem = nil
                } catch { print("Couldn't save " + (preset.dish ?? "new preset.")) }
            }
        }

        private func isAIAnalysisProduct(_ food: AIFoodItem) -> Bool {
            food.brand == "AI Analysis" || food.brand == nil || food.brand?.contains("AI") == true
        }

        private func handleSelectedFood(_ foodItem: FoodItem) {
            let calculatedCalories = Double(truncating: foodItem.carbs as NSNumber) * 4 +
                Double(truncating: foodItem.protein as NSNumber) * 4 +
                Double(truncating: foodItem.fat as NSNumber) * 9

            let aiFoodItem = AIFoodItem(
                name: foodItem.name,
                brand: foodItem.source,
                calories: calculatedCalories,
                carbs: Double(truncating: foodItem.carbs as NSNumber),
                protein: Double(truncating: foodItem.protein as NSNumber),
                fat: Double(truncating: foodItem.fat as NSNumber),
                imageURL: foodItem.imageURL
            )
            selectedFoodItem = aiFoodItem

            // Gramm zurücksetzen (100g für normale Produkte)
            portionGrams = 100.00001

            showingFoodSearch = false
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

        private func alert(food: AIFoodItem?) -> Alert {
            if let food = food {
                return Alert(
                    title: Text(
                        NSLocalizedString("Save", comment: "") + "\"" + food
                            .name + "\"" + NSLocalizedString("as new Meal Preset?", comment: "")
                    ),
                    message: Text("To avoid having to search for same food on web again."),
                    primaryButton: .destructive(Text("Yes"), action: { addToPresetsIfNew(food: food) }),
                    secondaryButton: .cancel(Text("No"), action: { cache(food: food) })
                )
            }

            return Alert(
                title: Text("Oops!"),
                message: Text(
                    NSLocalizedString("Something isnt't working with food item ", comment: "") + "\"" +
                        (food?.name ?? "nil")
                ),
                primaryButton: .cancel(Text("OK")),
                secondaryButton: .cancel()
            )
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

        private func handleSelectedFood(_ foodItem: FoodItem, image: UIImage? = nil) {
            let aiFoodItem = foodItem.toAIFoodItem()
            selectedFoodItem = aiFoodItem
            selectedFoodImage = image
            portionGrams = 100.0
            showingFoodSearch = false
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
