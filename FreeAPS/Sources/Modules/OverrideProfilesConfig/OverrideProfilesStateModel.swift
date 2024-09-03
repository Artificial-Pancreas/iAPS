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

        @Injected() var broadcaster: Broadcaster!
        @Injected() var ns: NightscoutManager!

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            defaultmaxIOB = settingsManager.preferences.maxIOB

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

            coredataContext.perform { [self] in
                let saveOverride = Override(context: self.coredataContext)
                saveOverride.duration = self.duration as NSDecimalNumber
                saveOverride.indefinite = self._indefinite
                saveOverride.percentage = self.percentage
                saveOverride.enabled = true
                saveOverride.smbIsOff = self.smbIsOff
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
                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = isf
                        saveOverride.cr = cr
                    } else { saveOverride.isfAndCr = true }
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

                if advancedSettings {
                    saveOverride.advancedSettings = true
                    if !isfAndCr {
                        saveOverride.isfAndCr = false
                        saveOverride.isf = isf
                        saveOverride.cr = cr
                    } else { saveOverride.isfAndCr = true }
                    if smbIsAlwaysOff {
                        saveOverride.smbIsAlwaysOff = true
                        saveOverride.start = start as NSDecimalNumber
                        saveOverride.end = end as NSDecimalNumber
                    } else { smbIsAlwaysOff = false }

                    saveOverride.smbMinutes = smbMinutes as NSDecimalNumber
                    saveOverride.uamMinutes = uamMinutes as NSDecimalNumber
                    saveOverride.maxIOB = maxIOB as NSDecimalNumber
                    saveOverride.overrideMaxIOB = overrideMaxIOB
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

            if let tar = profile.target, tar == 0 {
                saveOverride.target = 6
            } else {
                saveOverride.target = profile.target
            }

            if profile.advancedSettings {
                saveOverride.advancedSettings = true
                if !isfAndCr {
                    saveOverride.isfAndCr = false
                    saveOverride.isf = profile.isf
                    saveOverride.cr = profile.cr
                } else { saveOverride.isfAndCr = true }
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
        }
    }
}
