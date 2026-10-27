@testable import FreeAPS
import XCTest

final class NightscoutUploadBurstScheduleTests: XCTestCase {
    private typealias Schedule = NightscoutUploadBurstSchedule
    private typealias Instant = ContinuousClock.Instant

    private let t0 = ContinuousClock.now

    private func at(_ seconds: Double) -> Instant {
        t0 + .seconds(seconds)
    }

    private func at(_ duration: Duration) -> Instant {
        t0 + duration
    }

    /// a schedule whose routine burst fired at 2 s (requested at 0)
    private func routineBurst() -> Schedule {
        var schedule = Schedule(now: t0)
        let fireAt = schedule.request(.routine, now: t0)!
        XCTAssertEqual(schedule.fire(now: fireAt), .routine)
        return schedule
    }

    // MARK: routine vs immediate

    func testRoutineWaitsForTheLoopsStragglers() {
        var schedule = Schedule(now: t0)
        XCTAssertEqual(schedule.request(.routine, now: t0), at(Schedule.routineDelay))
    }

    func testImmediateWaitsForTheRelatedEvents() {
        var schedule = Schedule(now: t0)
        XCTAssertEqual(schedule.request(.immediate, now: t0), at(Schedule.immediateDelay))
    }

    func testBurstFiresOnlyOnceDue() {
        var schedule = Schedule(now: t0)
        let fireAt = schedule.request(.immediate, now: t0)!
        XCTAssertNil(schedule.fire(now: fireAt - .milliseconds(100)))
        XCTAssertEqual(schedule.fire(now: fireAt), .immediate)
        // nothing pending any more
        XCTAssertNil(schedule.fire(now: fireAt + .seconds(60)))
    }

    func testRequestsCoalesceIntoThePendingBurst() {
        var schedule = Schedule(now: t0)
        XCTAssertEqual(schedule.request(.immediate, now: t0), at(3))
        // a later request postpones it
        XCTAssertEqual(schedule.request(.immediate, now: at(1)), at(4))
        // one that's due no later changes nothing
        XCTAssertNil(schedule.request(.routine, now: at(1.5)))
        XCTAssertEqual(schedule.fire(now: at(4)), .routine)
    }

    func testPostponingIsCapped() {
        var schedule = Schedule(now: t0)
        _ = schedule.request(.immediate, now: t0)
        XCTAssertEqual(schedule.request(.immediate, now: at(9)), at(Schedule.maxDelay))
        XCTAssertNil(schedule.request(.immediate, now: at(9.5)))
        XCTAssertEqual(schedule.fire(now: at(Schedule.maxDelay)), .immediate)
    }

    func testMergedRoutineCountsAsTheLoopsBurst() {
        var schedule = Schedule(now: t0)
        _ = schedule.request(.immediate, now: t0)
        _ = schedule.request(.routine, now: at(1))
        XCTAssertEqual(schedule.fire(now: at(10)), .routine)
        // so the next loop within the minimum interval is deferred
        XCTAssertEqual(schedule.request(.routine, now: at(60)), at(10) + Schedule.routineMinInterval)
    }

    // MARK: routine minimum interval

    func testRoutineWithinTheMinimumIntervalIsDeferredToItsEnd() {
        var schedule = routineBurst()
        let end = at(2) + Schedule.routineMinInterval
        // not capped by maxDelay
        XCTAssertEqual(schedule.request(.routine, now: at(62)), end)
        XCTAssertNil(schedule.fire(now: end - .seconds(1)))
        XCTAssertEqual(schedule.fire(now: end), .routine)
    }

    func testDeferredLoopsShareOneBurst() {
        var schedule = routineBurst()
        let end = at(2) + Schedule.routineMinInterval
        XCTAssertEqual(schedule.request(.routine, now: at(62)), end)
        XCTAssertNil(schedule.request(.routine, now: at(122)))
        XCTAssertNil(schedule.request(.routine, now: at(182)))
        XCTAssertEqual(schedule.fire(now: end), .routine)
        XCTAssertNil(schedule.fire(now: end + .seconds(60)))
    }

    func testDeferredLoopStillGetsItsStragglerDelay() {
        var schedule = routineBurst()
        let end = at(2) + Schedule.routineMinInterval
        _ = schedule.request(.routine, now: at(62))
        let now = end - .seconds(1)
        XCTAssertEqual(schedule.request(.routine, now: now), now + Schedule.routineDelay)
    }

    func testRoutineAfterTheMinimumIntervalRuns() {
        var schedule = routineBurst()
        let now = at(2) + Schedule.routineMinInterval
        XCTAssertEqual(schedule.request(.routine, now: now), now + Schedule.routineDelay)
    }

    func testFiveMinuteLoopEndingEarlyOnlyWaitsTheDifference() {
        // the previous loop took 4 s longer than this one
        var schedule = routineBurst()
        XCTAssertEqual(schedule.request(.routine, now: at(298)), at(2) + Schedule.routineMinInterval)
    }

    func testOneMinuteLoopsGetABurstEveryFiveMinutes() {
        var schedule = Schedule(now: t0)
        var bursts = 0
        for second in 0 ..< 3600 {
            if second % 60 == 0 {
                _ = schedule.request(.routine, now: at(Double(second)))
            }
            if schedule.fire(now: at(Double(second))) != nil {
                bursts += 1
            }
        }
        XCTAssertEqual(bursts, 12)
    }

    func testImmediateIsNotLimited() {
        var schedule = routineBurst()
        XCTAssertEqual(schedule.request(.immediate, now: at(3)), at(6))
        XCTAssertEqual(schedule.fire(now: at(6)), .immediate)
        XCTAssertEqual(schedule.request(.immediate, now: at(10)), at(13))
    }

    func testImmediateBurstDoesNotDelayTheNextLoop() {
        var schedule = routineBurst()
        _ = schedule.request(.immediate, now: at(180))
        XCTAssertEqual(schedule.fire(now: at(183)), .immediate)
        XCTAssertEqual(schedule.request(.routine, now: at(302)), at(304))
    }

    func testImmediateFiresADeferredLoopEarly() {
        var schedule = routineBurst()
        let end = at(2) + Schedule.routineMinInterval
        _ = schedule.request(.routine, now: at(62))
        XCTAssertEqual(schedule.request(.immediate, now: at(100)), at(103))
        XCTAssertEqual(schedule.fire(now: at(103)), .immediate)
        // the deferred loop rode along
        XCTAssertNil(schedule.fire(now: end))
    }

    func testDeferredLoopRidesAlongWithAPendingBurst() {
        var schedule = routineBurst()
        _ = schedule.request(.immediate, now: at(100))
        XCTAssertNil(schedule.request(.routine, now: at(101)))
        XCTAssertEqual(schedule.fire(now: at(103)), .immediate)
        XCTAssertNil(schedule.fire(now: at(2) + Schedule.routineMinInterval))
    }

    // MARK: watchdog

    func testWatchdogCountsFromTheStart() {
        let schedule = Schedule(now: t0)
        XCTAssertFalse(schedule.isWatchdogDue(now: at(599)))
        XCTAssertTrue(schedule.isWatchdogDue(now: at(Schedule.watchdogInterval)))
    }

    func testAnyBurstResetsTheWatchdog() {
        var schedule = Schedule(now: t0)
        let fireAt = schedule.request(.immediate, now: at(480))!
        _ = schedule.fire(now: fireAt)
        XCTAssertFalse(schedule.isWatchdogDue(now: at(900)))
        XCTAssertTrue(schedule.isWatchdogDue(now: fireAt + Schedule.watchdogInterval))
    }

    func testWatchdogBurstFiresRightAway() {
        var schedule = Schedule(now: t0)
        let now = at(Schedule.watchdogInterval)
        XCTAssertEqual(schedule.request(.watchdog, now: now), now)
        XCTAssertEqual(schedule.fire(now: now), .watchdog)
        XCTAssertFalse(schedule.isWatchdogDue(now: now + .seconds(60)))
    }

    func testWatchdogKeepsRunningWithoutLoops() {
        var schedule = Schedule(now: t0)
        var bursts = 0
        for minute in 1 ... 60 {
            let now = at(Double(minute * 60))
            if schedule.isWatchdogDue(now: now), let fireAt = schedule.request(.watchdog, now: now),
               schedule.fire(now: fireAt) == .watchdog
            {
                bursts += 1
            }
        }
        XCTAssertEqual(bursts, 6)
    }

    func testOverduePendingBurstStillFires() {
        // its timer didn't run (suspended app): the watchdog tick fires it later
        var schedule = Schedule(now: t0)
        _ = schedule.request(.routine, now: t0)
        XCTAssertEqual(schedule.fire(now: at(420)), .routine)
    }

    // MARK: clock going back

    // The schedule runs on a monotonic clock, so this can't happen - but if an instant ever came from the
    // past, nothing may stall.

    func testWatchdogIsDueWhenTheLastBurstLooksInTheFuture() {
        let schedule = Schedule(now: at(3600))
        XCTAssertTrue(schedule.isWatchdogDue(now: t0))
    }

    func testRoutineIsNotDeferredByABurstThatLooksInTheFuture() {
        var schedule = Schedule(now: at(3600))
        _ = schedule.request(.routine, now: at(3600))
        _ = schedule.fire(now: at(3602))
        XCTAssertEqual(schedule.request(.routine, now: t0), at(Schedule.routineDelay))
    }

    func testBurstScheduledTooFarAheadIsDue() {
        var schedule = Schedule(now: at(3600))
        _ = schedule.request(.immediate, now: at(3600))
        XCTAssertEqual(schedule.fire(now: t0), .immediate)
    }

    // MARK: gate slack

    private let date0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testGateAllowsWithoutAnUpload() {
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: nil, interval: .hours(1), now: date0))
    }

    func testGateAllowsWithinTheSlackOfTheInterval() {
        let interval: TimeInterval = .hours(1)
        let due = interval - UploadScheduleGate.slack
        XCTAssertFalse(UploadScheduleGate.isDue(lastUpload: date0, interval: interval, now: date0 + due - 1))
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: date0, interval: interval, now: date0 + due))
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: date0, interval: interval, now: date0 + interval))
    }

    func testGateSlackAppliesTo12Hours() {
        let interval: TimeInterval = .hours(12)
        let eleventhHour: TimeInterval = .hours(11)
        let fourMinutes: TimeInterval = .minutes(4)
        XCTAssertFalse(UploadScheduleGate.isDue(lastUpload: date0, interval: interval, now: date0 + eleventhHour))
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: date0, interval: interval, now: date0 + interval - fourMinutes))
    }
}

final class DataSynchronizerPendingTests: XCTestCase {
    private struct TestRecord: SyncRecord {
        let id: Int
        let date: Date

        var syncID: Int { id }
        var syncSignature: Int { id }
        var syncDate: Date { date }
    }

    private struct TestSink: SyncSink {
        func upsert(_: [SyncUpsert<TestRecord>]) async throws {}
        func delete(_: [TestRecord]) async throws {}
    }

    private let storage = BaseFileStorage()
    private let snapshotFile = "test-datasync-\(UUID().uuidString).json"

    override func tearDown() async throws {
        await storage.remove(snapshotFile)
    }

    private func makeSync() -> DataSynchronizer<TestRecord, TestSink> {
        DataSynchronizer(
            name: "test",
            sink: TestSink(),
            storage: storage,
            snapshotFile: snapshotFile,
            retention: .hours(24),
            deletionWindow: 0
        )
    }

    func testRetryWithoutAMarkIsSkipped() async {
        let sync = makeSync()
        let record = TestRecord(id: 1, date: Date())
        let first = await sync.reconcile(trigger: .dataChanged) { [record] }
        XCTAssertEqual(first, .synced)
        let retry = await sync.reconcile(trigger: .retry) { [record] }
        XCTAssertEqual(retry, .skipped)
    }

    func testMarkDuringAReconcileKeepsTheWorkPending() async {
        let sync = makeSync()
        let record = TestRecord(id: 1, date: Date())
        let first = await sync.reconcile(trigger: .dataChanged) {
            // a change lands after this reconcile read its data
            await sync.markPending()
            return [record]
        }
        XCTAssertEqual(first, .synced)
        // the retry runs, instead of skipping the change
        let retry = await sync.reconcile(trigger: .retry) { [record] }
        XCTAssertEqual(retry, .noChanges)
    }

    func testMarkBeforeAReconcileIsConsumedByIt() async {
        let sync = makeSync()
        let record = TestRecord(id: 1, date: Date())
        await sync.markPending()
        _ = await sync.reconcile(trigger: .retry) { [record] }
        let retry = await sync.reconcile(trigger: .retry) { [record] }
        XCTAssertEqual(retry, .skipped)
    }
}
