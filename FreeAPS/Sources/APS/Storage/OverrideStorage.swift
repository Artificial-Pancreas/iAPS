import Combine
import CoreData
import Foundation
import SwiftDate

final class OverrideStorage: Sendable {
    private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

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

    func fetchLatestOverride() async -> [OverrideSnapshot] {
        await coredataContext.perform {
            let request = self.latestOverrideRequest()
            let overrideArray = try? self.coredataContext.fetch(request)
            return (overrideArray ?? []).map { OverrideSnapshot.create(from: $0) }
        }
    }

    func fetchLatestOverrideSnapshot() async -> OverrideSnapshot? {
        await coredataContext.perform {
            let request = self.latestOverrideRequest()
            let override = try? self.coredataContext.fetch(request).first
            return override.map { OverrideSnapshot.create(from: $0) }
        }
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
    }

    func fetchNumberOfOverrides(numbers: Int) async -> [OverrideSnapshot] {
        await coredataContext.perform {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = numbers
            let overrideArray = (try? self.coredataContext.fetch(requestOverrides)) ?? []
            return overrideArray.map { OverrideSnapshot.create(from: $0) }
        }
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
        let scheduled = await fetchLatestOverride().first
        return await coredataContext.perform {
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
    }

    func overrideFromPreset(_ preset: OverridePresetsSnapshot) async {
        await coredataContext.perform {
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
        }
    }

    func activatePreset(_ id: String) async {
        let overridePreset = await coredataContext.perform {
            var presetsArray = [OverridePresets]()
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "id == %@", id
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)

            return presetsArray.first.map { OverridePresetsSnapshot.create(from: $0) }
        }
        if let overridePreset {
            await overrideFromPreset(overridePreset)
        }
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

            guard (last.date ?? Date.now).addingTimeInterval(Int(truncating: last.duration ?? 0).minutes.timeInterval) > Date(),
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

    // TODO: confusing name
    func isPresetName() async -> String? {
        await coredataContext.perform {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = 1
            let overrideArray = (try? self.coredataContext.fetch(requestOverrides)) ?? []

            guard let or = overrideArray.first, let id = or.id else { return nil }
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "id == %@", id
            )
            let presetsArray = (try? self.coredataContext.fetch(requestPresets)) ?? []

            guard let presets = presetsArray.first, let presetName = presets.name else {
                return nil
            }
            return presetName
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

    func overrideFromPreset(_ preset: OverridePresetsSnapshot, _ id: String) async {
        await coredataContext.perform {
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
        }
    }
}
