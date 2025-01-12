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
        @State var index: Int = 1

        @Environment(\.dismiss) var dismiss
        @Environment(\.managedObjectContext) var moc

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "" as String
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

        var presetPopover: some View {
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

        var body: some View {
            Form {
                if state.presets.isNotEmpty {
                    Section {
                        ForEach(fetchedProfiles) { preset in
                            profilesView(for: preset)
                        }.onDelete(perform: removeProfile)
                    }
                }
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
                        HStack {
                            Toggle(isOn: $state.smbIsAlwaysOff) {
                                Text("Schedule when SMBs are Off")
                            }.disabled(!state.smbIsOff)
                        }
                        if state.smbIsAlwaysOff {
                            HStack {
                                Text("First Hour SMBs are Off (24 hours)")
                                DecimalTextField("0", value: $state.start, formatter: formatter, cleanInput: false)
                                Text("hour").foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Last Hour SMBs are Off (24 hours)")
                                DecimalTextField("0", value: $state.end, formatter: formatter, cleanInput: false)
                                Text("hour").foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Toggle(isOn: $state.isfAndCr) {
                                Text("Change ISF and CR")
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
                        }
                        HStack {
                            Text("SMB Minutes")
                            DecimalTextField(
                                "0",
                                value: $state.smbMinutes,
                                formatter: formatter,
                                cleanInput: false
                            )
                            Text("minutes").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("UAM SMB Minutes")
                            DecimalTextField(
                                "0",
                                value: $state.uamMinutes,
                                formatter: formatter,
                                cleanInput: false
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
                                    cleanInput: false
                                )
                                Text("U").foregroundColor(.secondary)
                            }
                        }

                        Group {
                            Toggle(isOn: $state.overrideAutoISF) {
                                Text("Override Auto ISF")
                            }

                            if state.overrideAutoISF {
                                Toggle(isOn: $state.autoISFsettings.autoisf) {
                                    Text("Enable Auto ISF")
                                }

                                if state.autoISFsettings.autoisf {
                                    Toggle(isOn: $state.autoISFsettings.enableBGacceleration) {
                                        Text("Enable BG Acceleration")
                                    }

                                    HStack {
                                        Text("Auto ISF Min")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.autoisf_min,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("Auto ISF Max")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.autoisf_max,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("SMB Delivery Ratio Minimum")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.smbDeliveryRatioMin,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("SMB Delivery Ratio Maximum")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.smbDeliveryRatioMax,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("SMB Delivery Ratio BG Range")
                                        BGTextField(
                                            "0",
                                            mgdlValue: $state.autoISFsettings.smbDeliveryRatioBGrange,
                                            units: $state.units,
                                            isDisabled: false
                                        )
                                    }

                                    HStack {
                                        Text("Auto ISF Hourly Max Change")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.autoISFhourlyChange,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("ISF Weight for higher BGs")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.higherISFrangeWeight,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("ISF Weight for lower BGs")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.lowerISFrangeWeight,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("ISF Weight for postprandial BG rise")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.postMealISFweight,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("ISF Weight while BG accelerates")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.bgAccelISFweight,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("ISF Weight while BG deccelerates")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.bgBrakeISFweight,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    HStack {
                                        Text("Max IOB Threshold Percent")
                                        DecimalTextField(
                                            "0",
                                            value: $state.autoISFsettings.iobThresholdPercent,
                                            formatter: insulinFormatter,
                                            cleanInput: false
                                        )
                                    }

                                    Toggle(isOn: $state.autoISFsettings.use_B30) {
                                        Text("Activate AIMI B30")
                                    }

                                    if state.autoISFsettings.use_B30 {
                                        HStack {
                                            Text("Minimum Start Bolus size")
                                            DecimalTextField(
                                                "0",
                                                value: $state.autoISFsettings.iTime_Start_Bolus,
                                                formatter: insulinFormatter,
                                                cleanInput: false
                                            )
                                        }

                                        HStack {
                                            Text("Target Level for B30 to be enacted")
                                            BGTextField(
                                                "0",
                                                mgdlValue: $state.autoISFsettings.b30targetLevel,
                                                units: $state.units,
                                                isDisabled: false
                                            )
                                        }

                                        HStack {
                                            Text("Upper SMB limit")
                                            BGTextField(
                                                "0",
                                                mgdlValue: $state.autoISFsettings.b30targetLevel,
                                                units: $state.units,
                                                isDisabled: false
                                            )
                                        }

                                        HStack {
                                            Text("Upper Delta SMB limit")
                                            BGTextField(
                                                "0",
                                                mgdlValue: $state.autoISFsettings.b30upperLimit,
                                                units: $state.units,
                                                isDisabled: false
                                            )
                                        }

                                        HStack {
                                            Text("B30 Basal rate increase factor")
                                            DecimalTextField(
                                                "0",
                                                value: $state.autoISFsettings.b30factor,
                                                formatter: insulinFormatter,
                                                cleanInput: false
                                            )
                                        }

                                        HStack {
                                            Text("Duration of increased B30 basal rate")
                                            DecimalTextField(
                                                "0",
                                                value: $state.autoISFsettings.b30_duration,
                                                formatter: insulinFormatter,
                                                cleanInput: false
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
                                                    cleanInput: false
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
                                                        formatter: insulinFormatter,
                                                        cleanInput: false
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Button("Start") {
                            showAlert.toggle()
                            alertSring = "\(state.percentage.formatted(.number)) %, " +
                                (
                                    state.duration > 0 && !state
                                        ._indefinite ?
                                        (
                                            state
                                                .duration
                                                .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                                                " min."
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
                        .alert(
                            "Start Profile",
                            isPresented: $showAlert,
                            actions: {
                                Button("Cancel", role: .cancel) { state.isEnabled = false }
                                Button("Start Profile", role: .destructive) {
                                    if state._indefinite { state.duration = 0 }
                                    state.isEnabled.toggle()
                                    state.saveSettings()
                                    dismiss()
                                }
                            },
                            message: {
                                Text(alertSring)
                            }
                        )
                        Button {
                            isSheetPresented = true
                        }
                        label: { Text("Save as Profile") }
                            .tint(.orange)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(BorderlessButtonStyle())
                            .controlSize(.mini)
                            .disabled(unChanged())
                    }
                    .sheet(isPresented: $isSheetPresented) {
                        presetPopover
                    }
                }

                header: { Text("Insulin") }
                footer: {
                    Text(
                        "Your profile basal insulin will be adjusted with the override percentage and your profile ISF and CR will be inversly adjusted with the percentage."
                    )
                }
                if state.isEnabled {
                    Section {
                        Button("Cancel Profile Override") {
                            state.cancelProfile()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(!state.isEnabled)
                        .tint(.red)
                    } footer: { Text("").padding(.bottom, 150) }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear {
                configureView()
                state.savedSettings()
            }
            .navigationBarTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
        }

        @ViewBuilder private func profilesView(for preset: OverridePresets) -> some View {
            let targetRaw = ((preset.target ?? 0) as NSDecimalNumber) as Decimal
            let target = state.units == .mmolL ? targetRaw.asMmolL : targetRaw
            let duration = (preset.duration ?? 0) as Decimal
            let name = ((preset.name ?? "") == "") || (preset.name?.isEmpty ?? true) ? "" : preset.name!
            let percent = preset.percentage / 100
            let perpetual = preset.indefinite
            let durationString = perpetual ? "" : "\(formatter.string(from: duration as NSNumber)!)"
            let scheduledSMBstring = (preset.smbIsOff && preset.smbIsAlwaysOff) ? "Scheduled SMBs" : ""
            let smbString = (preset.smbIsOff && scheduledSMBstring == "") ? "SMBs are off" : ""
            let targetString = targetRaw > 10 ? "\(glucoseFormatter.string(from: target as NSNumber)!)" : ""
            let maxMinutesSMB = (preset.smbMinutes as Decimal?) != nil ? (preset.smbMinutes ?? 0) as Decimal : 0
            let maxMinutesUAM = (preset.uamMinutes as Decimal?) != nil ? (preset.uamMinutes ?? 0) as Decimal : 0
            let maxIOB = preset.overrideMaxIOB ? (preset.maxIOB ?? 999) as Decimal : 999
            let isfString = preset.isf ? "ISF" : ""
            let crString = preset.cr ? "CR" : ""
            let dash = crString != "" ? "/" : ""
            let isfAndCRstring = isfString + dash + crString
            let autoisfSettings = fetchedSettings.first(where: { $0.id == preset.id })

            if name != "" {
                HStack {
                    VStack(alignment: .leading) {
                        Text(name)
                        HStack(spacing: 5) {
                            Text(percent.formatted(.percent.grouping(.never).rounded().precision(.fractionLength(0))))
                            if targetString != "" {
                                Text(targetString)
                                Text(targetString != "" ? state.units.rawValue : "")
                            }
                            if durationString != "" { Text(durationString + (perpetual ? "" : "min")) }
                            if smbString != "" { Text(smbString).foregroundColor(.secondary).font(.caption) }
                            if scheduledSMBstring != "" { Text(scheduledSMBstring) }
                            if preset.advancedSettings {
                                if !preset.smbIsOff {
                                    Text(maxMinutesSMB == 0 ? "" : maxMinutesSMB.formatted() + " SMB")
                                    Text(maxMinutesUAM == 0 ? "" : maxMinutesUAM.formatted() + " UAM")
                                }
                                Text(maxIOB == 999 ? "" : " Max IOB: " + maxIOB.formatted())
                                Text(isfAndCRstring)
                            }
                            if let settings = autoisfSettings {
                                Text("Auto ISF \(settings.autoisf)")
                            }

                            Spacer()
                        }
                        .padding(.top, 2)
                        .foregroundColor(.secondary)
                        .font(.caption)

                        if let settings = autoisfSettings, settings.autoisf {
                            HStack(spacing: 5) {
                                Text("Accel: \(settings.enableBGacceleration)")
                                Text("Keto: \(settings.ketoProtect)")
                                Text("B30: \(settings.use_B30)")
                                Text("Min/Max: \(settings.autoisf_min ?? 1)/\(settings.autoisf_max ?? 1)")
                            }.foregroundColor(.secondary)
                                .font(.caption)
                            HStack(spacing: 5) {
                                let threshold = (settings.iobThresholdPercent ?? 100) != 100 ?
                                    ", \(settings.iobThresholdPercent ?? 100)%" : ""
                                Text(
                                    "SMB: \(settings.smbDeliveryRatioMin ?? 0.5)/\(settings.smbDeliveryRatioMax ?? 0.5)" +
                                        threshold
                                )
                                let target: Decimal = state.units == .mmolL ? ((settings.smbDeliveryRatioBGrange ?? 8) as Decimal)
                                    .asMmolL : (settings.smbDeliveryRatioBGrange ?? 8) as Decimal
                                Text("SMB Range: " + (glucoseFormatter.string(from: target as NSNumber) ?? ""))
                                Text("PP: \(settings.postMealISFweight ?? 0)")
                            }.foregroundColor(.secondary).font(.caption)
                            HStack(spacing: 5) {
                                Text("lowBG: \(settings.lowerISFrangeWeight ?? 0)")
                                Text("highBG: \(settings.higherISFrangeWeight ?? 0)")
                                if settings.enableBGacceleration {
                                    Text("accel: \(settings.bgAccelISFweight ?? 0)")
                                    Text("brake: \(settings.bgBrakeISFweight ?? 0)")
                                }
                                Text("Dura: \(settings.autoISFhourlyChange ?? 0)")
                            }.foregroundColor(.secondary).font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.selectProfile(id_: preset.id ?? "")
                        state.hideModal()
                    }
                }
            }
        }

        private func unChanged() -> Bool {
            let isChanged = (
                state.percentage == 100 && !state.override_target && !state.smbIsOff && !state
                    .advancedSettings && !state.overrideMaxIOB
            ) ||
                (!state._indefinite && state.duration == 0) || (state.override_target && state.target == 0) ||
                (
                    state.percentage == 100 && !state.override_target && !state.smbIsOff && state.isf && state.cr && state
                        .smbMinutes == state.defaultSmbMinutes && state.uamMinutes == state.defaultUamMinutes && !state
                        .overrideMaxIOB
                )
            return isChanged
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
