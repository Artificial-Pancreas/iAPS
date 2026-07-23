import SwiftUI

extension OverrideProfilesConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var ns: NightscoutManager!
        @Injected() private var overrideStorage: OverrideStorage!
        @Injected() private var overrideManager: OverrideManager!

        @Published var profiles: [OverridePresetsSnapshot] = []

        @Published var form = OverrideForm()

        @Published var isOverrideActive = false

        @Published var currentAutoIsfSettings = AutoISFsettings()
        @Published var defaultSmbMinutes: Decimal = 0
        @Published var defaultUamMinutes: Decimal = 0
        @Published var defaultmaxIOB: Decimal = 0
        @Published var extended_overrides = false
        var units: GlucoseUnits = .mmolL

        var context: OverrideForm.Context {
            OverrideForm.Context(
                units: units,
                extendedOverrides: extended_overrides,
                defaultSmbMinutes: defaultSmbMinutes,
                defaultUamMinutes: defaultUamMinutes,
                defaultMaxIOB: defaultmaxIOB,
                currentAutoIsfSettings: currentAutoIsfSettings
            )
        }

        override func subscribe() async {
            let settings = appCoordinator.settings.value
            let preferences = appCoordinator.preferences.value

            units = settings.units
            extended_overrides = settings.extended_overrides
            defaultSmbMinutes = preferences.maxSMBBasalMinutes
            defaultUamMinutes = preferences.maxUAMSMBBasalMinutes
            defaultmaxIOB = preferences.maxIOB
            currentAutoIsfSettings = makeAutoIsfSettings(from: settings)

            await fetchOverridePresets()

            if let activeOverride = await overrideStorage.fetchCurrentActiveOverride() {
                isOverrideActive = true
                form = OverrideForm(from: activeOverride.toOverridePreset, context: context)
            } else {
                isOverrideActive = false
                form = OverrideForm.defaults(context: context)
            }
        }

        private func fetchOverridePresets() async {
            profiles = await overrideStorage.fetchOverridePresets().uniqued(on: \.id)
        }

        /// Start a new custom override or replace the active one - from the main form.
        func startOverride() {
            var draftForm = form
            if draftForm._indefinite { draftForm.duration = 0 }
            let draft = draftForm.snapshot(id: UUID().uuidString, name: nil, emoji: nil, context: context)

            Task {
                await overrideManager.cancelActiveOverride()
                guard let activated = await overrideStorage.activateOverrideFromPreset(
                    preset: draft,
                    fromSavedPreset: false
                ) else { return }
                isOverrideActive = true

                let duration = activated.duration == 0 ? 2880 : (activated.duration ?? 0)
                await ns.uploadOverride(activated.percentage.formatted(), Double(duration), Date.now)
            }
        }

        /// Activate a saved preset directly (tapping it in the list).
        func activateOverrideFromPreset(_ preset: OverridePresetsSnapshot) {
            Task {
                await overrideManager.cancelActiveOverride()
                guard let saved = await overrideStorage.activateOverrideFromPreset(
                    preset: preset,
                    fromSavedPreset: true,
                    defaultMaxIOB: defaultmaxIOB
                ) else { return }

                await ns.uploadOverride(
                    preset.name ?? "",
                    Double(preset.duration ?? 0),
                    saved.date ?? Date()
                )
            }
        }

        func cancelActiveOverride() {
            isOverrideActive = false
            form = OverrideForm.defaults(context: context)
            Task {
                await overrideManager.cancelActiveOverride()
            }
        }

        /// Save the current main form as a NEW preset.
        func saveAsNewPreset(name: String) {
            let draft = form.snapshot(id: UUID().uuidString, name: name, emoji: nil, context: context)
            Task {
                await overrideStorage.storeOverridePreset(draft)
                await fetchOverridePresets()
            }
        }

        /// Update an existing preset from its own isolated editor buffer. Does NOT touch `form`.
        func updatePreset(id: String, name: String, emoji: String?, form presetForm: OverrideForm) {
            let draft = presetForm.snapshot(id: id, name: name, emoji: emoji, context: context)
            Task {
                await overrideStorage.updateOverridePreset(draft)
                await fetchOverridePresets()
            }
        }

        func deleteProfile(at offsets: IndexSet) {
            let idsToDelete = Array(offsets).map { index in profiles[index].id }
            Task {
                await overrideStorage.deleteOverridePresets(ids: idsToDelete)
                await fetchOverridePresets()
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
    }
}
