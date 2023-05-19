import CoreData
import SwiftUI
import Swinject

extension OverrideProfilesConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State private var isEditing = false
        @State private var showAlert = false
        @State private var showingDetail = false
        @State private var isPresented = true
        @State private var alertSring = ""
        @State private var isPromtPresented = false
        @State private var saved = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?

        @Environment(\.dismiss) var dismiss
        @Environment(\.managedObjectContext) var moc

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "" as String
            )
        ) var fetchedProfiles: FetchedResults<OverridePresets>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        var presetPopover: some View {
            Form {
                Section(header: Text("Enter Profile Name")) {
                    TextField("Name Of Profile", text: $state.profileName)
                    Button {
                        if state.profileName != "", fetchedProfiles.filter({ $0.name == state.profileName }).isEmpty {
                            state.savePreset()
                            isPromtPresented = false
                        }
                    }
                    label: { Text("Save") }
                        .disabled(
                            state.profileName == "" ||
                                !fetchedProfiles.filter({ $0.name == state.profileName }).isEmpty
                        )
                    Button {
                        state.profileName = ""
                        isPromtPresented = false }
                    label: { Text("Cancel") }
                }
            }
        }

        var body: some View {
            Form {
                if !state.presets.isEmpty {
                    Section(header: Text("Profiles")) {
                        ForEach(fetchedProfiles) { preset in
                            presetView(for: preset)
                        }
                    }
                }
                Section(
                    header: Text("Override your profiles"),
                    footer: Text("" + (!state.isEnabled ? NSLocalizedString("Currently no Override active", comment: "") : ""))
                ) {
                    Toggle(isOn: $state.isEnabled) {
                        Text("Override Profiles")
                    }._onBindingChange($state.isEnabled, perform: { _ in
                        if !state.isEnabled {
                            state.duration = 0
                            state.percentage = 100
                            state._indefinite = true
                            state.override_target = false
                            state.saveSettings()
                        }
                    })
                }
                if state.isEnabled {
                    Section(
                        header: Text("Total Insulin Adjustment"),
                        footer: Text(
                            "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage.\n\nIf you toggle off the override every profile setting will return to normal."
                        )
                    ) {
                        VStack {
                            Slider(
                                value: $state.percentage,
                                in: 10 ... 200,
                                step: 1,
                                onEditingChanged: { editing in
                                    isEditing = editing
                                }
                            ).accentColor(state.percentage >= 130 ? .red : .blue)
                            Text("\(state.percentage.formatted(.number)) %")
                                .foregroundColor(
                                    state
                                        .percentage >= 130 ? .red :
                                        (isEditing ? .orange : .blue)
                                )
                                .font(.largeTitle)
                            Spacer()
                            Toggle(isOn: $state._indefinite) {
                                Text("Enable indefinitely")
                            }
                        }
                        if !state._indefinite {
                            HStack {
                                Text("Duration")
                                DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: false)
                                Text("minutes").foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            Toggle(isOn: $state.override_target) {
                                Text("Override Profile Target")
                            }
                        }
                        if state.override_target {
                            HStack {
                                Text("Target Glucose")
                                DecimalTextField("0", value: $state.target, formatter: glucoseFormatter, cleanInput: false)
                                Text(state.units.rawValue).foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Toggle(isOn: $state.smbIsOff) {
                                Text("Disable SMBs")
                            }
                        }

                        HStack {
                            Button("Start") {
                                showAlert.toggle()
                                alertSring = "\(state.percentage.formatted(.number)) %, " +
                                    (
                                        state.duration > 0 || !state
                                            ._indefinite ?
                                            (
                                                state
                                                    .duration
                                                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                                                    " min."
                                            ) :
                                            " infinite duration."
                                    ) +
                                    (
                                        (state.target == 0 || !state.override_target) ? "" :
                                            (" Target: " + state.target.formatted() + " " + state.units.rawValue + ".")
                                    )
                                    + (state.smbIsOff ? " SMBs are disabled." : "")
                                    +
                                    "\n\n"
                                    +
                                    "Starting this override will change your Profiles and/or your Target Glucose used for looping during the entire selected duration. Tapping ”Start” will start your new overide or edit your current active override."
                            }
                            .disabled(
                                !state
                                    .isEnabled || (state.percentage == 100 && !state.override_target && !state.smbIsOff) ||
                                    (!state._indefinite && state.duration == 0 || (state.override_target && state.target == 0))
                            )
                            .accentColor(.orange)
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .controlSize(.mini)
                            .alert(
                                "Start Override",
                                isPresented: $showAlert,
                                actions: {
                                    Button("Cancel", role: .cancel) {}
                                    Button("Start Override", role: .destructive) {
                                        if state._indefinite {
                                            state.duration = 0
                                        } else if state.duration == 0 {
                                            state.isEnabled = false
                                        }
                                        state.saveSettings()
                                        dismiss()
                                    }
                                },
                                message: {
                                    Text(alertSring)
                                }
                            )
                            Button {
                                isPromtPresented = true
                            }
                            label: { Text("Save as Profile") }
                                .disabled(
                                    !state
                                        .isEnabled || (state.percentage == 100 && !state.override_target && !state.smbIsOff) ||
                                        (
                                            !state._indefinite && state
                                                .duration == 0 || (state.override_target && state.target == 0)
                                        )
                                )
                        }
                        .popover(isPresented: $isPromtPresented) {
                            presetPopover
                        }
                    }
                }
            }
            .onAppear(perform: configureView)
            .onAppear { state.savedSettings() }
        }

        private func presetView(for preset: OverridePresets) -> some View {
            var target = (preset.target ?? 0) as Decimal
            if state.units == .mmolL {
                target = target.asMmolL
            }
            let duration = (preset.duration ?? 0) as Decimal
            let name = preset.name ?? ""
            let percent = preset.percentage
            let perpetual = preset.indefinite
            let durationString = perpetual ? "Perpetual" : "\(formatter.string(from: duration as NSNumber)!)"
            let smbString = preset.smbIsOff ? "SMBs off" : ""
            let targetString = target != 0 ? "\(formatter.string(from: target as NSNumber)!)" : ""

            return HStack {
                VStack {
                    HStack {
                        Text(name)
                        Spacer()
                    }
                    HStack(spacing: 2) {
                        Text(
                            "\(formatter.string(from: percent as NSNumber)!)"
                        )
                        .foregroundColor(.secondary)
                        .font(.caption)
                        Text(targetString)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(state.units.rawValue)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(perpetual ? "for" : "")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(durationString)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("min")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(smbString)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Spacer()
                    }.padding(.top, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.selectProfile(id: preset.id ?? "")
                }

                Image(systemName: "xmark.circle").foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .padding(.vertical)
                    .onTapGesture {
                        removeAlert = Alert(
                            title: Text("Are you sure?"),
                            message: Text("Delete Profile \"\(name)\""),
                            primaryButton: .destructive(Text("Delete"), action: { state.removeProfile(id: preset.id ?? "") }),
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
