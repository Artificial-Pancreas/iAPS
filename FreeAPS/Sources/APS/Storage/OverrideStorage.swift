import Combine
import CoreData
import Foundation
import SwiftDate

final class OverrideStorage: Sendable {
    private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
    private let appCoordinator: AppCoordinator

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }

    func fetchOverrides(interval: NSDate) async -> [OverrideSnapshot] {
        await coredataContext.perform {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "date > %@", interval
            )
            let overrideArray = (try? self.coredataContext.fetch(requestOverrides)) ?? []
            return overrideArray.map { OverrideSnapshot.create(from: $0) }
        }
    }

    private func latestOverrideRequest() -> NSFetchRequest<Override> {
        let request = Override.fetchRequest() as NSFetchRequest<Override>
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = 1
        return request
    }

    func fetchLatestOverride() async -> OverrideSnapshot? {
        await coredataContext.perform {
            let request = self.latestOverrideRequest()
            let override = try? self.coredataContext.fetch(request).first
            return override.map { OverrideSnapshot.create(from: $0) }
        }
    }

    func fetchCurrentActiveOverride() async -> OverrideSnapshot? {
        guard let override = await fetchLatestOverride(), override.enabled else { return nil }
        return override
    }

    func fetchPreset(id: String) async -> OverridePresetsSnapshot? {
        await coredataContext.perform {
            let requestOverrides = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "id == %@", id as String
            )
            let overrideArray = try? self.coredataContext.fetch(requestOverrides)
            return overrideArray?.first.map { OverridePresetsSnapshot.create(from: $0) }
        }
    }

    func fetchLatestAutoISFsettings() async -> [Auto_ISFSnapshot] {
        await coredataContext.perform {
            let request = Auto_ISF.fetchRequest() as NSFetchRequest<Auto_ISF>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            request.sortDescriptors = [sort]
            request.fetchLimit = 1
            let array = (try? self.coredataContext.fetch(request)) ?? []
            return array.map { Auto_ISFSnapshot.create(from: $0) }
        }
    }

    private func fetchAutoISFsettingRaw(id: String) -> Auto_ISF? {
        let request = Auto_ISF.fetchRequest() as NSFetchRequest<Auto_ISF>
        request.predicate = NSPredicate(
            format: "id == %@", id as String
        )
        let array = (try? coredataContext.fetch(request)) ?? []
        return array.first
    }

    func fetchAutoISFsetting(id: String) async -> Auto_ISFSnapshot? {
        await coredataContext.perform {
            let raw = self.fetchAutoISFsettingRaw(id: id)
            return raw.map { Auto_ISFSnapshot.create(from: $0) }
        }
    }

    func createOrUpdateAutoISF(id identifier: String, autoISFsettings: AutoISFsettings) async {
        await coredataContext.perform {
            let oldObject = self.fetchAutoISFsettingRaw(id: identifier)
            let saveAutoISF = oldObject ?? Auto_ISF(context: self.coredataContext)

            saveAutoISF.autoISFhourlyChange = autoISFsettings.autoISFhourlyChange as NSDecimalNumber
            saveAutoISF.autoisf = autoISFsettings.autoisf
            saveAutoISF.autocr = autoISFsettings.autocr
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
            if oldObject == nil { saveAutoISF.id = identifier }
            try? self.coredataContext.save()
        }
        appCoordinator.overridesDidChange()
    }

    func fetchOverrideHistory(interval: NSDate) async -> [OverrideHistorySnapshot] {
        await coredataContext.perform {
            let requestOverrides = OverrideHistory.fetchRequest() as NSFetchRequest<OverrideHistory>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "date > %@", interval
            )
            let overrideArray = (try? self.coredataContext.fetch(requestOverrides)) ?? []
            return overrideArray.map { OverrideHistorySnapshot.create(from: $0) }
        }
    }

    func cancelProfile() async -> Double? {
        let scheduled = await fetchLatestOverride()
        let duration: Double? = await coredataContext.perform {
            var duration: Double?

            let profiles = Override(context: self.coredataContext)
            let history = OverrideHistory(context: self.coredataContext)
            if let latest = scheduled {
                history.duration = -1 * (latest.date ?? Date()).timeIntervalSinceNow.minutes
                history.date = latest.date ?? Date()
                // Looks better in Home View Main Chart when target isn't == 0.
                if Double(latest.target ?? 100) < 6 {
                    history.target = 6
                } else { history.target = Double(latest.target ?? 100) }
                duration = history.duration
            }
            profiles.enabled = false
            profiles.date = Date()
            try? self.coredataContext.save()

            return duration
        }
        appCoordinator.overridesDidChange()
        return duration
    }

    func overrideFromPreset(_ preset: OverridePresetsSnapshot) async -> OverrideSnapshot {
        let saved = await coredataContext.perform {
            let save = Override(context: self.coredataContext)
            save.date = Date.now
            save.id = preset.id
            save.end = preset.end as? NSDecimalNumber
            save.start = preset.start as? NSDecimalNumber
            save.advancedSettings = preset.advancedSettings
            save.cr = preset.cr
            save.duration = preset.duration as? NSDecimalNumber
            save.enabled = true
            save.indefinite = preset.indefinite
            save.isPreset = true
            save.isf = preset.isf
            save.basal = preset.basal
            save.isfAndCr = preset.isfAndCr
            save.percentage = preset.percentage
            save.smbIsAlwaysOff = preset.smbIsAlwaysOff
            save.smbIsOff = preset.smbIsOff
            save.smbMinutes = preset.smbMinutes as? NSDecimalNumber
            save.uamMinutes = preset.uamMinutes as? NSDecimalNumber
            save.maxIOB = preset.maxIOB as? NSDecimalNumber
            save.target = preset.target as? NSDecimalNumber
            save.overrideMaxIOB = preset.overrideMaxIOB
            save.overrideAutoISF = preset.overrideAutoISF
            save.endWIthNewCarbs = preset.endWIthNewCarbs
            save.glucoseOverrideThresholdActive = preset.glucoseOverrideThresholdActive
            save.glucoseOverrideThreshold = preset.glucoseOverrideThreshold as? NSDecimalNumber
            save.glucoseOverrideThresholdActiveDown = preset.glucoseOverrideThresholdActiveDown
            save.glucoseOverrideThresholdDown = preset.glucoseOverrideThresholdDown as? NSDecimalNumber
            try? self.coredataContext.save()
            return OverrideSnapshot.create(from: save)
        }
        appCoordinator.overridesDidChange()
        return saved
    }

    func activatePreset(_ id: String) async -> OverrideSnapshot? {
        let overridePreset = await coredataContext.perform {
            var presetsArray = [OverridePresets]()
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "id == %@", id
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)

            return presetsArray.first.map { OverridePresetsSnapshot.create(from: $0) }
        }
        guard let overridePreset else { return nil }
        return await overrideFromPreset(overridePreset)
    }

    func fetchProfilePreset(_ name: String) async -> OverridePresetsSnapshot? {
        await coredataContext.perform {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name == %@", name
            )
            let presetsArray = (try? self.coredataContext.fetch(requestPresets)) ?? []

            return presetsArray.first.map { OverridePresetsSnapshot.create(from: $0) }
        }
    }

    func fetchProfile() async -> OverridePresetsSnapshot? {
        await coredataContext.perform {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name != %@", "" as String
            )
            let presetsArray = (try? self.coredataContext.fetch(requestPresets)) ?? []
            guard let last = presetsArray.first else {
                return nil
            }

            guard (last.date ?? Date.now).addingTimeInterval(.minutes(Int(truncating: last.duration ?? 0))) > Date(),
                  (last.date ?? Date.now) <= Date.now,
                  last.duration != 0
            else {
                return nil
            }
            return OverridePresetsSnapshot.create(from: last)
        }
    }

    func fetchProfiles() async -> [OverridePresetsSnapshot] {
        await coredataContext.perform {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name != %@", "" as String
            )
            let presetsArray = (try? self.coredataContext.fetch(requestPresets)) ?? []
            return presetsArray.map { OverridePresetsSnapshot.create(from: $0) }
        }
    }

    func isActive() async -> Bool {
        await coredataContext.perform {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = 1
            let overrideArray = (try? self.coredataContext.fetch(requestOverrides)) ?? []
            guard let lastOverride = overrideArray.first else {
                return false
            }
            return lastOverride.enabled
        }
    }

    func getPresetName(for override: OverrideSnapshot) async -> String? {
        await coredataContext.perform {
            guard let overrideId = override.id else { return nil }
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "id == %@", overrideId
            )
            requestPresets.fetchLimit = 1
            guard let presetsArray = try? self.coredataContext.fetch(requestPresets) else { return nil }

            return presetsArray.first?.name
        }
    }

    func fetchPreset(_ name: String) async -> (id: String?, preset: OverridePresetsSnapshot?) {
        await coredataContext.perform {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name == %@", name
            )
            let presetsArray = try? self.coredataContext.fetch(requestPresets)

            guard let overridePreset = presetsArray?.first else {
                return (nil, nil)
            }
            guard let id = overridePreset.id else {
                return (nil, nil)
            }

            return (id, OverridePresetsSnapshot.create(from: overridePreset))
        }
    }

    /// stores (and activates) a custom override built in the override editor
    /// - Returns: the activation date, for the Nightscout upload
    func storeOverride(_ draft: OverrideDraft) async -> Date {
        let savedAt: Date = await coredataContext.perform {
            let saveOverride = Override(context: self.coredataContext)
            saveOverride.duration = draft.duration as NSDecimalNumber
            saveOverride.indefinite = draft.indefinite
            saveOverride.percentage = draft.percentage
            saveOverride.enabled = true
            saveOverride.smbIsOff = draft.smbIsOff
            saveOverride.overrideAutoISF = draft.overrideAutoISF
            saveOverride.isPreset = draft.isPreset
            saveOverride.id = draft.id
            saveOverride.date = Date()
            saveOverride.target = draft.target as NSDecimalNumber
            if draft.advancedSettings {
                saveOverride.advancedSettings = true
                saveOverride.isfAndCr = draft.isfAndCr
                if !draft.isfAndCr {
                    saveOverride.isf = draft.isf
                    saveOverride.cr = draft.cr
                    saveOverride.basal = draft.basal
                }
                if draft.smbIsAlwaysOff {
                    saveOverride.smbIsAlwaysOff = true
                    saveOverride.start = draft.start as NSDecimalNumber
                    saveOverride.end = draft.end as NSDecimalNumber
                } else { saveOverride.smbIsAlwaysOff = false }

                saveOverride.smbMinutes = draft.smbMinutes as NSDecimalNumber
                saveOverride.uamMinutes = draft.uamMinutes as NSDecimalNumber
                saveOverride.maxIOB = draft.maxIOB as NSDecimalNumber
                saveOverride.overrideMaxIOB = draft.overrideMaxIOB
                saveOverride.endWIthNewCarbs = draft.endWIthNewCarbs
                saveOverride.glucoseOverrideThresholdActive = draft.glucoseOverrideThresholdActive
                if draft.glucoseOverrideThresholdActive {
                    saveOverride.glucoseOverrideThreshold = draft.glucoseOverrideThreshold as NSDecimalNumber
                }
                saveOverride.glucoseOverrideThresholdActiveDown = draft.glucoseOverrideThresholdActiveDown
                if draft.glucoseOverrideThresholdActiveDown {
                    saveOverride.glucoseOverrideThresholdDown = draft.glucoseOverrideThresholdDown as NSDecimalNumber
                }
            }
            try? self.coredataContext.save()
            return saveOverride.date ?? Date.now
        }
        appCoordinator.overridesDidChange()
        return savedAt
    }

    /// stores an override preset built in the override editor
    func storePreset(_ draft: OverrideDraft) async {
        await coredataContext.perform {
            let saveOverride = OverridePresets(context: self.coredataContext)
            saveOverride.duration = draft.duration as NSDecimalNumber
            saveOverride.indefinite = draft.indefinite
            saveOverride.percentage = draft.percentage.rounded()
            saveOverride.smbIsOff = draft.smbIsOff
            saveOverride.name = draft.name
            saveOverride.emoji = draft.emoji
            saveOverride.overrideAutoISF = draft.overrideAutoISF
            saveOverride.id = draft.id
            saveOverride.target = draft.target as NSDecimalNumber

            saveOverride.advancedSettings = draft.advancedSettings
            saveOverride.isfAndCr = draft.isfAndCr
            saveOverride.isf = draft.isf
            saveOverride.cr = draft.cr
            saveOverride.basal = draft.basal
            saveOverride.endWIthNewCarbs = draft.endWIthNewCarbs

            if draft.glucoseOverrideThresholdActive {
                saveOverride.glucoseOverrideThresholdActive = draft.glucoseOverrideThresholdActive
                saveOverride.glucoseOverrideThreshold = draft.glucoseOverrideThreshold as NSDecimalNumber
            }

            if draft.glucoseOverrideThresholdActiveDown {
                saveOverride.glucoseOverrideThresholdActiveDown = draft.glucoseOverrideThresholdActiveDown
                saveOverride.glucoseOverrideThresholdDown = draft.glucoseOverrideThresholdDown as NSDecimalNumber
            }

            if draft.smbIsAlwaysOff {
                saveOverride.smbIsAlwaysOff = true
                saveOverride.start = draft.start as NSDecimalNumber
                saveOverride.end = draft.end as NSDecimalNumber
            } else {
                saveOverride.smbIsAlwaysOff = false
            }

            saveOverride.smbMinutes = draft.smbMinutes as NSDecimalNumber
            saveOverride.uamMinutes = draft.uamMinutes as NSDecimalNumber
            saveOverride.maxIOB = draft.maxIOB as NSDecimalNumber
            saveOverride.overrideMaxIOB = draft.overrideMaxIOB
            saveOverride.date = Date.now

            try? self.coredataContext.save()
        }
        appCoordinator.overridesDidChange()
    }

    /// activates an override from a preset selected in the override editor
    /// (unlike `overrideFromPreset`, gates the advanced fields and falls back to defaults)
    /// - Returns: the activation date, for the Nightscout upload
    func activateProfile(_ profile: OverridePresetsSnapshot, id: String, defaultMaxIOB: Decimal) async -> OverrideSnapshot {
        let saved = await coredataContext.perform {
            let saveOverride = Override(context: self.coredataContext)
            saveOverride.duration = (profile.duration ?? 0) as NSDecimalNumber
            saveOverride.indefinite = profile.indefinite
            saveOverride.percentage = profile.percentage
            saveOverride.enabled = true
            saveOverride.smbIsOff = profile.smbIsOff
            saveOverride.isPreset = true
            saveOverride.date = Date()
            saveOverride.id = id
            saveOverride.advancedSettings = profile.advancedSettings
            saveOverride.isfAndCr = profile.isfAndCr
            saveOverride.overrideAutoISF = profile.overrideAutoISF

            if let tar = profile.target, tar == 0 {
                saveOverride.target = 6
            } else {
                saveOverride.target = profile.target as? NSDecimalNumber
            }

            if profile.advancedSettings {
                if !profile.isfAndCr {
                    saveOverride.isf = profile.isf
                    saveOverride.cr = profile.cr
                    saveOverride.basal = profile.basal
                }
                if profile.smbIsAlwaysOff {
                    saveOverride.smbIsAlwaysOff = true
                    saveOverride.start = profile.start as? NSDecimalNumber
                    saveOverride.end = profile.end as? NSDecimalNumber
                } else { saveOverride.smbIsAlwaysOff = false }

                saveOverride.smbMinutes = (profile.smbMinutes ?? 0) as NSDecimalNumber
                saveOverride.uamMinutes = (profile.uamMinutes ?? 0) as NSDecimalNumber
                saveOverride.maxIOB = (profile.maxIOB ?? defaultMaxIOB) as NSDecimalNumber
                saveOverride.overrideMaxIOB = profile.overrideMaxIOB
                saveOverride.endWIthNewCarbs = profile.endWIthNewCarbs
            }

            if profile.glucoseOverrideThresholdActive {
                saveOverride.glucoseOverrideThresholdActive = true
                saveOverride.glucoseOverrideThreshold = (profile.glucoseOverrideThreshold ?? 100) as NSDecimalNumber
            }

            if profile.glucoseOverrideThresholdActiveDown {
                saveOverride.glucoseOverrideThresholdActiveDown = true
                saveOverride.glucoseOverrideThresholdDown = (profile.glucoseOverrideThresholdDown ?? 90) as NSDecimalNumber
            }

            try? self.coredataContext.save()
            return OverrideSnapshot.create(from: saveOverride)
        }
        appCoordinator.overridesDidChange()
        return saved
    }

    func overrideFromPreset(_ preset: OverridePresetsSnapshot, _ id: String) async -> OverrideSnapshot {
        let saved = await coredataContext.perform {
            let save = Override(context: self.coredataContext)
            save.date = Date.now
            save.id = id
            save.end = preset.end as? NSDecimalNumber
            save.start = preset.start as? NSDecimalNumber
            save.advancedSettings = preset.advancedSettings
            save.cr = preset.cr
            save.duration = preset.duration as? NSDecimalNumber
            save.enabled = true
            save.indefinite = preset.indefinite
            save.isPreset = true
            save.isf = preset.isf
            save.basal = preset.basal
            save.isfAndCr = preset.isfAndCr
            save.percentage = preset.percentage
            save.smbIsAlwaysOff = preset.smbIsAlwaysOff
            save.smbIsOff = preset.smbIsOff
            save.smbMinutes = preset.smbMinutes as? NSDecimalNumber
            save.uamMinutes = preset.uamMinutes as? NSDecimalNumber
            save.maxIOB = preset.maxIOB as? NSDecimalNumber
            save.overrideMaxIOB = preset.overrideMaxIOB
            save.overrideAutoISF = preset.overrideAutoISF
            save.endWIthNewCarbs = preset.endWIthNewCarbs
            save.glucoseOverrideThresholdActive = preset.glucoseOverrideThresholdActive
            save.glucoseOverrideThreshold = preset.glucoseOverrideThreshold as? NSDecimalNumber
            save.glucoseOverrideThresholdActiveDown = preset.glucoseOverrideThresholdActiveDown
            save.glucoseOverrideThresholdDown = preset.glucoseOverrideThresholdDown as? NSDecimalNumber
            if (preset.target ?? 0) as Decimal > 6 {
                save.target = preset.target as? NSDecimalNumber
            } else { save.target = 6 }
            try? self.coredataContext.save()
            return OverrideSnapshot.create(from: save)
        }
        appCoordinator.overridesDidChange()
        return saved
    }
}
