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
        @State private var alertSring = ""
        @State var isSheetPresented: Bool = false
        @State var isEditingPreset: Bool = false
        @State var presetToEdit: OverridePresets?

        @Environment(\.managedObjectContext) var moc

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "Empty" as String
            )
        ) var fetchedProfiles: FetchedResults<OverridePresets>

        @FetchRequest(
            entity: Auto_ISF.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var fetchedSettings: FetchedResults<Auto_ISF>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var insulinFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
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

        private var higherPrecisionFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var dateFormatter: DateComponentsFormatter {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .brief
            return formatter
        }

        var body: some View {
            overridesView
                .navigationBarTitle("Profiles")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("Close", action: state.hideModal))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .onAppear {
                    configureView()
                    state.savedSettings(edit: false, identifier: nil)
                }
                .alert(
                    "Start Profile",
                    isPresented: $showAlert,
                    actions: { alertViewBuilder() }, message: { Text(alertSring) }
                )
                .sheet(isPresented: $isSheetPresented) { newPreset }
                .sheet(isPresented: $isEditingPreset) { edit }
        }

        var overridesView: some View {
            Form {
                if state.presets.isNotEmpty, !isEditingPreset {
                    Section {
                        ForEach(fetchedProfiles.uniqued(on: \.id)) { preset in
                            profilesView(for: preset)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        presetToEdit = preset
                                        state.savedSettings(edit: true, identifier: presetToEdit?.id)
                                        isEditingPreset.toggle()
                                    } label: {
                                        Label("Edit", systemImage: "pencil.line")
                                    }
                                }
                        }
                        .onDelete(perform: removeProfile)
                    }
                }

                // Insulin Slider
                Section {
                    VStack {
                        Spacer()
                        Text("\(state.percentage.formatted(.number)) %")
                            .foregroundColor(
                                state
                                    .percentage >= 130 ? .red :
                                    (isEditing ? .orange : .blue)
                            )
                            .font(.largeTitle)
                        let max: Double = state.extended_overrides ? 400 : 200
                        Slider(
                            value: $state.percentage,
                            in: 10 ... max,
                            step: 1,
                            onEditingChanged: { editing in
                                isEditing = editing
                            }
                        ).accentColor(state.percentage >= 130 ? .red : .blue)
                        Spacer()
                    }
                }
                header: { Text("Insulin") }
                footer: {
                    Text(
                        "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage."
                    )
                }

                // Duration
                Section {
                    Toggle(isOn: $state._indefinite) {
                        Text("Enable indefinitely")
                    }
                    if !state._indefinite {
                        HStack {
                            Text("Duration")
                            DecimalTextField("0", value: $state.duration, formatter: formatter, liveEditing: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                    }
                } header: { Text("Duration") }

                // Target
                Section {
                    HStack {
                        Toggle(isOn: $state.override_target) {
                            Text("Override Profile Target")
                        }
                    }
                    if state.override_target {
                        HStack {
                            Text("Target Glucose")
                            DecimalTextField("0", value: $state.target, formatter: glucoseFormatter, liveEditing: true)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }
                    }
                } header: { Text("Target") }

                // Advanced Settings
                Section {
                    HStack {
                        Toggle(isOn: $state.advancedSettings) {
                            Text("More options")
                        }
                    }

                    if state.advancedSettings {
                        HStack {
                            Toggle(isOn: $state.smbIsOff) {
                                Text("Disable SMBs")
                            }
                        }
                        if state.smbIsOff {
                            HStack {
                                Toggle(isOn: $state.smbIsAlwaysOff) {
                                    Text("Schedule when SMBs are Off")
                                }.disabled(!state.smbIsOff)
                            }
                            if state.smbIsAlwaysOff {
                                HStack {
                                    Text("First Hour SMBs are Off (24 hours)")
                                    DecimalTextField("0", value: $state.start, formatter: formatter, liveEditing: true)
                                    Text("hour").foregroundColor(.secondary)
                                }
                                HStack {
                                    Text("Last Hour SMBs are Off (24 hours)")
                                    DecimalTextField("0", value: $state.end, formatter: formatter, liveEditing: true)
                                    Text("hour").foregroundColor(.secondary)
                                }
                            }
                        }

                        HStack {
                            Toggle(isOn: $state.endWIthNewCarbs) {
                                Text("End the Override with next Meal")
                            }
                        }

                        HStack {
                            Toggle(isOn: $state.isfAndCr) {
                                Text("Change ISF and CR and Basal")
                            }
                        }
                        if !state.isfAndCr {
                            HStack {
                                Toggle(isOn: $state.isf) {
                                    Text("Change ISF")
                                }
                            }
                            HStack {
                                Toggle(isOn: $state.cr) {
                                    Text("Change CR")
                                }
                            }
                            HStack {
                                Toggle(isOn: $state.basal) {
                                    Text("Change Basal")
                                }
                            }
                        }
                        HStack {
                            Text("SMB Minutes")
                            DecimalTextField(
                                "0",
                                value: $state.smbMinutes,
                                formatter: formatter,
                                liveEditing: true
                            )
                            Text("minutes").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("UAM SMB Minutes")
                            DecimalTextField(
                                "0",
                                value: $state.uamMinutes,
                                formatter: formatter,
                                liveEditing: true
                            )
                            Text("minutes").foregroundColor(.secondary)
                        }

                        HStack {
                            Toggle(isOn: $state.overrideMaxIOB) {
                                Text("Override Max IOB")
                            }
                        }

                        if state.overrideMaxIOB {
                            HStack {
                                Text("Max IOB")
                                DecimalTextField(
                                    "0",
                                    value: $state.maxIOB,
                                    formatter: insulinFormatter,
                                    liveEditing: true
                                )
                                Text("U").foregroundColor(.secondary)
                            }
                        }
                    }
                } header: { Text("Advanced Settings") }

                // Auto ISF
                Section {
                    Toggle(isOn: $state.overrideAutoISF) {
                        Text("Override Auto ISF")
                    }

                    if state.overrideAutoISF {
                        Toggle(isOn: $state.autoISFsettings.autoisf) {
                            Text("Enable Auto ISF")
                        }

                        if state.autoISFsettings.autoisf {
                            Toggle(isOn: $state.autoISFsettings.enableBGacceleration) {
                                Text("Enable BG acceleration")
                            }

                            HStack {
                                Text("Auto ISF Min")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.autoisf_min,
                                    formatter: insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("Auto ISF Max")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.autoisf_max,
                                    formatter: insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("SMB Delivery Ratio Minimum")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.smbDeliveryRatioMin,
                                    formatter: insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("SMB Delivery Ratio Maximum")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.smbDeliveryRatioMax,
                                    formatter: insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("SMB Delivery Ratio BG Range")
                                BGTextField(
                                    "0",
                                    mgdlValue: $state.autoISFsettings.smbDeliveryRatioBGrange,
                                    units: $state.units,
                                    isDisabled: false,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("Duration Weight")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.autoISFhourlyChange,
                                    formatter: insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("ISF weight for higher BG")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.higherISFrangeWeight,
                                    formatter: higherPrecisionFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("ISF weight for lower BG")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.lowerISFrangeWeight,
                                    formatter: higherPrecisionFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("ISF weight for postprandial BG rise")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.postMealISFweight,
                                    formatter: higherPrecisionFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("ISF weight while BG accelerates")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.bgAccelISFweight,
                                    formatter: higherPrecisionFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("ISF weight while BG decelerates")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.bgBrakeISFweight,
                                    formatter: higherPrecisionFormatter,
                                    liveEditing: true
                                )
                            }

                            HStack {
                                Text("Max IOB Threshold Percent")
                                DecimalTextField(
                                    "0",
                                    value: $state.autoISFsettings.iobThresholdPercent,
                                    formatter: insulinFormatter,
                                    liveEditing: true
                                )
                            }

                            Toggle(isOn: $state.autoISFsettings.use_B30) {
                                Text("Activate B30")
                            }

                            if state.autoISFsettings.use_B30 {
                                HStack {
                                    Text("Minimum Start Bolus size")
                                    DecimalTextField(
                                        "0",
                                        value: $state.autoISFsettings.iTime_Start_Bolus,
                                        formatter: insulinFormatter,
                                        liveEditing: true
                                    )
                                }

                                HStack {
                                    Text("Target Level for B30 to be enacted")
                                    BGTextField(
                                        "0",
                                        mgdlValue: $state.autoISFsettings.b30targetLevel,
                                        units: $state.units,
                                        isDisabled: false,
                                        liveEditing: true
                                    )
                                }

                                HStack {
                                    Text("Upper BG limit")
                                    BGTextField(
                                        "0",
                                        mgdlValue: $state.autoISFsettings.b30upperLimit,
                                        units: $state.units,
                                        isDisabled: false,
                                        liveEditing: true
                                    )
                                }

                                HStack {
                                    Text("Upper Delta limit")
                                    BGTextField(
                                        "0",
                                        mgdlValue: $state.autoISFsettings.b30upperdelta,
                                        units: $state.units,
                                        isDisabled: false,
                                        liveEditing: true
                                    )
                                }

                                HStack {
                                    Text("B30 Basal rate increase factor")
                                    DecimalTextField(
                                        "0",
                                        value: $state.autoISFsettings.b30factor,
                                        formatter: insulinFormatter,
                                        liveEditing: true
                                    )
                                }

                                HStack {
                                    Text("Duration of increased B30 basal rate")
                                    DecimalTextField(
                                        "0",
                                        value: $state.autoISFsettings.b30_duration,
                                        formatter: insulinFormatter,
                                        liveEditing: true
                                    )
                                }
                            }

                            Toggle(isOn: $state.autoISFsettings.ketoProtect) {
                                Text("Enable Keto Protection")
                            }

                            if state.autoISFsettings.ketoProtect {
                                Toggle(isOn: $state.autoISFsettings.variableKetoProtect) {
                                    Text("Variable Keto Protection")
                                }

                                if state.autoISFsettings.variableKetoProtect {
                                    HStack {
                                        Text("Safety TBR in %")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.ketoProtectBasalPercent,
                                            formatter: insulinFormatter,
                                            liveEditing: true
                                        )
                                    }
                                } else {
                                    Toggle(isOn: $state.autoISFsettings.ketoProtectAbsolut) {
                                        Text("Enable Keto protection with pre-defined TBR")
                                    }
                                    if state.autoISFsettings.ketoProtectAbsolut {
                                        HStack {
                                            Text("Absolute Safety TBR")
                                            DecimalTextField(
                                                "0",
                                                value: $state.autoISFsettings.ketoProtectBasalAbsolut,
                                                formatter: higherPrecisionFormatter,
                                                liveEditing: true
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: { Text("Auto ISF") }

                if isEditingPreset {
                    Section {
                        HStack {
                            Text("Name").foregroundStyle(.secondary)
                            TextField("Name", text: $state.profileName)
                                .multilineTextAlignment(.trailing)
                        }
                    } header: { Text("Profile Name") }
                }

                // Buttons
                Section {
                    HStack {
                        if !isEditingPreset {
                            Button("Start") {
                                showAlert.toggle()
                                let duration = TimeInterval(state.duration * 60)
                                alertSring = "\(state.percentage.formatted(.number)) %, " +
                                    (
                                        state.duration > 0 && !state._indefinite ? (
                                            dateFormatter
                                                .string(from: duration) ?? ""
                                        ) :
                                            NSLocalizedString(" infinite duration.", comment: "")
                                    ) +
                                    (
                                        (state.target == 0 || !state.override_target) ? "" :
                                            (" Target: " + state.target.formatted() + " " + state.units.rawValue + ".")
                                    )
                                    +
                                    (
                                        state
                                            .smbIsOff ?
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
                            .disabled(unChanged())
                            .buttonStyle(BorderlessButtonStyle())
                            .font(.callout)
                            .controlSize(.mini)
                        }

                        Button {
                            if !isEditingPreset {
                                isSheetPresented = true
                            } else if let editThis = presetToEdit {
                                save(editThis)
                                isEditingPreset.toggle()
                            }
                        }
                        label: { Text(isEditingPreset ? LocalizedStringKey("Save") : LocalizedStringKey("Save as Profile")) }
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .controlSize(.mini)
                            .disabled(isEditingPreset ? false : unChanged())

                        if state.isEnabled, !isEditingPreset {
                            Section {
                                Button("Cancel Profile Override") {
                                    state.cancelProfile()
                                    state.hideModal()
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(!state.isEnabled)
                                .tint(.red)
                            } footer: { Text("").padding(.bottom, 150) }
                        }
                    }
                }
            }
        }

        var newPreset: some View {
            Form {
                Section {
                    TextField("Name", text: $state.profileName)
                } header: { Text("Profile Name").foregroundStyle(.primary) }

                Section {
                    Button("Save") {
                        state.savePreset()
                        isSheetPresented = false
                    }
                    .disabled(
                        state.profileName.isEmpty || fetchedProfiles.filter({ $0.name == state.profileName })
                            .isNotEmpty
                    )

                    Button("Cancel") {
                        isSheetPresented = false
                    }
                }
            }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }

        @ViewBuilder private func alertViewBuilder() -> some View {
            Button("Cancel", role: .cancel) { state.isEnabled = false }
            Button("Start Profile", role: .destructive) {
                if state._indefinite { state.duration = 0 }
                state.isEnabled.toggle()
                state.saveSettings()
                state.hideModal()
            }
        }

        // The Profile presets
        @ViewBuilder private func profilesView(for preset: OverridePresets) -> some View {
            // Values as String
            let targetRaw = ((preset.target ?? 0) as NSDecimalNumber) as Decimal
            let target = state.units == .mmolL ? targetRaw.asMmolL : targetRaw
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : dateFormatter
                .string(from: TimeInterval(truncating: (preset.duration ?? 0) as NSNumber) * 60) ?? ""
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
            let autoisfSettings = fetchedSettings.first(where: { $0.id == preset.id })

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
                            bool(bool: aisf.autoisf, setting: state.currentSettings.autoisf, label: "Auto ISF")
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
                        let standard = state.currentSettings
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

                            if ((aisf.smbDeliveryRatioMin ?? 0.5) as Decimal) != standard
                                .smbDeliveryRatioMin || ((aisf.smbDeliveryRatioMax ?? 0.5) as Decimal) != standard
                                .smbDeliveryRatioMax
                            {
                                Text(
                                    "SMB ratio: \(aisf.smbDeliveryRatioMin ?? 0.5)-\(aisf.smbDeliveryRatioMax ?? 0.5)"
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
                    state.selectProfile(id_: preset.id ?? "")
                    state.hideModal()
                }
                .dynamicTypeSize(...DynamicTypeSize.large)
            }
        }

        private var edit: some View {
            overridesView.dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }

        private func unChanged() -> Bool {
            let percentUnchanged = state.percentage == 100
            let targetUnchanged = !state.override_target || state.target == 0
            let smbUnchanged = !state.smbIsOff
            let maxIOBUnchanged = !state.advancedSettings || !state.overrideMaxIOB || state.maxIOB == 0
            let smbMinutesUnchanged = state.smbMinutes == state.defaultSmbMinutes
            let uamMinutesUnchanged = state.uamMinutes == state.defaultUamMinutes
            let autoISFUnchanged = !state.overrideAutoISF

            return percentUnchanged && targetUnchanged && smbUnchanged && maxIOBUnchanged && smbMinutesUnchanged &&
                uamMinutesUnchanged && autoISFUnchanged
        }

        private func decimal(decimal: NSDecimalNumber?, setting: Decimal, label: String) -> Text? {
            if let dec = decimal as? Decimal, round(dec) != round(setting) {
                return Text(label + "\(dec)")
            }
            return nil
        }

        private func bool(bool: Bool, setting: Bool, label: String) -> AnyView? {
            let onOff = bool ? NSLocalizedString(" on", comment: "Is true") :
                NSLocalizedString(" off", comment: "Is false")
            if bool != setting {
                return Text(label + onOff).foregroundStyle(.white).boolTag(bool).asAny()
            }
            return nil
        }

        private func percentage(decimal: NSDecimalNumber?, setting: Decimal, label: String) -> Text? {
            if let dec = decimal as? Decimal, dec != setting {
                return Text(label + "\(dec)%")
            }
            return nil
        }

        private func glucose(decimal: NSDecimalNumber?, setting: Decimal, label: String) -> Text? {
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

        private func removeProfile(at offsets: IndexSet) {
            for index in offsets {
                let preset = fetchedProfiles[index]
                moc.delete(preset)
            }
            do {
                try moc.save()
            } catch {
                // To do: add error
            }
        }

        private func save(_ preset: OverridePresets) {
            let saveOverride = preset

            saveOverride.duration = state.duration as NSDecimalNumber
            saveOverride.indefinite = state._indefinite
            saveOverride.percentage = state.percentage
            saveOverride.smbIsOff = state.smbIsOff
            saveOverride.name = state.profileName
            saveOverride.emoji = state.emoji
            saveOverride.overrideAutoISF = state.overrideAutoISF
            if state.override_target {
                saveOverride.target = (
                    state.units == .mmolL
                        ? state.target.asMgdL
                        : state.target
                ) as NSDecimalNumber
            } else { saveOverride.target = 6 }

            saveOverride.advancedSettings = state.advancedSettings
            saveOverride.endWIthNewCarbs = state.endWIthNewCarbs
            saveOverride.isfAndCr = state.isfAndCr
            if !state.isfAndCr {
                saveOverride.isf = state.isf
                saveOverride.cr = state.cr
                saveOverride.basal = state.basal
            }

            if state.smbIsAlwaysOff {
                saveOverride.smbIsAlwaysOff = true
                saveOverride.start = state.start as NSDecimalNumber
                saveOverride.end = state.end as NSDecimalNumber
            } else { saveOverride.smbIsAlwaysOff = false }

            if !state.smbIsAlwaysOff {
                saveOverride.smbMinutes = state.smbMinutes as NSDecimalNumber
                saveOverride.uamMinutes = state.uamMinutes as NSDecimalNumber
            }
            saveOverride.overrideMaxIOB = state.overrideMaxIOB
            if state.overrideMaxIOB {
                saveOverride.maxIOB = state.maxIOB as NSDecimalNumber
            }
            saveOverride.date = Date.now

            if state.overrideAutoISF {
                state.updateAutoISF(preset.id)
            }

            do {
                try moc.save()
            } catch {
                // To do: add error
            }
        }
    }
}
