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
}
