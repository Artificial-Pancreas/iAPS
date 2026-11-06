import Combine
import CoreData
@testable import FreeAPS
#if canImport(LoopKit)
    import LoopKit
#endif
import XCTest

private final class TestClock: @unchecked Sendable {
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

private final class Recorder<Item>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Item] = []

    func append(_ item: Item) {
        lock.withLock { items.append(item) }
    }

    func clear() {
        lock.withLock { items.removeAll() }
    }

    var all: [Item] {
        lock.withLock { items }
    }
}

/// The real database with its reconciles recorded. While the gate is closed a reconcile waits at it (before touching
/// the store) until it opens.
private actor GatedDatabase: PumpEventDatabase {
    private let base: CoreDataPumpEventDatabase
    private(set) var reconciles: [PumpEventStore.ReconcileRequest] = []
    private(set) var results: [PumpEventStore.ReconcileResult] = []
    private var closed = false
    private var held: [AsyncStream<Void>.Continuation] = []
    private var watchers: [AsyncStream<Void>.Continuation] = []

    init(_ base: CoreDataPumpEventDatabase) {
        self.base = base
    }

    func close() {
        closed = true
    }

    func open() {
        closed = false
        let waiting = held
        held = []
        waiting.forEach { $0.finish() }
    }

    /// Returns once a reconcile waits at the gate (at once when one does).
    func arrival() async {
        guard held.isEmpty else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        watchers.append(continuation)
        for await _ in stream {}
    }

    func reconcile(_ request: PumpEventStore.ReconcileRequest) async throws -> PumpEventStore.ReconcileResult {
        reconciles.append(request)
        if closed {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            held.append(continuation)
            let arrived = watchers
            watchers = []
            arrived.forEach { $0.finish() }
            for await _ in stream {}
        }
        let result = try await base.reconcile(request)
        results.append(result)
        return result
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
        try await base.storeBackfill(batch)
    }

    func storeSchedules(_ schedules: [PumpEventStore.ScheduleInsert], now: Date) async throws -> PumpEventStore
        .ScheduleBackfillResult
    {
        try await base.storeSchedules(schedules, now: now)
    }

    func storeNightscoutSessions(_ request: PumpEventStore.NightscoutSessionsRequest) async throws -> PumpEventStore
        .NightscoutSessionsResult
    {
        try await base.storeNightscoutSessions(request)
    }
}

/// Files in memory, for the pump history storage: only what it uses is implemented.
private actor MemoryFileStorage: FileStorage {
    private var files: [String: Data] = [:]

    func save<Value: Encodable & Sendable>(_ value: Value, as name: String) {
        if let string = value as? String {
            files[name] = Data(string.utf8)
        } else {
            files[name] = try? JSONCoding.encoder.encode(value)
        }
    }

    func save<Value: Decodable & Sendable>(raw: RawJSON, as name: String, decodingInto _: Value.Type) throws {
        _ = try JSONCoding.decoder.decode(Value.self, from: Data(raw.utf8))
        files[name] = Data(raw.utf8)
    }

    func retrieve<Value: Decodable & Sendable>(_ name: String, as _: Value.Type) -> Value? {
        files[name].flatMap { try? JSONCoding.decoder.decode(Value.self, from: $0) }
    }

    func retrieveRaw(_ name: String) -> String? {
        files[name].flatMap { String(data: $0, encoding: .utf8) }
    }

    func modify<Value: JSON>(file: String, as _: Value.Type, _ modify: @Sendable([Value]) -> [Value]) -> [Value] {
        let values = modify(retrieve(file, as: [Value].self) ?? [])
        save(values, as: file)
        return values
    }

    func delete<Value: JSON>(
        file: String,
        as _: Value.Type,
        where shouldDelete: @Sendable(Value) -> Bool
    ) -> (kept: [Value], deleted: [Value]?) {
        let values = retrieve(file, as: [Value].self) ?? []
        let deleted = values.filter(shouldDelete)
        guard deleted.isNotEmpty else { return (values, nil) }
        let kept = values.filter { !shouldDelete($0) }
        save(kept, as: file)
        return (kept, deleted)
    }

    func append<Value: JSON>(_: Value, to _: String) -> [Value]? { fatalError("unused") }
    func append<Value: JSON>(_: [Value], to _: String) -> [Value]? { fatalError("unused") }
    func append<Value: JSON, T: Equatable & Sendable>(_: Value, to _: String, uniqBy _: KeyPath<Value, T> & Sendable)
        -> [Value]? { fatalError("unused") }
    func append<Value: JSON, T: Equatable & Sendable>(_: [Value], to _: String, uniqBy _: KeyPath<Value, T> & Sendable)
        -> [Value]? { fatalError("unused") }
    func append<Value: JSON, T: Equatable & Sendable>(_: [Value], to _: String, uniqByProj _: @Sendable(Value) -> T)
        -> [Value]? { fatalError("unused") }
    func appendAndModify<Value: JSON, T: Equatable & Sendable>(
        _: [Value],
        to _: String,
        uniqBy _: KeyPath<Value, T> & Sendable,
        _: @Sendable([Value]) -> [Value]
    ) -> [Value] { fatalError("unused") }
    func maybeModify<Value: JSON>(file _: String, as _: Value.Type, _: @Sendable([Value]) -> [Value]?) -> (Bool, [Value]) {
        fatalError("unused")
    }

    func maybeModifyWithData<Value: JSON, Payload: Sendable>(
        file _: String,
        as _: Value.Type,
        _: @Sendable([Value]) -> ([Value], data: Payload)?
    ) -> (Bool, [Value], data: Payload?) { fatalError("unused") }
    func remove(_: String) { fatalError("unused") }
    func rename(_: String, to _: String) { fatalError("unused") }
    func urlFor(file _: String) -> URL? { nil }
}

private struct ScheduleRow: Sendable, Equatable {
    let date: Date
    let source: Int16
    let fingerprint: String
}

final class PumpEventStoreTests: XCTestCase {
    // MARK: - Fixtures

    private static let berlin = StatsFixtures.berlin

    /// 2026-10-20 12:00 Europe/Berlin (CEST)
    private static let t0 = StatsFixtures.day0.addingTimeInterval(.hours(12))

    /// `t0` plus the minutes
    private func at(_ minutes: Double) -> Date {
        Self.t0.addingTimeInterval(.minutes(minutes))
    }

    private func d(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    /// The date `minutes` (as the pump history stores them) after `start`: the end of a temp basal's stored span.
    private func after(_ start: Date, minutes: String) -> Date {
        start.addingTimeInterval(.minutes(Double(d(minutes))))
    }

    /// A store on an in-memory container, at a test clock, with the change signals it sends recorded.
    private final class Fixture {
        let container: NSPersistentContainer
        let database: CoreDataPumpEventDatabase
        let coordinator: AppCoordinator
        let clock: TestClock
        let signals = Recorder<InsulinDataChange>()
        private(set) var store: PumpEventStore
        private var subscription: AnyCancellable?

        init() {
            let container = StatsFixtures.inMemoryContainer()
            let database = CoreDataPumpEventDatabase(container: container, mergeBatchDelete: { _ in })
            let coordinator = AppCoordinator()
            let clock = TestClock(PumpEventStoreTests.t0)
            self.container = container
            self.database = database
            self.coordinator = coordinator
            self.clock = clock
            store = Self.makeStore(coordinator, database, clock)
            let signals = self.signals
            subscription = coordinator.insulinDataChanged.sink { signals.append($0) }
        }

        private static func makeStore(
            _ coordinator: AppCoordinator,
            _ database: PumpEventDatabase,
            _ clock: TestClock
        ) -> PumpEventStore {
            PumpEventStore(
                appCoordinator: coordinator,
                database: database,
                calendar: { PumpEventStoreTests.berlin },
                now: { clock.now }
            )
        }

        /// A new process on the same store (a relaunch).
        func relaunch() {
            store = Self.makeStore(coordinator, database, clock)
        }

        /// A new process whose store writes through `database`.
        func use(_ database: PumpEventDatabase) {
            store = Self.makeStore(coordinator, database, clock)
        }

        /// Publishes the list (newest -> oldest, as the file does), then reconciles at `now`.
        func reconcile(_ history: [PumpHistoryEvent]? = nil, at now: Date? = nil) async {
            if let now {
                clock.now = now
            }
            if let history {
                coordinator.setPumpHistory(history.sorted { $0.timestamp > $1.timestamp })
            }
            await store.requestReconcile()
            await store.idle()
        }

        /// - Parameter active: `deliveryUnitActive`; by default as `KnownPlugins.isDeliveryUnitActive` gives it for a
        ///   healthy pod/patch: Omnipod and Medtrum need an activated one
        func delivering(_ identifier: String = "Dana", onboarded: Bool = true, pod: Date? = nil, active: Bool? = nil) {
            coordinator.setPumpInfo(Self.pumpInfo(identifier, onboarded: onboarded, pod: pod, active: active))
        }

        static func pumpInfo(
            _ identifier: String,
            onboarded: Bool = true,
            pod: Date? = nil,
            active: Bool? = nil
        ) -> PumpDisplayInfo {
            PumpDisplayInfo(
                identifier: identifier,
                name: identifier,
                isOnboarded: onboarded,
                image: nil,
                expiresAt: nil,
                podActivatedAt: pod,
                deliveryUnitActive: active ?? (["Omni", "Medtrum"].contains(identifier) ? pod != nil : true)
            )
        }

        func notDelivering() {
            coordinator.setPumpInfo(nil)
        }

        /// Every event row, oldest -> newest.
        func events() async throws -> [PumpEventRecord] {
            try await rows()
        }

        /// Every `PumpEvent` row of a known kind, oldest -> newest.
        func rows() async throws -> [PumpEventRecord] {
            try await container.performBackgroundTask { context in
                let fetch = NSFetchRequest<PumpEvent>(entityName: PumpEventStore.Entity.events)
                return try context.fetch(fetch)
                    .compactMap { CoreDataPumpEventDatabase.record(of: $0) }
                    .sorted { ($0.date, $0.kind.rawValue, $0.source.rawValue) < ($1.date, $1.kind.rawValue, $1.source.rawValue) }
            }
        }

        /// Oldest -> newest.
        func schedules() async throws -> [ScheduleRow] {
            try await container.performBackgroundTask { context in
                let fetch = NSFetchRequest<BasalScheduleRecord>(entityName: PumpEventStore.Entity.schedules)
                fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
                return try context.fetch(fetch).map { row in
                    ScheduleRow(
                        date: row.date ?? .distantPast,
                        source: row.source,
                        // the fingerprint of the entries as stored (they decode to the schedule)
                        fingerprint: row.entries.flatMap { BasalScheduleRecordValue.decode($0) }
                            .map { BasalScheduleRecordValue.fingerprint($0) } ?? ""
                    )
                }
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

        /// A Nightscout schedule record.
        func insertSchedule(at date: Date, _ entries: [BasalProfileEntry]) async throws {
            let json = BasalScheduleRecordValue.encode(entries)
            let fingerprint = BasalScheduleRecordValue.fingerprint(entries)
            try await container.performBackgroundTask { context in
                let row = BasalScheduleRecord(context: context)
                row.date = date
                row.source = BasalScheduleSource.nightscout.rawValue
                row.entries = json
                row.fingerprint = fingerprint
                try context.save()
            }
        }

        /// LoopStatRecord rows: started at each date, ended 20 s later.
        func insertLoops(_ starts: [Date], status: String = "Success") async throws {
            try await container.performBackgroundTask { context in
                for start in starts {
                    let row = LoopStatRecord(context: context)
                    row.start = start
                    row.end = start.addingTimeInterval(20)
                    row.loopStatus = status
                }
                try context.save()
            }
        }

        /// The `PumpSession` rows, by start.
        func sessions() async throws -> [PumpSessionValue] {
            try await container.performBackgroundTask { context in
                try CoreDataPumpEventDatabase.sessionRows(in: context).map(\.value).sorted { $0.start < $1.start }
            }
        }

        func insert(_ sessions: [PumpSessionValue]) async throws {
            try await container.performBackgroundTask { context in
                for session in sessions {
                    CoreDataPumpEventDatabase.apply(session, to: PumpSession(context: context))
                }
                try context.save()
            }
        }

        /// `PumpEvent` rows of a kind no record maps (the coverage rows of earlier builds: kind 9, `end`, `eventID`).
        func insertOtherKind(_ dates: [Date], kind: Int16 = 9) async throws {
            try await container.performBackgroundTask { context in
                for date in dates {
                    let row = PumpEvent(context: context)
                    row.date = date
                    row.kind = kind
                    row.source = PumpEventSource.pump.rawValue
                }
                try context.save()
            }
        }

        /// Every `PumpEvent` row, of any kind.
        func rowCount() async throws -> Int {
            try await container.performBackgroundTask { context in
                try context.count(for: NSFetchRequest<PumpEvent>(entityName: PumpEventStore.Entity.events))
            }
        }

        /// One `hasNewPumpEvents` call's change events, received at `now`.
        func send(_ events: [PumpLifecycleEvent], at now: Date? = nil) async {
            if let now {
                clock.now = now
            }
            await store.lifecycleEvents(events)
        }
    }

    private func bolus(
        _ date: Date,
        _ amount: String,
        mutable: Bool? = nil,
        smb: Bool = false,
        external: Bool = false,
        id: String = UUID().uuidString
    ) -> PumpHistoryEvent {
        PumpHistoryEvent(
            id: id,
            type: .bolus,
            timestamp: date,
            isMutable: mutable,
            amount: d(amount),
            duration: 0,
            isSMB: smb,
            isExternal: external
        )
    }

    /// The pair the pump history storage writes: `.tempBasalDuration` (id X) and `.tempBasal` (id _X).
    private func temp(
        _ date: Date,
        rate: String,
        minutes: String,
        delivered: String? = nil,
        mutable: Bool? = nil,
        id: String = UUID().uuidString,
        percent: Bool = false
    ) -> [PumpHistoryEvent] {
        [
            PumpHistoryEvent(id: id, type: .tempBasalDuration, timestamp: date, isMutable: mutable, durationMin: d(minutes)),
            PumpHistoryEvent(
                id: "_" + id,
                type: .tempBasal,
                timestamp: date,
                isMutable: mutable,
                rate: d(rate),
                deliveredUnits: delivered.map { d($0) },
                temp: percent ? .percent : .absolute
            )
        ]
    }

    private func suspend(_ date: Date) -> PumpHistoryEvent {
        PumpHistoryEvent(id: UUID().uuidString, type: .pumpSuspend, timestamp: date)
    }

    private func resume(_ date: Date) -> PumpHistoryEvent {
        PumpHistoryEvent(id: UUID().uuidString, type: .pumpResume, timestamp: date)
    }

    /// A stored pump row.
    private func row(_ date: Date, _ kind: PumpEventKind, mutable: Bool = false) -> PumpEventRecord {
        PumpEventRecord(date: date, kind: kind, source: .pump, units: 1, isMutable: mutable)
    }

    private func schedule(_ entries: [(start: String, minutes: Int, rate: String)]) -> [BasalProfileEntry] {
        entries.map { BasalProfileEntry(start: $0.start, minutes: $0.minutes, rate: d($0.rate)) }
    }

    private func fingerprint(_ entries: [BasalProfileEntry]) -> String {
        BasalScheduleRecordValue.fingerprint(entries)
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while try await !condition() {
            guard Date() < deadline else {
                XCTFail("timed out", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Mapping

    func testTempPairIsOneRowInEitherOrderAndAnUnpairedHalfIsSkipped() {
        let pair = temp(at(0), rate: "0.8", minutes: "30.1", mutable: true, id: "A")
        let lone = temp(at(10), rate: "1.2", minutes: "30.1", id: "B")

        let records = PumpEventRecord.records(from: [pair[1], pair[0], lone[0]])
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record.kind, .tempBasal)
        XCTAssertEqual(record.source, .pump)
        XCTAssertEqual(record.date, at(0))
        XCTAssertEqual(record.rate, 0.8, accuracy: 1E-9)
        XCTAssertEqual(record.durationMin, 30.1, accuracy: 1E-9)
        XCTAssertEqual(record.units, -1)
        XCTAssertTrue(record.isMutable)
        XCTAssertNil(record.deliveredUnits)
        // the file's +0.1 min taken off
        XCTAssertEqual(record.nominalDuration, .minutes(30), accuracy: 1E-6)

        XCTAssertEqual(PumpEventRecord.records(from: pair), records)
        XCTAssertEqual(PumpEventRecord.records(from: [lone[1]]), [])
        XCTAssertEqual(PumpEventRecord.records(from: [lone[0]]), [])
    }

    func testTempHalvesPairOnlyInTheSameSecond() {
        let halves = temp(at(0), rate: "0.8", minutes: "30.1", id: "A")
        let rate = halves[1]
        let moved = PumpHistoryEvent(id: "_A", type: .tempBasal, timestamp: at(1), rate: rate.rate, temp: .absolute)
        XCTAssertEqual(PumpEventRecord.records(from: [halves[0], moved]), [])
    }

    func testOneMutableHalfMakesTheTempMutable() {
        var pair = temp(at(0), rate: "0.8", minutes: "30.1", mutable: false, id: "A")
        pair[0] = PumpHistoryEvent(id: "A", type: .tempBasalDuration, timestamp: at(0), isMutable: true, durationMin: 30)
        XCTAssertEqual(PumpEventRecord.records(from: pair).map(\.isMutable), [true])
    }

    func testFinalTempCarriesItsDeliveredUnits() {
        let records = PumpEventRecord.records(from: temp(at(0), rate: "0.8", minutes: "12.4", delivered: "0.16"))
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records[0].isMutable)
        XCTAssertEqual(records[0].deliveredUnits ?? -1, 0.16, accuracy: 1E-9)
        XCTAssertEqual(records[0].nominalDuration, .minutes(12.3), accuracy: 1E-6)
        XCTAssertEqual(records[0].span, DateInterval(start: at(0), end: after(at(0), minutes: "12.4")))

        // Nightscout rows carry no +0.1
        var nightscout = records[0]
        nightscout.source = .nightscout
        nightscout.durationMin = 30
        XCTAssertEqual(nightscout.nominalDuration, .minutes(30), accuracy: 1E-6)
    }

    func testBolusKinds() {
        let records = PumpEventRecord.records(from: [
            bolus(at(0), "0.3", smb: true),
            bolus(at(1), "2", mutable: true),
            bolus(at(2), "4", external: true),
            suspend(at(3)),
            resume(at(4)),
            PumpHistoryEvent(id: "r", type: .rewind, timestamp: at(5)),
            PumpHistoryEvent(id: "a", type: .pumpAlarm, timestamp: at(6), note: "alarm")
        ])
        XCTAssertEqual(records.map(\.kind), [.bolus, .bolus, .bolus, .suspend, .resume])
        XCTAssertEqual(records.map(\.isSMB), [true, false, false, false, false])
        XCTAssertEqual(records.map(\.isExternal), [false, false, true, false, false])
        XCTAssertEqual(records.map(\.isMutable), [false, true, false, false, false])
        XCTAssertEqual(records.map(\.signature.units), [300, 2000, 4000, 0, 0])
    }

    func testDecodedTimestampIsTruncated() throws {
        let json = """
        [{"id": "x", "_type": "Bolus", "timestamp": "2026-10-20T10:00:05.700Z", "amount": 1, "isSMB": true}]
        """
        let events = try JSONCoding.decoder.decode([PumpHistoryEvent].self, from: Data(json.utf8))
        XCTAssertNotEqual(events[0].timestamp, events[0].timestamp.truncatedToSecond)
        let records = PumpEventRecord.records(from: events)
        XCTAssertEqual(records.map(\.date), [Date(timeIntervalSince1970: 1_792_490_405)])
        XCTAssertEqual(PumpEventRecord.identity(of: events[0])?.date, records[0].date)
    }

    func testSignatureIsStableOverAJSONRoundTrip() throws {
        let history = [bolus(at(0), "0.05", smb: true), bolus(at(1), "1.35", mutable: true)] +
            temp(at(2), rate: "0.35", minutes: "7.3", delivered: "0.043") + temp(at(10), rate: "1.15", minutes: "30.1")
        let data = try JSONCoding.encoder.encode(history)
        let decoded = try JSONCoding.decoder.decode([PumpHistoryEvent].self, from: data)
        let before = PumpEventRecord.records(from: history)
        let after = PumpEventRecord.records(from: decoded)
        XCTAssertEqual(after.map(\.signature), before.map(\.signature))
        XCTAssertEqual(PumpEventStore.diff(current: after, stored: before, now: at(20)), PumpEventStore.Diff())
    }

    func testSameSecondCollapsesAndPercentTempsAreSkipped() {
        let records = PumpEventRecord.records(from: [
            bolus(at(0), "1", id: "first"),
            bolus(at(0).addingTimeInterval(0.6), "2", id: "second")
        ] + temp(at(5), rate: "120", minutes: "30", percent: true))
        XCTAssertEqual(records.map(\.units), [1])
    }

    func testScheduleFingerprint() {
        let a = schedule([("00:00:00", 0, "0.5"), ("06:00:00", 360, "1.0")])
        let reordered = schedule([("06:00", 360, "1"), ("00:00", 0, "0.5000")])
        XCTAssertEqual(fingerprint(a), "0:0.500,360:1.000")
        XCTAssertEqual(fingerprint(reordered), fingerprint(a))
        XCTAssertNotEqual(fingerprint(schedule([("00:00:00", 0, "0.5"), ("06:00:00", 360, "1.05")])), fingerprint(a))
        let decoded = BasalScheduleRecordValue.encode(a).flatMap { BasalScheduleRecordValue.decode($0) }
        XCTAssertEqual(decoded.map { fingerprint($0) }, fingerprint(a))
    }

    func testRawJSONEditRemovalsAreTheMissingIdentities() {
        let kept = bolus(at(0), "1")
        let removed = bolus(at(1), "2")
        let tempPair = temp(at(2), rate: "0.5", minutes: "30.1")
        let edited = PumpHistoryEvent(id: kept.id, type: .bolus, timestamp: at(0), amount: 3)
        let moved = bolus(at(3), "4")
        let movedLater = PumpHistoryEvent(id: moved.id, type: .bolus, timestamp: at(4), amount: 4)

        let result = BasePumpHistoryStorage.removed(
            from: [kept, removed, moved] + tempPair,
            keeping: [edited, movedLater] + tempPair
        )
        // an edited amount is an update, a moved timestamp a removal (and a new event)
        XCTAssertEqual(result, [removed, moved])
    }

    func testRawJSONEditDeletesWhatTheEditorRemovedAfterThePublish() async throws {
        let coordinator = AppCoordinator()
        let files = MemoryFileStorage()
        let storage = BasePumpHistoryStorage(storage: files, appCoordinator: coordinator)
        // inside the file's 24 h
        let now = Date().truncatedToSecond
        let kept = bolus(now.addingTimeInterval(-.minutes(30)), "1")
        let removed = bolus(now.addingTimeInterval(-.minutes(20)), "2")
        let smb = bolus(now.addingTimeInterval(-.minutes(1)), "0.3", smb: true)
        await storage.storeEvents([kept, removed])
        let file = await files.retrieveRaw(OpenAPS.Monitor.pumpHistory)
        let loaded = try XCTUnwrap(file)
        // stored while the editor is open: not in the edit, but not deleted by the user either
        await storage.storeEvents([smb])

        let order = Recorder<String>()
        let published = coordinator.pumpHistory.dropFirst().sink { list in
            order.append("published \(list.map(\.id))")
        }
        let deletions = coordinator.pumpHistoryDeletions.sink { deleted in
            order.append("deleted \(deleted.map(\.id)), listed: \(coordinator.pumpHistory.value.map(\.id))")
        }
        let edited = try XCTUnwrap(String(data: JSONCoding.encoder.encode([kept]), encoding: .utf8))
        try await storage.saveRawJSON(edited, editing: loaded)

        XCTAssertEqual(order.all, [
            "published \([kept.id])",
            "deleted \([removed.id]), listed: \([kept.id])"
        ])
        published.cancel()
        deletions.cancel()
    }

    // MARK: - Rules

    func testDiffWindowStartRule() {
        let now = at(0)
        // the list holds events older than 24 h (the file is read unfiltered at start)
        let current = [row(now.addingTimeInterval(-.hours(25)), .bolus)]
        let stored = [
            // a mutable row missing from the list within 5 min of the 24 h edge: kept
            row(now.addingTimeInterval(-.hours(24) + .minutes(4)), .bolus, mutable: true),
            // a mutable row missing from the list after it: deleted
            row(now.addingTimeInterval(-.hours(2)), .bolus, mutable: true),
            // a final missing from the list: kept
            row(now.addingTimeInterval(-.hours(1)), .bolus)
        ]
        XCTAssertEqual(PumpEventStore.diff(current: current, stored: stored, now: now).deletes, [1])

        // a list that lost its older part: a mutable row before its oldest event is not deleted
        let shortList = [row(now.addingTimeInterval(-.hours(3)), .bolus)]
        let older = [row(now.addingTimeInterval(-.hours(4)), .tempBasal, mutable: true)]
        XCTAssertEqual(
            PumpEventStore.diff(current: shortList, stored: older, now: now),
            PumpEventStore.Diff(inserts: shortList)
        )

        // an empty list (a corrupt file) changes nothing
        XCTAssertEqual(PumpEventStore.diff(current: [], stored: stored, now: now), PumpEventStore.Diff())
    }

    func testDiffInsertsUpdatesAndDropsDuplicates() {
        var changed = row(at(-10), .bolus, mutable: true)
        let same = row(at(-20), .bolus)
        let stored = [changed, same, same]
        changed.units = 0.95
        changed.isMutable = false
        let new = row(at(-5), .suspend)

        let diff = PumpEventStore.diff(current: [new, changed, same], stored: stored, now: at(0))
        XCTAssertEqual(diff.inserts, [new])
        XCTAssertEqual(diff.updates, [PumpEventStore.Diff.Update(index: 0, record: changed)])
        XCTAssertEqual(diff.deletes, [2])
    }

    func testMedtrumPatchStatesThatDeliver() {
        // active, active_alt, and the suspended states (their suspensions are reported as events)
        for raw: UInt8 in [32, 33, 64, 65, 66, 67, 68, 69, 70] {
            XCTAssertTrue(KnownPlugins.isDelivering(patchState: raw), "\(raw)")
        }
        // none and the setup states; occlusion, expired, reservoir empty, the faults, battery out, no calibration;
        // stopped; an unknown state
        for raw: UInt8 in [0, 1, 2, 3, 4, 5, 6, 96, 97, 98, 99, 100, 101, 102, 103, 128, 200] {
            XCTAssertFalse(KnownPlugins.isDelivering(patchState: raw), "\(raw)")
        }
    }

    #if canImport(LoopKit)
        func testOmnipodFaultedPodDoesNotDeliver() {
            let activated = at(-600)
            XCTAssertTrue(KnownPlugins.isDelivering(podActivatedAt: activated, basalDeliveryState: .active(at(-60))))
            XCTAssertTrue(KnownPlugins.isDelivering(podActivatedAt: activated, basalDeliveryState: .suspended(at(-5))))
            // a faulted pod (or one not set up) is reported "just like no pod"
            XCTAssertFalse(KnownPlugins.isDelivering(podActivatedAt: activated, basalDeliveryState: .active(.distantPast)))
            XCTAssertFalse(KnownPlugins.isDelivering(podActivatedAt: nil, basalDeliveryState: .active(at(-60))))
        }
    #endif

    // MARK: - Live mirror

    func testInsertSignalsTheChangedSpanAndAReconcileWithoutChangesSignalsNothing() async throws {
        let f = Fixture()
        let history = [bolus(at(-60), "1")] + temp(at(-30), rate: "0.8", minutes: "30.1")
        await f.reconcile(history)

        var events = try await f.events()
        XCTAssertEqual(events.map(\.kind), [.bolus, .tempBasal])
        XCTAssertEqual(events.map(\.source), [.pump, .pump])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(-60), end: after(at(-30), minutes: "30.1")))])

        f.signals.clear()
        await f.reconcile(history, at: at(1))
        XCTAssertEqual(f.signals.all, [])
        events = try await f.events()
        XCTAssertEqual(events.count, 2)
    }

    func testMedtrumMutableDosesBecomeFinalInPlace() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: at(-600))
        let mutable = [bolus(at(-10), "1", mutable: true, id: "bolus")] +
            temp(at(-20), rate: "0.8", minutes: "30.1", mutable: true, id: "temp")
        await f.reconcile(mutable)
        let inserted = try await f.events()
        XCTAssertEqual(inserted.map(\.isMutable), [true, true])
        XCTAssertEqual(inserted.map(\.units), [-1, 1])

        // re-sent mutable with every replacePendingEvents batch: nothing changes
        await f.reconcile(mutable, at: at(1))
        var events = try await f.events()
        XCTAssertEqual(events, inserted)

        // the records are matched: finals, with the delivered amounts
        let finals = [bolus(at(-10), "0.95", mutable: false, id: "bolus")] +
            temp(at(-20), rate: "0.8", minutes: "12.4", delivered: "0.16", mutable: false, id: "temp")
        f.signals.clear()
        await f.reconcile(finals, at: at(2))
        events = try await f.events()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.isMutable), [false, false])
        XCTAssertEqual(events[0].units, 0.16, accuracy: 1E-9)
        XCTAssertEqual(events[0].durationMin, 12.4, accuracy: 1E-9)
        XCTAssertEqual(events[1].units, 0.95, accuracy: 1E-9)
        // the temp's old span (30.1 min) and new one, the bolus, the session's extension
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(-20), end: after(at(-20), minutes: "30.1")))])

        // the final leaves the file (or the file is lost): frozen
        await f.reconcile([], at: at(3))
        let frozen = try await f.events()
        XCTAssertEqual(frozen, events)
    }

    func testMutableDoseNoLongerReportedIsDeleted() async throws {
        let f = Fixture()
        let final = bolus(at(-60), "1", mutable: false)
        await f.reconcile(
            [final, bolus(at(-5), "2", mutable: true)] + temp(at(-4), rate: "1", minutes: "30.1", mutable: true)
        )
        var events = try await f.events()
        XCTAssertEqual(events.count, 3)

        // a replacePendingEvents batch that no longer reports the mutable doses
        f.signals.clear()
        await f.reconcile([final], at: at(1))
        events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-60)])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(-5), end: after(at(-4), minutes: "30.1")))])
    }

    func testFinalsMissingFromTheListAreKept() async throws {
        let f = Fixture()
        await f.reconcile(
            [bolus(at(-600), "1"), bolus(at(-300), "2"), bolus(at(-60), "3")] +
                temp(at(-400), rate: "0.5", minutes: "30.1", mutable: true)
        )
        var events = try await f.events()
        XCTAssertEqual(events.count, 4)

        // a corrupt file reads as []
        await f.reconcile([], at: at(1))
        events = try await f.events()
        XCTAssertEqual(events.count, 4)

        // the next write keeps only the new events (as does a clock set ahead and back): the rows before the list's
        // oldest event are not deleted, mutable or not
        await f.reconcile([bolus(at(-60), "3"), bolus(at(-1), "0.5", smb: true)], at: at(2))
        events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-600), at(-400), at(-300), at(-60), at(-1)])
        XCTAssertEqual(events.map(\.isMutable), [false, true, false, false, false])

        // a final missing from inside the list's time: kept too
        await f.reconcile([bolus(at(-300), "2"), bolus(at(-1), "0.5", smb: true)], at: at(3))
        events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-600), at(-400), at(-300), at(-60), at(-1)])
    }

    func testANightscoutRowAtAListIdentityIsNotRewrittenButGoesInsideTheListsSpan() async throws {
        let f = Fixture()
        try await f.insert([
            PumpEventRecord(date: at(-10), kind: .bolus, source: .nightscout, units: 2),
            PumpEventRecord(date: at(-2000), kind: .bolus, source: .nightscout, units: 3)
        ])
        await f.reconcile([bolus(at(-10), "1")])
        // the pump row is inserted (the Nightscout one not rewritten into it); the Nightscout row at the list's
        // identity is inside the file's time (step 4) and goes; the one before the file's 24 h and the pump's rows stays
        let events = try await f.events()
        XCTAssertEqual(events.map(\.source), [.nightscout, .pump])
        XCTAssertEqual(events.map(\.units), [3, 1])
    }

    func testRowsBeforeTheListAreNotTouched() async throws {
        let f = Fixture()
        // a mutable row from long ago, and one a minute before the list (read: inside the lookback, still before the
        // list's oldest event)
        try await f.insert([row(at(-300), .bolus, mutable: true), row(at(-61), .bolus, mutable: true)])
        await f.reconcile([bolus(at(-60), "1")])
        let events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-300), at(-61), at(-60)])
    }

    func testABurstOfPublishesIsOneReconcileReadingTheNewestList() async throws {
        let f = Fixture()
        let gated = GatedDatabase(f.database)
        f.use(gated)
        let first = [bolus(at(-10), "1")]
        let second = first + [bolus(at(-5), "2")]
        let third = second + [bolus(at(-2), "3")]

        await gated.close()
        f.coordinator.setPumpHistory(first)
        await f.store.requestReconcile()
        // the first reconcile has read the list and waits in the database
        await gated.arrival()

        // published during it: one more reconcile (the dirty flag was cleared before the read), reading the list
        // when it starts
        f.coordinator.setPumpHistory(second.reversed())
        await f.store.requestReconcile()
        await f.store.requestReconcile()
        f.coordinator.setPumpHistory(third.reversed())
        await f.store.requestReconcile()

        await gated.open()
        await f.store.idle()

        let reconciles = await gated.reconciles
        XCTAssertEqual(reconciles.map(\.current.count), [1, 3])
        let events = try await f.events()
        XCTAssertEqual(events.count, 3)
    }

    func testStartObservesTheSubjects() async throws {
        let f = Fixture()
        f.coordinator.setBasalProfile(schedule([("00:00:00", 0, "0.8")]))
        await f.store.start()

        let deleted = bolus(at(-10), "1")
        f.coordinator.setPumpHistory([deleted])
        try await waitUntil { try await f.events().count == 1 }

        f.coordinator.setPumpHistory([])
        f.coordinator.sendPumpHistoryDeleted([deleted])
        try await waitUntil { try await f.events().isEmpty }

        try await waitUntil { try await f.schedules().count == 1 }

        f.delivering()
        f.coordinator.sendLoopCompleted(.failed(error: "x", timestamp: at(0)))
        try await waitUntil { try await f.sessions().count == 1 }
    }

    // MARK: - Explicit deletions

    func testExplicitDeletionsDeleteThePumpsRowsFinalOrNot() async throws {
        let f = Fixture()
        let final = bolus(at(-30), "1", mutable: false)
        let tempPair = temp(at(-20), rate: "0.8", minutes: "10.1", delivered: "0.13", mutable: false)
        await f.reconcile([final] + tempPair)
        try await f.insert([PumpEventRecord(date: at(-40), kind: .bolus, source: .nightscout, units: 2)])

        // DataTable's deleteInsulin: the list without it, then the deletion
        f.coordinator.setPumpHistory(tempPair)
        f.signals.clear()
        await f.store.deleted([final])
        var events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-40), at(-20)])
        // up to the next event that ends a temp or a suspension: the temp
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(-30), end: at(-20)))])

        // a temp basal: both halves of the pair
        f.coordinator.setPumpHistory([])
        await f.store.deleted(tempPair)
        // a Nightscout row with a deleted identity is not the pump's
        await f.store.deleted([bolus(at(-40), "2")])
        events = try await f.events()
        XCTAssertEqual(events.map(\.source), [.nightscout])

        // and a reconcile after them brings nothing back
        await f.reconcile(nil, at: at(1))
        events = try await f.events()
        XCTAssertEqual(events.count, 1)
    }

    // MARK: - Delivery

    /// No pump info, not onboarded, no pod or patch, a faulted or stopped one, External Insulin alone: no session. The
    /// first delivering heartbeat seeds one.
    func testNoSessionWithoutAPumpDelivering() async throws {
        let f = Fixture()
        f.notDelivering()
        await f.reconcile([bolus(at(-30), "4", external: true), bolus(at(-10), "2", external: true)], at: at(0))
        f.delivering(onboarded: false)
        await f.reconcile(nil, at: at(1))
        f.delivering("Omni", pod: nil)
        await f.reconcile(nil, at: at(2))
        f.delivering("Medtrum", pod: nil)
        await f.reconcile(nil, at: at(3))
        // a faulted pod, an occluded or expired patch: activated, but not delivering
        f.delivering("Omni", pod: at(-600), active: false)
        await f.reconcile(nil, at: at(3.5))
        f.delivering("Medtrum", pod: at(-600), active: false)
        await f.reconcile(nil, at: at(3.8))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions, [])
        let events = try await f.events()
        XCTAssertEqual(events.map(\.isExternal), [true, true])

        f.delivering("Omni", pod: at(-600))
        await f.reconcile(nil, at: at(4))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.plugin), ["Omni"])
        XCTAssertEqual(sessions.map(\.span), [DateInterval(start: at(4), duration: 0)])
    }

    // MARK: - Wipe

    func testWipeRestoresTheLast24hAtOnce() async throws {
        let f = Fixture()
        try await f.insertLoops(stride(from: -60.0, through: -5, by: 5).map { at($0) })
        f.delivering()
        await f.reconcile([bolus(at(-120), "1")] + temp(at(-30), rate: "1", minutes: "30.1"), at: at(0))
        // history from before the file, and a backfilled row
        try await f.insert([
            row(at(-3000), .bolus),
            PumpEventRecord(date: at(-4000), kind: .tempBasal, source: .nightscout, rate: 1, durationMin: 30)
        ])
        var events = try await f.events()
        XCTAssertEqual(events.count, 4)

        f.signals.clear()
        await f.store.wipe()

        // no publish needed
        events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-120), at(-30)])
        // the site seeded again from the loops since the list's oldest event
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.span), [DateInterval(start: at(-60).addingTimeInterval(20), end: at(0))])
        XCTAssertEqual(sessions.map(\.flags), [[.site, .seeded, .awaitingEvent]])
        XCTAssertEqual(f.signals.all.first, .all)
        XCTAssertEqual(f.signals.all.count, 2)
    }

    // MARK: - Retention

    /// The daily prune: events before the cutoff go, the schedule in effect at it stays, and the coverage rows of earlier
    /// builds (kind 9), whatever their date, go too: counted, idempotent. A later build's kind stays.
    func testPruneDeletesTheOldEventsAndTheOtherKindsAndKeepsTheScheduleInEffect() async throws {
        let f = Fixture()
        let cutoff = at(0).addingTimeInterval(-.days(120))
        let a = schedule([("00:00:00", 0, "0.5")])
        let b = schedule([("00:00:00", 0, "0.6")])
        let c = schedule([("00:00:00", 0, "0.7")])
        try await f.insert([
            row(cutoff.addingTimeInterval(-.hours(1)), .bolus),
            row(cutoff.addingTimeInterval(.hours(1)), .bolus),
            PumpEventRecord(date: cutoff.addingTimeInterval(-.days(2)), kind: .bolus, source: .nightscout, units: 1)
        ])
        // a long-lived live coverage row, a recent one, and a row of a later build's kind (a downgrade): kept
        try await f.insertOtherKind([cutoff.addingTimeInterval(-.days(200)), at(-60)])
        try await f.insertOtherKind([at(-30)], kind: 12)
        var count = try await f.rowCount()
        XCTAssertEqual(count, 6)
        try await f.insertSchedule(at: cutoff.addingTimeInterval(-.days(30)), a)
        try await f.insertSchedule(at: cutoff.addingTimeInterval(-.days(10)), b)
        try await f.insertSchedule(at: cutoff.addingTimeInterval(.days(5)), c)

        await f.reconcile([], at: at(0))

        var events = try await f.events()
        XCTAssertEqual(events.map(\.date), [cutoff.addingTimeInterval(.hours(1))])
        count = try await f.rowCount()
        XCTAssertEqual(count, 2)
        // the one in effect at the cutoff serves the oldest kept events
        let schedules = try await f.schedules()
        XCTAssertEqual(schedules.map(\.fingerprint), [fingerprint(b), fingerprint(c)])
        // the other kinds are read by nothing: only the days before the cutoff changed
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: cutoff.addingTimeInterval(-.days(1)), end: cutoff))])

        // counted, and idempotent
        try await f.insertOtherKind([at(-20)])
        var result = try await f.database.prune(cutoff: cutoff)
        XCTAssertEqual(result.otherKindsDeleted, 1)
        XCTAssertFalse(result.changed)
        result = try await f.database.prune(cutoff: cutoff)
        XCTAssertEqual(result, PumpEventStore.PruneResult())

        // once a day
        try await f.insert([row(cutoff.addingTimeInterval(-.hours(3)), .bolus)])
        await f.reconcile(nil, at: at(60))
        events = try await f.events()
        XCTAssertEqual(events.count, 2)
        await f.reconcile(nil, at: at(0).addingTimeInterval(.days(1)))
        events = try await f.events()
        XCTAssertEqual(events, [])
    }

    // MARK: - Basal schedule history

    func testScheduleHistory() async throws {
        let f = Fixture()
        let a = schedule([("00:00:00", 0, "0.5"), ("06:00:00", 360, "1.0")])
        let b = schedule([("00:00:00", 0, "0.5"), ("06:00:00", 360, "1.1")])

        // the subject's initial []
        await f.store.basalProfileChanged([])
        var schedules = try await f.schedules()
        XCTAssertEqual(schedules, [])

        // the first value seeds the history
        await f.store.basalProfileChanged(a)
        schedules = try await f.schedules()
        XCTAssertEqual(schedules, [ScheduleRow(
            date: at(0),
            source: BasalScheduleSource.local.rawValue,
            fingerprint: fingerprint(a)
        )])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(0), duration: 0))])

        // republished (an editor save without a change, a relaunch): nothing
        f.signals.clear()
        f.clock.now = at(30)
        await f.store.basalProfileChanged(schedule([("00:00", 0, "0.50"), ("06:00", 360, "1")]))
        f.relaunch()
        await f.store.basalProfileChanged(a)
        schedules = try await f.schedules()
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(f.signals.all, [])

        // an edit: one record at now, signalled from now on only
        f.clock.now = at(60)
        await f.store.basalProfileChanged(b)
        schedules = try await f.schedules()
        XCTAssertEqual(schedules.map(\.date), [at(0), at(60)])
        XCTAssertEqual(schedules.map(\.fingerprint), [fingerprint(a), fingerprint(b)])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(60), duration: 0))])

        // the wipe re-seeds from the current schedule
        f.coordinator.setBasalProfile(b)
        f.clock.now = at(90)
        f.signals.clear()
        await f.store.wipeSchedules()
        schedules = try await f.schedules()
        XCTAssertEqual(schedules.map(\.date), [at(90)])
        XCTAssertEqual(schedules.map(\.fingerprint), [fingerprint(b)])
        XCTAssertEqual(f.signals.all, [.all])
    }

    func testScheduleEqualToTheNewestRecordOfAnySourceIsNotRecorded() async throws {
        let f = Fixture()
        let a = schedule([("00:00:00", 0, "0.5")])
        try await f.insertSchedule(at: at(-600), a)
        await f.store.basalProfileChanged(a)
        let schedules = try await f.schedules()
        XCTAssertEqual(schedules.map(\.source), [BasalScheduleSource.nightscout.rawValue])
    }
}

// MARK: - Pump session rules

private typealias SessionRules = PumpSessionRules

/// A heartbeat or a change event, applied as the store does.
private enum SessionInput {
    case beat(PumpHeartbeat)
    case event(PumpLifecycleEvent, now: Date)
}

/// The pump session rules (pure): the change events, the heartbeats (gaps, closes, the fallback, the clamp), the seed,
/// the Nightscout sessions of both upload schemes, the prune and the gaps codec.
extension PumpEventStoreTests {
    private func h(_ hours: Double) -> Date {
        at(hours * 60)
    }

    private func sessionID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    private func medtrum(_ minutes: Double) -> PumpUnit {
        PumpUnit(plugin: "Medtrum", activation: at(minutes))
    }

    private func omni(_ minutes: Double) -> PumpUnit {
        PumpUnit(plugin: "Omni", activation: at(minutes))
    }

    private var dana: PumpUnit { PumpUnit(plugin: "Dana", activation: nil) }

    private func active(_ unit: PumpUnit, _ minutes: Double) -> SessionInput {
        .beat(PumpHeartbeat(state: .active(unit), now: at(minutes)))
    }

    private func actives(_ unit: PumpUnit, _ minutes: [Double]) -> [SessionInput] {
        minutes.map { active(unit, $0) }
    }

    private func inactive(_ plugin: String, _ minutes: Double) -> SessionInput {
        .beat(PumpHeartbeat(state: .inactive(plugin: plugin), now: at(minutes)))
    }

    private func unknown(_ minutes: Double) -> SessionInput {
        .beat(PumpHeartbeat(state: .unknown, now: at(minutes)))
    }

    private func lifecycle(_ plugin: String, _ component: PumpLifecycleEvent.Component, _ minutes: Double) -> PumpLifecycleEvent {
        PumpLifecycleEvent(plugin: plugin, component: component, date: at(minutes))
    }

    /// A change event dated `minutes`, received at `now` (by default at its date).
    private func change(
        _ plugin: String,
        _ component: PumpLifecycleEvent.Component,
        at minutes: Double,
        now: Double? = nil
    ) -> SessionInput {
        .event(lifecycle(plugin, component, minutes), now: at(now ?? minutes))
    }

    /// The pump sessions the inputs make, by start, each step applied as the store does (a seed without loops; new ids).
    private func run(_ inputs: [SessionInput], from start: [PumpSessionValue] = []) -> [PumpSessionValue] {
        var sessions = start
        func upsert(_ session: PumpSessionValue) {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.append(session)
            }
            sessions.sort { $0.start < $1.start }
        }
        for input in inputs {
            // unique across runs: a run goes on from another's sessions
            let id = UUID()
            switch input {
            case let .beat(heartbeat):
                let open = sessions.last { $0.end == nil }
                let newestEnd = sessions.last.map { $0.end ?? $0.lastSeen }
                switch SessionRules.step(open: open, newestEnd: newestEnd, heartbeat: heartbeat, newID: id) {
                case .none: break
                case let .close(session),
                     let .extend(session),
                     let .update(session):
                    upsert(session)
                case let .start(session, closing):
                    if let closing {
                        upsert(closing)
                    }
                    upsert(session)
                case let .seed(unit):
                    upsert(SessionRules.seed(unit, loops: [], now: heartbeat.now, newID: id))
                }
            case let .event(event, now):
                switch SessionRules.change(event, sessions: sessions, now: now, newID: id) {
                case .none: break
                case let .update(session):
                    upsert(session)
                case let .start(session, closing):
                    if let closing {
                        upsert(closing)
                    }
                    upsert(session)
                }
            }
        }
        return sessions
    }

    // MARK: Change events

    #if canImport(LoopKit)
        /// The pump managers' `.replaceComponent` events, by component; any other event is none.
        func testLifecycleEventFromThePumpEvent() {
            func event(_ type: PumpEventType?) -> NewPumpEvent {
                NewPumpEvent(date: at(5), dose: nil, raw: Data(), title: "", type: type)
            }
            XCTAssertEqual(
                PumpLifecycleEvent(event(.replaceComponent(componentType: .pump)), plugin: "Omni"),
                lifecycle("Omni", .pump, 5)
            )
            XCTAssertEqual(
                PumpLifecycleEvent(event(.replaceComponent(componentType: .infusionSet)), plugin: "Dana"),
                lifecycle("Dana", .infusionSet, 5)
            )
            XCTAssertEqual(
                PumpLifecycleEvent(event(.replaceComponent(componentType: .reservoir)), plugin: "Dana"),
                lifecycle("Dana", .reservoir, 5)
            )
            // the driver's title (the Site Change's notes); an empty one is none
            XCTAssertEqual(
                PumpLifecycleEvent(
                    NewPumpEvent(
                        date: at(5),
                        dose: nil,
                        raw: Data(),
                        title: "Patch replace",
                        type: .replaceComponent(componentType: .pump)
                    ),
                    plugin: "Medtrum"
                )?.title,
                "Patch replace"
            )
            XCTAssertNil(PumpLifecycleEvent(event(.replaceComponent(componentType: .pump)), plugin: "Omni")?.title)
            XCTAssertNil(PumpLifecycleEvent(event(.prime), plugin: "Minimed"))
            XCTAssertNil(PumpLifecycleEvent(event(.rewind), plugin: "Minimed"))
            XCTAssertNil(PumpLifecycleEvent(event(nil), plugin: "Minimed"))
        }
    #endif

    /// A `.pump` event starts a pod's or patch's session at its date, never partial (Omnipod's `activatedAt`, earlier by
    /// the setup, doesn't count; no heartbeat moves the activation); an `.infusionSet` event a tube pump's site
    /// session; `.reservoir` none. A pump clock ahead: clamped to now.
    func testEventStartsASession() {
        let pod = run([change("Omni", .pump, at: 10)] + actives(omni(-20), [12, 17]))
        XCTAssertEqual(pod.count, 1)
        XCTAssertEqual(pod[0].activation, at(10))
        XCTAssertEqual(pod[0].start, at(10))
        XCTAssertEqual(pod[0].localStart, at(10))
        XCTAssertEqual(pod[0].lastSeen, at(17))
        XCTAssertEqual(pod[0].source, .pump)
        XCTAssertEqual(pod[0].flags, [])
        XCTAssertNil(pod[0].end)
        XCTAssertFalse(pod[0].isPartial)

        let site = run([change("Dana", .infusionSet, at: 0)])
        XCTAssertEqual(site.map(\.flags), [[.site]])
        XCTAssertEqual(site.map(\.activation), [at(0)])

        XCTAssertEqual(SessionRules.change(lifecycle("Dana", .reservoir, 0), sessions: [], now: at(0)), .none)
        XCTAssertEqual(run([change("Dana", .infusionSet, at: 0), change("Dana", .reservoir, at: 30)]).count, 1)

        // a pump clock ahead: the start clamped to now, the activation the event's own date
        let ahead = run([change("Minimed", .infusionSet, at: 30, now: 20)])
        XCTAssertEqual(ahead[0].activation, at(30))
        XCTAssertEqual(ahead[0].start, at(20))
        XCTAssertEqual(ahead[0].lastSeen, at(20))
        // an infusion set of a pod or patch plugin: none
        XCTAssertEqual(SessionRules.change(lifecycle("Omni", .infusionSet, 0), sessions: [], now: at(0)), .none)
    }

    /// A pump clock ahead: the event's own date is the activation, so its re-sends (received 5, 10, 15 minutes later)
    /// are the same session, a pod's 2-minute window and a site's 15-minute one alike.
    func testEventResendsWithAPumpClockAhead() {
        for (plugin, component, ahead) in [("Omni", PumpLifecycleEvent.Component.pump, 10.0), ("Minimed", .infusionSet, 25)] {
            let result = run([0.0, 5, 10, 15].map { change(plugin, component, at: ahead, now: $0) })
            XCTAssertEqual(result.count, 1, plugin)
            XCTAssertEqual(result[0].activation, at(ahead), plugin)
            XCTAssertEqual(result[0].start, at(0), plugin)
        }
    }

    /// Re-sends carry the same date: the session of the same plugin and kind activated within 2 minutes is the
    /// event's (Minimed's 7 copies, heartbeats between them; Dana's components at one date). 3 minutes apart, another
    /// plugin, another kind: a new one.
    func testEventResends() {
        let minimed = PumpUnit(plugin: "Minimed", activation: nil)
        let copies = (1 ... 7).map { change("Minimed", .infusionSet, at: 0, now: Double($0) * 5) }
        XCTAssertEqual(run([change("Minimed", .infusionSet, at: 0, now: 1)] + copies).count, 1)
        let interleaved =
            run([change("Minimed", .infusionSet, at: 0, now: 1), active(minimed, 2)] + copies + [active(minimed, 40)])
        XCTAssertEqual(interleaved.count, 1)
        XCTAssertEqual(interleaved[0].lastSeen, at(40))

        // a pod or patch: 2 minutes
        XCTAssertEqual(run([change("Omni", .pump, at: 0), change("Omni", .pump, at: 1.5)]).count, 1)
        let apart = run([change("Omni", .pump, at: 0), change("Omni", .pump, at: 3)])
        XCTAssertEqual(apart.map(\.activation), [at(0), at(3)])
        XCTAssertEqual(apart[0].end, at(0))
        XCTAssertFalse(apart[0].flags.contains(.endApproximate))
        // a site: 15 minutes (Dana's cannula primed again 10 minutes later is one site)
        XCTAssertEqual(run([change("Dana", .infusionSet, at: 0), change("Dana", .infusionSet, at: 10)]).count, 1)
        XCTAssertEqual(run([change("Dana", .infusionSet, at: 0), change("Dana", .infusionSet, at: 16)]).count, 2)

        XCTAssertEqual(run([change("Dana", .infusionSet, at: 0), change("Dana", .reservoir, at: 0)]).count, 1)
        XCTAssertEqual(Set(run([change("Dana", .infusionSet, at: 0), change("Minimed", .infusionSet, at: 0)]).map(\.plugin)), [
            "Dana",
            "Minimed"
        ])
        XCTAssertEqual(run([change("Omni", .pump, at: 0), change("Omni", .infusionSet, at: 0)]).count, 1)
    }

    /// An event that came late (a tube pump's next history read, an app-dead stretch) splits the open session at its
    /// date: the part before it ends there exactly, the time after it (and its gaps) is the new session's. On time:
    /// the open session ends at its last heartbeat, approximate when that is more than the slack before the event.
    func testLateEventSplitsTheOpenSession() {
        let heartbeats = actives(
            dana,
            Array(stride(from: 0.0, through: 100, by: 10)) + Array(stride(from: 130.0, through: 300, by: 10))
        )
        let split = run(heartbeats + [change("Dana", .infusionSet, at: 120, now: 305)])
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].start, at(0))
        XCTAssertEqual(split[0].lastSeen, at(120))
        XCTAssertEqual(split[0].end, at(120))
        XCTAssertEqual(split[0].gaps, [DateInterval(start: at(100), end: at(120))])
        XCTAssertFalse(split[0].flags.contains(.endApproximate))
        XCTAssertEqual(split[1].activation, at(120))
        XCTAssertEqual(split[1].start, at(120))
        XCTAssertEqual(split[1].lastSeen, at(300))
        XCTAssertEqual(split[1].gaps, [DateInterval(start: at(120), end: at(130))])
        XCTAssertEqual(split[1].flags, [.site])
        XCTAssertNil(split[1].end)
        // its heartbeats go on in the new one
        XCTAssertEqual(run(actives(dana, [305]), from: split)[1].lastSeen, at(305))

        let onTime = run(actives(dana, [0, 10]) + [change("Dana", .infusionSet, at: 20)])
        XCTAssertEqual(onTime[0].end, at(10))
        XCTAssertFalse(onTime[0].flags.contains(.endApproximate))
        let after = run(actives(dana, [0, 10]) + [change("Dana", .infusionSet, at: 40)])
        XCTAssertEqual(after[0].end, at(10))
        XCTAssertTrue(after[0].flags.contains(.endApproximate))

        // nothing before it (an event at its start): the new session takes its row
        let row = run(actives(dana, [0, 10, 20]))
        let parts = SessionRules.split(row[0], at: at(0))
        XCTAssertNil(parts.before)
        XCTAssertEqual(SessionRules.split(row[0], at: at(-5)).before, nil)
        XCTAssertNotNil(SessionRules.split(row[0], at: at(5)).before)
    }

    /// A take keeps the event's own date as the activation: a tube pump's clock ahead by more than the 15 minutes,
    /// its re-sends after the take are the one site; a Dana cannula re-primed 14 minutes after the taken event too.
    func testTakeKeepsTheEventsDate() {
        let minimed = PumpUnit(plugin: "Minimed", activation: nil)
        let ahead = run([active(minimed, 0)] + [1.0, 5, 10, 20].map { change("Minimed", .infusionSet, at: 25, now: $0) })
        XCTAssertEqual(ahead.count, 1)
        XCTAssertEqual(ahead[0].activation, at(25))
        XCTAssertEqual(ahead[0].start, at(0))
        XCTAssertFalse(ahead[0].isPartial)
        XCTAssertFalse(ahead[0].flags.contains(.awaitingEvent))

        let reprimed = run([active(dana, 60), change("Dana", .infusionSet, at: 62), change("Dana", .infusionSet, at: 76)])
        XCTAssertEqual(reprimed.count, 1)
        XCTAssertEqual(reprimed[0].activation, at(62))
        XCTAssertEqual(reprimed[0].start, at(60))
    }

    /// The same plugin's late event splits at the new session's start: at the event, or (pushed past an older
    /// session's end) after it, the moved gaps clipped to the new session. A Medtrum patch's event while the old
    /// patch's session is still open and went on past the activation: split there. An event at the open session's
    /// start (nothing before it): the new session takes the row, its entered fields too.
    func testLateEventSplitPoint() {
        let patch = run(
            [change("Medtrum", .pump, at: 0)] + actives(medtrum(0), Array(stride(from: 10.0, through: 100, by: 10))) +
                [change("Medtrum", .pump, at: 80, now: 101)]
        )
        XCTAssertEqual(patch.map(\.start), [at(0), at(80)])
        XCTAssertEqual(patch[0].end, at(80))
        XCTAssertEqual(patch[0].lastSeen, at(80))
        XCTAssertEqual(patch[1].activation, at(80))
        XCTAssertEqual(patch[1].lastSeen, at(100))
        XCTAssertNil(patch[1].end)

        let base =
            run(actives(dana, Array(stride(from: 0.0, through: 120, by: 10)) + Array(stride(from: 180.0, through: 300, by: 10))))
        let nightscout = PumpSessionValue(
            id: sessionID(2),
            source: .nightscout,
            plugin: "Dana",
            activation: at(50),
            start: at(50),
            lastSeen: at(150),
            end: at(150),
            flags: [.site, .pluginAssumed]
        )
        let pushed = run([change("Dana", .infusionSet, at: 100, now: 301)], from: base + [nightscout])
            .filter { $0.source == .pump }
        XCTAssertEqual(pushed.map(\.start), [at(0), at(150)])
        XCTAssertEqual(pushed[0].end, at(150))
        XCTAssertEqual(pushed[0].gaps, [DateInterval(start: at(120), end: at(150))])
        XCTAssertEqual(pushed[1].activation, at(100))
        XCTAssertEqual(pushed[1].gaps, [DateInterval(start: at(150), end: at(180))])
        XCTAssertEqual(pushed[1].lastSeen, at(300))
        XCTAssertTrue(pushed[1].isPartial)

        var open = PumpSessionValue(
            id: sessionID(4),
            source: .pump,
            plugin: "Omni",
            activation: at(10),
            start: at(0),
            localStart: at(0),
            lastSeen: at(30),
            site: "arm"
        )
        open.gaps = [DateInterval(start: at(5), end: at(25))]
        var taken = open
        taken.activation = at(0)
        XCTAssertEqual(SessionRules.change(lifecycle("Omni", .pump, 0), sessions: [open], now: at(31)), .update(taken))
    }

    /// `changes`, one driver call's batch: a re-send and a take (the newest qualifying event taken, its copy and an
    /// older session's re-send nothing); a reservoir alone writes nothing; two plugins: the first closed by the second.
    func testChangesBatch() {
        let previous = PumpSessionValue(
            id: sessionID(1),
            source: .pump,
            plugin: "Medtrum",
            activation: at(-4000),
            start: at(-4000),
            lastSeen: at(0),
            end: at(0)
        )
        let fallback = run([active(medtrum(10), 60)], from: [previous])
        let written = SessionRules.changes(
            [lifecycle("Medtrum", .pump, 59), lifecycle("Medtrum", .pump, -4000), lifecycle("Medtrum", .pump, 59)],
            sessions: fallback,
            now: at(61)
        )
        XCTAssertEqual(written.map(\.id), [fallback[1].id])
        XCTAssertEqual(written.first?.activation, at(59))
        XCTAssertEqual(written.first?.start, at(59))
        XCTAssertEqual(written.first?.flags, [])

        XCTAssertEqual(SessionRules.changes([lifecycle("Dana", .reservoir, 0)], sessions: [], now: at(0)), [])

        let two = SessionRules.changes(
            [lifecycle("Dana", .infusionSet, 5), lifecycle("Omni", .pump, 0)],
            sessions: [],
            now: at(6)
        )
        XCTAssertEqual(two.map(\.plugin), ["Omni", "Dana"])
        XCTAssertEqual(two[0].end, at(0))
        XCTAssertFalse(two[0].flags.contains(.endApproximate))
        XCTAssertEqual(two[1].start, at(5))
        XCTAssertNil(two[1].end)
    }

    /// A late event of another plugin (or kind) doesn't split the other unit's session: that one delivered up to its
    /// last heartbeat and closes there, the new one starts there, its activation the event's (partial).
    func testLateEventOfAnotherPlugin() {
        for plugin in ["Medtrum", "Omni"] {
            let unit = PumpUnit(plugin: plugin, activation: at(-1))
            let result = run(
                [change(plugin, .pump, at: 0)] + actives(unit, Array(stride(from: 10.0, through: 100, by: 10))) +
                    [change("Dana", .infusionSet, at: 50, now: 101)]
            )
            XCTAssertEqual(result.count, 2, plugin)
            XCTAssertEqual(result[0].lastSeen, at(100), plugin)
            XCTAssertEqual(result[0].end, at(100), plugin)
            XCTAssertFalse(result[0].flags.contains(.endApproximate), plugin)
            XCTAssertEqual(result[1].plugin, "Dana", plugin)
            XCTAssertEqual(result[1].activation, at(50), plugin)
            XCTAssertEqual(result[1].start, at(100), plugin)
            XCTAssertEqual(result[1].flags, [.site], plugin)
            XCTAssertTrue(result[1].isPartial, plugin)
        }
    }

    /// The session a heartbeat started without an event (the fallback, the seed) takes the event that comes for it
    /// (started at most 2 minutes after it): its activation the event's, its start moved back to it (never before the
    /// previous session's end; the time to its old start a gap when longer than the slack). Later: a new session.
    func testEventTakesTheFallbackSession() {
        let previous = PumpSessionValue(
            id: sessionID(1),
            source: .pump,
            plugin: "Medtrum",
            activation: at(-4000),
            start: at(-4000),
            localStart: at(-4000),
            lastSeen: at(50),
            end: at(50)
        )
        let fallback = run([active(medtrum(55), 60)], from: [previous])
        XCTAssertEqual(fallback.count, 2)
        XCTAssertEqual(fallback[1].start, at(60))
        XCTAssertEqual(fallback[1].activation, at(55))
        XCTAssertEqual(fallback[1].flags, [.awaitingEvent])

        let taken = run([change("Medtrum", .pump, at: 57, now: 61)], from: fallback)
        XCTAssertEqual(taken.count, 2)
        XCTAssertEqual(taken[1].id, fallback[1].id)
        XCTAssertEqual(taken[1].activation, at(57))
        XCTAssertEqual(taken[1].start, at(57))
        // `prefixed` owns `[start, localStart)`: only the start moves
        XCTAssertEqual(taken[1].localStart, at(60))
        XCTAssertEqual(taken[1].flags, [])
        XCTAssertEqual(taken[1].gaps, [])
        // its re-send: nothing
        XCTAssertEqual(run([change("Medtrum", .pump, at: 57, now: 70)], from: taken), taken)

        let beforePrevious = run([change("Medtrum", .pump, at: 40, now: 61)], from: fallback)
        XCTAssertEqual(beforePrevious[1].start, at(50))
        XCTAssertEqual(beforePrevious[1].activation, at(40))

        let late = run([active(medtrum(10), 90), change("Medtrum", .pump, at: 55, now: 91)], from: [previous])
        XCTAssertEqual(late[1].start, at(55))
        XCTAssertEqual(late[1].gaps, [DateInterval(start: at(55), end: at(90))])

        // Medtrum's lost answer: the fallback started at the first delivering heartbeat. MedtrumKit's event, dated
        // at the real activation (its fix), is taken back to it; one dated when it started its session, just after the
        // heartbeat, is taken too (its date the activation, the start kept: not partial)
        let fixed = run([change("Medtrum", .pump, at: 55, now: 64)], from: fallback)
        XCTAssertEqual(fixed.count, 2)
        XCTAssertEqual(fixed[1].activation, at(55))
        XCTAssertEqual(fixed[1].start, at(55))
        let unfixed = run([change("Medtrum", .pump, at: 61, now: 64)], from: fallback)
        XCTAssertEqual(unfixed.count, 2)
        XCTAssertEqual(unfixed[1].activation, at(61))
        XCTAssertEqual(unfixed[1].start, at(60))
        XCTAssertFalse(unfixed[1].isPartial)
        // more than 2 minutes after its start: another change
        let next = run([change("Medtrum", .pump, at: 63, now: 64)], from: fallback)
        XCTAssertEqual(next.count, 3)
        XCTAssertEqual(next[1].end, at(60))
        XCTAssertEqual(next[2].start, at(63))
        // another plugin's event isn't its
        XCTAssertEqual(run([change("Omni", .pump, at: 59, now: 61)], from: fallback).count, 2)
    }

    /// A take moves the start back no further than the end of the newest older session of either source (an event
    /// dated inside a stored Nightscout session), a new session starts no earlier (but the first pump session); a seeded session takes its event; a
    /// closed one doesn't; of a batch, the newest event before the open session's start is taken; a newest session
    /// dated ahead is clamped first, so a real event isn't out of order.
    func testEventTakeBounds() {
        let nightscout = PumpSessionValue(
            id: sessionID(2),
            source: .nightscout,
            plugin: "Medtrum",
            activation: at(-300),
            start: at(-300),
            lastSeen: at(-200),
            end: at(-200)
        )
        let seeded = SessionRules.seed(medtrum(-260), loops: [], now: at(0), newID: sessionID(3))
        let inside = run([change("Medtrum", .pump, at: -250, now: 1)], from: [nightscout, seeded])
        XCTAssertEqual(inside.count, 2)
        XCTAssertEqual(inside[1].id, sessionID(3))
        XCTAssertEqual(inside[1].activation, at(-250))
        XCTAssertEqual(inside[1].start, at(-200))
        XCTAssertEqual(inside[1].localStart, at(0))
        XCTAssertEqual(inside[1].gaps, [DateInterval(start: at(-200), end: at(0))])
        // the first pump session starts at its event: no Nightscout session moves it (the store's tidy ends that one)
        let new = run([change("Omni", .pump, at: -250, now: 1)], from: [nightscout])
        XCTAssertEqual(new[1].start, at(-250))
        XCTAssertEqual(new[1].activation, at(-250))
        XCTAssertFalse(new[1].isPartial)

        // a tube pump's seed: a re-sent set change after the install
        let site = SessionRules.seed(PumpUnit(plugin: "Minimed", activation: nil), loops: [at(0), at(5)], now: at(10))
        let takeStep = SessionRules.change(lifecycle("Minimed", .infusionSet, -30), sessions: [site], now: at(11))
        var takenSite = site
        takenSite.activation = at(-30)
        takenSite.start = at(-30)
        takenSite.gaps = [DateInterval(start: at(-30), end: at(0))]
        takenSite.flags = [.site, .seeded]
        XCTAssertEqual(takeStep, .update(takenSite))

        // closed: refused
        var closed = run([active(medtrum(55), 60), active(medtrum(55), 70)])[0]
        closed.end = closed.lastSeen
        XCTAssertTrue(closed.flags.contains(.awaitingEvent))
        XCTAssertEqual(SessionRules.change(lifecycle("Medtrum", .pump, 59), sessions: [closed], now: at(80)), .none)

        // a batch of three older events: the newest is taken, the others are out of order
        let previous = PumpSessionValue(
            id: sessionID(1),
            source: .pump,
            plugin: "Medtrum",
            activation: at(-4000),
            start: at(-4000),
            lastSeen: at(0),
            end: at(0)
        )
        let fallback = run([active(medtrum(10), 60)], from: [previous])
        let written = SessionRules.changes(
            [20.0, 40, 30].map { lifecycle("Medtrum", .pump, $0) },
            sessions: fallback,
            now: at(61)
        )
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written.first?.id, fallback[1].id)
        XCTAssertEqual(written.first?.activation, at(40))
        XCTAssertEqual(written.first?.start, at(40))
        XCTAssertEqual(written.first?.gaps, [DateInterval(start: at(40), end: at(60))])

        // a newest session dated ahead (a clock set ahead, then corrected): clamped, the event starts the next one
        let ahead = run([change("Omni", .pump, at: 200)])
        let step = SessionRules.change(lifecycle("Medtrum", .pump, 30), sessions: ahead, now: at(30))
        guard case let .start(session, closing) = step else { return XCTFail("\(step)") }
        XCTAssertEqual(session.start, at(30))
        XCTAssertEqual(closing?.start, at(30))
        XCTAssertEqual(closing?.end, at(30))
    }

    /// An event older than the newest session's start is ignored (a pod's or patch's, out of order), unless it is a
    /// re-send of one.
    func testEventOutOfOrderIsIgnored() {
        let sessions = run([change("Omni", .pump, at: 100), active(omni(90), 105)])
        XCTAssertEqual(SessionRules.change(lifecycle("Omni", .pump, 50), sessions: sessions, now: at(106)), .none)
        XCTAssertEqual(SessionRules.change(lifecycle("Dana", .infusionSet, 99), sessions: sessions, now: at(106)), .none)
        var closed = sessions
        closed[0].end = closed[0].lastSeen
        XCTAssertEqual(SessionRules.change(lifecycle("Omni", .pump, 50), sessions: closed, now: at(106)), .none)
        // inside a closed session's span: the new one starts at its end
        let inside = run([change("Omni", .pump, at: 103, now: 106)], from: closed)
        XCTAssertEqual(inside.map(\.start), [at(100), at(105)])
        XCTAssertEqual(inside[1].activation, at(103))
    }

    // MARK: Heartbeats

    /// The heartbeat's state from the pump info: unknown without it or onboarding; inactive not delivering (or a pod
    /// or patch plugin without an activation); active with the unit.
    func testHeartbeatFromThePumpInfo() {
        let activated = at(-600)
        let now = at(0)
        XCTAssertEqual(PumpHeartbeat(info: nil, now: now).state, .unknown)
        XCTAssertEqual(PumpHeartbeat(info: Fixture.pumpInfo("Dana", onboarded: false), now: now).state, .unknown)
        XCTAssertEqual(PumpHeartbeat(info: Fixture.pumpInfo("Omni", pod: nil), now: now).state, .inactive(plugin: "Omni"))
        XCTAssertEqual(
            PumpHeartbeat(info: Fixture.pumpInfo("Medtrum", pod: nil, active: true), now: now).state,
            .inactive(plugin: "Medtrum")
        )
        XCTAssertEqual(
            PumpHeartbeat(info: Fixture.pumpInfo("Medtrum", pod: activated, active: false), now: now).state,
            .inactive(plugin: "Medtrum")
        )
        XCTAssertEqual(PumpHeartbeat(info: Fixture.pumpInfo("Dana"), now: now).state, .active(dana))
        XCTAssertEqual(
            PumpHeartbeat(info: Fixture.pumpInfo("Omni", pod: activated), now: now).state,
            .active(PumpUnit(plugin: "Omni", activation: activated))
        )
    }

    /// Without an open session: `unknown` and `inactive` do nothing; `active` seeds the first session, or starts one
    /// at the latest of now and the newest session's end (a clock set back: no overlap), awaiting its event, partial
    /// when late. A closed session passed as open is ignored.
    func testHeartbeatFallbackStart() throws {
        XCTAssertEqual(SessionRules.step(open: nil, newestEnd: nil, heartbeat: PumpHeartbeat(state: .unknown, now: at(0))), .none)
        XCTAssertEqual(
            SessionRules.step(open: nil, newestEnd: nil, heartbeat: PumpHeartbeat(state: .inactive(plugin: "Omni"), now: at(0))),
            .none
        )
        XCTAssertEqual(
            SessionRules.step(open: nil, newestEnd: nil, heartbeat: PumpHeartbeat(state: .active(medtrum(-60)), now: at(0))),
            .seed(medtrum(-60))
        )

        let closed =
            try XCTUnwrap(
                run([change("Medtrum", .pump, at: 0)] + actives(medtrum(0), [50, 100]) + [inactive("Medtrum", 105)])
                    .first
            )
        XCTAssertEqual(closed.end, at(100))
        for open in [nil, closed] {
            let step = SessionRules.step(
                open: open,
                newestEnd: closed.end,
                heartbeat: PumpHeartbeat(state: .active(medtrum(10)), now: at(90)),
                newID: sessionID(7)
            )
            guard case let .start(session, closing) = step else { return XCTFail("\(step)") }
            XCTAssertNil(closing)
            XCTAssertEqual(session.id, sessionID(7))
            XCTAssertEqual(session.start, at(100))
            XCTAssertEqual(session.lastSeen, at(100))
            XCTAssertEqual(session.activation, at(10))
            XCTAssertEqual(session.flags, [.awaitingEvent])
            XCTAssertTrue(session.isPartial)
        }
        let tube = run(actives(dana, [130]), from: [closed])
        XCTAssertEqual(tube[1].flags, [.site, .awaitingEvent])
        XCTAssertNil(tube[1].activation)
    }

    /// The open session closes on the first inactive heartbeat once its unit was seen delivering (not before: a pump
    /// info lagging the event), at its last heartbeat, approximate when that is more than the slack ago; `unknown`
    /// does nothing. Another plugin closes it too, an active one also starting a fallback.
    func testHeartbeatCloses() {
        let started = run([change("Omni", .pump, at: 0)])
        XCTAssertEqual(
            SessionRules.step(
                open: started[0],
                newestEnd: at(0),
                heartbeat: PumpHeartbeat(state: .inactive(plugin: "Omni"), now: at(1))
            ),
            .none
        )
        XCTAssertEqual(run([inactive("Omni", 1)], from: started), started)
        XCTAssertEqual(run([unknown(30)], from: started), started)
        // a unit that never delivers: after the slack, the inactive heartbeat closes it
        let never = run([inactive("Omni", 20)], from: started)
        XCTAssertEqual(never[0].end, at(0))
        XCTAssertEqual(never[0].flags, [.endApproximate])

        let worn = run([change("Omni", .pump, at: 0)] + actives(omni(-5), [5, 10]) + [inactive("Omni", 14)])
        XCTAssertEqual(worn.count, 1)
        XCTAssertEqual(worn[0].end, at(10))
        XCTAssertEqual(worn[0].flags, [])
        let late = run([change("Omni", .pump, at: 0)] + actives(omni(-5), [5, 10]) + [unknown(20), inactive("Omni", 40)])
        XCTAssertEqual(late[0].end, at(10))
        XCTAssertEqual(late[0].flags, [.endApproximate])
        // closed: a later inactive heartbeat does nothing, the next event starts the next one
        let next = run([inactive("Omni", 50), change("Omni", .pump, at: 60)], from: worn)
        XCTAssertEqual(next.map(\.activation), [at(0), at(60)])
        XCTAssertEqual(next[0].end, at(10))

        let switched = run([change("Omni", .pump, at: 0), active(omni(0), 5), active(dana, 8)])
        XCTAssertEqual(switched.count, 2)
        XCTAssertEqual(switched[0].end, at(5))
        XCTAssertEqual(switched[1].plugin, "Dana")
        XCTAssertEqual(switched[1].start, at(8))
        XCTAssertEqual(switched[1].flags, [.site, .awaitingEvent])
        let other = run([change("Omni", .pump, at: 0), active(omni(0), 5), inactive("Medtrum", 8)])
        XCTAssertEqual(other.count, 1)
        XCTAssertEqual(other[0].end, at(5))
    }

    /// More than the slack without a heartbeat is a gap, for every pump; 15 minutes isn't one. A stretch without a
    /// unit in between: the same rule.
    func testSessionGaps() {
        for unit in [dana, medtrum(-1)] {
            let result = run(actives(unit, [0, 10, 40, 50, 65]))
            XCTAssertEqual(result.count, 1, unit.plugin)
            XCTAssertEqual(result[0].gaps, [DateInterval(start: at(10), end: at(40))], unit.plugin)
            XCTAssertEqual(
                result[0].covered,
                [DateInterval(start: at(0), end: at(10)), DateInterval(start: at(40), end: at(65))],
                unit.plugin
            )
        }
        let unit = medtrum(-1)
        XCTAssertEqual(run(actives(unit, [0, 10]) + [unknown(12)] + actives(unit, [40]))[0].gaps, [
            DateInterval(start: at(10), end: at(40))
        ])
        XCTAssertEqual(run(actives(unit, [0, 10]) + [unknown(12)] + actives(unit, [20]))[0].gaps, [])
    }

    /// A clock set ahead, then corrected: every date of the open session past now + the slack goes to now (`start`,
    /// `localStart`, `lastSeen`; a closed one's `end` too), its gaps clipped (a short rest kept), its activation kept.
    /// A clamp that changes nothing writes nothing; ahead by less than the slack, it waits for the time to catch up.
    func testSessionClockClamp() throws {
        let ahead = run(actives(dana, [0, 10, 180, 185]))
        XCTAssertEqual(ahead[0].gaps, [DateInterval(start: at(10), end: at(180))])
        var clamped = ahead[0]
        clamped.lastSeen = at(15)
        clamped.gaps = [DateInterval(start: at(10), end: at(15))]
        XCTAssertEqual(SessionRules.clamp(ahead[0], now: at(15)), clamped)
        XCTAssertEqual(
            SessionRules.step(open: ahead[0], newestEnd: at(185), heartbeat: PumpHeartbeat(state: .active(dana), now: at(15))),
            .update(clamped)
        )
        XCTAssertEqual(run(actives(dana, [15, 20]), from: ahead)[0].lastSeen, at(20))

        var closed = ahead[0]
        closed.end = closed.lastSeen
        var clampedClosed = clamped
        clampedClosed.end = at(15)
        XCTAssertEqual(SessionRules.clamp(closed, now: at(15)), clampedClosed)

        // a start ahead: every date to now, the activation kept
        let patch = run([change("Omni", .pump, at: 180)] + actives(omni(170), [185]))
        var moved = patch[0]
        moved.start = at(15)
        moved.localStart = at(15)
        moved.lastSeen = at(15)
        XCTAssertEqual(SessionRules.clamp(patch[0], now: at(15)), moved)
        XCTAssertEqual(
            SessionRules.step(open: moved, newestEnd: at(15), heartbeat: PumpHeartbeat(state: .unknown, now: at(15))),
            .none
        )
        let goesOn = run([unknown(15)] + actives(omni(170), [20]), from: patch)
        XCTAssertEqual(goesOn.count, 1)
        XCTAssertEqual(goesOn[0].start, at(15))
        XCTAssertEqual(goesOn[0].lastSeen, at(20))
        XCTAssertEqual(goesOn[0].activation, at(180))

        // within the slack: left alone, and it waits
        let open = try XCTUnwrap(run(actives(dana, [0, 10, 20])).first)
        XCTAssertEqual(SessionRules.clamp(open, now: at(10)), open)
        XCTAssertEqual(
            SessionRules.step(open: open, newestEnd: at(20), heartbeat: PumpHeartbeat(state: .active(dana), now: at(10))),
            .none
        )
    }

    // MARK: Seed

    /// The first session from the successful loops at or after the activation: from the first one on, up to now; its
    /// gaps the stretches longer than the slack between them and to now (15 minutes isn't one). Without loops: at now
    /// (partial when late). It awaits its event.
    func testSessionSeed() {
        let loops = [at(-30), at(0), at(5), at(19.5), at(40), at(45), at(80), at(95)].shuffled()
        let pod = SessionRules.seed(medtrum(-10), loops: loops, now: at(90), newID: sessionID(1))
        XCTAssertEqual(pod.id, sessionID(1))
        XCTAssertEqual(pod.start, at(0))
        XCTAssertEqual(pod.localStart, at(0))
        XCTAssertEqual(pod.lastSeen, at(90))
        XCTAssertEqual(pod.activation, at(-10))
        XCTAssertEqual(pod.flags, [.seeded, .awaitingEvent])
        XCTAssertEqual(pod.gaps, [DateInterval(start: at(19.5), end: at(40)), DateInterval(start: at(45), end: at(80))])
        XCTAssertFalse(pod.isPartial)
        XCTAssertNil(pod.end)

        let tube = SessionRules.seed(dana, loops: loops, now: at(90))
        XCTAssertEqual(tube.start, at(-30))
        XCTAssertEqual(tube.flags, [.site, .seeded, .awaitingEvent])
        XCTAssertEqual(SessionRules.seed(dana, loops: [at(0), at(15)], now: at(30)).gaps, [])
        XCTAssertEqual(
            SessionRules.seed(medtrum(-10), loops: loops, now: at(120)).gaps.last,
            DateInterval(start: at(95), end: at(120))
        )

        // only loops before the activation: at now
        let bare = SessionRules.seed(medtrum(-10), loops: [at(-30), at(-20)], now: at(90))
        XCTAssertEqual(bare.start, at(90))
        XCTAssertEqual(bare.flags, [.awaitingEvent])
        XCTAssertTrue(bare.isPartial)
    }

    /// A Nightscout session of the same change (the plugin, its activation within 15 minutes of the unit's, or its span
    /// holding the unit's activation or the seed's start: Omnipod's Site Change at the setup's completion), whatever
    /// its end, is adopted through `prefixed`: its id, its earlier start and activation, the time from its last
    /// evidence to the seeded start a gap, its entered fields; open. Another change's, another plugin's, a tube pump's
    /// (no activation to match) isn't.
    func testSessionSeedAdoptsTheNightscoutSession() {
        let nightscout = PumpSessionValue(
            id: sessionID(5),
            source: .nightscout,
            plugin: "Medtrum",
            activation: at(-605),
            start: at(-605),
            lastSeen: at(-100),
            end: at(-100),
            flags: [.pluginAssumed, .endApproximate],
            site: "arm"
        )
        let loops = stride(from: -50.0, through: -5, by: 5).map { at($0) }
        let adopted = SessionRules.seed(medtrum(-600), loops: loops, now: at(0), adopting: nightscout, newID: sessionID(1))
        XCTAssertEqual(adopted.id, sessionID(5))
        XCTAssertEqual(adopted.source, .pump)
        XCTAssertEqual(adopted.start, at(-605))
        XCTAssertEqual(adopted.localStart, at(-50))
        XCTAssertEqual(adopted.activation, at(-605))
        XCTAssertNil(adopted.end)
        XCTAssertEqual(adopted.flags, [.seeded, .awaitingEvent])
        XCTAssertEqual(adopted.gaps, [DateInterval(start: at(-100), end: at(-50))])
        XCTAssertEqual(adopted.site, "arm")
        XCTAssertFalse(adopted.isPartial)

        // another change: activated after its span, the seed starting after it
        XCTAssertEqual(
            SessionRules.seed(medtrum(-60), loops: loops, now: at(0), adopting: nightscout, newID: sessionID(1)).id,
            sessionID(1)
        )
        // a previous unit's piece reaching past the new activation: not adopted (nor one 25 minutes before it)
        var older = nightscout
        older.activation = at(-2000)
        older.start = at(-2000)
        XCTAssertEqual(
            SessionRules.seed(medtrum(-600), loops: loops, now: at(0), adopting: older, newID: sessionID(1)).id,
            sessionID(1)
        )
        XCTAssertEqual(
            SessionRules.seed(medtrum(-580), loops: loops, now: at(0), adopting: nightscout, newID: sessionID(1)).id,
            sessionID(1)
        )
        // Omnipod: the Site Change (the change event) 30 minutes after `activatedAt`, the seed starting inside its span
        let pod = PumpSessionValue(
            id: sessionID(6),
            source: .nightscout,
            plugin: "Omni",
            activation: at(-570),
            start: at(-570),
            lastSeen: at(-40),
            end: at(-40),
            flags: [.pluginAssumed, .endApproximate]
        )
        let adoptedPod = SessionRules.seed(omni(-600), loops: loops, now: at(0), adopting: pod, newID: sessionID(1))
        XCTAssertEqual(adoptedPod.id, sessionID(6))
        XCTAssertEqual(adoptedPod.start, at(-570))
        XCTAssertEqual(adoptedPod.activation, at(-600))
        var omnipod = nightscout
        omnipod.plugin = "Omni"
        XCTAssertEqual(
            SessionRules.seed(medtrum(-600), loops: loops, now: at(0), adopting: omnipod, newID: sessionID(1)).id,
            sessionID(1)
        )
        var site = nightscout
        site.plugin = "Dana"
        let tube = SessionRules.seed(dana, loops: loops, now: at(0), adopting: site, newID: sessionID(1))
        XCTAssertEqual(tube.id, sessionID(1))
        XCTAssertEqual(tube.start, at(-50))
        XCTAssertNil(tube.site)
    }

    // MARK: Nightscout

    /// The Site Changes within 15 minutes of a cluster's first are one change, at the earliest; no chain. Both upload
    /// schemes: the old one's Medtrum pair (the phone's time, then the patch clock's 4 s earlier), Minimed's manual
    /// tube primes and fixed prime (a late insertion splits), Dana's repeated cannula prime; the new one's single Site
    /// Change per change event; the two schemes mixed; a hand-entered copy.
    func testNightscoutSiteChangesCluster() {
        XCTAssertEqual(
            SessionRules
                .activations(
                    [at(0).addingTimeInterval(4), at(0), at(10), at(16), h(100), h(100).addingTimeInterval(1)]
                        .shuffled()
                ),
            [at(0), at(16), h(100)]
        )
        XCTAssertEqual(SessionRules.activations([]), [])

        // old: pod age, Medtrum
        XCTAssertEqual(
            SessionRules.activations([h(0).addingTimeInterval(4), h(0), h(80).addingTimeInterval(4), h(80)]),
            [h(0), h(80)]
        )
        // old: primes, Minimed (manual, manual, manual, fixed), then one whose insertion came 20 minutes after the fill
        XCTAssertEqual(SessionRules.activations([at(0), at(1.5), at(3), at(8), h(72)]), [at(0), h(72)])
        XCTAssertEqual(SessionRules.activations([at(0), at(1.5), at(21)]), [at(0), at(21)])
        // old: primes, Dana (the cannula primed twice)
        XCTAssertEqual(SessionRules.activations([at(0), at(5)]), [at(0)])
        // new: one per change event
        XCTAssertEqual(SessionRules.activations([h(0), h(72), h(144)]), [h(0), h(72), h(144)])
        // both: the old pod-age pair and the new event's Site Change seconds later; a hand-entered copy
        XCTAssertEqual(
            SessionRules
                .activations([h(0), h(0).addingTimeInterval(4), h(0).addingTimeInterval(5), h(0).addingTimeInterval(600)]),
            [h(0)]
        )
    }

    /// A pod's or patch's window split at the activations: each piece covered by its evidence (an upload outage longer
    /// than the slack a gap), from its activation when the evidence starts within the slack of it (otherwise from the
    /// evidence: partial), to its last evidence or its first end alarm at or after its first evidence (a stray one
    /// before it ignored), with the reason. Never open. The plugin is the current pump's, assumed.
    func testNightscoutSessionsFromSiteChangesAndAlarms() {
        let siteChanges = [h(-200), h(-200).addingTimeInterval(4), h(-120), h(-40), h(10)]
        let evidence = [
            DateInterval(start: h(-300), end: h(-205)),
            DateInterval(start: h(-199.5), end: h(-150)),
            DateInterval(start: h(-146), end: h(-121)),
            DateInterval(start: h(-119.9), end: h(-42)),
            DateInterval(start: h(-39.9), end: h(-1))
        ]
        let alarms = [
            NightscoutAlarm(date: h(-119.95), reason: .occlusionOrFault),
            NightscoutAlarm(date: h(-44.9), reason: .occlusionOrFault),
            NightscoutAlarm(date: h(-45), reason: .ranEmpty)
        ]
        var ids = 0
        let result = SessionRules.nightscoutSessions(
            siteChanges: siteChanges,
            alarms: alarms,
            evidence: evidence,
            from: h(-240),
            to: h(0),
            currentPlugin: "Medtrum",
            existing: [],
            local: nil,
            makeID: { ids += 1
                return self.sessionID(ids) }
        )
        XCTAssertNil(result.prefixed)
        XCTAssertEqual(result.window, DateInterval(start: h(-240), end: h(0)))
        XCTAssertEqual(result.kept, [])
        let sessions = result.sessions
        XCTAssertEqual(sessions.map(\.activation), [nil, h(-200), h(-120), h(-40)])
        XCTAssertEqual(sessions.map(\.start), [h(-240), h(-199.5), h(-120), h(-40)])
        XCTAssertEqual(sessions.map(\.isPartial), [false, true, false, false])
        XCTAssertEqual(sessions.map(\.lastSeen), [h(-205), h(-121), h(-45), h(-1)])
        XCTAssertEqual(sessions.map(\.end), [h(-205), h(-121), h(-45), h(-1)])
        XCTAssertEqual(sessions.map(\.endReason), [nil, nil, .ranEmpty, nil])
        XCTAssertEqual(sessions[2].endReasonSource, .nightscout)
        XCTAssertEqual(sessions.map(\.flags), [
            [.pluginAssumed, .endApproximate],
            [.pluginAssumed, .endApproximate],
            [.pluginAssumed],
            [.pluginAssumed, .endApproximate]
        ])
        XCTAssertEqual(sessions.map(\.gaps), [[], [DateInterval(start: h(-150), end: h(-146))], [], []])
        XCTAssertEqual(Set(sessions.map(\.plugin)), ["Medtrum"])
        XCTAssertEqual(Set(sessions.map(\.source)), [.nightscout])
        XCTAssertEqual(sessions.map(\.localStart), [nil, nil, nil, nil])
        XCTAssertEqual(sessions.map(\.id), (1 ... 4).map { sessionID($0) })

        // nothing when the window is empty
        for (from, to) in [(h(0), h(0)), (h(0), h(-10))] {
            XCTAssertEqual(
                SessionRules.nightscoutSessions(
                    siteChanges: siteChanges,
                    alarms: alarms,
                    evidence: evidence,
                    from: from,
                    to: to,
                    currentPlugin: "Medtrum",
                    existing: [],
                    local: nil
                ),
                NightscoutSessions()
            )
        }
    }

    /// A tube pump's Site Changes are its site changes: the same cuts (sites, no maximum life), its alarms ending
    /// nothing; without a current pump the same cuts, without a plugin.
    func testNightscoutSessionsOfATubePump() {
        let siteChanges = [h(-200), h(-200).addingTimeInterval(180), h(-128), h(-60)]
        let evidence = [
            DateInterval(start: h(-240), end: h(-205)),
            DateInterval(start: h(-199.5), end: h(-150)),
            DateInterval(start: h(-146), end: h(-121)),
            DateInterval(start: h(-119.9), end: h(-42)),
            DateInterval(start: h(-39.9), end: h(-1))
        ]
        func run(_ plugin: String?) -> [PumpSessionValue] {
            SessionRules.nightscoutSessions(
                siteChanges: siteChanges,
                alarms: [NightscoutAlarm(date: h(-100), reason: .occlusionOrFault)],
                evidence: evidence,
                from: h(-240),
                to: h(0),
                currentPlugin: plugin,
                existing: [],
                local: nil
            ).sessions
        }
        let sites = run("Dana")
        XCTAssertEqual(sites.map(\.activation), [nil, h(-200), h(-128), h(-60)])
        XCTAssertEqual(sites.map(\.start), [h(-240), h(-199.5), h(-128), h(-60)])
        XCTAssertEqual(sites.map(\.lastSeen), [h(-205), h(-128), h(-60), h(-1)])
        XCTAssertEqual(sites.map(\.gaps), [
            [],
            [DateInterval(start: h(-150), end: h(-146))],
            [DateInterval(start: h(-121), end: h(-119.9))],
            [DateInterval(start: h(-42), end: h(-39.9))]
        ])
        XCTAssertEqual(Set(sites.map(\.flags)), [[.site, .pluginAssumed, .endApproximate]])
        XCTAssertEqual(Set(sites.map(\.endReason)), [nil])
        XCTAssertEqual(Set(sites.map(\.plugin)), ["Dana"])

        let none = run(nil)
        XCTAssertEqual(none.map(\.start), sites.map(\.start))
        XCTAssertEqual(Set(none.map(\.plugin)), [nil])
        XCTAssertEqual(Set(none.map(\.flags)), [[.endApproximate]])
    }

    /// A pod's or patch's piece is at most its plugin's longest life: Omnipod 80 h, Medtrum 120 h. Without an alarm,
    /// the rest is a piece without an activation; an alarm up to 12 h after it ends the activation's session, a later
    /// one is not its; after the alarm nothing is written up to the next activation, capped or not. A Medtrum patch
    /// worn 107 h to "Reservoir empty": one session, ended at the alarm.
    func testNightscoutSessionsMaximumLife() {
        let evidence = [
            DateInterval(start: h(-199), end: h(-150)),
            DateInterval(start: h(-110), end: h(-100)),
            DateInterval(start: h(-96), end: h(-90))
        ]
        func run(_ plugin: String, alarms: [NightscoutAlarm] = []) -> [PumpSessionValue] {
            SessionRules.nightscoutSessions(
                siteChanges: [h(-200)],
                alarms: alarms,
                evidence: evidence,
                from: h(-200),
                to: h(-80),
                currentPlugin: plugin,
                existing: [],
                local: nil
            ).sessions
        }

        let pods = run("Omni")
        XCTAssertEqual(pods.map(\.activation), [h(-200), nil])
        XCTAssertEqual(pods.map(\.start), [h(-199), h(-110)])
        XCTAssertEqual(pods.map(\.lastSeen), [h(-150), h(-90)])
        XCTAssertEqual(pods[1].gaps, [DateInterval(start: h(-100), end: h(-96))])
        XCTAssertEqual(pods.map(\.end), [h(-150), h(-90)])

        let alarmed = run("Omni", alarms: [NightscoutAlarm(date: h(-110), reason: .occlusionOrFault)])
        XCTAssertEqual(alarmed.map(\.activation), [h(-200)])
        XCTAssertEqual(alarmed[0].lastSeen, h(-120))
        XCTAssertEqual(alarmed[0].end, h(-110))
        XCTAssertEqual(alarmed[0].endReason, .occlusionOrFault)
        // after its maximum life: the time between unknown
        XCTAssertEqual(alarmed[0].flags, [.pluginAssumed, .endApproximate])

        let late = run("Omni", alarms: [NightscoutAlarm(date: h(-100), reason: .occlusionOrFault)])
        XCTAssertEqual(late.map(\.activation), [h(-200), nil])
        XCTAssertEqual(late[0].end, h(-150))
        XCTAssertEqual(late[0].flags, [.pluginAssumed, .endApproximate])
        XCTAssertEqual(late[1].start, h(-110))
        XCTAssertEqual(Set(late.map(\.endReason)), [nil])

        let early = run("Medtrum", alarms: [NightscoutAlarm(date: h(-160), reason: .ranEmpty)])
        XCTAssertEqual(early.map(\.activation), [h(-200)])
        XCTAssertEqual(early[0].lastSeen, h(-160))
        XCTAssertEqual(early[0].end, h(-160))
        XCTAssertEqual(early[0].endReason, .ranEmpty)

        let patch = run("Medtrum")
        XCTAssertEqual(patch.map(\.activation), [h(-200)])
        XCTAssertEqual(patch[0].lastSeen, h(-90))
        XCTAssertEqual(patch[0].gaps, [DateInterval(start: h(-150), end: h(-110)), DateInterval(start: h(-100), end: h(-96))])

        let worn = SessionRules.nightscoutSessions(
            siteChanges: [h(-110), h(-2.5)],
            alarms: [
                NightscoutAlarm(date: h(-3), reason: .ranEmpty),
                NightscoutAlarm(date: h(-3).addingTimeInterval(150), reason: .ranEmpty)
            ],
            evidence: [DateInterval(start: h(-109.9), end: h(-4))],
            from: h(-120),
            to: h(0),
            currentPlugin: "Medtrum",
            existing: [],
            local: nil
        ).sessions
        XCTAssertEqual(worn.map(\.activation), [h(-110)])
        XCTAssertEqual(worn[0].start, h(-110))
        XCTAssertEqual(worn[0].lastSeen, h(-3))
        XCTAssertEqual(worn[0].end, h(-3))
        XCTAssertEqual(worn[0].endReason, .ranEmpty)
        XCTAssertEqual(worn[0].flags, [.pluginAssumed])
        XCTAssertEqual(worn[0].gaps, [DateInterval(start: h(-4), end: h(-3))])
    }

    /// The oldest pump session's change is a cut too: its piece is that session's prefix (`[start, localStart)`
    /// rewritten, never stacked; the earlier activation taken; the time from the last evidence to the local start a
    /// gap; never before the retention's cutoff), evidence or not, also when the window starts inside its unit's life;
    /// of another change, a closed session. A re-run keeps the ids (an activation moved by minutes too) and the
    /// entered fields (the pump's and the user's over Nightscout's) and doubles nothing; a stored session matching the
    /// prefix gives the pump session its fields; unmatched ones with the user's are kept. A window starting inside a
    /// stored pod session starts at the next activation.
    func testNightscoutPrefixAndReRun() throws {
        let evidence = [
            DateInterval(start: h(-199), end: h(-121)),
            DateInterval(start: h(-119), end: h(-41)),
            DateInterval(start: h(-39), end: h(-10.5))
        ]
        let alarms = [NightscoutAlarm(date: h(-41.5), reason: .ranEmpty)]
        let local = SessionRules.seed(
            PumpUnit(plugin: "Medtrum", activation: h(-40).addingTimeInterval(4)),
            loops: [h(-10), h(-5)],
            now: h(0),
            newID: sessionID(50)
        )
        func run(
            existing: [PumpSessionValue],
            local: PumpSessionValue?,
            siteChanges: [Date]? = nil,
            evidence windowEvidence: [DateInterval]? = nil,
            from: Date? = nil,
            cutoff: Date? = nil
        ) -> NightscoutSessions {
            var ids = existing.count + 10
            return SessionRules.nightscoutSessions(
                siteChanges: siteChanges ?? [h(-200), h(-120), h(-40)],
                alarms: alarms,
                evidence: windowEvidence ?? evidence,
                from: from ?? h(-240),
                to: h(-10),
                currentPlugin: "Medtrum",
                existing: existing,
                local: local,
                cutoff: cutoff,
                makeID: { ids += 1
                    return self.sessionID(ids) }
            )
        }

        let first = run(existing: [], local: local)
        XCTAssertEqual(first.sessions.map(\.activation), [h(-200), h(-120)])
        let prefixed = try XCTUnwrap(first.prefixed)
        // its evidence starts an hour after the activation: from there
        XCTAssertEqual(prefixed.start, h(-39))
        XCTAssertEqual(prefixed.localStart, h(-10))
        XCTAssertEqual(prefixed.gaps, [DateInterval(start: h(-10.5), end: h(-10))] + local.gaps)
        XCTAssertEqual(prefixed.id, local.id)
        XCTAssertEqual(prefixed.activation, h(-40))
        XCTAssertEqual(prefixed.lastSeen, local.lastSeen)
        XCTAssertNil(prefixed.end)
        // recomputed, never stacked
        XCTAssertEqual(run(existing: first.sessions, local: prefixed).prefixed, prefixed)
        // without Nightscout's Site Change of it: its activation the cut, the same prefix
        let unlisted = run(existing: [], local: local, siteChanges: [h(-200), h(-120)])
        XCTAssertEqual(unlisted.prefixed?.start, h(-39))
        XCTAssertEqual(unlisted.sessions.map(\.activation), [h(-200), h(-120)])
        // without evidence of it: back to the activation, a gap up to the local start
        let bare = run(existing: [], local: local, evidence: Array(evidence.prefix(2)))
        XCTAssertEqual(bare.prefixed?.start, h(-40))
        XCTAssertEqual(bare.prefixed?.gaps.first, DateInterval(start: h(-40), end: h(-10)))
        // a window starting inside its unit's life: the first piece is the prefix
        let inside = run(existing: [], local: local, from: h(-30))
        XCTAssertEqual(inside.prefixed?.start, h(-30))
        XCTAssertEqual(inside.sessions, [])
        // never before the cutoff; the sessions before it dropped, one spanning it clipped
        let cut = run(existing: [], local: local, cutoff: h(-30))
        XCTAssertEqual(cut.prefixed?.start, h(-30))
        XCTAssertEqual(cut.sessions, [])
        XCTAssertEqual(run(existing: [], local: local, cutoff: h(-150)).sessions.map(\.start), [h(-150), h(-119)])

        // another change's pump session: the last piece is a closed session
        let other = run(existing: [], local: SessionRules.seed(medtrum(-10 * 60), loops: [h(-10)], now: h(0)))
        XCTAssertNil(other.prefixed)
        XCTAssertEqual(other.sessions.map(\.activation), [h(-200), h(-120), h(-40)])
        XCTAssertEqual(other.sessions.last?.end, h(-10.5))
        XCTAssertEqual(other.sessions.last?.flags, [.pluginAssumed, .endApproximate])

        // a re-run: the same sessions, their ids kept, also when an activation moved by minutes
        XCTAssertEqual(run(existing: first.sessions, local: local).sessions, first.sessions)
        var moved = first.sessions
        moved[0].activation = h(-200).addingTimeInterval(600)
        XCTAssertEqual(run(existing: moved, local: local).sessions.map(\.id), first.sessions.map(\.id))

        // the entered fields carry over: the pump's and the user's over Nightscout's, any over none
        var entered = first.sessions
        entered[0].site = "belly"
        entered[0].endReason = .expired
        entered[0].endReasonSource = .user
        entered[0].filledUnits = 180
        entered[0].fillSource = .user
        entered[1].endReason = .removedEarly
        entered[1].endReasonSource = .pump
        let again = run(existing: entered, local: local).sessions
        XCTAssertEqual(again.map(\.id), first.sessions.map(\.id))
        XCTAssertEqual(again[0].site, "belly")
        XCTAssertEqual(again[0].endReason, .expired)
        XCTAssertEqual(again[0].endReasonSource, .user)
        XCTAssertEqual(again[0].filledUnits, 180)
        XCTAssertEqual(again[1].endReason, .removedEarly)
        XCTAssertEqual(again[1].endReasonSource, .pump)
        XCTAssertEqual(again[1].end, h(-41.5))
        entered[1].endReasonSource = .nightscout
        XCTAssertEqual(run(existing: entered, local: local).sessions[1].endReason, .ranEmpty)

        // a stored session of the prefix's change gives the pump session its fields; unmatched ones with the user's
        // are kept, those without go
        func stored(_ number: Int, activation hours: Double) -> PumpSessionValue {
            PumpSessionValue(
                id: sessionID(number),
                source: .nightscout,
                plugin: "Medtrum",
                activation: h(hours),
                start: h(hours),
                lastSeen: h(hours + 1),
                end: h(hours + 1)
            )
        }
        var prefixStored = stored(30, activation: -40)
        prefixStored.site = "thigh"
        prefixStored.endReason = .removedEarly
        prefixStored.endReasonSource = .user
        var userStored = stored(31, activation: -160)
        userStored.site = "arm"
        let plainStored = stored(32, activation: -170)
        let withFields = run(existing: first.sessions + [prefixStored, userStored, plainStored], local: local)
        XCTAssertEqual(withFields.prefixed?.site, "thigh")
        XCTAssertEqual(withFields.prefixed?.endReason, .removedEarly)
        XCTAssertEqual(withFields.prefixed?.endReasonSource, .user)
        XCTAssertEqual(withFields.prefixed?.id, local.id)
        XCTAssertEqual(withFields.kept, [userStored])
        XCTAssertEqual(withFields.sessions, first.sessions)

        // a window starting inside a stored pod session ended by its alarm: from the next activation, nothing between
        var before = stored(33, activation: -250)
        before.lastSeen = h(-205)
        before.end = h(-205)
        let after = run(
            existing: [before],
            local: local,
            evidence: [DateInterval(start: h(-230), end: h(-201))] + evidence
        )
        XCTAssertEqual(after.window, DateInterval(start: h(-200), end: h(-10)))
        XCTAssertEqual(after.sessions.map(\.activation), [h(-200), h(-120)])
        XCTAssertEqual(after.kept, [])
    }

    // MARK: Prune, codec

    /// Sessions last seen before the cutoff go (an end after it doesn't keep one); one spanning it starts there,
    /// partial, its gaps clipped (a short rest kept).
    func testSessionPrune() {
        let cutoff = h(0)
        func session(_ number: Int, start: Double, lastSeen: Double, end: Double?) -> PumpSessionValue {
            PumpSessionValue(
                id: sessionID(number),
                source: .pump,
                plugin: "Dana",
                start: h(start),
                localStart: h(start),
                lastSeen: h(lastSeen),
                end: end.map { h($0) }
            )
        }
        var spanning = session(3, start: -10, lastSeen: 20, end: nil)
        spanning.gaps = [
            DateInterval(start: h(-5), end: h(-4)),
            DateInterval(start: h(-0.5), end: h(0.5)),
            DateInterval(start: h(5), end: h(6))
        ]
        var rest = session(5, start: -10, lastSeen: 20, end: 20)
        rest.gaps = [DateInterval(start: h(-1), end: at(5))]
        let result = SessionRules.prune([
            session(1, start: -100, lastSeen: -50, end: -50),
            session(2, start: -100, lastSeen: -1, end: nil),
            spanning,
            session(4, start: 1, lastSeen: 2, end: 2),
            rest,
            session(6, start: -100, lastSeen: -1, end: 5)
        ], cutoff: cutoff)
        XCTAssertEqual(result.deleted, [sessionID(1), sessionID(2), sessionID(6)])
        XCTAssertEqual(result.clipped.map(\.id), [sessionID(3), sessionID(5)])
        XCTAssertEqual(result.clipped[0].start, cutoff)
        XCTAssertEqual(result.clipped[0].localStart, cutoff)
        XCTAssertEqual(result.clipped[0].gaps, [DateInterval(start: h(0), end: h(0.5)), DateInterval(start: h(5), end: h(6))])
        XCTAssertEqual(result.clipped[1].gaps, [DateInterval(start: h(0), end: at(5))])
    }

    /// The gaps as stored round-trip (sub-second times too), read entry by entry: elements after the first two
    /// ignored, a bad entry (a boolean, a string, too short) dropping alone. Covered: the span without the gaps;
    /// partial: started more than the slack after the activation.
    func testSessionGapsCodecAndCoverage() {
        let gaps = [
            DateInterval(start: at(10).addingTimeInterval(0.123), end: at(40)),
            DateInterval(start: at(60), end: at(70).addingTimeInterval(0.5))
        ]
        XCTAssertEqual(PumpSessionValue.decodeGaps(PumpSessionValue.encodeGaps(gaps)), gaps)
        XCTAssertNil(PumpSessionValue.encodeGaps([]))
        XCTAssertEqual(PumpSessionValue.decodeGaps(nil), [])
        XCTAssertEqual(PumpSessionValue.decodeGaps("{"), [])
        XCTAssertEqual(PumpSessionValue.decodeGaps("{\"a\": 1}"), [])
        let reference = { (seconds: Double) in Date(timeIntervalSinceReferenceDate: seconds) }
        XCTAssertEqual(
            PumpSessionValue.decodeGaps(
                "[[3,4,1],[1,2],[5,4],[6],\"x\",[\"7\",8],[null,9],[true,2],[1,false],[7,8,0,\"later\"]]"
            ),
            [
                DateInterval(start: reference(1), end: reference(2)),
                DateInterval(start: reference(3), end: reference(4)),
                DateInterval(start: reference(7), end: reference(8))
            ]
        )

        var session = SessionRules.seed(medtrum(0), loops: [at(5)], now: at(5))
        session.lastSeen = at(100)
        session.gaps = gaps
        XCTAssertEqual(session.covered, [
            DateInterval(start: at(5), end: gaps[0].start),
            DateInterval(start: at(40), end: at(60)),
            DateInterval(start: gaps[1].end, end: at(100))
        ])
        XCTAssertFalse(session.isPartial)
        XCTAssertFalse(SessionRules.seed(medtrum(0), loops: [at(15)], now: at(100)).isPartial)
        XCTAssertTrue(SessionRules.seed(medtrum(0), loops: [at(15.1)], now: at(100)).isPartial)
        XCTAssertFalse(SessionRules.seed(dana, loops: [at(15.1)], now: at(100)).isPartial)
    }
}

// MARK: - Pump sessions in the store

/// The store's pump sessions: the change events, the heartbeat, the seed, the prune, the wipe; and the model edits'
/// migrations.
extension PumpEventStoreTests {
    private func pumpSession(
        _ id: Int,
        _ plugin: String,
        from start: Date,
        to end: Date?,
        lastSeen: Date? = nil,
        gaps: [DateInterval] = []
    ) -> PumpSessionValue {
        PumpSessionValue(
            id: sessionID(id),
            source: .pump,
            plugin: plugin,
            activation: start,
            start: start,
            localStart: start,
            lastSeen: lastSeen ?? end ?? start,
            end: end,
            gaps: gaps
        )
    }

    /// A change event before any heartbeat starts a session at its date (zero-length until a heartbeat comes), with the
    /// change signal; its re-sends change nothing and signal nothing; a reservoir is none. One log line per event.
    func testStoreChangeEventsStartSessions() async throws {
        let f = Fixture()
        await f.send([lifecycle("Medtrum", .pump, 0)], at: at(0))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.plugin, "Medtrum")
        XCTAssertEqual(sessions.first?.source, .pump)
        XCTAssertEqual(sessions.first?.activation, at(0))
        XCTAssertEqual(sessions.first?.span, DateInterval(start: at(0), duration: 0))
        XCTAssertEqual(sessions.first?.flags, [])
        XCTAssertNil(sessions.first?.end)
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(0), duration: 0))])

        f.signals.clear()
        await f.send([lifecycle("Medtrum", .pump, 0)], at: at(1))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(f.signals.all, [])

        let result = try await f.database.applyLifecycleEvents(
            [lifecycle("Medtrum", .pump, 0), lifecycle("Dana", .reservoir, 0)],
            now: at(2)
        )
        XCTAssertNil(result.changed)
        XCTAssertEqual(result.log.count, 2)
        XCTAssertTrue(result.log.contains { $0.hasSuffix("→ same (a re-send)") }, "\(result.log)")
        XCTAssertTrue(result.log.contains { $0.hasSuffix("→ none (a reservoir)") }, "\(result.log)")

        // a new patch: started, the open one closed at its last heartbeat (here its start)
        let next = try await f.database.applyLifecycleEvents([lifecycle("Medtrum", .pump, 30)], now: at(30))
        XCTAssertEqual(next.log.count, 2, "\(next.log)")
        XCTAssertTrue(next.log[0].contains("→ started at"), "\(next.log)")
        XCTAssertTrue(next.log[1].hasPrefix("Pump session: closed Medtrum session"), "\(next.log)")
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.activation), [at(0), at(30)])
        XCTAssertEqual(sessions.map(\.end), [at(0), nil])
    }

    /// Minimed re-sends its fixed prime's `.infusionSet` with every fetch (about 7 times, and after a relaunch): one site
    /// session, the copies in one batch and across batches.
    func testStoreMinimedResendsAreOneSite() async throws {
        let f = Fixture()
        let prime = lifecycle("Minimed", .infusionSet, -30)
        await f.send([prime, prime], at: at(-25))
        for minutes in stride(from: -20.0, through: 5, by: 5) {
            await f.send([prime], at: at(minutes))
        }
        f.relaunch()
        await f.send([prime], at: at(10))
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.activation), [at(-30)])
        XCTAssertEqual(sessions.first?.flags, [.site])
    }

    /// The heartbeats extend the event's session (a gap past the slack); the deactivation's inactive heartbeat closes it
    /// at its last delivering one, not approximate. The next pod's first heartbeat before its event starts one without
    /// it (a fallback); the event that comes after it is taken: its start moved back to the event.
    func testStoreHeartbeatsExtendAndCloseAndTheEventTakesTheFallback() async throws {
        let f = Fixture()
        await f.send([lifecycle("Omni", .pump, 0)], at: at(0))
        f.delivering("Omni", pod: at(-10))
        await f.reconcile([bolus(at(-10), "1")], at: at(5))
        await f.reconcile(nil, at: at(10))
        // the change signal is the time the heartbeat added, not the session's
        f.signals.clear()
        await f.reconcile(nil, at: at(40))
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(10), end: at(40)))])
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.span, DateInterval(start: at(0), end: at(40)))
        XCTAssertEqual(sessions.first?.gaps, [DateInterval(start: at(10), end: at(40))])
        XCTAssertEqual(sessions.first?.activation, at(0))
        XCTAssertNil(sessions.first?.end)

        f.delivering("Omni", pod: nil)
        f.signals.clear()
        await f.reconcile(nil, at: at(45))
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(40), duration: 0))])
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.first?.end, at(40))
        XCTAssertEqual(sessions.first?.flags, [])

        f.delivering("Omni", pod: at(50))
        await f.reconcile(nil, at: at(60))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.last?.start, at(60))
        XCTAssertEqual(sessions.last?.activation, at(50))
        XCTAssertEqual(sessions.last?.flags, [.awaitingEvent])

        f.signals.clear()
        await f.send([lifecycle("Omni", .pump, 59)], at: at(61))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.last?.activation, at(59))
        XCTAssertEqual(sessions.last?.start, at(59))
        XCTAssertEqual(sessions.last?.flags, [])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(59), end: at(60)))])

        // a re-send of it: nothing
        f.signals.clear()
        await f.send([lifecycle("Omni", .pump, 59)], at: at(62))
        let resent = try await f.sessions()
        XCTAssertEqual(resent, sessions)
        XCTAssertEqual(f.signals.all, [])
    }

    /// The first delivering heartbeat without any pump session seeds one from the successful loops: from the first at
    /// or after the latest of the activation and the oldest local dose row on, the gaps past the slack; once.
    func testStoreSeedsTheFirstSessionFromTheLoops() async throws {
        let f = Fixture()
        try await f.insertLoops(
            [at(-400)] + // before the activation
                stride(from: -180.0, through: -120, by: 5).map { at($0) } +
                stride(from: -60.0, through: -10, by: 5).map { at($0) }
        )
        try await f.insertLoops([at(-95), at(-90)], status: "Error: no pump")
        f.delivering("Medtrum", pod: at(-200))
        await f.reconcile([bolus(at(-300), "1")], at: at(0))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        let seeded = try XCTUnwrap(sessions.first)
        XCTAssertEqual(seeded.start, at(-180).addingTimeInterval(20))
        XCTAssertEqual(seeded.localStart, at(-180).addingTimeInterval(20))
        XCTAssertEqual(seeded.activation, at(-200))
        XCTAssertEqual(seeded.lastSeen, at(0))
        XCTAssertNil(seeded.end)
        XCTAssertEqual(seeded.flags, [.seeded, .awaitingEvent])
        XCTAssertEqual(seeded.gaps, [DateInterval(start: at(-120).addingTimeInterval(20), end: at(-60).addingTimeInterval(20))])

        // once: the next heartbeat extends it
        await f.reconcile(nil, at: at(5))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.lastSeen, at(5))

        // the oldest local dose row bounds it: no loops before the doses
        let g = Fixture()
        try await g.insertLoops(stride(from: -180.0, through: -10, by: 5).map { at($0) })
        g.delivering("Medtrum", pod: at(-200))
        await g.reconcile([bolus(at(-100), "1")], at: at(0))
        let bounded = try await g.sessions()
        XCTAssertEqual(bounded.map(\.start), [at(-100).addingTimeInterval(20)])
    }

    /// The daily prune: the sessions last seen before the cutoff go, one spanning it starts there (its activation kept:
    /// partial), its gaps clipped.
    func testStorePrunesTheSessions() async throws {
        let f = Fixture()
        let cutoff = at(0).addingTimeInterval(-.days(120))
        let old = pumpSession(
            1,
            "Medtrum",
            from: cutoff.addingTimeInterval(-.days(3)),
            to: cutoff.addingTimeInterval(-.hours(1))
        )
        let spanning = pumpSession(
            2,
            "Medtrum",
            from: cutoff.addingTimeInterval(-.days(5)),
            to: cutoff.addingTimeInterval(.days(2)),
            gaps: [DateInterval(start: cutoff.addingTimeInterval(-.hours(2)), end: cutoff.addingTimeInterval(.hours(1)))]
        )
        try await f.insert([old, spanning])
        await f.reconcile([], at: at(0))
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.id), [sessionID(2)])
        XCTAssertEqual(sessions.first?.start, cutoff)
        XCTAssertEqual(sessions.first?.localStart, cutoff)
        XCTAssertEqual(sessions.first?.activation, cutoff.addingTimeInterval(-.days(5)))
        XCTAssertEqual(sessions.first?.gaps, [DateInterval(start: cutoff, end: cutoff.addingTimeInterval(.hours(1)))])
        XCTAssertEqual(sessions.first?.isPartial, true)
        // from the clipped session's old start
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: cutoff.addingTimeInterval(-.days(5)), end: cutoff))])
    }

    /// The Settings wipe of `PumpEvent` clears the sessions too, entered fields included; the wipe's reconcile seeds the
    /// delivering unit's session again. Signalled as everything.
    func testStoreWipeClearsTheSessionsAndReseeds() async throws {
        let f = Fixture()
        var entered = pumpSession(1, "Medtrum", from: at(-3000), to: at(-2000))
        entered.site = "left arm"
        try await f.insert([entered])
        f.delivering("Medtrum", pod: at(-100))
        await f.reconcile([bolus(at(-120), "1")], at: at(0))
        var sessions = try await f.sessions()
        // a pump session exists: a fallback start, not a seed
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.last?.flags, [.awaitingEvent])

        try await f.insertLoops(stride(from: -60.0, through: -5, by: 5).map { at($0) })
        f.signals.clear()
        await f.store.wipe()
        XCTAssertEqual(f.signals.all.first, .all)
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.flags, [.seeded, .awaitingEvent])
        XCTAssertEqual(sessions.first?.start, at(-60).addingTimeInterval(20))
        XCTAssertNil(sessions.first?.site)
    }

    /// `start()` observes the change events; batches sent while a reconcile holds the serializer wait for it and are
    /// applied after it, in order (the second patch follows the first). The held reconcile (the pump history's initial
    /// empty list) seeds nothing: the seed waits for a list, so the first event starts the first session.
    func testStoreObservesTheChangeEventsBehindTheSerializer() async throws {
        let f = Fixture()
        let gated = GatedDatabase(f.database)
        f.use(gated)
        await gated.close()
        f.delivering("Medtrum", pod: at(-600))
        // the pump history's initial value: a reconcile, held
        await f.store.start()
        await gated.arrival()

        f.coordinator.sendPumpLifecycleEvents([lifecycle("Medtrum", .pump, 0)])
        f.coordinator.sendPumpLifecycleEvents([lifecycle("Medtrum", .pump, 30)])
        // the first batch is in the store, behind the held reconcile (the second waits in the observer's buffer)
        let store = f.store
        try await waitUntil { await store.queuedChangeBatches == 1 }
        let held = try await f.sessions()
        XCTAssertEqual(held, [])

        // received at 30 (the held reconcile read its time before)
        f.clock.now = at(30)
        await gated.open()
        await f.store.idle()
        try await waitUntil { try await f.sessions().count == 2 }
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.activation), [at(0), at(30)])
        XCTAssertEqual(sessions.map(\.start), [at(0), at(30)])
        XCTAssertEqual(sessions.first?.end, at(0))
        XCTAssertNil(sessions.last?.end)
        XCTAssertEqual(sessions.last?.flags, [])
    }

    // MARK: Migration

    /// An earlier model, built in code from the app's: the earlier models are in no bundle, as on the device (the
    /// store's own model cache is the source). C4's (HEAD 769baef33) has the coverage rows' attributes,
    /// `PumpEvent.end`/`eventID` and `BasalScheduleRecord.timeZone`/`uploader`, that model edit 2 dropped; the one before
    /// C2 (e2bcccbd9) has no `PumpSession` either. No subclass claimed: the app's classes stay the app model's (the
    /// other tests' contexts).
    private static func earlierModel(withSessions: Bool) throws -> NSManagedObjectModel {
        let current = CoreDataStack.shared.persistentContainer.managedObjectModel
        let model = try XCTUnwrap(current.copy() as? NSManagedObjectModel)
        if !withSessions {
            model.entities = model.entities.filter { $0.name != PumpEventStore.Entity.sessions }
        }
        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = true
            return attribute
        }
        let events = try XCTUnwrap(model.entitiesByName[PumpEventStore.Entity.events])
        events.properties += [attribute("end", .dateAttributeType), attribute("eventID", .stringAttributeType)]
        let schedules = try XCTUnwrap(model.entitiesByName[PumpEventStore.Entity.schedules])
        schedules.properties += [attribute("timeZone", .stringAttributeType), attribute("uploader", .stringAttributeType)]
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        return model
    }

    /// A store at the URL opened with the model as the app opens it: lightweight, the mapping inferred, in place.
    private static func openStore(_ model: NSManagedObjectModel, at url: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Core_Data", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        // the app's (NSPersistentContainer's default description)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw loadError
        }
        return container
    }

    private static func closeStore(_ container: NSPersistentContainer) throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    private static func objects(_ entity: String, in container: NSPersistentContainer) throws -> [NSManagedObject] {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: entity)
        fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return try container.viewContext.fetch(fetch)
    }

    private static func count(_ entity: String, in container: NSPersistentContainer) throws -> Int {
        try container.viewContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity))
    }

    private static func temporaryStore() throws -> (directory: URL, url: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("Core_Data.sqlite"))
    }

    /// The model's hashes against the pins: the earlier models built in code are C4's and e2bcccbd9's exactly, and model
    /// edit 2 changes `PumpEvent`'s and `BasalScheduleRecord`'s only (an accidental edit of another entity fails here).
    func testModelHashesArePinned() throws {
        let current = CoreDataStack.shared.persistentContainer.managedObjectModel
        let current64 = current.entityVersionHashesByName.mapValues { $0.base64EncodedString() }
        var expected = Self.c4EntityVersionHashes
        expected[PumpEventStore.Entity.events] = "qwM6RmQAhNA2zObJHUKQDni6AkZ17fR/dVnCmrKk6PE="
        expected[PumpEventStore.Entity.schedules] = "pdCC28pquStQiNl/Hlwi2jC52hyS+s4veydSnvQbZTw="
        XCTAssertEqual(current64, expected)
        XCTAssertEqual(
            Set(current.entitiesByName[PumpEventStore.Entity.events].map { Array($0.attributesByName.keys) } ?? []),
            ["date", "durationMin", "isExternal", "isMutable", "isSMB", "kind", "rate", "source", "units"]
        )
        XCTAssertEqual(current.entitiesByName[PumpEventStore.Entity.events]?.managedObjectClassName, "PumpEvent")
        XCTAssertEqual(
            try Self.earlierModel(withSessions: true).entityVersionHashesByName.mapValues { $0.base64EncodedString() },
            Self.c4EntityVersionHashes
        )
        XCTAssertEqual(
            try Self.earlierModel(withSessions: false).entityVersionHashesByName.mapValues { $0.base64EncodedString() },
            Self.c4EntityVersionHashes.filter { $0.key != PumpEventStore.Entity.sessions }
        )
    }

    /// Model edit 2 (the coverage rows' attributes dropped) on a store of C4's model, opened as the app opens it: every
    /// dose row and its values, the schedules, the sessions and the readings are kept, and so are the coverage rows
    /// (kind 9, without their `end`/`eventID` now), which no record maps; the next prune deletes them. A downgrade to
    /// C4's model and the upgrade again both work.
    func testModelEdit2MigratesAStoreOfTheC4ModelInPlace() throws {
        let current = CoreDataStack.shared.persistentContainer.managedObjectModel
        let c4 = try Self.earlierModel(withSessions: true)
        let (directory, url) = try Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let doses = [
            PumpEventRecord(date: at(-50), kind: .bolus, source: .pump, units: 1.5, durationMin: 0.4, isSMB: true),
            PumpEventRecord(
                date: at(-40),
                kind: .tempBasal,
                source: .pump,
                units: 0.16,
                rate: 0.8,
                durationMin: 12.4,
                isMutable: false
            ),
            PumpEventRecord(date: at(-30), kind: .tempBasal, source: .nightscout, units: -1, rate: 1.2, durationMin: 30),
            PumpEventRecord(date: at(-20), kind: .bolus, source: .pump, units: 2, isExternal: true),
            PumpEventRecord(date: at(-15), kind: .bolus, source: .pump, units: 0.3, isMutable: true),
            PumpEventRecord(date: at(-10), kind: .suspend, source: .pump),
            PumpEventRecord(date: at(-5), kind: .resume, source: .nightscout)
        ]
        // closed before the doses: none is in its local time, so the prune keeps them all
        var session = pumpSession(
            7,
            "Medtrum",
            from: at(-60),
            to: at(-52),
            gaps: [DateInterval(start: at(-58), end: at(-55).addingTimeInterval(0.25))]
        )
        session.flags = [.seeded, .endApproximate]
        session.filledUnits = 180
        session.fillSource = .pump
        session.site = "abdomen"

        // C4's store: the doses, the coverage rows (a unit's and a Nightscout one), schedules of both sources, a session
        // and readings
        let old = try Self.openStore(c4, at: url)
        let context = old.viewContext
        for dose in doses {
            let row = NSEntityDescription.insertNewObject(forEntityName: PumpEventStore.Entity.events, into: context)
            row.setValue(dose.date, forKey: "date")
            row.setValue(dose.kind.rawValue, forKey: "kind")
            row.setValue(dose.source.rawValue, forKey: "source")
            row.setValue(dose.units, forKey: "units")
            row.setValue(dose.rate, forKey: "rate")
            row.setValue(dose.durationMin, forKey: "durationMin")
            row.setValue(dose.isSMB, forKey: "isSMB")
            row.setValue(dose.isExternal, forKey: "isExternal")
            row.setValue(dose.isMutable, forKey: "isMutable")
            row.setValue("id \(dose.date.timeIntervalSince1970)", forKey: "eventID")
        }
        for (start, end, source, unit) in [
            (at(-60), at(0), PumpEventSource.pump, "Medtrum@1792447200" as String?),
            (at(-600), at(-300), PumpEventSource.nightscout, nil)
        ] {
            let row = NSEntityDescription.insertNewObject(forEntityName: PumpEventStore.Entity.events, into: context)
            row.setValue(start, forKey: "date")
            row.setValue(end, forKey: "end")
            row.setValue(Int16(9), forKey: "kind")
            row.setValue(source.rawValue, forKey: "source")
            row.setValue(unit, forKey: "eventID")
        }
        for (minutes, source, fingerprint) in [(-900.0, BasalScheduleSource.nightscout, "a"), (-100, .local, "b")] {
            let row = NSEntityDescription.insertNewObject(forEntityName: PumpEventStore.Entity.schedules, into: context)
            row.setValue(at(minutes), forKey: "date")
            row.setValue(source.rawValue, forKey: "source")
            row.setValue("[entries \(fingerprint)]", forKey: "entries")
            row.setValue(fingerprint, forKey: "fingerprint")
            row.setValue("Europe/Berlin", forKey: "timeZone")
            row.setValue(source == .nightscout ? "Profile Switch" : nil, forKey: "uploader")
        }
        let sessionRow = NSEntityDescription.insertNewObject(forEntityName: PumpEventStore.Entity.sessions, into: context)
        sessionRow.setValue(session.id, forKey: "id")
        sessionRow.setValue(session.source.rawValue, forKey: "source")
        sessionRow.setValue(session.plugin, forKey: "plugin")
        sessionRow.setValue(session.activation, forKey: "activation")
        sessionRow.setValue(session.start, forKey: "start")
        sessionRow.setValue(session.localStart, forKey: "localStart")
        sessionRow.setValue(session.lastSeen, forKey: "lastSeen")
        sessionRow.setValue(session.end, forKey: "end")
        sessionRow.setValue(PumpSessionValue.encodeGaps(session.gaps), forKey: "gaps")
        sessionRow.setValue(session.flags.rawValue, forKey: "flags")
        sessionRow.setValue(session.site, forKey: "site")
        sessionRow.setValue(NSNumber(value: 180), forKey: "filledUnits")
        sessionRow.setValue(session.fillSource.rawValue, forKey: "fillSource")
        for minutes in [0.0, 5] {
            let reading = NSEntityDescription.insertNewObject(forEntityName: "Readings", into: context)
            reading.setValue(at(minutes), forKey: "date")
            reading.setValue(Int16(120), forKey: "glucose")
        }
        try context.save()
        try Self.closeStore(old)

        /// The upgraded store's doses (records), coverage rows, schedules and session.
        func checkKept(
            in container: NSPersistentContainer,
            coverageRows: Int,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let fetch = NSFetchRequest<PumpEvent>(entityName: PumpEventStore.Entity.events)
            let rows = try container.viewContext.fetch(fetch)
            let records = rows.compactMap { CoreDataPumpEventDatabase.record(of: $0) }.sorted { $0.date < $1.date }
            XCTAssertEqual(records, doses, file: file, line: line)
            XCTAssertEqual(rows.filter { $0.kind == 9 }.count, coverageRows, file: file, line: line)
            let schedules = try Self.objects(PumpEventStore.Entity.schedules, in: container)
            XCTAssertEqual(
                schedules.compactMap { $0.value(forKey: "fingerprint") as? String },
                ["a", "b"],
                file: file,
                line: line
            )
            XCTAssertEqual(
                schedules.compactMap { $0.value(forKey: "date") as? Date },
                [at(-900), at(-100)],
                file: file,
                line: line
            )
            XCTAssertEqual(
                schedules.compactMap { ($0.value(forKey: "source") as? NSNumber)?.int16Value },
                [BasalScheduleSource.nightscout.rawValue, BasalScheduleSource.local.rawValue],
                file: file,
                line: line
            )
            XCTAssertEqual(schedules.compactMap { $0.value(forKey: "entries") as? String }, ["[entries a]", "[entries b]"])
            XCTAssertEqual(try CoreDataPumpEventDatabase.sessionRows(in: container.viewContext).map(\.value), [session])
            XCTAssertEqual(try Self.count("Readings", in: container), 2, file: file, line: line)
        }

        // upgrade: every row kept, the coverage rows read as no record
        let upgraded = try Self.openStore(current, at: url)
        try checkKept(in: upgraded, coverageRows: 2)
        XCTAssertNil(upgraded.managedObjectModel.entitiesByName[PumpEventStore.Entity.events]?.attributesByName["end"])
        try Self.closeStore(upgraded)

        // downgrade to C4's model: kept, the dropped columns come back empty
        let downgraded = try Self.openStore(c4, at: url)
        let events = try Self.objects(PumpEventStore.Entity.events, in: downgraded)
        XCTAssertEqual(events.count, doses.count + 2)
        XCTAssertTrue(events.allSatisfy { $0.value(forKey: "eventID") == nil && $0.value(forKey: "end") == nil })
        XCTAssertTrue(
            try Self.objects(PumpEventStore.Entity.schedules, in: downgraded).allSatisfy { $0.value(forKey: "timeZone") == nil }
        )
        XCTAssertEqual(try Self.count(PumpEventStore.Entity.sessions, in: downgraded), 1)
        try Self.closeStore(downgraded)

        // and up again; the next prune deletes the coverage rows (and only them: nothing is before its cutoff), once
        let again = try Self.openStore(current, at: url)
        try checkKept(in: again, coverageRows: 2)
        let cutoff = at(0).addingTimeInterval(-.days(120))
        let pruned = try CoreDataPumpEventDatabase.prune(cutoff: cutoff, in: again.viewContext, merge: { _ in })
        XCTAssertEqual(pruned, PumpEventStore.PruneResult(otherKindsDeleted: 2))
        again.viewContext.reset()
        try checkKept(in: again, coverageRows: 0)
        let repeated = try CoreDataPumpEventDatabase.prune(cutoff: cutoff, in: again.viewContext, merge: { _ in })
        XCTAssertEqual(repeated, PumpEventStore.PruneResult())
        try Self.closeStore(again)
    }

    /// Model edits 1 and 2 at once, on a store of the model before `PumpSession` (e2bcccbd9): the rows are kept (the
    /// coverage row too, until the prune), and `PumpSession` is there, empty, and round-trips a session. A downgrade
    /// drops it and keeps the rest; the upgrade again works.
    func testModelEditsMigrateAStoreOfTheModelBeforeTheSessionsInPlace() throws {
        let current = CoreDataStack.shared.persistentContainer.managedObjectModel
        let previous = try Self.earlierModel(withSessions: false)
        XCTAssertEqual(previous.entities.count, current.entities.count - 1)
        let (directory, url) = try Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // the previous model's store: doses, a coverage row, a schedule, and rows of entities sorting after PumpSession
        // (renumbered by the migration) and of a dosing one
        let old = try Self.openStore(previous, at: url)
        let context = old.viewContext
        for (minutes, units) in [(0.0, 1.5), (5, 0.25), (10, 2)] {
            let row = NSEntityDescription.insertNewObject(forEntityName: PumpEventStore.Entity.events, into: context)
            row.setValue(at(minutes), forKey: "date")
            row.setValue(PumpEventKind.bolus.rawValue, forKey: "kind")
            row.setValue(PumpEventSource.pump.rawValue, forKey: "source")
            row.setValue(units, forKey: "units")
        }
        let coverageRow = NSEntityDescription.insertNewObject(forEntityName: PumpEventStore.Entity.events, into: context)
        coverageRow.setValue(at(-60), forKey: "date")
        coverageRow.setValue(at(20), forKey: "end")
        coverageRow.setValue(Int16(9), forKey: "kind")
        coverageRow.setValue("Medtrum@1792447200", forKey: "eventID")
        let scheduleRow = NSEntityDescription.insertNewObject(forEntityName: PumpEventStore.Entity.schedules, into: context)
        scheduleRow.setValue(at(-600), forKey: "date")
        scheduleRow.setValue("fingerprint", forKey: "fingerprint")
        for minutes in [0.0, 5] {
            let reading = NSEntityDescription.insertNewObject(forEntityName: "Readings", into: context)
            reading.setValue(at(minutes), forKey: "date")
            reading.setValue(Int16(120), forKey: "glucose")
        }
        let overrideRow = NSEntityDescription.insertNewObject(forEntityName: "Override", into: context)
        overrideRow.setValue(at(-30), forKey: "date")
        overrideRow.setValue(true, forKey: "enabled")
        let tempTarget = NSEntityDescription.insertNewObject(forEntityName: "TempTargets", into: context)
        tempTarget.setValue(at(-20), forKey: "date")
        tempTarget.setValue("tt", forKey: "id")
        try context.save()
        try Self.closeStore(old)

        // upgrade
        let upgraded = try Self.openStore(current, at: url)
        let events = try Self.objects(PumpEventStore.Entity.events, in: upgraded)
        XCTAssertEqual(events.compactMap { $0.value(forKey: "date") as? Date }, [at(-60), at(0), at(5), at(10)])
        XCTAssertEqual(events.compactMap { ($0.value(forKey: "units") as? NSNumber)?.doubleValue }, [0, 1.5, 0.25, 2])
        XCTAssertEqual(events.compactMap { ($0.value(forKey: "kind") as? NSNumber)?.int16Value }, [9, 0, 0, 0])
        XCTAssertEqual(
            try Self.objects(PumpEventStore.Entity.schedules, in: upgraded).first?.value(forKey: "fingerprint") as? String,
            "fingerprint"
        )
        XCTAssertEqual(
            try Self.objects("Readings", in: upgraded).compactMap { $0.value(forKey: "date") as? Date },
            [at(0), at(5)]
        )
        XCTAssertEqual(try Self.objects("Override", in: upgraded).first?.value(forKey: "enabled") as? Bool, true)
        XCTAssertEqual(try Self.objects("TempTargets", in: upgraded).first?.value(forKey: "id") as? String, "tt")
        XCTAssertEqual(try Self.count(PumpEventStore.Entity.sessions, in: upgraded), 0)

        // a session round-trips through the new entity
        var session = pumpSession(
            7,
            "Medtrum",
            from: at(0),
            to: nil,
            lastSeen: at(90),
            gaps: [DateInterval(start: at(30), end: at(50).addingTimeInterval(0.25))]
        )
        session.flags = [.seeded, .awaitingEvent]
        session.filledUnits = 180
        session.fillSource = .pump
        session.endReason = .ranEmpty
        session.endReasonSource = .nightscout
        session.site = "abdomen"
        CoreDataPumpEventDatabase.apply(session, to: PumpSession(context: upgraded.viewContext))
        try upgraded.viewContext.save()
        upgraded.viewContext.reset()
        XCTAssertEqual(try CoreDataPumpEventDatabase.sessionRows(in: upgraded.viewContext).map(\.value), [session])
        try Self.closeStore(upgraded)

        // downgrade: the sessions' table goes, the rest stays
        let downgraded = try Self.openStore(previous, at: url)
        XCTAssertNil(downgraded.managedObjectModel.entitiesByName[PumpEventStore.Entity.sessions])
        XCTAssertEqual(try Self.count(PumpEventStore.Entity.events, in: downgraded), 4)
        XCTAssertEqual(try Self.count("Readings", in: downgraded), 2)
        try Self.closeStore(downgraded)

        // and up again: empty sessions, the rest kept
        let again = try Self.openStore(current, at: url)
        XCTAssertEqual(try Self.count(PumpEventStore.Entity.sessions, in: again), 0)
        XCTAssertEqual(try Self.count(PumpEventStore.Entity.events, in: again), 4)
        XCTAssertEqual(try Self.count("Override", in: again), 1)
        try Self.closeStore(again)
    }

    /// `entityVersionHashesByName` of C4's model (HEAD 769baef33, `momc` of Xcode 27.1 beta), base64. The model before
    /// `PumpSession` (e2bcccbd9) had the same ones but `PumpSession`'s.
    private static let c4EntityVersionHashes: [String: String] = [
        "ActiveProfile": "yRbM5h/OfxaSlH+E8Z0qiECjmoP1F59kaWm+pt6t6bo=",
        "Auto_ISF": "N9Ly86rEDT5TNU0gUL8XB2fhe0smvbAWD0Ee1exCn3A=",
        "BasalScheduleRecord": "B0Q2QLret6zzcYjynzopo2QP1hB41FNiJQ+xBYqB5yc=",
        "Fat": "T/dj51b6NfeXty5+74Jd/ajWuLA+kcREXZmC5ba1SoQ=",
        "Identifier": "XXk2q61+/gvUFw8E65vNY7+4pgousiR7O3W47I8gtbw=",
        "ImportError": "LeWuxCI+4m7CcLludqRrZ77MlH1cm4zxUoeBcyGSvRw=",
        "InsulinActivity": "BjQghUvlHo3Br5bad9V8sxOMN0qXFI82UlJQLGq94bw=",
        "InsulinConcentration": "nW5B1de2EbRkk6ImDVtkP+tthf4qpzrSxCThHnPX2Hk=",
        "InsulinDistribution": "eC1MZ07HWFPue2jDeg5dVYBNw0S/zuBAB0aYzosOfc8=",
        "LastLoop": "8qQXvRsTIrjCQGtIoWSkMoe3A4PgJrn+k0dOubjwHuo=",
        "LoopStatRecord": "W30LXpjkLAsP2PKdrDP4D6Q9xbFC9Ap8iVeKsF1XfjY=",
        "Meals": "p9YHvAUr7j462F58eZfDVNyNalUtZYMnu8sMJvMvdVI=",
        "Micronutrient": "/54jgrWsfYHZVl4bBC/LvlYcWzP4nXgF3cua3PObndM=",
        "NotUploaded": "6oYyRtkxa3C/N30OcfXJR8/w2+09bhGIxfyn4CzZSyQ=",
        "Onboarding": "s80O3aK9jzXLBbQ2M/2/An0FETqfxV0r8V0eeaKve8g=",
        "Override": "PfPEgHbwvwuvxscsN+y1daeywXY8ZitMk51RLbqFwjg=",
        "OverrideHistory": "jjwwFDoatUFy3/RVEkWewShm6e85daABC8KF23vuOd0=",
        "OverridePresets": "FeioxxXwRdd/fyWcX5nOv5TdzGpFgrUSG0c7zgdpbfw=",
        "PresetMicronutrient": "lnzgtbFXdcnNwqQd3ZO/WCRoOip9ftikA4BNN5Jixik=",
        "Presets": "92xA1s3F9g45Aauhsw+JzVdPy7cTNTSHwXBvt0u82lE=",
        "Profiles": "WqA5lL3TIVgt7AEThOIRbDxKOHbifSzTPlXKfC1W0g8=",
        "Protein": "k+dKGnY1otmjqAONBhMYZMx8UbO+rbIJ4y9KBGYUigk=",
        "Pump": "W3cYpQo+ofdVJwt0i+ZmrsGkbaEgNaXY2k6mBY3TXoA=",
        "PumpEvent": "Wlm2nRMYpqC6uIxEaOOkzNWQsqnOvBurwwgVWBoPHqw=",
        "PumpSession": "7M27p58QQuOPd5vge6kDgU7GEG5S36h5qEZCstQgG1U=",
        "Readings": "V6cEar1AfwAST9jaMjc2l83Vr7mc8O8RDocCALF6+Nc=",
        "Reasons": "X1+TlVOGWcT++HsTL1E8OcU8Zne6drspfigakMvbzmw=",
        "StatsData": "wqNilJSgwprmDceFmWITWleeLkJFn8Ff2Nj0WwoGuys=",
        "TDD": "knlrdZLR7XSZqYtB63PHzwXvtZSaJQ1v3Eg2viNsWmQ=",
        "TempTargets": "pjrtOauV9egcIwW6T47nmFPZrJYO2WAHgna3Bp24dsw=",
        "TempTargetsSlider": "PMAHi6cgx7B56MvF8881Lhp+N8D2evvYkM/lupWAsaQ=",
        "UXSettings": "ESR2D8XL/NUl3pDD+0w6gzDFZRotwv+4YNwO1y/h1K4=",
        "VNr": "xR7bjKI5TeIdG3pJj4OMgES8mBWx5Ns5rA34ZjgB56I="
    ]

    // MARK: Store paths

    /// A backfill before the seed (`wipeSessions`, then an import): the reconcile that seeds deletes the Nightscout dose
    /// row inside the seeded local time (older than the file's 24 h); one before the pump's dose rows stays.
    func testStoreSeedRemovesTheNightscoutRowsInsideItsLocalTime() async throws {
        let f = Fixture()
        let gated = GatedDatabase(f.database)
        f.use(gated)
        try await f.insertLoops(stride(from: -2400.0, through: -5, by: 5).map { at($0) })
        try await f.insert([row(at(-2450), .bolus)])
        try await f.insert([
            PumpEventRecord(date: at(-2000), kind: .bolus, source: .nightscout, units: 2),
            PumpEventRecord(date: at(-3000), kind: .bolus, source: .nightscout, units: 3)
        ])
        f.delivering("Medtrum", pod: at(-2420))
        await f.reconcile([bolus(at(-100), "1")], at: at(0))

        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.start), [at(-2400).addingTimeInterval(20)])
        let results = await gated.results
        XCTAssertEqual(results.map(\.nightscoutRemoved), [1])
        let nightscout = try await f.events().filter { $0.source == .nightscout }
        XCTAssertEqual(nightscout.map(\.date), [at(-3000)])
    }

    /// A change event starting the first session deletes the Nightscout dose rows in the time it touched (its instant:
    /// the session is zero-length until a heartbeat), with a log line; the rows a second off it stay (no local time).
    func testStoreChangeEventRemovesTheNightscoutRowsItMakesLocal() async throws {
        let f = Fixture()
        try await f.insert([at(-100), at(-100).addingTimeInterval(-1), at(-100).addingTimeInterval(1)].map { date in
            PumpEventRecord(date: date, kind: .bolus, source: .nightscout, units: 1)
        })
        let result = try await f.database.applyLifecycleEvents([lifecycle("Medtrum", .pump, -100)], now: at(0))
        XCTAssertTrue(result.log.contains("Pump session: 1 Nightscout dose rows inside the pump's local time deleted"))
        let changed = try XCTUnwrap(result.changed)
        XCTAssertTrue(changed.start <= at(-100) && at(-100) <= changed.end)
        let nightscout = try await f.events().filter { $0.source == .nightscout }
        XCTAssertEqual(nightscout.map(\.date), [at(-100).addingTimeInterval(-1), at(-100).addingTimeInterval(1)])
    }

    /// Step 4 with the knowledge failing (its session read): the file's time still goes (a Nightscout row inside the
    /// list's 24 h); one before it stays.
    func testStoreStepFourFallsBackToTheFilesTime() async throws {
        let f = Fixture()
        f.use(CoreDataPumpEventDatabase(
            container: f.container,
            mergeBatchDelete: { _ in },
            reconcileKnowledge: { _, _, _ in throw SessionReadFailure() }
        ))
        try await f.insert([
            PumpEventRecord(date: at(-30), kind: .bolus, source: .nightscout, units: 1),
            PumpEventRecord(date: at(-2000), kind: .bolus, source: .nightscout, units: 2)
        ])
        await f.reconcile([bolus(at(-60), "1")], at: at(0))
        let nightscout = try await f.events().filter { $0.source == .nightscout }
        XCTAssertEqual(nightscout.map(\.date), [at(-2000)])
    }

    /// The prune's removal of stale Nightscout rows (here one in a session's gap) signals their time, up to the next
    /// event that ends a temp (none: now).
    func testStorePruneSignalsTheNightscoutRowsItRemoves() async throws {
        let f = Fixture()
        try await f.insert([pumpSession(
            1,
            "Medtrum",
            from: at(-300),
            to: at(-100),
            gaps: [DateInterval(start: at(-250), end: at(-200))]
        )])
        try await f.insert([PumpEventRecord(date: at(-225), kind: .bolus, source: .nightscout, units: 1)])
        await f.reconcile([], at: at(0))
        let events = try await f.events()
        XCTAssertEqual(events, [])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(-225), end: at(0)))])
    }

    /// A failing session heartbeat (its `PumpSession` or `LoopStatRecord` read) is logged: the doses are mirrored all
    /// the same; the next reconcile that can read seeds.
    func testStoreSessionFailureStillMirrorsTheDoses() async throws {
        let f = Fixture()
        f.use(CoreDataPumpEventDatabase(
            container: f.container,
            mergeBatchDelete: { _ in },
            sessionHeartbeat: { _, _, _ in throw SessionReadFailure() }
        ))
        f.delivering()
        await f.reconcile([bolus(at(-10), "1")], at: at(0))
        await f.reconcile(nil, at: at(5))
        let events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-10)])
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions, [])

        f.use(f.database)
        await f.reconcile(nil, at: at(10))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
    }

    /// The seed waits for the list: an empty list at the first delivering heartbeat (a fresh
    /// install, a wipe with an empty 24 h file) seeds nothing; the list's first value seeds, bounded by its doses.
    func testStoreSeedWaitsForTheList() async throws {
        let f = Fixture()
        try await f.insertLoops(stride(from: -180.0, through: -10, by: 5).map { at($0) })
        f.delivering("Medtrum", pod: at(-200))
        await f.reconcile([], at: at(0))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions, [])

        await f.reconcile([bolus(at(-100), "1")], at: at(1))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.start), [at(-100).addingTimeInterval(20)])
        XCTAssertEqual(sessions.first?.flags, [.seeded, .awaitingEvent])
    }

    /// The Settings wipe of `PumpSession`: the sessions only (entered fields too), then reseeded; the events stay.
    func testStoreSessionsWipeKeepsTheEvents() async throws {
        let f = Fixture()
        try await f.insertLoops(stride(from: -60.0, through: -5, by: 5).map { at($0) })
        var entered = pumpSession(1, "Medtrum", from: at(-3000), to: at(-2000))
        entered.site = "left arm"
        try await f.insert([entered])
        f.delivering("Medtrum", pod: at(-100))
        await f.reconcile([bolus(at(-120), "1")], at: at(0))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 2)

        f.signals.clear()
        await f.store.wipeSessions()
        XCTAssertEqual(f.signals.all.first, .all)
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.flags, [.seeded, .awaitingEvent])
        XCTAssertEqual(sessions.first?.start, at(-60).addingTimeInterval(20))
        let events = try await f.events()
        XCTAssertEqual(events.map(\.date), [at(-120)])
    }

    /// A clock set ahead, then corrected: the open session is clamped to now (its gap clipped) and goes on; set back by
    /// less than the slack it waits. A closed newest session dated ahead is clamped too, so a fallback start isn't
    /// pushed into the future.
    func testStoreClockAheadAndBackClampsTheSessions() async throws {
        let f = Fixture()
        f.delivering()
        await f.reconcile([bolus(at(-10), "1")], at: at(0))
        await f.reconcile(nil, at: at(5))
        await f.reconcile(nil, at: at(180))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.first?.lastSeen, at(180))
        XCTAssertEqual(sessions.first?.gaps, [DateInterval(start: at(5), end: at(180))])

        await f.reconcile(nil, at: at(10))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.first?.lastSeen, at(10))
        XCTAssertEqual(sessions.first?.gaps, [DateInterval(start: at(5), end: at(10))])
        await f.reconcile(nil, at: at(15))
        await f.reconcile(nil, at: at(12))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.lastSeen, at(15))
        XCTAssertNil(sessions.first?.end)

        let g = Fixture()
        try await g.insert([pumpSession(1, "Medtrum", from: at(-60), to: at(200))])
        g.delivering("Medtrum", pod: nil)
        await g.reconcile([bolus(at(-10), "1")], at: at(0))
        sessions = try await g.sessions()
        XCTAssertEqual(sessions.first?.end, at(0))
        XCTAssertEqual(sessions.first?.lastSeen, at(0))
        g.delivering("Medtrum", pod: at(5))
        await g.reconcile(nil, at: at(10))
        sessions = try await g.sessions()
        XCTAssertEqual(sessions.map(\.start), [at(-60), at(10)])
    }

    /// Omnipod sends the event before `pumpManagerDidUpdateState`: an inactive pump info within the slack after it
    /// closes nothing; the first delivering heartbeat extends the event's session.
    func testStoreOmnipodLaggingInactiveClosesNothing() async throws {
        let f = Fixture()
        f.delivering("Omni", pod: nil)
        await f.reconcile([bolus(at(-10), "1")], at: at(-5))
        await f.send([lifecycle("Omni", .pump, 0)], at: at(0))
        await f.reconcile(nil, at: at(2))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions.first?.end)
        XCTAssertEqual(sessions.first?.lastSeen, at(0))

        f.delivering("Omni", pod: at(-8))
        await f.reconcile(nil, at: at(5))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.first?.lastSeen, at(5))
        XCTAssertEqual(sessions.first?.activation, at(0))
        XCTAssertNil(sessions.first?.end)
    }

    /// A patch's session from its event, to its last delivering heartbeat.
    private func medtrumPatch(_ f: Fixture) async {
        f.delivering("Medtrum", pod: at(0))
        await f.send([lifecycle("Medtrum", .pump, 0)], at: at(0))
        await f.reconcile([bolus(at(-10), "1")], at: at(5))
        await f.reconcile(nil, at: at(10))
        // emptied or expired: inactive, closed at its last delivering heartbeat
        f.delivering("Medtrum", pod: at(0), active: false)
        await f.reconcile(nil, at: at(12))
    }

    /// Medtrum's normal order: the old patch's inactive close, the new one's event, a pump info still the old patch's
    /// (nothing), then delivering; the patch clock's activation seconds later starts nothing.
    func testStoreMedtrumNormalPatchChange() async throws {
        let f = Fixture()
        await medtrumPatch(f)
        await f.send([lifecycle("Medtrum", .pump, 20)], at: at(20))
        await f.reconcile(nil, at: at(21))
        f.delivering("Medtrum", pod: at(20))
        await f.reconcile(nil, at: at(25))
        f.delivering("Medtrum", pod: at(20).addingTimeInterval(-4))
        await f.reconcile(nil, at: at(30))
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.end, at(10))
        XCTAssertEqual(sessions.first?.flags, [])
        XCTAssertEqual(sessions.last?.activation, at(20))
        XCTAssertEqual(sessions.last?.start, at(20))
        XCTAssertEqual(sessions.last?.lastSeen, at(30))
        XCTAssertNil(sessions.last?.end)
        XCTAssertEqual(sessions.last?.flags, [])
    }

    /// Medtrum's lost-answer order: the new patch's heartbeat starts a fallback first; its event, dated at the real
    /// activation (before the fallback's start and the old patch's end), is taken, the start bounded by that end.
    func testStoreMedtrumLostAnswerEventIsBoundedByTheOldEnd() async throws {
        let f = Fixture()
        await medtrumPatch(f)
        f.delivering("Medtrum", pod: at(14))
        await f.reconcile(nil, at: at(20))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.last?.flags, [.awaitingEvent])
        XCTAssertEqual(sessions.last?.start, at(20))

        await f.send([lifecycle("Medtrum", .pump, 8)], at: at(21))
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.end, at(10))
        XCTAssertEqual(sessions.last?.activation, at(8))
        XCTAssertEqual(sessions.last?.start, at(10))
        XCTAssertEqual(sessions.last?.flags, [])
    }

    /// A lost `.pump` event: the inactive close, then the new patch's first delivering heartbeat starts a late,
    /// partial session that awaits its event.
    func testStoreLostPumpEventFallsBack() async throws {
        let f = Fixture()
        await medtrumPatch(f)
        f.delivering("Medtrum", pod: at(14))
        await f.reconcile(nil, at: at(40))
        await f.reconcile(nil, at: at(45))
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.end, at(10))
        XCTAssertEqual(sessions.last?.activation, at(14))
        XCTAssertEqual(sessions.last?.span, DateInterval(start: at(40), end: at(45)))
        XCTAssertEqual(sessions.last?.flags, [.awaitingEvent])
        XCTAssertEqual(sessions.last?.isPartial, true)
    }

    #if canImport(LoopKit)
        /// Dana's set change: `.infusionSet` with a `.prime` (no change event) and a refill's `.reservoir`, one batch as
        /// `DeviceDataManager` maps it: one site session; a cannula primed again minutes later is the same site.
        func testStoreDanaSetChangeBatch() async throws {
            let f = Fixture()
            let events = [
                PumpEventType.replaceComponent(componentType: .infusionSet),
                .prime,
                .replaceComponent(componentType: .reservoir)
            ].map { NewPumpEvent(date: at(0), dose: nil, raw: Data(), title: "", type: $0) }
                .compactMap { PumpLifecycleEvent($0, plugin: "Dana") }
            XCTAssertEqual(events.map(\.component), [.infusionSet, .reservoir])
            let result = try await f.database.applyLifecycleEvents(events, now: at(1))
            XCTAssertEqual(result.log.count, 2, "\(result.log)")
            XCTAssertTrue(result.log.contains { $0.contains("→ started at") }, "\(result.log)")
            XCTAssertTrue(result.log.contains { $0.hasSuffix("→ none (a reservoir)") }, "\(result.log)")
            var sessions = try await f.sessions()
            XCTAssertEqual(sessions.map(\.activation), [at(0)])
            XCTAssertEqual(sessions.first?.flags, [.site])

            let again = try await f.database.applyLifecycleEvents([lifecycle("Dana", .infusionSet, 5)], now: at(6))
            XCTAssertNil(again.changed)
            XCTAssertTrue(again.log.contains { $0.hasSuffix("→ same (a re-send)") }, "\(again.log)")
            sessions = try await f.sessions()
            XCTAssertEqual(sessions.count, 1)
        }
    #endif

    /// A late Dana event (its next history sync) splits the seeded site session at its date: the new site from it on,
    /// signalled `[D, lastSeen]`.
    func testStoreLateDanaEventSplitsTheSeededSite() async throws {
        let f = Fixture()
        try await f.insertLoops(stride(from: -60.0, through: -5, by: 5).map { at($0) })
        f.delivering("Dana")
        await f.reconcile([bolus(at(-120), "1")], at: at(0))
        await f.reconcile(nil, at: at(5))
        await f.reconcile(nil, at: at(10))
        f.signals.clear()
        await f.send([lifecycle("Dana", .infusionSet, 3)], at: at(12))
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: at(3), end: at(10)))])
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.start, at(-60).addingTimeInterval(20))
        XCTAssertEqual(sessions.first?.end, at(3))
        XCTAssertEqual(sessions.last?.activation, at(3))
        XCTAssertEqual(sessions.last?.span, DateInterval(start: at(3), end: at(10)))
        XCTAssertNil(sessions.last?.end)
        XCTAssertEqual(sessions.last?.flags, [.site])
    }

    /// The log's wording: a late event with nothing of the open session before it replaces it (its row reused); a
    /// session started and closed within one batch gets its closed line.
    func testStoreChangeEventLogLines() async throws {
        var open = pumpSession(1, "Medtrum", from: at(10), to: nil)
        open.activation = at(-30)
        var replacing = pumpSession(1, "Medtrum", from: at(10), to: nil)
        replacing.activation = at(10)
        var reported = Set<UUID>()
        let line = CoreDataPumpEventDatabase.lifecycleLine(
            lifecycle("Medtrum", .pump, 10),
            before: [open],
            written: [replacing],
            reported: &reported
        )
        XCTAssertTrue(line.contains("→ started at") && line.contains("replacing the open"), line)

        let f = Fixture()
        let result = try await f.database.applyLifecycleEvents(
            [lifecycle("Medtrum", .pump, 0), lifecycle("Medtrum", .pump, 30)],
            now: at(30)
        )
        XCTAssertEqual(result.log.filter { $0.contains("→ started at") }.count, 2, "\(result.log)")
        XCTAssertEqual(result.log.filter { $0.hasPrefix("Pump session: closed Medtrum session") }.count, 1, "\(result.log)")
    }

    /// A batch of change events sent while the wipe holds the serializer is applied after it (not wiped): it takes
    /// the session the wipe's reconcile seeded.
    func testStoreChangeEventsQueuedBehindAWipe() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: at(-600))
        await f.reconcile([bolus(at(-10), "1")], at: at(0))
        try await f.insert([pumpSession(1, "Medtrum", from: at(-3000), to: at(-2000))])
        let gated = GatedDatabase(f.database)
        f.use(gated)
        let store = f.store

        await gated.close()
        let wipe = Task { await store.wipe() }
        // the rows are gone; the wipe's reconcile holds the serializer
        await gated.arrival()
        let events = Task { await store.lifecycleEvents([lifecycle("Medtrum", .pump, 0)]) }
        try await waitUntil { await store.queuedChangeBatches == 1 }
        await gated.open()
        await wipe.value
        await events.value

        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.activation, at(0))
        XCTAssertEqual(sessions.first?.flags, [])
    }

    /// A tube pump's seed (no activation) reaches back to the list's oldest row only, not to older stored doses: no
    /// site of months. Signalled from its start to now.
    func testStoreTubeSeedIsBoundedByTheList() async throws {
        let f = Fixture()
        try await f.insert(stride(from: -10.0, through: -2, by: 1).map { row(at($0 * 24 * 60), .bolus) })
        try await f.insertLoops(stride(from: -10.0 * 24 * 60, through: -5, by: 5).map { at($0) })
        f.delivering("Dana")
        await f.reconcile([bolus(at(-60), "1")], at: at(0))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.start), [at(-60).addingTimeInterval(20)])

        f.signals.clear()
        await f.store.wipeSessions()
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.start), [at(-60).addingTimeInterval(20)])
        XCTAssertEqual(sessions.first?.flags, [.site, .seeded, .awaitingEvent])
        XCTAssertEqual(f.signals.all, [.all, .interval(DateInterval(start: at(-60).addingTimeInterval(20), end: at(0)))])
    }

    /// A session heartbeat failure warns once per distinct error, or an hour after the last warning.
    func testStoreSessionFailureWarnsOncePerErrorOrHour() async {
        let f = Fixture()
        var warns = await f.store.sessionFailureWarns("a", now: at(0))
        XCTAssertTrue(warns)
        warns = await f.store.sessionFailureWarns("a", now: at(5))
        XCTAssertFalse(warns)
        warns = await f.store.sessionFailureWarns("b", now: at(10))
        XCTAssertTrue(warns)
        warns = await f.store.sessionFailureWarns("b", now: at(69))
        XCTAssertFalse(warns)
        warns = await f.store.sessionFailureWarns("b", now: at(70))
        XCTAssertTrue(warns)
    }

    /// The prune's signal for the sessions: a clipped one's from its old start to the cutoff, deleted ones as the events
    /// (`[cutoff - 1 d, cutoff]`), both their union.
    func testStorePruneSignals() async throws {
        let cutoff = at(0).addingTimeInterval(-.days(120))
        let deleted = pumpSession(
            1,
            "Medtrum",
            from: cutoff.addingTimeInterval(-.days(3)),
            to: cutoff.addingTimeInterval(-.hours(1))
        )
        let clipped = pumpSession(
            2,
            "Medtrum",
            from: cutoff.addingTimeInterval(-.hours(12)),
            to: cutoff.addingTimeInterval(.days(2))
        )
        let day = DateInterval(start: cutoff.addingTimeInterval(-.days(1)), end: cutoff)
        for (sessions, signal) in [
            ([deleted], day),
            ([clipped], DateInterval(start: cutoff.addingTimeInterval(-.hours(12)), end: cutoff)),
            ([deleted, clipped], day)
        ] {
            let f = Fixture()
            try await f.insert(sessions)
            await f.reconcile([], at: at(0))
            XCTAssertEqual(f.signals.all, [.interval(signal)], "\(sessions.map(\.id))")
        }
    }
}

private struct SessionReadFailure: Error {}

// MARK: - Nightscout sessions in the store

/// The Nightscout pump sessions of the insulin backfill (C3): the Site Changes and alarm Announcements read from both
/// upload schemes and other uploaders, the sessions built and stored before the local ones, a re-run, the prefix, the
/// seed adopting the session of its change, the wipes, an empty window, a tube pump. Synthetic values, shaped like the
/// documents Nightscout returns.
extension PumpEventStoreTests {
    /// The end titles of MedtrumKit's catalog, current and earlier values (its history from June 2026), pinned.
    private static let pinnedAlarmTitles: [(title: String, reason: PatchEndReason)] = [
        ("Alert: Reservoir empty", .ranEmpty),
        ("تنبيه: الخزان فارغ", .ranEmpty),
        ("Upozornění: Nádrž je prázdná", .ranEmpty),
        ("Advarsel: Beholderen er tom", .ranEmpty),
        ("Warnung: Reservoir leer", .ranEmpty),
        ("Aviso: Depósito vacío", .ranEmpty),
        ("Hälytys: Säiliö tyhjä", .ranEmpty),
        ("Avertissement : réservoir vide", .ranEmpty),
        ("התראה: מאגר ריק", .ranEmpty),
        ("Figyelem: A tartály üres", .ranEmpty),
        ("Avviso: serbatoio vuoto", .ranEmpty),
        ("警告：貯水タンクが空です", .ranEmpty),
        ("경고: 저수조 비움", .ranEmpty),
        ("Varsel: Tomt reservoar", .ranEmpty),
        ("Waarschuwing: Reservoir leeg", .ranEmpty),
        ("Ostrzeżenie: Zbiornik pusty", .ranEmpty),
        ("Aviso: Reservatório vazio", .ranEmpty),
        ("Avertisment: Rezervorul este gol", .ranEmpty),
        ("Предупреждение: резервуар пуст", .ranEmpty),
        ("Upozornenie: Nádrž je prázdna", .ranEmpty),
        ("Opozorilo: Rezervoar je prazen", .ranEmpty),
        ("Varning: Behållaren är tom", .ranEmpty),
        ("Uyarı: Depo boş", .ranEmpty),
        ("Попередження: резервуар порожній", .ranEmpty),
        ("Cảnh báo: Hồ chứa trống", .ranEmpty),
        ("警报：水箱已空", .ranEmpty),
        ("Warnung: Behälter leer", .ranEmpty),
        ("Varsel: Beholderen er tom", .ranEmpty),
        ("Alert: Occlusion", .occlusionOrFault),
        ("تنبيه: انسداد", .occlusionOrFault),
        ("Upozornění: Uzávěr", .occlusionOrFault),
        ("Advarsel: Blokering", .occlusionOrFault),
        ("Warnung: Verstopfung", .occlusionOrFault),
        ("Aviso: Oclusión", .occlusionOrFault),
        ("Varoitus: Tukos", .occlusionOrFault),
        ("Avertissement : occlusion", .occlusionOrFault),
        ("התראה: חסימה", .occlusionOrFault),
        ("Figyelem: elzáródás", .occlusionOrFault),
        ("Avviso: occlusione", .occlusionOrFault),
        ("警告：閉塞", .occlusionOrFault),
        ("경고: 폐색", .occlusionOrFault),
        ("Varsel: Blokkering", .occlusionOrFault),
        ("Waarschuwing: verstopping", .occlusionOrFault),
        ("Ostrzeżenie: niedrożność", .occlusionOrFault),
        ("Aviso: Oclusão", .occlusionOrFault),
        ("Avertisment: Ocluzie", .occlusionOrFault),
        ("Предупреждение: окклюзия", .occlusionOrFault),
        ("Upozornenie: Okluzia", .occlusionOrFault),
        ("Opozorilo: zapora", .occlusionOrFault),
        ("Varning: Blockering", .occlusionOrFault),
        ("Uyarı: Tıkanma", .occlusionOrFault),
        ("Попередження: Оклюзія", .occlusionOrFault),
        ("Cảnh báo: Tắc nghẽn", .occlusionOrFault),
        ("警报：阻塞", .occlusionOrFault),
        ("Alert: Patch fault", .occlusionOrFault),
        ("تنبيه: خطأ في التصحيح", .occlusionOrFault),
        ("Upozornění: Chyba v opravě", .occlusionOrFault),
        ("Advarsel: Fejl i opdateringen", .occlusionOrFault),
        ("Warnung: Patch-Fehler", .occlusionOrFault),
        ("Aviso: Error en el parche", .occlusionOrFault),
        ("Hälytys: Päivitysvirhe", .occlusionOrFault),
        ("Alerte : erreur de mise à jour", .occlusionOrFault),
        ("התראה: תקלה בתיקון", .occlusionOrFault),
        ("Figyelem: Frissítési hiba", .occlusionOrFault),
        ("Avviso: errore di patch", .occlusionOrFault),
        ("警告：パッチの不具合", .occlusionOrFault),
        ("경고: 패치 오류", .occlusionOrFault),
        ("Varsel: Feil med patch", .occlusionOrFault),
        ("Waarschuwing: Fout in patch", .occlusionOrFault),
        ("Ostrzeżenie: Błąd aktualizacji", .occlusionOrFault),
        ("Aviso: Falha na atualização", .occlusionOrFault),
        ("Avertisment: Eroare la aplicarea pompei", .occlusionOrFault),
        ("Предупреждение: Ошибка установки исправления", .occlusionOrFault),
        ("Upozornenie: Chyba aktualizácie", .occlusionOrFault),
        ("Opozorilo: Napaka pri namestitvi popravka", .occlusionOrFault),
        ("Varning: Fel i uppdateringen", .occlusionOrFault),
        ("Uyarı: Yama hatası", .occlusionOrFault),
        ("Попередження: Помилка оновлення", .occlusionOrFault),
        ("Cảnh báo: lỗi vá", .occlusionOrFault),
        ("警报：贴泵硬件故障", .occlusionOrFault),
        ("Warnung: Okklusion", .occlusionOrFault),
        ("Warnung: Fehler beim Patch", .occlusionOrFault),
        ("Varsel: Feil i oppdateringen", .occlusionOrFault),
        ("Avertisment: Eroare la aplicarea patch-ului", .occlusionOrFault),
        ("警报：储药器故障", .occlusionOrFault),
        ("警报：储药贴故障", .occlusionOrFault),
        ("警报：补丁故障", .occlusionOrFault),
        ("Alert: Occlussion", .occlusionOrFault),
        ("Upozornění: Okluze", .occlusionOrFault),
        ("Aviso: oclusión", .occlusionOrFault),
        ("התראה: סתירה", .occlusionOrFault),
        ("Advarsel: Blokkering", .occlusionOrFault),
        ("Waarschuwing: Occlusie", .occlusionOrFault),
        ("Ostrzeżenie: zablokowanie", .occlusionOrFault),
        ("Varning: Ocklusion", .occlusionOrFault),
        ("Cảnh báo: Occlussion", .occlusionOrFault)
    ]

    /// A Medtrum history: three changes uploaded by the old scheme (the pod-age pair, the patch clock 4 s before the
    /// phone's time), the newest also by the new one (the change event's Site Change seconds after); the first ended
    /// by a repeated "Reservoir empty" alarm; the evidence of each with a few minutes missing at its ends.
    private func nightscoutInput(from: Date? = nil, siteChanges: [Date]? = nil) -> NightscoutSessionsInput {
        NightscoutSessionsInput(
            siteChanges: siteChanges ?? [
                h(-200), h(-200).addingTimeInterval(4),
                h(-120).addingTimeInterval(4), h(-120),
                h(-40), h(-40).addingTimeInterval(3), h(-40).addingTimeInterval(4)
            ],
            alarms: [
                NightscoutAlarm(date: h(-125), reason: .ranEmpty),
                NightscoutAlarm(date: h(-125).addingTimeInterval(150), reason: .ranEmpty)
            ],
            evidence: [
                DateInterval(start: h(-199.9), end: h(-125.1)),
                DateInterval(start: h(-119.9), end: h(-41)),
                DateInterval(start: h(-39.9), end: h(-0.5))
            ],
            from: from ?? h(-210)
        )
    }

    private func nightscoutSession(
        _ id: Int,
        activation: Date?,
        start: Date,
        end: Date,
        plugin: String = "Medtrum"
    ) -> PumpSessionValue {
        PumpSessionValue(
            id: sessionID(id),
            source: .nightscout,
            plugin: plugin,
            activation: activation,
            start: start,
            lastSeen: end,
            end: end,
            flags: [.pluginAssumed, .endApproximate]
        )
    }

    /// Rewrites the stored session with the id.
    private func update(_ f: Fixture, _ id: UUID, _ change: @escaping @Sendable(inout PumpSessionValue) -> Void) async throws {
        try await f.container.performBackgroundTask { context in
            guard let entry = try CoreDataPumpEventDatabase.sessionRows(in: context).first(where: { $0.value.id == id })
            else { return XCTFail("no session \(id)") }
            var value = entry.value
            change(&value)
            CoreDataPumpEventDatabase.apply(value, to: entry.row)
            try context.save()
        }
    }

    /// The store's Nightscout sessions of the input, unwrapped (nil only when the write failed).
    private func storeSessions(
        _ f: Fixture,
        _ input: NightscoutSessionsInput,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> PumpEventStore.NightscoutSessionsResult {
        let result = await f.store.storeNightscoutSessions(input)
        return try XCTUnwrap(result, file: file, line: line)
    }

    /// Both upload schemes and other uploaders parse: iAPS's pod-age pair and prime Site Changes, a Loop-style one
    /// (`timestamp` and `created_at`, `enteredBy` "loop://…", the event's title), an AAPS v3 one (`date` in ms; a
    /// soft-deleted one skipped), a hand-entered one. iAPS's alarm Announcements map to an end reason in any language;
    /// another alarm, a remote command, a Note are none. The input keeps the complete time only, from its oldest record.
    func testNightscoutSiteChangesAndAlarmsParse() throws {
        let json = #"""
        [
          {"_id": "a1", "eventType": "Site Change", "created_at": "2026-10-12T08:00:04.290Z", "enteredBy": "iAPS",
           "utcOffset": 0, "carbs": null, "insulin": null},
          {"_id": "a2", "eventType": "Site Change", "created_at": "2026-10-12T08:00:00.000Z", "enteredBy": "iAPS",
           "utcOffset": 0, "carbs": null, "insulin": null, "srvCreated": 1791792004500, "srvModified": 1791792004500},
          {"_id": "a3", "eventType": "Site Change", "created_at": "2026-10-14T09:00:00.000Z", "enteredBy": "iAPS",
           "utcOffset": 0, "bolus": {"id": "x", "_type": "Prime", "timestamp": "2026-10-14T09:00:00.000Z"}},
          {"_id": "a4", "eventType": "Site Change", "created_at": "2026-10-16T10:00:00.000Z",
           "timestamp": "2026-10-16T10:00:00Z", "enteredBy": "loop://iPhone", "notes": "Pod Change (Dash)"},
          {"identifier": "a5", "eventType": "Site Change", "date": 1792310400000, "app": "AAPS", "isValid": true},
          {"identifier": "a6", "eventType": "Site Change", "date": 1792314000000, "app": "AAPS", "isValid": false},
          {"_id": "a7", "eventType": "Site Change", "created_at": "2026-10-18T07:30:00.000Z"},
          {"_id": "a8", "eventType": "Site Change", "created_at": "2026-10-01T07:30:00.000Z", "enteredBy": "iAPS"},
          {"_id": "b1", "eventType": "Announcement", "created_at": "2026-10-15T19:48:44.000Z", "enteredBy": "iAPS",
           "duration": 30, "isAnnouncement": true, "notes": "Alarm Optional(\"Alert: Reservoir empty\") pumpAlarm",
           "utcOffset": 0, "carbs": null, "insulin": null},
          {"_id": "b2", "eventType": "Announcement", "created_at": "2026-10-17T05:00:00.000Z", "enteredBy": "iAPS",
           "duration": 30, "isAnnouncement": true, "notes": "Alarm Optional(\"Warnung: Verstopfung\") pumpAlarm"},
          {"_id": "b3", "eventType": "Announcement", "created_at": "2026-10-17T06:00:00.000Z", "enteredBy": "iAPS",
           "duration": 30, "isAnnouncement": true, "notes": "Alarm Optional(\"Alert: Patch fault\") pumpAlarm"},
          {"_id": "b4", "eventType": "Announcement", "created_at": "2026-10-17T07:00:00.000Z", "enteredBy": "iAPS",
           "duration": 30, "isAnnouncement": true, "notes": "Alarm Optional(\"Alert: Hourly Insulin Limit\") pumpAlarm"},
          {"_id": "b5", "eventType": "Announcement", "created_at": "2026-10-17T08:00:00.000Z", "enteredBy": "remote",
           "notes": "bolus:1.5"},
          {"_id": "b6", "eventType": "Note", "created_at": "2026-10-17T09:00:00.000Z", "enteredBy": "loop://iPhone",
           "notes": "Alert: Occlusion"}
        ]
        """#
        let documents = try JSONDecoder().decode([NightscoutInsulinTreatment].self, from: Data(json.utf8))
        func date(_ string: String) -> Date { NightscoutDate.parse(string)! }

        XCTAssertEqual(documents.map(\.siteChange), [
            date("2026-10-12T08:00:04.290Z"), date("2026-10-12T08:00:00.000Z"), date("2026-10-14T09:00:00.000Z"),
            date("2026-10-16T10:00:00.000Z"), Date(timeIntervalSince1970: 1_792_310_400), nil,
            date("2026-10-18T07:30:00.000Z"), date("2026-10-01T07:30:00.000Z"), nil, nil, nil, nil, nil, nil
        ])
        let notAlarms: [PatchEndReason?] = Array(repeating: nil, count: 8)
        XCTAssertEqual(
            documents.map { $0.alarm()?.reason },
            notAlarms + [.ranEmpty, .occlusionOrFault, .occlusionOrFault, nil, nil, nil]
        )
        XCTAssertEqual(documents[8].alarm()?.date, date("2026-10-15T19:48:44.000Z"))
        // every catalog title maps, current and earlier values, each to one reason
        XCTAssertEqual(NightscoutInsulinTreatment.alarmTitles.map(\.title), Self.pinnedAlarmTitles.map(\.title))
        XCTAssertEqual(NightscoutInsulinTreatment.alarmTitles.map(\.reason), Self.pinnedAlarmTitles.map(\.reason))
        // a created_at with an offset
        let offset = try JSONDecoder().decode(
            [NightscoutInsulinTreatment].self,
            from: Data(#"[{"eventType": "Site Change", "created_at": "2026-10-13T10:00:00.000+02:00"}]"#.utf8)
        )
        XCTAssertEqual(offset.first?.siteChange, date("2026-10-13T08:00:00.000Z"))

        // the input: the complete time only (the a8 before it dropped), from its oldest record (a temp)
        var fetched = FetchedInsulin()
        fetched
            .treatments = [NightscoutInsulinTreatment(id: "t", eventType: "Temp Basal", createdAt: date("2026-10-11T00:00:00Z"))]
        fetched.sessionTreatments = documents
        fetched.sessionsComplete = DateInterval(start: date("2026-10-10T00:00:00Z"), end: date("2026-10-20T00:00:00Z"))
        let evidence = [DateInterval(start: date("2026-10-11T00:00:00Z"), end: date("2026-10-19T00:00:00Z"))]
        let input = try XCTUnwrap(NightscoutSessionsInput(fetched: fetched, evidence: evidence))
        XCTAssertEqual(input.from, date("2026-10-11T00:00:00Z"))
        XCTAssertEqual(input.evidence, evidence)
        XCTAssertEqual(input.siteChanges.count, 6)
        XCTAssertEqual(input.siteChanges, input.siteChanges.sorted())
        XCTAssertEqual(input.alarms.map(\.reason), [.ranEmpty, .occlusionOrFault, .occlusionOrFault])
        // the pod-age pair is one change; the prime, Loop's, AAPS's and the hand-entered one each their own
        XCTAssertEqual(PumpSessionRules.activations(input.siteChanges), [
            date("2026-10-12T08:00:00.000Z"), date("2026-10-14T09:00:00.000Z"), date("2026-10-16T10:00:00.000Z"),
            date("2026-10-18T07:30:00.000Z"), Date(timeIntervalSince1970: 1_792_310_400)
        ])
        // nothing complete, or nothing in it: none
        fetched.sessionsComplete = nil
        XCTAssertNil(NightscoutSessionsInput(fetched: fetched, evidence: evidence))
        fetched.sessionsComplete = DateInterval(start: date("2026-10-19T00:00:00Z"), end: date("2026-10-20T00:00:00Z"))
        XCTAssertNil(NightscoutSessionsInput(fetched: fetched, evidence: evidence))
    }

    /// Without a pump session the sessions are built up to now, never open, the plugin the current pump's (assumed),
    /// with the change signal. A re-run changes nothing and signals nothing; one whose Site Change moved by minutes
    /// keeps the ids, and the user's fields stay.
    func testStoreNightscoutSessionsAndReRun() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40))
        let first = try await storeSessions(f, nightscoutInput())
        XCTAssertEqual(first.window, DateInterval(start: h(-210), end: h(0)))
        XCTAssertEqual(first.sessions, 3)
        XCTAssertEqual(first.inserted, 3)
        XCTAssertFalse(first.prefixed)
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.activation), [h(-200), h(-120), h(-40)])
        XCTAssertEqual(sessions.map(\.start), [h(-200), h(-120), h(-40)])
        XCTAssertEqual(sessions.map(\.end), [h(-125), h(-41), h(-0.5)])
        XCTAssertEqual(sessions.map(\.endReason), [.ranEmpty, nil, nil])
        XCTAssertEqual(
            sessions.map(\.flags),
            [[.pluginAssumed], [.pluginAssumed, .endApproximate], [.pluginAssumed, .endApproximate]]
        )
        XCTAssertEqual(Set(sessions.map(\.source)), [.nightscout])
        XCTAssertEqual(Set(sessions.map(\.plugin)), ["Medtrum"])
        XCTAssertEqual(sessions.map(\.gaps), [[], [], []])
        XCTAssertEqual(f.signals.all, [.interval(DateInterval(start: h(-200), end: h(-0.5)))])

        f.signals.clear()
        let again = try await storeSessions(f, nightscoutInput())
        XCTAssertEqual(again.inserted + again.updated + again.deleted, 0)
        XCTAssertNil(again.changed)
        let unchanged = try await f.sessions()
        XCTAssertEqual(unchanged, sessions)
        XCTAssertEqual(f.signals.all, [])

        // the user's fields on the second; its Site Change 5 minutes later on the next run
        let ids = sessions.map(\.id)
        try await update(f, ids[1]) { session in
            session.site = "arm"
            session.endReason = .removedEarly
            session.endReasonSource = .user
        }
        var moved = nightscoutInput().siteChanges.filter { abs($0.timeIntervalSince(h(-120))) > 10 }
        moved.append(h(-120).addingTimeInterval(300))
        let rerun = try await storeSessions(f, nightscoutInput(siteChanges: moved))
        XCTAssertEqual(rerun.inserted, 0)
        XCTAssertEqual(rerun.deleted, 0)
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.id), ids)
        XCTAssertEqual(sessions[1].activation, h(-120).addingTimeInterval(300))
        XCTAssertEqual(sessions[1].site, "arm")
        XCTAssertEqual(sessions[1].endReason, .removedEarly)
        XCTAssertEqual(sessions[1].endReasonSource, .user)
    }

    /// With a pump session the window ends at its local start: its change's piece is its prefix (its start moved back
    /// to the activation, the earlier one taken), the sessions before it are built, no Site Change inside the local
    /// time makes one, and a stored Nightscout session there goes unless it holds the user's fields. A stored one before
    /// the window stays.
    func testStoreNightscoutPrefixAndNoHolesFilled() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40).addingTimeInterval(4))
        let local = PumpSessionValue(
            id: sessionID(50),
            source: .pump,
            plugin: "Medtrum",
            activation: h(-40).addingTimeInterval(4),
            start: h(-10),
            localStart: h(-10),
            lastSeen: h(0),
            flags: [.seeded, .awaitingEvent]
        )
        let stale = nightscoutSession(60, activation: h(-5), start: h(-5), end: h(-4))
        var entered = nightscoutSession(61, activation: nil, start: h(-3), end: h(-2))
        entered.site = "belly"
        let older = nightscoutSession(62, activation: h(-300), start: h(-300), end: h(-250))
        try await f.insert([local, stale, entered, older])

        let input = nightscoutInput(siteChanges: nightscoutInput().siteChanges + [h(-5)])
        let result = try await storeSessions(f, input)
        XCTAssertEqual(result.window, DateInterval(start: h(-210), end: h(-10)))
        XCTAssertEqual(result.sessions, 2)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertTrue(result.prefixed)

        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.id).filter { ![sessionID(50), sessionID(61), sessionID(62)].contains($0) }.count, 2)
        XCTAssertFalse(sessions.contains { $0.id == sessionID(60) })
        let pump = try XCTUnwrap(sessions.first { $0.source == .pump })
        XCTAssertEqual(pump.id, sessionID(50))
        XCTAssertEqual(pump.start, h(-40))
        XCTAssertEqual(pump.activation, h(-40))
        XCTAssertEqual(pump.localStart, h(-10))
        XCTAssertEqual(pump.lastSeen, h(0))
        XCTAssertEqual(pump.gaps, [])
        XCTAssertNil(pump.end)
        XCTAssertFalse(pump.isPartial)
        let nightscout = sessions.filter { $0.source == .nightscout }
        XCTAssertEqual(nightscout.map(\.activation), [h(-300), h(-200), h(-120), nil])
        // inside the local time: only the one with the user's fields
        XCTAssertEqual(nightscout.filter { $0.start >= h(-10) }.map(\.id), [sessionID(61)])
        XCTAssertEqual(f.signals.all.count, 1)
        if case let .interval(changed) = f.signals.all.first {
            XCTAssertTrue(changed.contains(h(-200)) && changed.contains(h(-4)), "\(changed)")
        } else {
            XCTFail("an interval")
        }

        // a re-run: the same rows, the prefix not stacked
        f.signals.clear()
        let again = try await storeSessions(f, input)
        XCTAssertFalse(again.prefixed)
        XCTAssertEqual(again.inserted + again.updated + again.deleted, 0)
        let rerunSessions = try await f.sessions()
        XCTAssertEqual(rerunSessions, sessions)
        XCTAssertEqual(f.signals.all, [])
    }

    /// A backfill before the first heartbeat: the seed adopts the Nightscout session of its unit's change (its id, its
    /// earlier start and activation), and a re-run then keeps it as the prefix. Another unit's piece reaching past the
    /// activation (the new patch's Site Change not uploaded) isn't adopted. The candidate's rule: the plugin, the
    /// activation within the cluster, the newest; none for a tube pump.
    func testStoreSeedAdoptsTheNightscoutSessionOfItsChange() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40).addingTimeInterval(4))
        _ = await f.store.storeNightscoutSessions(nightscoutInput())
        let stored = try await f.sessions()
        let current = try XCTUnwrap(stored.last)
        try await f.insertLoops(stride(from: -120.0, through: -5, by: 5).map { at($0) })
        await f.reconcile([bolus(h(-30), "1")], at: h(0))
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 3)
        let adopted = try XCTUnwrap(sessions.last)
        XCTAssertEqual(adopted.id, current.id)
        XCTAssertEqual(adopted.source, .pump)
        XCTAssertEqual(adopted.start, h(-40))
        XCTAssertEqual(adopted.activation, h(-40))
        XCTAssertEqual(adopted.localStart, at(-120).addingTimeInterval(20))
        XCTAssertEqual(adopted.lastSeen, h(0))
        XCTAssertNil(adopted.end)
        XCTAssertEqual(adopted.flags, [.seeded, .awaitingEvent])
        XCTAssertEqual(sessions.dropLast().map(\.id), stored.dropLast().map(\.id))

        let rerun = try await storeSessions(f, nightscoutInput())
        XCTAssertEqual(rerun.inserted + rerun.updated + rerun.deleted, 0)
        XCTAssertFalse(rerun.prefixed)
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.last, adopted)

        // a new patch at -20 h whose Site Change never reached Nightscout: the older piece isn't its, and ends at the
        // seeded start (the first pump session's tidy)
        let g = Fixture()
        g.delivering("Medtrum", pod: h(-20))
        _ = await g.store.storeNightscoutSessions(nightscoutInput())
        let older = try await g.sessions()
        try await g.insertLoops(stride(from: -120.0, through: -5, by: 5).map { at($0) })
        await g.reconcile([bolus(h(-30), "1")], at: h(0))
        let seeded = try await g.sessions()
        XCTAssertEqual(seeded.count, 4)
        var trimmed = older
        trimmed[2].lastSeen = at(-120).addingTimeInterval(20)
        trimmed[2].end = at(-120).addingTimeInterval(20)
        XCTAssertEqual(seeded.filter { $0.source == .nightscout }, trimmed)
        let pump = try XCTUnwrap(seeded.first { $0.source == .pump })
        XCTAssertFalse(older.map(\.id).contains(pump.id))
        XCTAssertEqual(pump.start, at(-120).addingTimeInterval(20))
        XCTAssertEqual(pump.activation, h(-20))

        // the rule
        let unit = PumpUnit(plugin: "Medtrum", activation: h(-40))
        let before = nightscoutSession(1, activation: h(-40).addingTimeInterval(-600), start: h(-40), end: h(-1))
        let after = nightscoutSession(2, activation: h(-40).addingTimeInterval(300), start: h(-40), end: h(-1))
        let late = nightscoutSession(3, activation: h(-2).addingTimeInterval(600), start: h(-2), end: h(-1))
        let tooLate = nightscoutSession(4, activation: h(-2).addingTimeInterval(1200), start: h(-2), end: h(-1))
        let omni = nightscoutSession(5, activation: h(-40), start: h(-40), end: h(-1), plugin: "Omni")
        XCTAssertEqual(SessionRules.seedCandidate(for: unit, seedStart: h(-30), among: [before, after, omni])?.id, sessionID(2))
        XCTAssertEqual(SessionRules.seedCandidate(for: unit, seedStart: h(-30), among: [before, omni])?.id, sessionID(1))
        // the seed's start late (Omnipod's Site Change at the setup's completion): up to 15 minutes after it
        XCTAssertEqual(SessionRules.seedCandidate(for: unit, seedStart: h(-2), among: [before, late])?.id, sessionID(3))
        XCTAssertNil(SessionRules.seedCandidate(for: unit, seedStart: h(-2), among: [tooLate, omni]))
        XCTAssertNil(SessionRules.seedCandidate(for: dana, seedStart: h(-30), among: [before, after]))
        var pumpSource = after
        pumpSource.source = .pump
        XCTAssertNil(SessionRules.seedCandidate(for: unit, seedStart: h(-30), among: [pumpSource]))
    }

    /// Both wipes clear the Nightscout sessions; the next backfill builds them again.
    func testStoreNightscoutSessionsWipeThenRebuild() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40))
        _ = await f.store.storeNightscoutSessions(nightscoutInput())
        let built = try await f.sessions()
        XCTAssertEqual(built.count, 3)

        await f.store.wipeSessions()
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.filter { $0.source == .nightscout }, [])
        f.signals.clear()
        let rebuilt = try await storeSessions(f, nightscoutInput())
        XCTAssertEqual(rebuilt.inserted, 3)
        XCTAssertEqual(f.signals.all.count, 1)
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.filter { $0.source == .nightscout }.map(\.activation), built.map(\.activation))

        await f.store.wipe()
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.filter { $0.source == .nightscout }, [])
        _ = await f.store.storeNightscoutSessions(nightscoutInput())
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.filter { $0.source == .nightscout }.map(\.activation), built.map(\.activation))
    }

    /// The oldest pump session's local start at or before the oldest record fetched: no window, nothing built, no
    /// crash, nothing signalled.
    func testStoreNightscoutSessionsWithAnEmptyWindow() async throws {
        for localStart in [h(-300), h(-210)] {
            let f = Fixture()
            f.delivering("Medtrum", pod: h(-40))
            let local = PumpSessionValue(
                id: sessionID(50),
                source: .pump,
                plugin: "Medtrum",
                activation: localStart,
                start: localStart,
                localStart: localStart,
                lastSeen: h(0)
            )
            try await f.insert([local])
            let result = try await storeSessions(f, nightscoutInput())
            XCTAssertEqual(result, PumpEventStore.NightscoutSessionsResult())
            let stored = try await f.sessions()
            XCTAssertEqual(stored, [local])
            XCTAssertEqual(f.signals.all, [])
        }
    }

    /// A tube pump: its Site Changes (both schemes: the prime ones, a set's several primes minutes apart, one per change
    /// event) cut sites, its alarms end nothing, the last one ends at the local site's start; a seeded local site (no
    /// activation) gets no prefix and is left as it is.
    func testStoreNightscoutSessionsOfATubePump() async throws {
        let f = Fixture()
        f.delivering("Dana")
        let local = PumpSessionValue(
            id: sessionID(70),
            source: .pump,
            plugin: "Dana",
            start: h(-10),
            localStart: h(-10),
            lastSeen: h(0),
            flags: [.site, .seeded, .awaitingEvent]
        )
        try await f.insert([local])
        let input = NightscoutSessionsInput(
            siteChanges: [
                h(-150), h(-150).addingTimeInterval(300),
                h(-80), h(-80).addingTimeInterval(90), h(-80).addingTimeInterval(480),
                h(-30)
            ],
            alarms: [NightscoutAlarm(date: h(-60), reason: .occlusionOrFault)],
            evidence: [DateInterval(start: h(-149.9), end: h(-0.5))],
            from: h(-160)
        )
        let result = try await storeSessions(f, input)
        XCTAssertFalse(result.prefixed)
        let sessions = try await f.sessions()
        let sites = sessions.filter { $0.source == .nightscout }
        XCTAssertEqual(sites.map(\.activation), [h(-150), h(-80), h(-30)])
        XCTAssertEqual(sites.map(\.start), [h(-150), h(-80), h(-30)])
        XCTAssertEqual(sites.map(\.lastSeen), [h(-80), h(-30), h(-10)])
        XCTAssertEqual(sites.map(\.end), [h(-80), h(-30), h(-10)])
        XCTAssertEqual(Set(sites.map(\.flags)), [[.site, .pluginAssumed, .endApproximate]])
        XCTAssertEqual(Set(sites.map(\.endReason)), [nil])
        XCTAssertEqual(Set(sites.map(\.plugin)), ["Dana"])
        XCTAssertEqual(sessions.first { $0.source == .pump }, local)
    }
}

// MARK: - Nightscout sessions: review cases

/// The C3 review's cases: the first pump session's tidy, the adoption's end reason, the check from the local start,
/// the prefix's own plugin, the first piece's identity across cutoffs, holes between local sessions, partial fetches,
/// the store's cutoff, a pump switch, a deleted Site Change.
extension PumpEventStoreTests {
    /// An adopted Nightscout session's end reason (Nightscout's) goes: the adopted session is open. The user's stays.
    func testSeedAdoptionDropsTheNightscoutEndReason() {
        var nightscout = PumpSessionValue(
            id: sessionID(5),
            source: .nightscout,
            plugin: "Medtrum",
            activation: at(-605),
            start: at(-605),
            lastSeen: at(-100),
            end: at(-90),
            flags: [.pluginAssumed],
            endReason: .ranEmpty,
            endReasonSource: .nightscout
        )
        let loops = stride(from: -50.0, through: -5, by: 5).map { at($0) }
        let adopted = SessionRules.seed(medtrum(-600), loops: loops, now: at(0), adopting: nightscout)
        XCTAssertEqual(adopted.id, sessionID(5))
        XCTAssertNil(adopted.end)
        XCTAssertNil(adopted.endReason)
        XCTAssertEqual(adopted.endReasonSource, .none)
        nightscout.endReason = .removedEarly
        nightscout.endReasonSource = .user
        let entered = SessionRules.seed(medtrum(-600), loops: loops, now: at(0), adopting: nightscout)
        XCTAssertEqual(entered.endReason, .removedEarly)
        XCTAssertEqual(entered.endReasonSource, .user)
    }

    /// The activation-less first piece, clipped by a cutoff that moved since, is the stored one (by its end): its id
    /// and fields kept.
    func testNightscoutFirstPieceKeepsItsIdAcrossCutoffs() {
        func run(cutoff: Date, existing: [PumpSessionValue]) -> [PumpSessionValue] {
            SessionRules.nightscoutSessions(
                siteChanges: [h(-100)],
                alarms: [],
                evidence: [DateInterval(start: h(-300), end: h(-101)), DateInterval(start: h(-99.9), end: h(-1))],
                from: h(-310),
                to: h(0),
                currentPlugin: "Medtrum",
                existing: existing,
                local: nil,
                cutoff: cutoff
            ).sessions
        }
        var first = run(cutoff: h(-250), existing: [])
        XCTAssertEqual(first.map(\.activation), [nil, h(-100)])
        XCTAssertEqual(first[0].start, h(-250))
        first[0].site = "arm"
        let next = run(cutoff: h(-226), existing: first)
        XCTAssertEqual(next.map(\.id), first.map(\.id))
        XCTAssertEqual(next[0].start, h(-226))
        XCTAssertEqual(next[0].site, "arm")
    }

    /// Two local sessions with a hole between them (no pump for a day): Nightscout's Site Change and evidence there
    /// make nothing, and a stored Nightscout session there goes; the local sessions stay as they are.
    func testStoreNightscoutFillsNoHoleBetweenLocalSessions() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-30))
        let older = pumpSession(50, "Medtrum", from: h(-100), to: h(-60))
        let newer = pumpSession(51, "Medtrum", from: h(-30), to: nil, lastSeen: h(0))
        let inHole = nightscoutSession(60, activation: h(-50), start: h(-50), end: h(-40))
        try await f.insert([older, newer, inHole])
        let input = NightscoutSessionsInput(
            siteChanges: [h(-200), h(-100), h(-50), h(-30)],
            alarms: [],
            evidence: [DateInterval(start: h(-199.9), end: h(-0.5))],
            from: h(-210)
        )
        let result = try await storeSessions(f, input)
        XCTAssertEqual(result.window, DateInterval(start: h(-210), end: h(-100)))
        XCTAssertEqual(result.deleted, 1)
        let sessions = try await f.sessions()
        let nightscout = sessions.filter { $0.source == .nightscout }
        XCTAssertEqual(nightscout.map(\.activation), [h(-200)])
        XCTAssertEqual(nightscout.first?.end, h(-100))
        XCTAssertEqual(sessions.filter { $0.source == .pump }, [older, newer])
    }

    /// A tube pump's site started by its change event (taken by a fallback: its start moved back, a gap to the local
    /// start) gets the prefix of its Site Change: Nightscout's evidence replaces the gap.
    func testStoreNightscoutPrefixOfAnEventStartedTubeSite() async throws {
        let f = Fixture()
        f.delivering("Dana")
        let local = PumpSessionValue(
            id: sessionID(70),
            source: .pump,
            plugin: "Dana",
            activation: h(-20),
            start: h(-20),
            localStart: h(-10),
            lastSeen: h(0),
            gaps: [DateInterval(start: h(-20), end: h(-10))],
            flags: [.site]
        )
        try await f.insert([local])
        let input = NightscoutSessionsInput(
            siteChanges: [h(-150), h(-20)],
            alarms: [],
            evidence: [DateInterval(start: h(-149.9), end: h(-0.5))],
            from: h(-160)
        )
        let result = try await storeSessions(f, input)
        XCTAssertTrue(result.prefixed)
        let sessions = try await f.sessions()
        let pump = try XCTUnwrap(sessions.first { $0.source == .pump })
        XCTAssertEqual(pump.start, h(-20))
        XCTAssertEqual(pump.localStart, h(-10))
        XCTAssertEqual(pump.gaps, [])
        let sites = sessions.filter { $0.source == .nightscout }
        XCTAssertEqual(sites.map(\.activation), [h(-150)])
        XCTAssertEqual(sites.map(\.end), [h(-20)])
        XCTAssertEqual(sites.first?.flags, [.site, .pluginAssumed, .endApproximate])
    }

    /// A fetch whose session queries stopped early (a later `sessionsComplete`): the input starts at its oldest record
    /// after it, the window at the next activation after the stored session it falls in; the older stored sessions
    /// are kept, the newer ones keep their ids.
    func testStoreNightscoutPartialFetchKeepsTheOlderSessions() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40))
        _ = try await storeSessions(f, nightscoutInput())
        let before = try await f.sessions()

        var fetched = FetchedInsulin()
        fetched.treatments = [NightscoutInsulinTreatment(id: "t", eventType: "Temp Basal", createdAt: h(-129))]
        fetched.sessionTreatments = [h(-200), h(-120), h(-40)].enumerated().map { index, date in
            NightscoutInsulinTreatment(id: "s\(index)", eventType: "Site Change", createdAt: date)
        }
        fetched.sessionsComplete = DateInterval(start: h(-130), end: h(0))
        let input = try XCTUnwrap(NightscoutSessionsInput(fetched: fetched, evidence: nightscoutInput().evidence))
        XCTAssertEqual(input.from, h(-129))
        XCTAssertEqual(input.siteChanges, [h(-120), h(-40)])
        let result = try await storeSessions(f, input)
        XCTAssertEqual(result.window, DateInterval(start: h(-120), end: h(0)))
        XCTAssertEqual(result.inserted + result.deleted, 0)
        let after = try await f.sessions()
        XCTAssertEqual(after, before)

        // the window starting inside a stored session: from the next activation
        let inside = try await storeSessions(f, nightscoutInput(from: h(-150)))
        XCTAssertEqual(inside.window, DateInterval(start: h(-120), end: h(0)))
        let again = try await f.sessions()
        XCTAssertEqual(again, before)
    }

    /// The retention's cutoff when the store builds them: a session spanning it starts there (partial, its activation
    /// kept); on a later run one last seen before it isn't built, and its stored row goes.
    func testStoreNightscoutSessionsAtTheCutoff() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40))
        f.clock.now = h(0).addingTimeInterval(.days(120) - .hours(160))
        _ = try await storeSessions(f, nightscoutInput())
        var sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.activation), [h(-200), h(-120), h(-40)])
        XCTAssertEqual(sessions.first?.start, h(-160))
        XCTAssertEqual(sessions.first?.isPartial, true)
        let ids = sessions.map(\.id)

        f.clock.now = h(0).addingTimeInterval(.days(120) - .hours(124))
        let result = try await storeSessions(f, nightscoutInput())
        XCTAssertEqual(result.deleted, 1)
        sessions = try await f.sessions()
        XCTAssertEqual(sessions.map(\.activation), [h(-120), h(-40)])
        XCTAssertEqual(sessions.map(\.id), Array(ids.dropFirst()))
    }

    /// A pump switched since the last backfill: a re-run relabels the Nightscout sessions with the current pump, their
    /// ids kept; the oldest pump session (of the earlier pump) still gets its prefix, of its own plugin.
    func testStoreNightscoutSessionsAfterAPumpSwitch() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40))
        _ = try await storeSessions(f, nightscoutInput())
        let medtrum = try await f.sessions()
        f.delivering("Omni", pod: h(-5))
        _ = try await storeSessions(f, nightscoutInput())
        let omni = try await f.sessions()
        XCTAssertEqual(omni.map(\.id), medtrum.map(\.id))
        XCTAssertEqual(Set(omni.map(\.plugin)), ["Omni"])

        let g = Fixture()
        g.delivering("Omni", pod: h(-5))
        let local = PumpSessionValue(
            id: sessionID(50),
            source: .pump,
            plugin: "Medtrum",
            activation: h(-40).addingTimeInterval(4),
            start: h(-10),
            localStart: h(-10),
            lastSeen: h(0)
        )
        try await g.insert([local])
        let result = try await storeSessions(g, nightscoutInput())
        XCTAssertTrue(result.prefixed)
        let sessions = try await g.sessions()
        let pump = try XCTUnwrap(sessions.first { $0.source == .pump })
        XCTAssertEqual(pump.plugin, "Medtrum")
        XCTAssertEqual(pump.start, h(-40))
        XCTAssertEqual(Set(sessions.filter { $0.source == .nightscout }.map(\.plugin)), ["Omni"])
    }

    /// A Site Change deleted in Nightscout: its stored session with the user's fields is kept, and the time it covered
    /// is a new session without an activation.
    func testStoreNightscoutDeletedSiteChangeKeepsTheAnnotatedRow() async throws {
        let f = Fixture()
        f.delivering("Medtrum", pod: h(-40))
        let full = nightscoutInput()
        let quiet = NightscoutSessionsInput(siteChanges: full.siteChanges, alarms: [], evidence: full.evidence, from: full.from)
        _ = try await storeSessions(f, quiet)
        let first = try await f.sessions()
        try await update(f, first[1].id) { $0.site = "thigh" }

        let removed = NightscoutSessionsInput(
            siteChanges: full.siteChanges.filter { abs($0.timeIntervalSince(h(-120))) > 10 },
            alarms: [],
            evidence: full.evidence,
            from: full.from
        )
        let result = try await storeSessions(f, removed)
        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.kept, 1)
        XCTAssertEqual(result.deleted, 0)
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.first { $0.id == first[1].id }?.site, "thigh")
        let added = try XCTUnwrap(sessions.first { !first.map(\.id).contains($0.id) })
        XCTAssertNil(added.activation)
        XCTAssertEqual(added.start, h(-80))
        XCTAssertEqual(added.lastSeen, h(-41))
        XCTAssertEqual(sessions.first?.id, first[0].id)
        XCTAssertEqual(sessions.first?.lastSeen, h(-80))
    }

    /// An import without a pump (no plugin), then the pump: the seed adopts the session of its change, taking the
    /// unit's plugin. A first change event starts at its own date (no Nightscout session moves it): the one it falls
    /// in ends there, the ones after it go.
    func testStoreFirstPumpSessionTidiesTheNightscoutSessions() async throws {
        let f = Fixture()
        _ = try await storeSessions(f, nightscoutInput())
        let imported = try await f.sessions()
        XCTAssertEqual(Set(imported.map(\.plugin)), [nil])
        f.delivering("Medtrum", pod: h(-40).addingTimeInterval(4))
        try await f.insertLoops(stride(from: -120.0, through: -5, by: 5).map { at($0) })
        await f.reconcile([bolus(h(-30), "1")], at: h(0))
        let sessions = try await f.sessions()
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(Array(sessions.prefix(2)), Array(imported.prefix(2)))
        let adopted = try XCTUnwrap(sessions.last)
        XCTAssertEqual(adopted.id, imported[2].id)
        XCTAssertEqual(adopted.source, .pump)
        XCTAssertEqual(adopted.plugin, "Medtrum")
        XCTAssertEqual(adopted.start, h(-40))
        XCTAssertNil(adopted.end)

        // a change event dated inside the second: it starts there, the second ends at it, the third goes
        let g = Fixture()
        _ = try await storeSessions(g, nightscoutInput())
        let ids = try await g.sessions().map(\.id)
        let result = try await g.database.applyLifecycleEvents([lifecycle("Medtrum", .pump, -50 * 60)], now: h(0))
        XCTAssertTrue(
            result.log.contains { $0.contains("1 Nightscout sessions after it deleted, 1 ended at it") },
            "\(result.log)"
        )
        let after = try await g.sessions()
        let nightscout = after.filter { $0.source == .nightscout }
        XCTAssertEqual(nightscout.map(\.id), Array(ids.prefix(2)))
        XCTAssertEqual(nightscout.last?.lastSeen, h(-50))
        XCTAssertEqual(nightscout.last?.end, h(-50))
        XCTAssertEqual(nightscout.last?.flags.contains(.endApproximate), true)
        XCTAssertEqual(after.first { $0.source == .pump }?.start, h(-50))
    }
}

// MARK: - Nightscout sessions: review round 2

extension PumpEventStoreTests {
    /// A Nightscout end reason is never carried: a re-run without the alarm has none (a tube pump's re-run neither);
    /// the user's reason and fill are. A prefix match carries none onto the open pump session; a stored row whose user
    /// value the pump session had its own of is kept.
    func testNightscoutEndReasonsAreNotCarried() throws {
        let base = nightscoutInput()
        func run(
            _ plugin: String?,
            alarms: [NightscoutAlarm],
            existing: [PumpSessionValue],
            local: PumpSessionValue? = nil,
            to: Date? = nil
        ) -> NightscoutSessions {
            SessionRules.nightscoutSessions(
                siteChanges: base.siteChanges,
                alarms: alarms,
                evidence: base.evidence,
                from: base.from,
                to: to ?? h(0),
                currentPlugin: plugin,
                existing: existing,
                local: local
            )
        }
        let first = run("Medtrum", alarms: base.alarms, existing: []).sessions
        XCTAssertEqual(first[0].endReason, .ranEmpty)
        let again = run("Medtrum", alarms: [], existing: first).sessions
        XCTAssertEqual(again.map(\.id), first.map(\.id))
        XCTAssertNil(again[0].endReason)
        XCTAssertEqual(again[0].endReasonSource, .none)
        var entered = first
        entered[0].endReason = .expired
        entered[0].endReasonSource = .user
        entered[0].filledUnits = 180
        entered[0].fillSource = .user
        let user = run("Medtrum", alarms: [], existing: entered).sessions
        XCTAssertEqual(user[0].endReason, .expired)
        XCTAssertEqual(user[0].endReasonSource, .user)
        XCTAssertEqual(user[0].filledUnits, 180)
        // a switch to a tube pump: its alarms end nothing, the stored reasons don't come back
        let tube = run("Dana", alarms: base.alarms, existing: first).sessions
        XCTAssertEqual(tube.map(\.id), first.map(\.id))
        XCTAssertEqual(Set(tube.map(\.endReason)), [nil])
        XCTAssertTrue(tube.allSatisfy { $0.flags.contains(.site) })

        // the prefix
        var local = SessionRules.seed(medtrum(-40 * 60), loops: [h(-10), h(-5)], now: h(0), newID: sessionID(50))
        var stored = nightscoutSession(30, activation: h(-40), start: h(-40), end: h(-11))
        stored.endReason = .ranEmpty
        stored.endReasonSource = .nightscout
        stored.site = "arm"
        let prefixed = run("Medtrum", alarms: [], existing: [stored], local: local, to: h(-10))
        XCTAssertEqual(prefixed.prefixed?.site, "arm")
        XCTAssertNil(prefixed.prefixed?.endReason)
        XCTAssertNil(prefixed.prefixed?.end)
        XCTAssertEqual(prefixed.kept, [])
        // the pump session's own user fill: the stored one's stays on its row
        local.filledUnits = 170
        local.fillSource = .user
        stored.filledUnits = 150
        stored.fillSource = .user
        let own = run("Medtrum", alarms: [], existing: [stored], local: local, to: h(-10))
        XCTAssertEqual(own.prefixed?.filledUnits, 170)
        XCTAssertEqual(own.prefixed?.site, "arm")
        XCTAssertEqual(own.kept.map(\.id), [sessionID(30)])
    }

    /// The first pump session's tidy, pure: a pump session and the excluded (adopted) one untouched; after the start a
    /// plain one goes, an annotated one stays; one spanning it ends there, its fields kept but a Nightscout end reason;
    /// one ending exactly at it is left alone.
    func testNightscoutTidyAtTheFirstPumpSession() {
        let start = h(-50)
        let pump = pumpSession(1, "Medtrum", from: h(-60), to: nil, lastSeen: h(0))
        let adopted = nightscoutSession(2, activation: h(-45), start: h(-45), end: h(-30))
        let plain = nightscoutSession(3, activation: h(-44), start: h(-44), end: h(-30))
        var annotated = nightscoutSession(4, activation: h(-40), start: h(-40), end: h(-30))
        annotated.site = "x"
        var spanning = nightscoutSession(5, activation: h(-100), start: h(-100), end: h(-30))
        spanning.site = "y"
        spanning.endReason = .ranEmpty
        spanning.endReasonSource = .nightscout
        spanning.gaps = [DateInterval(start: h(-60), end: h(-40))]
        var userReason = nightscoutSession(6, activation: h(-90), start: h(-90), end: h(-20))
        userReason.endReason = .expired
        userReason.endReasonSource = .user
        let touching = nightscoutSession(7, activation: h(-200), start: h(-200), end: start)

        let plan = SessionRules.tidy(
            [pump, adopted, plain, annotated, spanning, userReason, touching],
            from: start,
            except: [adopted.id]
        )
        XCTAssertEqual(plan.deleted, [plain.id])
        XCTAssertEqual(plan.trimmed.map(\.id), [spanning.id, userReason.id])
        let ended = plan.trimmed[0]
        XCTAssertEqual(ended.end, start)
        XCTAssertEqual(ended.lastSeen, start)
        XCTAssertEqual(ended.gaps, [DateInterval(start: h(-60), end: start)])
        XCTAssertEqual(ended.site, "y")
        XCTAssertNil(ended.endReason)
        XCTAssertTrue(ended.flags.contains(.endApproximate))
        XCTAssertEqual(plan.trimmed[1].endReason, .expired)
        XCTAssertEqual(plan.trimmed[1].endReasonSource, .user)
    }

    /// The Announcement query asks the server for the alarms only.
    func testAnnouncementsQueryFiltersAlarmsOnTheServer() {
        let items = NightscoutInsulinQuery.announcements.queryItems
        XCTAssertTrue(items.contains(URLQueryItem(name: "find[eventType]", value: "Announcement")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "find[notes][$regex]", value: "^Alarm")))
        XCTAssertEqual(
            NightscoutInsulinQuery.siteChanges.queryItems,
            [URLQueryItem(name: "find[eventType]", value: "Site Change")]
        )
    }

    /// The activation-less first piece and a post-expiry piece of one run keep their own ids across cutoffs: the
    /// end-or-start sameness doesn't merge them.
    func testNightscoutFirstAndPostExpiryPiecesStayApart() {
        func run(cutoff: Date, existing: [PumpSessionValue]) -> [PumpSessionValue] {
            SessionRules.nightscoutSessions(
                siteChanges: [h(-200)],
                alarms: [],
                evidence: [
                    DateInterval(start: h(-300), end: h(-201)),
                    DateInterval(start: h(-199.9), end: h(-150)),
                    DateInterval(start: h(-110), end: h(-90))
                ],
                from: h(-310),
                to: h(-80),
                currentPlugin: "Omni",
                existing: existing,
                local: nil,
                cutoff: cutoff
            ).sessions
        }
        let first = run(cutoff: h(-280), existing: [])
        XCTAssertEqual(first.map(\.activation), [nil, h(-200), nil])
        XCTAssertEqual(first.map(\.start), [h(-280), h(-200), h(-110)])
        XCTAssertEqual(Set(first.map(\.id)).count, 3)
        let next = run(cutoff: h(-260), existing: first)
        XCTAssertEqual(next.map(\.id), first.map(\.id))
        XCTAssertEqual(next.map(\.start), [h(-260), h(-200), h(-110)])
    }

    /// An alarm after the pod's maximum life (within the margin) ends it at the alarm, approximate: the time between
    /// its last piece time and the alarm is unknown.
    func testNightscoutAlarmAfterTheMaximumLifeIsApproximate() {
        let sessions = SessionRules.nightscoutSessions(
            siteChanges: [h(-200)],
            alarms: [NightscoutAlarm(date: h(-115), reason: .occlusionOrFault)],
            evidence: [DateInterval(start: h(-199.9), end: h(-125))],
            from: h(-210),
            to: h(-80),
            currentPlugin: "Omni",
            existing: [],
            local: nil
        ).sessions
        XCTAssertEqual(sessions.map(\.activation), [h(-200)])
        XCTAssertEqual(sessions[0].end, h(-115))
        XCTAssertEqual(sessions[0].lastSeen, h(-120))
        XCTAssertEqual(sessions[0].endReason, .occlusionOrFault)
        XCTAssertEqual(sessions[0].flags, [.pluginAssumed, .endApproximate])
    }

    /// The oldest pump session's piece is capped by its own unit's life: a Medtrum patch worn 90 h (past Omnipod's
    /// 80 h) before the local start still gets its prefix with an Omnipod current.
    func testNightscoutPrefixUsesTheLocalUnitsLife() throws {
        let local = PumpSessionValue(
            id: sessionID(50),
            source: .pump,
            plugin: "Medtrum",
            activation: h(-100),
            start: h(-10),
            localStart: h(-10),
            lastSeen: h(0)
        )
        let result = SessionRules.nightscoutSessions(
            siteChanges: [h(-200), h(-100)],
            alarms: [],
            evidence: [DateInterval(start: h(-199.9), end: h(-0.5))],
            from: h(-210),
            to: h(-10),
            currentPlugin: "Omni",
            existing: [],
            local: local
        )
        let prefixed = try XCTUnwrap(result.prefixed)
        XCTAssertEqual(prefixed.start, h(-100))
        XCTAssertEqual(prefixed.plugin, "Medtrum")
        // the Omnipod-era piece: capped at its 80 h, the rest a piece without an activation
        XCTAssertEqual(result.sessions.map(\.activation), [h(-200), nil])
        XCTAssertEqual(result.sessions.map(\.lastSeen), [h(-120), h(-100)])
    }

    /// Every end title of MedtrumKit's current catalog is in the table, with its reason (skipped without the
    /// submodule's file).
    func testAlarmTitlesCoverTheCurrentCatalog() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MedtrumKit/Localization/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("no MedtrumKit catalog at \(url.path)")
        }
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let table = Dictionary(
            NightscoutInsulinTreatment.alarmTitles.map { ($0.title, $0.reason) },
            uniquingKeysWith: { first, _ in first }
        )
        let keys: [(String, PatchEndReason)] = [
            ("Alert: Reservoir empty", .ranEmpty),
            ("Alert: Occlusion", .occlusionOrFault),
            ("Alert: Patch fault", .occlusionOrFault)
        ]
        for (key, reason) in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let values = [key] + localizations.values.compactMap { localization in
                ((localization as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            }
            for value in values {
                XCTAssertEqual(table[value], reason, value)
            }
        }
    }
}
