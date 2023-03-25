import CoreData
import SwiftUI
import Swinject

extension AddTempTarget {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isPromtPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?
        @State private var isEditing = false

        @FetchRequest(
            entity: ViewPercentage.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var isEnabledArray: FetchedResults<ViewPercentage>

        @Environment(\.managedObjectContext) var moc

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                if !state.presets.isEmpty {
                    Section(header: Text("Presets")) {
                        ForEach(state.presets) { preset in
                            presetView(for: preset)
                        }
                    }
                }

                Toggle(isOn: $state.viewPercantage) {
                    HStack {
                        Text("Use Slider for")
                        Image(systemName: "figure.highintensity.intervaltraining")
                        Text("or")
                        Image(systemName: "fork.knife")
                    }
                }

                if state.viewPercantage {
                    Section(
                        header: Text("Percent Insulin")
                    ) {
                        VStack {
                            Slider(
                                value: $state.percentage,
                                in: 15 ...
                                    Double(state.maxValue * 100),
                                step: 1,
                                onEditingChanged: { editing in
                                    isEditing = editing
                                }
                            )
                            Text("\(state.percentage.formatted(.number)) %")
                                .foregroundColor(isEditing ? .orange : .blue)
                                .font(.largeTitle)
                            Divider()
                            Text(
                                NSLocalizedString("Target glucose", comment: "") +
                                    (
                                        state
                                            .units == .mmolL ?
                                            ": \(computeTarget().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L" :
                                            ": \(computeTarget().formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) mg/dl"
                                    )
                            ) // .foregroundColor(.primary).italic()

                            Slider(
                                value: $state.hbt,
                                in: 104 ... 180,
                                step: 1
                            )
                            Text(
                                state
                                    .units == .mgdL ? "Half normal Basal at: \(state.hbt.formatted(.number)) mg/dl" :
                                    "Half normal Basal at: \(state.hbt.asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L"
                            )
                            .foregroundColor(.green)
                            .font(.caption).italic()
                        }
                    }
                } else {
                    Section(header: Text("Custom")) {
                        HStack {
                            Text("Target")
                            Spacer()
                            DecimalTextField("0", value: $state.low, formatter: formatter, cleanInput: true)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromtPresented = true }
                        label: { Text("Save as preset") }
                    }
                }
                if state.viewPercantage {
                    Section {
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromtPresented = true }
                        label: { Text("Save as preset") }
                    }
                }

                Section {
                    Button { state.enact() }
                    label: { Text("Enact") }
                    Button { state.cancel() }
                    label: { Text("Cancel Temp Target") }
                }
            }
            .popover(isPresented: $isPromtPresented) {
                Form {
                    Section(header: Text("Enter preset name")) {
                        TextField("Name", text: $state.newPresetName)
                        Button {
                            state.save()
                            isPromtPresented = false
                        }
                        label: { Text("Save") }
                        Button { isPromtPresented = false }
                        label: { Text("Cancel") }
                    }
                }
            }
            .onAppear {
                configureView()
                state.hbt = isEnabledArray.first?.hbt ?? 160
            }
            .navigationTitle("Enact Temp Target")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
            .onDisappear {
                if state.viewPercantage, state.saveSettings {
                    let isEnabledMoc = ViewPercentage(context: moc)
                    isEnabledMoc.enabled = true
                    isEnabledMoc.date = Date()
                    isEnabledMoc.hbt = state.hbt
                    try? moc.save()
                } else {
                    let isEnabledMoc = ViewPercentage(context: moc)
                    isEnabledMoc.enabled = false
                    isEnabledMoc.date = Date()
                    isEnabledMoc.hbt = isEnabledArray.first?.hbt ?? 160
                    try? moc.save()
                }
            }
        }

        func computeTarget() -> Decimal {
            var ratio = Decimal(state.percentage / 100)
            let c = Decimal(state.hbt - 100)
            var target = (c / ratio) - c + 100

            if c * (c + target - 100) <= 0 {
                ratio = state.maxValue
                target = (c / ratio) - c + 100
            }
            return target
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            return HStack {
                VStack {
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                    }
                    HStack(spacing: 2) {
                        Text(
                            "\(formatter.string(from: (low ?? 0) as NSNumber)!) - \(formatter.string(from: (high ?? 0) as NSNumber)!)"
                        )
                        .foregroundColor(.secondary)
                        .font(.caption)

                        Text(state.units.rawValue)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("for")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(formatter.string(from: preset.duration as NSNumber)!)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("min")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Spacer()
                    }.padding(.top, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.enactPreset(id: preset.id)
                }

                Image(systemName: "xmark.circle").foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .padding(.vertical)
                    .onTapGesture {
                        removeAlert = Alert(
                            title: Text("Are you sure?"),
                            message: Text("Delete preset \"\(preset.displayName)\""),
                            primaryButton: .destructive(Text("Delete"), action: { state.removePreset(id: preset.id) }),
                            secondaryButton: .cancel()
                        )
                        isRemoveAlertPresented = true
                    }
                    .alert(isPresented: $isRemoveAlertPresented) {
                        removeAlert!
                    }
            }
        }
    }
}
