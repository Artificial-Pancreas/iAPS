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

                        if state.useFPU {
                            HStack {
                                Text("Protein").foregroundColor(.loopRed).fontWeight(.thin)
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
                                Text("Fat").foregroundColor(.loopYellow).fontWeight(.thin)
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
                            .disabled(state.carbs <= 0 && state.fat <= 0 && state.protein <= 0)
                            .popover(isPresented: $isPromtPresented) {
                                presetPopover
                            }
                        }
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
                        state.carbs = ((state.selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                        state.fat = ((state.selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                        state.protein = ((state.selection?.protein ?? 0) as NSDecimalNumber) as Decimal
                    }
                }
                Button {
                    state.deletePreset()
                }
                label: { Text("Delete Selected Preset") }
                    .disabled(state.selection == nil)
            }
        }
    }
}
