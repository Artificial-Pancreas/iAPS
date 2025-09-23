import CoreData
import Foundation
import Swinject

final class CoreDataStorageGlucoseSaver: NewGlucoseObserver {
    private let backgroundContext: NSManagedObjectContext
    private let broadcaster: Broadcaster!

    init(resolver: Resolver) {
        broadcaster = resolver.resolve(Broadcaster.self)!

        backgroundContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil

        subscribe()
    }

    private func subscribe() {
        broadcaster.register(NewGlucoseObserver.self, observer: self)
    }

    func newGlucoseStored(_ bloodGlucose: [BloodGlucose]) {
        backgroundContext.perform {
            guard let earliestDate = bloodGlucose.min(by: { $0.dateString < $1.dateString }).map(\.dateString) else { return }
            do {
                let requestReadings = Readings.fetchRequest()
                requestReadings.predicate = NSPredicate(
                    format: "%K >= %@", #keyPath(Readings.date), earliestDate.addingTimeInterval(-60) as NSDate
                )

                let existing = try self.backgroundContext.fetch(requestReadings)
                let existingDates = Set(existing.compactMap { $0.date?.roundedTo1Second })

                for bg in bloodGlucose {
                    guard let glucose = bg.glucose,
                          !existingDates.contains(bg.dateString.roundedTo1Second)
                    else {
                        continue
                    }
                    let dataForForStats = Readings(context: self.backgroundContext)
                    dataForForStats.date = bg.dateString
                    dataForForStats.glucose = Int16(glucose)
                    dataForForStats.id = bg.id
                    dataForForStats.direction = bg.direction?.symbol ?? "↔︎"
                }
                try self.backgroundContext.save()
            } catch {
                debug(.service, "failed to save glucose to core data: \(error)")
            }
        }
    }
}
