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
            sortDescriptors: [NSSortDescriptor(key: "enabled", ascending: false)]
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
                    Text("Exercise / Pre Meal Slider")
                }

                if state.viewPercantage {
                    Section(
                        header: Text("Effect of TT on Basal and Sensitivity"),
                        footer: Text(
                            NSLocalizedString(
                                "'Half Basal Target' (HBT) setting adjusts how a temp target affects basal and ISF.\n     A lower HBT will allow Basal to be reduced earlier (at a less high TT).\n",
                                comment: ""
                            ) +
                                NSLocalizedString("     HBT setting: ", comment: "") + "\(state.halfBasal) " +
                                NSLocalizedString("mg/dl. Autosens.max setting determines the max endpoint", comment: "") +
                                " (\(state.maxValue): \(state.maxValue * 100) %)"
                        )
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
                                NSLocalizedString("Temp Target to Save", comment: "") +
                                    (
                                        state
                                            .units == .mmolL ?
                                            ": \(computeTarget().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L" :
                                            ": \(computeTarget().formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) mg/dl"
                                    )
                            ).foregroundColor(.primary).italic()
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
            .onAppear(perform: configureView)
            .navigationTitle("Enact Temp Target")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
            .onDisappear {
                if state.viewPercantage {
                    let isEnabledMoc = ViewPercentage(context: moc)
                    isEnabledMoc.enabled = true
                    isEnabledMoc.date = Date()
                    try? moc.save()
                } else {
                    let isEnabledMoc = ViewPercentage(context: moc)
                    isEnabledMoc.enabled = false
                    isEnabledMoc.date = Date()
                    try? moc.save()
                }
            }
        }

        func computeTarget() -> Decimal {
            var ratio = Decimal(state.percentage / 100)
            let hB = state.halfBasal
            let c = hB - 100
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
