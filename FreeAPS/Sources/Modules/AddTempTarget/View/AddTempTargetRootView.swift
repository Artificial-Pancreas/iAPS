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

                Section(
                    header: Text("Basal Insulin and Sensitivity ratio"),
                    footer: Text(
                        NSLocalizedString(
                            "A lower 'Half Basal Target' setting will reduce the basal and raise the ISF earlier, at a lower target glucose.",
                            comment: ""
                        ) +
                            NSLocalizedString(" Your setting: ", comment: "") + "\(state.halfBasal) " +
                            NSLocalizedString("mg/dl. Autosens.max limits the max endpoint", comment: "") +
                            " (\(state.maxValue * 100) %)"
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
                            NSLocalizedString("Target", comment: "") +
                                (
                                    state
                                        .units == .mmolL ?
                                        ": \(computeTarget().asMmolL.formatted(.number.grouping(.never).rounded(rule: .towardZero).precision(.fractionLength(1)))) mmol/L" :
                                        ": \(computeTarget().formatted(.number.grouping(.never).rounded(rule: .towardZero).precision(.fractionLength(0)))) mg/dl"
                                )
                        ).foregroundColor(.secondary).italic()
                    }
                }

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
        }

        func computeTarget() -> Decimal {
            let ratio = min(Decimal(state.percentage / 100), state.maxValue)
            let diff = Double(state.halfBasal - 100)
            let multiplier = state.percentage - (diff * (state.percentage / 100))
            var target = Decimal(diff + multiplier) / ratio

            if (state.halfBasal + (state.halfBasal + target - 100)) <= 0 {
                target = (state.halfBasal - 100 + (state.halfBasal - 100) * state.maxValue) / state.maxValue
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
