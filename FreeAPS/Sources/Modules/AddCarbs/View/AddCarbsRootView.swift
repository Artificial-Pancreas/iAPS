import CoreData
import SwiftUI
import Swinject

extension AddCarbs {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State var dish: String = ""
        @State var isPromtPresented = false
        @State var saved = false
        @State private var showAlert = false

        @FetchRequest(
            entity: Presets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "dish", ascending: true)]
        ) var carbPresets: FetchedResults<Presets>

        @Environment(\.managedObjectContext) var moc

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                if let carbsReq = state.carbsRequired {
                    Section {
                        HStack {
                            Text("Carbs required")
                            Spacer()
                            Text(formatter.string(from: carbsReq as NSNumber)! + " g")
                        }
                    }
                }
                Section {
                    Section {
                        HStack {
                            Text("Carbs").fontWeight(.semibold)
                            Spacer()
                            DecimalTextField("0", value: $state.carbs, formatter: formatter, autofocus: true, cleanInput: true)
                            Text("grams").foregroundColor(.secondary)
                        }.padding(.vertical)

                        if state.useFPU { proteinAndFat() }
                        DatePicker("Date", selection: $state.date)
                    }
                }
                Section {
                    Button { state.add() }
                    label: { Text("Save and continue") }
                        .disabled(state.carbs <= 0 && state.fat <= 0 && state.protein <= 0)
                }

                if state.useFPU {
                    mealPresets
                }
            }
            .onAppear(perform: configureView)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
        }

        var presetPopover: some View {
            Form {
                Section(header: Text("Enter Meal Preset Name")) {
                    TextField("Name Of Dish", text: $dish)
                    Button {
                        saved = true
                        if dish != "", saved {
                            let preset = Presets(context: moc)
                            preset.dish = dish
                            preset.fat = state.fat as NSDecimalNumber
                            preset.protein = state.protein as NSDecimalNumber
                            preset.carbs = state.carbs as NSDecimalNumber
                            try? moc.save()
                            state.selection = preset
                            saved = false
                            isPromtPresented = false
                        }
                    }
                    label: { Text("Save") }
                    Button {
                        dish = ""
                        saved = false
                        isPromtPresented = false }
                    label: { Text("Cancel") }
                }
            }
        }

        var mealPresets: some View {
            Section {
                VStack {
                    Picker("Meal Presets", selection: $state.selection) {
                        Text("Empty").tag(nil as Presets?)
                        ForEach(carbPresets, id: \.self) { (preset: Presets) in
                            Text(preset.dish ?? "").tag(preset as Presets?)
                        }
                    }
                    .pickerStyle(.automatic)
                    ._onBindingChange($state.selection) { _ in
                        state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                        state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                        state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal
                    }
                }
                HStack {
                    Button("Delete Preset") {
                        showAlert.toggle()
                    }
                    .disabled(state.selection == nil)
                    .accentColor(.orange)
                    .buttonStyle(BorderlessButtonStyle())
                    .alert(
                        "Delete preset '\(state.selection?.dish ?? "")'?",
                        isPresented: $showAlert,
                        actions: {
                            Button("No", role: .cancel) {}
                            Button("Yes", role: .destructive) {
                                state.deletePreset()
                            }
                        }
                    )
                    Button {
                        if state.carbs != 0 { state.carbs -= ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal }
                        if state.fat != 0 { state.fat -= ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal }
                        if state.protein != 0 { state.protein -= ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal }
                    }
                    label: { Text("[ -1 ]") }
                        .disabled(state.selection == nil || (
                            (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal) == state
                                .carbs && (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal) == state
                                .fat && (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal) == state
                                .protein
                        ))
                        .buttonStyle(BorderlessButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accentColor(.minus)
                    Button {
                        state.carbs += ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                        state.fat += ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                        state.protein += ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal }
                    label: { Text("[ +1 ]") }
                        .disabled(state.selection == nil)
                        .buttonStyle(BorderlessButtonStyle())
                        .accentColor(.blue)
                }
            }
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Protein").foregroundColor(.red) // .fontWeight(.thin)
                Spacer()
                DecimalTextField(
                    "0",
                    value: $state.protein,
                    formatter: formatter,
                    autofocus: false,
                    cleanInput: true
                ).foregroundColor(.loopRed)

                Text("grams").foregroundColor(.secondary)
            }
            HStack {
                Text("Fat").foregroundColor(.orange) // .fontWeight(.thin)
                Spacer()
                DecimalTextField(
                    "0",
                    value: $state.fat,
                    formatter: formatter,
                    autofocus: false,
                    cleanInput: true
                )
                Text("grams").foregroundColor(.secondary)
            }
            HStack {
                Button {
                    isPromtPresented = true
                }
                label: { Text("Save as Preset") }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(
                (state.carbs <= 0 && state.fat <= 0 && state.protein <= 0) ||
                    (
                        (((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal) == state
                            .carbs && (((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal) == state
                            .fat && (((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal) == state
                            .protein
                    )
            )
            .popover(isPresented: $isPromtPresented) {
                presetPopover
            }
        }
    }
}
