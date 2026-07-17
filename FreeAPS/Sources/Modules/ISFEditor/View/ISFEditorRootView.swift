import SwiftUI
import Swinject

extension ISFEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        @State private var editMode = EditMode.inactive

        @Environment(AppUIState.self) private var appUIState

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }()

        private static let rateFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            Form {
                if let autotune = state.autotune, let createdAt = autotune.createdAt, !appUIState.settings.onlyAutotuneBasals {
                    Section {
                        HStack {
                            Text("Calculated Sensitivity")
                            Spacer()
                            if state.units == .mmolL {
                                Text(Self.rateFormatter.string(from: autotune.sensitivity.asMmolL as NSNumber) ?? "0")
                            } else {
                                Text(Self.rateFormatter.string(from: autotune.sensitivity as NSNumber) ?? "0")
                            }
                            Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                        }
                    }
                    header: {
                        Text("Autotune")
                    }
                    footer: {
                        Text(Self.dateFormatter.string(from: createdAt))
                    }
                }
                if let sensitivityRatio = appUIState.suggestion?.sensitivityRatio, let isf = appUIState.suggestion?.isf {
                    Section(
                        header: !appUIState.preferences.useNewFormula ? Text("Autosens") : Text("Dynamic Sensitivity")
                    ) {
//                        let ratio = state.suggestion?.sensitivityRatio ?? 0
//                        let isf = state.sensitivity
                        HStack {
                            Text("Sensitivity Ratio")
                            Spacer()
                            Text(
                                Self.rateFormatter.string(from: sensitivityRatio as NSNumber) ?? "1"
                            )
                        }
                        HStack {
                            Text("Calculated Sensitivity")
                            Spacer()
                            Text(
                                Self.rateFormatter.string(from: isf as NSNumber) ?? ""
                            )
                            Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                        }
                    }
                }
                Section(header: Text("Schedule")) {
                    list
                    addButton
                }
                Section {
                    Button {
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.impactOccurred()
                        state.save()
                    }
                    label: {
                        Text("Save")
                    }
                    .disabled(state.items.isEmpty)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Insulin Sensitivities")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                trailing: EditButton()
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
                                        Self.rateFormatter
                                            .string(from: state.rateValues[i] as NSNumber) ?? ""
                                    ) + " \(state.units.rawValue)/U"
                                ).tag(i)
                            }
                        }
                        .frame(maxWidth: geometry.size.width / 2)
                        .clipped()

                        Picker(selection: $state.items[index].timeIndex, label: EmptyView()) {
                            ForEach(0 ..< state.timeValues.count, id: \.self) { i in
                                Text(
                                    Self.dateFormatter
                                        .string(from: Date(
                                            timeIntervalSince1970: state
                                                .timeValues[i]
                                        ))
                                ).tag(i)
                            }
                        }
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
                                "\(Self.rateFormatter.string(from: state.rateValues[item.rateIndex] as NSNumber) ?? "0") \(state.units.rawValue)/U"
                            )
                            Spacer()
                            Text("starts at").foregroundColor(.secondary)
                            Text(
                                "\(Self.dateFormatter.string(from: Date(timeIntervalSince1970: state.timeValues[item.timeIndex])))"
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

        func onAdd() {
            state.add()
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
        }
    }
}
