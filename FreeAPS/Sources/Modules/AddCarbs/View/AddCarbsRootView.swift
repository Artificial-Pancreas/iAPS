import CoreData
import SwiftUI
import Swinject

extension AddCarbs {
    struct RootView: BaseView {
        let resolver: Resolver
        let editMode: Bool
        let override: Bool
        @StateObject var state = StateModel()
        @State var dish: String = ""
        @State var isPromptPresented = false
        @State var saved = false
        @State var pushed = false
        @State var button = false
        @State private var showAlert = false
        @State private var presentPresets = false
        @State private var string = ""

        @FetchRequest(
            entity: Presets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "dish", ascending: true)]
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
                    !carbPresets.isEmpty ? mealPresets : nil

                    HStack {
                        Text("Carbs").fontWeight(.semibold)
                        Spacer()
                        DecimalTextField(
                            "0",
                            value: $state.carbs,
                            formatter: formatter,
                            autofocus: true,
                            cleanInput: true
                        )
                        Text("grams").foregroundColor(.secondary)
                    }

                    if state.useFPUconversion {
                        proteinAndFat()
                    }

                    /*
                     if !empty {
                         Button { isPromptPresented = true }
                         label: { Text("Save as Preset") }
                             .buttonStyle(.borderless)
                     }*/

                    // Summary when combining presets
                    if state.selection != nil {
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
                    .popover(isPresented: $isPromptPresented) {
                        presetPopover
                    }
                }

                // Optional Hypo Treatment
                if state.carbs > 0, let profile = state.id, profile != "None", let carbsReq = state.carbsRequired {
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
            .navigationBarItems(trailing: Button("Cancel", action: state.hideModal))
            .sheet(isPresented: $presentPresets, content: {
                presetView
            })
        }

        private var presetPopover: some View {
            Form {
                Section {
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
                            if state.combinedPresets.isEmpty {
                                state.addPresetToNewMeal()
                            }

                            saved = false
                            isPromptPresented = false
                        }
                    }
                    label: { Text("Save") }
                    Button {
                        dish = ""
                        saved = false
                        isPromptPresented = false }
                    label: { Text("Cancel") }
                } header: { Text("Enter Meal Preset Name") }
            }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
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

        private var presetView: some View {
            Form {
                Section {} header: {
                    Text("Back").textCase(nil).foregroundStyle(.blue).font(.system(size: 16))
                        .onTapGesture { reset() } }

                if !empty {
                    Section {
                        Button {
                            isPromptPresented = true
                        }
                        label: {
                            Text("Save as Preset")
                        }.frame(maxWidth: .infinity, alignment: .center)
                    }
                    header: { Text("Save") }
                    footer: {
                        Text("[\(state.carbs), \(state.fat), \(state.protein)]").frame(maxWidth: .infinity, alignment: .center) }
                        .listRowBackground(Color(.systemBlue)).tint(.white)
                }

                if carbPresets.count > 4 {
                    Section {
                        TextField("Search", text: $string)
                    } header: { Text("Search") }
                }
                let data = string.isEmpty ? carbPresets
                    .filter { _ in true } : carbPresets
                    .filter { ($0.dish ?? "").localizedCaseInsensitiveContains(string) }

                Section {
                    ForEach(data, id: \.self) { preset in
                        presetsList(for: preset)
                    }.onDelete(perform: delete)
                } header: { Text("Saved Food") }
            }
        }

        private func reset() {
            presentPresets = false
            string = ""
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                Text("Fat").foregroundColor(.orange)
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
                Text("Protein").foregroundColor(.red)
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
        }

        private var minusButton: some View {
            Button {
                state.subtract()

                if empty {
                    state.selection = nil
                    state.combinedPresets = []
                }
            }
            label: { Image(systemName: "minus.circle") }
                .disabled(state.selection == nil)
                .buttonStyle(.borderless)
                .tint(.blue)
        }

        private var plusButton: some View {
            Button {
                state.plus()
            }
            label: { Image(systemName: "plus.circle") }
                .disabled(state.selection == nil)
                .buttonStyle(.borderless)
                .tint(.blue)
        }

        private func delete(at offsets: IndexSet) {
            for index in offsets {
                let preset = carbPresets[index]
                moc.delete(preset)
            }
            do {
                try moc.save()
            } catch {
                // To do: add error
            }
        }

        @ViewBuilder private func presetsList(for preset: Presets) -> some View {
            let dish = preset.dish ?? ""

            if dish != "" {
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
                }
            }
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
