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

    // nightscout backfill calls this version and waits for the `completion` callback
    func storeGlucose(_ bloodGlucose: [BloodGlucose], completion: (() -> Void)? = nil) {
        backgroundContext.perform {
            guard let earliestDate = bloodGlucose.min(by: { $0.dateString < $1.dateString }).map(\.dateString) else {
                completion?()
                return
            }
            do {
                let requestReadings = Readings.fetchRequest()
                requestReadings.predicate = NSPredicate(
                    format: "%K >= %@", #keyPath(Readings.date), earliestDate.addingTimeInterval(-60) as NSDate
                )

                let existing = try self.backgroundContext.fetch(requestReadings)
                var existingDates = existing.compactMap(\.date)

                for bg in bloodGlucose {
                    guard let glucose = bg.glucose,
                          !existingDates.contains(where: { abs($0.timeIntervalSince(bg.dateString)) <= 45 })
                    else {
                        continue
                    }
                    existingDates.append(bg.dateString)
                    let dataForForStats = Readings(context: self.backgroundContext)
                    dataForForStats.date = bg.dateString
                    dataForForStats.glucose = Int16(glucose)
                    dataForForStats.id = bg.id
                    dataForForStats.direction = bg.direction?.symbol ?? "↔︎"
                }
                try self.backgroundContext.save()
                completion?()
            } catch {
                debug(.service, "failed to save glucose to core data: \(error)")
                completion?()
            }
        }
    }

    func newGlucoseStored(_ bloodGlucose: [BloodGlucose]) {
        storeGlucose(bloodGlucose)
    }
}
