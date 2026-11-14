import CoreData
@testable import FreeAPS
import XCTest

/// The statistics suites' shared fixtures: the calendar, the reference days and the in-memory store.
enum StatsFixtures {
    /// A Gregorian calendar in the time zone.
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static let berlin = calendar("Europe/Berlin")

    /// 2026-10-20 00:00 Europe/Berlin (CEST)
    static let day0 = Date(timeIntervalSince1970: 1_792_447_200)
    /// 2026-03-29 00:00 Europe/Berlin (CET), a 23-hour day
    static let springForward = Date(timeIntervalSince1970: 1_774_738_800)
    /// 2026-10-25 00:00 Europe/Berlin (CEST), a 25-hour day
    static let fallBack = Date(timeIntervalSince1970: 1_792_879_200)
    /// 2026-10-10 00:00 Europe/Berlin (CEST): a week without a DST change
    static let week = Date(timeIntervalSince1970: 1_791_583_200)

    /// The app's model in an in-memory SQLite store (batch deletes need SQLite). The model is the instance of
    /// `CoreDataStack.shared` (which only builds it: the stores are opened by `loadStores()`), not one loaded from the
    /// momd again: two loaded models both claim the entity classes, and `Readings(context:)` (`insertBatch`) could then
    /// resolve the wrong one.
    static func inMemoryContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: "Core_Data",
            managedObjectModel: CoreDataStack.shared.persistentContainer.managedObjectModel
        )
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        return container
    }

    /// The rows' covered time, as `CoreDataStorage.fetchCoverage` reads it.
    static func covered(_ rows: [PumpSessionValue]) -> [CoveredInterval] {
        CoreDataStorage.coverage(rows, from: .distantPast, to: .distantFuture)
    }
}

/// A fake's gates: a call matching a closed gate is held there until it opens. The fake actor stores it and awaits the
/// stream `hold`/`arrival` return; `open` releases the held calls.
struct TestGates<Input> {
    private struct Gate {
        let matches: @Sendable(Input) -> Bool
        var isOpen = false
        var arrived = 0
        /// the calls held at it
        var held: [AsyncStream<Void>.Continuation] = []
        /// waiting for a call to arrive
        var watchers: [AsyncStream<Void>.Continuation] = []
    }

    private var gates: [Int: Gate] = [:]
    private var lastGate = 0

    /// A gate holding the calls matching the predicate until `open`.
    mutating func add(_ matches: @escaping @Sendable(Input) -> Bool) -> Int {
        lastGate += 1
        gates[lastGate] = Gate(matches: matches)
        return lastGate
    }

    mutating func open(_ gate: Int) {
        gates[gate]?.isOpen = true
        let held = gates[gate]?.held ?? []
        gates[gate]?.held = []
        held.forEach { $0.finish() }
    }

    /// What to wait on until a call is held at the gate; nil when one was (or there is no such gate).
    mutating func arrival(at gate: Int) -> AsyncStream<Void>? {
        guard let current = gates[gate], current.arrived == 0 else { return nil }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gates[gate]?.watchers.append(continuation)
        return stream
    }

    /// What the call waits on at the first closed gate matching it; nil when none does.
    mutating func hold(_ input: Input) -> AsyncStream<Void>? {
        guard let gate = gates.keys.sorted().first(where: { gates[$0].map { !$0.isOpen && $0.matches(input) } ?? false })
        else { return nil }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gates[gate]?.held.append(continuation)
        gates[gate]?.arrived += 1
        let watchers = gates[gate]?.watchers ?? []
        gates[gate]?.watchers = []
        watchers.forEach { $0.finish() }
        return stream
    }
}

/// The insulin suites' pump rows: a suite adopting it gets the builders.
protocol PumpEventRecordBuilders {}

extension PumpEventRecordBuilders {
    func bolus(
        _ date: Date,
        _ units: Double,
        smb: Bool = false,
        external: Bool = false,
        source: PumpEventSource = .pump
    ) -> PumpEventRecord {
        PumpEventRecord(date: date, kind: .bolus, source: source, units: units, isSMB: smb, isExternal: external)
    }

    /// A temp basal; `minutes` as stored (pump rows carry the file's +0.1). Without `units`, not delivered/final.
    func temp(
        _ date: Date,
        rate: Double,
        minutes: Double,
        units: Double? = nil,
        source: PumpEventSource = .pump
    ) -> PumpEventRecord {
        PumpEventRecord(
            date: date,
            kind: .tempBasal,
            source: source,
            units: units ?? -1,
            rate: rate,
            durationMin: minutes,
            isMutable: units == nil
        )
    }

    func suspend(_ date: Date, source: PumpEventSource = .pump) -> PumpEventRecord {
        PumpEventRecord(date: date, kind: .suspend, source: source)
    }

    func resume(_ date: Date, source: PumpEventSource = .pump) -> PumpEventRecord {
        PumpEventRecord(date: date, kind: .resume, source: source)
    }
}
