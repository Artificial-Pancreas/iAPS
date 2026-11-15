import CoreData
@testable import FreeAPS
import XCTest

final class CGMSessionStoreTests: XCTestCase {
    /// 2026-10-20 12:00 Europe/Berlin (CEST)
    private static let t0 = StatsFixtures.day0.addingTimeInterval(.hours(12))

    /// `t0` plus the minutes
    private func at(_ minutes: Double) -> Date {
        Self.t0.addingTimeInterval(.minutes(minutes))
    }

    private static let all = DateInterval(start: .distantPast, end: .distantFuture)

    private func g7(sensor minutes: Double?, id: String? = "G7-A") -> CGMSnapshot {
        CGMSnapshot(
            plugin: "G7CGMManager",
            cgmId: "dexcomG7",
            name: "Dexcom G7",
            sensorStart: minutes.map { at($0) },
            expectedLife: .days(10),
            oneMinute: false,
            sensorId: id
        )
    }

    private func libre(sensor minutes: Double?, oneMinute: Bool = false) -> CGMSnapshot {
        CGMSnapshot(
            plugin: "LibreLoopCGMManager",
            cgmId: "libre3",
            name: "Libre 3",
            sensorStart: minutes.map { at($0) },
            expectedLife: .days(14),
            oneMinute: oneMinute,
            sensorId: nil
        )
    }

    private let nightscout = CGMSnapshot(
        plugin: "NightscoutRemoteCGM",
        cgmId: "nightscout",
        name: "Nightscout",
        sensorStart: nil,
        expectedLife: nil,
        oneMinute: false,
        sensorId: nil
    )

    private func event(
        _ kind: CGMSessionEvent.Kind = .updated,
        _ cgm: CGMSnapshot?,
        at minutes: Double,
        lastReading: Double? = nil
    ) -> CGMSessionEvent {
        CGMSessionEvent(kind: kind, cgm: cgm, at: at(minutes), lastReadingAt: lastReading.map { at($0) })
    }

    /// A `.sensorStart` event at the minutes
    private func started(_ minutes: Double, warmup: TimeInterval? = nil, id: String? = nil) -> CGMSessionEvent.Kind {
        .sensorStarted(CGMSessionEvent.SensorStart(date: at(minutes), warmup: warmup, sensorId: id))
    }

    private func store(_ container: NSPersistentContainer) -> CGMSessionStore {
        CGMSessionStore(container: container, now: { [t0 = Self.t0] in t0 })
    }

    private func rows(_ store: CGMSessionStore) async -> [CGMSessionRecord] {
        await store.sessions(in: Self.all)
    }

    private func spans(_ sessions: [CGMSessionRecord]) -> [[Date?]] {
        sessions.map { [$0.start, $0.end] }
    }

    // MARK: - Opening and closing

    /// The first run after the upgrade: the current sensor's session starts at its sensor start, so its readings are
    /// attributed; without one (or one in the future: a G7 warming up) it starts now.
    func testFirstSessionStartsAtTheSensorStartElseNow() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -3000), at: 0))
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), nil]])
        XCTAssertEqual(sessions.first?.plugin, "G7CGMManager")
        XCTAssertEqual(sessions.first?.cgmId, "dexcomG7")
        XCTAssertEqual(sessions.first?.name, "Dexcom G7")
        XCTAssertEqual(sessions.first?.sensorStart, at(-3000))
        XCTAssertEqual(sessions.first?.expectedLife, TimeInterval.days(10))
        XCTAssertEqual(sessions.first?.sensorId, "G7-A")

        let sensorless = store(StatsFixtures.inMemoryContainer())
        await sensorless.apply(event(.manager, nightscout, at: 0))
        let nightscoutSessions = await rows(sensorless)
        XCTAssertEqual(spans(nightscoutSessions), [[at(0), nil]])

        let warmingUp = store(StatsFixtures.inMemoryContainer())
        await warmingUp.apply(event(.manager, g7(sensor: 20), at: 0))
        let warmingUpSessions = await rows(warmingUp)
        XCTAssertEqual(spans(warmingUpSessions), [[at(0), nil]])
        XCTAssertEqual(warmingUpSessions.first?.sensorStart, at(20))
    }

    /// A relaunch restores the same manager and sensor: a new store on the same rows adds and changes nothing.
    func testRelaunchWithTheSameManagerAndSensorAddsNothing() async {
        let container = StatsFixtures.inMemoryContainer()
        let first = store(container)
        await first.apply(event(.manager, g7(sensor: -3000), at: 0))
        await first.apply(event(.updated, g7(sensor: -3000), at: 5))
        let before = await rows(first)

        let relaunched = store(container)
        await relaunched.apply(event(.manager, g7(sensor: -3000), at: 600))
        await relaunched.apply(event(started(-3000), g7(sensor: -3000), at: 601))
        let after = await rows(relaunched)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.count, 1)
    }

    /// The session start moving within the tolerance (30 min) is the same sensor; beyond it, a new sensor: the old
    /// session closes at the new sensor start, which the new one starts at.
    func testSessionStartWithinToleranceAddsNothingBeyondItOpensANewSession() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -3000, id: nil), at: 0))
        await s.apply(event(.updated, g7(sensor: -2970, id: nil), at: 10))
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), nil]])
        XCTAssertEqual(sessions.first?.sensorStart, at(-3000))

        await s.apply(event(.updated, g7(sensor: 100, id: nil), at: 130))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), at(100)], [at(100), nil]])
        XCTAssertEqual(sessions.last?.sensorStart, at(100))
    }

    /// A sensor change of the same CGM by a `.sensorStart` event (a new sensor id and start): the old session closes at
    /// the new sensor's start. An event without the manager's own start dates the sensor by the event.
    func testSensorChangeMidCGMClosesAtTheNewSensorStart() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -3000, id: "A"), at: 0))
        await s.apply(event(started(200), g7(sensor: 230, id: "B"), at: 240))
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), at(230)], [at(230), nil]])
        XCTAssertEqual(sessions.map(\.sensorId), ["A", "B"])

        await s.apply(event(started(5000), g7(sensor: nil, id: nil), at: 5010))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), at(230)], [at(230), at(5000)], [at(5000), nil]])
        XCTAssertEqual(sessions.last?.sensorStart, at(5000))
        XCTAssertNil(sessions.last?.sensorId)
    }

    /// A new sensor id alone (the starts unknown) is a new sensor, opened now.
    func testNewSensorIdOpensASessionNow() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: nil, id: "A"), at: 0))
        await s.apply(event(.updated, g7(sensor: nil, id: "B"), at: 60))
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(0), at(60)], [at(60), nil]])
    }

    /// G7 to Libre: the G7 gave the readings until the switch, so it closes then and the Libre opens then, though its
    /// sensor started two days ago.
    func testCGMSwitchClosesAndOpensAtTheSwitch() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -5000), at: 0))
        await s.apply(event(.manager, libre(sensor: -2880), at: 300))
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-5000), at(300)], [at(300), nil]])
        XCTAssertEqual(sessions.map(\.cgmId), ["dexcomG7", "libre3"])
        XCTAssertEqual(sessions.last?.sensorStart, at(-2880))
    }

    /// An AppGroup CGM's source app is unknown until its first reading: filled in place; another app is another CGM.
    func testUnknownCGMIdFillsInPlaceAndAnotherOneSwitches() async {
        let s = store(StatsFixtures.inMemoryContainer())
        var appGroup = nightscout
        appGroup.plugin = "AppGroupCGM"
        appGroup.cgmId = nil
        await s.apply(event(.manager, appGroup, at: 0))
        appGroup.cgmId = "xDrip4iOS"
        await s.apply(event(.updated, appGroup, at: 5))
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(0), nil]])
        XCTAssertEqual(sessions.first?.cgmId, "xDrip4iOS")

        appGroup.cgmId = "Juggluco"
        await s.apply(event(.updated, appGroup, at: 60))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(0), at(60)], [at(60), nil]])
        XCTAssertEqual(sessions.map(\.cgmId), ["xDrip4iOS", "Juggluco"])
    }

    /// Removal closes the open session now; no session until a manager is set, which starts at its sensor start only
    /// if that is after the removal.
    func testRemovalClosesAndTheNextManagerStartsNoEarlierThanIt() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -3000), at: 0))
        await s.apply(event(.manager, nil, at: 100))
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), at(100)]])

        await s.apply(event(.manager, libre(sensor: 50), at: 200))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), at(100)], [at(200), nil]])

        await s.apply(event(.manager, nil, at: 300))
        await s.apply(event(.manager, libre(sensor: 350), at: 400))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), at(100)], [at(200), at(300)], [at(350), nil]])
    }

    /// Same CGM and sensor: `oneMinute`, `expectedLife` and `sensorId` change in place; a nil keeps the stored value.
    func testSameSensorUpdatesTheOtherFieldsInPlace() async throws {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, libre(sensor: -600), at: 0))
        let opened = await rows(s).first
        let id = try XCTUnwrap(opened?.id)

        var changed = libre(sensor: -600, oneMinute: true)
        changed.expectedLife = .days(15)
        changed.sensorId = "3MH00"
        await s.apply(event(.updated, changed, at: 10))
        var sessions = await rows(s)
        XCTAssertEqual(sessions.map(\.id), [id])
        XCTAssertEqual(sessions.first?.oneMinute, true)
        XCTAssertEqual(sessions.first?.expectedLife, TimeInterval.days(15))
        XCTAssertEqual(sessions.first?.sensorId, "3MH00")

        changed.expectedLife = nil
        changed.sensorId = nil
        changed.sensorStart = nil
        await s.apply(event(.updated, changed, at: 20))
        sessions = await rows(s)
        XCTAssertEqual(sessions.map(\.id), [id])
        XCTAssertEqual(sessions.first?.expectedLife, TimeInterval.days(15))
        XCTAssertEqual(sessions.first?.sensorId, "3MH00")
        XCTAssertEqual(sessions.first?.sensorStart, at(-600))
    }

    /// A first sensor start for a session opened without one: the same sensor when it is not later than the session's
    /// start (beyond the tolerance), else a sensor started inside the session.
    func testFirstKnownSensorStartFillsInOrOpens() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: nil, id: nil), at: 0))
        await s.apply(event(.updated, g7(sensor: -2000, id: nil), at: 5))
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(0), nil]])
        XCTAssertEqual(sessions.first?.sensorStart, at(-2000))

        let later = store(StatsFixtures.inMemoryContainer())
        await later.apply(event(.manager, g7(sensor: nil, id: nil), at: 0))
        await later.apply(event(.updated, g7(sensor: 90, id: nil), at: 100))
        sessions = await rows(later)
        XCTAssertEqual(spans(sessions), [[at(0), at(90)], [at(90), nil]])
    }

    /// The clock set back: a session never closes before its start, and the next never starts before it.
    func testClockSetBackNeverClosesBeforeTheStart() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, nightscout, at: 100))
        await s.apply(event(.manager, libre(sensor: nil), at: 50))
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(100), at(100)], [at(100), nil]])
    }

    /// Two open sessions (never written by the rules): the earlier closes at the later's start.
    func testTwoOpenSessionsAreRepaired() {
        let a = CGMSessionRecord(id: UUID(), start: at(0), g7(sensor: 0))
        let b = CGMSessionRecord(id: UUID(), start: at(100), g7(sensor: 100))
        let writes = CGMSessionRules.changes(for: g7(sensor: 100), sessions: [b, a], now: at(200), newID: UUID())
        XCTAssertEqual(writes.map(\.id), [a.id])
        XCTAssertEqual(writes.first?.end, at(100))
    }

    /// The Settings wipe: every row goes, and the current CGM's session opens again as on the first run.
    func testWipeOpensTheCurrentSessionAgain() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, nightscout, at: -500))
        await s.apply(event(.manager, g7(sensor: -3000), at: -100))
        await s.wipe()
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), nil]])
        XCTAssertEqual(sessions.first?.cgmId, "dexcomG7")
    }

    /// The events recorded before `start()` wait in the stream and are applied in order.
    func testRecordedEventsAreAppliedInOrder() async throws {
        let s = store(StatsFixtures.inMemoryContainer())
        s.record(event(.manager, nightscout, at: 0))
        s.record(event(.manager, libre(sensor: nil), at: 10))
        s.record(event(.manager, nil, at: 20))
        await s.start()
        let deadline = Date().addingTimeInterval(5)
        var sessions = await rows(s)
        while sessions.count < 2 || sessions.last?.end == nil {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
            sessions = await rows(s)
        }
        XCTAssertEqual(spans(sessions), [[at(0), at(10)], [at(10), at(20)]])
    }

    /// The reader: the sessions overlapping the interval, an open one reaching to the future.
    func testSessionsInAnIntervalAreTheOverlappingOnes() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, nightscout, at: 0))
        await s.apply(event(.manager, libre(sensor: nil), at: 100))
        await s.apply(event(.manager, g7(sensor: nil), at: 200))
        let before = await s.sessions(in: DateInterval(start: at(-50), end: at(0)))
        XCTAssertEqual(before, [])
        let first = await s.sessions(in: DateInterval(start: at(-50), end: at(50)))
        XCTAssertEqual(first.map(\.cgmId), ["nightscout"])
        let boundary = await s.sessions(in: DateInterval(start: at(100), end: at(150)))
        XCTAssertEqual(boundary.map(\.cgmId), ["libre3"])
        let open = await s.sessions(in: DateInterval(start: at(10000), end: at(10001)))
        XCTAssertEqual(open.map(\.cgmId), ["dexcomG7"])
        let all = await s.sessions(in: DateInterval(start: at(50), end: at(250)))
        XCTAssertEqual(all.map(\.cgmId), ["nightscout", "libre3", "dexcomG7"])
    }

    /// LibreTransmitter sends the `.sensorStart` event before its observables (the session start, the serial) are the
    /// new sensor's: the event's date and id replace the stale state. The stale state's later updates change nothing;
    /// the new sensor's own state (its serial, its start within seconds) fills in the same session.
    func testSensorStartEventReplacesAStaleState() async {
        let s = store(StatsFixtures.inMemoryContainer())
        var old = libre(sensor: -14000)
        old.plugin = "LibreTransmitterManagerV3"
        old.sensorId = "serial-A"
        await s.apply(event(.manager, old, at: 0))
        await s.apply(event(started(100, warmup: .hours(1), id: "uid-B"), old, at: 110, lastReading: 95))
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-14000), at(100)], [at(100), nil]])
        XCTAssertEqual(sessions.last?.sensorStart, at(100))
        XCTAssertEqual(sessions.last?.sensorId, "uid-B")

        await s.apply(event(.updated, old, at: 112, lastReading: 95))
        let unchanged = await rows(s)
        XCTAssertEqual(unchanged, sessions)

        // a stale state's other fields are merged; its start and id stay ignored
        var staleChanged = old
        staleChanged.oneMinute = true
        staleChanged.expectedLife = .days(15)
        await s.apply(event(.updated, staleChanged, at: 114, lastReading: 95))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-14000), at(100)], [at(100), nil]])
        XCTAssertEqual(sessions.last?.oneMinute, true)
        XCTAssertEqual(sessions.last?.expectedLife, TimeInterval.days(15))
        XCTAssertEqual(sessions.last?.sensorStart, at(100))
        XCTAssertEqual(sessions.last?.sensorId, "uid-B")

        var fresh = old
        fresh.sensorStart = at(100).addingTimeInterval(40)
        fresh.sensorId = "serial-B"
        await s.apply(event(.updated, fresh, at: 120, lastReading: 115))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-14000), at(100)], [at(100), nil]])
        XCTAssertEqual(sessions.last?.sensorStart, at(100))
        XCTAssertEqual(sessions.last?.sensorId, "serial-B")
    }

    /// A G7's session start is the warm-up's end: a sensor start event at the activation agrees with it (the warm-up
    /// plus the tolerance), so the manager's start is kept and its later states compare equal.
    func testSensorStartEventAgreeingWithTheWarmupEndKeepsTheManagersStart() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -5000, id: "A"), at: -4000))
        await s.apply(event(started(0, warmup: .minutes(60), id: "serial-B"), g7(sensor: 60, id: "B"), at: 10))
        await s.apply(event(.updated, g7(sensor: 60, id: "B"), at: 70))
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-5000), at(10)], [at(10), nil]])
        XCTAssertEqual(sessions.last?.sensorStart, at(60))
        XCTAssertEqual(sessions.last?.sensorId, "B")
    }

    /// A new sensor started ahead (a pre-soaked G7, a Libre 3 activated a day early): its session starts just after
    /// the old sensor's last reading, which stays the old session's. One that started after that reading (the app was
    /// down) keeps its start.
    func testNewSensorStartsAfterTheOldSensorsLastReading() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -14000, id: "A"), at: 0))
        // the reading's date is sub-second; the stored readings are truncated to the second
        let lastReading = at(300).addingTimeInterval(0.7)
        let presoaked = g7(sensor: -600, id: "B")
        await s.apply(CGMSessionEvent(kind: .updated, cgm: presoaked, at: at(310), lastReadingAt: lastReading))
        var sessions = await rows(s)
        let split = at(300).addingTimeInterval(CGMSessionRules.afterLastReading)
        XCTAssertEqual(spans(sessions), [[at(-14000), split], [split, nil]])
        XCTAssertEqual(sessions.last?.sensorStart, at(-600))
        let attribution = CGMSessionAttribution.attribute([reading(299), reading(300), reading(305)], to: sessions)
        XCTAssertEqual(attribution.bySession.map { $0.readings.map(\.time) }, [[at(299), at(300)], [at(305)]])

        await s.apply(event(.updated, g7(sensor: 1000, id: "C"), at: 1500, lastReading: 800))
        sessions = await rows(s)
        XCTAssertEqual(sessions.last?.start, at(1000))
        XCTAssertEqual(sessions.dropLast().last?.end, at(1000))
    }

    /// A G6 transmitter swap mid-sensor (the ids differ, the sensor start doesn't): no new session; the ids decide only
    /// while a start is unknown.
    func testDifferentSensorIdsWithTheSameStartAreTheSameSensor() async {
        let s = store(StatsFixtures.inMemoryContainer())
        var g6 = g7(sensor: -3000, id: "8G1")
        g6.plugin = "G6CGMManager"
        g6.cgmId = "dexcomG6"
        await s.apply(event(.manager, g6, at: 0))
        g6.sensorId = "8G2"
        await s.apply(event(.updated, g6, at: 60))
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), nil]])
    }

    /// An event whose CGM equals the last one applied is skipped without reading the rows: with the rows deleted
    /// behind the store's back, it opens nothing; a different one reads them again.
    func testApplySkipsTheSameStateWithoutARead() async throws {
        let container = StatsFixtures.inMemoryContainer()
        let s = store(container)
        await s.apply(event(.manager, nightscout, at: 0))
        try await container.performBackgroundTask { context in
            let rows = try context.fetch(NSFetchRequest<CGMSession>(entityName: CGMSessionStore.Entity.sessions))
            rows.forEach(context.delete)
            try context.save()
        }
        await s.apply(event(.updated, nightscout, at: 10))
        var sessions = await rows(s)
        XCTAssertEqual(sessions, [])
        await s.apply(event(.updated, libre(sensor: nil), at: 20))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(20), nil]])
    }

    /// `DeviceDataManager`'s compare: sensor starts jittering by seconds are the same state; a first known start, one
    /// beyond the tolerance, or another field is a change.
    func testSnapshotStateCompareToleratesStartJitterOnly() {
        let base = libre(sensor: 0)
        var jitter = base
        jitter.sensorStart = at(0).addingTimeInterval(20)
        XCTAssertTrue(CGMSnapshot.isSameState(base, jitter))
        XCTAssertTrue(CGMSnapshot.isSameState(nil, nil))
        XCTAssertFalse(CGMSnapshot.isSameState(nil, base))
        XCTAssertFalse(CGMSnapshot.isSameState(libre(sensor: nil), base))
        XCTAssertFalse(CGMSnapshot.isSameState(base, libre(sensor: 31)))
        var appGroup = base
        appGroup.cgmId = "xDrip4iOS"
        XCTAssertFalse(CGMSnapshot.isSameState(base, appGroup))
        XCTAssertFalse(CGMSnapshot.isSameState(base, libre(sensor: 0, oneMinute: true)))
    }

    // MARK: - No overlaps

    /// SplitMix64: a seeded generator, so a failure repeats.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A random sequence of events (CGM switches, removals, sensor changes, moves within and beyond the tolerance,
    /// field changes, the clock now and then set back): after every one, at most one open session and it is the last,
    /// every session ends at or after its start, and none overlaps the next.
    func testNoOverlapsInARandomEventSequence() {
        var random = SeededGenerator(state: 20_261_108)
        var sessions: [CGMSessionRecord] = []
        var minutes = 0.0
        var sensorStart: Double? = -1000
        var cgm: CGMSnapshot? = g7(sensor: -1000)
        for index in 0 ..< 2000 {
            // now and then the clock set back
            let step: ClosedRange<Double> = random.next() % 10 == 0 ? -120 ... 0 : 0 ... 600
            minutes += Double.random(in: step, using: &random)
            let change = random.next() % 8
            switch change {
            case 0: cgm = nil
            case 1: cgm = [g7(sensor: sensorStart), libre(sensor: sensorStart), nightscout].randomElement(using: &random)
            case 2:
                sensorStart = minutes + Double.random(in: -900 ... 60, using: &random)
                cgm?.sensorStart = sensorStart.map { at($0) }
            case 3: cgm?.sensorStart = sensorStart.map { at($0 + Double.random(in: -29 ... 29, using: &random)) }
            case 4: cgm?.sensorId = ["A", "B", nil].randomElement(using: &random)!
            case 5: cgm?.oneMinute.toggle()
            case 6: cgm?.sensorStart = nil
            default: break
            }
            let lastReading = Bool.random(using: &random) ? at(minutes - Double.random(in: -5 ... 300, using: &random)) : nil
            let writes = CGMSessionRules.changes(
                for: cgm,
                sessions: sessions,
                now: at(minutes),
                newID: UUID(),
                lastReadingAt: lastReading
            )
            for write in writes {
                if let index = sessions.firstIndex(where: { $0.id == write.id }) {
                    sessions[index] = write
                } else {
                    sessions.append(write)
                }
            }
            let sorted = CGMSessionRules.ordered(sessions)
            let open = sorted.filter { $0.end == nil }
            XCTAssertLessThanOrEqual(open.count, 1, "step \(index)")
            if let open = open.first {
                XCTAssertEqual(open.id, sorted.last?.id, "step \(index)")
            }
            XCTAssertEqual(open.isEmpty, cgm == nil, "step \(index)")
            for (position, session) in sorted.enumerated() {
                if let end = session.end {
                    XCTAssertGreaterThanOrEqual(end, session.start, "step \(index)")
                }
                if position + 1 < sorted.count {
                    XCTAssertLessThanOrEqual(session.end ?? .distantFuture, sorted[position + 1].start, "step \(index)")
                }
            }
        }
        XCTAssertGreaterThan(sessions.count, 50)
    }

    // MARK: - Entered sessions

    /// A closed session the user entered for Unknown readings, `[from, to)` in minutes.
    private func entered(_ from: Double, _ to: Double?, _ cgm: CGMSnapshot? = nil) -> CGMSessionRecord {
        CGMSessionRecord(id: UUID(), start: at(from), end: to.map { at($0) }, cgm ?? libre(sensor: from), source: .entered)
    }

    private func enteredSpans(_ sessions: [CGMSessionRecord]) -> [[Date?]] {
        spans(sessions.filter { $0.source == .entered })
    }

    /// Entered sessions are written closed and as entered (an open one is dropped), their fields kept; a new one
    /// replaces every stored entered one it overlaps, or that overlaps `replacing`, whole; `removeEntered(in:)` takes
    /// out an interval's time only (the parts outside stay), `removeAllEntered` every one.
    func testEnterReplacesAndRemovesTheEnteredSessions() async {
        let s = store(StatsFixtures.inMemoryContainer())
        var first = entered(-3000, -2000)
        first.source = .recorded
        await s.enter([first, entered(-1000, nil)])
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), at(-2000)]])
        XCTAssertEqual(sessions.map(\.source), [.entered])
        XCTAssertEqual(sessions.first?.cgmId, "libre3")
        XCTAssertEqual(sessions.first?.sensorStart, at(-3000))

        await s.enter([entered(-5000, -4000), entered(-2500, -1500, g7(sensor: -2500))])
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-5000), at(-4000)], [at(-2500), at(-1500)]])
        XCTAssertEqual(sessions.map(\.cgmId), ["libre3", "dexcomG7"])

        await s.enter([entered(-6000, -5500)], replacing: DateInterval(start: at(-1600), end: at(-1400)))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-6000), at(-5500)], [at(-5000), at(-4000)]])

        await s.removeEntered(in: DateInterval(start: at(-5800), end: at(-4500)))
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-6000), at(-5800)], [at(-4500), at(-4000)]])

        await s.removeAllEntered()
        sessions = await rows(s)
        XCTAssertEqual(sessions, [])
    }

    /// An answer changed: the first sensor saved as a Libre 3 started its hour's warm-up before the Unknown readings,
    /// as a G7 its 30 minutes. Nothing of the Libre 3's is left before the G7's (no ghost period).
    func testAChangedAnswerLeavesNothingOfTheOldOne() async {
        let s = store(StatsFixtures.inMemoryContainer())
        let unknown = DateInterval(start: at(0), end: at(1000))
        await s.enter([entered(-60, 500), entered(500, 1000)], replacing: unknown)
        await s.enter([entered(-30, 1000, g7(sensor: -30))], replacing: unknown)
        let sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-30), at(1000)]])
        XCTAssertEqual(sessions.map(\.cgmId), ["dexcomG7"])
    }

    /// The reader after clipping: an entered session's parts that overlap the interval, none outside it; a recorded
    /// session that covers all of an entered one in the interval leaves nothing of it there.
    func testSessionsInAnIntervalAfterClipping() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, nightscout, at: -3000))
        await s.apply(event(.manager, nil, at: -2000))
        await s.enter([entered(-4000, -1000)])
        let inRecorded = await s.sessions(in: DateInterval(start: at(-2800), end: at(-2200)))
        XCTAssertEqual(spans(inRecorded), [[at(-3000), at(-2000)]])
        XCTAssertEqual(inRecorded.map(\.source), [.recorded])
        let after = await s.sessions(in: DateInterval(start: at(-1500), end: at(-1200)))
        XCTAssertEqual(spans(after), [[at(-2000), at(-1000)]])
        XCTAssertEqual(after.map(\.source), [.entered])
        let across = await s.sessions(in: DateInterval(start: at(-3500), end: at(-1500)))
        XCTAssertEqual(spans(across), [[at(-4000), at(-3000)], [at(-3000), at(-2000)], [at(-2000), at(-1000)]])
        let none = await s.sessions(in: DateInterval(start: at(-900), end: at(-800)))
        XCTAssertEqual(none, [])
    }

    /// A recorded session always wins: an entered one is clipped to the time no recorded one covers when it is
    /// written, and again when it is read after recording added one over it (here the first session after the
    /// upgrade, at its sensor start). A recorded session inside it leaves two parts, each with an id of its own, the
    /// same at every read.
    func testARecordedSessionWinsOverAnEnteredOne() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.enter([entered(-6000, -100)])
        await s.apply(event(.manager, g7(sensor: -2000), at: 0))
        var sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-6000), at(-2000)], [at(-2000), nil]])
        XCTAssertEqual(sessions.map(\.source), [.entered, .recorded])

        // written over the recorded one: only the time before it (the entered one it overlaps replaced)
        await s.enter([entered(-2500, 500)])
        sessions = await rows(s)
        XCTAssertEqual(enteredSpans(sessions), [[at(-2500), at(-2000)]])

        let container = StatsFixtures.inMemoryContainer()
        let other = store(container)
        await other.apply(event(.manager, nightscout, at: -3000))
        await other.apply(event(.manager, nil, at: -2000))
        let around = entered(-4000, -1000)
        await other.enter([around])
        let parts = await rows(other)
        XCTAssertEqual(spans(parts), [[at(-4000), at(-3000)], [at(-3000), at(-2000)], [at(-2000), at(-1000)]])
        XCTAssertEqual(parts.map(\.source), [.entered, .recorded, .entered])
        XCTAssertNotEqual(parts[0].id, parts[2].id)
        // a later recorded session splits a stored entered one at the read: the parts' ids stay
        await other.apply(event(.manager, nightscout, at: -1500))
        let read = await rows(other)
        let again = await rows(other)
        XCTAssertEqual(read.map(\.id), again.map(\.id))
        XCTAssertEqual(enteredSpans(read), [[at(-4000), at(-3000)], [at(-2000), at(-1500)]])
        XCTAssertEqual(
            CGMEnteredSessions.pieceID(around.id, 0),
            around.id
        )
        XCTAssertNotEqual(CGMEnteredSessions.pieceID(around.id, 1), around.id)
    }

    /// The writer's rules see the recorded sessions only: an entered session after the last recorded one neither
    /// counts as the open one nor as the last session's end, and the rules never change it.
    func testTheRulesNeverTouchAnEnteredSession() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -3000), at: -3000))
        await s.apply(event(.manager, nil, at: -2000))
        await s.enter([entered(-1500, -1000)])
        await s.apply(event(.manager, libre(sensor: -1800), at: 0))
        let sessions = await rows(s)
        // the Libre's session opens at its sensor start after the last recorded end, the entered one clipped by it
        XCTAssertEqual(spans(sessions.filter { $0.source == .recorded }), [[at(-3000), at(-2000)], [at(-1800), nil]])
        XCTAssertEqual(enteredSpans(sessions), [])
        await s.apply(event(.manager, nil, at: 10))
        let closed = await rows(s)
        XCTAssertEqual(spans(closed), [[at(-3000), at(-2000)], [at(-1800), at(10)]])
    }

    /// The Settings wipe removes the entered sessions with the recorded ones.
    func testWipeRemovesTheEnteredSessions() async {
        let s = store(StatsFixtures.inMemoryContainer())
        await s.apply(event(.manager, g7(sensor: -3000), at: 0))
        await s.enter([entered(-6000, -4000)])
        var sessions = await rows(s)
        XCTAssertEqual(enteredSpans(sessions), [[at(-6000), at(-4000)]])
        await s.wipe()
        sessions = await rows(s)
        XCTAssertEqual(spans(sessions), [[at(-3000), nil]])
        XCTAssertEqual(sessions.map(\.source), [.recorded])
    }

    /// The pure clipping: the parts outside the others, none of zero length.
    func testSubtractLeavesThePartsOutside() {
        let whole = DateInterval(start: at(0), end: at(100))
        XCTAssertEqual(CGMEnteredSessions.subtract(whole, []), [whole])
        XCTAssertEqual(
            CGMEnteredSessions.subtract(whole, [
                DateInterval(start: at(20), end: at(30)),
                DateInterval(start: at(-10), end: at(5)),
                DateInterval(start: at(25), end: at(40)),
                DateInterval(start: at(100), end: at(200))
            ]),
            [DateInterval(start: at(5), end: at(20)), DateInterval(start: at(40), end: at(100))]
        )
        XCTAssertEqual(CGMEnteredSessions.subtract(whole, [DateInterval(start: at(-1), end: at(101))]), [])
    }

    // MARK: - Attribution

    private func reading(_ minutes: Double) -> GlucosePoint {
        GlucosePoint(time: at(minutes), mgdl: 100)
    }

    /// Readings by `[start, end)`: one at a session's start is its, one at its end the next's (or Unknown); the time
    /// before the first session, between a removal and the next, and outside any is the Unknown remainder. An open
    /// session reaches to the future.
    func testAttributionByTimeAtTheBoundariesAndTheUnknownRemainder() {
        let first = CGMSessionRecord(id: UUID(), start: at(0), end: at(100), g7(sensor: -500))
        let second = CGMSessionRecord(id: UUID(), start: at(100), end: at(200), libre(sensor: nil))
        let third = CGMSessionRecord(id: UUID(), start: at(300), libre(sensor: 300))
        let readings = [-10.0, 0, 50, 99.9, 100, 199, 200, 250, 300, 10000].map(reading)

        let attribution = CGMSessionAttribution.attribute(readings, to: [third, first, second])
        XCTAssertEqual(attribution.bySession.map(\.session.id), [first.id, second.id, third.id])
        XCTAssertEqual(attribution.bySession.map { $0.readings.map(\.time) }, [
            [at(0), at(50), at(99.9)],
            [at(100), at(199)],
            [at(300), at(10000)]
        ])
        XCTAssertEqual(attribution.unknown.map(\.time), [at(-10), at(200), at(250)])

        let none = CGMSessionAttribution.attribute(readings, to: [])
        XCTAssertEqual(none.bySession.count, 0)
        XCTAssertEqual(none.unknown, readings)
    }

    /// The engine's sensor starts: each session's sensor start, else its start, ascending.
    func testSensorStartsAreTheSensorsElseTheSessionsStart() {
        let first = CGMSessionRecord(id: UUID(), start: at(0), end: at(100), g7(sensor: -500))
        let second = CGMSessionRecord(id: UUID(), start: at(100), libre(sensor: nil))
        XCTAssertEqual(CGMSessionAttribution.sensorStarts([second, first]), [at(-500), at(100)])
    }
}
