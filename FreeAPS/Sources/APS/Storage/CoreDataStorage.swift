import CoreData
import Foundation
import SwiftDate
import Swinject

final class CoreDataStorage: Sendable, GlucosePointSource {
    private let injectedContainer: NSPersistentContainer?

    /// - Parameter container: for the statistics fetches (`fetchGlucosePoints`, `fetchLoopStatRecords`, the insulin and
    ///   meals fetches) only, so the tests can run them against an in-memory store; nil (the app) is the shared stack's
    init(container: NSPersistentContainer? = nil) {
        injectedContainer = container
    }

    private var statisticsContainer: NSPersistentContainer {
        injectedContainer ?? CoreDataStack.shared.persistentContainer
    }

    func fetchGlucose(interval: NSDate) async -> [ReadingsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReadings.sortDescriptors = [sort]
            requestReadings.predicate = NSPredicate(
                format: "glucose > 0 AND date > %@", interval
            )
            let fetchGlucose = (try? context.fetch(requestReadings)) ?? []
            return fetchGlucose.map { ReadingsSnapshot.create(from: $0) }
        }
    }

    @discardableResult func updateGlucose(_ values: [String: Int]) async -> Int {
        guard values.isNotEmpty else { return 0 }

        return await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = Readings.fetchRequest() as NSFetchRequest<Readings>
            request.predicate = NSPredicate(format: "id IN %@", Array(values.keys))

            guard let readings = try? context.fetch(request) else { return 0 }

            var updated = 0
            for reading in readings {
                guard let id = reading.id, let value = values[id], reading.glucose != Int16(value) else { continue }
                reading.glucose = Int16(value)
                updated += 1
            }

            guard updated > 0 else { return 0 }

            do {
                try context.save()
            } catch {
                debug(.service, "failed to update glucose in core data: \(error)")
                return 0
            }

            return updated
        }
    }

    func fetchRecentGlucose() async -> ReadingsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReadings.sortDescriptors = [sort]
            requestReadings.fetchLimit = 1
            if let fetchGlucose = (try? context.fetch(requestReadings))?.first {
                return ReadingsSnapshot.create(from: fetchGlucose)
            } else {
                return nil
            }
        }
    }

    /// The readings the statistics count (CGM: `type` sgv, or none for the rows from before it was stored),
    /// `[from, to)`, oldest -> newest. Fetched as plain values, in chunks of at most 7 days, each in its own
    /// background context. Throws when any chunk fails: a part of the range must never read as "no readings".
    func fetchGlucosePoints(from: Date, to: Date) async throws -> [GlucosePoint] {
        var points: [GlucosePoint] = []
        var chunkStart = from
        while chunkStart < to {
            let start = chunkStart
            let end = min(start.addingTimeInterval(.days(7)), to)
            let chunk = try await statisticsContainer.performBackgroundTask { context in
                try Self.glucosePoints(from: start, to: end, limit: nil, in: context)
            }
            points += chunk
            chunkStart = end
        }
        return points
    }

    /// The oldest `limit` of `fetchGlucosePoints`' readings in `[from, to)`, in one fetch of at most that many rows
    /// (is there a reading before a date?).
    func fetchGlucosePoints(from: Date, to: Date, limit: Int) async throws -> [GlucosePoint] {
        guard from < to, limit > 0 else { return [] }
        return try await statisticsContainer.performBackgroundTask { context in
            try Self.glucosePoints(from: from, to: to, limit: limit, in: context)
        }
    }

    /// `fetchGlucosePoints`' rows of `[from, to)`, oldest first, at most `limit` of them.
    private static func glucosePoints(
        from start: Date,
        to end: Date,
        limit: Int?,
        in context: NSManagedObjectContext
    ) throws -> [GlucosePoint] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Readings")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["date", "glucose"]
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@ AND glucose > 0 AND (type == nil OR type == %@)",
            start as NSDate,
            end as NSDate,
            GlucoseType.sgv.rawValue
        )
        if let limit {
            request.fetchLimit = limit
        }
        return try context.fetch(request).compactMap { row -> GlucosePoint? in
            guard let date = row["date"] as? Date, let glucose = row["glucose"] as? NSNumber else { return nil }
            return GlucosePoint(time: date, mgdl: glucose.int16Value)
        }
    }

    // MARK: - Insulin and meals statistics

    // Plain values from dictionary fetches, on background contexts of the statistics container; each throws when any
    // part fails (a failed read must never show as "no pump data"). Events and IOB are read in chunks of at most 7 days.

    /// `[from, to)` in chunks of at most 7 days, in order, each in its own background context.
    private func fetchInChunks<Value: Sendable>(
        from: Date,
        to: Date,
        _ fetch: @escaping @Sendable(NSManagedObjectContext, Date, Date) throws -> [Value]
    ) async throws -> [Value] {
        var values: [Value] = []
        var chunkStart = from
        while chunkStart < to {
            let start = chunkStart
            let end = min(start.addingTimeInterval(.days(7)), to)
            values += try await statisticsContainer.performBackgroundTask { context in
                try fetch(context, start, end)
            }
            chunkStart = end
        }
        return values
    }

    private static let pumpEventProperties = [
        "date", "kind", "source", "units", "rate", "durationMin", "isSMB", "isExternal", "isMutable"
    ]

    /// The doses' kinds: a `PumpEvent` row of another (the coverage rows of earlier builds, until the store's prune
    /// deletes them) is read by nothing.
    private static var doseKinds: [NSNumber] { PumpEventKind.allCases.map { NSNumber(value: $0.rawValue) } }

    /// A `PumpEvent` row of a dictionary fetch; nil without a date, or with an unknown kind or source.
    static func pumpEventRecord(_ row: NSDictionary) -> PumpEventRecord? {
        guard let date = row["date"] as? Date,
              let kind = ((row["kind"] as? NSNumber)?.int16Value).flatMap(PumpEventKind.init(rawValue:)),
              let source = ((row["source"] as? NSNumber)?.int16Value).flatMap(PumpEventSource.init(rawValue:))
        else { return nil }
        return PumpEventRecord(
            date: date,
            kind: kind,
            source: source,
            units: (row["units"] as? NSNumber)?.doubleValue ?? 0,
            rate: (row["rate"] as? NSNumber)?.doubleValue ?? 0,
            durationMin: (row["durationMin"] as? NSNumber)?.doubleValue ?? 0,
            isSMB: (row["isSMB"] as? NSNumber)?.boolValue ?? false,
            isExternal: (row["isExternal"] as? NSNumber)?.boolValue ?? false,
            isMutable: (row["isMutable"] as? NSNumber)?.boolValue ?? false
        )
    }

    /// The dose rows, both sources, `[from, to)`, oldest -> newest.
    private static func pumpEvents(from: Date, to: Date, in context: NSManagedObjectContext) throws -> [PumpEventRecord] {
        let request = NSFetchRequest<NSDictionary>(entityName: PumpEventStore.Entity.events)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = pumpEventProperties
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        request.predicate = NSPredicate(
            format: "date >= %@ AND date < %@ AND kind IN %@",
            from as NSDate,
            to as NSDate,
            doseKinds
        )
        return try context.fetch(request).compactMap { pumpEventRecord($0) }
    }

    /// The doses of both sources (`PumpEvent` rows of kinds 0–3), `date` in `[from, to)`, oldest -> newest.
    func fetchPumpEvents(from: Date, to: Date) async throws -> [PumpEventRecord] {
        try await fetchInChunks(from: from, to: to) { context, start, end in
            try CoreDataStorage.pumpEvents(from: start, to: end, in: context)
        }
    }

    /// How far back the state running into a range is looked for: a temp lasts at most a day (24 h on Dana and
    /// Medtrum, 12 h on Omnipod); a suspension older than this still running needs a week without a temp, a resume or
    /// a pump bolus (a pump taken off, which isn't delivering).
    static let runningIntoLookback: TimeInterval = .days(7)

    /// The state running into `date`: every event (both sources) from the newest temp basal before it on, up to `date`
    /// (excluded); without a temp basal before it, from the newest suspend or resume on; none without either, all within
    /// `runningIntoLookback`. That is all the insulin statistics need of the time before `date`, as a read from the
    /// beginning would give it: the newest temp (an older one ends at its start), a suspension after it (or, without
    /// one, the newest suspend or resume) and what ends that suspension (a resume, a pump bolus). Short: a loop sets
    /// temps every few minutes.
    /// The anchor is the newest **pump** temp when there is one: the store keeps no Nightscout row inside the pump's
    /// local time (`PumpSessionRules.localTime`: the backfill skips them, the reconcile and the prune delete them), but
    /// should one be there the engine drops it, and the pump temp before it must then be read. A Nightscout temp newer than it (one in
    /// a gap of the pump's coverage) is in the range anyway. The caller reads the coverage from the anchor on (`InsulinStatsService.read`).
    func fetchPumpEventsRunningInto(_ date: Date) async throws -> [PumpEventRecord] {
        try await statisticsContainer.performBackgroundTask { context in
            let earliest = date.addingTimeInterval(-CoreDataStorage.runningIntoLookback) as NSDate
            func newest(_ kinds: [PumpEventKind], source: PumpEventSource? = nil) throws -> Date? {
                let request = NSFetchRequest<NSDictionary>(entityName: PumpEventStore.Entity.events)
                request.resultType = .dictionaryResultType
                request.propertiesToFetch = ["date"]
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                request.fetchLimit = 1
                let kinds = kinds.map { NSNumber(value: $0.rawValue) }
                request.predicate = source.map { source in
                    NSPredicate(
                        format: "date >= %@ AND date < %@ AND kind IN %@ AND source == %@",
                        earliest,
                        date as NSDate,
                        kinds,
                        NSNumber(value: source.rawValue)
                    )
                } ?? NSPredicate(format: "date >= %@ AND date < %@ AND kind IN %@", earliest, date as NSDate, kinds)
                return try context.fetch(request).first?["date"] as? Date
            }
            let start: Date
            if let temp = try newest([.tempBasal], source: .pump) ?? newest([.tempBasal]) {
                start = temp
            } else if let state = try newest([.suspend, .resume]) {
                start = state
            } else {
                return []
            }
            return try CoreDataStorage.pumpEvents(from: start, to: date, in: context)
        }
    }

    /// The pump sessions (`PumpSession`, both sources, read only) reaching into `[from, to)`: started before `to`, last
    /// seen or ended at or after `from`; any order. A few rows a month and no index: one fetch (a scan).
    func fetchPumpSessions(from: Date, to: Date) async throws -> [PumpSessionValue] {
        try await statisticsContainer.performBackgroundTask { context in
            try CoreDataStorage.pumpSessions(from: from, to: to, in: context)
        }
    }

    private static func pumpSessions(from: Date, to: Date, in context: NSManagedObjectContext) throws -> [PumpSessionValue] {
        let request = NSFetchRequest<PumpSession>(entityName: PumpEventStore.Entity.sessions)
        request.predicate = NSPredicate(
            format: "start < %@ AND (lastSeen >= %@ OR %K >= %@)",
            to as NSDate,
            from as NSDate,
            "end",
            from as NSDate
        )
        return try context.fetch(request).compactMap { CoreDataPumpEventDatabase.value(of: $0) }
    }

    /// The covered time inside `[from, to)` (clipped to it), both sources, oldest -> newest: each pump session's
    /// `[start, lastSeen]` without its gaps (`PumpSessionValue.covered`); and the pump's local time in it
    /// (`PumpSessionRules.localTime` of every pump session and the oldest pump dose row: the store's own rule), where a
    /// Nightscout event is the pump's double. Three fetches (the sessions are a few rows a month: scans).
    func fetchCoverage(from: Date, to: Date) async throws -> [CoveredInterval] {
        try await statisticsContainer.performBackgroundTask { context in
            let sessions = try CoreDataStorage.pumpSessions(from: from, to: to, in: context)
            let all = try context.fetch(NSFetchRequest<PumpSession>(entityName: PumpEventStore.Entity.sessions))
                .compactMap { CoreDataPumpEventDatabase.value(of: $0) }
            let oldest = NSFetchRequest<NSDictionary>(entityName: PumpEventStore.Entity.events)
            oldest.resultType = .dictionaryResultType
            oldest.propertiesToFetch = ["date"]
            oldest.predicate = NSPredicate(
                format: "source == %@ AND kind IN %@ AND date != nil",
                NSNumber(value: PumpEventSource.pump.rawValue),
                CoreDataStorage.doseKinds
            )
            oldest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            oldest.fetchLimit = 1
            let oldestPumpDose = try context.fetch(oldest).first?["date"] as? Date
            let local = PumpSessionRules.localTime(all, oldestPumpDose: oldestPumpDose)
            return CoreDataStorage.coverage(sessions, localTime: local, from: from, to: to)
        }
    }

    /// The sessions' covered time inside `[from, to)`, oldest -> newest (`fetchCoverage`), and the local time's pieces in
    /// it (`isCovered == false`, `pump`; closed, zero-length ones too). A pump session's `[start, localStart)` is
    /// labelled Nightscout: its prefix from the backfill (local all the same where the local time holds it: pump dose
    /// rows before the first session). For a fallback start that a late change event moved back
    /// (`PumpSessionRules.change`), that stretch is local time of at most the slack (a longer one is a gap), so the label
    /// is harmless there.
    /// - Parameter localTime: `PumpSessionRules.localTime`; nil: of `sessions` alone, without dose rows
    static func coverage(
        _ sessions: [PumpSessionValue],
        localTime: [DateInterval]? = nil,
        from: Date,
        to: Date
    ) -> [CoveredInterval] {
        guard to > from else { return [] }
        let range = DateInterval(start: from, end: to)
        let covered = sessions.flatMap { session -> [CoveredInterval] in
            let covered = PumpEventStore.intersect(session.covered, with: range)
            guard session.source == .pump else { return covered.map { CoveredInterval(interval: $0, source: .nightscout) } }
            let local = session.localStart ?? session.start
            let prefix = PumpEventStore.intersect(covered, with: DateInterval(start: .distantPast, end: local))
            let own = PumpEventStore.intersect(covered, with: DateInterval(start: local, end: .distantFuture))
            return prefix.map { CoveredInterval(interval: $0, source: .nightscout) }
                + own.map { CoveredInterval(interval: $0, source: .pump) }
        }
        let local = (localTime ?? PumpSessionRules.localTime(sessions, oldestPumpDose: nil))
            .compactMap { piece -> CoveredInterval? in
                let start = Swift.max(piece.start, from)
                let end = Swift.min(piece.end, to)
                guard start <= end, start < to else { return nil }
                return CoveredInterval(interval: DateInterval(start: start, end: end), source: .pump, isCovered: false)
            }
        return (covered + local).sorted { a, b in
            (a.interval.start, a.interval.end, a.isCovered ? 0 : 1) < (b.interval.start, b.interval.end, b.isCovered ? 0 : 1)
        }
    }

    /// The basal schedule records in effect during `[from, to)`, oldest -> newest: the newest one at or before `from`
    /// (in effect when the range starts), then those after it before `to`. Without a record at or before `from`, the
    /// oldest record instead (even at or after `to`): the time before it uses it ("Profile assumed"). One background
    /// task; rows whose entries don't decode are left out.
    func fetchBasalSchedules(from: Date, to: Date) async throws -> [BasalScheduleRecordValue] {
        try await statisticsContainer.performBackgroundTask { context in
            func scheduleRequest(_ predicate: NSPredicate, ascending: Bool, limit: Int = 0) -> NSFetchRequest<NSDictionary> {
                let request = NSFetchRequest<NSDictionary>(entityName: PumpEventStore.Entity.schedules)
                request.resultType = .dictionaryResultType
                request.propertiesToFetch = ["date", "source", "entries"]
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: ascending)]
                request.predicate = predicate
                request.fetchLimit = limit
                return request
            }
            let start = from as NSDate
            let inEffect = try context.fetch(
                scheduleRequest(NSPredicate(format: "date <= %@", start), ascending: false, limit: 1)
            )
            let first = try inEffect.isEmpty
                ? context.fetch(scheduleRequest(NSPredicate(format: "date != nil"), ascending: true, limit: 1))
                : inEffect
            let later = try context.fetch(scheduleRequest(
                NSPredicate(format: "date > %@ AND date < %@", start, to as NSDate),
                ascending: true
            ))

            // the oldest one (no record at or before `from`) can also be among the later ones
            struct Identity: Hashable {
                let date: Date
                let source: BasalScheduleSource
            }
            var seen = Set<Identity>()
            return (first + later).compactMap { row -> BasalScheduleRecordValue? in
                guard let date = row["date"] as? Date,
                      let source = ((row["source"] as? NSNumber)?.int16Value).flatMap(BasalScheduleSource.init(rawValue:)),
                      seen.insert(Identity(date: date, source: source)).inserted,
                      let json = row["entries"] as? String,
                      let entries = BasalScheduleRecordValue.decode(json)
                else { return nil }
                return BasalScheduleRecordValue(date: date, source: source, entries: entries)
            }
            .sorted { $0.date < $1.date }
        }
    }

    /// The loop's IOB (`Reasons`: `date`, `iob`), `[from, to)`, oldest -> newest. `iob` is a Decimal column: the
    /// dictionary gives an `NSDecimalNumber`, read through `NSNumber`.
    func fetchIOBPoints(from: Date, to: Date) async throws -> [IOBPoint] {
        try await fetchInChunks(from: from, to: to) { context, start, end in
            let request = NSFetchRequest<NSDictionary>(entityName: "Reasons")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["date", "iob"]
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
            return try context.fetch(request).compactMap { row -> IOBPoint? in
                guard let date = row["date"] as? Date, let iob = (row["iob"] as? NSNumber)?.doubleValue else { return nil }
                return IOBPoint(time: date, iob: iob)
            }
        }
    }

    /// The meals (`Meals` saved to the file), `actualDate` in `[from, to)`, oldest -> newest, duplicates included
    /// (`MealStatsEngine.clean` takes them out). The amounts through `NSNumber`: the model's Double, the class's
    /// `NSDecimalNumber`. With each row's fiber and micronutrients (in the unit stored, `MicroNutrient.unit`).
    func fetchMealPoints(from: Date, to: Date) async throws -> [MealPoint] {
        // one fetch of the rows and one of their micronutrients: a few rows a day, and no index on `actualDate` (chunks
        // would scan the table each)
        try await statisticsContainer.performBackgroundTask { context in
            let start = from
            let end = to
            // the row's object id: its micronutrients' `meal`
            let objectID = NSExpressionDescription()
            objectID.name = "objectID"
            objectID.expression = NSExpression.expressionForEvaluatedObject()
            objectID.expressionResultType = .objectIDAttributeType
            let request = NSFetchRequest<NSDictionary>(entityName: "Meals")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["actualDate", "createdAt", "carbs", "fat", "protein", "fiber", "id", objectID]
            request.sortDescriptors = [NSSortDescriptor(key: "actualDate", ascending: true)]
            request.predicate = NSPredicate(
                format: "savedToFile == YES AND actualDate >= %@ AND actualDate < %@",
                start as NSDate,
                end as NSDate
            )

            // the micronutrients of the same rows, one fetch: `type` is the `MicroNutrient` raw value (as
            // `micronutrientTotals` reads it), `meal` the row's object id. A preset's definitions have no meal.
            let micronutrients = NSFetchRequest<NSDictionary>(entityName: "Micronutrient")
            micronutrients.resultType = .dictionaryResultType
            micronutrients.propertiesToFetch = ["type", "amount", "meal"]
            micronutrients.predicate = NSPredicate(
                format: "meal.savedToFile == YES AND meal.actualDate >= %@ AND meal.actualDate < %@",
                start as NSDate,
                end as NSDate
            )
            var byMeal: [NSManagedObjectID: [MicroNutrient: Double]] = [:]
            for row in try context.fetch(micronutrients) {
                guard let meal = row["meal"] as? NSManagedObjectID,
                      let nutrient = (row["type"] as? String).flatMap({ MicroNutrient(rawValue: $0) }),
                      let amount = (row["amount"] as? NSNumber)?.doubleValue
                else { continue }
                byMeal[meal, default: [:]][nutrient, default: 0] += amount
            }

            return try context.fetch(request).compactMap { row -> MealPoint? in
                guard let actualDate = row["actualDate"] as? Date else { return nil }
                return MealPoint(
                    id: row["id"] as? String,
                    actualDate: actualDate,
                    createdAt: row["createdAt"] as? Date,
                    carbs: (row["carbs"] as? NSNumber)?.doubleValue ?? 0,
                    fat: (row["fat"] as? NSNumber)?.doubleValue ?? 0,
                    protein: (row["protein"] as? NSNumber)?.doubleValue ?? 0,
                    fiber: (row["fiber"] as? NSNumber)?.doubleValue ?? 0,
                    micronutrients: (row["objectID"] as? NSManagedObjectID).flatMap { byMeal[$0] } ?? [:]
                )
            }
        }
    }

    func fetchInsulinData(interval: NSDate) async -> [IOBEntryShort] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestTicks = InsulinActivity.fetchRequest()
            let sort = NSSortDescriptor(key: "date", ascending: true)
            requestTicks.sortDescriptors = [sort]
            requestTicks.predicate = NSPredicate(
                format: "date > %@", interval
            )
            let fetchTicks = (try? context.fetch(requestTicks)) ?? []
            let result = fetchTicks.compactMap { tick -> IOBEntryShort? in
                guard let date = tick.date, let activity = tick.activity, let iob = tick.iob else {
                    return nil
                }
                return IOBEntryShort(
                    time: date,
                    iob: iob as Decimal,
                    activity: activity as Decimal
                )
            }
            return result
        }
    }

    func fetchLatestInsulinData() async -> IOBEntryShort? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestTicks = InsulinActivity.fetchRequest()
            let sort = NSSortDescriptor(key: "date", ascending: true)
            requestTicks.sortDescriptors = [sort]
            requestTicks.fetchLimit = 1
            let fetchTicks = (try? context.fetch(requestTicks)) ?? []

            return fetchTicks.firstNonNil { tick -> IOBEntryShort? in
                guard let date = tick.date, let activity = tick.activity, let iob = tick.iob else {
                    return nil
                }
                return IOBEntryShort(
                    time: date,
                    iob: iob as Decimal,
                    activity: activity as Decimal
                )
            }
        }
    }

    @discardableResult func saveInsulinData(iobEntries: [IOBEntry]) async -> [IOBEntryShort] {
        guard let firstDate = iobEntries.compactMap(\.time).min() else { return [] }

        return await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let deleteRequest = InsulinActivity.fetchRequest()
            deleteRequest.predicate = NSPredicate(
                format: "date >= %@ OR date < %@",
                firstDate.addingTimeInterval(-60) as NSDate, // delete previous "future" entries
                firstDate.addingTimeInterval(-86400) as NSDate // delete entries older than 1 day
            )
            if let recordsToDelete = try? context.fetch(deleteRequest) {
                for record in recordsToDelete {
                    context.delete(record)
                }
            }

            for iobEntry in iobEntries {
                let record = InsulinActivity(context: context)
                record.date = iobEntry.time
                record.iob = NSDecimalNumber(decimal: iobEntry.iob)
                record.activity = NSDecimalNumber(decimal: iobEntry.activity)
            }
            try? context.save()

            let windowRequest = InsulinActivity.fetchRequest()
            windowRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            windowRequest.predicate = NSPredicate(
                format: "date > %@",
                Date.now.subtractingTimeInterval(.hours(24)) as NSDate
            )
            let saved = (try? context.fetch(windowRequest)) ?? []
            return saved.compactMap { tick -> IOBEntryShort? in
                guard let date = tick.date, let activity = tick.activity, let iob = tick.iob else {
                    return nil
                }
                return IOBEntryShort(time: date, iob: iob as Decimal, activity: activity as Decimal)
            }
        }
    }

    /// The loop records started after `since`, newest -> oldest, also the first loop after a gap (`interval` 0): the
    /// Statistics loop numbers and the Home Loops card count every loop. Fetched as plain values.
    func fetchLoopStatRecords(since: Date) async -> [LoopStatRecordSnapshot] {
        await statisticsContainer.performBackgroundTask { context in
            let request = NSFetchRequest<NSDictionary>(entityName: "LoopStatRecord")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["start", "end", "duration", "interval", "loopStatus", "error"]
            request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]
            request.predicate = NSPredicate(format: "start > %@", since as NSDate)
            do {
                return try context.fetch(request).map { row in
                    LoopStatRecordSnapshot(
                        start: row["start"] as? Date,
                        end: row["end"] as? Date,
                        duration: (row["duration"] as? NSNumber)?.doubleValue ?? 0,
                        interval: (row["interval"] as? NSNumber)?.doubleValue ?? 0,
                        loopStatus: row["loopStatus"] as? String,
                        error: row["error"] as? String
                    )
                }
            } catch {
                debug(.service, "failed to fetch the loop records: \(error)")
                return []
            }
        }
    }

    func fetchLoopStarts(interval: NSDate) async -> [Date] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: true)]
            request.predicate = NSPredicate(format: "start > %@", interval)
            return ((try? context.fetch(request)) ?? []).compactMap(\.start)
        }
    }

    func fetchTDD(interval: NSDate) async -> [TDDSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestTDD = TDD.fetchRequest() as NSFetchRequest<TDD>
            requestTDD.predicate = NSPredicate(format: "timestamp > %@ AND tdd > 0", interval)
            let sortTDD = NSSortDescriptor(key: "timestamp", ascending: false)
            requestTDD.sortDescriptors = [sortTDD]
            let uniqueEvents = (try? context.fetch(requestTDD)) ?? []
            return uniqueEvents.map { TDDSnapshot.create(from: $0) }
        }
    }

    func saveTDD(_ insulin: (bolus: Decimal, basal: Decimal, hours: Double)) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveToTDD = TDD(context: context)
            saveToTDD.timestamp = Date.now
            saveToTDD.tdd = (insulin.basal + insulin.bolus) as NSDecimalNumber?
            let saveToInsulin = InsulinDistribution(context: context)
            saveToInsulin.bolus = insulin.bolus as NSDecimalNumber?
            // saveToInsulin.scheduledBasal = (suggestion.insulin?.scheduled_basal ?? 0) as NSDecimalNumber?
            saveToInsulin.tempBasal = insulin.basal as NSDecimalNumber?
            saveToInsulin.date = Date()
            try? context.save()
        }
    }

    /// The newest HBT row of the temp target with this id.
    func fetchTempTargetHBT(id: String) async -> TempTargetsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = TempTargets.fetchRequest() as NSFetchRequest<TempTargets>
            request.predicate = NSPredicate(format: "id == %@", id)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.fetchLimit = 1
            return ((try? context.fetch(request)) ?? []).first.map { TempTargetsSnapshot.create(from: $0) }
        }
    }

    /// The half basal target of an enacted temp target (`active == false`: no % temp target).
    func saveTempTargetHBT(id: String, active: Bool, hbt: Double?, duration: Decimal, startDate: Date) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let row = TempTargets(context: context)
            row.id = id
            row.active = active
            if let hbt {
                row.hbt = hbt
            }
            row.date = Date()
            row.duration = duration as NSDecimalNumber
            row.startDate = startDate
            do {
                try context.save()
            } catch {
                debug(.service, "temp target HBT couldn't be saved to CoreData: \(error.localizedDescription)")
            }
        }
    }

    /// The half basal target of a % temp target preset, by the preset's id.
    func saveTempTargetHBTPreset(id: String, hbt: Double, duration: Decimal) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let row = TempTargetsSlider(context: context)
            row.id = id
            row.isPreset = true
            row.enabled = true
            row.hbt = hbt
            row.date = Date()
            row.duration = duration as NSDecimalNumber
            do {
                try context.save()
            } catch {
                debug(.service, "temp target preset HBT couldn't be saved to CoreData: \(error.localizedDescription)")
            }
        }
    }

    func fetchTempTargetHBTPreset(id: String) async -> TempTargetsSliderSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            request.predicate = NSPredicate(format: "id == %@ AND isPreset == YES", id)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.fetchLimit = 1
            return ((try? context.fetch(request)) ?? []).first.map { TempTargetsSliderSnapshot.create(from: $0) }
        }
    }

    func deleteTempTargetHBTPresets(id: String) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            request.predicate = NSPredicate(format: "id == %@", id)
            let rows = (try? context.fetch(request)) ?? []
            guard rows.isNotEmpty else { return }
            rows.forEach { context.delete($0) }
            do {
                try context.save()
            } catch {
                debug(.service, "temp target preset HBT couldn't be deleted from CoreData: \(error.localizedDescription)")
            }
        }
    }

    /// The newest preset HBT, to seed the slider (skips the old cancel rows).
    func fetchLastHBT() async -> Double? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            request.predicate = NSPredicate(format: "isPreset == YES")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.fetchLimit = 1
            return ((try? context.fetch(request)) ?? []).first?.hbt
        }
    }

    /// Fetch saved meals within interval, future entries excluded
    func fetchMealData(interval: NSDate) async -> [MealsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let now = NSDate()
            let requestData = Meals.fetchRequest()
            let sortData = NSSortDescriptor(key: "actualDate", ascending: false)
            requestData.sortDescriptors = [sortData]
            requestData.predicate = NSPredicate(
                format: "savedToFile == true AND actualDate > %@ AND actualDate <= %@",
                interval,
                now
            )
            let data = (try? context.fetch(requestData)) ?? []
            print("Meal Flow: \(data.count) entries retrieved")
            return data.map { MealsSnapshot.create(from: $0) }
        }
    }

    func fetchStats() async -> StatsDataSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestStats = StatsData.fetchRequest() as NSFetchRequest<StatsData>
            let sortStats = NSSortDescriptor(key: "lastrun", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            let stats = (try? context.fetch(requestStats)) ?? []
            return stats.map { StatsDataSnapshot.create(from: $0) }.first
        }
    }

    func fetchInsulinDistribution() async -> InsulinDistributionSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestInsulinDistribution = InsulinDistribution.fetchRequest() as NSFetchRequest<InsulinDistribution>
            let sortInsulin = NSSortDescriptor(key: "date", ascending: false)
            requestInsulinDistribution.sortDescriptors = [sortInsulin]
            requestInsulinDistribution.fetchLimit = 1
            let insulinDistribution = (try? context.fetch(requestInsulinDistribution)) ?? []
            return insulinDistribution.map { InsulinDistributionSnapshot.create(from: $0) }.first
        }
    }

    // TODO: no longer used
    func fetchReason() async -> ReasonsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.fetchLimit = 1
            let suggestions = (try? context.fetch(requestReasons)) ?? []
            return suggestions.map { ReasonsSnapshot.create(from: $0) }.first
        }
    }

    func fetchReasons(interval: NSDate) async -> [ReasonsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.predicate = NSPredicate(
                format: "date > %@", interval
            )
            let reasonArray = (try? context.fetch(requestReasons)) ?? []
            return reasonArray.map { ReasonsSnapshot.create(from: $0) }
        }
    }

    // TODO: duplicate of fetchReason() ?
    // TODO: no longer used
    func recentReason() async -> ReasonsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.fetchLimit = 1
            let reasonArray = (try? context.fetch(requestReasons)) ?? []
            return reasonArray.map { ReasonsSnapshot.create(from: $0) }.first
        }
    }

    func saveStatUploadCount() async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveStatsCoreData = StatsData(context: context)
            saveStatsCoreData.lastrun = Date()
            try? context.save()
        }
        UserDefaults.standard.set(false, forKey: IAPSconfig.newVersion)
    }

    func saveVersion(_ versions: Version?) async {
        guard let version = versions else { return }
        guard version.main != "" else { return }
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveNr = VNr(context: context)
            saveNr.nr = version.main
            saveNr.dev = version.dev

            if context.hasChanges {
                saveNr.date = Date.now
                try? context.save()
            }
        }
    }

    func fetchVersion() async -> VNrSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestNr = VNr.fetchRequest() as NSFetchRequest<VNr>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestNr.sortDescriptors = [sort]
            requestNr.fetchLimit = 1
            let nr = (try? context.fetch(requestNr)) ?? []
            return nr.map { VNrSnapshot.create(from: $0) }.first
        }
    }

    /// Saves a Meals row per entry. Upsert by id: saving a meal again updates its row, and drops any other copies of it
    /// (left by the old insert-only save of the Nightscout carbs, which ran on every fetch)
    func saveMeals(_ entries: [CarbsEntry]) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            for entry in entries {
                let id = entry.id ?? ""
                var existing: [Meals] = []
                if !id.isEmpty {
                    let request = Meals.fetchRequest() as NSFetchRequest<Meals>
                    request.predicate = NSPredicate(format: "id == %@", id)
                    // the row `deduplicateMealsOnce` keeps (the earliest) stays
                    request.sortDescriptors = [NSSortDescriptor(key: "actualDate", ascending: true)]
                    existing = (try? context.fetch(request)) ?? []
                }
                existing.dropFirst().forEach { context.delete($0) }
                let save = existing.first ?? Meals(context: context)
                // an updated row gets its micronutrients replaced
                (save.micronutrient as? Set<Micronutrient>)?.forEach { context.delete($0) }

                save.createdAt = entry.createdAt
                save.actualDate = entry.actualDate ?? entry.createdAt
                save.id = id
                save.carbs = entry.carbs as NSDecimalNumber
                save.fat = (entry.fat ?? 0) as NSDecimalNumber
                save.protein = (entry.protein ?? 0) as NSDecimalNumber
                save.fiber = (entry.fiber ?? 0) as NSDecimalNumber
                save.note = entry.note
                save.savedToFile = true

                // MARK: Are there any micronutrients?

                if let micros = entry.micronutrient {
                    for value in micros {
                        guard value.amount != 0 else { continue }
                        let micro = Micronutrient(context: context)

                        micro.id = UUID()
                        micro.name = value.name
                        micro.type = value.substance.rawValue
                        micro.unit = value.unit
                        micro.amount = NSDecimalNumber(decimal: value.amount)
                        micro.meal = save

                        save.addToMicronutrients(micro)
                    }
                }
            }

            do {
                try context.save()
            } catch {
                debug(.apsManager, "Meals couldn't be saved: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes the Meals rows of these ids. A context delete: it cascades to the micronutrients (a batch delete does not)
    func deleteMeals(ids: [String]) async {
        guard ids.isNotEmpty else { return }
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request = Meals.fetchRequest() as NSFetchRequest<Meals>
            request.predicate = NSPredicate(format: "id IN %@", ids)
            let meals = (try? context.fetch(request)) ?? []
            meals.forEach { context.delete($0) }
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                debug(.apsManager, "Meals couldn't be deleted: \(error.localizedDescription)")
            }
        }
    }

    private static let mealsDeduplicatedKey = "meals.deduplicatedByID"

    /// Once, in the background (it can be long: an older version saved a downloaded meal again on every fetch, one row
    /// per minute for 24 h). By the ids with more than one row, a chunk at a time: the duplicates go in batch deletes.
    /// Those rows (Nightscout downloads) never had micronutrients, so the batch delete leaves none behind
    func deduplicateMealsOnce() async {
        guard !UserDefaults.standard.bool(forKey: Self.mealsDeduplicatedKey) else { return }
        let done = await CoreDataStack.shared.persistentContainer.performBackgroundTask { context -> Bool in
            let request = NSFetchRequest<NSDictionary>(entityName: "Meals")
            request.resultType = .dictionaryResultType
            let count = NSExpressionDescription()
            count.name = "count"
            count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "id")])
            count.expressionResultType = .integer64AttributeType
            request.propertiesToFetch = ["id", count]
            request.propertiesToGroupBy = ["id"]
            request.predicate = NSPredicate(format: "id != nil AND id != %@", "")
            guard let grouped = try? context.fetch(request) else { return false }
            let ids = grouped.compactMap { row -> String? in
                let rows = (row["count"] as? NSNumber)?.intValue ?? 0
                guard rows > 1 else { return nil }
                return row["id"] as? String
            }

            var deleted = 0
            for chunk in CoreDataStorage.chunked(ids, size: 50) {
                guard let chunkDeleted = CoreDataStorage.deleteDuplicateMeals(ids: chunk, in: context) else { return false }
                deleted += chunkDeleted
            }
            debug(.apsManager, "Meals: \(deleted) duplicate rows deleted")
            return true
        }
        if done {
            UserDefaults.standard.set(true, forKey: Self.mealsDeduplicatedKey)
        }
    }

    /// The duplicate rows of these ids deleted (batch deletes, merged into the contexts); nil when it failed
    private static func deleteDuplicateMeals(ids: [String], in context: NSManagedObjectContext) -> Int? {
        let request = NSFetchRequest<NSDictionary>(entityName: "Meals")
        request.resultType = .dictionaryResultType
        let objectID = NSExpressionDescription()
        objectID.name = "objectID"
        objectID.expression = NSExpression.expressionForEvaluatedObject()
        objectID.expressionResultType = .objectIDAttributeType
        request.propertiesToFetch = [objectID, "id", "actualDate"]
        request.predicate = NSPredicate(format: "id IN %@", ids)
        guard let rows = try? context.fetch(request) else { return nil }

        let parsed = rows.compactMap { row -> (objectID: NSManagedObjectID, id: String, actualDate: Date?)? in
            guard let objectID = row["objectID"] as? NSManagedObjectID, let id = row["id"] as? String else { return nil }
            return (objectID: objectID, id: id, actualDate: row["actualDate"] as? Date)
        }
        let duplicates = duplicateMealRows(parsed.map { (id: $0.id, actualDate: $0.actualDate) })
        let objectIDs = duplicates.sorted().map { parsed[$0].objectID }

        for batch in chunked(objectIDs, size: 1000) {
            let delete = NSBatchDeleteRequest(objectIDs: batch)
            delete.resultType = .resultTypeObjectIDs
            do {
                let result = try context.execute(delete) as? NSBatchDeleteResult
                if let deleted = result?.result as? [NSManagedObjectID] {
                    CoreDataStack.shared.mergeBatchDelete(deleted)
                }
            } catch {
                debug(.apsManager, "Meals couldn't be deduplicated: \(error.localizedDescription)")
                return nil
            }
        }
        return objectIDs.count
    }

    /// The indices of the duplicate rows: of the rows of an id, the one with the earliest actual date stays (no date
    /// first, as the store sorts it, see `saveMeals`)
    static func duplicateMealRows(_ rows: [(id: String, actualDate: Date?)]) -> Set<Int> {
        var kept: [String: Int] = [:]
        var duplicates = Set<Int>()
        for (index, row) in rows.enumerated() where !row.id.isEmpty {
            guard let keptIndex = kept[row.id] else {
                kept[row.id] = index
                continue
            }
            let keptDate = rows[keptIndex].actualDate ?? .distantPast
            if (row.actualDate ?? .distantPast) < keptDate {
                duplicates.insert(keptIndex)
                kept[row.id] = index
            } else {
                duplicates.insert(index)
            }
        }
        return duplicates
    }

    /// `items` in chunks of `size` (the last one shorter)
    static func chunked<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [items] }
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0 ..< min($0 + size, items.count)]) }
    }

    func fetchMealPreset(_ name: String) async -> PresetsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
            requestPresets.predicate = NSPredicate(
                format: "dish == %@", name
            )
            requestPresets.fetchLimit = 1

            let presetsArray = (try? context.fetch(requestPresets)) ?? []

            return presetsArray.map { PresetsSnapshot.create(from: $0) }.first
        }
    }

    func fetchMealPresets() async -> [PresetsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
            requestPresets.predicate = NSPredicate(
                format: "dish != %@", "" as String
            )
            let presetsArray = (try? context.fetch(requestPresets)) ?? []
            return presetsArray.map { PresetsSnapshot.create(from: $0) }
        }
    }

    func fetchOnbarding() async -> Bool {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestBool = Onboarding.fetchRequest() as NSFetchRequest<Onboarding>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestBool.sortDescriptors = [sort]
            requestBool.fetchLimit = 1
            return ((try? context.fetch(requestBool)) ?? []).first?.firstRun ?? true
        }
    }

    func saveOnbarding() async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Onboarding(context: context)
            save.firstRun = false
            save.date = Date.now
            try? context.save()
        }
    }

    func startOnbarding() async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Onboarding(context: context)
            save.firstRun = true
            save.date = Date.now
            try? context.save()
        }
    }

    func fetchSettingProfileName() async -> String {
        await fetchActiveProfile()
    }

    func fetchSettingProfileNames() async -> [ProfilesSnapshot]? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestProfiles = Profiles.fetchRequest() as NSFetchRequest<Profiles>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            let profilesArray = (try? context.fetch(requestProfiles)) ?? []
            return profilesArray.map { ProfilesSnapshot.create(from: $0) }
        }
    }

    func saveProfileSettingName(name: String) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Profiles(context: context)
            save.name = name
            save.date = Date.now
            try? context.save()
        }
    }

    func migrateProfileSettingName(name: String) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Profiles(context: context)
            save.name = name
            save.date = Date.now
            save.uploaded = true
            try? context.save()
        }
    }

    func profileSettingUploaded(name: String) async {
        // Avoid duplicates
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in

            func fetchUniqueSettingProfileName(_ name: String) -> Bool {
                let requestProfiles = Profiles.fetchRequest() as NSFetchRequest<Profiles>
                let sort = NSSortDescriptor(key: "date", ascending: false)
                requestProfiles.sortDescriptors = [sort]
                requestProfiles.predicate = NSPredicate(
                    format: "uploaded == true && name == %@", name as String
                )
                requestProfiles.fetchLimit = 1
                return ((try? context.fetch(requestProfiles)) ?? []).isNotEmpty
            }

            if !fetchUniqueSettingProfileName(name) {
                var profile: String = name
                if profile.isEmpty {
                    profile = "default"
                }

                let save = Profiles(context: context)
                save.name = profile
                save.date = Date.now
                save.uploaded = true
                try? context.save()
            }
        }
    }

    func activeProfile(name: String) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = ActiveProfile(context: context)
            save.name = name
            save.date = Date.now
            save.active = true
            try? context.save()
        }
    }

    func checkIfActiveProfile() async -> Bool {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            requestProfiles.fetchLimit = 1

            let presetsArray = (try? context.fetch(requestProfiles)) ?? []
            return (presetsArray.first?.active ?? false)
        }
    }

    func fetchActiveProfile() async -> String {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            requestProfiles.fetchLimit = 1

            let presetsArray = (try? context.fetch(requestProfiles)) ?? []
            return presetsArray.first?.name ?? "default"
        }
    }

    func fetchLastLoop() async -> LastLoopSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestLastLoop = LastLoop.fetchRequest() as NSFetchRequest<LastLoop>
            let sortLoops = NSSortDescriptor(key: "timestamp", ascending: false)
            requestLastLoop.sortDescriptors = [sortLoops]
            requestLastLoop.fetchLimit = 1
            let lastLoop = (try? context.fetch(requestLastLoop)) ?? []
            return lastLoop.map { LastLoopSnapshot.create(from: $0) }.first
        }
    }

    func saveConcentration(_ concentration: Double, increment: Decimal) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let row = InsulinConcentration(context: context)
            row.concentration = concentration
            row.incrementSetting = Double(increment)
            row.date = Date.now
            do {
                try context.save()
            } catch {
                debug(.service, "insulin concentration couldn't be saved to CoreData: \(error.localizedDescription)")
            }
        }
    }

    func insulinConcentration() async -> (concentration: Double, increment: Double) {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestConc = InsulinConcentration.fetchRequest() as NSFetchRequest<InsulinConcentration>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestConc.sortDescriptors = [sort]
            requestConc.fetchLimit = 1
            let conc = (try? context.fetch(requestConc)) ?? []
            let recent = conc.first
            return (recent?.concentration ?? 1.0, recent?.incrementSetting ?? 0.1)
        }
    }

    func deleteBatch(identifier: String?, entity: String) async {
        guard let id = identifier else { return }
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<NSFetchRequestResult>
            fetchRequest = NSFetchRequest(entityName: entity)
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: fetchRequest
            )
            deleteRequest.resultType = .resultTypeObjectIDs
            do {
                let deleteResult = try context.execute(deleteRequest) as? NSBatchDeleteResult
                if let objectIDs = deleteResult?.result as? [NSManagedObjectID] {
                    CoreDataStack.shared.mergeBatchDelete(objectIDs)
                }
            } catch { debug(.apsManager, entity + "records failed to delete in batch.") }
        }
    }
}

extension CoreDataStorage: MealRowStore {}

extension CoreDataStorage: InsulinDataSource {}

// public typealias PresetsCoreDataClassSet = NSSet

@objc(Presets) class Presets: NSManagedObject {
    @NSManaged public var carbs: NSDecimalNumber?
    @NSManaged public var dish: String?
    @NSManaged public var fat: NSDecimalNumber?
    @NSManaged public var fiber: NSDecimalNumber?
    @NSManaged public var foodID: UUID?
    @NSManaged public var glycemicIndex: NSDecimalNumber?
    @NSManaged public var imageURL: String?
    @NSManaged public var mealUnits: String?
    @NSManaged public var per100: Bool
    @NSManaged public var portionSize: NSDecimalNumber?
    @NSManaged public var protein: NSDecimalNumber?
    @NSManaged public var standardName: String?
    @NSManaged public var standardServing: String?
    @NSManaged public var standardServingSize: NSDecimalNumber?
    @NSManaged public var sugars: NSDecimalNumber?
    @NSManaged public var tags: String?
    @NSManaged public var micronutrient: Set<PresetMicronutrient>?
}

@objc(Micronutrient) class Micronutrient: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var type: String
    @NSManaged public var amount: NSDecimalNumber?
    @NSManaged public var unit: String?
    @NSManaged public var entries: Set<PresetMicronutrient>
}

@objc(PresetMicronutrient) class PresetMicronutrient: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged var amount: NSDecimalNumber?
    @NSManaged var per100: Bool
    @NSManaged var preset: Presets
    @NSManaged var micronutrient: Micronutrient
}

extension Presets {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Presets> {
        NSFetchRequest<Presets>(entityName: "Presets")
    }

    @objc(addMicronutrientObject:)
    @NSManaged public func addToMicronutrients(_ value: PresetMicronutrient)

    @objc(removeMicronutrientsObject:)
    @NSManaged public func removeFromMicronutrients(_ value: PresetMicronutrient)

    @objc(addMicronutrients:)
    @NSManaged public func addToMicronutrients(_ values: NSSet)

    @objc(removeMicronutrients:)
    @NSManaged public func removeFromMicronutrients(_ values: NSSet)

    func micronutrientValues() -> [PresetMicronutrient] {
        let set = micronutrient ?? []

        return set.sorted {
            ($0.micronutrient.name ?? "") < ($1.micronutrient.name ?? "")
        }
    }

    func setMicronutrient(
        name: String,
        type: String,
        unit: String,
        amount: Decimal,
        per100: Bool,
        context: NSManagedObjectContext
    ) throws {
        // 1. Fetch or create Micronutrient definition
        let micronutrient: Micronutrient

        if let existing = try Micronutrient.fetchByName(name, context: context) {
            micronutrient = existing
        } else {
            let new = Micronutrient(context: context)
            new.id = UUID()
            new.name = name
            new.type = type
            new.unit = unit
            micronutrient = new
        }

        // 2. Check if this preset already has this micronutrient
        let existingEntry = (self.micronutrient ?? [])
            .first(where: { $0.micronutrient == micronutrient })

        if let entry = existingEntry {
            // Update
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
        } else {
            // Create
            let entry = PresetMicronutrient(context: context)
            entry.id = UUID()
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
            entry.preset = self
            entry.micronutrient = micronutrient
        }
    }

    func replaceMicronutrients(
        with values: [(name: String, type: String, unit: String, amount: Decimal, per100: Bool)],
        context: NSManagedObjectContext
    ) throws {
        // Remove
        if let existing = micronutrient {
            for item in existing {
                context.delete(item)
            }
        }

        // New
        for value in values {
            try setMicronutrient(
                name: value.name,
                type: value.type,
                unit: value.unit,
                amount: value.amount,
                per100: value.per100,
                context: context
            )
        }
    }

    func allNutrients() -> [NutrientValue] {
        var results: [NutrientValue] = []

        // Macro nutrients
        if let carbs = carbs?.decimalValue {
            results.append(NutrientValue(name: "Carbs", amount: carbs, unit: "g"))
        }

        if let fat = fat?.decimalValue {
            results.append(NutrientValue(name: "Fat", amount: fat, unit: "g"))
        }

        if let protein = protein?.decimalValue {
            results.append(NutrientValue(name: "Protein", amount: protein, unit: "g"))
        }

        if let fiber = fiber?.decimalValue {
            results.append(NutrientValue(name: "Fiber", amount: fiber, unit: "g"))
        }

        if let sugars = sugars?.decimalValue {
            results.append(NutrientValue(name: "Sugars", amount: sugars, unit: "g"))
        }

        // Micronutrients
        let micros = micronutrientValuesTyped()

        for micro in micros {
            results.append(
                NutrientValue(
                    name: micro.name,
                    amount: micro.amount,
                    unit: micro.unit
                )
            )
        }
        return results
    }

    func applyMicronutrients(
        from values: [MicronutrientValue],
        context: NSManagedObjectContext
    ) throws {
        for value in values {
            try setMicronutrient(
                value.substance,
                amount: value.amountPer100,
                per100: true,
                context: context
            )
        }
    }

    func replaceMicronutrients(
        from values: [MicronutrientValue],
        context: NSManagedObjectContext
    ) throws {
        if let existing = micronutrient {
            for entry in existing {
                context.delete(entry)
            }
        }

        for value in values where value.amount > 0 || value.amountPer100 > 0 {
            try setMicronutrient(
                value.substance,
                amount: value.amountPer100,
                per100: true,
                context: context
            )
        }
    }

    func setMicronutrient(
        _ nutrient: MicroNutrient,
        amount: Decimal,
        per100: Bool,
        context: NSManagedObjectContext
    ) throws {
        let definition: Micronutrient

        if let existing = try Micronutrient.fetchByName(
            nutrient.coreDataName,
            context: context
        ) {
            definition = existing
            definition.type = nutrient.coreDataType
            definition.unit = nutrient.unit
        } else {
            let new = Micronutrient(context: context)
            new.id = UUID()
            new.name = nutrient.coreDataName
            new.type = nutrient.coreDataType
            new.unit = nutrient.unit
            definition = new
        }

        let existingEntry = (micronutrient ?? [])
            .first { $0.micronutrient == definition }

        if let entry = existingEntry {
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
        } else {
            let entry = PresetMicronutrient(context: context)
            entry.id = UUID()
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
            entry.preset = self
            entry.micronutrient = definition
        }
    }

    func micronutrientValuesTyped() -> [MicronutrientValue] {
        (micronutrient ?? [])
            .compactMap { entry in
                guard
                    let name = entry.micronutrient.name,
                    let substance = MicroNutrient(coreDataName: name),
                    let storedAmount = entry.amount?.decimalValue
                else {
                    return nil
                }

                let amountPer100: Decimal
                let amount: Decimal

                if entry.per100 {
                    amountPer100 = storedAmount

                    if let portion = portionSize?.decimalValue, portion > 0 {
                        amount = storedAmount / 100 * portion
                    } else {
                        amount = storedAmount
                    }
                } else {
                    amount = storedAmount

                    if let portion = portionSize?.decimalValue, portion > 0 {
                        amountPer100 = storedAmount / portion * 100
                    } else {
                        amountPer100 = storedAmount
                    }
                }

                return MicronutrientValue(
                    substance: substance,
                    amount: amount,
                    amountPer100: amountPer100
                )
            }
            .sorted { $0.name < $1.name }
    }
}

extension Micronutrient {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Micronutrient> {
        NSFetchRequest<Micronutrient>(entityName: "Micronutrient")
    }

    static func fetchAll(
        context: NSManagedObjectContext
    ) throws -> [Micronutrient] {
        let request: NSFetchRequest<Micronutrient> = Micronutrient.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "type", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return try context.fetch(request)
    }

    /// A preset's definition row of this name (no meal). A meal's own rows share the names: one of them as a preset's
    /// definition would get its `type` overwritten and be deleted with the meal's next edit.
    static func fetchByName(
        _ name: String,
        context: NSManagedObjectContext
    ) throws -> Micronutrient? {
        let request: NSFetchRequest<Micronutrient> = Micronutrient.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@ AND meal == nil", name)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    @NSManaged public var meal: Meals?
}

struct NutrientValue {
    let name: String
    let amount: Decimal
    let unit: String
}

@objc(NightTimeConfigurationBox) public final class NightTimeConfigurationBox: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let enabled: Bool

    init(_ value: NightTimeConfiguration) {
        startHour = value.startHour
        startMinute = value.startMinute
        endHour = value.endHour
        endMinute = value.endMinute
        enabled = value.enabled
        super.init()
    }

    var value: NightTimeConfiguration {
        NightTimeConfiguration(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            enabled: enabled
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(startHour, forKey: "startHour")
        coder.encode(startMinute, forKey: "startMinute")
        coder.encode(endHour, forKey: "endHour")
        coder.encode(endMinute, forKey: "endMinute")
        coder.encode(enabled, forKey: "enabled")
    }

    public required init?(coder: NSCoder) {
        startHour = coder.decodeInteger(forKey: "startHour")
        startMinute = coder.decodeInteger(forKey: "startMinute")
        endHour = coder.decodeInteger(forKey: "endHour")
        endMinute = coder.decodeInteger(forKey: "endMinute")
        enabled = coder.decodeBool(forKey: "enabled")
        super.init()
    }
}

public typealias MealsCoreDataClassSet = NSSet
@objc(Meals)
public class Meals: NSManagedObject {}

public typealias MealsCoreDataPropertiesSet = NSSet

extension Meals {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Meals> {
        NSFetchRequest<Meals>(entityName: "Meals")
    }

    @NSManaged var carbs: NSDecimalNumber?
    @NSManaged var date: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var actualDate: Date?
    @NSManaged var enteredBy: String?
    @NSManaged var fat: NSDecimalNumber?
    @NSManaged var id: String?
    @NSManaged var note: String?
    @NSManaged var protein: NSDecimalNumber?
    @NSManaged var fiber: NSDecimalNumber?
    @NSManaged var fpuID: String?
    @NSManaged var savedToFile: Bool
    @NSManaged var micronutrient: NSSet?

    @NSManaged public var micronutrientsData: Data?

    @objc(addMicronutrientObject:)
    @NSManaged func addToMicronutrients(_ value: Micronutrient)

    @objc(removeMicronutrientsObject:)
    @NSManaged func removeFromMicronutrients(_ value: Micronutrient)

    @objc(addMicronutrients:)
    @NSManaged func addToMicronutrients(_ values: Set<Micronutrient>)

    @objc(removeMicronutrients:)
    @NSManaged func removeFromMicronutrients(_ values: Set<Micronutrient>)

    var micronutrientTotals: [MicroNutrient: Decimal] {
        guard let micronutrients = micronutrient as? Set<Micronutrient> else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: micronutrients.compactMap { item -> (MicroNutrient, Decimal)? in
                guard let nutrient = MicroNutrient(rawValue: item.type), let amount = item.amount else {
                    return nil
                }

                return (
                    nutrient,
                    amount as Decimal
                )
            }
        )
    }

    var micronutrientValues: [MicronutrientValue] {
        guard let items = micronutrient?.allObjects as? [Micronutrient] else {
            return []
        }

        return items.compactMap { item in
            guard let substance = MicroNutrient(rawValue: item.type), let amount = item.amount?.decimalValue else {
                return nil
            }

            return MicronutrientValue(
                substance: substance,
                amount: amount,
                amountPer100: 0
            )
        }
        .sorted { $0.name < $1.name }
    }
}
