import Combine
import CoreData
@testable import FreeAPS
import XCTest

private final class BackfillClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ now: Date) {
        current = now
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

private final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [InsulinDataChange] = []

    func append(_ item: InsulinDataChange) {
        lock.withLock { items.append(item) }
    }

    func clear() {
        lock.withLock { items.removeAll() }
    }

    var all: [InsulinDataChange] {
        lock.withLock { items }
    }
}

private struct PageFailure: Error {}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Double] = []

    func append(_ item: Double) {
        lock.withLock { items.append(item) }
    }

    var all: [Double] {
        lock.withLock { items }
    }
}

/// The real database; its backfill batches fail from the `failFrom`-th on (1-based; 0: never), and its Nightscout
/// sessions' write with `failSessions`.
private actor FailingDatabase: PumpEventDatabase {
    private let base: CoreDataPumpEventDatabase
    private let failFrom: Int
    private let failSessions: Bool
    private var batches = 0

    init(_ base: CoreDataPumpEventDatabase, failFrom: Int, failSessions: Bool = false) {
        self.base = base
        self.failFrom = failFrom
        self.failSessions = failSessions
    }

    func reconcile(_ request: PumpEventStore.ReconcileRequest) async throws -> PumpEventStore.ReconcileResult {
        try await base.reconcile(request)
    }

    func deleteEvents(_ identities: Set<PumpEventRecord.Identity>, now: Date) async throws -> DateInterval? {
        try await base.deleteEvents(identities, now: now)
    }

    func prune(cutoff: Date) async throws -> PumpEventStore.PruneResult {
        try await base.prune(cutoff: cutoff)
    }

    func wipeEvents() async throws {
        try await base.wipeEvents()
    }

    func wipeSessions() async throws {
        try await base.wipeSessions()
    }

    func applyLifecycleEvents(_ events: [PumpLifecycleEvent], now: Date) async throws -> PumpEventStore.LifecycleResult {
        try await base.applyLifecycleEvents(events, now: now)
    }

    func recordSchedule(_ schedule: PumpEventStore.ScheduleInsert) async throws -> Bool {
        try await base.recordSchedule(schedule)
    }

    func wipeSchedules() async throws {
        try await base.wipeSchedules()
    }

    func storeBackfill(_ batch: PumpEventStore.BackfillBatch) async throws -> PumpEventStore.BackfillBatchResult {
        batches += 1
        if failFrom > 0, batches >= failFrom {
            throw PageFailure()
        }
        return try await base.storeBackfill(batch)
    }

    func storeSchedules(_ schedules: [PumpEventStore.ScheduleInsert], now: Date) async throws -> PumpEventStore
        .ScheduleBackfillResult
    {
        try await base.storeSchedules(schedules, now: now)
    }

    func storeNightscoutSessions(_ request: PumpEventStore.NightscoutSessionsRequest) async throws -> PumpEventStore
        .NightscoutSessionsResult
    {
        if failSessions {
            throw PageFailure()
        }
        return try await base.storeNightscoutSessions(request)
    }
}

/// A fake Nightscout: per query, the treatments it holds; a page is the newest `limit` in the interval (both ends
/// included, to the millisecond, as Nightscout compares normalized `created_at` strings).
private struct FakeNightscout: Sendable {
    var treatments: [NightscoutInsulinQuery: [NightscoutInsulinTreatment]] = [:]
    var documents: [NightscoutProfileDocument] = []
    var limit = 100
    /// a query's page fails when its end is before this date
    var failing: (query: NightscoutInsulinQuery, before: Date)?

    var source: InsulinBackfillSource {
        let fake = self
        return InsulinBackfillSource(
            treatments: { query, interval in
                if let failing = fake.failing, failing.query == query, failing.before > interval.end {
                    throw PageFailure()
                }
                return FakeNightscout.page(fake.treatments[query] ?? [], interval, fake.limit) { $0.createdAt }
            },
            treatmentsBefore: { query, date, count in
                Array(
                    (fake.treatments[query] ?? []).filter { ($0.createdAt ?? .distantFuture) < date }
                        .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                        .prefix(count)
                )
            },
            profiles: { interval in
                FakeNightscout.page(fake.documents, interval, fake.limit) { $0.startDate }
            },
            profileBefore: { date in
                fake.documents.filter { ($0.startDate ?? .distantFuture) < date }
                    .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            }
        )
    }

    static func page<Entry>(_ entries: [Entry], _ interval: DateInterval, _ limit: Int, _ date: (Entry) -> Date?) -> [Entry] {
        Array(
            entries
                .filter { entry in date(entry).map { interval.start <= $0 && $0 <= interval.end } ?? false }
                .sorted { (date($0) ?? .distantPast) > (date($1) ?? .distantPast) }
                .prefix(limit)
        )
    }
}

private struct PagedEntry: Sendable, Hashable {
    let id: Int
    let date: Date
}

final class InsulinBackfillTests: XCTestCase {
    // MARK: - Fixtures

    private static let berlin = StatsFixtures.berlin

    /// 2026-10-20 12:00 Europe/Berlin (CEST) = 10:00Z
    private static let t0 = StatsFixtures.day0.addingTimeInterval(.hours(12))

    private func at(_ minutes: Double) -> Date {
        Self.t0.addingTimeInterval(.minutes(minutes))
    }

    private func hours(_ hours: Double) -> Date {
        Self.t0.addingTimeInterval(.hours(hours))
    }

    private func days(_ days: Double) -> Date {
        Self.t0.addingTimeInterval(.days(days))
    }

    private func d(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func treatments(_ json: String) throws -> [NightscoutInsulinTreatment] {
        try decode([NightscoutInsulinTreatment].self, json)
    }

    private func schedule(_ entries: [(minutes: Int, rate: String)]) -> [BasalProfileEntry] {
        entries.map {
            BasalProfileEntry(
                start: String(format: "%02d:%02d:00", $0.minutes / 60, $0.minutes % 60),
                minutes: $0.minutes,
                rate: d($0.rate)
            )
        }
    }

    private func fingerprint(_ entries: [BasalProfileEntry]) -> String {
        BasalScheduleRecordValue.fingerprint(entries)
    }

    private final class Fixture {
        let container: NSPersistentContainer
        let database: CoreDataPumpEventDatabase
        let coordinator = AppCoordinator()
        let clock = BackfillClock(InsulinBackfillTests.t0)
        let signals = SignalRecorder()
        private(set) var store: PumpEventStore
        private var subscription: AnyCancellable?

        init(failFrom: Int = 0, failSessions: Bool = false) {
            container = StatsFixtures.inMemoryContainer()
            database = CoreDataPumpEventDatabase(container: container, mergeBatchDelete: { _ in })
            let clock = self.clock
            store = PumpEventStore(
                appCoordinator: coordinator,
                database: failFrom > 0 || failSessions
                    ? FailingDatabase(database, failFrom: failFrom, failSessions: failSessions) : database,
                calendar: { InsulinBackfillTests.berlin },
                now: { clock.now }
            )
            let signals = self.signals
            subscription = coordinator.insulinDataChanged.sink { signals.append($0) }
        }

        func reconcile(_ history: [PumpHistoryEvent]) async {
            coordinator.setPumpHistory(history.sorted { $0.timestamp > $1.timestamp })
            await store.requestReconcile()
            await store.idle()
        }

        func rows() async throws -> [PumpEventRecord] {
            try await container.performBackgroundTask { context in
                let fetch = NSFetchRequest<PumpEvent>(entityName: PumpEventStore.Entity.events)
                return try context.fetch(fetch)
                    .compactMap { CoreDataPumpEventDatabase.record(of: $0) }
                    .sorted { ($0.date, $0.kind.rawValue, $0.source.rawValue) < ($1.date, $1.kind.rawValue, $1.source.rawValue) }
            }
        }

        func events(_ source: PumpEventSource) async throws -> [PumpEventRecord] {
            try await rows().filter { $0.source == source }
        }

        func insert(_ sessions: [PumpSessionValue]) async throws {
            try await container.performBackgroundTask { context in
                for session in sessions {
                    CoreDataPumpEventDatabase.apply(session, to: PumpSession(context: context))
                }
                try context.save()
            }
        }

        func insert(_ records: [PumpEventRecord]) async throws {
            try await container.performBackgroundTask { context in
                for record in records {
                    CoreDataPumpEventDatabase.apply(record, to: PumpEvent(context: context))
                }
                try context.save()
            }
        }

        /// (date, source, fingerprint), oldest first
        func schedules() async throws -> [(date: Date, source: Int16, fingerprint: String)] {
            try await container.performBackgroundTask { context in
                let fetch = NSFetchRequest<BasalScheduleRecord>(entityName: PumpEventStore.Entity.schedules)
                fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
                return try context.fetch(fetch).map { row in
                    (row.date ?? .distantPast, row.source, row.fingerprint ?? "")
                }
            }
        }
    }

    private func nightscoutBolus(_ date: Date, _ units: Double) -> PumpEventRecord {
        PumpEventRecord(date: date, kind: .bolus, source: .nightscout, units: units)
    }

    private func nightscoutTemp(_ date: Date, rate: Double, minutes: Double = 30) -> PumpEventRecord {
        PumpEventRecord(date: date, kind: .tempBasal, source: .nightscout, units: -1, rate: rate, durationMin: minutes)
    }

    // MARK: - Mapping, per uploader

    func testIAPSUploads() throws {
        // NightscoutConversions: SMB / Bolus / External Insulin with the event nested; a temp with raw_rate/raw_duration
        let records = try NightscoutInsulinTreatment.records(from: treatments("""
        [
          {"_id": "i1", "eventType": "SMB", "created_at": "2026-10-20T09:00:00.000Z", "insulin": 0.3, "enteredBy": "iAPS",
           "bolus": {"_type": "Bolus", "amount": 0.3, "isSMB": true, "timestamp": "2026-10-20T09:00:00.000Z"}},
          {"_id": "i2", "eventType": "Bolus", "created_at": "2026-10-20T08:00:00.000Z", "insulin": 4, "enteredBy": "iAPS",
           "bolus": {"_type": "Bolus", "amount": 4, "isSMB": false}},
          {"_id": "i3", "eventType": "Bolus", "created_at": "2026-10-20T07:30:00.000Z", "insulin": 0.2, "enteredBy": "iAPS",
           "bolus": {"_type": "Bolus", "amount": 0.2, "isSMB": true}},
          {"_id": "i4", "eventType": "External Insulin", "created_at": "2026-10-20T07:00:00.000Z", "insulin": 2, "enteredBy": "iAPS"},
          {"_id": "i5", "eventType": "Temp Basal", "created_at": "2026-10-20T06:00:00.000Z", "duration": 12.4, "absolute": 0.8,
           "rate": 0.8, "enteredBy": "iAPS",
           "raw_rate": {"_type": "TempBasal", "rate": 0.8, "temp": "absolute", "deliveredUnits": 0.16},
           "raw_duration": {"_type": "TempBasalDuration", "duration (min)": 12.4}},
          {"_id": "i6", "eventType": "Site Change", "created_at": "2026-10-20T05:00:00.000Z", "enteredBy": "iAPS"}
        ]
        """))
        XCTAssertEqual(records, [
            nightscoutBolus(hours(-1), 0.3).with { $0.isSMB = true },
            nightscoutBolus(hours(-2), 4),
            nightscoutBolus(hours(-2.5), 0.2).with { $0.isSMB = true },
            nightscoutBolus(hours(-3), 2).with { $0.isExternal = true },
            PumpEventRecord(
                date: hours(-4),
                kind: .tempBasal,
                source: .nightscout,
                units: 0.16,
                rate: 0.8,
                durationMin: 12.4
            )
        ])
    }

    func testTrioUploads() throws {
        let records = try NightscoutInsulinTreatment.records(from: treatments("""
        [
          {"_id": "t1", "eventType": "SMB", "created_at": "2026-10-20T09:00:00.123Z", "insulin": 0.4, "enteredBy": "Trio", "id": "u1"},
          {"_id": "t2", "eventType": "Bolus", "created_at": "2026-10-20T08:00:00.000Z", "insulin": 3, "enteredBy": "Trio"},
          {"_id": "t3", "eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00.000Z", "duration": 30, "absolute": 1.2,
           "rate": 1.2, "enteredBy": "Trio"},
          {"_id": "t4", "eventType": "Note", "created_at": "2026-10-20T06:00:00.000Z", "notes": "PumpSuspend", "enteredBy": "Trio"},
          {"_id": "t5", "eventType": "Note", "created_at": "2026-10-20T06:30:00.000Z", "notes": "PumpResume", "enteredBy": "Trio"},
          {"_id": "t6", "eventType": "Note", "created_at": "2026-10-20T05:00:00.000Z", "notes": "Pod alarm", "enteredBy": "Trio"}
        ]
        """))
        XCTAssertEqual(records.map(\.kind), [.bolus, .bolus, .tempBasal, .resume, .suspend])
        XCTAssertEqual(records[0].date, hours(-1)) // truncated to the second
        XCTAssertTrue(records[0].isSMB)
        XCTAssertFalse(records[1].isSMB)
        XCTAssertEqual(records[2].rate, 1.2, accuracy: 1E-9)
        XCTAssertEqual(records[2].units, -1)
        XCTAssertEqual(records[3].date, at(-210))
        XCTAssertEqual(records[4].date, hours(-4))
    }

    func testOlderTrioCancelNextToANewTempKeepsTheOneWithADuration() throws {
        // older Trio/iAPS: a zero-length "Temp Basal" cancel in the same second as the next temp, in either order
        for order in [["c", "n"], ["n", "c"]] {
            let documents = [
                "c": """
                {"_id": "c", "eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00.000Z", "duration": 0, "absolute": 0, "rate": 0}
                """,
                "n": """
                {"_id": "n", "eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00.000Z", "duration": 30, "absolute": 0.9, "rate": 0.9}
                """
            ]
            let records = try NightscoutInsulinTreatment.records(from: treatments(
                "[" + order.map { documents[$0]! }
                    .joined(separator: ",") + "]"
            ))
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records.first?.durationMin, 30)
            XCTAssertEqual(records.first?.rate, 0.9)
        }
        // a lone zero-length temp is kept: zero-length
        let lone = try NightscoutInsulinTreatment.records(from: treatments("""
        [{"_id": "z", "eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00.000Z", "duration": 0, "absolute": 0}]
        """))
        XCTAssertEqual(lone.map(\.durationMin), [0])
    }

    func testLoopUploads() throws {
        // NightscoutServiceKit: every bolus a "Correction Bolus" (automatic marks the SMB-like ones), dates without
        // milliseconds, durations in minutes as Doubles, a suspend as a rate-0 temp
        let records = try NightscoutInsulinTreatment.records(from: treatments("""
        [
          {"eventType": "Correction Bolus", "created_at": "2026-10-20T09:00:00Z", "timestamp": "2026-10-20T09:00:00Z",
           "type": "normal", "insulin": 0.35, "programmed": 0.35, "duration": 0.2, "automatic": true,
           "enteredBy": "loop://iPhone", "syncIdentifier": "s1"},
          {"eventType": "Correction Bolus", "created_at": "2026-10-20T08:00:00Z", "type": "normal", "insulin": 5,
           "programmed": 5, "duration": 2.5, "automatic": false, "enteredBy": "loop://iPhone"},
          {"eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00Z", "temp": "absolute", "rate": 0, "absolute": 0,
           "duration": 42.5, "amount": 0, "reason": "suspend", "automatic": true, "enteredBy": "loop://iPhone"},
          {"eventType": "Temp Basal", "created_at": "2026-10-20T06:00:00Z", "temp": "absolute", "rate": 1.15, "absolute": 1.15,
           "duration": 30, "amount": 0.4, "automatic": true, "enteredBy": "loop://iPhone"}
        ]
        """))
        XCTAssertEqual(records.map(\.kind), [.bolus, .bolus, .tempBasal, .tempBasal])
        XCTAssertEqual(records.map(\.isSMB), [true, false, false, false])
        XCTAssertEqual(records[0].units, 0.35, accuracy: 1E-9)
        XCTAssertEqual(records[2].rate, 0)
        XCTAssertEqual(records[2].durationMin, 42.5, accuracy: 1E-9)
        XCTAssertEqual(records[3].rate, 1.15, accuracy: 1E-9)
        XCTAssertEqual(records[3].units, -1) // Loop's `amount` isn't read
        XCTAssertEqual(records.map(\.date), [hours(-1), hours(-2), hours(-3), hours(-4)])
        // without `_id` (never from Nightscout) the documents still count once each
        XCTAssertEqual(Set(try treatments("""
        [{"eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00Z", "rate": 0, "duration": 0},
         {"eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00Z", "rate": 0.5, "duration": 30}]
        """).map(\.pagingKey)).count, 2)
    }

    func testAAPSUploads() throws {
        // API v3 documents: `date` in ms (the server adds `created_at`), `type`, `isValid`, `durationInMilliseconds`
        let records = try NightscoutInsulinTreatment.records(from: treatments("""
        [
          {"identifier": "a1", "app": "AAPS", "date": 1792486800000, "created_at": "2026-10-20T09:00:00.000Z",
           "eventType": "Correction Bolus", "insulin": 0.25, "type": "SMB", "isValid": true, "utcOffset": 120},
          {"identifier": "a2", "app": "AAPS", "date": 1792483200000, "eventType": "Meal Bolus", "insulin": 6, "type": "NORMAL",
           "isValid": true},
          {"identifier": "a3", "app": "AAPS", "date": 1792481400000, "eventType": "Meal Bolus", "insulin": 1, "type": "PRIMING",
           "isValid": true},
          {"identifier": "a4", "app": "AAPS", "date": 1792480500000, "eventType": "Meal Bolus", "insulin": 2, "type": "NORMAL",
           "isValid": false},
          {"identifier": "a5", "app": "AAPS", "date": 1792479600000, "eventType": "Temp Basal", "rate": 0.64, "percent": -20,
           "duration": 29, "durationInMilliseconds": 1800000, "type": "NORMAL", "isValid": true},
          {"identifier": "a6", "app": "AAPS", "date": 1792478700000, "eventType": "Temp Basal", "percent": -20, "duration": 30,
           "isValid": true},
          {"identifier": "a7", "app": "AAPS", "date": 1792476000000, "eventType": "Combo Bolus", "enteredinsulin": 1.5,
           "splitNow": 0, "splitExt": 100, "relative": 1.5, "duration": 60, "isEmulatingTempBasal": false, "isValid": true},
          {"identifier": "a8", "app": "AAPS", "date": 1792472400000, "eventType": "Combo Bolus", "enteredinsulin": 1,
           "duration": 60, "isEmulatingTempBasal": true, "isValid": true},
          {"identifier": "a9", "app": "AAPS", "date": 1792468800000, "eventType": "Temp Basal", "rate": 0, "absolute": 0,
           "durationInMilliseconds": 900000, "type": "PUMP_SUSPEND", "isValid": true},
          {"identifier": "a10", "app": "AAPS", "date": 1792465200000, "eventType": "Correction Bolus", "insulin": "0.5",
           "type": "SMB", "isValid": "true"}
        ]
        """))
        // a1, a2, a5, a7, a9, a10
        XCTAssertEqual(records.map(\.kind), [.bolus, .bolus, .tempBasal, .bolus, .tempBasal, .bolus])
        XCTAssertEqual(records.map(\.date), [hours(-1), hours(-2), hours(-3), hours(-4), hours(-6), hours(-7)])
        XCTAssertEqual(records.map(\.isSMB), [true, false, false, false, false, true])
        // a percent temp with its U/h rate, the exact duration
        XCTAssertEqual(records[2].rate, 0.64, accuracy: 1E-9)
        XCTAssertEqual(records[2].durationMin, 30, accuracy: 1E-9)
        // an extended bolus not emulated: its insulin at its start
        XCTAssertEqual(records[3].kind, .bolus)
        XCTAssertEqual(records[3].units, 1.5, accuracy: 1E-9)
        // a pump suspend: a zero temp
        XCTAssertEqual(records[4].rate, 0)
        XCTAssertEqual(records[4].durationMin, 15, accuracy: 1E-9)
        XCTAssertEqual(records[5].units, 0.5, accuracy: 1E-9)
    }

    func testDatesOfEveryShape() {
        XCTAssertEqual(NightscoutDate.parse("2026-10-20T10:00:00Z"), Self.t0)
        XCTAssertEqual(NightscoutDate.parse("2026-10-20T10:00:00.000Z"), Self.t0)
        XCTAssertEqual(NightscoutDate.parse("2026-10-20T12:00:00+02:00"), Self.t0)
        // AAPS: seven fractional digits
        XCTAssertEqual(
            NightscoutDate.parse("2026-10-20T10:00:00.1230000Z")?.timeIntervalSince1970 ?? 0,
            Self.t0.timeIntervalSince1970 + 0.123,
            accuracy: 1E-3
        )
        XCTAssertEqual(NightscoutDate.parse("1792490400000"), Self.t0)
        XCTAssertNil(NightscoutDate.parse("yesterday"))
    }

    // MARK: - Pager

    func testTreatmentPagerKeepsEveryEntryOfASharedBoundarySecond() async {
        let since = days(-2)
        // one a minute, with four entries in one second (milliseconds apart) right where the first page ends
        var entries = (0 ..< 250).map { PagedEntry(id: $0, date: at(-Double($0))) }
        let boundary = at(-99).addingTimeInterval(0.2)
        entries += (0 ..< 4).map { PagedEntry(id: 1000 + $0, date: boundary.addingTimeInterval(-0.05 * Double($0))) }
        let all = entries
        let result = await BaseNightscoutManager.fetchTreatmentPages(
            since: since,
            until: at(10),
            date: { $0.date },
            key: { $0.id },
            page: { FakeNightscout.page(all, $0, 100) { $0.date } },
            reached: { _ in }
        )
        XCTAssertNil(result.error)
        XCTAssertEqual(result.entries.count, all.count)
        XCTAssertEqual(Set(result.entries), Set(all))
        XCTAssertEqual(result.complete(since: since, until: at(10)), since)
    }

    func testTreatmentPagerWithWholeSecondDates() async {
        // several entries in each second: the end is the second after the oldest entry, so the whole boundary
        // second comes again (Nightscout normalizes to milliseconds; this also covers a document it didn't)
        let since = days(-1)
        let entries = (0 ..< 30).map { PagedEntry(id: $0, date: at(-Double($0 / 3))) } // three per minute, one second
        let result = await BaseNightscoutManager.fetchTreatmentPages(
            since: since,
            until: at(10),
            date: { $0.date },
            key: { $0.id },
            page: { FakeNightscout.page(entries, $0, 10) { $0.date } },
            reached: { _ in }
        )
        XCTAssertEqual(Set(result.entries), Set(entries))
    }

    func testTreatmentPagerStopsAtAFailedPage() async {
        let since = days(-2)
        let entries = (0 ..< 250).map { PagedEntry(id: $0, date: at(-Double($0) - 0.5)) }
        let failBefore = at(-90)
        let result = await BaseNightscoutManager.fetchTreatmentPages(
            since: since,
            until: at(10),
            date: { $0.date },
            key: { $0.id },
            page: { interval in
                if failBefore > interval.end { throw PageFailure() }
                return FakeNightscout.page(entries, interval, 100) { $0.date }
            },
            reached: { _ in }
        )
        XCTAssertTrue(result.error is PageFailure)
        XCTAssertEqual(result.entries.count, 100)
        XCTAssertEqual(result.oldest, entries[99].date)
        // complete from the second after the oldest fetched
        XCTAssertEqual(result.complete(since: since, until: at(10)), entries[99].date.truncatedToSecond.addingTimeInterval(1))

        // nothing fetched: complete nowhere
        let none = await BaseNightscoutManager.fetchTreatmentPages(
            since: since, until: at(10), date: { $0.date }, key: { $0.id },
            page: { _ -> [PagedEntry] in throw PageFailure() }, reached: { _ in }
        )
        XCTAssertEqual(none.complete(since: since, until: at(10)), at(10))
    }

    func testTreatmentPagerReportsAServerIgnoringTheEnd() async {
        let same = [PagedEntry(id: 1, date: at(-10)), PagedEntry(id: 2, date: at(-20))]
        let stuck = await BaseNightscoutManager.fetchTreatmentPages(
            since: days(-1), until: at(10), date: { $0.date }, key: { $0.id }, page: { _ in same }, reached: { _ in }
        )
        XCTAssertEqual(stuck.entries, same)
        XCTAssertEqual(stuck.error as? FetchPagesError, .notPagingBack)
    }

    private func temp(_ date: Date, id: String, rate: Double = 1) -> NightscoutInsulinTreatment {
        var treatment = NightscoutInsulinTreatment(id: id, eventType: "Temp Basal", createdAt: date, duration: 30, absolute: rate)
        treatment.rate = rate
        return treatment
    }

    private func bolusTreatment(_ date: Date, id: String, insulin: Double = 1) -> NightscoutInsulinTreatment {
        NightscoutInsulinTreatment(id: id, eventType: "Bolus", createdAt: date, insulin: insulin)
    }

    func testEachQueryPagesOnItsOwn() async {
        // temps every 5 minutes fill page after page; the boluses, every 6 hours, fit in one. One pager over both
        // would end its second page at the 100th temp and skip the boluses between it and the oldest bolus.
        let since = days(-3)
        var fake = FakeNightscout()
        fake.treatments[.tempBasals] = (0 ..< 800).map { temp(at(-5 * Double($0)), id: "t\($0)") }
        fake.treatments[.boluses] = (0 ..< 12).map { bolusTreatment(hours(-6 * Double($0) - 1), id: "b\($0)") }
        let fetched = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { _ in }
        XCTAssertNil(fetched.failure)
        XCTAssertNil(fetched.schedulesFailure)
        XCTAssertEqual(fetched.complete, DateInterval(start: since, end: at(10)))
        XCTAssertEqual(fetched.treatments.filter { $0.eventType == "Bolus" }.count, 12)
        XCTAssertEqual(fetched.treatments.filter { $0.eventType == "Temp Basal" }.count, 800)
    }

    /// The pump sessions' Site Changes and Announcements come along, each query paged on its own; a failed page of
    /// one shortens only the sessions' complete time, never the insulin records'.
    func testTheSessionQueriesComeAlongAndTheirFailureShortensOnlyTheSessions() async {
        let since = days(-3)
        var fake = FakeNightscout()
        fake.treatments[.tempBasals] = (0 ..< 300).map { temp(at(-10 * Double($0)), id: "t\($0)") }
        fake.treatments[.siteChanges] = (0 ..< 150).map {
            NightscoutInsulinTreatment(id: "s\($0)", eventType: "Site Change", createdAt: at(-20 * Double($0) - 3))
        }
        fake.treatments[.announcements] = [NightscoutInsulinTreatment(id: "a0", eventType: "Announcement", createdAt: at(-61))]
        let fetched = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { _ in }
        XCTAssertNil(fetched.failure)
        XCTAssertNil(fetched.sessionsFailure)
        XCTAssertEqual(fetched.sessionsComplete, DateInterval(start: since, end: at(10)))
        XCTAssertEqual(fetched.sessionTreatments.count, 151)
        XCTAssertEqual(fetched.treatments.count, 300)

        // the Site Changes' second page fails: they reach back to their 100th
        fake.failing = (.siteChanges, at(-1000))
        let failed = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { _ in }
        let complete = at(-20 * 99 - 3).truncatedToSecond.addingTimeInterval(1)
        XCTAssertNil(failed.failure)
        XCTAssertNotNil(failed.sessionsFailure)
        XCTAssertEqual(failed.complete, DateInterval(start: since, end: at(10)))
        XCTAssertEqual(failed.treatments.count, 300)
        XCTAssertEqual(failed.sessionsComplete, DateInterval(start: complete, end: at(10)))
        XCTAssertEqual(failed.sessionTreatments.count, 100)
        XCTAssertTrue(failed.sessionTreatments.allSatisfy { ($0.createdAt ?? .distantPast) >= complete })
    }

    /// A session query failing on its first page: nothing of the sessions is complete, so no input (nothing written,
    /// nothing deleted). An insulin query failing with the session queries complete: the sessions' time is the
    /// insulin's (their evidence), from the newest point it stopped at.
    func testSessionQueriesFailingOrTheInsulinFailing() async {
        let since = days(-3)
        var fake = FakeNightscout()
        fake.treatments[.tempBasals] = (0 ..< 300).map { temp(at(-10 * Double($0)), id: "t\($0)") }
        fake.treatments[.boluses] = (0 ..< 300).map { bolusTreatment(at(-10 * Double($0) - 1), id: "b\($0)") }
        fake.treatments[.siteChanges] = (0 ..< 20).map {
            NightscoutInsulinTreatment(id: "s\($0)", eventType: "Site Change", createdAt: at(-150 * Double($0) - 3))
        }
        fake.failing = (.siteChanges, at(100))
        let first = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { _ in }
        XCTAssertNil(first.failure)
        XCTAssertNotNil(first.sessionsFailure)
        XCTAssertEqual(first.sessionsComplete, DateInterval(start: at(10), end: at(10)))
        XCTAssertEqual(first.sessionTreatments, [])
        XCTAssertNil(NightscoutInsulinBackfill(fetched: first).sessions)

        fake.failing = (.boluses, at(-900))
        let insulin = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { _ in }
        let complete = at(-10 * 99 - 1).truncatedToSecond.addingTimeInterval(1)
        XCTAssertNil(insulin.sessionsFailure)
        XCTAssertEqual(insulin.complete?.start, complete)
        XCTAssertEqual(insulin.sessionsComplete?.start, complete)
        XCTAssertEqual(
            insulin.sessionTreatments.count,
            fake.treatments[.siteChanges]!.filter { $0.createdAt! >= complete }.count
        )
        let input = NightscoutInsulinBackfill(fetched: insulin).sessions
        XCTAssertNotNil(input)
        XCTAssertGreaterThanOrEqual(input?.from ?? .distantPast, complete)
    }

    /// The sessions' write failing: logged, nil; the records stored before it stand.
    func testANightscoutSessionsFailureKeepsTheRecords() async throws {
        let f = Fixture(failSessions: true)
        let records = NightscoutInsulinTreatment
            .records(from: (0 ..< 10).map { temp(days(-2).addingTimeInterval(.minutes(30 * Double($0))), id: "t\($0)") })
        let outcome = await f.store.storeBackfill(records)
        XCTAssertEqual(outcome.inserted, 10)
        let sessions = await f.store.storeNightscoutSessions(NightscoutSessionsInput(
            siteChanges: [days(-2)],
            alarms: [],
            evidence: [DateInterval(start: days(-2), end: days(-2).addingTimeInterval(.hours(5)))],
            from: days(-2)
        ))
        XCTAssertNil(sessions)
        let stored = try await f.events(.nightscout)
        XCTAssertEqual(stored.count, 10)
    }

    func testAFailedQueryStopsEveryQueryAtTheNewestPointOneStoppedAt() async {
        let since = days(-3)
        var fake = FakeNightscout()
        fake.treatments[.tempBasals] = (0 ..< 800).map { temp(at(-5 * Double($0)), id: "t\($0)") }
        fake.treatments[.boluses] = (0 ..< 300).map { bolusTreatment(at(-10 * Double($0) - 1), id: "b\($0)") }
        // the boluses' second page fails: they reach back to their 100th
        fake.failing = (.boluses, at(-900))
        let fetched = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { _ in }
        let complete = at(-10 * 99 - 1).truncatedToSecond.addingTimeInterval(1)
        guard case let .pageFailed(reached, _) = fetched.failure else {
            return XCTFail("a page failure")
        }
        XCTAssertEqual(reached, complete)
        XCTAssertEqual(fetched.complete?.start, complete)
        // the temps that went further are cut there too
        XCTAssertTrue(fetched.treatments.allSatisfy { ($0.createdAt ?? .distantPast) >= complete })
        XCTAssertEqual(fetched.treatments.filter { $0.eventType == "Bolus" }.count, 99)
        XCTAssertEqual(
            fetched.treatments.filter { $0.eventType == "Temp Basal" }.count,
            fake.treatments[.tempBasals]!.filter { $0.createdAt! >= complete }.count
        )
    }

    // MARK: - Nightscout coverage

    func testNightscoutCoverageFromTheFetchedTemps() {
        // every 30 min 00:00-05:00, a 3 h gap, 08:00-09:00, a lone temp at 14:00
        let day = hours(-10)
        let starts = stride(from: 0.0, through: 5, by: 0.5).map { day.addingTimeInterval(.hours($0)) } +
            [8, 8.5, 9].map { day.addingTimeInterval(.hours($0)) } + [day.addingTimeInterval(.hours(14))]
        XCTAssertEqual(PumpEventStore.nightscoutCoverage(tempStarts: starts.shuffled()), [
            DateInterval(start: day, end: day.addingTimeInterval(.hours(5))),
            DateInterval(start: day.addingTimeInterval(.hours(8)), end: day.addingTimeInterval(.hours(9)))
        ])
        // a gap just under 3 h doesn't split
        XCTAssertEqual(
            PumpEventStore.nightscoutCoverage(tempStarts: [day, day.addingTimeInterval(.hours(2.9))]),
            [DateInterval(start: day, end: day.addingTimeInterval(.hours(2.9)))]
        )
        XCTAssertEqual(PumpEventStore.nightscoutCoverage(tempStarts: []), [])
    }

    func testIntervalRules() {
        let a = DateInterval(start: hours(-10), end: hours(-5))
        XCTAssertEqual(PumpEventStore.subtract([a], [DateInterval(start: hours(-8), end: hours(-7))]), [
            DateInterval(start: hours(-10), end: hours(-8)),
            DateInterval(start: hours(-7), end: hours(-5))
        ])
        XCTAssertEqual(PumpEventStore.subtract([a], [DateInterval(start: hours(-6), duration: 0)]), [a])
        XCTAssertEqual(PumpEventStore.intersect([a], with: DateInterval(start: hours(-6), end: hours(0))), [
            DateInterval(start: hours(-6), end: hours(-5))
        ])
        XCTAssertEqual(
            PumpEventStore.merge([DateInterval(start: hours(-5), end: hours(-3)), a]),
            [DateInterval(start: hours(-10), end: hours(-3))]
        )
    }

    func testBackfillBatchesNewestFirst() {
        let records = (0 ..< 7).map { nightscoutBolus(hours(-Double($0) - 1), 1) }
        let batches = PumpEventStore.backfillBatches(records.shuffled(), size: 3)
        XCTAssertEqual(
            batches.map { $0.map(\.date) },
            [[hours(-1), hours(-2), hours(-3)], [hours(-4), hours(-5), hours(-6)], [hours(-7)]]
        )
        XCTAssertEqual(PumpEventStore.backfillBatches([], size: 3).count, 0)
    }

    // MARK: - Store

    /// A pump session, local from `localStart` (its start without one) on.
    private func localSession(
        from start: Date,
        localStart: Date? = nil,
        lastSeen: Date,
        gaps: [DateInterval] = []
    ) -> PumpSessionValue {
        PumpSessionValue(
            id: UUID(),
            source: .pump,
            plugin: "Medtrum",
            activation: start,
            start: start,
            localStart: localStart ?? start,
            lastSeen: lastSeen,
            gaps: gaps
        )
    }

    func testBackfillLeavesOutWhatThePumpKnowsAndARerunDoublesNothing() async throws {
        let f = Fixture()
        // the file: its oldest event an hour ago (so the last 24 h are the pump's); pump sessions 6 to 5.5 and 3 to 2
        // days ago; a pump row between them
        f.coordinator.setPumpHistory([PumpHistoryEvent(id: "p", type: .bolus, timestamp: at(-60), amount: 1)])
        try await f.insert([
            localSession(from: days(-6), lastSeen: days(-5.5)),
            localSession(from: days(-3), lastSeen: days(-2))
        ])
        try await f.insert([PumpEventRecord(date: days(-4), kind: .bolus, source: .pump, units: 2)])
        let records = [
            // in the last 24 h
            nightscoutBolus(hours(-10), 1),
            // inside the second session's local time, and at its start
            nightscoutTemp(days(-2.5), rate: 1),
            nightscoutBolus(days(-3), 1),
            // kept: between the sessions, before them
            nightscoutBolus(days(-4.5), 3),
            nightscoutTemp(days(-7), rate: 0.7),
            // the pump row's identity
            nightscoutBolus(days(-4), 2),
            // inside the first session
            nightscoutBolus(days(-5.75), 1)
        ]

        let outcome = await f.store.storeBackfill(records)
        // the last 24 h counted on their own: any uploader's records there are the file's
        XCTAssertEqual(outcome, PumpEventStore.BackfillOutcome(inserted: 2, updated: 0, skipped: 4, recent: 1))
        var events = try await f.events(.nightscout)
        XCTAssertEqual(events.map(\.date), [days(-7), days(-4.5)])
        XCTAssertEqual(f.signals.all.count, 1)

        // a re-run: nothing new, the same rows
        f.signals.clear()
        let again = await f.store.storeBackfill(records)
        XCTAssertEqual(again, PumpEventStore.BackfillOutcome(inserted: 0, updated: 0, skipped: 4, recent: 1))
        events = try await f.events(.nightscout)
        XCTAssertEqual(events.map(\.date), [days(-7), days(-4.5)])
        XCTAssertEqual(f.signals.all, [])

        // a changed value is an update
        var changed = records
        changed[3].units = 3.5
        let update = await f.store.storeBackfill(changed)
        XCTAssertEqual(update.updated, 1)
        events = try await f.events(.nightscout)
        XCTAssertEqual(events.map(\.units), [-1, 3.5])
    }

    func testAnInterruptedBackfillKeepsItsStoredBatches() async throws {
        let f = Fixture(failFrom: 2)
        f.coordinator.setPumpHistory([PumpHistoryEvent(id: "p", type: .bolus, timestamp: at(-60), amount: 1)])
        // a temp every 2 hours from 4 days ago to 2 days ago
        let records = (0 ..< 25)
            .map { nightscoutTemp(days(-2).addingTimeInterval(-.hours(2 * Double($0))), rate: 1) }

        let outcome = await f.store.storeBackfill(records, batchSize: 10)
        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.inserted, 10)
        // the newest record of the failed batch: the ones newer than it are stored
        XCTAssertEqual(outcome.reached, records[10].date)
        let events = try await f.events(.nightscout)
        XCTAssertEqual(events.map(\.date), records[0 ..< 10].map(\.date).reversed())
    }

    func testAReconcileRemovesTheNightscoutRowsInsideWhatThePumpNowKnows() async throws {
        let f = Fixture()
        // a backfill that ran before the first reconcile (a wipe, a fresh install): Nightscout rows reaching into the
        // file's time (inside the list's span, at a pump identity), and one older than the file's 24 h and the pump's
        // dose rows
        try await f.insert([
            nightscoutBolus(at(-120), 1),
            nightscoutTemp(at(-1500), rate: 1),
            nightscoutBolus(at(-30), 2)
        ])
        await f.reconcile([
            PumpHistoryEvent(id: "a", type: .bolus, timestamp: at(-200), amount: 1),
            PumpHistoryEvent(id: "b", type: .bolus, timestamp: at(-30), amount: 2)
        ])
        let nightscout = try await f.events(.nightscout)
        XCTAssertEqual(nightscout.map(\.date), [at(-1500)])
        let pump = try await f.events(.pump)
        XCTAssertEqual(pump.map(\.date), [at(-200), at(-30)])
        // the change covers them
        guard case let .interval(changed) = f.signals.all.last else {
            return XCTFail("a change")
        }
        XCTAssertLessThanOrEqual(changed.start, at(-200))
        XCTAssertGreaterThanOrEqual(changed.end, at(-30))
    }

    func testAReconcileWithoutAListLeavesTheNightscoutRows() async throws {
        let f = Fixture()
        try await f.insert([nightscoutBolus(at(-120), 1)])
        await f.reconcile([])
        let nightscout = try await f.events(.nightscout)
        XCTAssertEqual(nightscout.map(\.date), [at(-120)])
    }

    func testScheduleBackfillGoesOnlyBeforeTheOldestLocalRecord() async throws {
        let f = Fixture()
        let a = schedule([(0, "0.5"), (360, "1.0")])
        let b = schedule([(0, "0.6")])
        let c = schedule([(0, "0.7")])
        await f.store.basalProfileChanged(a)
        f.signals.clear()

        let imported = await f.store.storeScheduleBackfill([
            NightscoutBasalSchedule(date: days(-30), entries: a, uploader: "iAPS", timeZone: "Europe/Berlin"),
            NightscoutBasalSchedule(date: days(-20), entries: b, uploader: "iAPS", timeZone: nil),
            // equal to the record in effect before it
            NightscoutBasalSchedule(date: days(-15), entries: b, uploader: "iAPS", timeZone: nil),
            NightscoutBasalSchedule(date: days(-5), entries: a, uploader: "iAPS", timeZone: nil),
            // the local history wins from its start on
            NightscoutBasalSchedule(date: hours(1), entries: c, uploader: "iAPS", timeZone: nil)
        ])
        XCTAssertEqual(try imported.get(), 3)
        var rows = try await f.schedules()
        XCTAssertEqual(rows.map(\.date), [days(-30), days(-20), days(-5), Self.t0])
        XCTAssertEqual(rows.map(\.source), [1, 1, 1, 0])
        XCTAssertEqual(rows.map(\.fingerprint), [fingerprint(a), fingerprint(b), fingerprint(a), fingerprint(a)])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: days(-30), end: Self.t0))])

        // a re-run imports nothing new
        f.signals.clear()
        let again = await f.store.storeScheduleBackfill([
            NightscoutBasalSchedule(date: days(-30), entries: a, uploader: "iAPS", timeZone: nil),
            NightscoutBasalSchedule(date: days(-20), entries: b, uploader: "iAPS", timeZone: nil)
        ])
        XCTAssertEqual(try again.get(), 0)
        rows = try await f.schedules()
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(f.signals.all, [])
    }

    // MARK: - Profiles

    func testProfileDocumentsToSchedules() throws {
        let documents = try decode([NightscoutProfileDocument].self, """
        [
          {"_id": "p1", "defaultProfile": "default", "startDate": "2026-10-10T10:00:00.000Z", "mills": 1791626400000,
           "enteredBy": "iAPS", "units": "mmol",
           "store": {"default": {"dia": 6, "timezone": "Europe/Berlin", "units": "mmol",
             "basal": [{"time": "00:00", "value": 0.5, "timeAsSeconds": 0}, {"time": "06:00", "value": 1.05, "timeAsSeconds": 21600}],
             "sens": [{"time": "00:00", "value": 5, "timeAsSeconds": 0}]}}},
          {"_id": "p2", "enteredBy": "iAPS", "created_at": "2026-10-11T10:00:00.000Z", "max_iob": 5, "enableSMB_always": true},
          {"_id": "p3", "defaultProfile": "default", "startDate": "2026-10-12T10:00:00.000Z", "enteredBy": "iAPS",
           "store": {"default": {"basal": [{"time": "00:00", "value": 0.5, "timeAsSeconds": 0},
                                           {"time": "06:00", "value": 1.05, "timeAsSeconds": 21600}]}}},
          {"_id": "p4", "defaultProfile": "Default", "startDate": "2026-10-14T10:00:00Z", "mills": "1791972000000",
           "enteredBy": "Loop", "store": {"Default": {"dia": 6, "carbs_hr": "0", "delay": "0", "timezone": "ETC/GMT-2",
             "basal": [{"time": "00:00", "value": 0.8}, {"time": "07:30", "value": "1.2"}]}}},
          {"_id": "p5", "defaultProfile": "default", "startDate": "2026-10-15T10:00:00.000Z", "enteredBy": "Trio",
           "store": {"default": {"basal": [{"time": "01:00", "value": 0.5, "timeAsSeconds": 3600}]}}},
          {"_id": "p6", "defaultProfile": "default", "startDate": "2026-10-16T10:00:00.000Z", "enteredBy": "Trio",
           "store": {"default": {"basal": [{"time": "00:00", "value": 0.5}, {"time": "06:00", "value": 0.7},
                                           {"time": "05:00", "value": 0.6}]}}},
          {"_id": "p7", "defaultProfile": "default", "startDate": "2026-10-17T10:00:00.000Z", "enteredBy": "Trio",
           "store": {"default": {"basal": [{"time": "00:00", "value": 0.5}, {"time": "06:00", "value": -0.1}]}}},
          {"_id": "p8", "defaultProfile": "default", "startDate": "2026-10-18T10:00:00.000Z", "enteredBy": "Trio",
           "store": {"default": {"basal": [{"time": "00:00", "value": 0}]}}},
          {"_id": "p9", "defaultProfile": "Weekday", "startDate": "2026-10-19T10:00:00.1230000Z", "app": "AAPS",
           "store": {"Weekday": {"timezone": "Europe/Berlin",
             "basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 0.9}, {"time": "12:00", "timeAsSeconds": 43200, "value": 1.1}]}}}
        ]
        """)
        XCTAssertEqual(documents.count, 9)
        XCTAssertNil(documents[1].basalSchedule()) // iAPS Preferences
        XCTAssertEqual(documents[3].basalSchedule(), schedule([(0, "0.8"), (450, "1.2")])) // `time` only
        XCTAssertNil(documents[4].basalSchedule()) // not from 00:00
        XCTAssertNil(documents[5].basalSchedule()) // unordered
        XCTAssertNil(documents[6].basalSchedule()) // negative
        XCTAssertNil(documents[7].basalSchedule()) // all zero

        let schedules = NightscoutProfileDocument.basalSchedules(documents: documents.shuffled(), switches: [])
        // p3 repeats p1: one record, from the earliest
        XCTAssertEqual(schedules.map(\.date), [days(-10), days(-6), days(-1).addingTimeInterval(0.123)])
        XCTAssertEqual(schedules.map(\.uploader), ["iAPS", "Loop", "AAPS"])
        XCTAssertEqual(schedules[0].entries, schedule([(0, "0.5"), (360, "1.05")]))
        XCTAssertEqual(schedules[0].timeZone, "Europe/Berlin")
        XCTAssertEqual(schedules[2].entries, schedule([(0, "0.9"), (720, "1.1")]))
    }

    func testAAPSProfileSwitches() throws {
        let documents = try decode([NightscoutProfileDocument].self, """
        [
          {"identifier": "doc", "defaultProfile": "Base", "startDate": "2026-10-01T10:00:00.000Z", "app": "AAPS",
           "store": {"Base": {"basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1.0},
                                        {"time": "06:00", "timeAsSeconds": 21600, "value": 2.0}]}}},
          {"_id": "trio", "defaultProfile": "default", "startDate": "2026-10-02T10:00:00.000Z", "enteredBy": "Trio",
           "store": {"default": {"basal": [{"time": "00:00", "value": 0.4}]}}}
        ]
        """)
        let profileJson =
            #"{\"units\":\"mg/dl\",\"timezone\":\"Europe/Berlin\",\"basal\":[{\"time\":\"00:00\",\"timeAsSeconds\":0,\"value\":1.0},{\"time\":\"06:00\",\"timeAsSeconds\":21600,\"value\":2.0}]}"#
        let switches = try treatments("""
        [
          {"identifier": "s1", "app": "AAPS", "eventType": "Profile Switch", "created_at": "2026-10-10T10:00:00.000Z",
           "profile": "Base", "originalProfileName": "Base", "percentage": 100, "duration": 0, "isValid": true},
          {"identifier": "s2", "app": "AAPS", "eventType": "Profile Switch", "created_at": "2026-10-11T10:00:00.000Z",
           "profile": "Base (80%,2h)", "originalProfileName": "Base", "profileJson": "\(profileJson)",
           "percentage": 80, "timeshift": 7200000, "duration": 0, "isValid": true},
          {"identifier": "s3", "app": "AAPS", "eventType": "Profile Switch", "created_at": "2026-10-12T10:00:00.000Z",
           "profile": "Base (150%)", "originalProfileName": "Base", "percentage": 150, "duration": 60,
           "durationInMilliseconds": 3600000, "isValid": true},
          {"identifier": "s4", "app": "AAPS", "eventType": "Profile Switch", "created_at": "2026-10-13T10:00:00.000Z",
           "profile": "Base", "percentage": 50, "isValid": false}
        ]
        """)
        let schedules = NightscoutProfileDocument.basalSchedules(documents: documents, switches: switches)
        let base = schedule([(0, "1.0"), (360, "2.0")])
        // 80%, shifted +2 h: 08:00 runs the profile's 06:00 rate
        let shifted = schedule([(0, "1.6"), (120, "0.8"), (480, "1.6")])
        XCTAssertEqual(schedules.map(\.date), [days(-18), days(-10), days(-9), days(-8), days(-8).addingTimeInterval(.hours(1))])
        XCTAssertEqual(schedules.map(\.entries), [
            schedule([(0, "0.4")]), // Trio's own document; the AAPS document isn't a schedule
            base,
            shifted,
            schedule([(0, "1.5"), (360, "3.0")]),
            // the temporary switch ends: back to the one before it
            shifted
        ])
        XCTAssertEqual(
            schedules.map(\.uploader),
            ["Trio", "Profile Switch", "Profile Switch", "Profile Switch", "Profile Switch"]
        )
    }

    func testTimeshiftAndPercentage() {
        let base = schedule([(0, "1.0"), (360, "2.0")])
        XCTAssertEqual(NightscoutProfileDocument.adjusted(base, percentage: nil, timeshift: nil), base)
        // -2 h (hours, as Nightscout's careportal sends them): 04:00 runs the 06:00 rate
        XCTAssertEqual(
            NightscoutProfileDocument.adjusted(base, percentage: 100, timeshift: -2),
            schedule([(0, "1.0"), (240, "2.0"), (1320, "1.0")])
        )
    }

    // MARK: - Review round 1

    /// The strict rule (`PumpSessionRules.localTime`, both ends included): a Nightscout record is skipped inside a pump
    /// session's whole `[localStart, lastSeen]` (its gap too, a zero-length one's instant) and in `[the oldest pump dose,
    /// the first localStart]` (a double a second off a pump row there); stored before the local data, between the
    /// sessions, in a Nightscout session's time.
    func testBackfillSkipsThePumpsLocalTime() async throws {
        let f = Fixture()
        f.coordinator.setPumpHistory([PumpHistoryEvent(id: "p", type: .bolus, timestamp: at(-60), amount: 1)])
        try await f.insert([
            localSession(from: days(-3), lastSeen: days(-2.5)),
            localSession(from: days(-2.3), lastSeen: days(-1.5), gaps: [DateInterval(start: days(-2.1), end: days(-2))]),
            localSession(from: days(-1.3), lastSeen: days(-1.3)),
            PumpSessionValue(
                id: UUID(),
                source: .nightscout,
                plugin: "Medtrum",
                activation: days(-6.5),
                start: days(-6.5),
                lastSeen: days(-5.5),
                end: days(-5.5)
            )
        ])
        // the oldest pump dose, before the first session
        try await f.insert([PumpEventRecord(date: days(-4), kind: .bolus, source: .pump, units: 2)])
        let stored = [
            // before the local data: in a Nightscout session, and before it
            nightscoutBolus(days(-7), 1),
            nightscoutBolus(days(-6), 1),
            // between the sessions
            nightscoutBolus(days(-2.4), 1),
            nightscoutTemp(days(-1.4), rate: 1),
            // a second after the zero-length session
            nightscoutBolus(days(-1.3).addingTimeInterval(1), 1)
        ]
        let skipped = [
            // a double a second off the pump row, and a record before the first local start
            nightscoutBolus(days(-4).addingTimeInterval(1), 2),
            nightscoutTemp(days(-3.5), rate: 1),
            // the first session's local start and last heartbeat
            nightscoutBolus(days(-3), 1),
            nightscoutBolus(days(-2.5), 1),
            // the second one's gap
            nightscoutTemp(days(-2.05), rate: 1),
            // the zero-length session's instant
            nightscoutBolus(days(-1.3), 1)
        ]
        let outcome = await f.store.storeBackfill(stored + skipped)
        XCTAssertEqual(outcome, PumpEventStore.BackfillOutcome(inserted: 5, updated: 0, skipped: 6, recent: 0))
        let events = try await f.events(.nightscout)
        XCTAssertEqual(events.map(\.date), stored.map(\.date))
    }

    /// Between the sessions (outside the local time) a Nightscout record at a pump row's identity is skipped; one of
    /// another kind there, or a second off it, is stored. In a pump session's own prefix (`[start, localStart)`), with no
    /// pump dose before its local start, a record is stored: the prefix is Nightscout's.
    func testBackfillIdentityTwinBetweenSessionsAndThePrefix() async throws {
        let f = Fixture()
        f.coordinator.setPumpHistory([PumpHistoryEvent(id: "p", type: .bolus, timestamp: at(-60), amount: 1)])
        try await f.insert([
            localSession(from: days(-6.5), localStart: days(-6), lastSeen: days(-5.5)),
            localSession(from: days(-3), lastSeen: days(-2))
        ])
        try await f.insert([PumpEventRecord(date: days(-4), kind: .bolus, source: .pump, units: 2)])
        let twin = nightscoutBolus(days(-4), 2.1)
        let stored = [
            nightscoutBolus(days(-6.25), 1),
            nightscoutTemp(days(-4), rate: 1),
            nightscoutBolus(days(-4).addingTimeInterval(1), 2)
        ]
        let outcome = await f.store.storeBackfill([twin] + stored)
        XCTAssertEqual(outcome, PumpEventStore.BackfillOutcome(inserted: 3, updated: 0, skipped: 1, recent: 0))
        let events = try await f.events(.nightscout)
        XCTAssertEqual(events.map(\.date), stored.map(\.date))
        XCTAssertEqual(events.map(\.kind), [.bolus, .tempBasal, .bolus])
    }

    /// The Nightscout rows an import before the strict rule left inside the pump's local time (a session's gap, a double
    /// of a pump row before the first session) go at the next prune, counted, once; one between the sessions stays.
    func testThePruneRemovesTheStaleNightscoutRows() async throws {
        let f = Fixture()
        try await f.insert([
            localSession(from: days(-3), lastSeen: days(-2.5)),
            localSession(from: days(-2.3), lastSeen: days(-1.5), gaps: [DateInterval(start: days(-2.1), end: days(-2))])
        ])
        try await f.insert([
            PumpEventRecord(date: days(-4), kind: .bolus, source: .pump, units: 2),
            nightscoutBolus(days(-4).addingTimeInterval(1), 2),
            nightscoutTemp(days(-2.05), rate: 1),
            nightscoutBolus(days(-2.4), 1)
        ])
        let cutoff = days(-120)
        var result = try await f.database.prune(cutoff: cutoff)
        XCTAssertEqual(result.nightscoutRemoved, 2)
        XCTAssertNotNil(result.nightscoutChanged)
        let events = try await f.events(.nightscout)
        XCTAssertEqual(events.map(\.date), [days(-2.4)])
        result = try await f.database.prune(cutoff: cutoff)
        XCTAssertEqual(result, PumpEventStore.PruneResult())
    }

    func testAAPSAndLoopCoverageReadsTheirSparseLoops() throws {
        // a quiet night at the profile basal: AAPS and Loop set no neutral temps, only an SMB at 03:00
        func night(_ uploader: String) -> String {
            """
            [
              {"_id": "\(uploader)1", "eventType": "Temp Basal", "created_at": "2026-10-19T20:00:00.000Z", "rate": 1.4,
               "absolute": 1.4, "duration": 30, "enteredBy": "\(uploader)"},
              {"_id": "\(uploader)2", "eventType": "Temp Basal", "created_at": "2026-10-19T20:30:00.000Z", "rate": 0.4,
               "absolute": 0.4, "duration": 30, "enteredBy": "\(uploader)"},
              {"_id": "\(uploader)3", "eventType": "Correction Bolus", "created_at": "2026-10-20T01:00:00.000Z", "insulin": 0.3,
               "type": "SMB", "automatic": true, "enteredBy": "\(uploader)"},
              {"_id": "\(uploader)4", "eventType": "Temp Basal", "created_at": "2026-10-20T05:00:00.000Z", "rate": 0.2,
               "absolute": 0.2, "duration": 30, "enteredBy": "\(uploader)"},
              {"_id": "\(uploader)5", "eventType": "External Insulin", "created_at": "2026-10-20T08:00:00.000Z", "insulin": 3,
               "enteredBy": "\(uploader)"}
            ]
            """
        }
        let evening = hours(-14)
        let morning = hours(-5)
        for uploader in ["openaps://AndroidAPS", "loop://iPhone"] {
            XCTAssertEqual(
                try NightscoutInsulinTreatment.coverage(from: treatments(night(uploader))),
                [DateInterval(start: evening, end: morning)],
                uploader
            )
        }
        // API v3 AAPS: `app`
        var v3 = try treatments(night("x"))
        for index in v3.indices {
            v3[index].enteredBy = nil
            v3[index].app = "AAPS"
        }
        XCTAssertEqual(NightscoutInsulinTreatment.coverage(from: v3), [DateInterval(start: evening, end: morning)])
        // oref0 sets neutral temps: the same gaps mean nothing was uploaded
        XCTAssertEqual(
            try NightscoutInsulinTreatment.coverage(from: treatments(night("iAPS"))),
            [DateInterval(start: evening, end: evening.addingTimeInterval(.minutes(30)))]
        )
    }

    func testLegacyAAPSTempBasalCancelEndsTheTemp() throws {
        // AAPS < 3.0 (`NSUpload.uploadTempBasalEnd`): no rate, no duration
        let records = try NightscoutInsulinTreatment.records(from: treatments("""
        [
          {"_id": "end", "eventType": "Temp Basal", "created_at": "2026-10-20T07:10:00.000Z", "enteredBy": "AndroidAPS",
           "notes": "Temp basal end"},
          {"_id": "start", "eventType": "Temp Basal", "created_at": "2026-10-20T07:00:00.000Z", "absolute": 1.5, "rate": 1.5,
           "duration": 30, "enteredBy": "openaps://AndroidAPS"},
          {"_id": "percent", "eventType": "Temp Basal", "created_at": "2026-10-20T06:00:00.000Z", "percent": 50, "duration": 30,
           "enteredBy": "openaps://AndroidAPS"}
        ]
        """))
        XCTAssertEqual(records.map(\.date), [at(-170), at(-180)])
        XCTAssertEqual(records[0].durationMin, 0)
        XCTAssertEqual(records[0].rate, 0)
    }

    private func profileSwitch(
        _ date: String,
        id: String,
        profile: String = "Base",
        percentage: Int = 100,
        minutes: Int = 0,
        uploader: String = "AAPS"
    ) -> String {
        """
        {"identifier": "\(id)", "app": "\(uploader)", "eventType": "Profile Switch", "created_at": "\(date)",
         "profile": "\(profile)", "percentage": \(percentage), "duration": \(minutes), "isValid": true}
        """
    }

    private let aapsLibrary = """
    [{"identifier": "doc", "defaultProfile": "Base", "startDate": "2026-10-01T10:00:00.000Z", "app": "AAPS",
      "store": {"Base": {"basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1.0}]},
                "Sport": {"basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 0.5}]}}}]
    """

    func testNestedTemporarySwitchesResolveAsAAPSDoes() throws {
        let documents = try decode([NightscoutProfileDocument].self, aapsLibrary)
        let switches = try treatments("[" + [
            profileSwitch("2026-10-10T10:00:00.000Z", id: "p"),
            // 2 h at 150%, and inside it 30 min of Sport
            profileSwitch("2026-10-11T10:00:00.000Z", id: "t1", percentage: 150, minutes: 120),
            profileSwitch("2026-10-11T10:30:00.000Z", id: "t2", profile: "Sport", minutes: 30),
            // an unknown profile: left out, it doesn't hide t1's end
            profileSwitch("2026-10-11T11:15:00.000Z", id: "x", profile: "Missing", minutes: 10)
        ].joined(separator: ",") + "]")
        let schedules = NightscoutProfileDocument.basalSchedules(documents: documents, switches: switches)
        let t1 = days(-9)
        XCTAssertEqual(schedules.map(\.date), [
            days(-10), t1, t1.addingTimeInterval(.minutes(30)), t1.addingTimeInterval(.minutes(60)),
            t1.addingTimeInterval(.minutes(120))
        ])
        XCTAssertEqual(schedules.map { $0.entries.map(\.rate) }, [[1], [d("1.5")], [d("0.5")], [d("1.5")], [1]])
    }

    func testATemporarySwitchWithoutAKnownPredecessorEnds() throws {
        let switches =
            try treatments("[" + profileSwitch("2026-10-11T10:00:00.000Z", id: "t", percentage: 150, minutes: 60) + "]")
        // ends into the switching uploader's document (its default profile)
        let documents = try decode([NightscoutProfileDocument].self, aapsLibrary)
        var schedules = NightscoutProfileDocument.basalSchedules(documents: documents, switches: switches)
        XCTAssertEqual(schedules.map(\.date), [days(-9), days(-9).addingTimeInterval(.hours(1))])
        XCTAssertEqual(schedules.map { $0.entries.map(\.rate) }, [[d("1.5")], [1]])
        // nothing to end into: the temporary is left out, the other records apply
        let profileJson = #"{\"basal\":[{\"time\":\"00:00\",\"timeAsSeconds\":0,\"value\":1.0}]}"#
        let lone = try treatments("""
        [{"identifier": "t", "app": "AAPS", "eventType": "Profile Switch", "created_at": "2026-10-11T10:00:00.000Z",
          "profile": "Base (150%)", "profileJson": "\(profileJson)", "percentage": 150, "duration": 60}]
        """)
        schedules = NightscoutProfileDocument.basalSchedules(documents: [], switches: lone)
        XCTAssertEqual(schedules, [])
    }

    func testAAPSV1DocumentsWithoutAnUploaderAreALibraryWhenItSwitches() throws {
        let documents = try decode([NightscoutProfileDocument].self, """
        [{"_id": "v1", "defaultProfile": "Base", "startDate": "2026-10-01T10:00:00.000Z",
          "store": {"Base": {"basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 1.0}]}}}]
        """)
        let switches = try treatments("[" + profileSwitch(
            "2026-10-10T10:00:00.000Z",
            id: "p",
            percentage: 80,
            uploader: "openaps://AndroidAPS"
        ).replacingOccurrences(of: "\"app\"", with: "\"enteredBy\"") + "]")
        let schedules = NightscoutProfileDocument.basalSchedules(documents: documents, switches: switches)
        XCTAssertEqual(schedules.map(\.date), [days(-10)])
        XCTAssertEqual(schedules.first?.entries.map(\.rate), [d("0.8")])
    }

    func testTheSwitchesBeforeTheRangeAreFetchedBackToAPermanentOne() async throws {
        let since = days(-3)
        var fake = FakeNightscout()
        var deleted = try treatments("[" + profileSwitch("2026-10-16T10:00:00.000Z", id: "deleted") + "]")
        deleted[0].isValid = false
        fake.treatments[.profileSwitches] = try treatments("[" + [
            profileSwitch("2026-10-15T10:00:00.000Z", id: "temp", percentage: 150, minutes: 60),
            profileSwitch("2026-10-10T10:00:00.000Z", id: "permanent", percentage: 90)
        ].joined(separator: ",") + "]") + deleted
        let fetched = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { _ in }
        XCTAssertEqual(Set(fetched.profileSwitches.compactMap(\.identifier)), ["temp", "permanent"])
    }

    func testProfileDocumentsDatedOddlyDontFailTheImport() async {
        // a negative-offset `startDate` string sorts before its time: the server returns it on pages it is newer than
        let odd = NightscoutProfileDocument(id: "odd", startDate: at(5), defaultProfile: "default", store: [:])
        let older = NightscoutProfileDocument(id: "older", startDate: at(-60), defaultProfile: "default", store: [:])
        let result = await BaseNightscoutManager.fetchTreatmentPages(
            since: days(-1),
            until: at(-30),
            checksEnd: false,
            date: { $0.startDate },
            key: { $0.pagingKey },
            page: { _ in [odd, older] },
            reached: { _ in }
        )
        XCTAssertNil(result.error)
        XCTAssertEqual(result.entries.map(\.id), ["odd", "older"])
    }

    func testProgressOnlyGoesForwardAndEndsAtOne() async {
        let since = days(-3)
        var fake = FakeNightscout()
        fake.treatments[.tempBasals] = (0 ..< 800).map { temp(at(-5 * Double($0)), id: "t\($0)") }
        fake.treatments[.boluses] = (0 ..< 300).map { bolusTreatment(at(-10 * Double($0) - 1), id: "b\($0)") }
        let reports = ProgressRecorder()
        _ = await BaseNightscoutManager.fetchInsulin(since: since, until: at(10), source: fake.source) { reports.append($0) }
        // a `reached` still in flight lands after the end: ignored
        try? await Task.sleep(nanoseconds: 50_000_000)
        let values = reports.all
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(values, values.sorted())
    }

    func testHugeNumbersDontCrash() throws {
        let documents = try decode([NightscoutProfileDocument].self, """
        [{"_id": "x", "defaultProfile": "default", "startDate": "2026-10-10T10:00:00.000Z",
          "store": {"default": {"basal": [{"time": "00:00", "value": 1, "timeAsSeconds": 1e300}]}}}]
        """)
        XCTAssertNil(documents[0].basalSchedule())
        XCTAssertNotNil(NightscoutProfileDocument.adjusted(schedule([(0, "1")]), percentage: 100, timeshift: 1E300))
        XCTAssertNil(NightscoutDate.parse("1e300"))
        let treatment = try treatments(#"[{"eventType": "SMB", "date": 1e300, "insulin": 1}]"#)
        XCTAssertNil(treatment[0].createdAt)
    }

    func testScheduleBackfillWithoutALocalRecordEndsItsSpanAtTheStoresNow() async throws {
        let f = Fixture()
        f.clock.now = hours(2)
        _ = await f.store.storeScheduleBackfill([
            NightscoutBasalSchedule(date: days(-30), entries: schedule([(0, "0.5")]), uploader: "iAPS", timeZone: nil)
        ])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: days(-30), end: hours(2)))])
    }
}

private extension PumpEventRecord {
    func with(_ change: (inout PumpEventRecord) -> Void) -> PumpEventRecord {
        var record = self
        change(&record)
        return record
    }
}
