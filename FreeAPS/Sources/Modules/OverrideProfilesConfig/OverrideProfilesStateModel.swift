import CoreData
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
        @Published var presets: [OverridePresets] = []
        @Published var selection: OverridePresets?
        @Published var advancedSettings: Bool = false
        @Published var isfAndCr: Bool = true
        @Published var isf: Bool = true
        @Published var cr: Bool = true
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
        @Published var extended_overrides = false
        @Published var overrideAutoISF: Bool = false

        @Published var autoISFsettings = AutoISFsettings()

        @Injected() var broadcaster: Broadcaster!
        @Injected() var ns: NightscoutManager!

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            defaultmaxIOB = settingsManager.preferences.maxIOB
            extended_overrides = settingsManager.settings.extended_overrides

            presets = [OverridePresets(context: coredataContext)]
        }

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        func saveSettings() {
            // Is other override already active?
            let last = OverrideStorage().fetchLatestOverride().last

            // Is other already active?
            if let active = last, active.enabled {
                if let preset = OverrideStorage().isPresetName(), let duration = OverrideStorage().cancelProfile() {
                    ns.editOverride(preset, duration, last?.date ?? Date.now)
                } else if let duration = OverrideStorage().cancelProfile() {
                    let nsString = active.percentage.formatted() != "100" ? active.percentage
                        .formatted() + " %" : active.isPreset ? "📉" : "Custom"
                    ns.editOverride(nsString, duration, last?.date ?? Date.now)
                }
            }
            // Save
            coredataContext.perform { [self] in
                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.enabled = true
                saveOverride.smbIsOff = self.smbIsOff
                saveOverride.overrideAutoISF = self.overrideAutoISF
                if self.isPreset {
                    saveOverride.isPreset = true
                    saveOverride.id = id
                } else { saveOverride.isPreset = false }
                saveOverride.date = Date()
                if override_target {
                    saveOverride.target = (
                        units == .mmolL
                            ? target.asMgdL
                            : target
                    ) as NSDecimalNumber
                } else { saveOverride.target = 6 }
                if advancedSettings {
                    saveOverride.advancedSettings = true
                    saveOverride.isfAndCr = isfAndCr
                    if !isfAndCr {
                        saveOverride.isf = isf
                        saveOverride.cr = cr
                    }
                    if smbIsAlwaysOff {
                        saveOverride.smbIsAlwaysOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { saveOverride.smbIsAlwaysOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                    saveOverride.maxIOB = maxIOB as NSDecimalNumber
                    saveOverride.overrideMaxIOB = overrideMaxIOB
                }

                if self.overrideAutoISF {
                    self.updateAutoISF(nil)
                }

                let duration = (self.duration as NSDecimalNumber) == 0 ? 2880 : Int(self.duration as NSDecimalNumber)
                ns.uploadOverride(self.percentage.formatted(), Double(duration), saveOverride.date ?? Date.now)

                try? self.coredataContext.save()
            }
        }

        func savePreset() {
            coredataContext.perform { [self] in
                let saveOverride = OverridePresets(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.smbIsOff = self.smbIsOff
                saveOverride.name = self.profileName
                saveOverride.emoji = self.emoji
                saveOverride.overrideAutoISF = self.overrideAutoISF
                id = UUID().uuidString
                self.isPreset = true
                saveOverride.id = id
                saveOverride.date = Date()
                if override_target {
                    saveOverride.target = (
                        units == .mmolL
                            ? target.asMgdL
                            : target
                    ) as NSDecimalNumber
                } else { saveOverride.target = 6 }

                if self.advancedSettings {
                    saveOverride.advancedSettings = true
                    saveOverride.isfAndCr = self.isfAndCr
                    if !isfAndCr {
                        saveOverride.isf = self.isf
                        saveOverride.cr = self.cr
                    }
                    if smbIsAlwaysOff {
                        saveOverride.smbIsAlwaysOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { smbIsAlwaysOff = false }

                    saveOverride.smbMinutes = self.smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = self.uamMinutes as NSDecimalNumber
                    saveOverride.maxIOB = maxIOB as NSDecimalNumber
                    saveOverride.overrideMaxIOB = self.overrideMaxIOB
                }

                if self.overrideAutoISF {
                    self.updateAutoISF(id)
                }

                try? self.coredataContext.save()
            }
        }

        func selectProfile(id_: String) {
            guard !id_.isEmpty else { return }

            // Double Check that preset actually still exist in databasa (shouldn't really be necessary)
            let profileArray = OverrideStorage().fetchProfiles()
            guard let profile = profileArray.filter({ $0.id == id_ }).first else { return }

            // Is there already an active override?
            let last = OverrideStorage().fetchLatestOverride().last
            let lastPreset = OverrideStorage().isPresetName()
            if let alreadyActive = last, alreadyActive.enabled, let duration = OverrideStorage().cancelProfile() {
                ns.editOverride(
                    (last?.isPreset ?? false) ? (lastPreset ?? "📉") : "Custom",
                    duration,
                    alreadyActive.date ?? Date.now
                )
            }
            // New Override properties
            let saveOverride = Override(context: coredataContext)
            saveOverride.duration = (profile.duration ?? 0) as NSDecimalNumber
            saveOverride.indefinite = profile.indefinite
            saveOverride.percentage = profile.percentage
            saveOverride.enabled = true
            saveOverride.smbIsOff = profile.smbIsOff
            saveOverride.isPreset = true
            saveOverride.date = Date()
            saveOverride.id = id_
            saveOverride.advancedSettings = profile.advancedSettings
            saveOverride.isfAndCr = profile.isfAndCr
            saveOverride.overrideAutoISF = profile.overrideAutoISF

            if let tar = profile.target, tar == 0 {
                saveOverride.target = 6
            } else {
                saveOverride.target = profile.target
            }

            if profile.advancedSettings {
                if !profile.isfAndCr {
                    saveOverride.isf = profile.isf
                    saveOverride.cr = profile.cr
                }
                if profile.smbIsAlwaysOff {
                    saveOverride.smbIsAlwaysOff = true
                    saveOverride.start = profile.start
                    saveOverride.end = profile.end
                } else { saveOverride.smbIsAlwaysOff = false }

                saveOverride.smbMinutes = (profile.smbMinutes ?? 0) as NSDecimalNumber
                saveOverride.uamMinutes = (profile.uamMinutes ?? 0) as NSDecimalNumber
                saveOverride.maxIOB = (profile.maxIOB ?? defaultmaxIOB as NSDecimalNumber) as NSDecimalNumber
                saveOverride.overrideMaxIOB = profile.overrideMaxIOB
            }

            // Saves
            coredataContext.perform { try? self.coredataContext.save() }

            // Uploads new Override to NS
            ns.uploadOverride(profile.name ?? "", Double(saveOverride.duration ?? 0), saveOverride.date ?? Date())
        }

        func savedSettings() {
            guard let overrideArray = OverrideStorage().fetchLatestOverride().first else {
                defaults()
                return
            }
            isEnabled = overrideArray.enabled
            percentage = overrideArray.percentage
            _indefinite = overrideArray.indefinite
            duration = (overrideArray.duration ?? 0) as Decimal
            smbIsOff = overrideArray.smbIsOff
            advancedSettings = overrideArray.advancedSettings
            isfAndCr = overrideArray.isfAndCr
            smbIsAlwaysOff = overrideArray.smbIsAlwaysOff
            overrideMaxIOB = overrideArray.overrideMaxIOB
            overrideAutoISF = overrideArray.overrideAutoISF

            if advancedSettings {
                if !isfAndCr {
                    isf = overrideArray.isf
                    cr = overrideArray.cr
                }
                if smbIsAlwaysOff {
                    start = (overrideArray.start ?? 0) as Decimal
                    end = (overrideArray.end ?? 0) as Decimal
                }

                if (overrideArray.smbMinutes as Decimal?) != nil {
                    smbMinutes = (overrideArray.smbMinutes ?? 30) as Decimal
                }

                if (overrideArray.uamMinutes as Decimal?) != nil {
                    uamMinutes = (overrideArray.uamMinutes ?? 30) as Decimal
                }

                if let maxIOB_ = overrideArray.maxIOB as Decimal? {
                    maxIOB = maxIOB_ as Decimal
                }
            }

            if overrideAutoISF {
                if let fetched = OverrideStorage().fetchLatestAutoISFsettings().first {
                    autoISFsettings = AutoISFsettings(
                        autoisf: fetched.autoisf,
                        smbDeliveryRatioBGrange: (fetched.smbDeliveryRatioBGrange ?? 0) as Decimal,
                        smbDeliveryRatioMin: (fetched.smbDeliveryRatioMin ?? 0) as Decimal,
                        smbDeliveryRatioMax: (fetched.smbDeliveryRatioMax ?? 0) as Decimal,
                        autoISFhourlyChange: (fetched.autoISFhourlyChange ?? 0) as Decimal,
                        higherISFrangeWeight: (fetched.higherISFrangeWeight ?? 0) as Decimal,
                        lowerISFrangeWeight: (fetched.lowerISFrangeWeight ?? 0) as Decimal,
                        postMealISFweight: (fetched.postMealISFweight ?? 0) as Decimal,
                        enableBGacceleration: fetched.enableBGacceleration,
                        bgAccelISFweight: (fetched.bgAccelISFweight ?? 0) as Decimal,
                        bgBrakeISFweight: (fetched.bgBrakeISFweight ?? 0) as Decimal,
                        iobThresholdPercent: (fetched.iobThresholdPercent ?? 0) as Decimal,
                        autoisf_max: (fetched.autoisf_max ?? 0) as Decimal,
                        autoisf_min: (fetched.autoisf_min ?? 0) as Decimal,
                        use_B30: fetched.use_B30,
                        iTime_Start_Bolus: (fetched.iTime_Start_Bolus ?? 1.5) as Decimal,
                        b30targetLevel: (fetched.b30targetLevel ?? 80) as Decimal,
                        b30upperLimit: (fetched.b30upperLimit ?? 140) as Decimal,
                        b30upperdelta: (fetched.b30upperdelta ?? 8) as Decimal,
                        b30factor: (fetched.b30factor ?? 5) as Decimal,
                        b30_duration: (fetched.b30_duration ?? 30) as Decimal,
                        ketoProtect: fetched.ketoProtect,
                        variableKetoProtect: fetched.variableKetoProtect,
                        ketoProtectBasalPercent: (fetched.ketoProtectBasalPercent ?? 0) as Decimal,
                        ketoProtectAbsolut: fetched.ketoProtectAbsolut,
                        ketoProtectBasalAbsolut: (fetched.ketoProtectBasalAbsolut ?? 0.2) as Decimal,
                        id: fetched.id ?? ""
                    )
                }
            }

            let overrideTarget = (overrideArray.target ?? 0) as Decimal
            var newDuration = Double(duration)
            if isEnabled {
                let duration = overrideArray.duration ?? 0
                let addedMinutes = Int(duration as Decimal)
                let date = overrideArray.date ?? Date()
                if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(), !_indefinite {
                    isEnabled = false
                }
                newDuration = Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes
                if override_target {
                    target = units == .mmolL ? overrideTarget.asMmolL : overrideTarget
                }
            }
            if newDuration < 0 { newDuration = 0 } else { duration = Decimal(newDuration) }

            if !isEnabled { defaults() }
        }

        func cancelProfile() {
            defaults()
            let storage = OverrideStorage()
            let duration_ = storage.cancelProfile()
            let last_ = storage.fetchLatestOverride().last
            let name = storage.isPresetName()
            if let last = last_, let duration = duration_ {
                ns.editOverride(name ?? "", duration, last.date ?? Date.now)
            }
        }

        private func defaults() {
            _indefinite = true
            percentage = 100
            duration = 0
            target = 0
            override_target = false
            smbIsOff = false
            advancedSettings = false
            isfAndCr = true
            smbMinutes = defaultSmbMinutes
            uamMinutes = defaultUamMinutes
            maxIOB = defaultmaxIOB
            overrideMaxIOB = false
            overrideAutoISF = false

            let settings = settingsManager.settings

            autoISFsettings = AutoISFsettings(
                autoisf: settings.autoisf,
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
                id: ""
            )
        }

        // Save Auto ISF Override settings
        private func updateAutoISF(_ id_: String?) {
            coredataContext.perform { [self] in
                let saveAutoISF = Auto_ISF(context: coredataContext)
                saveAutoISF.autoISFhourlyChange = autoISFsettings.autoISFhourlyChange as NSDecimalNumber
                saveAutoISF.autoisf = autoISFsettings.autoisf
                saveAutoISF.autoisf_min = autoISFsettings.autoisf_min as NSDecimalNumber
                saveAutoISF.autoisf_max = autoISFsettings.autoisf_max as NSDecimalNumber
                saveAutoISF.enableBGacceleration = autoISFsettings.enableBGacceleration
                saveAutoISF.bgAccelISFweight = autoISFsettings.bgAccelISFweight as NSDecimalNumber
                saveAutoISF.bgBrakeISFweight = autoISFsettings.bgBrakeISFweight as NSDecimalNumber
                saveAutoISF.lowerISFrangeWeight = autoISFsettings.lowerISFrangeWeight as NSDecimalNumber
                saveAutoISF.higherISFrangeWeight = autoISFsettings.higherISFrangeWeight as NSDecimalNumber
                saveAutoISF.iTime_Start_Bolus = autoISFsettings.iTime_Start_Bolus as NSDecimalNumber
                saveAutoISF.iTime_target = autoISFsettings.iTime_target as NSDecimalNumber
                saveAutoISF.use_B30 = autoISFsettings.use_B30
                saveAutoISF.b30_duration = autoISFsettings.b30_duration as NSDecimalNumber
                saveAutoISF.b30factor = autoISFsettings.b30factor as NSDecimalNumber
                saveAutoISF.b30targetLevel = autoISFsettings.b30targetLevel as NSDecimalNumber
                saveAutoISF.b30upperLimit = autoISFsettings.b30upperLimit as NSDecimalNumber
                saveAutoISF.b30upperdelta = autoISFsettings.b30upperdelta as NSDecimalNumber
                saveAutoISF.iobThresholdPercent = autoISFsettings.iobThresholdPercent as NSDecimalNumber
                saveAutoISF.ketoProtect = autoISFsettings.ketoProtect
                saveAutoISF.ketoProtectAbsolut = autoISFsettings.ketoProtectAbsolut
                saveAutoISF.ketoProtectBasalAbsolut = autoISFsettings.ketoProtectBasalAbsolut as NSDecimalNumber
                saveAutoISF.variableKetoProtect = autoISFsettings.variableKetoProtect
                saveAutoISF.ketoProtectBasalPercent = autoISFsettings.ketoProtectBasalPercent as NSDecimalNumber
                saveAutoISF.smbDeliveryRatioMin = autoISFsettings.smbDeliveryRatioMin as NSDecimalNumber
                saveAutoISF.smbDeliveryRatioMax = autoISFsettings.smbDeliveryRatioMax as NSDecimalNumber
                saveAutoISF.smbDeliveryRatioBGrange = autoISFsettings.smbDeliveryRatioBGrange as NSDecimalNumber
                saveAutoISF.postMealISFweight = autoISFsettings.postMealISFweight as NSDecimalNumber
                saveAutoISF.date = Date.now

                // ID here managed different depending on preset or custom override. To do: refactor this later
                if let isId = id_ { saveAutoISF.id = isId } else { saveAutoISF.id = id }

                try? self.coredataContext.save()
            }
        }
    }
}
