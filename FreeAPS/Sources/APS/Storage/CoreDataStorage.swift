import CoreData
import Foundation
import SwiftDate
import Swinject

final class CoreDataStorage {
    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext // newBackgroundContext()

    func fetchGlucose(interval: NSDate) -> [Readings] {
        var fetchGlucose = [Readings]()
        coredataContext.performAndWait {
            let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReadings.sortDescriptors = [sort]
            requestReadings.predicate = NSPredicate(
                format: "glucose > 0 AND date > %@", interval
            )
            try? fetchGlucose = self.coredataContext.fetch(requestReadings)
        }
        return fetchGlucose
    }

    func fetchLatestOverride() -> [Override] {
        var overrideArray = [Override]()
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = 1
            try? overrideArray = self.coredataContext.fetch(requestOverrides)
        }
        return overrideArray
    }

    func isPresetName() -> String? {
        var presetsArray = [OverridePresets]()
        var overrideArray = [Override]()
        var name: String?
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = 1
            try? overrideArray = self.coredataContext.fetch(requestOverrides)

            if let or = overrideArray.first, let id = or.id {
                let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
                requestPresets.predicate = NSPredicate(
                    format: "id == %@", id
                )
                try? presetsArray = self.coredataContext.fetch(requestPresets)

                guard let presets = presetsArray.first, let presetName = presets.name else {
                    return
                }
                name = presetName
            }
        }
        return name
    }

    func nameOfLastActiveOverride() -> String? {
        var presetsArray = [OverridePresets]()
        var overrideArray = [Override]()
        var name: String?
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = 2
            try? overrideArray = self.coredataContext.fetch(requestOverrides)

            if let or = overrideArray.first, let id = or.id {
                let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
                requestPresets.predicate = NSPredicate(
                    format: "id == %@", id
                )
                try? presetsArray = self.coredataContext.fetch(requestPresets)

                guard let presets = presetsArray.first, let presetName = presets.name else {
                    return
                }
                name = presetName
            }
        }
        return name
    }

    func fetchPreset(_ name: String) -> (id: String?, preset: OverridePresets?) {
        var presetsArray = [OverridePresets]()
        var id: String?
        var overridePreset: OverridePresets?
        coredataContext.performAndWait {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name == %@", name
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)

            guard let preset = presetsArray.first else {
                return
            }
            guard let id_ = preset.id else {
                return
            }
            id = id_
            overridePreset = preset
        }
        return (id, overridePreset)
    }

    func overrideFromPreset(_ preset: OverridePresets, _ id: String) {
        coredataContext.performAndWait {
            coredataContext.performAndWait {
                let save = Override(context: coredataContext)
                save.date = Date.now
                save.id = id
                save.end = preset.end
                save.start = preset.start
                save.advancedSettings = preset.advancedSettings
                save.cr = preset.cr
                save.duration = preset.duration
                save.enabled = true
                save.indefinite = preset.indefinite
                save.isPreset = true
                save.isf = preset.isf
                save.isfAndCr = preset.isfAndCr
                save.percentage = preset.percentage
                save.smbIsAlwaysOff = preset.smbIsAlwaysOff
                save.smbMinutes = preset.smbMinutes
                save.uamMinutes = preset.uamMinutes
                save.target = preset.target
                try? coredataContext.save()
            }
        }
    }

    func activateOverride(_ override: Override) {
        coredataContext.performAndWait {
            let save = Override(context: coredataContext)
            save.date = Date.now
            save.id = override.id
            save.end = override.end
            save.start = override.start
            save.advancedSettings = override.advancedSettings
            save.cr = override.cr
            save.duration = override.duration
            save.enabled = override.enabled
            save.indefinite = override.indefinite
            save.isPreset = override.isPreset
            save.isf = override.isf
            save.isfAndCr = override.isfAndCr
            save.percentage = override.percentage
            save.smbIsAlwaysOff = override.smbIsAlwaysOff
            save.smbMinutes = override.smbMinutes
            save.uamMinutes = override.uamMinutes
            save.target = override.target
            try? coredataContext.save()
        }
    }

    func isActive() -> Bool {
        var overrideArray = [Override]()
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = 1
            try? overrideArray = self.coredataContext.fetch(requestOverrides)
        }
        guard let lastOverride = overrideArray.first else {
            return false
        }
        return lastOverride.enabled
    }

    func addToNotUploaded(_ add: Int16) {
        var currentCount = [NotUploaded]()
        coredataContext.performAndWait {
            let requestCount = NotUploaded.fetchRequest() as NSFetchRequest<NotUploaded>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestCount.sortDescriptors = [sortOverride]
            requestCount.fetchLimit = 1
            try? currentCount = self.coredataContext.fetch(requestCount)

            var log: Int16 = currentCount.first?.number ?? 0

            let save = NotUploaded(context: coredataContext)
            if currentCount.first != nil, log != 0 {
                save.number += add
                save.date = Date.now
                try? coredataContext.save()
                log = save.number
            } else if add > 0 {
                save.number = add
                save.date = Date.now
                try? coredataContext.save()
                log = save.number
            } else if add < 0 {
                if (currentCount.first?.number ?? 0) + add >= 0 {
                    save.number = add
                    save.date = Date.now
                    try? coredataContext.save()
                    log = save.number
                } else {
                    save.number = 0
                    save.date = Date.now
                    try? coredataContext.save()
                    log = save.number
                }
            }
            debug(.service, "CoreData. addToNotUploaded Overides incremented. Current amount: \(log)")
        }
    }

    func countNotUploaded() -> Int? {
        var currentCount = [NotUploaded]()
        coredataContext.performAndWait {
            let requestCount = NotUploaded.fetchRequest() as NSFetchRequest<NotUploaded>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestCount.predicate = NSPredicate(
                format: "date > %@", Date().addingTimeInterval(-2.days.timeInterval) as NSDate
            )
            requestCount.sortDescriptors = [sortOverride]
            requestCount.fetchLimit = 1
            try? currentCount = self.coredataContext.fetch(requestCount)
        }
        if let latest = currentCount.first, latest.number > 0 {
            return Int(latest.number)
        }
        return nil
    }
}
