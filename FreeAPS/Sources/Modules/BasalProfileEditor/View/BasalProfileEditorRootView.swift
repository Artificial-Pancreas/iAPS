import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var editMode = EditMode.inactive
        @Environment(\.dismiss) var dismiss

        @FetchRequest(
            entity: InsulinConcentration.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)]
        ) var concentration: FetchedResults<InsulinConcentration>

        let saveNewConcentration: Bool
        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        @State var set: Decimal = 1
        @State var saving = false
        @State var showAlert = false
        @State var clean = false

        var body: some View {
            Form {
                if !saveNewConcentration {
                    basalProfileView
                } else {
                    concentrationView
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear {
                configureView()
                set = Decimal(concentration.last?.concentration ?? 1)
            }
            .navigationTitle(saveNewConcentration ? "Insulin Concentration" : "Basal Profile")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                trailing: !saveNewConcentration ? EditButton() : nil
            )
            .environment(\.editMode, $editMode)
            .onAppear {
                state.validate()
            }
        }

        private func pickers(for index: Int) -> some View {
            GeometryReader { geometry in
                VStack {
                    HStack {
                        Text("Rate").frame(width: geometry.size.width / 2)
                        Text("Time").frame(width: geometry.size.width / 2)
                    }
                    HStack(spacing: 0) {
                        Picker(selection: $state.items[index].rateIndex, label: EmptyView()) {
                            ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                                Text(
                                    (
                                        self.rateFormatter
                                            .string(from: state.rateValues[i] as NSNumber) ?? ""
                                    ) + " U/hr"
                                ).tag(i)
                            }
                        }
                        .onChange(of: state.items[index].rateIndex) { state.calcTotal() }
                        .frame(maxWidth: geometry.size.width / 2)
                        .clipped()

                        Picker(selection: $state.items[index].timeIndex, label: EmptyView()) {
                            ForEach(0 ..< state.timeValues.count, id: \.self) { i in
                                Text(
                                    self.dateFormatter
                                        .string(from: Date(
                                            timeIntervalSince1970: state
                                                .timeValues[i]
                                        ))
                                ).tag(i)
                            }
                        }
                        .onChange(of: state.items[index].timeIndex) { state.calcTotal() }
                        .frame(maxWidth: geometry.size.width / 2)
                        .clipped()
                    }
                }
            }
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Rate").foregroundColor(.secondary)
                            Text(
                                "\(rateFormatter.string(from: state.rateValues[item.rateIndex] as NSNumber) ?? "0") U/hr"
                            )
                            Spacer()
                            Text("starts at").foregroundColor(.secondary)
                            Text(
                                "\(dateFormatter.string(from: Date(timeIntervalSince1970: state.timeValues[item.timeIndex])))"
                            )
                        }
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        private var addButton: some View {
            guard state.canAdd else {
                return AnyView(EmptyView())
            }

            switch editMode {
            case .inactive:
                return AnyView(Button(action: onAdd) { Text("Add") })
            default:
                return AnyView(EmptyView())
            }
        }

        private var basalProfileView: some View {
            Group {
                Section {
                    list
                    addButton
                } header: {
                    HStack {
                        Text("Schedule")
                        Text("(standard units / hour)")
                    }
                }

                Section {
                    HStack {
                        Text("Total")
                            .bold()
                            .foregroundColor(.primary)
                        Spacer()
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                            .foregroundColor(.primary) +
                            Text(" U/day")
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    HStack {
                        if state.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button { state.save() }
                        label: {
                            Text(state.syncInProgress ? "Saving..." : "Save on Pump")
                        }
                        .disabled(state.syncInProgress || state.items.isEmpty)
                    }
                }
            }
        }

        private var concentrationView: some View {
            Group {
                Section {
                    Text("U " + (rateFormatter.string(from: set * 100 as NSNumber) ?? ""))
                } header: { Text("Insulin Concentration") }

                Section {
                    Picker("Insulin", selection: $set) {
                        Text("U100").tag(Decimal(1))
                        Text("U200").tag(Decimal(2))
                        if state.allowDilution {
                            Text("U50").tag(Decimal(0.5))
                            Text("U10").tag(Decimal(0.1))
                        }
                    }._onBindingChange($set) { _ in
                        clean = true
                    }
                } header: { Text("Change Insulin") }

                footer: {
                    let diluted = NSLocalizedString("Insulin diluted to", comment: "") + " \(set) * " +
                        NSLocalizedString("standard concentration:", comment: "") + " \(set * 100) " +
                        NSLocalizedString("units per ml", comment: "")
                    let standard = NSLocalizedString("Standard concentration (U 100)", comment: "")
                    let concentrated = NSLocalizedString("Insulin concentration increased to", comment: "") + " \(set) * " +
                        NSLocalizedString("standard concentration:", comment: "") + " \(set * 100) " +
                        NSLocalizedString("units per ml", comment: "")
                    Text(set < 1 ? diluted : set == 1 ? standard : concentrated)
                }

                Section {
                    HStack {
                        if state.syncInProgress {
                            ProgressView().padding(.trailing, 10)
                        }
                        Button {
                            showAlert.toggle()
                        }
                        label: {
                            Text(state.syncInProgress ? "Saving..." : "Save on Pump")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(
                            state.syncInProgress || state.items
                                .isEmpty || set <= 0
                        )
                    }
                } footer: {
                    Text(
                        state.syncInProgress ? "" :
                            (saving && !state.saved) ? "Couldn't save to pump. Try again when pump isn't busy bolusing." :
                            (saving && state.saved && !clean) ? "Saved" : ""
                    )
                    .textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle((saving && !state.saved) ? .red : .secondary) }
            }
            .alert(
                Text("Are you sure?"),
                isPresented: $showAlert
            ) {
                Button("No", role: .cancel) {}
                Button("Yes", role: .destructive) {
                    clean = false
                    saving = true
                    save()
                }
            } message: {
                Text("\n" + NSLocalizedString(
                    "Please verify that you have selected the correct insulin concentration before saving your settings.\n\nThe insulin vial or pen should indicate the concentration in units per milliliter (e.g., U100 indicates 100 units per milliliter, which is the standard concentration).\n\nAccurate selection is critical for proper dosing.",
                    comment: "Insulin alert message"
                ))
            }
        }

        func onAdd() {
            state.add()
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
            state.calcTotal()
        }

        private func save() {
            coredataContext.perform { [self] in
                let newConfiguration = InsulinConcentration(context: self.coredataContext)
                newConfiguration.concentration = Double(set)
                newConfiguration.incrementSetting = Double(state.settingsManager.preferences.bolusIncrement)
                newConfiguration.date = Date.now
                do { try self.coredataContext.save()
                } catch {
                    debug(.apsManager, "Insulin Concentration setting couldn't be saved to CoreData. Error: " + "\(error)")
                }
                self.state.save()
            }
        }
    }
}
