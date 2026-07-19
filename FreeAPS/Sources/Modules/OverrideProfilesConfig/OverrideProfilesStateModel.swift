import SwiftUI

extension OverrideProfilesConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var percentage: Double = 100
        @Published var isEnabled = false
        @Published var _indefinite = true
        @Published var duration: Decimal = 0
        @Published var target: Decimal = 0
        @Published var override_target: Bool = false
        @Published var smbIsOff: Bool = false
        @Published var id: String = ""
        @Published var profileName: String = ""
        @Published var isPreset: Bool = false
//        @Published var presets: [OverridePresets] = []
//        @Published var selection: OverridePresets?
        @Published var advancedSettings: Bool = false
        @Published var isfAndCr: Bool = true
        @Published var isf: Bool = true
        @Published var cr: Bool = true
        @Published var basal: Bool = true
        @Published var smbIsAlwaysOff: Bool = false
        @Published var start: Decimal = 0
        @Published var end: Decimal = 23
        @Published var smbMinutes: Decimal = 0
        @Published var uamMinutes: Decimal = 0
        @Published var defaultSmbMinutes: Decimal = 0
        @Published var defaultUamMinutes: Decimal = 0
        @Published var defaultmaxIOB: Decimal = 0
        @Published var emoji: String = ""
        @Published var maxIOB: Decimal = 0
        @Published var overrideMaxIOB: Bool = false
        @Published var endWIthNewCarbs: Bool = false
        @Published var extended_overrides = false
        @Published var overrideAutoISF: Bool = false
        @Published var glucoseOverrideThresholdActive: Bool = false
        @Published var glucoseOverrideThreshold: Decimal = 100
        @Published var glucoseOverrideThresholdActiveDown: Bool = false
        @Published var glucoseOverrideThresholdDown: Decimal = 100

        @Published var currentSettings = AutoISFsettings()

        @Published var autoISFsettings = AutoISFsettings()

        @Injected() private var ns: NightscoutManager!

        @Injected() private var overrideStorage: OverrideStorage!
        @Injected() private var overrideManager: OverrideManager!

        var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            let settings = await settingsManager.settings
            let preferences = await settingsManager.preferences
            units = settings.units
            defaultSmbMinutes = preferences.maxSMBBasalMinutes
            defaultUamMinutes = preferences.maxUAMSMBBasalMinutes
            defaultmaxIOB = preferences.maxIOB
            extended_overrides = settings.extended_overrides
            currentSettings = makeAutoIsfSettings(from: settings)
        }

        func saveSettings() {
            Task {
                percentage.round()

                await overrideManager.cancelActiveOverride()

                // Save
                let overrideId = self.isPreset ? id : UUID().uuidString
                let savedAt = await overrideStorage.storeOverride(currentDraft(id: overrideId))

                if overrideAutoISF {
                    updateAutoISF(overrideId)
                }

                let duration = self.duration == 0 ? 2880 : self.duration
                await ns.uploadOverride(self.percentage.formatted(), Double(duration), savedAt)
            }
        }

        private func currentDraft(id: String, name: String? = nil, emoji: String? = nil) -> OverrideDraft {
            OverrideDraft(
                id: id,
                name: name,
                emoji: emoji,
                isPreset: isPreset,
                duration: duration,
                indefinite: _indefinite,
                percentage: percentage,
                smbIsOff: smbIsOff,
                overrideAutoISF: overrideAutoISF,
                target: override_target ? (units == .mmolL ? target.asMgdL : target) : 6,
                advancedSettings: advancedSettings,
                isfAndCr: isfAndCr,
                isf: isf,
                cr: cr,
                basal: basal,
                smbIsAlwaysOff: smbIsAlwaysOff,
                start: start,
                end: end,
                smbMinutes: smbMinutes,
                uamMinutes: uamMinutes,
                maxIOB: maxIOB,
                overrideMaxIOB: overrideMaxIOB,
                endWIthNewCarbs: endWIthNewCarbs,
                glucoseOverrideThresholdActive: glucoseOverrideThresholdActive,
                glucoseOverrideThreshold: glucoseOverrideThreshold,
                glucoseOverrideThresholdActiveDown: glucoseOverrideThresholdActiveDown,
                glucoseOverrideThresholdDown: glucoseOverrideThresholdDown
            )
        }

        func savePreset() {
            let useId = UUID().uuidString
            isPreset = true
            let draft = currentDraft(id: useId, name: profileName, emoji: emoji)
            Task {
                await overrideStorage.storePreset(draft)

                if overrideAutoISF {
                    updateAutoISF(useId)
                }
            }
        }

        func selectProfile(id_: String) {
            Task {
                guard !id_.isEmpty else { return }

                // Double Check that preset actually still exist in databasa (shouldn't really be necessary)
                let profileArray = await overrideStorage.fetchProfiles()
                guard let profile = profileArray.filter({ $0.id == id_ }).first else { return }

                await overrideManager.cancelActiveOverride()

                let saved = await overrideStorage.activateProfile(profile, id: id_, defaultMaxIOB: defaultmaxIOB)

                // uploads the new override to NS
                await ns.uploadOverride(
                    profile.name ?? "",
                    Double(profile.duration ?? 0),
                    saved.date ?? Date()
                )
            }
        }

        func savedSettings(edit: Bool, identifier: String?) {
            Task {
                let latestOverride = await overrideStorage.fetchLatestOverride()

                if !edit, latestOverride == nil {
                    resetToDefaults()
                    return
                }

                if !edit, !(latestOverride?.enabled ?? false) {
                    resetToDefaults()
                    return
                }
                var editedPreset: OverridePresetsSnapshot?
                if edit {
                    editedPreset = await overrideStorage.fetchPreset(id: identifier ?? "No, I'm sorry.")
                    profileName = editedPreset?.name ?? ""
                }

                // TODO: force unwraps
                percentage = !edit ? latestOverride!.percentage : editedPreset?.percentage ?? 100
                _indefinite = !edit ? latestOverride!.indefinite : editedPreset?.indefinite ?? true
                duration = !edit ? (latestOverride!.duration ?? 0) as Decimal : (editedPreset?.duration ?? 0) as Decimal
                smbIsOff = !edit ? latestOverride!.smbIsOff : editedPreset?.smbIsOff ?? false
                advancedSettings = !edit ? latestOverride!.advancedSettings : editedPreset?.advancedSettings ?? false
                isfAndCr = !edit ? latestOverride!.isfAndCr : editedPreset?.isfAndCr ?? true
                smbIsAlwaysOff = !edit ? latestOverride!.smbIsAlwaysOff : editedPreset?.smbIsAlwaysOff ?? false
                overrideMaxIOB = !edit ? latestOverride!.overrideMaxIOB : editedPreset?.overrideMaxIOB ?? false
                overrideAutoISF = !edit ? latestOverride!.overrideAutoISF : editedPreset?.overrideAutoISF ?? false
                endWIthNewCarbs = !edit ? latestOverride!.endWIthNewCarbs : editedPreset?.endWIthNewCarbs ?? false
                glucoseOverrideThresholdActive = !edit ? latestOverride!.glucoseOverrideThresholdActive : editedPreset?
                    .glucoseOverrideThresholdActive ?? false
                glucoseOverrideThresholdActiveDown = !edit ? latestOverride!.glucoseOverrideThresholdActiveDown : editedPreset?
                    .glucoseOverrideThresholdActiveDown ?? false

                if glucoseOverrideThresholdActive {
                    glucoseOverrideThreshold = !edit ? (latestOverride?.glucoseOverrideThreshold ?? 100) as Decimal :
                        (editedPreset?.glucoseOverrideThreshold ?? 100) as Decimal
                }

                if glucoseOverrideThresholdActiveDown {
                    glucoseOverrideThresholdDown = !edit ? (latestOverride?.glucoseOverrideThresholdDown ?? 100) as Decimal :
                        (editedPreset?.glucoseOverrideThresholdDown ?? 100) as Decimal
                }

                isf = !edit ? latestOverride!.isf : editedPreset?.isf ?? true
                cr = !edit ? latestOverride!.cr : editedPreset?.cr ?? true
                basal = !edit ? latestOverride!.basal : editedPreset?.basal ?? true

                if smbIsAlwaysOff {
                    start = !edit ? (latestOverride!.start ?? 0) as Decimal : (editedPreset?.start ?? 0) as Decimal
                    end = !edit ? (latestOverride!.end ?? 0) as Decimal : (editedPreset?.end ?? 0) as Decimal
                }

                if !edit, (latestOverride!.smbMinutes as Decimal?) != nil {
                    smbMinutes = (latestOverride!.smbMinutes ?? defaultSmbMinutes) as Decimal
                } else if edit {
                    smbMinutes = (latestOverride?.smbMinutes ?? defaultSmbMinutes) as Decimal
                }

                if !edit, (latestOverride!.uamMinutes as Decimal?) != nil {
                    uamMinutes = (latestOverride!.uamMinutes ?? defaultUamMinutes) as Decimal
                } else if edit {
                    uamMinutes = (latestOverride?.uamMinutes ?? defaultUamMinutes) as Decimal
                }

                if !edit, let maxIOB_ = latestOverride!.maxIOB as Decimal? {
                    maxIOB = maxIOB_ as Decimal
                } else if edit, let maxIOB_ = editedPreset?.maxIOB as Decimal? {
                    maxIOB = maxIOB_ as Decimal
                }

                let aisf = !edit && (latestOverride?.enabled ?? false) ? await overrideStorage
                    .fetchAutoISFsetting(id: latestOverride?.id ?? "No, I'm very sorry.") : edit ? await overrideStorage
                    .fetchAutoISFsetting(id: identifier ?? "No, I'm very sorry.") : nil

                if let fetched = aisf {
                    autoISFsettings = fetch(fetched: fetched)
                } else {
                    autoISFsettings = currentSettings
                }

                if !edit {
                    override_target = (Double(latestOverride!.target ?? 0) > 6.0)
                } else {
                    override_target = (Double(editedPreset?.target ?? 0) > 6.0)
                }
                let overrideTarget = !edit ? (latestOverride!.target ?? 0) as Decimal : (editedPreset?.target ?? 0) as Decimal
                if override_target {
                    target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
                }

                var newDuration = Double(duration)
                if isEnabled {
                    let duration = !edit ? latestOverride!.duration ?? 0 : editedPreset?.duration ?? 0
                    let addedMinutes = Int(duration as Decimal)
                    let date = !edit ? latestOverride!.date ?? Date() : editedPreset?.date ?? Date()
                    if date.addingTimeInterval(.minutes(addedMinutes)) < Date(), !_indefinite {
                        isEnabled = false
                    }
                    newDuration = Date().distance(to: date.addingTimeInterval(.minutes(addedMinutes))).minutes
                }
                if newDuration < 0 { newDuration = 0 } else { duration = Decimal(newDuration) }
            }
        }

        func cancelProfile() {
            Task {
                resetToDefaults()
                await overrideManager.cancelActiveOverride()
            }
        }

        private func resetToDefaults() {
            _indefinite = true
            percentage = 100
            duration = 0
            target = units == .mmolL ? 5 : 100
            override_target = false
            smbIsOff = false
            advancedSettings = false
            isfAndCr = true
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
            maxIOB = defaultmaxIOB
            overrideMaxIOB = false
            overrideAutoISF = false
            endWIthNewCarbs = false
            glucoseOverrideThresholdActive = false
            glucoseOverrideThreshold = 100
            glucoseOverrideThresholdActiveDown = false
            glucoseOverrideThresholdDown = 90

            autoISFsettings = currentSettings
        }

        // Save Auto ISF Override settings
        func updateAutoISF(_ identifier: String?) {
            guard let identifier else { return }
            Task {
                await overrideStorage.createOrUpdateAutoISF(id: identifier, autoISFsettings: autoISFsettings)
            }
        }

        private func makeAutoIsfSettings(from settings: FreeAPSSettings) -> AutoISFsettings {
            AutoISFsettings(
                autoisf: settings.autoisf,
                autocr: settings.autocr,
                smbDeliveryRatioBGrange: settings.smbDeliveryRatioBGrange as Decimal,
                smbDeliveryRatioMin: settings.smbDeliveryRatioMin as Decimal,
                smbDeliveryRatioMax: settings.smbDeliveryRatioMax as Decimal,
                autoISFhourlyChange: settings.autoISFhourlyChange as Decimal,
                higherISFrangeWeight: settings.higherISFrangeWeight as Decimal,
                lowerISFrangeWeight: settings.lowerISFrangeWeight as Decimal,
                postMealISFweight: settings.postMealISFweight as Decimal,
                enableBGacceleration: settings.enableBGacceleration,
                bgAccelISFweight: settings.bgAccelISFweight as Decimal,
                bgBrakeISFweight: settings.bgBrakeISFweight as Decimal,
                iobThresholdPercent: settings.iobThresholdPercent as Decimal,
                autoisf_max: settings.autoisf_max as Decimal,
                autoisf_min: settings.autoisf_min as Decimal,
                use_B30: settings.use_B30,
                iTime_Start_Bolus: settings.iTime_Start_Bolus as Decimal,
                b30targetLevel: settings.b30targetLevel as Decimal,
                b30upperLimit: settings.b30upperLimit as Decimal,
                b30upperdelta: settings.b30upperdelta as Decimal,
                b30factor: settings.b30factor as Decimal,
                b30_duration: settings.b30_duration as Decimal,
                ketoProtect: settings.ketoProtect,
                variableKetoProtect: settings.variableKetoProtect,
                ketoProtectBasalPercent: settings.ketoProtectBasalPercent as Decimal,
                ketoProtectAbsolut: settings.ketoProtectAbsolut,
                ketoProtectBasalAbsolut: settings.ketoProtectBasalAbsolut as Decimal,
                id: "",
                nightTime: settings.nightTime as NightTimeConfiguration
            )
        }

        private func fetch(fetched: Auto_ISFSnapshot) -> AutoISFsettings {
            AutoISFsettings(
                autoisf: fetched.autoisf,
                autocr: fetched.autocr,
                smbDeliveryRatioBGrange: fetched.smbDeliveryRatioBGrange ?? 0,
                smbDeliveryRatioMin: fetched.smbDeliveryRatioMin ?? 0,
                smbDeliveryRatioMax: fetched.smbDeliveryRatioMax ?? 0,
                autoISFhourlyChange: fetched.autoISFhourlyChange ?? 0,
                higherISFrangeWeight: fetched.higherISFrangeWeight ?? 0,
                lowerISFrangeWeight: fetched.lowerISFrangeWeight ?? 0,
                postMealISFweight: fetched.postMealISFweight ?? 0,
                enableBGacceleration: fetched.enableBGacceleration,
                bgAccelISFweight: fetched.bgAccelISFweight ?? 0,
                bgBrakeISFweight: fetched.bgBrakeISFweight ?? 0,
                iobThresholdPercent: fetched.iobThresholdPercent ?? 0,
                autoisf_max: fetched.autoisf_max ?? 0,
                autoisf_min: fetched.autoisf_min ?? 0,
                use_B30: fetched.use_B30,
                iTime_Start_Bolus: fetched.iTime_Start_Bolus ?? 1.5,
                b30targetLevel: fetched.b30targetLevel ?? 80,
                b30upperLimit: fetched.b30upperLimit ?? 140,
                b30upperdelta: fetched.b30upperdelta ?? 8,
                b30factor: fetched.b30factor ?? 5,
                b30_duration: fetched.b30_duration ?? 30,
                ketoProtect: fetched.ketoProtect,
                variableKetoProtect: fetched.variableKetoProtect,
                ketoProtectBasalPercent: fetched.ketoProtectBasalPercent ?? 0,
                ketoProtectAbsolut: fetched.ketoProtectAbsolut,
                ketoProtectBasalAbsolut: fetched.ketoProtectBasalAbsolut ?? 0.2,
                id: fetched.id ?? "",
                nightTime: fetched.nightTime?.value ?? .default
            )
        }
    }
}
