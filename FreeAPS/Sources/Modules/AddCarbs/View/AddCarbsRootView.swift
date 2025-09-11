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

        @StateObject var state = StateModel()
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
        @State private var showAISettings = false
        @State private var showingAICamera = false
        @State private var foodSearchText = ""
        @State private var searchResults: [FoodItem] = []
        @State private var isLoading = false
        @State private var errorMessage: String?
        @State private var showingBarcodeScanner = false

        init(resolver: Resolver, editMode: Bool, override: Bool) {
            self.resolver = resolver
            self.editMode = editMode
            self.override = override
        }

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

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                foodSearchSection

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
                            autofocus: true,
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
            .onAppear {
                configureView {
                    state.loadEntries(editMode)
                }
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                // leading: foodSearchButton,
                trailing: Button("Cancel", action: {
                    state.hideModal()
                    if editMode { state.apsManager.determineBasalSync() }
                })
            )
            .sheet(isPresented: $showingAICamera) {
                AICameraView(
                    onFoodAnalyzed: { _, _ in
                        Task { @MainActor in
                            // TODO: Ergebnis in dein StateModel übertragen
                            showingAICamera = false
                        }
                    },
                    onCancel: { showingAICamera = false }
                )
            }
            .sheet(isPresented: $presentPresets, content: { presetView })
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(
                    state: foodSearchState,
                    onSelect: { selectedFood in
                        handleSelectedFood(selectedFood)
                    }
                )
            }
        }

        // MARK: - Helper Functions

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Fat").foregroundColor(.orange)
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
                Text("Protein").foregroundColor(.red)
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

        private var foodSearchSection: some View {
            Section(header: Text("AI Food Search")) {
                Button {
                    showingFoodSearch = true
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search Food Database")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundColor(.blue)
                }

                NavigationLink(destination: AISettingsView()) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("AI Settings")
                        Spacer()
                    }
                    .foregroundColor(.blue)
                }
                .overlay(
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .semibold)),
                    alignment: .trailing
                )
            }
        }

        private var foodSearchButton: some View {
            Button {
                showingFoodSearch.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
            }
        }

        private func handleSelectedFood(_ food: FoodItem) {
            state.carbs = food.carbs
            state.fat = food.fat
            state.protein = food.protein
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
                Section {} header: {
                    Text("Back").textCase(nil).foregroundStyle(.blue).font(.system(size: 16))
                        .onTapGesture { reset() } }

                if !empty {
                    Section {
                        Button {
                            addfromCarbsView()
                        }
                        label: {
                            HStack {
                                Text("Save as Preset")
                                Spacer()
                                Text("[\(state.carbs), \(state.fat), \(state.protein)]")
                            }
                        }.frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color(.systemBlue)).tint(.white)
                    }
                    header: { Text("Save") }
                }

                let filtered = carbPresets.filter { ($0.dish ?? "").count > 1 }.removeDublicates()
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
                // Error handling
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
                } catch {}
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
            newPreset = (NSLocalizedString("New", comment: ""), state.carbs, state.fat, state.protein)
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

private func searchFoodProducts(query: String) async throws -> [FoodItem] {
    print("🔍 Starting search for: '\(query)'")
    let openFoodProducts = try await FoodSearchRouter.shared.searchFoodsByText(query)

    return openFoodProducts.map { openFoodProduct in
        FoodItem(
            name: openFoodProduct.productName ?? "Unknown",
            carbs: Decimal(openFoodProduct.nutriments.carbohydrates),
            fat: Decimal(openFoodProduct.nutriments.fat ?? 0),
            protein: Decimal(openFoodProduct.nutriments.proteins ?? 0),
            source: openFoodProduct.brands ?? "OpenFoodFacts"
        )
    }
}

private func searchOpenFoodFactsByBarcode(_ barcode: String) async throws -> [FoodItem] {
    let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
    print("🌐 OpenFoodFacts API Call: \(urlString)")

    guard let url = URL(string: urlString) else {
        throw NSError(domain: "OpenFoodFactsError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }

    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "OpenFoodFactsError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }

    guard httpResponse.statusCode == 200 else {
        print("❌ OpenFoodFacts API Error: Status \(httpResponse.statusCode)")
        return [] // Leeres Array für "nicht gefunden"
    }

    // Parse die Response
    let productResponse = try JSONDecoder().decode(OpenFoodFactsProductResponse.self, from: data)

    if productResponse.status == 1, let product = productResponse.product {
        // Produkt gefunden
        let foodItem = FoodItem(
            name: product.productName ?? "Unknown",
            carbs: Decimal(product.nutriments.carbohydrates),
            fat: Decimal(product.nutriments.fat ?? 0),
            protein: Decimal(product.nutriments.proteins ?? 0),
            source: product.brands ?? "OpenFoodFacts"
        )
        return [foodItem]
    } else {
        // Kein Produkt gefunden
        print("ℹ️ OpenFoodFacts: No product found for barcode \(barcode)")
        return []
    }
}

private func searchFoodProducts(query: String, completion: @escaping ([AIFoodItem]) -> Void) async throws -> [FoodItem] {
    do {
        print("🔍 Starting AI search for: '\(query)'")

        // Use the FoodSearchRouter to handle the search
        let openFoodProducts = try await FoodSearchRouter.shared.searchFoodsByText(query)

        print("✅ AI search completed, found \(openFoodProducts.count) products")

        // Konvertiert OpenFoodFactsProduct zu AIFoodItem
        let aiProducts = openFoodProducts.map { openFoodProduct in
            AIFoodItem(
                name: openFoodProduct.productName ?? "Unknown",
                brand: openFoodProduct.brands,
                calories: 0,
                carbs: openFoodProduct.nutriments.carbohydrates,
                protein: openFoodProduct.nutriments.proteins ?? 0,
                fat: openFoodProduct.nutriments.fat ?? 0
            )
        }

        // Rückgabe der AI-Ergebnisse via Completion Handler
        completion(aiProducts)

        // Konvertiere zu FoodItem für Rückgabe
        return openFoodProducts.map { openFoodProduct in
            FoodItem(
                name: openFoodProduct.productName ?? "Unknown",
                carbs: Decimal(openFoodProduct.nutriments.carbohydrates),
                fat: Decimal(openFoodProduct.nutriments.fat ?? 0),
                protein: Decimal(openFoodProduct.nutriments.proteins ?? 0),
                source: openFoodProduct.brands ?? "OpenFoodFacts"
            )
        }
    } catch {
        print("❌ AI Search failed: \(error.localizedDescription)")
        completion([])
        return []
    }
}

// Erweiterung für AIConfidenceLevel
extension AIConfidenceLevel {
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }

    var description: String {
        switch self {
        case .high: return "Hoch"
        case .medium: return "Mittel"
        case .low: return "Niedrig"
        }
    }
}

extension OpenFoodFactsProduct {
    func toFoodItem() -> FoodItem {
        FoodItem(
            name: productName ?? "Unknown",
            carbs: Decimal(nutriments.carbohydrates),
            fat: Decimal(nutriments.fat ?? 0),
            protein: Decimal(nutriments.proteins ?? 0),
            source: brands ?? "OpenFoodFacts"
        )
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
