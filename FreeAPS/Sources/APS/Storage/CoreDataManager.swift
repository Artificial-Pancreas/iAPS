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
        observe(appCoordinator.glucoseDeletions) { me, deleted in
            for g in deleted {
                await me.coreDataStorage.deleteBatch(identifier: g.id, entity: "Readings")
            }
        }

        observe(appCoordinator.loopCompleted) { me, loopOutcome in
            await withBackgroundTask("core data - save loop outcome") {
                await me.loopCompleted(loopOutcome)
                if let suggestion = loopOutcome.suggestion {
                    await me.saveSuggestion(suggestion)
                }
            }
        }
    }

    private func loopCompleted(_ loopOutcome: LoopOutcome) async {
        if case .failed = loopOutcome { return }
        guard let suggestion = loopOutcome.suggestion else {
            return
        }

        // Save to CoreData also. TO DO: Remove the JSON saving after some testing.
        let lastLoopIob = (suggestion.iob ?? 0)
        let lastLoopCob = (suggestion.cob ?? 0)
        let lastLoopTimestamp = suggestion.timestamp
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { coredataContext in
            let saveLastLoop = LastLoop(context: coredataContext)
            saveLastLoop.iob = lastLoopIob as NSDecimalNumber
            saveLastLoop.cob = lastLoopCob as NSDecimalNumber
            saveLastLoop.timestamp = lastLoopTimestamp
            try? coredataContext.save()
        }
    }

    private func saveSuggestion(_ suggestion: Suggestion) async {
        guard let iaps = suggestion.iaps else { return }
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveSuggestion = Reasons(context: context)
            saveSuggestion.isf = iaps.isf as NSDecimalNumber?
            saveSuggestion.cr = iaps.cr as NSDecimalNumber?
            saveSuggestion.tdd = iaps.totalDailyDose as NSDecimalNumber?
            saveSuggestion.iob = suggestion.iob as NSDecimalNumber?
            saveSuggestion.cob = suggestion.cob as NSDecimalNumber?
            saveSuggestion.target = suggestion.targetBG as NSDecimalNumber?
            saveSuggestion.minPredBG = iaps.minPredBG as NSDecimalNumber?
            saveSuggestion.eventualBG = suggestion.eventualBG.map { Decimal($0) as NSDecimalNumber }
            saveSuggestion.insulinReq = (suggestion.insulinReq ?? 0) as NSDecimalNumber
            saveSuggestion.smb = (suggestion.units ?? 0) as NSDecimalNumber
            saveSuggestion.reasons = suggestion.iaps?.aisfReasons
            saveSuggestion.glucose = (suggestion.bg ?? 0) as NSDecimalNumber
            saveSuggestion.ratio = (suggestion.sensitivityRatio ?? 1) as NSDecimalNumber

            saveSuggestion.override = suggestion.iaps?.overrideActive ?? false

            saveSuggestion.date = Date.now

            if let rate = suggestion.rate ?? suggestion.iaps?.maxSafeBasal {
                saveSuggestion.rate = rate as NSDecimalNumber
            }

            saveSuggestion.mmol = suggestion.iaps?.units == .mmolL

            try? context.save()
        }
    }

    // nightscout backfill calls this version
    func storeGlucose(_ bloodGlucose: [BloodGlucose]) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { backgroundContext in
            backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

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
                    let glucose = bg.glucose
                    guard !existingDates.contains(where: { abs($0.timeIntervalSince(bg.dateString)) <= 45 })
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
