import CoreData
import Foundation
import SwiftDate

final class OverrideStorage {
    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext // newBackgroundContext()

    func fetchOverrides(interval: NSDate) -> [Override] {
        var overrideArray = [Override]()
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "date > %@", interval
            )
            try? overrideArray = self.coredataContext.fetch(requestOverrides)
        }
        return overrideArray
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

    func fetchOverrideHistory(interval: NSDate) -> [OverrideHistory] {
        var overrideArray = [OverrideHistory]()
        coredataContext.performAndWait {
            let requestOverrides = OverrideHistory.fetchRequest() as NSFetchRequest<OverrideHistory>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "date > %@", interval
            )
            try? overrideArray = self.coredataContext.fetch(requestOverrides)
        }
        return overrideArray
    }

    func cancelProfile() {
        let scheduled = fetchLatestOverride().first
        coredataContext.perform { [self] in
            let profiles = Override(context: self.coredataContext)
            let history = OverrideHistory(context: self.coredataContext)
            if let latest = scheduled {
                history.duration = -1 * (latest.date ?? Date()).timeIntervalSinceNow.minutes
                print("History duration: \(history.duration) min")
                history.date = latest.date ?? Date()
                history.target = Double(latest.target ?? 100)
            }
            profiles.enabled = false
            profiles.date = Date()
            try? self.coredataContext.save()
        }
    }

    func overrideFromPreset(_ preset: OverridePresets) {
        coredataContext.performAndWait {
            let save = Override(context: coredataContext)
            save.date = Date.now
            save.id = preset.id
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

    func fetchProfile(_ name: String) -> Override? {
        var presetsArray = [OverridePresets]()
        var overrideArray = [Override]()
        var override: Override?
        coredataContext.performAndWait {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name == %@", name
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)

            guard let preset = presetsArray.first else {
                return
            }
            guard let id = preset.id else {
                return
            }
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            requestOverrides.predicate = NSPredicate(
                format: "id == %@", id
            )
            try? overrideArray = self.coredataContext.fetch(requestOverrides)

            guard let override_ = overrideArray.first else {
                return
            }
            override = override_
        }
        return override
    }

    func fetchProfiles() -> OverridePresets? {
        var presetsArray = [OverridePresets]()
        coredataContext.performAndWait {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name != %@", "" as String
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)
        }

        guard let last = presetsArray.first else {
            return nil
        }

        guard (last.date ?? Date.now).addingTimeInterval(Int(last.duration ?? 0).minutes.timeInterval) > Date(),
              (last.date ?? Date.now) <= Date.now,
              last.duration != 0
        else {
            return nil
        }
        return last
    }

    func fetchProfiles() -> [OverridePresets] {
        var presetsArray = [OverridePresets]()
        coredataContext.performAndWait {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "name != %@", "" as String
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)
        }
        return presetsArray
    }

    func activateOverride(_ override: Override) {
        var overrideArray = [Override]()
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
}
