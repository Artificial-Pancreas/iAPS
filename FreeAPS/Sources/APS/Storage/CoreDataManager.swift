import CoreData
import Foundation
import Swinject

final class CoreDataManager: LifetimeOwner, AppService {
    private let coreDataStorage = CoreDataStorage()
    private let appCoordinator: AppCoordinator
    /// one `storeGlucose` batch, or one deletion, at a time
    private let serializer = TaskSerializer()
    private let container: NSPersistentContainer
    private let batchSize: Int
    private let insert: @Sendable(
        [BloodGlucose],
        NSManagedObjectContext
    ) throws -> (count: Int, change: ReadingsChange?)

    let lifetime = Lifetime()

    convenience init(resolver: Resolver) {
        self.init(appCoordinator: resolver.resolve(AppCoordinator.self)!)
    }

    /// `container`, `batchSize` and `insert` are for the tests: the app stores into the shared stack, in batches
    /// of `glucoseBatchSize`, with `CoreDataManager.insertBatch`.
    init(
        appCoordinator: AppCoordinator,
        container: NSPersistentContainer = CoreDataStack.shared.persistentContainer,
        batchSize: Int = CoreDataManager.glucoseBatchSize,
        insert: @escaping @Sendable(
            [BloodGlucose],
            NSManagedObjectContext
        ) throws -> (count: Int, change: ReadingsChange?) = { try CoreDataManager.insertBatch($0, into: $1) }
    ) {
        self.appCoordinator = appCoordinator
        self.container = container
        self.batchSize = batchSize
        self.insert = insert
    }

    // this is called at the start of the app
    func start() async {
        observe(appCoordinator.newGlucoseRecords) { me, bloodGlucose in
            await me.storeGlucose(bloodGlucose)
        }
        observe(appCoordinator.glucoseDeletions) { me, deleted in
            // in turn with the batches stored: a deletion never lands before a queued insert of the same reading
            await me.serializer.run {
                for g in deleted {
                    await me.coreDataStorage.deleteBatch(identifier: g.id, entity: "Readings")
                }
                if let change = ReadingsChange.readings(at: deleted.map(\.dateString), newest: false) {
                    me.appCoordinator.sendReadingsChanged(change)
                }
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
        let date = Date.now
        let saved = await CoreDataStack.shared.persistentContainer.performBackgroundTask { context -> Bool in
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

            saveSuggestion.date = date

            if let rate = suggestion.rate ?? suggestion.iaps?.maxSafeBasal {
                saveSuggestion.rate = rate as NSDecimalNumber
            }

            saveSuggestion.mmol = suggestion.iaps?.units == .mmolL

            return (try? context.save()) != nil
        }
        // after the save: the insulin statistics read the IOB from these rows
        if saved {
            appCoordinator.sendInsulinDataChanged(.interval(DateInterval(start: date, duration: 0)))
        }
    }

    /// What `storeGlucose` stored.
    struct GlucoseStoreOutcome: Sendable, Equatable {
        /// the readings inserted: not the duplicates of stored ones
        var inserted = 0
        /// why saving stopped: the batches before it are stored
        var error: String?
        /// the newest reading of the batch that failed: the readings newer than it are stored
        var reached: Date?
    }

    /// readings per batch: two days of 1-minute readings, ten of 5-minute ones
    static let glucoseBatchSize = 3000

    /// Stores the readings that are not duplicates (see `nonDuplicates`): the CGM readings coming in, and the
    /// Nightscout backfill. In batches of contiguous time, newest first, each saved and announced on its own: an
    /// interrupted backfill keeps the batches before, and the statistics fill in from the recent days. One batch at
    /// a time, across calls too, so two calls never check against the same stored rows; the serializer is free
    /// between the batches, so a CGM reading coming in during a backfill waits for one batch at most. `progress`:
    /// the fraction of the batches stored, awaited before the next batch.
    @discardableResult func storeGlucose(
        _ bloodGlucose: [BloodGlucose],
        progress: (@MainActor @Sendable(Double) async -> Void)? = nil
    ) async -> GlucoseStoreOutcome {
        let batches = Self.batches(of: bloodGlucose.map(\.dateString), size: batchSize)
        var outcome = GlucoseStoreOutcome()
        for (number, batch) in batches.enumerated() {
            let readings = batch.map { bloodGlucose[$0] }
            do {
                outcome.inserted += try await serializer.run { try await self.storeBatch(readings) }
            } catch {
                debug(.service, "failed to save glucose to core data: \(error)")
                outcome.error = error.localizedDescription
                outcome.reached = readings.map(\.dateString).max()
                return outcome
            }
            await progress?(Double(number + 1) / Double(batches.count))
        }
        return outcome
    }

    /// Stores one batch, checked against the stored rows it fetches; returns the number inserted.
    private func storeBatch(_ bloodGlucose: [BloodGlucose]) async throws -> Int {
        let insert = self.insert
        let (count, change) = try await container.performBackgroundTask { context in
            try insert(bloodGlucose, context)
        }
        // after the save: the statistics re-read what changed
        if let change {
            appCoordinator.sendReadingsChanged(change)
        }
        return count
    }

    /// Inserts and saves the readings of one batch that are not duplicates of the stored rows: the number inserted,
    /// and the change for the statistics.
    static func insertBatch(
        _ bloodGlucose: [BloodGlucose],
        into context: NSManagedObjectContext
    ) throws -> (count: Int, change: ReadingsChange?) {
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        let dates = bloodGlucose.map(\.dateString)
        guard let earliest = dates.min(), let latest = dates.max() else {
            return (0, nil)
        }

        // the stored rows a new reading can be a duplicate of: within a minute of the batch
        let requestReadings = NSFetchRequest<NSDictionary>(entityName: "Readings")
        requestReadings.resultType = .dictionaryResultType
        requestReadings.propertiesToFetch = ["date", "type"]
        requestReadings.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            earliest.addingTimeInterval(-60) as NSDate,
            latest.addingTimeInterval(60) as NSDate
        )
        let existingRows = try context.fetch(requestReadings).compactMap { row -> (date: Date, type: String?)? in
            guard let date = row["date"] as? Date else { return nil }
            return (date: date, type: row["type"] as? String)
        }

        // the newest stored CGM reading
        let requestNewest = Readings.fetchRequest()
        requestNewest.predicate = NSPredicate(
            format: "date != nil AND (type == nil OR type == %@)", GlucoseType.sgv.rawValue
        )
        requestNewest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        requestNewest.fetchLimit = 1
        let newestStored = try context.fetch(requestNewest).first?.date

        // the CGM readings inserted: only they count in the statistics
        var inserted: [Date] = []

        let toInsert = nonDuplicates(
            bloodGlucose.map { (date: $0.dateString, type: $0.type) },
            existing: existingRows
        )
        for index in toInsert {
            let bg = bloodGlucose[index]
            let reading = Readings(context: context)
            reading.date = bg.dateString
            reading.glucose = Int16(bg.glucose)
            reading.id = bg.id
            reading.direction = bg.direction?.symbol ?? "↔︎"
            reading.type = bg.type
            if isCGM(bg.type) {
                inserted.append(bg.dateString)
            }
        }
        try context.save()

        let newest = newestStored.map { stored in inserted.allSatisfy { $0 > stored } } ?? true
        return (toInsert.count, ReadingsChange.readings(at: inserted, newest: newest))
    }

    /// The indices of `dates` in batches of at most `size`: each batch a contiguous stretch of time, the newest
    /// batch first. Within a batch the indices keep their order, so of two duplicates the first is kept, as with
    /// one batch; across batches the newer batch's reading is.
    static func batches(of dates: [Date], size: Int) -> [[Int]] {
        guard dates.isNotEmpty else { return [] }
        guard dates.count > size else { return [Array(dates.indices)] }
        let newestFirst = dates.indices.sorted { a, b in
            dates[a] == dates[b] ? b > a : dates[a] > dates[b]
        }
        return stride(from: 0, to: newestFirst.count, by: max(size, 1)).map { start in
            newestFirst[start ..< min(start + max(size, 1), newestFirst.count)].sorted()
        }
    }

    /// A CGM reading, as the statistics count them: sgv, or no type (the rows stored before it was).
    private static func isCGM(_ type: String?) -> Bool {
        type == nil || type == GlucoseType.sgv.rawValue
    }

    /// The indices of the `readings` to store, in their order. Like GlucoseStorage: a CGM reading is a duplicate of
    /// a CGM reading within 45 s, a manual or meter BG only of one of its own type (a manual BG next to a CGM reading
    /// is kept, and vice versa). Checked against the `existing` rows and the readings kept before it, so of new
    /// readings within 45 s of each other the first one wins.
    static func nonDuplicates(
        _ readings: [(date: Date, type: String?)],
        existing: [(date: Date, type: String?)]
    ) -> [Int] {
        var kept = DuplicateIndex()
        for row in existing {
            kept.insert(row.date, type: row.type)
        }
        var result: [Int] = []
        for (index, reading) in readings.enumerated() where !kept.contains(near: reading.date, type: reading.type) {
            kept.insert(reading.date, type: reading.type)
            result.append(index)
        }
        return result
    }

    /// Dates by reading class (CGM, or one manual / meter type) in 60 s buckets: a date within 45 s of another one
    /// is in the same bucket or an adjacent one, so a lookup compares only those.
    private struct DuplicateIndex {
        /// the class key: nil for every CGM reading, the type for the others
        private var buckets: [String?: [Int: [Date]]] = [:]
        /// dates too far out for a bucket (never in a real reading): compared one by one
        private var outliers: [String?: [Date]] = [:]

        private static func classKey(_ type: String?) -> String? {
            CoreDataManager.isCGM(type) ? nil : type
        }

        private static func bucket(_ date: Date) -> Int? {
            let minutes = (date.timeIntervalSinceReferenceDate / 60).rounded(.down)
            guard minutes.isFinite, abs(minutes) < 1E15 else { return nil }
            return Int(minutes)
        }

        private static func isDuplicate(_ stored: Date, _ date: Date) -> Bool {
            abs(stored.timeIntervalSince(date)) <= 45
        }

        func contains(near date: Date, type: String?) -> Bool {
            let key = Self.classKey(type)
            guard let bucket = Self.bucket(date) else {
                return outliers[key]?.contains { Self.isDuplicate($0, date) } ?? false
            }
            guard let dates = buckets[key] else { return false }
            return (bucket - 1 ... bucket + 1).contains { neighbour in
                dates[neighbour]?.contains { Self.isDuplicate($0, date) } ?? false
            }
        }

        mutating func insert(_ date: Date, type: String?) {
            let key = Self.classKey(type)
            guard let bucket = Self.bucket(date) else {
                outliers[key, default: []].append(date)
                return
            }
            buckets[key, default: [:]][bucket, default: []].append(date)
        }
    }
}
