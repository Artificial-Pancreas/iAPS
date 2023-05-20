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
                        state.savePreset()
                        isPromtPresented = false
                    }

                    label: { Text("Save") }
                        .disabled(
                            state.profileName == "" ||
                                fetchedProfiles.filter({ $0.name == state.profileName }).isNotEmpty
                        )
                    Button {
                        isPromtPresented = false }
                    label: { Text("Cancel") }
                }
            }
        }

        var body: some View {
            Form {
                if state.presets.isNotEmpty {
                    Section {
                        /*
                         ForEach(fetchedProfiles) { preset in
                             profilesView(for: preset)
                         }.onDelete(perform: removeProfile)
                         */

                        ForEach(fetchedProfiles, id: \.self) { (preset: OverridePresets) in
                            let name = (preset.name ?? "") == "" || (preset.name?.isEmpty ?? true) ? "" : preset.name!
                            if name != "" { // Ugly. To do: fix
                                profilesView(for: preset)
                            }
                        }.onDelete(perform: removeProfile)
                    }
                    header: { Text("Profiles") }
                    // footer: { Text("swipe to delete").italic().frame(maxWidth: .infinity, alignment: .trailing) }
                }
                Section(
                    header: Text("Insulin"),
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
                            (state.percentage == 100 && !state.override_target && !state.smbIsOff) ||
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
                                Button("Cancel", role: .cancel) { state.isEnabled = false }
                                Button("Start Override", role: .destructive) {
                                    if state._indefinite {
                                        state.duration = 0
                                    } else if state.duration == 0 {
                                        state.isEnabled = true
                                    }
                                    state.isEnabled = true
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
                                (state.percentage == 100 && !state.override_target && !state.smbIsOff) ||
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
            .onAppear { state.savedSettings() }
            .onAppear(perform: configureView)
        }

        @ViewBuilder private func profilesView(for preset: OverridePresets) -> some View {
            let target = state.units == .mmolL ? (((preset.target ?? 0) as NSDecimalNumber) as Decimal)
                .asMmolL : (preset.target ?? 0) as Decimal
            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "from now on" : "\(formatter.string(from: duration as NSNumber)!)"
            let smbString = preset.smbIsOff ? "SMBs are off" : ""
            let targetString = target != 0 ? "\(formatter.string(from: target as NSNumber)!)" : ""

            if name != "" {
                HStack {
                    VStack {
                        HStack {
                            Text(name)
                            Spacer()
                        }
                        HStack(spacing: 2) {
                            Text(percent.formatted(.percent.grouping(.never).rounded().precision(.fractionLength(0))))
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(targetString)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(state.units.rawValue)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(perpetual ? "" : "for")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(durationString)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(perpetual ? "" : "min")
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
                        dismiss()
                    }
                }
            }
        }

        private func removeProfile(at offsets: IndexSet) {
            for index in offsets {
                let language = fetchedProfiles[index]
                moc.delete(language)
            }
            do {
                try moc.save()
            } catch {
                // To do: add error
            }
        }
    }
}
