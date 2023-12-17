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
    func overridesDidUpdate(_: [Override])
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
}
