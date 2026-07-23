import SwiftUI
import Swinject

extension OverrideProfilesConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state: StateModel

        @State private var showAlert = false
        @State private var alertString = ""

        /// The preset currently being edited in its own sheet (isolated from the main form).
        @State private var presetToEdit: OverridePresetsSnapshot?

        /// "Save as Profile" name entry.
        @State private var showingNewPresetName = false
        @State private var newPresetName = ""

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

        private var dateFormatter: DateComponentsFormatter {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .brief
            return formatter
        }

        private var promilleFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 3
            return formatter
        }

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            overridesView
                .navigationBarTitle("Profiles")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("Close", action: state.hideModal))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .alert(
                    "Start Profile",
                    isPresented: $showAlert,
                    actions: { alertViewBuilder() }, message: { Text(alertString) }
                )
                .sheet(isPresented: $showingNewPresetName) { newPresetSheet }
                .sheet(item: $presetToEdit) { preset in
                    PresetEditorView(
                        preset: preset,
                        context: state.context,
                        onSave: { name, emoji, form in
                            state.updatePreset(id: preset.id, name: name, emoji: emoji, form: form)
                            presetToEdit = nil
                        },
                        onCancel: { presetToEdit = nil }
                    )
                }
        }

        var overridesView: some View {
            Form {
                Section {
                    ForEach(state.profiles, id: \.id) { preset in
                        profilesView(for: preset)
                            .swipeActions(edge: .leading) {
                                Button {
                                    presetToEdit = preset
                                } label: {
                                    Label("Edit", systemImage: "pencil.line")
                                }
                            }
                    }
                    .onDelete(perform: state.deleteProfile)
                }

                OverrideSettingsForm(form: $state.form, context: state.context)

                // Buttons
                Section {
                    HStack {
                        Button("Start") {
                            alertString = startAlertString()
                            showAlert.toggle()
                        }
                        .disabled(unChanged())
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.callout)
                        .controlSize(.mini)

                        Button {
                            newPresetName = ""
                            showingNewPresetName = true
                        }
                        label: { Text("Save as Profile") }
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .controlSize(.mini)
                            .disabled(unChanged())
                    }

                    if state.isOverrideActive {
                        Button("Cancel Profile Override") {
                            state.cancelActiveOverride()
                            state.hideModal()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(BorderlessButtonStyle())
                        .tint(.red)
                    }
                }
            }
        }

        var newPresetSheet: some View {
            Form {
                Section {
                    TextField("Name", text: $newPresetName)
                } header: { Text("Profile Name").foregroundStyle(.primary) }

                Section {
                    Button("Save") {
                        state.saveAsNewPreset(name: newPresetName)
                        showingNewPresetName = false
                    }
                    .disabled(
                        newPresetName.isEmpty || state.profiles.contains(where: { $0.name == newPresetName })
                    )

                    Button("Cancel") {
                        showingNewPresetName = false
                    }
                }
            }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }

        private func startAlertString() -> String {
            let seconds = TimeInterval.minutes(state.form.duration)
            return (formatter.string(from: state.form.percentage as NSNumber) ?? "100") + "%, " +
                (
                    state.form.duration > 0 && !state.form._indefinite ? (
                        dateFormatter.string(from: seconds) ?? ""
                    ) :
                        NSLocalizedString(" infinite duration.", comment: "")
                ) +
                (
                    (state.form.target == 0 || !state.form.override_target) ? "" :
                        (" Target: " + state.form.target.formatted() + " " + state.units.rawValue + ".")
                )
                +
                (
                    state.form.smbIsOff ?
                        NSLocalizedString(
                            " SMBs are disabled either by schedule or during the entire duration.",
                            comment: ""
                        ) : ""
                )
                +
                "\n\n"
                +
                NSLocalizedString(
                    "Starting this override will change your Profiles and/or your Target Glucose used for looping during the entire selected duration. Tapping ”Start Profile” will start your new profile or edit your current active profile.",
                    comment: ""
                )
        }

        @ViewBuilder private func alertViewBuilder() -> some View {
            Button("Cancel", role: .cancel) {}
            Button("Start Profile", role: .destructive) {
                state.startOverride()
                state.hideModal()
            }
        }

        // The Profile presets
        @ViewBuilder private func profilesView(for preset: OverridePresetsSnapshot) -> some View {
            // Values as String
            let targetRaw = ((preset.target ?? 0) as NSDecimalNumber) as Decimal
            let target = state.units == .mmolL ? targetRaw.asMmolL : targetRaw
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : dateFormatter
                .string(from: TimeInterval.minutes(preset.duration ?? 0)) ?? ""
            let scheduledSMBstring = (preset.smbIsOff && preset.smbIsAlwaysOff) ? LocalizedStringKey("🕝 SMBs") : ""
            let smbString = (preset.smbIsOff && scheduledSMBstring == "") ? "SMBs" : ""
            let targetString = targetRaw > 10 ? "\(glucoseFormatter.string(from: target as NSNumber) ?? "")" : ""
            let isfString = preset.isf ? "ISF" : ""
            let crString = preset.cr ? "CR" : ""
            let basalString = preset.basal ? "Basal" : ""
            let dash = (crString != "" && isfString != "") ? ", " : ""
            let dash2 = (basalString != "" && isfString + dash + crString != "") ? ", " : ""
            let isfAndCRstring = isfString + dash + crString + dash2 + basalString != "" ? "[" + isfString + dash + crString +
                dash2 + basalString + "]" : "[None]"
            let autoisfSettings = preset.aisf

            if name != "" {
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(name).padding(.vertical, 4)
                        if preset.advancedSettings, preset.endWIthNewCarbs {
                            Image("PreMealOverride").foregroundStyle(.green)
                        }
                        Spacer()
                    }
                    HStack {
                        percent != 1 ?
                            Text(percent.formatted(.percent.grouping(.never).rounded().precision(.fractionLength(0))))
                            .foregroundStyle(.secondary) : nil
                        targetString != "" ? Text(targetString + " " + state.units.rawValue).foregroundStyle(.secondary) : nil
                        durationString != "" ? Text(durationString).foregroundStyle(.secondary) : nil
                        if let aisf = autoisfSettings, preset.overrideAutoISF {
                            bool(bool: aisf.autoisf, setting: state.currentAutoIsfSettings.autoisf, label: "Auto ISF")
                            bool(bool: aisf.autocr, setting: state.currentAutoIsfSettings.autocr, label: "Auto CR")
                        }

                        if preset.glucoseOverrideThresholdActive || preset.glucoseOverrideThresholdActiveDown {
                            Image(systemName: "drop.fill").foregroundStyle(.red)
                        }
                    }
                    .font(.caption)

                    if preset.advancedSettings {
                        HStack {
                            percent != 1 && !(preset.isf && preset.cr && preset.basal) ?
                                Text(
                                    NSLocalizedString("Adjust ", comment: "Override adjustment of ISF, CR and Basal") +
                                        isfAndCRstring
                                ) : nil
                            if !preset.smbIsOff {
                                decimal(decimal: preset.smbMinutes ?? 0, setting: state.defaultSmbMinutes, label: "SMB ")
                                decimal(decimal: preset.uamMinutes ?? 0, setting: state.defaultUamMinutes, label: "UAM ")
                            }
                            if preset.overrideMaxIOB {
                                decimal(decimal: preset.maxIOB, setting: state.defaultmaxIOB, label: "Max IOB: ")
                            }
                            smbString != "" ? bool(bool: false, setting: true, label: smbString) : nil
                            scheduledSMBstring != "" ? Text(scheduledSMBstring) : nil
                        }.foregroundStyle(.secondary).font(.caption)
                    }

                    // All of the Auto ISF Settings (Bool and Decimal optionals)
                    if preset.overrideAutoISF, let aisf = autoisfSettings, aisf.autoisf {
                        let standard = state.currentAutoIsfSettings
                        HStack {
                            bool(bool: aisf.enableBGacceleration, setting: standard.enableBGacceleration, label: "Accel")
                                .frame(maxHeight: 30)
                            bool(bool: aisf.ketoProtect, setting: standard.ketoProtect, label: "Keto").frame(maxHeight: 30)
                            bool(bool: aisf.use_B30, setting: standard.use_B30, label: "B30").frame(maxHeight: 30)

                            decimal(decimal: aisf.autoisf_min, setting: standard.autoisf_min, label: "Min: ")
                            decimal(decimal: aisf.autoisf_max, setting: standard.autoisf_max, label: "Max: ")
                        }
                        .foregroundStyle(.secondary).font(.caption)

                        HStack {
                            percentage(
                                decimal: aisf.iobThresholdPercent,
                                setting: standard
                                    .iobThresholdPercent,
                                label: "SMB IOB: "
                            )

                            if aisf.smbDeliveryRatioMin != standard.smbDeliveryRatioMin ||
                                aisf.smbDeliveryRatioMax != standard.smbDeliveryRatioMax
                            {
                                Text(
                                    "SMB ratio: \(aisf.smbDeliveryRatioMin as NSNumber)-\(aisf.smbDeliveryRatioMax as NSNumber)"
                                )
                            }
                            glucose(
                                decimal: aisf.smbDeliveryRatioBGrange,
                                setting: standard.smbDeliveryRatioBGrange,
                                label: "SMB Range: "
                            )
                        }.foregroundStyle(.secondary).font(.caption)

                        HStack {
                            decimal(
                                decimal: aisf.lowerISFrangeWeight,
                                setting: standard.lowerISFrangeWeight,
                                label: "low: "
                            )
                            decimal(
                                decimal: aisf.higherISFrangeWeight,
                                setting: standard.higherISFrangeWeight,
                                label: "high: "
                            )

                            if aisf.enableBGacceleration {
                                decimal(
                                    decimal: aisf.bgAccelISFweight,
                                    setting: standard.bgAccelISFweight,
                                    label: "accel: "
                                )
                                decimal(
                                    decimal: aisf.bgBrakeISFweight,
                                    setting: standard.bgBrakeISFweight,
                                    label: "brake: "
                                )
                            }
                            decimal(
                                decimal: aisf.autoISFhourlyChange,
                                setting: standard.autoISFhourlyChange,
                                label: "dura: "
                            )
                            decimal(decimal: aisf.postMealISFweight, setting: standard.postMealISFweight, label: "pp: ")
                        }.foregroundStyle(.secondary).font(.caption)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.activateOverrideFromPreset(preset)
                    state.hideModal()
                }
                .dynamicTypeSize(...DynamicTypeSize.large)
            }
        }

        private func unChanged() -> Bool {
            let percentUnchanged = state.form.percentage == 100
            let targetUnchanged = !state.form.override_target || state.form.target == 0
            let smbUnchanged = !state.form.smbIsOff
            let maxIOBUnchanged = !state.form.advancedSettings || !state.form.overrideMaxIOB || state.form.maxIOB == 0
            let smbMinutesUnchanged = state.form.smbMinutes == state.defaultSmbMinutes
            let uamMinutesUnchanged = state.form.uamMinutes == state.defaultUamMinutes
            let autoISFUnchanged = !state.form.overrideAutoISF
            let glucoseOverrideUnchanged = !state.form.glucoseOverrideThresholdActive

            return percentUnchanged && targetUnchanged && smbUnchanged && maxIOBUnchanged && smbMinutesUnchanged &&
                uamMinutesUnchanged && autoISFUnchanged && glucoseOverrideUnchanged
        }

        private func decimal(decimal: Decimal?, setting: Decimal, label: String) -> Text? {
            guard let dec = decimal, round(dec) != round(setting) else { return nil }

            guard label != "pp: " else {
                return Text(label + (promilleFormatter.string(from: (decimal ?? 0) as NSDecimalNumber) ?? ""))
            }

            return Text(label + "\(dec)")
        }

        private func bool(bool: Bool, setting: Bool, label: String) -> AnyView? {
            let onOff = bool ? NSLocalizedString(" on", comment: "Is true") :
                NSLocalizedString(" off", comment: "Is false")
            if bool != setting {
                return Text(label + onOff).foregroundStyle(.white).boolTag(bool).asAny()
            }
            return nil
        }

        private func percentage(decimal: Decimal?, setting: Decimal, label: String) -> Text? {
            if let dec = decimal, dec != setting {
                return Text(label + "\(dec)%")
            }
            return nil
        }

        private func glucose(decimal: Decimal?, setting: Decimal, label: String) -> Text? {
            if let nsDecimal = decimal {
                let dec = nsDecimal as Decimal
                if round(dec) != round(setting) {
                    let target: Decimal = state.units == .mmolL ? dec.asMmolL : dec
                    return Text(label + (glucoseFormatter.string(from: target as NSNumber) ?? "") + " " + state.units.rawValue)
                }
            }
            return nil
        }

        /// Round to two fraction digits
        private func round(_ decimal: Decimal) -> Decimal {
            decimal.rounded(to: 2)
        }
    }

    /// Edits a saved preset in its own sheet, with its own `OverrideForm` buffer and name.
    /// Completely isolated from the main override form, so opening it never disturbs a
    /// custom/active override the user was editing.
    struct PresetEditorView: View {
        let preset: OverridePresetsSnapshot
        let context: OverrideForm.Context
        let onSave: (_ name: String, _ emoji: String?, _ form: OverrideForm) -> Void
        let onCancel: () -> Void

        @State private var form: OverrideForm
        @State private var name: String

        init(
            preset: OverridePresetsSnapshot,
            context: OverrideForm.Context,
            onSave: @escaping (String, String?, OverrideForm) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.preset = preset
            self.context = context
            self.onSave = onSave
            self.onCancel = onCancel
            _form = State(initialValue: OverrideForm(from: preset, context: context))
            _name = State(initialValue: preset.name ?? "")
        }

        var body: some View {
            NavigationView {
                Form {
                    Section {
                        HStack {
                            Text("Name").foregroundStyle(.secondary)
                            TextField("Name", text: $name)
                                .multilineTextAlignment(.trailing)
                        }
                    } header: { Text("Profile Name") }

                    OverrideSettingsForm(form: $form, context: context)
                }
                .navigationBarTitle("Edit Profile", displayMode: .inline)
                .navigationBarItems(
                    leading: Button("Cancel", action: onCancel),
                    trailing: Button("Save") { onSave(name, preset.emoji, form) }
                        .disabled(name.isEmpty)
                )
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
        }
    }
}

// `.sheet(item:)` requires Identifiable; the snapshot already carries a stable `id`.
extension OverridePresetsSnapshot: Identifiable {}
