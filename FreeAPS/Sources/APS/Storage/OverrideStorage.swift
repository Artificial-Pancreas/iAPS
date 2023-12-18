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
}
