import CoreData
import Foundation
import Swinject

final class CoreDataManager: LifetimeOwner, AppService {
    private let coreDataStorage = CoreDataStorage()
    private let appCoordinator: AppCoordinator

    let lifetime = Lifetime()

    init(resolver: Resolver) {
        appCoordinator = resolver.resolve(AppCoordinator.self)!
    }

    // this is called at the start of the app
    func start() async {
        observe(appCoordinator.newGlucoseRecords) { me, bloodGlucose in
            await me.storeGlucose(bloodGlucose)
        }
        observe(appCoordinator.loopCompleted) { me, loopOutcome in
            await me.loopCompleted(loopOutcome)
        }
    }

    private func loopCompleted(_ loopOutcome: LoopOutcome) async {
        if case .failed = loopOutcome { return }
        guard let suggestion = loopOutcome.suggestion else {
            return
        }

        // Save to CoreData also. TO DO: Remove the JSON saving after some testing.
        let lastLoopIob = (suggestion.iob ?? 0) as NSDecimalNumber
        let lastLoopCob = (suggestion.cob ?? 0) as NSDecimalNumber
        let lastLoopTimestamp = suggestion.timestamp
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { coredataContext in
            let saveLastLoop = LastLoop(context: coredataContext)
            saveLastLoop.iob = lastLoopIob
            saveLastLoop.cob = lastLoopCob
            saveLastLoop.timestamp = lastLoopTimestamp
            try? coredataContext.save()
        }
    }

    // nightscout backfill calls this version and waits for the `completion` callback
    func storeGlucose(_ bloodGlucose: [BloodGlucose]) async {
        let backgroundContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil

        await backgroundContext.perform {
            guard let earliestDate = bloodGlucose.min(by: { $0.dateString < $1.dateString }).map(\.dateString) else {
                return
            }
            do {
                let requestReadings = Readings.fetchRequest()
                requestReadings.predicate = NSPredicate(
                    format: "%K >= %@", #keyPath(Readings.date), earliestDate.addingTimeInterval(-60) as NSDate
                )

                let existing = try backgroundContext.fetch(requestReadings)
                var existingDates = existing.compactMap(\.date)

                for bg in bloodGlucose {
                    guard let glucose = bg.glucose,
                          !existingDates.contains(where: { abs($0.timeIntervalSince(bg.dateString)) <= 45 })
                    else {
                        continue
                    }
                    existingDates.append(bg.dateString)
                    let dataForForStats = Readings(context: backgroundContext)
                    dataForForStats.date = bg.dateString
                    dataForForStats.glucose = Int16(glucose)
                    dataForForStats.id = bg.id
                    dataForForStats.direction = bg.direction?.symbol ?? "↔︎"
                }
                try backgroundContext.save()
            } catch {
                debug(.service, "failed to save glucose to core data: \(error)")
            }
        }
    }
}
