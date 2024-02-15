import CoreData
import Foundation
import SwiftDate
import Swinject

/*
 protocol OverrideStorage {
     func fetchOverrides(interval: NSDate) -> [Override]
     func fetchLatestOverride() -> [Override]
 }
  */
protocol OverrideObserver {
    func overrideHistoryDidUpdate(_: [OverrideHistory])
}

final class OverrideStorage {
    private let processQueue = DispatchQueue(label: "BaseOverrideStorage.processQueue")

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var storage: FileStorage!

    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext // newBackgroundContext()

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

    func fetchLatestActiveOverride() -> Override? {
        var overrideArray = [Override]()
        coredataContext.performAndWait {
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.fetchLimit = 2
            try? overrideArray = self.coredataContext.fetch(requestOverrides)
        }
        return overrideArray.first
    }

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

    func cancelProfile() -> Double? {
        let scheduled = fetchLatestOverride().first
        var duration: Double?
        coredataContext.performAndWait { [self] in
            let profiles = Override(context: self.coredataContext)
            let history = OverrideHistory(context: self.coredataContext)
            if let latest = scheduled {
                history.duration = -1 * (latest.date ?? Date()).timeIntervalSinceNow.minutes
                print("History duration: \(history.duration) min")
                history.date = latest.date ?? Date()
                history.target = Double(latest.target ?? 100)
                duration = history.duration
            }
            profiles.enabled = false
            profiles.date = Date()
            try? self.coredataContext.save()
        }
        return duration
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
}
