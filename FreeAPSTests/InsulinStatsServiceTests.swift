import Combine
import CoreData
@testable import FreeAPS
import XCTest

private typealias Engine = InsulinStatsEngine

/// The real fetchers (`CoreDataStorage` on an in-memory store) with every call recorded. A call matching a closed gate
/// waits there, after its fetch, until it opens: it returns what was stored when it started. A call matching a failure
/// throws instead (once).
private actor RecordingSource: InsulinDataSource {
    enum Fetch: Sendable, Equatable {
        case events
        case runningInto
        case coverage
        case schedules
        case iob
    }

    struct Call: Sendable, Equatable {
        let fetch: Fetch
        let range: DateInterval
    }

    struct Failure: Error {}

    private let base: CoreDataStorage
    private(set) var calls: [Call] = []
    private var gates = TestGates<Call>()
    private var failures: [@Sendable(Call) -> Bool] = []

    init(_ base: CoreDataStorage) {
        self.base = base
    }

    func clearCalls() {
        calls = []
    }

    func gate(_ matches: @escaping @Sendable(Call) -> Bool) -> Int {
        gates.add(matches)
    }

    func open(_ gate: Int) {
        gates.open(gate)
    }

    /// Returns once a call is held at the gate (at once when one was).
    func arrival(at gate: Int) async {
        guard let arrival = gates.arrival(at: gate) else { return }
        for await _ in arrival {}
    }

    func failOnce(_ matches: @escaping @Sendable(Call) -> Bool) {
        failures.append(matches)
    }

    private func run<Value: Sendable>(_ call: Call, _ fetch: @Sendable() async throws -> Value) async throws -> Value {
        calls.append(call)
        if let index = failures.firstIndex(where: { $0(call) }) {
            failures.remove(at: index)
            throw Failure()
        }
        let value = try await fetch()
        if let held = gates.hold(call) {
            for await _ in held {}
        }
        return value
    }

    func fetchPumpEvents(from: Date, to: Date) async throws -> [PumpEventRecord] {
        let base = self.base
        return try await run(Call(fetch: .events, range: DateInterval(start: from, end: to))) {
            try await base.fetchPumpEvents(from: from, to: to)
        }
    }

    func fetchPumpEventsRunningInto(_ date: Date) async throws -> [PumpEventRecord] {
        let base = self.base
        return try await run(Call(fetch: .runningInto, range: DateInterval(start: date, duration: 0))) {
            try await base.fetchPumpEventsRunningInto(date)
        }
    }

    func fetchCoverage(from: Date, to: Date) async throws -> [CoveredInterval] {
        let base = self.base
        return try await run(Call(fetch: .coverage, range: DateInterval(start: from, end: to))) {
            try await base.fetchCoverage(from: from, to: to)
        }
    }

    func fetchBasalSchedules(from: Date, to: Date) async throws -> [BasalScheduleRecordValue] {
        let base = self.base
        return try await run(Call(fetch: .schedules, range: DateInterval(start: from, end: to))) {
            try await base.fetchBasalSchedules(from: from, to: to)
        }
    }

    func fetchIOBPoints(from: Date, to: Date) async throws -> [IOBPoint] {
        let base = self.base
        return try await run(Call(fetch: .iob, range: DateInterval(start: from, end: to))) {
            try await base.fetchIOBPoints(from: from, to: to)
        }
    }
}

private extension PumpSessionValue {
    /// A coverage stretch's time (a closed session without gaps) as the engine takes it (`InsulinInput.coverage`).
    var coveredInterval: CoveredInterval { CoveredInterval(interval: span, source: source) }
}

/// A `Meals` row: the amounts as decimal strings (`saveMeals` writes NSDecimalNumbers into the Double columns).
private typealias MealRow = (
    id: String?,
    actualDate: Date?,
    createdAt: Date?,
    carbs: String,
    fat: String,
    protein: String,
    saved: Bool
)

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var currentNow: Date
    private var currentCalendar: Calendar

    init(now: Date, calendar: Calendar) {
        currentNow = now
        currentCalendar = calendar
    }

    var now: Date {
        get { lock.withLock { currentNow } }
        set { lock.withLock { currentNow = newValue } }
    }

    var calendar: Calendar {
        get { lock.withLock { currentCalendar } }
        set { lock.withLock { currentCalendar = newValue } }
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

/// The Meals rows a carbs storage writes, counted only.
private actor CountingMealRows: MealRowStore {
    private(set) var saves = 0
    private(set) var deletes = 0

    func saveMeals(_: [CarbsEntry]) async {
        saves += 1
    }

    func deleteMeals(ids _: [String]) async {
        deletes += 1
    }

    func deduplicateMealsOnce() async {}
}

final class InsulinStatsServiceTests: XCTestCase, PumpEventRecordBuilders {
    // MARK: - Fixtures

    private static let berlin = StatsFixtures.berlin

    /// 2026-10-20, today in every test (no DST change in the weeks before)
    private static let day0 = StatsFixtures.day0

    /// The day `offset` days from day0 (Berlin), at the time of day.
    private static func at(_ offset: Int, hours: Double = 0, minutes: Double = 0) -> Date {
        berlin.date(byAdding: .day, value: offset, to: day0)!.addingTimeInterval(TimeInterval.hours(hours) + .minutes(minutes))
    }

    private func at(_ offset: Int, hours: Double = 0, minutes: Double = 0) -> Date {
        Self.at(offset, hours: hours, minutes: minutes)
    }

    /// 12:01 today
    private let noon = InsulinStatsServiceTests.at(0, hours: 12, minutes: 1)

    private let accuracy = 1E-6

    private final class Fixture: @unchecked Sendable {
        let container: NSPersistentContainer
        let storage: CoreDataStorage
        let source: RecordingSource
        let clock: TestClock
        let coordinator: AppCoordinator
        let statistics: InsulinStatsService

        init(now: Date) {
            container = StatsFixtures.inMemoryContainer()
            storage = CoreDataStorage(container: container)
            source = RecordingSource(storage)
            let clock = TestClock(now: now, calendar: InsulinStatsServiceTests.berlin)
            self.clock = clock
            coordinator = AppCoordinator()
            statistics = InsulinStatsService(
                appCoordinator: coordinator,
                source: source,
                calendar: { clock.calendar },
                now: { clock.now }
            )
        }

        func insert(_ events: [PumpEventRecord]) async throws {
            try await container.performBackgroundTask { context in
                for record in events {
                    CoreDataPumpEventDatabase.apply(record, to: PumpEvent(context: context))
                }
                try context.save()
            }
        }

        func insert(sessions: [PumpSessionValue]) async throws {
            try await container.performBackgroundTask { context in
                for session in sessions {
                    CoreDataPumpEventDatabase.apply(session, to: PumpSession(context: context))
                }
                try context.save()
            }
        }

        func insert(_ schedules: [BasalScheduleRecordValue]) async throws {
            try await container.performBackgroundTask { context in
                for schedule in schedules {
                    let row = BasalScheduleRecord(context: context)
                    row.date = schedule.date
                    row.source = schedule.source.rawValue
                    row.entries = BasalScheduleRecordValue.encode(schedule.entries)
                    row.fingerprint = BasalScheduleRecordValue.fingerprint(schedule.entries)
                }
                try context.save()
            }
        }

        /// `iob` as a decimal string, as the loop stores it (a Decimal column)
        func insert(iob rows: [(date: Date?, iob: String?)]) async throws {
            try await container.performBackgroundTask { context in
                for row in rows {
                    let reason = Reasons(context: context)
                    reason.date = row.date
                    reason.iob = row.iob.map { NSDecimalNumber(string: $0) }
                }
                try context.save()
            }
        }

        func insert(iob points: [IOBPoint]) async throws {
            try await insert(iob: points.map { (date: $0.time, iob: InsulinStatsServiceTests.decimalString($0.iob)) })
        }

        func insert(meals: [MealRow]) async throws {
            try await container.performBackgroundTask { context in
                for meal in meals {
                    let row = NSEntityDescription.insertNewObject(forEntityName: "Meals", into: context)
                    row.setValue(meal.id, forKey: "id")
                    row.setValue(meal.actualDate, forKey: "actualDate")
                    row.setValue(meal.createdAt, forKey: "createdAt")
                    // as `saveMeals` writes them: NSDecimalNumber into the Double columns
                    row.setValue(NSDecimalNumber(string: meal.carbs), forKey: "carbs")
                    row.setValue(NSDecimalNumber(string: meal.fat), forKey: "fat")
                    row.setValue(NSDecimalNumber(string: meal.protein), forKey: "protein")
                    row.setValue(meal.saved, forKey: "savedToFile")
                }
                try context.save()
            }
        }
    }

    /// The IOB as the tests store it: two decimals, read back through the Decimal column.
    private static func decimalString(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func stored(_ value: Double) -> Double {
        NSDecimalNumber(string: decimalString(value)).doubleValue
    }

    /// A stretch of coverage: a closed session of its time, without gaps (a pump one a Dana site, local from its start).
    private func coverage(_ start: Date, _ end: Date, source: PumpEventSource = .pump) -> PumpSessionValue {
        PumpSessionValue(
            id: UUID(),
            source: source,
            plugin: source == .pump ? "Dana" : nil,
            activation: nil,
            start: start,
            localStart: source == .pump ? start : nil,
            lastSeen: end,
            end: end,
            flags: source == .pump ? .site : []
        )
    }

    /// A schedule record: (start "HH:mm", U/h) entries.
    private func schedule(_ date: Date, _ entries: [(String, Double)], source: BasalScheduleSource = .local)
        -> BasalScheduleRecordValue
    {
        BasalScheduleRecordValue(
            date: date,
            source: source,
            entries: entries.map { start, rate in
                let parts = start.split(separator: ":").compactMap { Int($0) }
                return BasalProfileEntry(
                    start: start + ":00",
                    minutes: parts[0] * 60 + parts[1],
                    rate: Decimal(string: String(rate), locale: Locale(identifier: "en_US_POSIX"))!
                )
            }
        )
    }

    /// Everything stored, as the engine takes it.
    private struct History {
        var events: [PumpEventRecord] = []
        var coverage: [PumpSessionValue] = []
        var schedules: [BasalScheduleRecordValue] = []
        var iob: [IOBPoint] = []

        var input: InsulinInput {
            InsulinInput(events: events, coverage: coverage.map(\.coveredInterval), schedules: schedules, iob: iob)
        }
    }

    /// Two weeks of looping up to `end`: temps every 30 min at :15/:45 (some longer than 30 min, so the next one
    /// clips them: also over midnight), a suspension, SMBs, meal boluses, External Insulin, a Nightscout temp inside the
    /// pump coverage, a coverage gap, two schedule records (one within the period), IOB every 5 min across midnight with a
    /// duplicate.
    private func twoWeeks(until end: Date) -> History {
        var history = History()
        history.schedules = [
            schedule(at(-20), [("00:00", 0.8), ("06:00", 1.2), ("18:00", 0.9)]),
            schedule(at(-5, hours: 12), [("00:00", 0.8), ("06:00", 1.4), ("18:00", 0.9)])
        ]
        history.coverage = [
            coverage(at(-14), at(-7, hours: 10)),
            coverage(at(-7, hours: 14), end.addingTimeInterval(-.minutes(3)))
        ]

        let suspension = DateInterval(start: at(-9, hours: 9), end: at(-9, hours: 10.5))
        var start = at(-14, minutes: 15)
        var index = 0
        while start.addingTimeInterval(.minutes(30)) < end {
            defer {
                start = start.addingTimeInterval(.minutes(30))
                index += 1
            }
            guard !suspension.contains(start), index % 4 != 3 else { continue }
            let rate = [0.0, 0.6, 1.1, 2.3, 0.9][index % 5]
            let minutes = index % 5 == 2 ? 45.1 : 30.1
            let isFinal = start.addingTimeInterval(.hours(1)) < end
            history.events.append(temp(start, rate: rate, minutes: minutes, units: isFinal ? rate * 0.5 * 0.97 : nil))
        }
        history.events += [suspend(suspension.start), resume(suspension.end)]

        var day = -14
        while at(day) < end {
            for hour in stride(from: 1.0, to: 24, by: 2) where at(day, hours: hour, minutes: 5) < end {
                history.events.append(bolus(at(day, hours: hour, minutes: 5), 0.3 + Double(day + 14) * 0.01, smb: true))
            }
            for hour in [8.0, 13, 19] where at(day, hours: hour) < end {
                history.events.append(bolus(at(day, hours: hour), 4 + Double(day + 14) * 0.1))
            }
            day += 1
        }
        history.events.append(bolus(at(-6, hours: 21), 2, external: true))
        // inside the pump coverage: never counted
        history.events.append(temp(at(-10, hours: 3), rate: 5, minutes: 30, units: 2.5, source: .nightscout))

        // off the hour: the row before each midnight stands for 3 minutes after it
        var time = at(-14).addingTimeInterval(-.minutes(8))
        var step = 0
        while time < end.addingTimeInterval(-.minutes(2)) {
            let iob = Self.stored(sin(Double(step) / 9) * 1.5 + 0.2)
            history.iob.append(IOBPoint(time: time, iob: iob))
            if step % 288 == 144 {
                // a failed loop's row next to the next loop's
                history.iob.append(IOBPoint(time: time.addingTimeInterval(4), iob: iob))
            }
            time = time.addingTimeInterval(.minutes(5))
            step += 1
        }
        return history
    }

    private func store(_ history: History, in f: Fixture) async throws {
        try await f.insert(history.events)
        try await f.insert(sessions: history.coverage)
        try await f.insert(history.schedules)
        try await f.insert(iob: history.iob)
    }

    /// The whole computation from the raw rows, with the engine alone.
    private func expected(_ period: StatsPeriod, _ history: History, now: Date, calendar: Calendar? = nil) -> InsulinPeriod {
        Engine.period(period, input: history.input, now: now, calendar: calendar ?? Self.berlin)
    }

    private func assertEqual(
        _ actual: InsulinPeriod,
        _ expected: InsulinPeriod,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        func near(_ a: Double?, _ b: Double?, _ what: String) {
            switch (a, b) {
            case let (a?, b?): XCTAssertEqual(a, b, accuracy: accuracy, what, file: file, line: line)
            case (nil, nil): break
            default: XCTFail("\(what): \(String(describing: a)) vs \(String(describing: b))", file: file, line: line)
            }
        }
        XCTAssertEqual(actual.days.count, expected.days.count, "days", file: file, line: line)
        for (a, b) in zip(actual.days, expected.days) {
            let name = "\(b.day.start)"
            XCTAssertEqual(a.day, b.day, file: file, line: line)
            XCTAssertEqual(a.isToday, b.isToday, name, file: file, line: line)
            XCTAssertEqual(a.hasDeliveries, b.hasDeliveries, name, file: file, line: line)
            XCTAssertEqual(a.coveredUntil, b.coveredUntil, name, file: file, line: line)
            XCTAssertEqual(a.profileAssumedBefore, b.profileAssumedBefore, name, file: file, line: line)
            near(a.basal, b.basal, "basal \(name)")
            near(a.smb, b.smb, "smb \(name)")
            near(a.bolus, b.bolus, "bolus \(name)")
            near(a.scheduled, b.scheduled, "scheduled \(name)")
            near(a.zeroBasalSeconds, b.zeroBasalSeconds, "zero basal \(name)")
            near(a.coveredSeconds, b.coveredSeconds, "covered \(name)")
            near(a.negativeIOBSeconds, b.negativeIOBSeconds, "negative IOB \(name)")
            near(a.iobSeconds, b.iobSeconds, "IOB \(name)")
            XCTAssertEqual(a.hours.count, b.hours.count, file: file, line: line)
            for (h, g) in zip(a.hours, b.hours) {
                near(h.basal + h.smb + h.bolus + h.scheduled, g.basal + g.smb + g.bolus + g.scheduled, "hour \(g.hour) \(name)")
                near(h.coveredSeconds + h.iobSeconds, g.coveredSeconds + g.iobSeconds, "hour \(g.hour) \(name)")
            }
        }
        let a = actual.summary
        let b = expected.summary
        XCTAssertEqual(a.window, b.window, file: file, line: line)
        XCTAssertEqual(a.calendarDays, b.calendarDays, file: file, line: line)
        XCTAssertEqual(a.daysWithData, b.daysWithData, file: file, line: line)
        XCTAssertEqual(a.headlineDays, b.headlineDays, file: file, line: line)
        XCTAssertEqual(a.splitPercents, b.splitPercents, file: file, line: line)
        XCTAssertEqual(a.coveragePercent, b.coveragePercent, file: file, line: line)
        XCTAssertEqual(a.isEmpty, b.isEmpty, file: file, line: line)
        XCTAssertEqual(a.profileAssumedBefore, b.profileAssumedBefore, file: file, line: line)
        near(a.tdd, b.tdd, "tdd")
        near(a.basal, b.basal, "summary basal")
        near(a.basalVsScheduled, b.basalVsScheduled, "vs scheduled")
        near(a.scheduledPerDay, b.scheduledPerDay, "scheduled per day")
        near(a.zeroBasalSecondsPerDay, b.zeroBasalSecondsPerDay, "zero basal per day")
        near(a.negativeIOBSecondsPerDay, b.negativeIOBSecondsPerDay, "negative IOB per day")
        XCTAssertEqual(actual.hours.count, expected.hours.count, file: file, line: line)
        for (h, g) in zip(actual.hours, expected.hours) {
            near(h.basal, g.basal, "hours basal \(g.hour)")
            near(h.scheduled, g.scheduled, "hours scheduled \(g.hour)")
            near(h.smb + h.bolus, g.smb + g.bolus, "hours boluses \(g.hour)")
        }
    }

    /// The days the period's event reads covered, from the recorded calls: (from, to) of each `.events` call.
    private func eventReads(_ f: Fixture) async -> [DateInterval] {
        await f.source.calls.filter { $0.fetch == .events }.map(\.range)
    }

    // MARK: - Fetchers

    func testFetchPumpEventsReadsBothSourcesWithoutOtherKindsInChunks() async throws {
        let f = Fixture(now: noon)
        let smb = PumpEventRecord(
            date: at(-10, hours: 3),
            kind: .bolus,
            source: .pump,
            units: 0.35,
            durationMin: 0.2,
            isSMB: true,
            isMutable: true
        )
        let rows = [
            temp(at(-20, hours: 1), rate: 0.6, minutes: 30.1, units: 0.29),
            smb,
            // on a chunk boundary (7 days after the range's start): read once
            bolus(at(-13), 3),
            bolus(at(-12, hours: 9), 1.5, external: true, source: .nightscout),
            suspend(at(-5, hours: 2)),
            resume(at(-5, hours: 3)),
            // at the end: out
            bolus(at(-1), 2)
        ]
        try await f.insert(rows)
        // a coverage row of an earlier build (kind 9), until the store's prune deletes it: no record
        let coverageStart = at(-20)
        try await f.container.performBackgroundTask { context in
            let row = PumpEvent(context: context)
            row.date = coverageStart
            row.kind = 9
            try context.save()
        }

        let events = try await f.storage.fetchPumpEvents(from: at(-20), to: at(-1))
        XCTAssertEqual(
            events.map(\.date),
            [at(-20, hours: 1), at(-13), at(-12, hours: 9), at(-10, hours: 3), at(-5, hours: 2), at(-5, hours: 3)].sorted()
        )
        XCTAssertEqual(events.first { $0.kind == .tempBasal }, rows[0])
        XCTAssertEqual(events.first { $0.isSMB }, smb)
        XCTAssertEqual(events.first { $0.source == .nightscout }?.isExternal, true)
    }

    func testRunningIntoStartsAtTheNewestTempBefore() async throws {
        let f = Fixture(now: noon)
        try await f.insert([
            suspend(at(-3, hours: 1)),
            resume(at(-3, hours: 2)),
            temp(at(-2, hours: 20), rate: 1, minutes: 30.1, units: 0.5),
            temp(at(-1, hours: 22), rate: 2, minutes: 240.1),
            // a suspension after it, and the bolus that ends it
            suspend(at(-1, hours: 23)),
            bolus(at(-1, hours: 23.5), 1),
            // at the date: not before it
            temp(at(0), rate: 3, minutes: 30.1)
        ])
        try await f.insert(sessions: [coverage(at(-3), at(0, hours: 1))])
        let events = try await f.storage.fetchPumpEventsRunningInto(at(0))
        XCTAssertEqual(events.map(\.date), [at(-1, hours: 22), at(-1, hours: 23), at(-1, hours: 23.5)])
        XCTAssertEqual(events.map(\.kind), [.tempBasal, .suspend, .bolus])
    }

    func testRunningIntoWithoutATempStartsAtTheNewestSuspendOrResume() async throws {
        let f = Fixture(now: noon)
        try await f.insert([
            suspend(at(-30)),
            resume(at(-29)),
            suspend(at(-4, hours: 6)),
            bolus(at(-4, hours: 7), 2, external: true),
            bolus(at(-8), 3)
        ])
        let events = try await f.storage.fetchPumpEventsRunningInto(at(0))
        XCTAssertEqual(events.map(\.date), [at(-4, hours: 6), at(-4, hours: 7)])

        // the engine: the suspension runs into the day (the pen doesn't end it)
        let day = Engine.days(
            [DateInterval(start: at(0), end: at(1))],
            input: InsulinInput(
                events: events,
                coverage: [coverage(at(-5), at(0, hours: 6)).coveredInterval],
                schedules: [schedule(at(-40), [("00:00", 1)])]
            ),
            now: at(0, hours: 6),
            calendar: Self.berlin
        )[0]
        XCTAssertEqual(day.basal, 0, accuracy: accuracy)
        XCTAssertEqual(day.zeroBasalSeconds, .hours(6), accuracy: accuracy)

        let none = Fixture(now: noon)
        try await none.insert([bolus(at(-3), 1)])
        let nothing = try await none.storage.fetchPumpEventsRunningInto(at(0))
        XCTAssertEqual(nothing, [])
    }

    /// The anchor is the newest pump temp: a Nightscout temp after it (inside the pump's coverage, where the store
    /// keeps none) doesn't hide it; and the state is looked for within a week only.
    func testRunningIntoAnchorsOnThePumpsTempWithinAWeek() async throws {
        let f = Fixture(now: noon)
        try await f.insert([
            temp(at(-1, hours: 22), rate: 2, minutes: 240.1),
            temp(at(-1, hours: 23), rate: 5, minutes: 30, units: 2.5, source: .nightscout)
        ])
        let events = try await f.storage.fetchPumpEventsRunningInto(at(0))
        XCTAssertEqual(events.map(\.date), [at(-1, hours: 22), at(-1, hours: 23)])
        XCTAssertEqual(events.map(\.source), [.pump, .nightscout])

        // without a pump temp: the newest of any source
        let nightscout = Fixture(now: noon)
        try await nightscout.insert([
            temp(at(-2, hours: 22), rate: 1, minutes: 30, source: .nightscout),
            temp(at(-1, hours: 23), rate: 2, minutes: 30, source: .nightscout)
        ])
        let nightscoutEvents = try await nightscout.storage.fetchPumpEventsRunningInto(at(0))
        XCTAssertEqual(nightscoutEvents.map(\.date), [at(-1, hours: 23)])

        // a suspension more than a week back isn't looked for
        let old = Fixture(now: noon)
        try await old.insert([suspend(at(-8))])
        let none = try await old.storage.fetchPumpEventsRunningInto(at(0))
        XCTAssertEqual(none, [])
    }

    /// Should a Nightscout temp be inside the pump's coverage before a run (the store keeps none there), the engine
    /// drops it: the coverage is read from the running-into state on, so the run sees it as a read from the start does.
    func testANightscoutTempInsideThePumpsCoverageBeforeARunIsDropped() async throws {
        let f = Fixture(now: noon)
        var history = History()
        history.schedules = [schedule(at(-20), [("00:00", 1)])]
        history.coverage = [
            coverage(at(-8), at(-1, hours: 23, minutes: 30)),
            coverage(at(0, minutes: 30), noon.addingTimeInterval(-.minutes(3)))
        ]
        history.events = [
            temp(at(-1, hours: 22), rate: 2, minutes: 60.1, units: 1.9),
            temp(at(-1, hours: 23), rate: 5, minutes: 120, source: .nightscout)
        ]
        try await store(history, in: f)
        _ = try await f.statistics.period(.days7)
        // warm: today read on its own, from its running-into state
        let result = try await f.statistics.period(.days7)
        assertEqual(result, expected(.days7, history, now: noon))
        // the schedule from 00:30 to 11:58, nothing before
        XCTAssertEqual(result.days[6].basal, 11 + 28.0 / 60, accuracy: accuracy)
    }

    /// The coverage is the pump sessions' covered time (both sources), `[start, lastSeen]` without the gaps, clipped to
    /// the range: a session's Nightscout prefix (before its local start) Nightscout's; the sessions read are those
    /// reaching into the range, any row of any time (no lookback).
    func testFetchCoverageFromThePumpSessions() async throws {
        let f = Fixture(now: noon)
        func session(
            _ source: PumpEventSource,
            _ start: Date,
            _ lastSeen: Date,
            localStart: Date? = nil,
            gaps: [DateInterval] = [],
            open: Bool = false
        ) -> PumpSessionValue {
            PumpSessionValue(
                id: UUID(),
                source: source,
                plugin: source == .pump ? "Medtrum" : nil,
                activation: start,
                start: start,
                localStart: source == .pump ? localStart ?? start : nil,
                lastSeen: lastSeen,
                end: open ? nil : lastSeen,
                gaps: gaps
            )
        }
        let sessions = [
            // ends at the start: out
            session(.pump, at(-10), at(-5)),
            // a month long, from long before: its part in the range
            session(
                .pump,
                at(-40),
                at(-4, hours: 2),
                gaps: [DateInterval(start: at(-4, hours: 1), end: at(-4, hours: 1.5))]
            ),
            session(
                .nightscout,
                at(-4, hours: 3),
                at(-3),
                gaps: [DateInterval(start: at(-4, hours: 6), end: at(-4, hours: 7))]
            ),
            // its prefix before the local start: Nightscout's
            session(.pump, at(-3, hours: 12), at(0, hours: 6), localStart: at(-2, hours: 6), open: true),
            // zero-length: nothing
            session(.pump, at(-2, hours: 18), at(-2, hours: 18))
        ]
        try await f.insert(sessions: sessions)
        try await f.insert([bolus(at(-4), 1)])

        let covered = try await f.storage.fetchCoverage(from: at(-5), to: at(-2))
        XCTAssertEqual(covered.filter(\.isCovered), [
            CoveredInterval(interval: DateInterval(start: at(-5), end: at(-4, hours: 1)), source: .pump),
            CoveredInterval(interval: DateInterval(start: at(-4, hours: 1.5), end: at(-4, hours: 2)), source: .pump),
            CoveredInterval(interval: DateInterval(start: at(-4, hours: 3), end: at(-4, hours: 6)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(-4, hours: 7), end: at(-3)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(-3, hours: 12), end: at(-2)), source: .nightscout)
        ])
        // the local time in it: the pump sessions' whole `[localStart, lastSeen]` (of every pump session: the store's
        // rule), the gap too
        XCTAssertEqual(covered.filter { !$0.isCovered }, [
            CoveredInterval(interval: DateInterval(start: at(-5), end: at(-4, hours: 2)), source: .pump, isCovered: false)
        ])
        let later = try await f.storage.fetchCoverage(from: at(-2), to: at(1))
        XCTAssertEqual(later, [
            CoveredInterval(interval: DateInterval(start: at(-2), end: at(-2, hours: 6)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(-2, hours: 6), end: at(0, hours: 6)), source: .pump),
            CoveredInterval(
                interval: DateInterval(start: at(-2, hours: 6), end: at(0, hours: 6)),
                source: .pump,
                isCovered: false
            )
        ])
        let none = try await f.storage.fetchCoverage(from: at(-50), to: at(-45))
        XCTAssertEqual(none, [])

        // the sessions reaching into a range: started before its end, last seen at or after its start
        let read = try await f.storage.fetchPumpSessions(from: at(-5), to: at(-2))
        XCTAssertEqual(Set(read.map(\.id)), Set([sessions[0], sessions[1], sessions[2], sessions[3]].map(\.id)))
        XCTAssertEqual(read.first { $0.id == sessions[1].id }, sessions[1])
    }

    /// The Insulin tab's numbers over the sessions' coverage: a pump session with gaps and a Nightscout one, the
    /// scheduled basal where they cover only, as the engine gives it from the same covered time.
    func testCoverageFromSessionsOfBothSourcesWithGaps() async throws {
        let f = Fixture(now: noon)
        let gap = DateInterval(start: at(-3, hours: 10), end: at(-3, hours: 14))
        let pump = PumpSessionValue(
            id: UUID(),
            source: .pump,
            plugin: "Omni",
            activation: at(-4),
            start: at(-4),
            localStart: at(-4),
            lastSeen: noon.addingTimeInterval(-.minutes(3)),
            end: nil,
            gaps: [gap]
        )
        let nightscout = PumpSessionValue(
            id: UUID(),
            source: .nightscout,
            plugin: "Omni",
            activation: at(-7),
            start: at(-7),
            lastSeen: at(-5, hours: 12),
            end: at(-5, hours: 12),
            flags: .pluginAssumed
        )
        try await f.insert(sessions: [pump, nightscout])
        let schedules = [schedule(at(-20), [("00:00", 1)])]
        try await f.insert(schedules)
        // a Nightscout bolus in the pump's own time: dropped; one in the Nightscout session's: counted
        let events = [bolus(at(-3, hours: 8), 2, source: .nightscout), bolus(at(-6, hours: 8), 3, source: .nightscout)]
        try await f.insert(events)

        let result = try await f.statistics.period(.days7)
        let input = InsulinInput(
            events: events,
            coverage: CoreDataStorage.coverage([pump, nightscout], from: .distantPast, to: .distantFuture),
            schedules: schedules
        )
        assertEqual(result, Engine.period(.days7, input: input, now: noon, calendar: Self.berlin))
        // day -6 the Nightscout session's, day -5 half of it, day -4 the pump's, day -3 the pump's but for the 4 h gap
        XCTAssertEqual(result.days.map(\.day.start).prefix(4), [at(-6), at(-5), at(-4), at(-3)])
        XCTAssertEqual(result.days[0].scheduled, 24, accuracy: accuracy)
        XCTAssertEqual(result.days[1].scheduled, 12, accuracy: accuracy)
        XCTAssertEqual(result.days[2].scheduled, 24, accuracy: accuracy)
        XCTAssertEqual(result.days[3].scheduled, 20, accuracy: accuracy)
        XCTAssertEqual(result.days[0].bolus, 3, accuracy: accuracy)
        XCTAssertEqual(result.days[3].bolus, 0, accuracy: accuracy)
    }

    /// A pump session's Nightscout prefix (before its local start) is Nightscout's coverage: a Nightscout event there
    /// counts; one after its local start, inside the pump's own time, is dropped (the pump's rows are the truth there).
    func testANightscoutEventInAPrefixCountsAndOneAfterTheLocalStartIsDropped() async throws {
        let f = Fixture(now: noon)
        let session = PumpSessionValue(
            id: UUID(),
            source: .pump,
            plugin: "Medtrum",
            activation: at(-3),
            start: at(-3),
            localStart: at(-2),
            lastSeen: noon.addingTimeInterval(-.minutes(3)),
            end: nil
        )
        try await f.insert(sessions: [session])
        let schedules = [schedule(at(-20), [("00:00", 1)])]
        try await f.insert(schedules)
        let inPrefix = bolus(at(-3, hours: 8), 2, source: .nightscout)
        let afterLocal = bolus(at(-2, hours: 8), 3, source: .nightscout)
        try await f.insert([inPrefix, afterLocal])

        let result = try await f.statistics.period(.days7)
        XCTAssertEqual(result.days.map(\.day.start)[3 ... 4], [at(-3), at(-2)])
        XCTAssertEqual(result.days[3].bolus, 2, accuracy: accuracy)
        XCTAssertEqual(result.days[4].bolus, 0, accuracy: accuracy)
        // covered either way: the scheduled basal fills both days
        XCTAssertEqual(result.days[3].scheduled, 24, accuracy: accuracy)
        XCTAssertEqual(result.days[4].scheduled, 24, accuracy: accuracy)
    }

    /// The strict rule on read, as the store's on write (`PumpSessionRules.localTime`): a Nightscout double of a pump
    /// dose a second off it, before the first session's local start (the pump's dose rows are the truth there), and one in
    /// a session's gap are dropped; one between the sessions counts. Each dose once.
    func testNightscoutDoublesInThePumpsLocalTimeCountOnce() async throws {
        let f = Fixture(now: noon)
        let gap = DateInterval(start: at(-1, hours: 10), end: at(-1, hours: 14))
        let first = PumpSessionValue(
            id: UUID(),
            source: .pump,
            plugin: "Omni",
            activation: at(-4),
            start: at(-4),
            localStart: at(-4),
            lastSeen: at(-3),
            end: at(-3)
        )
        let second = PumpSessionValue(
            id: UUID(),
            source: .pump,
            plugin: "Omni",
            activation: at(-2),
            start: at(-2),
            localStart: at(-2),
            lastSeen: noon.addingTimeInterval(-.minutes(3)),
            end: nil,
            gaps: [gap]
        )
        try await f.insert(sessions: [first, second])
        try await f.insert([schedule(at(-20), [("00:00", 1)])])
        try await f.insert([
            // the pump's, before the first session, and its double
            bolus(at(-5, hours: 8), 2),
            bolus(at(-5, hours: 8).addingTimeInterval(1), 2, source: .nightscout),
            // in the second session's gap
            bolus(at(-1, hours: 12), 3, source: .nightscout),
            // between the sessions
            bolus(at(-3, hours: 12), 4, source: .nightscout)
        ])

        let result = try await f.statistics.period(.days7)
        func dayBolus(_ day: Date) -> Double {
            result.days.first { $0.day.start == day }?.bolus ?? -1
        }
        XCTAssertEqual(dayBolus(at(-5)), 2, accuracy: accuracy)
        XCTAssertEqual(dayBolus(at(-3)), 4, accuracy: accuracy)
        XCTAssertEqual(dayBolus(at(-1)), 0, accuracy: accuracy)
    }

    /// One fixture through both sides of the rule: what the backfill stores (`PumpKnowledge.knows`) is exactly what the
    /// read keeps (`fetchCoverage`'s local time, `usableEvents`), at every boundary and a second outside it: the oldest
    /// pump dose, the first local start, a session's `localStart` and `lastSeen`, a zero-length session.
    func testTheBackfillAndTheReadAgreeAtTheBoundaries() async throws {
        let f = Fixture(now: noon)
        let pumpEvents = PumpEventStore(
            appCoordinator: f.coordinator,
            database: CoreDataPumpEventDatabase(container: f.container, mergeBatchDelete: { _ in }),
            calendar: { InsulinStatsServiceTests.berlin },
            now: { f.clock.now }
        )
        func session(_ start: Date, _ lastSeen: Date) -> PumpSessionValue {
            PumpSessionValue(
                id: UUID(),
                source: .pump,
                plugin: "Omni",
                activation: start,
                start: start,
                localStart: start,
                lastSeen: lastSeen,
                end: lastSeen
            )
        }
        let oldest = at(-5)
        let first = (start: at(-4), lastSeen: at(-3))
        let zero = at(-2)
        let last = (start: at(-1), lastSeen: at(-1, hours: 6))
        try await f
            .insert(sessions: [session(first.start, first.lastSeen), session(zero, zero), session(last.start, last.lastSeen)])
        try await f.insert([bolus(oldest, 1)])
        let second: TimeInterval = 1
        let local = [
            oldest,
            first.start.addingTimeInterval(-second),
            first.start,
            first.lastSeen,
            zero,
            last.start,
            last.lastSeen
        ]
        let outside = [
            oldest.addingTimeInterval(-second),
            first.lastSeen.addingTimeInterval(second),
            zero.addingTimeInterval(-second),
            zero.addingTimeInterval(second),
            last.start.addingTimeInterval(-second),
            last.lastSeen.addingTimeInterval(second)
        ]
        // temps: not the pump bolus's identity
        let probes = (local + outside).map { temp($0, rate: 1, minutes: 30, source: .nightscout) }

        let outcome = await pumpEvents.storeBackfill(probes)
        XCTAssertEqual(outcome.skipped, local.count)
        XCTAssertEqual(outcome.recent, 0)
        let stored = try await f.storage.fetchPumpEvents(from: at(-6), to: noon).filter { $0.source == .nightscout }
        XCTAssertEqual(stored.map(\.date), outside.sorted())

        let coverage = try await f.storage.fetchCoverage(from: at(-6), to: noon)
        let kept = InsulinStatsEngine.usableEvents(probes, coverage: coverage).filter { $0.source == .nightscout }
        XCTAssertEqual(kept.map(\.date), outside.sorted())
    }

    func testFetchBasalSchedulesFromTheOneInEffect() async throws {
        let f = Fixture(now: noon)
        let a = schedule(at(-40), [("00:00", 0.5)], source: .nightscout)
        let b = schedule(at(-20), [("00:00", 0.6), ("06:00", 1)])
        let c = schedule(at(-10), [("00:00", 0.7)])
        let d = schedule(at(-3), [("00:00", 0.8)])
        try await f.insert([a, b, c, d])

        var records = try await f.storage.fetchBasalSchedules(from: at(-15), to: at(-3))
        XCTAssertEqual(records, [b, c])
        // a record at `from` is the one in effect
        records = try await f.storage.fetchBasalSchedules(from: at(-10), to: at(0))
        XCTAssertEqual(records, [c, d])
        records = try await f.storage.fetchBasalSchedules(from: at(-50), to: at(-30))
        // before the first record: the oldest one, though it is after the range
        XCTAssertEqual(records, [a])
        records = try await f.storage.fetchBasalSchedules(from: at(-50), to: at(-15))
        XCTAssertEqual(records, [a, b])
        records = try await f.storage.fetchBasalSchedules(from: at(-50), to: at(-40))
        XCTAssertEqual(records, [a])

        let empty = Fixture(now: noon)
        let nothing = try await empty.storage.fetchBasalSchedules(from: at(-5), to: at(0))
        XCTAssertEqual(nothing, [])
    }

    /// The rule the fetcher's oldest record serves: days before the first record get it, flagged.
    func testDaysBeforeTheFirstScheduleUseIt() async throws {
        let f = Fixture(now: noon)
        let first = schedule(at(-2), [("00:00", 1)])
        try await f.insert([first])
        try await f.insert(sessions: [coverage(at(-6), noon)])

        let result = try await f.statistics.period(.days7)
        let days = result.days
        XCTAssertEqual(days[1].profileAssumedBefore, at(-2))
        XCTAssertEqual(days[1].scheduled, 24, accuracy: accuracy)
        XCTAssertNil(days[5].profileAssumedBefore)
        XCTAssertEqual(result.summary.profileAssumedBefore, at(-2))
    }

    func testFetchIOBPointsThroughNSNumber() async throws {
        let f = Fixture(now: noon)
        try await f.insert(iob: [
            (date: at(-9), iob: "-0.35"),
            (date: at(-2, hours: 5), iob: "1.25"),
            (date: nil, iob: "2"),
            (date: at(-2, hours: 6), iob: nil),
            (date: at(-1), iob: "3")
        ])
        let points = try await f.storage.fetchIOBPoints(from: at(-9), to: at(-1))
        XCTAssertEqual(points, [IOBPoint(time: at(-9), iob: -0.35), IOBPoint(time: at(-2, hours: 5), iob: 1.25)])
    }

    func testFetchMealPoints() async throws {
        let f = Fixture(now: noon)
        try await f.insert(meals: [
            (
                id: "a",
                actualDate: at(-3, hours: 8),
                createdAt: at(-3, hours: 8.1),
                carbs: "45.5",
                fat: "12",
                protein: "20",
                saved: true
            ),
            (
                id: "a",
                actualDate: at(-3, hours: 9),
                createdAt: at(-3, hours: 9),
                carbs: "45.5",
                fat: "12",
                protein: "20",
                saved: true
            ),
            (id: "b", actualDate: at(-2, hours: 13), createdAt: nil, carbs: "30", fat: "0", protein: "0", saved: false),
            (
                id: nil,
                actualDate: at(-1, hours: 19),
                createdAt: at(-1, hours: 19),
                carbs: "60",
                fat: "0",
                protein: "0",
                saved: true
            ),
            (id: "c", actualDate: at(0, hours: 13), createdAt: at(0, hours: 7), carbs: "20", fat: "0", protein: "0", saved: true)
        ])
        let points = try await f.storage.fetchMealPoints(from: at(-3), to: at(0, hours: 13))
        XCTAssertEqual(points, [
            MealPoint(id: "a", actualDate: at(-3, hours: 8), createdAt: at(-3, hours: 8.1), carbs: 45.5, fat: 12, protein: 20),
            MealPoint(id: "a", actualDate: at(-3, hours: 9), createdAt: at(-3, hours: 9), carbs: 45.5, fat: 12, protein: 20),
            MealPoint(id: nil, actualDate: at(-1, hours: 19), createdAt: at(-1, hours: 19), carbs: 60)
        ])
    }

    /// The fiber and the micronutrients come with their row: summed by type, joined by the meal (not by its id: a
    /// duplicate keeps its own), an unknown type left out; a preset's definitions (no meal), an unsaved meal's and a
    /// meal outside the range not read.
    func testFetchMealPointsWithTheirNutrients() async throws {
        let f = Fixture(now: noon)
        try await f.container.performBackgroundTask { context in
            func meal(_ id: String, _ date: Date, fiber: String, saved: Bool = true) -> NSManagedObject {
                let row = NSEntityDescription.insertNewObject(forEntityName: "Meals", into: context)
                row.setValue(id, forKey: "id")
                row.setValue(date, forKey: "actualDate")
                row.setValue(NSDecimalNumber(string: "30"), forKey: "carbs")
                row.setValue(NSDecimalNumber(string: fiber), forKey: "fiber")
                row.setValue(saved, forKey: "savedToFile")
                return row
            }
            func micronutrient(_ type: String, _ amount: String, of meal: NSManagedObject?) {
                let row = NSEntityDescription.insertNewObject(forEntityName: "Micronutrient", into: context)
                row.setValue(UUID(), forKey: "id")
                row.setValue(type, forKey: "type")
                row.setValue(NSDecimalNumber(string: amount), forKey: "amount")
                row.setValue(meal, forKey: "meal")
            }
            let lunch = meal("a", InsulinStatsServiceTests.at(-2, hours: 12), fiber: "4.5")
            micronutrient("salt", "1.2", of: lunch)
            micronutrient("salt", "0.3", of: lunch)
            micronutrient("vitaminC", "20", of: lunch)
            micronutrient("chromium", "35", of: lunch)
            // the old Nightscout save's duplicate: the same id, its own rows
            let copy = meal("a", InsulinStatsServiceTests.at(-2, hours: 13), fiber: "0")
            micronutrient("iron", "2", of: copy)
            _ = meal("b", InsulinStatsServiceTests.at(-1, hours: 8), fiber: "0")
            let unsaved = meal("c", InsulinStatsServiceTests.at(-1, hours: 9), fiber: "1", saved: false)
            micronutrient("salt", "5", of: unsaved)
            let before = meal("d", InsulinStatsServiceTests.at(-5, hours: 9), fiber: "1")
            micronutrient("salt", "5", of: before)
            micronutrient("salt", "9", of: nil)
            try context.save()
        }
        let points = try await f.storage.fetchMealPoints(from: at(-3), to: at(0))
        XCTAssertEqual(points.map(\.id), ["a", "a", "b"])
        XCTAssertEqual(points[0].fiber, 4.5, accuracy: accuracy)
        XCTAssertEqual(Set(points[0].micronutrients.keys), [.salt, .vitaminC])
        XCTAssertEqual(points[0].micronutrients[.salt] ?? 0, 1.5, accuracy: accuracy)
        XCTAssertEqual(points[0].micronutrients[.vitaminC] ?? 0, 20, accuracy: accuracy)
        XCTAssertEqual(points[1].micronutrients, [.iron: 2])
        XCTAssertEqual(points[1].fiber, 0)
        XCTAssertTrue(points[1].hasNutrientData)
        XCTAssertEqual(points[2].micronutrients, [:])
        XCTAssertFalse(points[2].hasNutrientData)
    }

    /// A preset's micronutrient goes onto a definition row (no meal), never onto a meal's row of the same name: the
    /// meal's row keeps its type (`micronutrientTotals` and the Statistics read it) and no preset entry, and the
    /// definition is shared by the presets (the restore's by-name path, case-insensitive, included).
    func testPresetMicronutrientNeverTakesAMealsRow() async throws {
        let f = Fixture(now: noon)
        let vitaminC = MicroNutrient.vitaminC
        try await f.container.performBackgroundTask { context in
            let meal = Meals(context: context)
            meal.id = "a"
            meal.actualDate = InsulinStatsServiceTests.at(-1, hours: 12)
            meal.carbs = NSDecimalNumber(string: "30")
            meal.savedToFile = true
            let mealRow = Micronutrient(context: context)
            mealRow.id = UUID()
            mealRow.name = vitaminC.coreDataName
            mealRow.type = vitaminC.rawValue
            mealRow.unit = vitaminC.unit
            mealRow.amount = NSDecimalNumber(string: "20")
            mealRow.meal = meal
            meal.addToMicronutrients(mealRow)
            try context.save()

            let preset = Presets(context: context)
            preset.dish = "Orange"
            try preset.setMicronutrient(vitaminC, amount: 50, per100: true, context: context)
            let restored = Presets(context: context)
            restored.dish = "Orange juice"
            try restored.setMicronutrient(
                name: "vitamin c",
                type: vitaminC.coreDataType,
                unit: vitaminC.unit,
                amount: 30,
                per100: true,
                context: context
            )
            try context.save()

            XCTAssertEqual(mealRow.type, vitaminC.rawValue)
            XCTAssertTrue(mealRow.entries.isEmpty)
            XCTAssertEqual(meal.micronutrientTotals, [.vitaminC: 20])
            let definition = try XCTUnwrap(preset.micronutrient?.first?.micronutrient)
            XCTAssertNil(definition.meal)
            XCTAssertNotEqual(definition.objectID, mealRow.objectID)
            XCTAssertEqual(restored.micronutrient?.first?.micronutrient.objectID, definition.objectID)
            XCTAssertEqual(try Micronutrient.fetchAll(context: context).filter { $0.meal == nil }.count, 1)
        }
        let points = try await f.storage.fetchMealPoints(from: at(-3), to: at(0))
        XCTAssertEqual(points.map(\.micronutrients), [[.vitaminC: 20]])
    }

    // MARK: - Service: the cache

    func testThePeriodIsTheEnginesFromTheRawRowsColdAndWarm() async throws {
        let f = Fixture(now: noon)
        let history = twoWeeks(until: noon)
        try await store(history, in: f)

        for period in [StatsPeriod.days7, .days14] {
            let cold = try await f.statistics.period(period)
            assertEqual(cold, expected(period, history, now: noon))
        }
        await f.source.clearCalls()
        let warm = try await f.statistics.period(.days14)
        assertEqual(warm, expected(.days14, history, now: noon))
        // only today read
        let reads = await eventReads(f)
        XCTAssertEqual(reads, [DateInterval(start: at(0), end: at(1))])
        let runningInto = await f.source.calls.filter { $0.fetch == .runningInto }.map(\.range.start)
        XCTAssertEqual(runningInto, [at(0)])
    }

    /// Home's insulin card: the last 8 days (the 7 before today, and today), the engine's from the raw rows; after the
    /// 7 d period only the day before its first and today are read (the rest from the cache).
    func testTheLastDaysAreTheEnginesFromTheRawRows() async throws {
        let f = Fixture(now: noon)
        let history = twoWeeks(until: noon)
        try await store(history, in: f)

        func expectedDays(_ count: Int) -> [DayInsulin] {
            let days = Engine.lastDays(count, now: noon, calendar: Self.berlin)
            return Engine.days(days, input: history.input, now: noon, calendar: Self.berlin)
        }
        func asPeriod(_ days: [DayInsulin]) -> InsulinPeriod {
            InsulinPeriod(summary: Engine.summary(days, period: nil), days: days, hours: Engine.hours(days))
        }

        let cold = try await f.statistics.days(last: 8)
        XCTAssertEqual(cold.map(\.day.start), (-7 ... 0).map { at($0) })
        XCTAssertEqual(cold.last?.isToday, true)
        assertEqual(asPeriod(cold), asPeriod(expectedDays(8)))
        // Statistics › Insulin › Today: the same days (`usualDays` and today), the summary without a period
        XCTAssertEqual(Engine.usualDays, 7)
        let today = try await f.statistics.today()
        XCTAssertEqual(today.days.map(\.day.start), (-7 ... 0).map { at($0) })
        assertEqual(today, asPeriod(expectedDays(8)))
        XCTAssertEqual(today.summary.calendarDays, 8)
        XCTAssertEqual(today.summary.headlineDays, 7)

        let other = Fixture(now: noon)
        try await store(history, in: other)
        _ = try await other.statistics.period(.days7)
        await other.source.clearCalls()
        let warm = try await other.statistics.days(last: 8)
        assertEqual(asPeriod(warm), asPeriod(expectedDays(8)))
        // the day before the 7 d period's first, and today
        let reads = await eventReads(other)
        XCTAssertEqual(reads, [
            DateInterval(start: at(-7), end: at(-6, hours: 1)),
            DateInterval(start: at(0), end: at(1))
        ])
    }

    func testTodayIsNeverCached() async throws {
        let f = Fixture(now: noon)
        var history = twoWeeks(until: noon)
        try await store(history, in: f)
        _ = try await f.statistics.period(.days7)

        // no signal: today is read again anyway
        let late = bolus(at(0, hours: 11), 5)
        try await f.insert([late])
        history.events.append(late)
        let result = try await f.statistics.period(.days7)
        assertEqual(result, expected(.days7, history, now: noon))
    }

    func testAnIntervalChangeDropsOnlyTheDaysItTouches() async throws {
        let f = Fixture(now: noon)
        var history = twoWeeks(until: noon)
        try await store(history, in: f)
        let before = try await f.statistics.period(.days7)

        // stored without a signal: the cached day stays as it was (a cache hit)
        let added = bolus(at(-3, hours: 12), 7)
        try await f.insert([added])
        var result = try await f.statistics.period(.days7)
        XCTAssertEqual(result.days[3].bolus, before.days[3].bolus, accuracy: accuracy)

        history.events.append(added)
        await f.source.clearCalls()
        await f.statistics.insulinDataChanged(.interval(DateInterval(start: added.date, duration: 0)))
        result = try await f.statistics.period(.days7)
        assertEqual(result, expected(.days7, history, now: noon))
        XCTAssertEqual(result.days[3].bolus, before.days[3].bolus + 7, accuracy: accuracy)
        // that day (11:00-13:00) and today
        let reads = await eventReads(f)
        XCTAssertEqual(reads, [
            DateInterval(start: at(-3), end: at(-2, hours: 1)),
            DateInterval(start: at(0), end: at(1))
        ])
    }

    func testAChangeAtMidnightDropsBothDays() async throws {
        let f = Fixture(now: noon)
        try await store(twoWeeks(until: noon), in: f)
        _ = try await f.statistics.period(.days7)
        await f.source.clearCalls()
        // a temp at 00:20 clips the one running over midnight
        await f.statistics.insulinDataChanged(.interval(DateInterval(start: at(-2, minutes: 20), duration: .minutes(30))))
        _ = try await f.statistics.period(.days7)
        let reads = await eventReads(f)
        XCTAssertEqual(reads, [
            DateInterval(start: at(-3), end: at(-1, hours: 1)),
            DateInterval(start: at(0), end: at(1))
        ])
    }

    /// A profile edit comes as the store's `.interval([edit, now])`: only today is read again.
    func testAProfileEditDropsOnlyToday() async throws {
        let f = Fixture(now: noon)
        var history = twoWeeks(until: noon)
        try await store(history, in: f)
        _ = try await f.statistics.period(.days14)

        let edit = schedule(at(0, hours: 11), [("00:00", 2)])
        try await f.insert([edit])
        history.schedules.append(edit)
        await f.source.clearCalls()
        await f.statistics.insulinDataChanged(.interval(DateInterval(start: noon, duration: 0)))
        let result = try await f.statistics.period(.days14)
        assertEqual(result, expected(.days14, history, now: noon))
        let reads = await eventReads(f)
        XCTAssertEqual(reads, [DateInterval(start: at(0), end: at(1))])
    }

    func testAChangeDuringAReadIsReturnedButNotStored() async throws {
        let f = Fixture(now: noon)
        var history = twoWeeks(until: noon)
        try await store(history, in: f)

        // the past days' events read, held before the request computes them
        let gate = await f.source.gate { $0.fetch == .events && $0.range.start == InsulinStatsServiceTests.at(-6) }
        async let request = f.statistics.period(.days7)
        await f.source.arrival(at: gate)

        let added = bolus(at(-4, hours: 12), 6)
        try await f.insert([added])
        history.events.append(added)
        await f.statistics.insulinDataChanged(.interval(DateInterval(start: added.date, duration: 0)))
        await f.source.open(gate)
        let stale = try await request
        // read before the change
        XCTAssertEqual(stale.days[2].bolus, expected(.days7, history, now: noon).days[2].bolus - 6, accuracy: accuracy)

        await f.source.clearCalls()
        let fresh = try await f.statistics.period(.days7)
        assertEqual(fresh, expected(.days7, history, now: noon))
        // the day it touched was not stored: read again; the others were
        let reads = await eventReads(f)
        XCTAssertEqual(reads, [
            DateInterval(start: at(-4), end: at(-3, hours: 1)),
            DateInterval(start: at(0), end: at(1))
        ])
    }

    /// A wipe (or a time zone change) while a read is in flight: nothing it read is stored (`storeFloor`, the identity).
    func testAWipeOrATimeZoneChangeDuringAReadStoresNothing() async throws {
        for wipe in [true, false] {
            let f = Fixture(now: noon)
            try await store(twoWeeks(until: noon), in: f)
            let gate = await f.source.gate { $0.fetch == .events }
            async let request = f.statistics.period(.days7)
            await f.source.arrival(at: gate)
            if wipe {
                await f.statistics.insulinDataChanged(.all)
            } else {
                f.clock.calendar = StatsFixtures.calendar("Europe/London")
                // noticed by the next change or request, as on a device
                await f.statistics.insulinDataChanged(.interval(DateInterval(start: noon, duration: 0)))
            }
            await f.source.open(gate)
            _ = try await request

            await f.source.clearCalls()
            _ = try await f.statistics.period(.days7)
            let reads = await eventReads(f)
            XCTAssertEqual(reads.count, 1)
            XCTAssertEqual(reads.first?.end, f.clock.calendar.startOfDay(for: noon).addingTimeInterval(.days(1)))
            XCTAssertEqual(reads.first.map { $0.duration > .days(6) }, true)
        }
    }

    func testAFailedReadThrowsAndStoresNothing() async throws {
        let f = Fixture(now: noon)
        let history = twoWeeks(until: noon)
        try await store(history, in: f)

        await f.source.failOnce { $0.fetch == .iob }
        do {
            _ = try await f.statistics.period(.days7)
            XCTFail("a failed read must throw")
        } catch {}

        await f.source.clearCalls()
        let result = try await f.statistics.period(.days7)
        assertEqual(result, expected(.days7, history, now: noon))
        let reads1 = await eventReads(f)
        XCTAssertEqual(reads1, [DateInterval(start: at(-6), end: at(1))])
    }

    func testAllClearsTheCache() async throws {
        let f = Fixture(now: noon)
        try await store(twoWeeks(until: noon), in: f)
        _ = try await f.statistics.period(.days7)
        await f.source.clearCalls()
        await f.statistics.insulinDataChanged(.all)
        _ = try await f.statistics.period(.days7)
        let reads2 = await eventReads(f)
        XCTAssertEqual(reads2, [DateInterval(start: at(-6), end: at(1))])
        XCTAssertEqual(f.coordinator.insulinStatsChanged.value, StatsChange(seq: 1, interval: nil))
    }

    func testAMemoryWarningDropsTheCache() async throws {
        let f = Fixture(now: noon)
        try await store(twoWeeks(until: noon), in: f)
        _ = try await f.statistics.period(.days7)
        await f.source.clearCalls()
        await f.statistics.memoryWarning()
        _ = try await f.statistics.period(.days7)
        let reads3 = await eventReads(f)
        XCTAssertEqual(reads3, [DateInterval(start: at(-6), end: at(1))])
        // nothing changed: nothing published
        XCTAssertEqual(f.coordinator.insulinStatsChanged.value.seq, 0)
    }

    func testMidnightCachesTheDayThatEnded() async throws {
        let late = at(0, hours: 23, minutes: 30)
        let f = Fixture(now: late)
        let history = twoWeeks(until: at(1, hours: 0, minutes: 30))
        try await store(history, in: f)
        _ = try await f.statistics.period(.days7)

        f.clock.now = at(1, minutes: 30)
        await f.source.clearCalls()
        var result = try await f.statistics.period(.days7)
        assertEqual(result, expected(.days7, history, now: at(1, minutes: 30)))
        // the day that was today, with the new today: the days before it stay cached
        let reads4 = await eventReads(f)
        XCTAssertEqual(reads4, [DateInterval(start: at(0), end: at(2))])

        await f.source.clearCalls()
        result = try await f.statistics.period(.days7)
        let reads5 = await eventReads(f)
        XCTAssertEqual(reads5, [DateInterval(start: at(1), end: at(2))])
        assertEqual(result, expected(.days7, history, now: at(1, minutes: 30)))
    }

    func testATimeZoneChangeClearsTheCache() async throws {
        let f = Fixture(now: noon)
        let history = twoWeeks(until: noon)
        try await store(history, in: f)
        _ = try await f.statistics.period(.days7)

        let tokyo = StatsFixtures.calendar("Asia/Tokyo")
        f.clock.calendar = tokyo
        await f.source.clearCalls()
        let result = try await f.statistics.period(.days7)
        assertEqual(result, expected(.days7, history, now: noon, calendar: tokyo))
        let reads = await eventReads(f)
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(reads.first?.start, Engine.periodDays(.days7, now: noon, calendar: tokyo).first?.start)
        XCTAssertEqual(f.coordinator.insulinStatsChanged.value, StatsChange(seq: 1, interval: nil))
    }

    func testOneSeqPerInvalidation() async throws {
        let f = Fixture(now: noon)
        let seen = Recorder<StatsChange>()
        let subscription = f.coordinator.insulinStatsChanged.sink { seen.append($0) }
        defer { subscription.cancel() }

        await f.statistics.start()
        f.coordinator.sendInsulinDataChanged(.interval(DateInterval(start: at(-3, hours: 5), duration: .hours(1))))
        f.coordinator.sendInsulinDataChanged(.all)
        f.coordinator.sendInsulinDataChanged(.interval(DateInterval(start: noon, duration: 0)))
        for _ in 0 ..< 200 where f.coordinator.insulinStatsChanged.value.seq < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(seen.all, [
            StatsChange(seq: 0, interval: nil),
            StatsChange(seq: 1, interval: DateInterval(start: at(-3, hours: 4), end: at(-3, hours: 7))),
            StatsChange(seq: 2, interval: nil),
            StatsChange(seq: 3, interval: DateInterval(start: noon.addingTimeInterval(-.hours(1)), duration: .hours(2)))
        ])
    }

    /// "Profile assumed" days follow the oldest record: a Nightscout import of an older one (its span only from the
    /// imported record on) changes the days before it too.
    func testProfileAssumedDaysFollowANewOldestRecord() async throws {
        let f = Fixture(now: noon)
        var history = twoWeeks(until: noon)
        // the history starts on day -2 (the upgrade): the days before it are assumed
        history.schedules = [schedule(at(-2, hours: 8), [("00:00", 0.9)])]
        try await store(history, in: f)
        let before = try await f.statistics.period(.days7)
        XCTAssertEqual(before.days[0].profileAssumedBefore, at(-2, hours: 8))
        assertEqual(before, expected(.days7, history, now: noon))

        let imported = schedule(at(-4), [("00:00", 0.5), ("12:00", 1.5)], source: .nightscout)
        try await f.insert([imported])
        history.schedules.append(imported)
        // as `PumpEventStore.storeScheduleBackfill` sends it: from the imported record to the first local one
        await f.statistics.insulinDataChanged(.interval(DateInterval(start: imported.date, end: at(-2, hours: 8))))
        let after = try await f.statistics.period(.days7)
        assertEqual(after, expected(.days7, history, now: noon))
        XCTAssertEqual(after.days[0].profileAssumedBefore, at(-4))
        XCTAssertNotEqual(after.days[0].scheduled, before.days[0].scheduled, accuracy: 0.01)
    }

    /// Without any schedule record nothing is filled; the first record (the seed, signalled from now on) fills the past
    /// days too: they were never cached.
    func testDaysReadWithoutAnyScheduleAreNotCached() async throws {
        let f = Fixture(now: noon)
        var history = twoWeeks(until: noon)
        history.schedules = []
        try await store(history, in: f)
        let empty = try await f.statistics.period(.days7)
        XCTAssertEqual(empty.days[2].scheduled, 0)
        assertEqual(empty, expected(.days7, history, now: noon))

        let seed = schedule(noon, [("00:00", 1)])
        try await f.insert([seed])
        history.schedules = [seed]
        await f.statistics.insulinDataChanged(.interval(DateInterval(start: noon, duration: 0)))
        let filled = try await f.statistics.period(.days7)
        XCTAssertGreaterThan(filled.days[2].scheduled, 0)
        assertEqual(filled, expected(.days7, history, now: noon))
    }

    /// The oldest record's entries changed in place (a Nightscout re-import of it, the same start date): its signal
    /// starts at its date, but the "Profile assumed" days before it change too.
    func testProfileAssumedDaysFollowTheOldestRecordChangedInPlace() async throws {
        let f = Fixture(now: noon)
        var history = twoWeeks(until: noon)
        history.schedules = [
            schedule(at(-4), [("00:00", 0.5)], source: .nightscout),
            schedule(at(-2, hours: 8), [("00:00", 0.9)])
        ]
        try await store(history, in: f)
        let before = try await f.statistics.period(.days7)
        XCTAssertEqual(before.days[0].profileAssumedBefore, at(-4))

        let changed = schedule(at(-4), [("00:00", 0.5), ("12:00", 1.5)], source: .nightscout)
        let container = f.container
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<BasalScheduleRecord>(entityName: PumpEventStore.Entity.schedules)
            request.predicate = NSPredicate(format: "date == %@", changed.date as NSDate)
            for row in try context.fetch(request) {
                row.entries = BasalScheduleRecordValue.encode(changed.entries)
                row.fingerprint = BasalScheduleRecordValue.fingerprint(changed.entries)
            }
            try context.save()
        }
        history.schedules[0] = changed
        // as `PumpEventStore.storeScheduleBackfill` sends it: from the record to the first local one
        await f.statistics.insulinDataChanged(.interval(DateInterval(start: changed.date, end: at(-2, hours: 8))))
        let after = try await f.statistics.period(.days7)
        assertEqual(after, expected(.days7, history, now: noon))
        XCTAssertNotEqual(after.days[0].scheduled, before.days[0].scheduled, accuracy: 0.01)
    }

    /// A deleted temp lets the one before it run on, past its own span and the hour around it: the store's change
    /// reaches the next temp (or now), so the day it runs into is read again.
    func testDeletingATempReachesTheDaysItUnclips() async throws {
        let f = Fixture(now: noon)
        let pumpEvents = PumpEventStore(
            appCoordinator: f.coordinator,
            database: CoreDataPumpEventDatabase(container: f.container, mergeBatchDelete: { _ in }),
            calendar: { InsulinStatsServiceTests.berlin },
            now: { f.clock.now }
        )
        let signals = Recorder<InsulinDataChange>()
        let subscription = f.coordinator.insulinDataChanged.sink { signals.append($0) }
        defer { subscription.cancel() }
        await f.statistics.start()

        var history = History()
        history.schedules = [schedule(at(-20), [("00:00", 1)])]
        history.coverage = [coverage(at(-8), noon.addingTimeInterval(-.minutes(3)))]
        let long = temp(at(-2, hours: 22), rate: 2, minutes: 240.1)
        let clip = temp(at(-2, hours: 22, minutes: 30), rate: 0, minutes: 10.1)
        let next = temp(at(-1, hours: 3), rate: 1, minutes: 30.1)
        history.events = [long, clip, next]
        try await store(history, in: f)
        let before = try await f.statistics.period(.days7)

        await pumpEvents.deleted([PumpHistoryEvent(id: "clip", type: .tempBasal, timestamp: clip.date)])
        XCTAssertEqual(signals.all, [.interval(DateInterval(start: clip.date, end: next.date))])
        for _ in 0 ..< 200 where f.coordinator.insulinStatsChanged.value.seq < 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        history.events = [long, next]
        await f.source.clearCalls()
        let after = try await f.statistics.period(.days7)
        assertEqual(after, expected(.days7, history, now: noon))
        // the long temp runs on to 02:00 of the next day now
        XCTAssertEqual(after.days[5].basal - before.days[5].basal, (2 - 1) * 2, accuracy: accuracy)
        // the two days it touches, with today after them
        let reads = await eventReads(f)
        XCTAssertEqual(reads, [DateInterval(start: at(-2), end: at(1))])

        // the newest temp: up to now
        signals.clear()
        await pumpEvents.deleted([PumpHistoryEvent(id: "next", type: .tempBasal, timestamp: next.date)])
        XCTAssertEqual(signals.all, [.interval(DateInterval(start: next.date, end: noon))])
    }

    /// A re-run backfill inserting a missed temp that clips an older one running over midnight, with a newer insert on
    /// another day: the signal is one interval from the oldest change to the newest's reach, so the next day is read
    /// again.
    func testABackfilledTempClippingAnOlderOneReachesTheNextDay() async throws {
        let f = Fixture(now: noon)
        let pumpEvents = PumpEventStore(
            appCoordinator: f.coordinator,
            database: CoreDataPumpEventDatabase(container: f.container, mergeBatchDelete: { _ in }),
            calendar: { InsulinStatsServiceTests.berlin },
            now: { f.clock.now }
        )
        await f.statistics.start()
        var history = History()
        history.schedules = [schedule(at(-30), [("00:00", 1)])]
        let older = temp(at(-4, hours: 21), rate: 1, minutes: 300, source: .nightscout)
        let next = temp(at(-3, hours: 1.5), rate: 0.5, minutes: 30, source: .nightscout)
        history.events = [older, next]
        try await store(history, in: f)
        let before = try await f.statistics.period(.days7)

        let missed = temp(at(-4, hours: 22), rate: 3, minutes: 30, source: .nightscout)
        let newer = bolus(at(-1, hours: 12), 2, source: .nightscout)
        let signals = Recorder<InsulinDataChange>()
        let subscription = f.coordinator.insulinDataChanged.sink { signals.append($0) }
        defer { subscription.cancel() }
        _ = await pumpEvents.storeBackfill([older, missed, next, newer])
        guard case let .interval(changed)? = signals.all.last, signals.all.count == 1 else {
            return XCTFail("one change: \(signals.all)")
        }
        XCTAssertLessThanOrEqual(changed.start, missed.date)
        XCTAssertGreaterThanOrEqual(changed.end, next.date)
        for _ in 0 ..< 200 where f.coordinator.insulinStatsChanged.value.seq < 1 {
            try await Task.sleep(for: .milliseconds(10))
        }

        history.events += [missed, newer]
        let after = try await f.statistics.period(.days7)
        assertEqual(after, expected(.days7, history, now: noon))
        // the older temp no longer runs from midnight to 01:30 of the next day
        XCTAssertEqual(before.days[3].basal - after.days[3].basal, 1.5, accuracy: accuracy)
    }

    // MARK: - Provider

    /// Today and 24 h are mapped to 7 d (the Meals tab's Today is computed as it, the Insulin tab's labelled with it:
    /// its days are `InsulinStatsService.today`'s) and shown as Today.
    func testTodayAnd24hAreComputedAs7Days() {
        XCTAssertEqual(Stat.Provider.insulinAndMealsShownPeriod(.today), .today)
        XCTAssertEqual(Stat.Provider.insulinAndMealsShownPeriod(.last24h), .today)
        XCTAssertEqual(Stat.Provider.insulinAndMealsPeriod(.today), .days7)
        XCTAssertEqual(Stat.Provider.insulinAndMealsPeriod(.last24h), .days7)
        XCTAssertEqual(Stat.Provider.insulinAndMealsPeriod(.days14), .days14)
        XCTAssertEqual(Stat.Provider.insulinAndMealsPeriod(.days90), .days90)
        XCTAssertEqual(Stat.Provider.insulinAndMealsPeriod(.weeks5), .days30)
        XCTAssertEqual(Stat.Provider.insulinAndMealsPeriod(.weeks13), .days90)
    }

    func testMealsReadTheLast90DaysForEveryPeriod() async throws {
        let range = Stat.Provider.mealsRange(.days7, now: noon, calendar: Self.berlin)
        XCTAssertEqual(range, DateInterval(start: at(-89), end: at(1)))

        let f = Fixture(now: noon)
        try await f.insert(meals: [
            // fat 80 days ago: the tiles are shown on 7 d too
            (id: "old", actualDate: at(-80, hours: 12), createdAt: nil, carbs: "10", fat: "20", protein: "30", saved: true),
            (id: "a", actualDate: at(-2, hours: 8), createdAt: nil, carbs: "40", fat: "0", protein: "0", saved: true),
            (id: "a", actualDate: at(-2, hours: 8.5), createdAt: nil, carbs: "40", fat: "0", protein: "0", saved: true),
            (id: "b", actualDate: at(-1, hours: 19), createdAt: nil, carbs: "60", fat: "0", protein: "0", saved: true),
            (id: "c", actualDate: at(0, hours: 7), createdAt: nil, carbs: "30", fat: "0", protein: "0", saved: true)
        ])
        let points = try await f.storage.fetchMealPoints(from: range.start, to: range.end)
        let result = Stat.Provider.mealsResult(points, period: .days7, factor: 0.5, now: noon, calendar: Self.berlin)
        XCTAssertEqual(result.period, .days7)
        XCTAssertEqual(result.meals.days.count, 7)
        XCTAssertEqual(result.labels.count, 7)
        XCTAssertTrue(result.meals.summary.logsFatOrProtein)
        // the complete days with entries: day -2 (once) and day -1; today not averaged
        XCTAssertEqual(result.meals.summary.daysWithEntries, 2)
        XCTAssertEqual(result.meals.summary.carbsPerDay ?? 0, 50, accuracy: accuracy)
        XCTAssertEqual(result.meals.days[6].carbs, 30, accuracy: accuracy)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Meals signal

    func testMealsChangedGrowsByOnePerChangeAcrossSenders() async {
        let coordinator = AppCoordinator()
        let seen = Recorder<Int>()
        let subscription = coordinator.mealsChanged.sink { seen.append($0) }
        defer { subscription.cancel() }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { coordinator.sendMealsChanged() }
            }
        }
        XCTAssertEqual(seen.all, Array(0 ... 100))
    }

    /// A subscriber sending again (a misuse) nests instead of deadlocking.
    func testMealsChangedSentFromASubscriberDoesNotDeadlock() {
        let coordinator = AppCoordinator()
        let seen = Recorder<Int>()
        let subscription = coordinator.mealsChanged.sink { value in
            seen.append(value)
            if value == 1 {
                coordinator.sendMealsChanged()
            }
        }
        defer { subscription.cancel() }
        coordinator.sendMealsChanged()
        XCTAssertEqual(seen.all, [0, 1, 2])
    }

    func testCarbsStorageSendsMealsChangedOnlyWhenSomethingChanged() async throws {
        let files = BaseFileStorage()
        let coordinator = AppCoordinator()
        let file = "test-carbs-\(UUID().uuidString).json"
        let carbs = BaseCarbsStorage(
            storage: files,
            settingsManager: BaseSettingsManager(storage: files, appCoordinator: coordinator),
            appCoordinator: coordinator,
            mealRows: CountingMealRows(),
            carbsFile: file
        )
        let now = Date().truncatedToSecond
        let downloaded = CarbsEntry(
            id: "65f0c0ffee0000000000abcd", createdAt: now.addingTimeInterval(-.hours(1)),
            actualDate: now.addingTimeInterval(-.hours(1)), carbs: 30, fat: 0, protein: 0, fiber: nil, note: nil,
            enteredBy: "Trio", isFPU: false
        )

        await carbs.storeDownloadedCarbs([downloaded])
        XCTAssertEqual(coordinator.mealsChanged.value, 1)
        // the next poll fetches the same 24 h: nothing changed, nothing sent
        await carbs.storeDownloadedCarbs([downloaded])
        await carbs.storeDownloadedCarbs([])
        XCTAssertEqual(coordinator.mealsChanged.value, 1)

        let meal = CarbsEntry(
            id: UUID().uuidString, createdAt: now.addingTimeInterval(-.minutes(10)),
            actualDate: now.addingTimeInterval(-.minutes(10)), carbs: 20, fat: 0, protein: 0, fiber: nil, note: nil,
            enteredBy: CarbsEntry.manual, isFPU: false
        )
        await carbs.storeMeal(meal)
        XCTAssertEqual(coordinator.mealsChanged.value, 2)
        // a replaced meal: once
        let edited = CarbsEntry(
            id: meal.id, createdAt: now.addingTimeInterval(-.minutes(5)),
            actualDate: now.addingTimeInterval(-.minutes(10)), carbs: 25, fat: 0, protein: 0, fiber: nil, note: nil,
            enteredBy: CarbsEntry.manual, isFPU: false
        )
        await carbs.replaceMeal(createdAt: meal.createdAt, with: edited)
        XCTAssertEqual(coordinator.mealsChanged.value, 3)
        await carbs.deleteCarbsAndFPUs(at: edited.createdAt)
        XCTAssertEqual(coordinator.mealsChanged.value, 4)
        // nothing there to delete
        await carbs.deleteCarbsAndFPUs(at: edited.createdAt)
        XCTAssertEqual(coordinator.mealsChanged.value, 4)

        await files.remove(file)
    }

    // MARK: - Timing

    /// 90 days of a 1-minute looper: 129 600 `Reasons` rows, 51 840 pump events (a temp and an SMB every 5 minutes).
    /// Targets (simulator): a cold 90 d under 1 s, a warm one (after a change of today) under 50 ms. The test build is
    /// unoptimized (Debug, -Onone): there it only checks for a gross regression, and prints both.
    func testTiming90DaysWith130kReasons() async throws {
        let now = noon
        let f = Fixture(now: now)
        let start = at(-89)
        try await f.insert([schedule(at(-100), [("00:00", 0.8), ("06:00", 1.2), ("18:00", 0.9)])])
        try await f.insert(sessions: [coverage(at(-95), now.addingTimeInterval(-.minutes(1)))])

        // built inside the background task: the dictionaries aren't Sendable
        let counts = try await f.container.performBackgroundTask { context -> (events: Int, reasons: Int) in
            var events: [[String: Any]] = []
            var time = start
            var index = 0
            while time < now {
                events.append([
                    "date": time, "kind": NSNumber(value: PumpEventKind.tempBasal.rawValue),
                    "source": NSNumber(value: PumpEventSource.pump.rawValue), "rate": NSNumber(value: Double(index % 7) * 0.3),
                    "durationMin": NSNumber(value: 30.1), "units": NSNumber(value: Double(index % 7) * 0.025)
                ])
                events.append([
                    "date": time.addingTimeInterval(20), "kind": NSNumber(value: PumpEventKind.bolus.rawValue),
                    "source": NSNumber(value: PumpEventSource.pump.rawValue), "units": NSNumber(value: 0.1),
                    "isSMB": NSNumber(value: true)
                ])
                time = time.addingTimeInterval(.minutes(5))
                index += 1
            }
            var reasons: [[String: Any]] = []
            time = start
            index = 0
            while time < now {
                reasons.append([
                    "date": time,
                    "iob": NSDecimalNumber(string: InsulinStatsServiceTests.decimalString(sin(Double(index) / 50)))
                ])
                time = time.addingTimeInterval(.minutes(1))
                index += 1
            }
            _ = try context.execute(NSBatchInsertRequest(entityName: PumpEventStore.Entity.events, objects: events))
            _ = try context.execute(NSBatchInsertRequest(entityName: "Reasons", objects: reasons))
            return (events.count, reasons.count)
        }
        XCTAssertGreaterThanOrEqual(counts.reasons, 128_000)
        XCTAssertGreaterThanOrEqual(counts.events, 51000)

        var clock = ContinuousClock.now
        let cold = try await f.statistics.period(.days90)
        let coldTime = ContinuousClock.now - clock
        XCTAssertEqual(cold.days.count, 90)
        XCTAssertEqual(cold.summary.headlineDays, 89)

        await f.statistics.insulinDataChanged(.interval(DateInterval(start: now, duration: 0)))
        await f.source.clearCalls()
        clock = ContinuousClock.now
        let warm = try await f.statistics.period(.days90)
        let warmTime = ContinuousClock.now - clock
        assertEqual(warm, cold)
        let reads6 = await eventReads(f)
        XCTAssertEqual(reads6, [DateInterval(start: at(0), end: at(1))])

        let coldSeconds = Double(coldTime.components.seconds) + Double(coldTime.components.attoseconds) / 1E18
        let warmSeconds = Double(warmTime.components.seconds) + Double(warmTime.components.attoseconds) / 1E18
        print("Insulin statistics timing: cold 90 d \(coldSeconds) s, warm 90 d \(warmSeconds) s")
        #if DEBUG
            XCTAssertLessThan(coldSeconds, 5)
            XCTAssertLessThan(warmSeconds, 0.25)
        #else
            XCTAssertLessThan(coldSeconds, 1)
            XCTAssertLessThan(warmSeconds, 0.05)
        #endif
    }
}
