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

    // MARK: gate clock boundaries

    /// a fixed UTC date
    private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    func testGateAllowsWithoutAnUpload() {
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: nil, interval: .hours(1), now: date(28, 10, 0)))
    }

    func testGateHoldsWithinTheSameHour() {
        XCTAssertFalse(UploadScheduleGate.isDue(
            lastUpload: date(28, 10, 0, 30),
            interval: .hours(1),
            now: date(28, 10, 59, 59)
        ))
    }

    func testGateAllowsOnceTheHourIsCrossed() {
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: date(28, 10, 58), interval: .hours(1), now: date(28, 11, 1)))
    }

    func testEntitiesUploadedAtDifferentTimesAreDueTogether() {
        let interval: TimeInterval = .hours(1)
        let early = date(28, 10, 13)
        let late = date(28, 10, 28)
        XCTAssertFalse(UploadScheduleGate.isDue(lastUpload: early, interval: interval, now: date(28, 10, 59)))
        XCTAssertFalse(UploadScheduleGate.isDue(lastUpload: late, interval: interval, now: date(28, 10, 59)))
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: early, interval: interval, now: date(28, 11, 2)))
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: late, interval: interval, now: date(28, 11, 2)))
    }

    func testGateAllowsWhenTheClockWentBack() {
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: date(28, 11, 5), interval: .hours(1), now: date(28, 10, 30)))
    }

    func testGateUses12HourBoundaries() {
        let interval: TimeInterval = .hours(12)
        XCTAssertFalse(UploadScheduleGate.isDue(lastUpload: date(28, 0, 5), interval: interval, now: date(28, 11, 59)))
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: date(28, 11, 50), interval: interval, now: date(28, 12, 1)))
        XCTAssertFalse(UploadScheduleGate.isDue(lastUpload: date(28, 12, 1), interval: interval, now: date(28, 23, 59)))
        XCTAssertTrue(UploadScheduleGate.isDue(lastUpload: date(28, 23, 59), interval: interval, now: date(29, 0, 1)))
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

/// The Site Change upload (`PumpChangeRecorder`, `NightscoutUploads.siteChangeSync`): one per change event, as Loop and
/// Trio upload them; none from pod age or primes any more.
final class NightscoutSiteChangeTests: XCTestCase {
    private actor Calls {
        var upserts: [SyncUpsert<NigtscoutTreatment>] = []
        var deleted: [NigtscoutTreatment] = []
        var failing = false

        var upserted: [NigtscoutTreatment] { upserts.map(\.record) }

        func upsert(_ items: [SyncUpsert<NigtscoutTreatment>]) throws {
            guard !failing else { throw DataSyncError.sinkUnavailable }
            upserts += items
        }

        func delete(_ records: [NigtscoutTreatment]) {
            deleted += records
        }

        func fail(_ failing: Bool) {
            self.failing = failing
        }
    }

    private struct FakeSink: SyncSink {
        let calls: Calls

        func upsert(_ items: [SyncUpsert<NigtscoutTreatment>]) async throws {
            try await calls.upsert(items)
        }

        func delete(_ records: [NigtscoutTreatment]) async throws {
            await calls.delete(records)
        }
    }

    private actor Counter {
        var count = 0
        func increment() { count += 1 }
    }

    private final class FakeReachability: ReachabilityManager, @unchecked Sendable {
        var status: ReachabilityStatus { .reachable(.ethernetOrWiFi) }
        var isReachable: Bool { true }
        func startListening(onQueue _: DispatchQueue, onUpdatePerforming _: @escaping Listener) -> Bool { true }
        func stopListening() {}
    }

    private typealias Sync = DataSynchronizer<NigtscoutTreatment, KeepingSink<FakeSink>>
    private typealias Config = NightscoutUploads.SiteChangeSync

    private let storage = IsolatedFileStorage()
    private let calls = Calls()
    /// the first launch with the Site Changes from the change events
    private let launch = Date().addingTimeInterval(-.hours(1)).truncatedToSecond
    private let keychain = BaseKeychain(serviceName: "test-site-changes-\(UUID().uuidString)")

    override func tearDown() async throws {
        await storage.remove(OpenAPS.Monitor.pumpChanges)
        await storage.remove(OpenAPS.Nightscout.uploadedSiteChanges)
        await storage.remove(OpenAPS.Nightscout.uploadedPumphistory)
        _ = keychain.removeAllKeys()
    }

    private func at(_ minutes: Double) -> Date {
        launch.addingTimeInterval(.minutes(minutes))
    }

    /// a launch: the recorder started, as `NightscoutUploads.start` does
    private func recorder(launchedAt date: Date? = nil) async -> PumpChangeRecorder {
        let launch = date ?? self.launch
        let recorder = PumpChangeRecorder(storage: storage, now: { launch })
        await recorder.start()
        return recorder
    }

    /// the production configuration's synchronizer (`NightscoutUploads.SiteChangeSync`)
    private func siteChangeSync() -> Sync {
        DataSynchronizer(
            name: "test.siteChanges",
            sink: KeepingSink(base: FakeSink(calls: calls), keeps: Config.keeps),
            storage: storage,
            snapshotFile: Config.snapshotFile,
            retention: Config.retention,
            deletionWindow: Config.deletionWindow
        )
    }

    @discardableResult private func upload(
        _ recorder: PumpChangeRecorder,
        _ sync: Sync,
        trigger: SyncTrigger = .dataChanged
    ) async -> SyncResult {
        await sync.reconcile(trigger: trigger) { await recorder.currentRecords() }
    }

    private func change(
        _ plugin: String,
        _ component: PumpLifecycleEvent.Component,
        _ minutes: Double,
        _ title: String? = nil
    ) -> PumpLifecycleEvent {
        PumpLifecycleEvent(plugin: plugin, component: component, date: at(minutes), title: title)
    }

    private func siteChange(_ date: Date, notes: String? = nil) -> NigtscoutTreatment {
        NigtscoutTreatment(
            duration: nil,
            rawDuration: nil,
            rawRate: nil,
            absolute: nil,
            rate: nil,
            eventType: .nsSiteChange,
            createdAt: date,
            enteredBy: NigtscoutTreatment.local,
            bolus: nil,
            insulin: nil,
            notes: notes,
            carbs: nil,
            fat: nil,
            protein: nil,
            targetTop: nil,
            targetBottom: nil
        )
    }

    private func log() async -> PumpChangeRecorder.Log? {
        await storage.retrieve(OpenAPS.Monitor.pumpChanges, as: [PumpChangeRecorder.Log].self)?.first
    }

    // MARK: The configuration

    /// The retired pod-age sync's name (its Last Uploads history), group and snapshot; append-only.
    func testConfiguration() {
        XCTAssertEqual(Config.name, "podAge")
        XCTAssertEqual(Config.group, .deviceStatus)
        XCTAssertEqual(Config.snapshotFile, "upload/uploaded-pod-age.json")
        XCTAssertEqual(Config.retention, .days(15))
        XCTAssertEqual(Config.deletionWindow, 0)
        let site = siteChange(at(0))
        var bolus = site
        bolus.eventType = .bolus
        XCTAssertTrue(Config.keeps(site))
        XCTAssertTrue(Config.keeps(bolus))
        XCTAssertTrue(NightscoutUploads.pumpHistoryKeeps(site))
        XCTAssertFalse(NightscoutUploads.pumpHistoryKeeps(bolus))
    }

    // MARK: One per change

    func testOneSiteChangePerPatchAndPodChange() async {
        let recorder = await self.recorder()
        let sync = siteChangeSync()
        let notedMedtrum = await recorder.note([change("Medtrum", .pump, 10.4, "Patch replace")])
        XCTAssertTrue(notedMedtrum)
        // the patch clock's start a few seconds earlier is no event: nothing more comes for this patch
        await upload(recorder, sync)
        var upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.eventType), [.nsSiteChange])
        XCTAssertEqual(upserted.map(\.createdAt), [at(10.4).truncatedToSecond])
        XCTAssertEqual(upserted.map(\.notes), ["Patch replace"])
        XCTAssertEqual(upserted.map(\.enteredBy), [NigtscoutTreatment.local])

        // a re-send within 2 min: none; a new patch 3 min later (the first faulted): its own
        let resent = await recorder.note([change("Medtrum", .pump, 11.4)])
        XCTAssertFalse(resent)
        let replaced = await recorder.note([change("Medtrum", .pump, 13.5, "Patch replace")])
        XCTAssertTrue(replaced)
        // a pod, at its setup's completion
        let notedPod = await recorder.note([change("Omni", .pump, 50, "Pod Change (Dash)")])
        XCTAssertTrue(notedPod)
        await upload(recorder, sync)
        upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [at(10.4), at(13.5), at(50)].map(\.truncatedToSecond))
        XCTAssertEqual(upserted.map(\.notes), ["Patch replace", "Patch replace", "Pod Change (Dash)"])
        let deleted = await calls.deleted
        XCTAssertTrue(deleted.isEmpty)
    }

    func testTubePumpSetChange() async {
        let recorder = await self.recorder()
        let sync = siteChangeSync()
        // Dana: a cannula prime's `.infusionSet` (its `.prime` is no change event), a refill's `.reservoir`
        let noted = await recorder.note([change("Dana", .reservoir, 5), change("Dana", .infusionSet, 8, "Prime 0.3U")])
        XCTAssertTrue(noted)
        let refill = await recorder.note([change("Dana", .reservoir, 40)])
        XCTAssertFalse(refill)
        await upload(recorder, sync)
        let upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.eventType), [.nsSiteChange])
        XCTAssertEqual(upserted.map(\.createdAt), [at(8).truncatedToSecond])
        XCTAssertEqual(upserted.map(\.notes), ["Prime 0.3U"])
    }

    /// The pump sessions' kind rule: a pod's or patch's `.infusionSet` is none; a tube pump's site takes either
    /// component, one change within 15 min.
    func testTheSessionsKindRule() async {
        let recorder = await self.recorder()
        let podSet = await recorder.note([change("Omni", .infusionSet, 5)])
        XCTAssertFalse(podSet)
        let tube = await recorder.note([change("Dana", .infusionSet, 10), change("Dana", .pump, 20)])
        XCTAssertTrue(tube)
        let changes = await log()?.changes
        XCTAssertEqual(changes?.map(\.date), [at(10).truncatedToSecond])
    }

    func testTwoPluginsWithinOneWindowAreTwoChanges() async {
        let recorder = await self.recorder()
        let noted = await recorder.note([change("Medtrum", .pump, 10), change("Omni", .pump, 11)])
        XCTAssertTrue(noted)
        let changes = await log()?.changes
        XCTAssertEqual(changes?.map(\.plugin), ["Medtrum", "Omni"])
    }

    func testMinimedResendsUploadOnce() async {
        let recorder = await self.recorder()
        let sync = siteChangeSync()
        var noted: [Bool] = []
        // every 5-min fetch re-reads 35 min back: the fixed prime's set change comes about 7 times
        for _ in 0 ..< 7 {
            await noted.append(recorder.note([change("Minimed", .infusionSet, 20, "Set Change (fixed prime)")]))
            await upload(recorder, sync)
        }
        XCTAssertEqual(noted, [true, false, false, false, false, false, false])
        let upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [at(20).truncatedToSecond])
    }

    func testDanaReprimeWithinFifteenMinutesIsTheSameChange() async {
        let recorder = await self.recorder()
        let sync = siteChangeSync()
        let first = await recorder.note([change("Dana", .infusionSet, 0, "Prime 0.3U")])
        let again = await recorder.note([change("Dana", .infusionSet, 12, "Prime 0.2U")])
        let next = await recorder.note([change("Dana", .infusionSet, 16, "Prime 0.3U")])
        XCTAssertEqual([first, again, next], [true, false, true])
        await upload(recorder, sync)
        let upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [at(0), at(16)].map(\.truncatedToSecond))
    }

    /// A pump clock ahead: the change is recorded and uploaded at its date, and never deleted.
    func testAFutureDatedChangeIsUploadedAndNeverDeleted() async {
        let ahead = Date().addingTimeInterval(.minutes(10)).truncatedToSecond
        let recorder = await self.recorder()
        let sync = siteChangeSync()
        let noted = await recorder.note([PumpLifecycleEvent(plugin: "Dana", component: .infusionSet, date: ahead)])
        XCTAssertTrue(noted)
        await upload(recorder, sync)
        var upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [ahead])
        // gone from the records (the log edited), while another change uploads: no delete
        await storage.save([PumpChangeRecorder.Log(since: launch, changes: [])], as: OpenAPS.Monitor.pumpChanges)
        _ = await recorder.note([change("Medtrum", .pump, 30)])
        await upload(recorder, sync)
        upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [ahead, at(30).truncatedToSecond])
        let deleted = await calls.deleted
        XCTAssertTrue(deleted.isEmpty)
    }

    func testTheLogKeepsFifteenDays() async {
        let recorder = await self.recorder()
        _ = await recorder.note([change("Medtrum", .pump, 10)])
        // 16 days on
        let later = await self.recorder(launchedAt: at(16 * 24 * 60))
        _ = await later.note([change("Medtrum", .pump, 16 * 24 * 60)])
        let changes = await log()?.changes
        XCTAssertEqual(changes?.map(\.date), [at(16 * 24 * 60).truncatedToSecond])
        let records = await later.currentRecords()
        XCTAssertEqual(records.map(\.createdAt), [at(16 * 24 * 60).truncatedToSecond])
    }

    /// An event older than the retention isn't recorded (the log would prune it, and record it again on its next
    /// re-send).
    func testAChangeOlderThanTheRetentionIsNone() async {
        await storage.save(
            [PumpChangeRecorder.Log(since: at(-20 * 24 * 60), changes: [])],
            as: OpenAPS.Monitor.pumpChanges
        )
        let recorder = await self.recorder()
        let old = await recorder.note([change("Dana", .infusionSet, -16 * 24 * 60)])
        XCTAssertFalse(old)
        let recent = await recorder.note([change("Dana", .infusionSet, -14 * 24 * 60)])
        XCTAssertTrue(recent)
        let changes = await log()?.changes
        XCTAssertEqual(changes?.map(\.date), [at(-14 * 24 * 60).truncatedToSecond])
    }

    // MARK: Relaunch, the first launch, offline

    func testRelaunchUploadsNothingAgain() async {
        let notedBefore = await recorder().note([change("Minimed", .infusionSet, 20)])
        XCTAssertTrue(notedBefore)
        let result = await upload(recorder(), siteChangeSync())
        XCTAssertEqual(result, .synced)

        // a relaunch: a new recorder and sync on the same files; Minimed re-sends the change
        let relaunched = await recorder(launchedAt: at(40))
        let resent = await relaunched.note([change("Minimed", .infusionSet, 20)])
        XCTAssertFalse(resent)
        let again = await upload(relaunched, siteChangeSync())
        XCTAssertEqual(again, .noChanges)
        let upserted = await calls.upserted
        XCTAssertEqual(upserted.count, 1)
    }

    func testFirstLaunchUploadsNoHistory() async throws {
        // the retired pod-age sync's snapshot (its file is this sync's): a patch's pair, an older pod
        let podAge = [siteChange(at(-60 * 24)), siteChange(at(-60 * 24).addingTimeInterval(4)), siteChange(at(-60 * 70))]
        await storage.save(podAge, as: OpenAPS.Nightscout.uploadedSiteChanges)

        // the first fetch re-sends a set change from before the update (the primes uploaded it then): not recorded
        let recorder = await self.recorder()
        let resent = await recorder.note([change("Minimed", .infusionSet, -30)])
        XCTAssertFalse(resent)
        let result = await upload(recorder, siteChangeSync())
        XCTAssertEqual(result, .noChanges)
        let upserted = await calls.upserted
        let deleted = await calls.deleted
        XCTAssertTrue(upserted.isEmpty)
        XCTAssertTrue(deleted.isEmpty)

        // the log's start holds after a relaunch (Minimed re-sends after one)
        let since = await log()?.since
        XCTAssertEqual(since, launch)
        let relaunched = await self.recorder(launchedAt: at(30))
        let resentAgain = await relaunched.note([change("Minimed", .infusionSet, -30)])
        XCTAssertFalse(resentAgain)
        // a change after the update is recorded
        let after = await relaunched.note([change("Minimed", .infusionSet, 20)])
        XCTAssertTrue(after)
    }

    /// The first launch with this starts the log, without any event: a change dated between it and the next launch
    /// (an earlier one's re-send, a pump clock behind) is recorded and uploaded.
    func testTheFirstLaunchStartsTheLogWithoutEvents() async {
        _ = await recorder()
        let since = await log()?.since
        XCTAssertEqual(since, launch)

        let relaunched = await recorder(launchedAt: at(60))
        let noted = await relaunched.note([change("Minimed", .infusionSet, 30, "Set Change (fixed prime)")])
        XCTAssertTrue(noted)
        let sinceAfter = await log()?.since
        XCTAssertEqual(sinceAfter, launch)
        await upload(relaunched, siteChangeSync())
        let upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [at(30).truncatedToSecond])
    }

    func testOfflineThenARetryUploads() async {
        let recorder = await self.recorder()
        let sync = siteChangeSync()
        _ = await recorder.note([change("Medtrum", .pump, 10)])
        await calls.fail(true)
        let failed = await upload(recorder, sync, trigger: .retry)
        XCTAssertEqual(failed, .failed)
        await calls.fail(false)
        let retried = await upload(recorder, sync, trigger: .retry)
        XCTAssertEqual(retried, .synced)
        let upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [at(10).truncatedToSecond])
    }

    // MARK: The push-only sync

    private func uploadingContext(storage: FileStorage) -> (NightscoutUploadContext, AppCoordinator) {
        keychain.setValue("https://nightscout.invalid", forKey: NightscoutConfig.Config.urlKey)
        keychain.setValue("not-a-secret", forKey: NightscoutConfig.Config.secretKey)
        let coordinator = AppCoordinator()
        var settings = FreeAPSSettings()
        settings.isUploadEnabled = true
        let always = UploadNetworkSchedule(interval: .always, alwaysWhileCharging: false)
        settings.deviceStatusUploadSchedule = UploadSchedule(onWifi: always, onCellular: always)
        coordinator.setSettings(settings)
        let apiProvider = NightscoutAPIProvider(keychain: keychain, appCoordinator: coordinator)
        apiProvider.start()
        let context = NightscoutUploadContext(
            apiProvider: apiProvider,
            appCoordinator: coordinator,
            reachabilityManager: FakeReachability(),
            storage: storage
        )
        return (context, coordinator)
    }

    /// The production sync (`NightscoutUploads.siteChangeSync`), end to end: an event is recorded, marks the work
    /// pending, and the flush uploads it; an event that records nothing leaves nothing pending (the flush reads no
    /// records). A sentinel batch (a refill, recorded as nothing) after each: `observe` handles the batches one at a
    /// time, so once the sentinel's note ran, the event's push, its `markPending` too, is done.
    func testPushOnlySyncEndToEnd() async throws {
        let probe = StorageProbe()
        let storage = ObservedFileStorage(base: self.storage, probe: probe)
        let (context, coordinator) = uploadingContext(storage: storage)
        XCTAssertTrue(context.canUpload())
        let lastUploadKey = "nightscoutUpload.lastUpload.\(Config.name)"
        let lastUpload = UserDefaults.standard.object(forKey: lastUploadKey)
        defer { UserDefaults.standard.set(lastUpload, forKey: lastUploadKey) }
        UserDefaults.standard.removeObject(forKey: lastUploadKey)

        let launch = self.launch
        let recorder = PumpChangeRecorder(storage: storage, now: { launch })
        await recorder.start()
        let sync = NightscoutUploads.siteChangeSync(sink: FakeSink(calls: calls), recorder: recorder, context: context)
        await sync.start()
        // the launch's flush (pending from the start): nothing yet
        await sync.flush(startedAt: Date())
        var reads = await probe.reads
        XCTAssertEqual(reads, 1)
        let sentinel = change("Dana", .reservoir, 0)

        coordinator.sendPumpLifecycleEvents([change("Medtrum", .pump, 10, "Patch replace")])
        coordinator.sendPumpLifecycleEvents([sentinel])
        await probe.waitForNotes(2)
        await sync.flush(startedAt: Date())
        var upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [at(10).truncatedToSecond])
        XCTAssertNotNil(UploadScheduleGate.lastUpload(named: Config.name))
        reads = await probe.reads
        XCTAssertEqual(reads, 2)

        // a re-send: nothing recorded, nothing pending
        coordinator.sendPumpLifecycleEvents([change("Medtrum", .pump, 10.5)])
        coordinator.sendPumpLifecycleEvents([sentinel])
        await probe.waitForNotes(4)
        await sync.flush(startedAt: Date())
        reads = await probe.reads
        XCTAssertEqual(reads, 2)
        upserted = await calls.upserted
        XCTAssertEqual(upserted.count, 1)
    }

    /// `NightscoutUploads.start()` begins the Site Changes' log before any event (uploads off: nothing is sent).
    func testStartingTheUploadsBeginsTheLog() async throws {
        let before = Date().truncatedToSecond
        let coordinator = AppCoordinator()
        let uploads = NightscoutUploads(
            apiProvider: NightscoutAPIProvider(keychain: keychain, appCoordinator: coordinator),
            appCoordinator: coordinator,
            reachabilityManager: FakeReachability(),
            storage: storage
        )
        try await uploads.start()
        let log = await log()
        let since = try XCTUnwrap(log?.since)
        XCTAssertGreaterThanOrEqual(since, before)
        XCTAssertLessThanOrEqual(since, Date())
        XCTAssertEqual(log?.changes, [])
    }

    // MARK: The retired sources

    func testNoSiteChangeFromAPrime() {
        let events = [
            PumpHistoryEvent(id: "p", type: .prime, timestamp: at(0), amount: 0.3),
            PumpHistoryEvent(id: "r", type: .rewind, timestamp: at(-5))
        ]
        let treatments = NightscoutConversions.treatments(fromPumpHistory: events)
        XCTAssertEqual(treatments.map(\.eventType), [.nsInsulinChange])
    }

    func testNoSiteChangeFromPodAge() async {
        // the pod-age sync read `pumpInfo.podActivatedAt`; the sync's records are the change events' only
        await storage.save([siteChange(at(-30))], as: OpenAPS.Nightscout.uploadedSiteChanges)
        let records = await recorder().currentRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testRetiringTheOldSourcesDeletesNothing() async {
        // the site changes: the pod-age snapshot's records are missing from the records, one dated ahead too (a patch
        // clock ahead): none is deleted
        await storage.save(
            [siteChange(at(-20)), siteChange(Date().addingTimeInterval(.minutes(10)))],
            as: OpenAPS.Nightscout.uploadedSiteChanges
        )
        let recorder = await self.recorder()
        _ = await recorder.note([change("Medtrum", .pump, 30, "Patch replace")])
        await upload(recorder, siteChangeSync())
        var deleted = await calls.deleted
        XCTAssertTrue(deleted.isEmpty)
        let upserted = await calls.upserted
        XCTAssertEqual(upserted.map(\.createdAt), [at(30).truncatedToSecond])

        // the pump history: a prime's Site Change uploaded before the update stays in Nightscout; a bolus removed
        // from the history is still deleted
        let now = Date().truncatedToSecond
        let prime = PumpHistoryEvent(id: "p", type: .prime, timestamp: now.addingTimeInterval(-.hours(1)), amount: 0.3)
        let bolus = PumpHistoryEvent(id: "b", type: .bolus, timestamp: now.addingTimeInterval(-.hours(2)), amount: 1)
        let kept = PumpHistoryEvent(id: "k", type: .bolus, timestamp: now.addingTimeInterval(-.hours(3)), amount: 2)
        var uploaded = NightscoutConversions.treatments(fromPumpHistory: [bolus, kept])
        uploaded.append(siteChange(prime.timestamp))
        await storage.save(uploaded, as: OpenAPS.Nightscout.uploadedPumphistory)
        let pumpHistory = DataSynchronizer(
            name: "test.pumpHistory",
            sink: KeepingSink(base: FakeSink(calls: calls), keeps: NightscoutUploads.pumpHistoryKeeps),
            storage: storage,
            snapshotFile: OpenAPS.Nightscout.uploadedPumphistory,
            retention: .hours(24),
            deletionWindow: .hours(8)
        )
        let result = await pumpHistory.reconcile { NightscoutConversions.treatments(fromPumpHistory: [prime, kept]) }
        XCTAssertEqual(result, .synced)
        deleted = await calls.deleted
        XCTAssertEqual(deleted.map(\.eventType), [.bolus])
        XCTAssertEqual(deleted.map(\.createdAt), [bolus.timestamp])
        // the Site Change left the snapshot: it is never deleted later either
        let snapshot = await storage.retrieve(OpenAPS.Nightscout.uploadedPumphistory, as: [NigtscoutTreatment].self)
        XCTAssertEqual(snapshot?.map(\.eventType), [.bolus])
    }

    /// An adopted pod-age record (milliseconds, no notes) in the same second as a change: the same key, other fields,
    /// so the sink gets an update of it (`NightscoutTreatmentSink` deletes and re-POSTs it), never a delete.
    func testSameSecondAsAnAdoptedPodAgeRecord() async {
        let second = at(30).truncatedToSecond
        await storage.save([siteChange(second.addingTimeInterval(0.4))], as: OpenAPS.Nightscout.uploadedSiteChanges)
        let recorder = await self.recorder()
        let event = PumpLifecycleEvent(
            plugin: "Medtrum",
            component: .pump,
            date: second.addingTimeInterval(0.7),
            title: "Patch replace"
        )
        _ = await recorder.note([event])
        await upload(recorder, siteChangeSync())
        let upserts = await calls.upserts
        XCTAssertEqual(upserts.map(\.isUpdate), [true])
        XCTAssertEqual(upserts.map(\.record.createdAt), [second])
        XCTAssertEqual(upserts.map(\.record.notes), ["Patch replace"])
        let deleted = await calls.deleted
        XCTAssertTrue(deleted.isEmpty)
    }

    // MARK: The format

    /// The upload as Loop's (`eventType`, `created_at`, `enteredBy`, the title in `notes`), read back by the insulin
    /// backfill's parse (C3) as a Site Change at its date.
    func testUploadedSiteChangeParsesAsASiteChange() async throws {
        let recorder = await self.recorder()
        _ = await recorder.note([change("Omni", .pump, 12.75, "Pod Change (Dash)")])
        let records = await recorder.currentRecords()
        // as `NightscoutAPI.uploadTreatments` sends it
        let body = try JSONCoding.encoder.encode(records)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        XCTAssertEqual(object.count, 1)
        XCTAssertEqual(object.first?["eventType"] as? String, "Site Change")
        XCTAssertEqual(object.first?["enteredBy"] as? String, "iAPS")
        XCTAssertEqual(object.first?["notes"] as? String, "Pod Change (Dash)")
        XCTAssertNotNil(object.first?["created_at"] as? String)

        let documents = try JSONDecoder().decode([NightscoutInsulinTreatment].self, from: body)
        XCTAssertEqual(documents.map(\.siteChange), [at(12.75).truncatedToSecond])
        XCTAssertEqual(PumpSessionRules.activations(documents.compactMap(\.siteChange)), [at(12.75).truncatedToSecond])
    }
}

/// Counts the Site Changes' log reads (`PumpChangeRecorder.currentRecords`: a reconcile ran) and its notes (each
/// `note` is one `maybeModifyWithData`), and waits for a number of notes.
private actor StorageProbe {
    private(set) var reads = 0
    private(set) var notes = 0
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func read() {
        reads += 1
    }

    func noted() {
        notes += 1
        let ready = waiters.filter { $0.count <= notes }
        waiters.removeAll { $0.count <= notes }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }

    func waitForNotes(_ count: Int) async {
        guard notes < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

/// `IsolatedFileStorage` with the Site Changes' log observed (`StorageProbe`).
private struct ObservedFileStorage: FileStorage {
    let base: IsolatedFileStorage
    let probe: StorageProbe

    func save<Value: Encodable & Sendable>(_ value: Value, as name: String) async {
        await base.save(value, as: name)
    }

    func save<Value: Decodable & Sendable>(raw: RawJSON, as name: String, decodingInto type: Value.Type) async throws {
        try await base.save(raw: raw, as: name, decodingInto: type)
    }

    func retrieve<Value: Decodable & Sendable>(_ name: String, as type: Value.Type) async -> Value? {
        if name == OpenAPS.Monitor.pumpChanges {
            await probe.read()
        }
        return await base.retrieve(name, as: type)
    }

    func retrieveRaw(_ name: String) async -> String? {
        await base.retrieveRaw(name)
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) async -> [Value]? {
        await base.append(newValue, to: name)
    }

    func append<Value: JSON>(_ newValues: [Value], to name: String) async -> [Value]? {
        await base.append(newValues, to: name)
    }

    func append<Value: JSON, T: Equatable & Sendable>(
        _ newValue: Value,
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]? {
        await base.append(newValue, to: name, uniqBy: keyPath)
    }

    func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]? {
        await base.append(newValues, to: name, uniqBy: keyPath)
    }

    func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqByProj proj: @Sendable(Value) -> T
    ) async -> [Value]? {
        await base.append(newValues, to: name, uniqByProj: proj)
    }

    func appendAndModify<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable,
        _ modify: @Sendable([Value]) -> [Value]
    ) async -> [Value] {
        await base.appendAndModify(newValues, to: name, uniqBy: keyPath, modify)
    }

    func modify<Value: JSON>(file name: String, as type: Value.Type, _ modify: @Sendable([Value]) -> [Value]) async -> [Value] {
        await base.modify(file: name, as: type, modify)
    }

    func delete<Value: JSON>(
        file name: String,
        as type: Value.Type,
        where shouldDelete: @Sendable(Value) -> Bool
    ) async -> (kept: [Value], deleted: [Value]?) {
        await base.delete(file: name, as: type, where: shouldDelete)
    }

    func maybeModify<Value: JSON>(
        file name: String,
        as type: Value.Type,
        _ modify: @Sendable([Value]) -> [Value]?
    ) async -> (Bool, [Value]) {
        await base.maybeModify(file: name, as: type, modify)
    }

    func maybeModifyWithData<Value: JSON, Data: Sendable>(
        file name: String,
        as type: Value.Type,
        _ modify: @Sendable([Value]) -> ([Value], data: Data)?
    ) async -> (Bool, [Value], data: Data?) {
        let result = await base.maybeModifyWithData(file: name, as: type, modify)
        if name == OpenAPS.Monitor.pumpChanges {
            await probe.noted()
        }
        return result
    }

    func remove(_ name: String) async {
        await base.remove(name)
    }

    func rename(_ name: String, to newName: String) async {
        await base.rename(name, to: newName)
    }

    func urlFor(file name: String) async -> URL? {
        await base.urlFor(file: name)
    }
}
