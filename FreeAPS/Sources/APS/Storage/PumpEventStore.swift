import CoreData
import Foundation
import LoopKit

/// The Core Data side of `PumpEventStore`: each call is one background task with one save. `CoreDataPumpEventDatabase`
/// in the app; the tests wrap it to hold or count the calls.
protocol PumpEventDatabase: Sendable {
    /// The live mirror's reconcile: the diff against the stored pump rows, the pump session's heartbeat, the Nightscout
    /// events inside the list's span deleted, one save.
    func reconcile(_ request: PumpEventStore.ReconcileRequest) async throws -> PumpEventStore.ReconcileResult
    /// Deletes the `source = pump` event rows with these identities, final or not. Returns the time they touched (up to
    /// the next event that ends a temp or a suspension, or `now`: `CoreDataPumpEventDatabase.reach`).
    func deleteEvents(_ identities: Set<PumpEventRecord.Identity>, now: Date) async throws -> DateInterval?
    /// The retention prune (events, pump sessions, schedules), the coverage rows of earlier builds, the Nightscout dose
    /// rows inside what the pump knows. Returns what changed.
    func prune(cutoff: Date) async throws -> PumpEventStore.PruneResult
    /// Every `PumpEvent` row (both sources) and every `PumpSession` row (entered fields too).
    func wipeEvents() async throws
    /// Every `PumpSession` row (entered fields too); the events stay.
    func wipeSessions() async throws
    /// The pump driver's change events of one batch against the stored sessions (`PumpSessionRules.changes`), one
    /// save.
    func applyLifecycleEvents(_ events: [PumpLifecycleEvent], now: Date) async throws -> PumpEventStore.LifecycleResult
    /// Inserts the schedule unless the newest record (any source) has its fingerprint. Returns whether it inserted.
    func recordSchedule(_ schedule: PumpEventStore.ScheduleInsert) async throws -> Bool
    /// Every `BasalScheduleRecord` row.
    func wipeSchedules() async throws
    /// One batch of the Nightscout backfill: its records (upserted among the Nightscout rows), without what the pump
    /// knows (the 24 h file, the pump sessions' local time, the pump rows' identities); one save.
    func storeBackfill(_ batch: PumpEventStore.BackfillBatch) async throws -> PumpEventStore.BackfillBatchResult
    /// The Nightscout basal schedules before the oldest local record; one save. `now` ends the change span when there
    /// is no local record.
    func storeSchedules(_ schedules: [PumpEventStore.ScheduleInsert], now: Date) async throws -> PumpEventStore
        .ScheduleBackfillResult
    /// The Nightscout pump sessions of a backfill (`PumpSessionRules.nightscoutSessions`) against the stored sessions;
    /// one save.
    func storeNightscoutSessions(_ request: PumpEventStore.NightscoutSessionsRequest) async throws -> PumpEventStore
        .NightscoutSessionsResult
}

/// The 120-day store of pump events, the pump sessions and the basal schedule history: a mirror of the 24 h pump history
/// file that keeps what ages out of it, and the pods, patches and sites whose covered time is where "no temp" means the
/// scheduled basal (the coverage, `CoreDataStorage.fetchCoverage`).
///
/// - The only writer of `PumpEvent`, `PumpSession` and `BasalScheduleRecord`. Every write (the live mirror, the change
///   events, the explicit deletions, the schedules, the backfill, the prune, the wipes) runs through one
///   `TaskSerializer`, on background contexts only.
/// - `PumpEvent` holds doses only (kinds 0–3). The coverage rows of earlier builds (kind 9) are deleted by the daily
///   prune.
/// - **Local data wins** (`PumpSessionRules.localTime`, one rule for the writes and the statistics' reads): no
///   Nightscout dose row in the 24 h file's time, at a pump row's identity, inside a pump session's whole
///   `[localStart, lastSeen]` (gaps included), or in `[oldest pump dose row, the oldest session's localStart]`. Both
///   ends included. The backfill skips them; the reconcile (the file's time, the time a heartbeat's seed or start
///   touched), the change events (the time they touched) and the daily prune (all) delete them. Nightscout keeps the
///   time before the local data and between the sessions.
/// - A dose is what the file says it is, for as long as the file holds it. A final row (or one that left the file) is
///   never deleted for being missing from the list: only by an explicit deletion (`pumpHistoryDeletions`: DataTable,
///   the raw JSON editor). A corrupt file reads as `[]`, and a clock set ahead and back trims real events.
/// - `start()` only registers observers: it awaits no Core Data, so it doesn't delay the startup or the loop.
/// - Nothing on the dosing side reads or waits on this store. The observers are buffered (AsyncStream) and only mark
///   the store dirty, so the senders (the pump history storage, the loop) never wait for it.
/// - After a save that changed rows, `appCoordinator.insulinDataChanged` gets the time the change touched.
/// - The pump sessions (`PumpSession`, `PumpSessionRules`): started by the pump driver's change events
///   (`pumpLifecycleEvents`), extended and closed by the reconcile's heartbeat, seeded from the loops while there is
///   none. The statistics read them (the coverage, the Patches topic, the local time).
///   - The seed runs only while there is no pump session. Minimed re-sends its last `.infusionSet` with every fetch
///     (35 min back, and after a relaunch), so on the first launch with this model it can start a site session before
///     the first delivering heartbeat, and the loop-record seed is then skipped. The time before the event, back to
///     the oldest dose row, stays uncovered (possibly days), and the first heartbeat records a gap from the event's
///     date to now. Accepted. That stretch is local time all the same (`PumpSessionRules.localTime`: the pump's dose
///     rows before the first session): the backfill imports no Nightscout dose there, and only the Nightscout sessions
///     import (a prefix, a session before it) can cover it.
///   - The insulin backfill writes the Nightscout sessions (`storeNightscoutSessions`): before the oldest pump session
///     only, plus that one's prefix; the seed adopts the Nightscout session of its unit's change.
///   - A tube pump's seed (no activation) reaches back to the list's oldest row (the 24 h file) only: a site isn't
///     known before it, and a seed back to the oldest stored dose would make one site of months.
///   - A session failure (a `PumpSession` or `LoopStatRecord` read) is logged and never fails the dose mirror: at
///     debug every time, as a warning once per distinct error or hour.
actor PumpEventStore: AppService, LifetimeOwner {
    enum Config {
        /// a heartbeat within this of the session's last one extends it without a gap; also the gap between seeded
        /// loops (`PumpSessionRules.Config.slack`)
        static let coverageSlack: TimeInterval = .minutes(15)
        static let retention: TimeInterval = .days(120)
        /// the coverage rows' kind of earlier builds: the prune deletes them
        static let coverageKind: Int16 = 9
        /// the dates of one `date IN` read of the pump rows (the identity lookup of the Nightscout rows' removal)
        static let identityChunk = 300
        /// the stored rows a reconcile reads start this much before the oldest event of the list
        static let storedLookback: TimeInterval = .minutes(1)
        /// a mutable row missing from the list is deleted only from 24 h ago plus this on (the file trims at 24 h)
        static let deletionMargin: TimeInterval = .minutes(5)
        static let fileWindow: TimeInterval = .hours(24)
        /// Nightscout records per backfill batch (one background task, one save, each)
        static let backfillBatchSize = 5000
        /// a closed loop sets a temp at least every 30 min: a longer stretch without one starting means nothing was
        /// uploaded, so the Nightscout evidence (the Nightscout sessions' covered time) ends there
        static let nightscoutCoverageGap: TimeInterval = .hours(3)
        /// AAPS and Loop set no neutral temps: a quiet night at the profile basal can pass without a temp or an SMB.
        /// Their evidence (temps and pump boluses) is read with this gap instead.
        static let sparseCoverageGap: TimeInterval = .hours(12)
        /// a session heartbeat failure warns again after this (`sessionFailureWarns`)
        static let sessionFailureInterval: TimeInterval = .hours(1)
    }

    /// The entity names (the Settings wipe list shows them).
    enum Entity {
        static let events = "PumpEvent"
        static let schedules = "BasalScheduleRecord"
        static let sessions = "PumpSession"
    }

    struct ReconcileRequest: Sendable, Equatable {
        /// the list mapped to records, newest -> oldest
        let current: [PumpEventRecord]
        let now: Date
        /// the pump sessions' heartbeat (`PumpSessionRules.step`); `unknown` while the seed waits for a list
        let heartbeat: PumpHeartbeat
    }

    struct ReconcileResult: Sendable, Equatable {
        var inserted = 0
        var updated = 0
        var deleted = 0
        /// Nightscout dose rows deleted: inside the file's time, or the time the heartbeat's writes made local
        var nightscoutRemoved = 0
        /// the time the changed rows (events and pump sessions) touch; nil when nothing changed
        var changed: DateInterval?
        /// what the heartbeat did to the pump sessions, other than extending the open one (the log)
        var sessionLog: [String] = []
        /// why the pump sessions' heartbeat failed (the events were saved without it)
        var sessionFailure: String?
    }

    /// What a batch of change events did (`applyLifecycleEvents`).
    struct LifecycleResult: Sendable, Equatable {
        /// one line per event, in date order, then one per session it closed (the log)
        var log: [String] = []
        /// the time the sessions written touched (`CoreDataPumpEventDatabase.touched`); nil when none was
        var changed: DateInterval?
    }

    struct ScheduleInsert: Sendable, Equatable {
        let date: Date
        let entries: String
        let fingerprint: String
    }

    /// One batch of the Nightscout backfill.
    struct BackfillBatch: Sendable, Equatable {
        /// `source = nightscout`, one per identity
        let records: [PumpEventRecord]
        /// what the 24 h file covers: `min(now - 24 h, its oldest event)` on, when the batch runs
        let pumpKnownFrom: Date
        /// when the batch runs: the change of an inserted event reaches up to the next one, or this
        let now: Date
    }

    struct BackfillBatchResult: Sendable, Equatable {
        var inserted = 0
        var updated = 0
        /// dropped: inside the pump's local time (`PumpSessionRules.localTime`) or at a pump row's identity (iAPS has
        /// them)
        var skipped = 0
        /// dropped: in the 24 h file's time (any uploader's: the file is the truth there)
        var recent = 0
        var changed: DateInterval?
    }

    /// What `storeBackfill` stored.
    struct BackfillOutcome: Sendable, Equatable {
        var inserted = 0
        var updated = 0
        var skipped = 0
        var recent = 0
        /// why saving stopped: the batches before it are stored
        var error: String?
        /// the newest record of the batch that failed: the records newer than it are stored
        var reached: Date?
    }

    struct PruneResult: Sendable, Equatable {
        /// rows before the cutoff were deleted (events, schedules)
        var changed = false
        /// pump sessions last seen before the cutoff were deleted
        var sessionsDeleted = false
        /// from the oldest old start of the sessions clipped to the cutoff
        var clippedSessions: DateInterval?
        /// the coverage rows of earlier builds deleted (kind 9; also those an older build writes after a downgrade).
        /// Nothing reads them.
        var otherKindsDeleted = 0
        /// Nightscout dose rows deleted inside what the pump knows (`CoreDataPumpEventDatabase.PumpKnowledge`: stored
        /// by an import before the strict rule), and the time they touched
        var nightscoutRemoved = 0
        var nightscoutChanged: DateInterval?
    }

    struct ScheduleBackfillResult: Sendable, Equatable {
        var inserted = 0
        var updated = 0
        var changed: DateInterval?
    }

    /// The Nightscout pump sessions of a backfill (`storeNightscoutSessions`).
    struct NightscoutSessionsRequest: Sendable, Equatable {
        let input: NightscoutSessionsInput
        /// the current pump's plugin (a tube pump's sessions are sites); nil without one
        let plugin: String?
        let now: Date
        /// the retention's start: nothing is written before it
        let cutoff: Date
    }

    struct NightscoutSessionsResult: Sendable, Equatable {
        /// the Nightscout sessions built (`PumpSessionRules.nightscoutSessions`), and of them the new ones and the
        /// changed ones (the rest were stored as they are)
        var sessions = 0
        var inserted = 0
        var updated = 0
        /// stored Nightscout sessions deleted: replaced in the window, or inside the local sessions' time
        var deleted = 0
        /// stored Nightscout sessions no new one took over, kept for the user's fields
        var kept = 0
        /// the oldest pump session's prefix changed
        var prefixed = false
        /// the window replaced; nil: none (nothing fetched before the oldest pump session's local start)
        var window: DateInterval?
        var changed: DateInterval?
    }

    let lifetime = Lifetime()

    private let appCoordinator: AppCoordinator
    private let database: PumpEventDatabase
    private let calendar: @Sendable() -> Calendar
    private let now: @Sendable() -> Date
    private let serializer = TaskSerializer()

    /// a trigger came in since the last reconcile read the list
    private var dirty = false
    /// a reconcile is queued and hasn't started yet: the triggers coalesce into it
    private var queued = false
    /// the newest queued reconcile (`idle`)
    private var lastReconcile: Task<Void, Never>?
    /// no non-empty list was read yet in this process (or since a wipe): the heartbeat waits (`unknown`), as the
    /// session seed reads the list's oldest event (the subject's initial `[]` at startup)
    private var awaitsList = true
    /// the start of the local day the prune last ran on
    private var lastPruneDay: Date?
    /// change event batches waiting for the serializer or applying (the tests)
    private(set) var queuedChangeBatches = 0
    /// the session heartbeat's last failure warned about, and when
    private var lastSessionFailureWarning: (description: String, at: Date)?

    init(
        appCoordinator: AppCoordinator,
        database: PumpEventDatabase = CoreDataPumpEventDatabase(),
        calendar: @escaping @Sendable() -> Calendar = { .autoupdatingCurrent },
        now: @escaping @Sendable() -> Date = { Date() }
    ) {
        self.appCoordinator = appCoordinator
        self.database = database
        self.calendar = calendar
        self.now = now
    }

    /// Registers the observers only. The two triggers keep just the newest value: the reconcile reads the list itself.
    func start() async {
        observe(appCoordinator.pumpHistory.map { _ in () }, bufferingPolicy: .bufferingNewest(1)) { me, _ in
            await me.requestReconcile()
        }
        // the pump sessions' heartbeat: every loop, failed ones too
        observe(appCoordinator.loopCompleted.map { _ in () }, bufferingPolicy: .bufferingNewest(1)) { me, _ in
            await me.requestReconcile()
        }
        observe(appCoordinator.pumpHistoryDeletions) { me, deleted in
            await me.deleted(deleted)
        }
        observe(appCoordinator.basalProfile) { me, profile in
            await me.basalProfileChanged(profile)
        }
        // unbounded: every batch is applied, in order, also while the serializer is busy (a backfill)
        observe(appCoordinator.pumpLifecycleEvents) { me, events in
            await me.lifecycleEvents(events)
        }
    }

    // MARK: - Live mirror

    /// Marks the store dirty and queues one reconcile, unless one is queued already. Returns at once.
    func requestReconcile() {
        dirty = true
        guard !queued else { return }
        queued = true
        lastReconcile = Task { await self.runQueuedReconcile() }
    }

    /// Returns once no reconcile is queued or running (the tests).
    func idle() async {
        while let task = lastReconcile {
            await task.value
            if lastReconcile == task {
                lastReconcile = nil
            }
        }
    }

    private func runQueuedReconcile() async {
        await serializer.run {
            // a trigger from here on queues another reconcile, which reads the list again
            queued = false
            guard dirty else { return }
            dirty = false
            await reconcile()
        }
    }

    /// One reconcile (on the serializer): the list as it is now against the stored rows, the pump sessions' heartbeat,
    /// the prune.
    private func reconcile() async {
        let now = self.now()
        let current = PumpEventRecord.records(from: appCoordinator.pumpHistory.value)
        let pumpInfo = appCoordinator.pumpInfo.value
        // the session seed waits for a list (the subject's initial [] at startup): it reads the list's oldest event
        // (a fresh install, a wipe; a tube pump's site starts no earlier)
        let waitsForList = awaitsList && current.isEmpty
        let request = ReconcileRequest(
            current: current,
            now: now,
            heartbeat: waitsForList ? PumpHeartbeat(state: .unknown, now: now) : PumpHeartbeat(info: pumpInfo, now: now)
        )
        do {
            let result = try await database.reconcile(request)
            if current.isNotEmpty {
                awaitsList = false
            }
            if result.inserted + result.updated + result.deleted + result.nightscoutRemoved > 0 {
                debug(
                    .service,
                    "Pump event store: \(result.inserted) inserted, \(result.updated) updated, \(result.deleted) deleted, " +
                        "\(result.nightscoutRemoved) Nightscout rows removed"
                )
            }
            for line in result.sessionLog {
                debug(.service, line)
            }
            if let failure = result.sessionFailure {
                debug(.service, "Pump event store: the pump session heartbeat failed: \(failure)")
                if sessionFailureWarns(failure, now: now) {
                    warning(.service, "Pump event store: the pump session heartbeat failed", description: failure)
                }
            }
            if let changed = result.changed {
                appCoordinator.sendInsulinDataChanged(.interval(changed))
            }
        } catch {
            warning(.service, "Pump event store: reconcile failed", error: error)
        }
        await pruneIfDue(now)
    }

    /// A session heartbeat failure files a warning (an issue report) once per distinct error, or an hour after the
    /// last one warned about (either way of the clock); every one is logged at debug. Returns whether it warns.
    func sessionFailureWarns(_ description: String, now: Date) -> Bool {
        if let last = lastSessionFailureWarning, last.description == description,
           abs(now.timeIntervalSince(last.at)) < Config.sessionFailureInterval
        {
            return false
        }
        lastSessionFailureWarning = (description, now)
        return true
    }

    /// UTC, to the second (the "Pump lifecycle:" lines' form).
    static func logDate(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    // MARK: - Pump change events

    /// One `hasNewPumpEvents` call's change events (`pumpLifecycleEvents`), on the serializer: one line per event in
    /// the log, and the change signal with the sessions' time.
    func lifecycleEvents(_ events: [PumpLifecycleEvent]) async {
        guard events.isNotEmpty else { return }
        queuedChangeBatches += 1
        defer { queuedChangeBatches -= 1 }
        await serializer.run {
            do {
                let result = try await database.applyLifecycleEvents(events, now: self.now())
                for line in result.log {
                    debug(.service, line)
                }
                if let changed = result.changed {
                    appCoordinator.sendInsulinDataChanged(.interval(changed))
                }
            } catch {
                warning(.service, "Pump event store: applying the pump change events failed", error: error)
            }
        }
    }

    // MARK: - Explicit deletions

    /// DataTable's `deleteInsulin` and the raw JSON editor (`pumpHistoryDeletions`): the rows go, final or not.
    func deleted(_ events: [PumpHistoryEvent]) async {
        let identities = Set(events.compactMap { PumpEventRecord.identity(of: $0) })
        guard identities.isNotEmpty else { return }
        await serializer.run {
            do {
                if let changed = try await database.deleteEvents(identities, now: self.now()) {
                    appCoordinator.sendInsulinDataChanged(.interval(changed))
                }
            } catch {
                warning(.service, "Pump event store: deleting failed", error: error)
            }
        }
    }

    // MARK: - Basal schedule history

    /// Every `basalProfile` value: the subject's initial `[]` is ignored, and so is a schedule equal to the newest
    /// record's. Otherwise a `source = local` record at `now` (the first one seeds the history).
    func basalProfileChanged(_ entries: [BasalProfileEntry]) async {
        guard entries.isNotEmpty else { return }
        await serializer.run {
            let now = self.now()
            if await recordSchedule(entries, at: now) {
                // only from the change on: past days keep their own schedule
                appCoordinator.sendInsulinDataChanged(.interval(DateInterval(start: now, duration: 0)))
            }
        }
    }

    private func recordSchedule(_ entries: [BasalProfileEntry], at date: Date) async -> Bool {
        guard let json = BasalScheduleRecordValue.encode(entries) else { return false }
        let schedule = ScheduleInsert(
            date: date,
            entries: json,
            fingerprint: BasalScheduleRecordValue.fingerprint(entries)
        )
        do {
            return try await database.recordSchedule(schedule)
        } catch {
            warning(.service, "Pump event store: recording the basal schedule failed", error: error)
            return false
        }
    }

    // MARK: - Settings wipe

    /// The Settings wipe of `PumpEvent`: every row of it and of `PumpSession` goes (the sessions' entered fields too),
    /// then the last 24 h come back at once from the list, and the first delivering heartbeat seeds a session.
    func wipe() async {
        await serializer.run {
            do {
                try await database.wipeEvents()
            } catch {
                warning(.service, "Pump event store: wiping failed", error: error)
                return
            }
            awaitsList = true
            appCoordinator.sendInsulinDataChanged(.all)
            await reconcile()
        }
    }

    /// The Settings wipe of `PumpSession`: every session goes (entered fields too), the events stay; the reconcile
    /// right after it seeds the delivering unit's session again. Until then the local time is all of it from the oldest
    /// pump dose on (`PumpSessionRules.localTime`): Nightscout doses older than the pump's own rows are kept; those
    /// between them are dropped.
    func wipeSessions() async {
        await serializer.run {
            do {
                try await database.wipeSessions()
            } catch {
                warning(.service, "Pump event store: wiping the pump sessions failed", error: error)
                return
            }
            appCoordinator.sendInsulinDataChanged(.all)
            await reconcile()
        }
    }

    /// The Settings wipe of `BasalScheduleRecord`: the history restarts from the current schedule.
    func wipeSchedules() async {
        await serializer.run {
            do {
                try await database.wipeSchedules()
            } catch {
                warning(.service, "Pump event store: wiping the basal schedules failed", error: error)
                return
            }
            let entries = appCoordinator.basalProfile.value
            if entries.isNotEmpty {
                _ = await recordSchedule(entries, at: self.now())
            }
            appCoordinator.sendInsulinDataChanged(.all)
        }
    }

    // MARK: - Nightscout backfill

    /// The insulin backfill's records (`source = nightscout`), in batches of `backfillBatchSize` contiguous in time,
    /// newest first, each one background task with one save on the serializer (a live reconcile waits one batch at
    /// most), so an interrupted backfill keeps what it stored. What the pump knows is left out: the 24 h file (from
    /// `min(now - 24 h, its oldest event)` on), the local time (`PumpSessionRules.localTime`: every pump session's whole
    /// `[localStart, lastSeen]`, the dose rows before the first one), the pump rows' identities. Nightscout writes only
    /// before the local data and between the sessions. Upserted by identity among the Nightscout rows, so a re-run
    /// doubles nothing.
    /// After each saved batch that changed rows, the change signal with its span. `progress`: the fraction of the
    /// batches stored.
    func storeBackfill(
        _ records: [PumpEventRecord],
        batchSize: Int = Config.backfillBatchSize,
        progress: (@MainActor @Sendable(Double) async -> Void)? = nil
    ) async -> BackfillOutcome {
        let batches = Self.backfillBatches(records, size: batchSize)
        var outcome = BackfillOutcome()
        for (number, batch) in batches.enumerated() {
            let result: BackfillBatchResult
            do {
                result = try await serializer.run {
                    // read when the batch runs: the list moves on during a backfill
                    let now = self.now()
                    let oldestCurrent = PumpEventRecord.records(from: appCoordinator.pumpHistory.value).map(\.date).min()
                    let pumpKnownFrom = Swift.min(now.addingTimeInterval(-Config.fileWindow), oldestCurrent ?? now)
                    return try await database.storeBackfill(BackfillBatch(
                        records: batch,
                        pumpKnownFrom: pumpKnownFrom,
                        now: now
                    ))
                }
            } catch {
                warning(.service, "Pump event store: storing the Nightscout backfill failed", error: error)
                outcome.error = error.localizedDescription
                outcome.reached = batch.map(\.date).max()
                return outcome
            }
            outcome.inserted += result.inserted
            outcome.updated += result.updated
            outcome.skipped += result.skipped
            outcome.recent += result.recent
            if let changed = result.changed {
                appCoordinator.sendInsulinDataChanged(.interval(changed))
            }
            await progress?(Double(number + 1) / Double(batches.count))
        }
        debug(
            .service,
            "Pump event store: Nightscout backfill \(outcome.inserted) inserted, \(outcome.updated) updated, " +
                "\(outcome.skipped) skipped, \(outcome.recent) in the last 24 h"
        )
        return outcome
    }

    /// The basal schedules from Nightscout: only before the oldest local record (local records win from their start
    /// on), and none equal to the record in effect before it. Upserted by identity among the Nightscout rows; one save.
    /// The change signal with the span from the oldest imported record to the first local one.
    func storeScheduleBackfill(_ schedules: [NightscoutBasalSchedule]) async -> Result<Int, Error> {
        let inserts = schedules.compactMap { schedule -> ScheduleInsert? in
            guard let json = BasalScheduleRecordValue.encode(schedule.entries) else { return nil }
            return ScheduleInsert(
                date: schedule.date.truncatedToSecond,
                entries: json,
                fingerprint: BasalScheduleRecordValue.fingerprint(schedule.entries)
            )
        }
        guard inserts.isNotEmpty else { return .success(0) }
        do {
            let now = self.now()
            let result = try await serializer.run { try await database.storeSchedules(inserts, now: now) }
            if let changed = result.changed {
                appCoordinator.sendInsulinDataChanged(.interval(changed))
            }
            return .success(result.inserted + result.updated)
        } catch {
            warning(.service, "Pump event store: storing the Nightscout basal schedules failed", error: error)
            return .failure(error)
        }
    }

    /// The Nightscout pump sessions of an insulin backfill, after its batches, on the serializer: built
    /// (`PumpSessionRules.nightscoutSessions`) for the current pump from the input's oldest record up to the oldest
    /// pump session's local start (now without one; nothing when that isn't after it), that session's prefix
    /// rewritten, the stored Nightscout sessions of the window replaced (a re-run keeps their ids and entered fields),
    /// and those inside the local sessions' time without the user's fields deleted: Nightscout never fills a hole
    /// between local sessions. One save, the change signal with the time it touched. nil when it failed (logged). The
    /// backfill calls it only when it stored insulin records: without them there is no evidence, and the window's
    /// stored sessions would be replaced by none.
    @discardableResult func storeNightscoutSessions(_ input: NightscoutSessionsInput) async -> NightscoutSessionsResult? {
        await serializer.run { () -> NightscoutSessionsResult? in
            let now = self.now()
            let info = appCoordinator.pumpInfo.value
            let request = NightscoutSessionsRequest(
                input: input,
                plugin: info.flatMap { $0.isOnboarded ? $0.identifier : nil },
                now: now,
                cutoff: now.addingTimeInterval(-Config.retention)
            )
            do {
                let result = try await database.storeNightscoutSessions(request)
                debug(.service, Self.describe(result, request))
                if let changed = result.changed {
                    appCoordinator.sendInsulinDataChanged(.interval(changed))
                }
                return result
            } catch {
                warning(.service, "Pump event store: storing the Nightscout pump sessions failed", error: error)
                return nil
            }
        }
    }

    /// One line for the log: counts and the window, no values.
    static func describe(_ result: NightscoutSessionsResult, _ request: NightscoutSessionsRequest) -> String {
        let input = request.input
        let window = result.window.map { "\(logDate($0.start))–\(logDate($0.end))" } ?? "none"
        return "Pump event store: Nightscout sessions of \(request.plugin ?? "no pump") from " +
            "\(input.siteChanges.count) Site Changes, \(input.alarms.count) alarms over \(window): " +
            "\(result.sessions) sessions (\(result.inserted) new, \(result.updated) changed), \(result.deleted) deleted, " +
            "\(result.kept) kept for the user's fields" + (result.prefixed ? ", the oldest pump session's prefix" : "")
    }

    // MARK: - Retention

    /// On the first reconcile of each local day: events older than the retention go, the sessions are clipped to it,
    /// the schedules are kept from the one in effect at the cutoff on, the coverage rows of earlier builds (kind 9) go
    /// whatever their date, and so do the Nightscout dose rows the pump knows (an import before the strict rule).
    private func pruneIfDue(_ now: Date) async {
        let day = calendar().startOfDay(for: now)
        guard lastPruneDay != day else { return }
        let cutoff = now.addingTimeInterval(-Config.retention)
        do {
            let result = try await database.prune(cutoff: cutoff)
            lastPruneDay = day
            if result.otherKindsDeleted > 0 {
                debug(.service, "Pump event store: \(result.otherKindsDeleted) coverage rows of earlier builds deleted")
            }
            if result.nightscoutRemoved > 0 {
                debug(
                    .service,
                    "Pump event store: \(result.nightscoutRemoved) Nightscout dose rows inside the pump's local time deleted"
                )
            }
            // rows before the cutoff: the days before it, and the one around it (the coverage rows aren't read); the
            // Nightscout rows removed
            var changed: [DateInterval] = []
            if result.changed {
                changed.append(DateInterval(start: cutoff.addingTimeInterval(-.days(1)), end: cutoff))
            }
            if let removed = result.nightscoutChanged {
                changed.append(removed)
            }
            // a clipped session from its old start; deleted ones (last seen before the cutoff) as the events
            if let clipped = result.clippedSessions {
                changed.append(clipped)
            }
            if result.sessionsDeleted {
                changed.append(DateInterval(start: cutoff.addingTimeInterval(-.days(1)), end: cutoff))
            }
            if let start = changed.map(\.start).min(), let end = changed.map(\.end).max() {
                appCoordinator.sendInsulinDataChanged(.interval(DateInterval(start: start, end: end)))
            }
        } catch {
            warning(.service, "Pump event store: pruning failed", error: error)
        }
    }

    // MARK: - Rules (static, pure)

    struct Diff: Sendable, Equatable {
        struct Update: Sendable, Equatable {
            /// into `stored`
            let index: Int
            /// the new values
            let record: PumpEventRecord
        }

        var inserts: [PumpEventRecord] = []
        var updates: [Update] = []
        /// into `stored`
        var deletes: [Int] = []

        var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
    }

    /// The list against the stored pump rows (`date >= oldest current - storedLookback`):
    /// - in current, not stored: insert
    /// - in both, the signature changed: update in place
    /// - stored, not in current: deleted only when the row is mutable (a dose a `replacePendingEvents` batch no
    ///   longer reports) and dated from `max(now - 24 h + 5 min, oldest current)` on. A final is never deleted for
    ///   being missing: a list can lose finals without any deletion (a corrupt file, a clock correction).
    /// - a second stored row with an identity: deleted (one row per identity)
    /// An empty list changes nothing.
    static func diff(current: [PumpEventRecord], stored: [PumpEventRecord], now: Date) -> Diff {
        guard let oldestCurrent = current.map(\.date).min() else { return Diff() }
        let deletableFrom = Swift.max(
            now.addingTimeInterval(-Config.fileWindow + Config.deletionMargin),
            oldestCurrent
        )

        var byIdentity: [PumpEventRecord.Identity: PumpEventRecord] = [:]
        for record in current where byIdentity[record.identity] == nil {
            byIdentity[record.identity] = record
        }

        var diff = Diff()
        var seen = Set<PumpEventRecord.Identity>()
        for (index, row) in stored.enumerated() {
            guard seen.insert(row.identity).inserted else {
                diff.deletes.append(index)
                continue
            }
            if let record = byIdentity[row.identity] {
                if record.signature != row.signature {
                    diff.updates.append(Diff.Update(index: index, record: record))
                }
            } else if row.isMutable, row.date >= deletableFrom {
                diff.deletes.append(index)
            }
        }

        var inserted = Set<PumpEventRecord.Identity>()
        for record in current where !seen.contains(record.identity) && inserted.insert(record.identity).inserted {
            diff.inserts.append(record)
        }
        return diff
    }

    // MARK: Nightscout backfill rules

    /// The backfill's records in batches of at most `size`, newest first: each contiguous in time.
    static func backfillBatches(_ records: [PumpEventRecord], size: Int) -> [[PumpEventRecord]] {
        let sorted = records.sorted { $0.date > $1.date }
        guard sorted.isNotEmpty, size > 0 else { return [] }
        return stride(from: 0, to: sorted.count, by: size).map { Array(sorted[$0 ..< Swift.min($0 + size, sorted.count)]) }
    }

    /// The Nightscout evidence the fetched temps give (the Nightscout sessions' covered time): from the oldest temp start
    /// to the newest, split wherever `gap` or more passes without one starting. A lone temp gives none. No temp: none
    /// (boluses count, basal is unknown).
    static func nightscoutCoverage(tempStarts: [Date], gap: TimeInterval = Config.nightscoutCoverageGap) -> [DateInterval] {
        var intervals: [DateInterval] = []
        var start: Date?
        var last: Date?
        for time in tempStarts.sorted() {
            if let previous = last, time.timeIntervalSince(previous) < gap {
                last = time
                continue
            }
            if let start, let last, last > start {
                intervals.append(DateInterval(start: start, end: last))
            }
            start = time
            last = time
        }
        if let start, let last, last > start {
            intervals.append(DateInterval(start: start, end: last))
        }
        return intervals
    }

    /// The parts of the intervals inside `span`; empty parts dropped.
    static func intersect(_ intervals: [DateInterval], with span: DateInterval) -> [DateInterval] {
        StatsIntervals.intersect(intervals, with: span)
    }

    /// The intervals without the parts in `removed`, oldest first; empty parts dropped.
    static func subtract(_ intervals: [DateInterval], _ removed: [DateInterval]) -> [DateInterval] {
        StatsIntervals.subtract(intervals, removed)
    }

    /// Overlapping or touching intervals as one, oldest first; empty ones dropped.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        StatsIntervals.mergedDroppingEmpty(intervals)
    }
}

// MARK: - Core Data

/// `PumpEventDatabase` on background contexts of the container (never the viewContext). `container`, the batch
/// delete merge, the session heartbeat and the reconcile's knowledge are for the tests: the app uses the shared stack,
/// `sessionHeartbeat` and `pumpKnowledge`.
struct CoreDataPumpEventDatabase: PumpEventDatabase {
    private typealias Store = PumpEventStore
    typealias SessionHeartbeat = @Sendable(PumpHeartbeat, Date?, NSManagedObjectContext) throws
        -> (changed: [DateInterval], log: [String])
    /// `pumpKnowledge(fileFrom:pendingOldest:in:)`
    typealias ReconcileKnowledge = @Sendable(Date?, Date?, NSManagedObjectContext) throws -> PumpKnowledge

    let container: NSPersistentContainer
    let mergeBatchDelete: @Sendable([NSManagedObjectID]) -> Void
    let sessionHeartbeat: SessionHeartbeat
    /// the reconcile's `pumpKnowledge` (the tests make it fail)
    let reconcileKnowledge: ReconcileKnowledge

    init(
        container: NSPersistentContainer = CoreDataStack.shared.persistentContainer,
        mergeBatchDelete: @escaping @Sendable([NSManagedObjectID]) -> Void = { CoreDataStack.shared.mergeBatchDelete($0) },
        sessionHeartbeat: @escaping SessionHeartbeat = {
            try CoreDataPumpEventDatabase.sessionHeartbeat($0, oldestCurrent: $1, in: $2) },
        reconcileKnowledge: @escaping ReconcileKnowledge = {
            try CoreDataPumpEventDatabase.pumpKnowledge(fileFrom: $0, pendingOldest: $1, in: $2) }
    ) {
        self.container = container
        self.mergeBatchDelete = mergeBatchDelete
        self.sessionHeartbeat = sessionHeartbeat
        self.reconcileKnowledge = reconcileKnowledge
    }

    func reconcile(_ request: PumpEventStore.ReconcileRequest) async throws -> PumpEventStore.ReconcileResult {
        let heartbeat = sessionHeartbeat
        let knowledge = reconcileKnowledge
        return try await container.performBackgroundTask { context in
            try Self.reconcile(request, in: context, sessionHeartbeat: heartbeat, knowledge: knowledge)
        }
    }

    func deleteEvents(_ identities: Set<PumpEventRecord.Identity>, now: Date) async throws -> DateInterval? {
        try await container.performBackgroundTask { context in
            try Self.deleteEvents(identities, now: now, in: context)
        }
    }

    func prune(cutoff: Date) async throws -> PumpEventStore.PruneResult {
        let merge = mergeBatchDelete
        return try await container.performBackgroundTask { context in
            try Self.prune(cutoff: cutoff, in: context, merge: merge)
        }
    }

    func wipeEvents() async throws {
        let merge = mergeBatchDelete
        try await container.performBackgroundTask { context in
            // the sessions first: a failure between the two never leaves sessions without their events
            _ = try Self.batchDelete(Store.Entity.sessions, predicate: nil, in: context, merge: merge)
            _ = try Self.batchDelete(Store.Entity.events, predicate: nil, in: context, merge: merge)
        }
    }

    func wipeSessions() async throws {
        let merge = mergeBatchDelete
        try await container.performBackgroundTask { context in
            _ = try Self.batchDelete(Store.Entity.sessions, predicate: nil, in: context, merge: merge)
        }
    }

    func applyLifecycleEvents(_ events: [PumpLifecycleEvent], now: Date) async throws -> PumpEventStore.LifecycleResult {
        try await container.performBackgroundTask { context in
            try Self.applyLifecycleEvents(events, now: now, in: context)
        }
    }

    func recordSchedule(_ schedule: PumpEventStore.ScheduleInsert) async throws -> Bool {
        try await container.performBackgroundTask { context in
            try Self.recordSchedule(schedule, in: context)
        }
    }

    func wipeSchedules() async throws {
        let merge = mergeBatchDelete
        try await container.performBackgroundTask { context in
            _ = try Self.batchDelete(Store.Entity.schedules, predicate: nil, in: context, merge: merge)
        }
    }

    func storeBackfill(_ batch: PumpEventStore.BackfillBatch) async throws -> PumpEventStore.BackfillBatchResult {
        try await container.performBackgroundTask { context in
            try Self.storeBackfill(batch, in: context)
        }
    }

    func storeSchedules(_ schedules: [PumpEventStore.ScheduleInsert], now: Date) async throws -> PumpEventStore
        .ScheduleBackfillResult
    {
        try await container.performBackgroundTask { context in
            try Self.storeSchedules(schedules, now: now, in: context)
        }
    }

    func storeNightscoutSessions(_ request: PumpEventStore.NightscoutSessionsRequest) async throws -> PumpEventStore
        .NightscoutSessionsResult
    {
        try await container.performBackgroundTask { context in
            try Self.storeNightscoutSessions(request, in: context)
        }
    }

    // MARK: Rows <-> records

    static func record(of row: PumpEvent) -> PumpEventRecord? {
        guard let date = row.date,
              let kind = PumpEventKind(rawValue: row.kind),
              let source = PumpEventSource(rawValue: row.source)
        else { return nil }
        return PumpEventRecord(
            date: date,
            kind: kind,
            source: source,
            units: row.units,
            rate: row.rate,
            durationMin: row.durationMin,
            isSMB: row.isSMB,
            isExternal: row.isExternal,
            isMutable: row.isMutable
        )
    }

    static func apply(_ record: PumpEventRecord, to row: PumpEvent) {
        row.date = record.date
        row.kind = record.kind.rawValue
        row.source = record.source.rawValue
        row.units = record.units
        row.rate = record.rate
        row.durationMin = record.durationMin
        row.isSMB = record.isSMB
        row.isExternal = record.isExternal
        row.isMutable = record.isMutable
    }

    /// nil without an id, a start, a last seen or a known source.
    static func value(of row: PumpSession) -> PumpSessionValue? {
        guard let id = row.id, let start = row.start, let lastSeen = row.lastSeen,
              let source = PumpEventSource(rawValue: row.source)
        else { return nil }
        return PumpSessionValue(
            id: id,
            source: source,
            plugin: row.plugin,
            activation: row.activation,
            start: start,
            localStart: row.localStart,
            lastSeen: lastSeen,
            end: row.end,
            gaps: PumpSessionValue.decodeGaps(row.gaps),
            flags: PumpSessionValue.Flags(rawValue: row.flags),
            site: row.site,
            filledUnits: row.filledUnits?.doubleValue,
            fillSource: PumpSessionValue.FieldSource(rawValue: row.fillSource) ?? .none,
            endReason: row.endReason.flatMap { PatchEndReason(rawValue: $0) },
            endReasonSource: PumpSessionValue.FieldSource(rawValue: row.endReasonSource) ?? .none
        )
    }

    static func apply(_ value: PumpSessionValue, to row: PumpSession) {
        row.id = value.id
        row.source = value.source.rawValue
        row.plugin = value.plugin
        row.activation = value.activation
        row.start = value.start
        row.localStart = value.localStart
        row.lastSeen = value.lastSeen
        row.end = value.end
        row.gaps = PumpSessionValue.encodeGaps(value.gaps)
        row.flags = value.flags.rawValue
        row.site = value.site
        row.filledUnits = value.filledUnits.map { NSNumber(value: $0) }
        row.fillSource = value.fillSource.rawValue
        row.endReason = value.endReason?.rawValue
        row.endReasonSource = value.endReasonSource.rawValue
    }

    /// the doses' kinds (0–3): the rows of any other kind (the coverage rows of earlier builds, which the prune deletes)
    /// are read by nothing
    private static var doseKinds: [NSNumber] { PumpEventKind.allCases.map { NSNumber(value: $0.rawValue) } }
    private static var pump: NSNumber { NSNumber(value: PumpEventSource.pump.rawValue) }
    private static var nightscout: NSNumber { NSNumber(value: PumpEventSource.nightscout.rawValue) }

    // MARK: Operations (inside one background task)

    static func reconcile(
        _ request: PumpEventStore.ReconcileRequest,
        in context: NSManagedObjectContext,
        sessionHeartbeat: SessionHeartbeat = { try CoreDataPumpEventDatabase.sessionHeartbeat($0, oldestCurrent: $1, in: $2) },
        knowledge: ReconcileKnowledge = { try CoreDataPumpEventDatabase.pumpKnowledge(fileFrom: $0, pendingOldest: $1, in: $2) }
    ) throws -> PumpEventStore.ReconcileResult {
        var result = PumpEventStore.ReconcileResult()
        var changed: [DateInterval] = []
        // the events inserted or deleted: their change reaches on to the next event that ends a temp or a suspension
        var affected: [PumpEventRecord] = []
        let oldestCurrent = request.current.map(\.date).min()

        // 1-3. the events: with an empty list nothing is read
        if let oldestCurrent {
            let fetch = NSFetchRequest<PumpEvent>(entityName: Store.Entity.events)
            fetch.predicate = NSPredicate(
                format: "source == %@ AND kind IN %@ AND date >= %@",
                pump,
                doseKinds,
                oldestCurrent.addingTimeInterval(-Store.Config.storedLookback) as NSDate
            )
            let rows = try context.fetch(fetch).compactMap { row in Self.record(of: row).map { (row: row, record: $0) } }
            let diff = Store.diff(current: request.current, stored: rows.map(\.record), now: request.now)

            for index in diff.deletes {
                context.delete(rows[index].row)
                changed.append(rows[index].record.span)
                affected.append(rows[index].record)
            }
            for update in diff.updates {
                changed.append(rows[update.index].record.span)
                apply(update.record, to: rows[update.index].row)
                changed.append(update.record.span)
            }
            for record in diff.inserts {
                apply(record, to: PumpEvent(context: context))
                changed.append(record.span)
                affected.append(record)
            }
            result.inserted = diff.inserts.count
            result.updated = diff.updates.count
            result.deleted = diff.deletes.count
        }

        // the pump sessions' heartbeat. Its reads come before its writes, so a failure leaves nothing of it in the
        // context: logged, the events saved without it.
        var sessionsChanged: [DateInterval] = []
        do {
            let heartbeat = try sessionHeartbeat(request.heartbeat, oldestCurrent, context)
            sessionsChanged = heartbeat.changed
            changed += heartbeat.changed
            result.sessionLog = heartbeat.log
        } catch {
            result.sessionFailure = "\(error)"
        }

        // 4. the Nightscout dose rows the pump now knows go (`PumpKnowledge`): in the file's time, and in the time the
        // sessions' writes touched (a seed, a start moved back: a backfill that ran before them left rows there)
        let fileFrom = oldestCurrent.map { Swift.min(request.now.addingTimeInterval(-Store.Config.fileWindow), $0) }
        let windows = (fileFrom.map { [DateInterval(start: $0, end: Swift.max($0, request.now))] } ?? []) + sessionsChanged
        result.nightscoutRemoved = try removeNightscout(
            // a failed session read (logged with the heartbeat's) leaves the file's time
            knownBy: {
                (try? knowledge(fileFrom, oldestCurrent, context)) ?? PumpKnowledge(fileFrom: fileFrom, localTime: [])
            },
            within: windows,
            in: context,
            changed: &changed,
            affected: &affected
        )
        if let reach = try reach(of: affected, now: request.now, in: context) {
            changed.append(reach)
        }

        if context.hasChanges {
            try context.save()
        }
        result.changed = union(changed)
        return result
    }

    /// What the pump knows: the time a Nightscout dose row is left out of (the backfill) or deleted from (the reconcile,
    /// the change events, the prune). One rule: the file's time, the local time (`PumpSessionRules.localTime`, both ends
    /// included), a pump row's identity (checked by the callers, against the rows they read).
    struct PumpKnowledge: Sendable, Equatable {
        /// the 24 h file's time: `min(now - 24 h, the list's oldest event)` on; nil: not known here (an empty list at a
        /// reconcile, the change events, the prune)
        let fileFrom: Date?
        let localTime: [DateInterval]

        func knows(_ date: Date) -> Bool {
            fileFrom.map { date >= $0 } == true || PumpSessionRules.isLocal(date, in: localTime)
        }

        /// where it starts knowing anything; nil: nowhere
        var start: Date? { [fileFrom, localTime.first?.start].compactMap { $0 }.min() }
    }

    /// The pump's knowledge in this context (its pending sessions too).
    /// - Parameter pendingOldest: the oldest pump dose row inserted in this context (the list's oldest event)
    static func pumpKnowledge(
        fileFrom: Date?,
        pendingOldest: Date? = nil,
        in context: NSManagedObjectContext
    ) throws -> PumpKnowledge {
        let sessions = try sessionRows(in: context).map(\.value)
        let oldest = try [oldestPumpDose(in: context), pendingOldest].compactMap { $0 }.min()
        return PumpKnowledge(fileFrom: fileFrom, localTime: PumpSessionRules.localTime(sessions, oldestPumpDose: oldest))
    }

    /// Deletes the `source = nightscout` dose rows the pump knows (`PumpKnowledge`: its time, or a pump row's identity)
    /// inside the windows (both ends included). The rows are read first: without one, the knowledge isn't built. Returns
    /// the number deleted; they go into `affected`, their spans into `changed`.
    static func removeNightscout(
        knownBy knowledge: () throws -> PumpKnowledge,
        within windows: [DateInterval],
        in context: NSManagedObjectContext,
        changed: inout [DateInterval],
        affected: inout [PumpEventRecord]
    ) throws -> Int {
        guard let from = windows.map(\.start).min(), let to = windows.map(\.end).max() else { return 0 }
        let fetch = NSFetchRequest<PumpEvent>(entityName: Store.Entity.events)
        fetch.predicate = NSPredicate(
            format: "source == %@ AND kind IN %@ AND date >= %@ AND date <= %@",
            nightscout,
            doseKinds,
            from as NSDate,
            to as NSDate
        )
        let rows = try context.fetch(fetch)
            .compactMap { row in Self.record(of: row).map { (row: row, record: $0) } }
            .filter { entry in windows.contains { $0.start <= entry.record.date && entry.record.date <= $0.end } }
        guard rows.isNotEmpty else { return 0 }
        let known = try knowledge()
        // the pump rows at the dates of those outside the pump's time: read only for them (usually none)
        let unknown = Array(Set(rows.map(\.record.date).filter { !known.knows($0) }))
        var pumpIdentities = Set<PumpEventRecord.Identity>()
        for start in stride(from: 0, to: unknown.count, by: Store.Config.identityChunk) {
            let dates = unknown[start ..< Swift.min(start + Store.Config.identityChunk, unknown.count)]
            let pumpRows = NSFetchRequest<PumpEvent>(entityName: Store.Entity.events)
            pumpRows.predicate = NSPredicate(
                format: "source == %@ AND kind IN %@ AND date IN %@",
                pump,
                doseKinds,
                dates.map { $0 as NSDate }
            )
            pumpIdentities.formUnion(try context.fetch(pumpRows).compactMap { Self.record(of: $0)?.identity })
        }
        var removed = 0
        for (row, record) in rows where known.knows(record.date) || pumpIdentities.contains(record.identity) {
            context.delete(row)
            changed.append(record.span)
            affected.append(record)
            removed += 1
        }
        return removed
    }

    /// The prune's pass: every `source = nightscout` dose row in the pump's time (`PumpKnowledge.knows`), from where it
    /// knows anything on, read as dictionaries and batch-deleted by object id. No identity lookup: the backfill skips the
    /// pump rows' twins, and the statistics dedupe by identity. Returns the records deleted.
    static func removeNightscoutInPumpTime(
        knownBy knowledge: PumpKnowledge,
        in context: NSManagedObjectContext,
        merge: @Sendable([NSManagedObjectID]) -> Void
    ) throws -> [PumpEventRecord] {
        guard let from = knowledge.start else { return [] }
        let objectID = NSExpressionDescription()
        objectID.name = "objectID"
        objectID.expression = NSExpression.expressionForEvaluatedObject()
        objectID.expressionResultType = .objectIDAttributeType
        let fetch = NSFetchRequest<NSDictionary>(entityName: Store.Entity.events)
        fetch.resultType = .dictionaryResultType
        fetch.propertiesToFetch = [objectID, "date", "kind", "source", "units", "rate", "durationMin", "isExternal"]
        fetch.predicate = NSPredicate(
            format: "source == %@ AND kind IN %@ AND date >= %@",
            nightscout,
            doseKinds,
            from as NSDate
        )
        var ids: [NSManagedObjectID] = []
        var records: [PumpEventRecord] = []
        for row in try context.fetch(fetch) {
            guard let id = row["objectID"] as? NSManagedObjectID, let record = CoreDataStorage.pumpEventRecord(row),
                  knowledge.knows(record.date)
            else { continue }
            ids.append(id)
            records.append(record)
        }
        guard ids.isNotEmpty else { return [] }
        let request = NSBatchDeleteRequest(objectIDs: ids)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        merge(result?.result as? [NSManagedObjectID] ?? ids)
        return records
    }

    static func deleteEvents(
        _ identities: Set<PumpEventRecord.Identity>,
        now: Date,
        in context: NSManagedObjectContext
    ) throws -> DateInterval? {
        let dates = identities.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let fetch = NSFetchRequest<PumpEvent>(entityName: Store.Entity.events)
        fetch.predicate = NSPredicate(
            format: "source == %@ AND kind IN %@ AND date >= %@ AND date <= %@",
            pump,
            doseKinds,
            first as NSDate,
            last as NSDate
        )
        var changed: [DateInterval] = []
        var deleted: [PumpEventRecord] = []
        for row in try context.fetch(fetch) {
            guard let record = Self.record(of: row), identities.contains(record.identity) else { continue }
            context.delete(row)
            changed.append(record.span)
            deleted.append(record)
        }
        if let reach = try reach(of: deleted, now: now, in: context) {
            changed.append(reach)
        }
        if context.hasChanges {
            try context.save()
        }
        return union(changed)
    }

    static func prune(
        cutoff: Date,
        in context: NSManagedObjectContext,
        merge: @Sendable([NSManagedObjectID]) -> Void
    ) throws -> PumpEventStore.PruneResult {
        // the coverage rows of earlier builds (kind 9), whatever their date: first, so the count holds them all. Only
        // kind 9: a later build's kinds survive a downgrade
        let otherKinds = try batchDelete(
            Store.Entity.events,
            predicate: NSPredicate(format: "kind == %@", NSNumber(value: Store.Config.coverageKind)),
            in: context,
            merge: merge
        )
        // events, both sources
        var changed = try batchDelete(
            Store.Entity.events,
            predicate: NSPredicate(format: "date < %@", cutoff as NSDate),
            in: context,
            merge: merge
        ) > 0

        // the pump sessions last seen before the cutoff go, one spanning it starts there
        let sessions = try sessionRows(in: context)
        let plan = PumpSessionRules.prune(sessions.map(\.value), cutoff: cutoff)
        var sessionsDeleted = false
        var clippedFrom: Date?
        for entry in sessions where plan.deleted.contains(entry.value.id) {
            context.delete(entry.row)
            sessionsDeleted = true
        }
        for clipped in plan.clipped {
            guard let entry = sessions.first(where: { $0.value.id == clipped.id }) else { continue }
            clippedFrom = Swift.min(clippedFrom ?? entry.value.start, entry.value.start)
            apply(clipped, to: entry.row)
        }

        // the Nightscout dose rows the pump knows (an import before this rule: the coverage gaps, the time before the
        // first session), all of them
        let removed = try removeNightscoutInPumpTime(
            knownBy: pumpKnowledge(fileFrom: nil, in: context),
            in: context,
            merge: merge
        )
        var removedSpans = removed.map(\.span)
        // the prune's now: the cutoff is the retention before it
        if let reach = try reach(of: removed, now: cutoff.addingTimeInterval(Store.Config.retention), in: context) {
            removedSpans.append(reach)
        }

        // the schedules from the one in effect at the cutoff on (it serves the oldest kept events)
        let inEffect = NSFetchRequest<BasalScheduleRecord>(entityName: Store.Entity.schedules)
        inEffect.predicate = NSPredicate(format: "date <= %@", cutoff as NSDate)
        inEffect.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        inEffect.fetchLimit = 1
        if let kept = try context.fetch(inEffect).first?.date {
            changed = try batchDelete(
                Store.Entity.schedules,
                predicate: NSPredicate(format: "date < %@", kept as NSDate),
                in: context,
                merge: merge
            ) > 0 || changed
        }

        if context.hasChanges {
            try context.save()
        }
        return PumpEventStore.PruneResult(
            changed: changed,
            sessionsDeleted: sessionsDeleted,
            clippedSessions: clippedFrom.map { DateInterval(start: $0, end: Swift.max($0, cutoff)) },
            otherKindsDeleted: otherKinds,
            nightscoutRemoved: removed.count,
            nightscoutChanged: union(removedSpans)
        )
    }

    static func recordSchedule(_ schedule: PumpEventStore.ScheduleInsert, in context: NSManagedObjectContext) throws -> Bool {
        let newestFetch = NSFetchRequest<BasalScheduleRecord>(entityName: Store.Entity.schedules)
        newestFetch.predicate = NSPredicate(format: "date != nil")
        newestFetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        newestFetch.fetchLimit = 1
        if let newest = try context.fetch(newestFetch).first, newest.fingerprint == schedule.fingerprint {
            return false
        }
        let row = BasalScheduleRecord(context: context)
        row.date = schedule.date
        row.source = BasalScheduleSource.local.rawValue
        row.entries = schedule.entries
        row.fingerprint = schedule.fingerprint
        try context.save()
        return true
    }

    /// One backfill batch. What the pump knows is left out: the file's time (`min(now - 24 h, the list's oldest event)`
    /// on: `recent`), the local time (`PumpSessionRules.localTime`) and the pump rows' identities (`skipped`); the
    /// records are upserted among the Nightscout rows by identity.
    static func storeBackfill(
        _ batch: PumpEventStore.BackfillBatch,
        in context: NSManagedObjectContext
    ) throws -> PumpEventStore.BackfillBatchResult {
        var result = PumpEventStore.BackfillBatchResult()
        var changed: [DateInterval] = []
        let pumpKnownFrom = batch.pumpKnownFrom
        var inserted: [PumpEventRecord] = []
        let dates = batch.records.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return result }

        let knowledge = try pumpKnowledge(fileFrom: pumpKnownFrom, in: context)
        let rowsFetch = NSFetchRequest<PumpEvent>(entityName: Store.Entity.events)
        rowsFetch.predicate = NSPredicate(
            format: "kind IN %@ AND date >= %@ AND date <= %@",
            doseKinds,
            first as NSDate,
            last as NSDate
        )
        var pumpIdentities = Set<PumpEventRecord.Identity>()
        var stored: [PumpEventRecord.Identity: (row: PumpEvent, record: PumpEventRecord)] = [:]
        for row in try context.fetch(rowsFetch) {
            guard let record = Self.record(of: row) else { continue }
            switch record.source {
            case .pump: pumpIdentities.insert(record.identity)
            case .nightscout: stored[record.identity] = stored[record.identity] ?? (row, record)
            }
        }
        for record in batch.records {
            // the file's time: any uploader's records there are left out, the file is the truth
            guard record.date < pumpKnownFrom else {
                result.recent += 1
                continue
            }
            // the pump's own: its local time (`PumpSessionRules.localTime`) or its rows
            let pumpKnows = pumpIdentities.contains(record.identity) || knowledge.knows(record.date)
            guard !pumpKnows else {
                result.skipped += 1
                continue
            }
            if let existing = stored[record.identity] {
                guard existing.record.signature != record.signature else { continue }
                changed.append(existing.record.span)
                apply(record, to: existing.row)
                changed.append(record.span)
                result.updated += 1
            } else {
                apply(record, to: PumpEvent(context: context))
                changed.append(record.span)
                inserted.append(record)
                result.inserted += 1
            }
        }
        if let reach = try reach(of: inserted, now: batch.now, in: context) {
            changed.append(reach)
        }

        if context.hasChanges {
            try context.save()
        }
        result.changed = union(changed)
        return result
    }

    /// The Nightscout schedules: none at or after the oldest local record, none equal to the record in effect before
    /// it (consecutive equal schedules are one, from the earliest), upserted by identity (the date to the second)
    /// among the Nightscout rows.
    static func storeSchedules(
        _ schedules: [PumpEventStore.ScheduleInsert],
        now: Date,
        in context: NSManagedObjectContext
    ) throws -> PumpEventStore.ScheduleBackfillResult {
        var result = PumpEventStore.ScheduleBackfillResult()

        let oldestLocalFetch = NSFetchRequest<BasalScheduleRecord>(entityName: Store.Entity.schedules)
        oldestLocalFetch.predicate = NSPredicate(
            format: "source == %@ AND date != nil",
            NSNumber(value: BasalScheduleSource.local.rawValue)
        )
        oldestLocalFetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        oldestLocalFetch.fetchLimit = 1
        let oldestLocal = try context.fetch(oldestLocalFetch).first?.date

        let candidates = schedules
            .filter { schedule in oldestLocal.map { schedule.date < $0 } ?? true }
            .sorted { $0.date < $1.date }
        guard candidates.isNotEmpty else { return result }

        // every row before the oldest local one: the Nightscout history so far
        let storedFetch = NSFetchRequest<BasalScheduleRecord>(entityName: Store.Entity.schedules)
        storedFetch.predicate = oldestLocal.map { NSPredicate(format: "date < %@", $0 as NSDate) } ??
            NSPredicate(format: "date != nil")
        storedFetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        let storedRows = try context.fetch(storedFetch)
        var byDate: [Date: BasalScheduleRecord] = [:]
        for row in storedRows where row.source == BasalScheduleSource.nightscout.rawValue {
            if let date = row.date?.truncatedToSecond, byDate[date] == nil {
                byDate[date] = row
            }
        }
        // the timeline the "in effect before" check reads: (date, fingerprint), oldest first
        var timeline: [(date: Date, fingerprint: String)] = storedRows.compactMap { row in
            guard let date = row.date else { return nil }
            return (date, row.fingerprint ?? "")
        }

        var changedDates: [Date] = []
        for schedule in candidates {
            let existing = byDate[schedule.date]
            let before = timeline.last { $0.date < schedule.date }
            if before?.fingerprint == schedule.fingerprint {
                continue
            }
            if let existing {
                guard existing.fingerprint != schedule.fingerprint else { continue }
                write(schedule, to: existing)
                result.updated += 1
            } else {
                let row = BasalScheduleRecord(context: context)
                write(schedule, to: row)
                byDate[schedule.date] = row
                result.inserted += 1
            }
            timeline.removeAll { $0.date == schedule.date }
            timeline.append((schedule.date, schedule.fingerprint))
            timeline.sort { $0.date < $1.date }
            changedDates.append(schedule.date)
        }

        if context.hasChanges {
            try context.save()
        }
        if let first = changedDates.min() {
            result.changed = DateInterval(start: first, end: Swift.max(first, oldestLocal ?? now))
        }
        return result
    }

    private static func write(_ schedule: PumpEventStore.ScheduleInsert, to row: BasalScheduleRecord) {
        row.date = schedule.date
        row.source = BasalScheduleSource.nightscout.rawValue
        row.entries = schedule.entries
        row.fingerprint = schedule.fingerprint
    }

    // MARK: Pump sessions

    /// Every `PumpSession` row that reads as a value: a few a month, so no index (a scan).
    static func sessionRows(in context: NSManagedObjectContext) throws -> [(row: PumpSession, value: PumpSessionValue)] {
        let fetch = NSFetchRequest<PumpSession>(entityName: Store.Entity.sessions)
        return try context.fetch(fetch).compactMap { row in value(of: row).map { (row, $0) } }
    }

    /// Writes the sessions by id (the new ones inserted, the unchanged ones left alone); returns the time they touched
    /// (`touched`).
    private static func writeSessions(
        _ sessions: [PumpSessionValue],
        over stored: [(row: PumpSession, value: PumpSessionValue)],
        in context: NSManagedObjectContext
    ) -> [DateInterval] {
        var changed: [DateInterval] = []
        var inserted: [UUID: PumpSession] = [:]
        for session in sessions {
            if let entry = stored.first(where: { $0.value.id == session.id }) {
                guard entry.value != session else { continue }
                changed += touched(entry.value, session)
                apply(session, to: entry.row)
            } else if let row = inserted[session.id] {
                apply(session, to: row)
                changed.append(session.span)
            } else {
                let row = PumpSession(context: context)
                apply(session, to: row)
                inserted[session.id] = row
                changed.append(session.span)
            }
        }
        return changed
    }

    /// The time a session's write changed: between its old and new start, last seen and end, and the gaps of only one
    /// of them (an extension is `[old lastSeen, now]`, not the whole session); a change of other fields only (a close
    /// at `lastSeen`, the activation, the flags), its end or last seen.
    static func touched(_ old: PumpSessionValue, _ new: PumpSessionValue) -> [DateInterval] {
        var parts: [DateInterval] = []
        func between(_ a: Date, _ b: Date) {
            if a != b {
                parts.append(DateInterval(start: Swift.min(a, b), end: Swift.max(a, b)))
            }
        }
        between(old.start, new.start)
        between(old.lastSeen, new.lastSeen)
        between(old.end ?? old.lastSeen, new.end ?? new.lastSeen)
        parts += Set(old.gaps).symmetricDifference(Set(new.gaps))
        if parts.isEmpty {
            parts.append(DateInterval(start: new.end ?? new.lastSeen, duration: 0))
        }
        return parts
    }

    /// One batch of change events against every stored session (both sources: `PumpSessionRules.changes` needs those
    /// in reach), one save. The log: a line per event, in date order, then one per session closed.
    static func applyLifecycleEvents(
        _ events: [PumpLifecycleEvent],
        now: Date,
        in context: NSManagedObjectContext
    ) throws -> PumpEventStore.LifecycleResult {
        let stored = try sessionRows(in: context)
        let before = stored.map(\.value)
        let written = PumpSessionRules.changes(events, sessions: before, now: now)
        var changed = writeSessions(written, over: stored, in: context)
        var tidyLog: [String] = []
        changed += tidyNightscout(after: written, stored: stored, log: &tidyLog, in: context)
        // the Nightscout dose rows in the time the sessions became local (a start, a start moved back)
        var affected: [PumpEventRecord] = []
        let touchedTime = changed
        let removed = try removeNightscout(
            knownBy: { try pumpKnowledge(fileFrom: nil, in: context) },
            within: touchedTime,
            in: context,
            changed: &changed,
            affected: &affected
        )
        if let reach = try reach(of: affected, now: now, in: context) {
            changed.append(reach)
        }
        if context.hasChanges {
            try context.save()
        }
        var result = PumpEventStore.LifecycleResult(changed: union(changed))
        var reported = Set<UUID>()
        for event in events.sorted(by: { $0.date < $1.date }) {
            result.log.append(lifecycleLine(event, before: before, written: written, reported: &reported))
        }
        // the sessions closed: open before, or started and closed in this batch
        for session in written {
            guard let end = session.end, before.first(where: { $0.id == session.id })?.end == nil else { continue }
            result.log.append("Pump session: closed \(describe(session)) at \(Store.logDate(end))")
        }
        result.log += tidyLog
        if removed > 0 {
            result.log.append("Pump session: \(removed) Nightscout dose rows inside the pump's local time deleted")
        }
        return result
    }

    /// What a change event did, for the log: "Pump session: Medtrum pump change at … → started at …", "→ same (a
    /// re-send)", "→ none (…)".
    static func lifecycleLine(
        _ event: PumpLifecycleEvent,
        before: [PumpSessionValue],
        written: [PumpSessionValue],
        reported: inout Set<UUID>
    ) -> String {
        let name = "Pump session: \(event.plugin) \(event.component.rawValue) change at \(Store.logDate(event.date))"
        guard event.component != .reservoir else { return "\(name) → none (a reservoir)" }
        if let session = written.first(where: { session in
            session.source == .pump && session.plugin == event.plugin && session.activation == event.date
        }), reported.insert(session.id).inserted {
            guard let old = before.first(where: { $0.id == session.id }) else {
                return "\(name) → started at \(Store.logDate(session.start))"
            }
            if old.flags.contains(.awaitingEvent), !session.flags.contains(.awaitingEvent) {
                return "\(name) → taken by the session from \(Store.logDate(old.start)) (now from " +
                    "\(Store.logDate(session.start)))"
            }
            // a late event with nothing of the open session before it: the new one replaces it (its row reused)
            return "\(name) → started at \(Store.logDate(session.start)), replacing the open \(describe(old))"
        }
        let window = PumpSessionRules.dedupWindow(site: !PumpSessionRules.isPodOrPatch(event.plugin))
        let isResend = (before + written).contains { session in
            session.source == .pump && session.plugin == event.plugin
                && session.activation.map { abs($0.timeIntervalSince(event.date)) <= window } == true
        }
        return isResend ? "\(name) → same (a re-send)" : "\(name) → none (out of order, or no boundary of this pump)"
    }

    /// "Medtrum session from … (activated …)", for the log.
    static func describe(_ session: PumpSessionValue) -> String {
        let kind = session.flags.contains(.site) ? "site" : "session"
        let activation = session.activation.map { ", activated \(Store.logDate($0))" } ?? ""
        return "\(session.plugin ?? "unknown") \(kind) from \(Store.logDate(session.start))\(activation)"
    }

    /// One heartbeat against the pump sessions, the clamp first: a closed newest session dated ahead is clamped here,
    /// the open one by `PumpSessionRules.step`. Without any pump session, a delivering unit's first is seeded from the
    /// successful loops since the latest of its activation, the oldest local pump dose row (`pendingOldest`: the
    /// list's oldest, inserted in this context; a tube pump's: the list's oldest only) and the retention's start,
    /// adopting the Nightscout session of its change (`PumpSessionRules.seedCandidate`: a backfill ran before it).
    /// Returns the time written and the log (everything but an extension).
    static func sessionHeartbeat(
        _ heartbeat: PumpHeartbeat,
        oldestCurrent pendingOldest: Date?,
        in context: NSManagedObjectContext
    ) throws -> (changed: [DateInterval], log: [String]) {
        let now = heartbeat.now
        let stored = try sessionRows(in: context)
        let pump = stored.map(\.value).filter { $0.source == .pump }.sorted { $0.start < $1.start }
        var written: [PumpSessionValue] = []
        var log: [String] = []

        var newest = pump.last
        if let session = newest, session.end != nil {
            let clamped = PumpSessionRules.clamp(session, now: now)
            if clamped != session {
                written.append(clamped)
                newest = clamped
                log.append("Pump session: \(describe(clamped)) clamped to now (the clock was ahead)")
            }
        }
        let open = pump.last { $0.end == nil }
        let newestEnd = newest.map { $0.end ?? $0.lastSeen }
        switch PumpSessionRules.step(open: open, newestEnd: newestEnd, heartbeat: heartbeat) {
        case .none:
            break
        case let .extend(session):
            written.append(session)
        case let .update(session):
            written.append(session)
            log.append("Pump session: \(describe(session)) clamped to now (the clock was ahead)")
        case let .close(session):
            written.append(session)
            log.append("Pump session: closed \(describe(session)) at \(Store.logDate(session.end ?? session.lastSeen))")
        case let .start(session, closing):
            if let closing {
                written.append(closing)
                log.append("Pump session: closed \(describe(closing)) at \(Store.logDate(closing.end ?? closing.lastSeen))")
            }
            written.append(session)
            log.append("Pump session: started \(describe(session)) without its change event")
        case let .seed(unit):
            // a pod or patch from its activation (and the oldest dose row); a tube pump's site from the list's oldest
            // row only (the 24 h file): no activation bounds it, and a seed from the oldest stored dose would make one
            // site of months
            let oldestDose = try unit.activation == nil
                ? pendingOldest
                : [oldestPumpDose(in: context), pendingOldest].compactMap { $0 }.min()
            let from = [unit.activation, oldestDose ?? now, now.addingTimeInterval(-Store.Config.retention)]
                .compactMap { $0 }.max() ?? now
            let loops = try successfulLoops(from: from, to: now, in: context)
            let plain = PumpSessionRules.seed(unit, loops: loops, now: now)
            // the Nightscout session of the unit's change (a backfill before the first heartbeat), adopted
            let candidate = PumpSessionRules.seedCandidate(for: unit, seedStart: plain.start, among: stored.map(\.value))
            let seeded = candidate.map { PumpSessionRules.seed(unit, loops: loops, now: now, adopting: $0) } ?? plain
            written.append(seeded)
            let adopted = candidate.map { nightscout in
                seeded.id == nightscout.id ? ", adopting the Nightscout session from \(Store.logDate(nightscout.start))" : ""
            }
            log.append(
                "Pump session: seeded \(describe(seeded)) from \(loops.count) loops since \(Store.logDate(from)), " +
                    "\(seeded.gaps.count) gaps" + (adopted ?? "")
            )
        }
        var changed = writeSessions(written, over: stored, in: context)
        changed += tidyNightscout(after: written, stored: stored, log: &log, in: context)
        return (changed, log)
    }

    /// When the written sessions hold the first pump session (a seed, a change event, no pump session stored):
    /// `PumpSessionRules.tidy` from its start, applied (the written ones, an adopted one, left out). Returns the time
    /// it changed; a log line when it did.
    private static func tidyNightscout(
        after written: [PumpSessionValue],
        stored: [(row: PumpSession, value: PumpSessionValue)],
        log: inout [String],
        in context: NSManagedObjectContext
    ) -> [DateInterval] {
        guard !stored.contains(where: { $0.value.source == .pump }),
              let first = written.filter({ $0.source == .pump }).map(\.start).min()
        else { return [] }
        let plan = PumpSessionRules.tidy(stored.map(\.value), from: first, except: Set(written.map(\.id)))
        var changed: [DateInterval] = []
        for entry in stored where plan.deleted.contains(entry.value.id) {
            context.delete(entry.row)
            changed.append(entry.value.span)
        }
        for trimmed in plan.trimmed {
            guard let entry = stored.first(where: { $0.value.id == trimmed.id }) else { continue }
            changed += touched(entry.value, trimmed)
            apply(trimmed, to: entry.row)
        }
        if changed.isNotEmpty {
            log.append(
                "Pump session: the first pump session from \(Store.logDate(first)): \(plan.deleted.count) Nightscout " +
                    "sessions after it deleted, \(plan.trimmed.count) ended at it"
            )
        }
        return changed
    }

    /// The Nightscout sessions of a backfill against every stored session: `PumpSessionRules.nightscoutSessions` up to
    /// the oldest pump session's local start (now without one), with the stored Nightscout sessions as `existing` and
    /// that pump session as `local`. Written by id: the sessions built (a re-run's keep their stored ids), the pump
    /// session's prefix. Deleted: the stored Nightscout sessions starting in the window that no new one took over and
    /// that aren't `kept`, and those starting in the local sessions' time (from the oldest one's local start on)
    /// without the user's fields (an earlier run's, before the pump sessions began: Nightscout fills no hole between
    /// local sessions). One save.
    static func storeNightscoutSessions(
        _ request: PumpEventStore.NightscoutSessionsRequest,
        in context: NSManagedObjectContext
    ) throws -> PumpEventStore.NightscoutSessionsResult {
        let stored = try sessionRows(in: context)
        let values = stored.map(\.value)
        let local = values.filter { $0.source == .pump }.min { $0.start < $1.start }
        let to = local.map { $0.localStart ?? $0.start } ?? request.now
        let input = request.input
        let built = PumpSessionRules.nightscoutSessions(
            siteChanges: input.siteChanges,
            alarms: input.alarms,
            evidence: input.evidence,
            from: input.from,
            to: to,
            currentPlugin: request.plugin,
            existing: values.filter { $0.source == .nightscout },
            local: local,
            cutoff: request.cutoff
        )
        var result = PumpEventStore.NightscoutSessionsResult(
            sessions: built.sessions.count,
            kept: built.kept.count,
            window: built.window
        )
        for session in built.sessions {
            if let old = values.first(where: { $0.id == session.id }) {
                result.updated += old == session ? 0 : 1
            } else {
                result.inserted += 1
            }
        }
        if let prefixed = built.prefixed {
            result.prefixed = values.first(where: { $0.id == prefixed.id }) != prefixed
        }
        let written = built.sessions + (built.prefixed.map { [$0] } ?? [])
        var changed = writeSessions(written, over: stored, in: context)

        let keep = Set(written.map(\.id) + built.kept.map(\.id))
        for entry in stored where entry.value.source == .nightscout && !keep.contains(entry.value.id) {
            let session = entry.value
            let replaced = built.window.map { ($0.start ..< $0.end).contains(session.start) } ?? false
            let insideLocal = session.start >= to && !session.hasUserFields
            guard replaced || insideLocal else { continue }
            context.delete(entry.row)
            changed.append(session.span)
            result.deleted += 1
        }

        if context.hasChanges {
            try context.save()
        }
        result.changed = union(changed)
        return result
    }

    /// The oldest `source = pump` dose row's date.
    private static func oldestPumpDose(in context: NSManagedObjectContext) throws -> Date? {
        let fetch = NSFetchRequest<PumpEvent>(entityName: Store.Entity.events)
        fetch.predicate = NSPredicate(format: "source == %@ AND kind IN %@ AND date != nil", pump, doseKinds)
        fetch.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        fetch.fetchLimit = 1
        return try context.fetch(fetch).first?.date
    }

    // MARK: Helpers

    /// An event that ends a temp or a suspension in the statistics (`InsulinStatsEngine.timeline`): a temp, a suspend, a
    /// resume, a pump bolus (not External Insulin).
    static func endsDelivery(_ record: PumpEventRecord) -> Bool {
        switch record.kind {
        case .resume,
             .suspend,
             .tempBasal: true
        case .bolus: !record.isExternal && record.units > 0
        }
    }

    /// Inserting or deleting an event that ends a temp or a suspension changes more than its own span: a deleted temp
    /// lets the one before it run on (a deleted resume or pump bolus, the suspension before it), an inserted one clips
    /// it, up to the next such event. So the change reaches from the newest of them to the next stored one after it
    /// (any source; in this context, with its pending changes: the rows just inserted count, the deleted ones don't), or
    /// to `now` without one. Their own spans are in the change already. nil when none of them ends anything.
    static func reach(of records: [PumpEventRecord], now: Date, in context: NSManagedObjectContext) throws -> DateInterval? {
        guard let newest = records.filter(endsDelivery).map(\.date).max() else { return nil }
        let next = NSFetchRequest<PumpEvent>(entityName: Store.Entity.events)
        next.predicate = NSPredicate(
            format: "date > %@ AND (kind IN %@ OR (kind == %@ AND isExternal == NO AND units > 0))",
            newest as NSDate,
            [PumpEventKind.tempBasal, .suspend, .resume].map { NSNumber(value: $0.rawValue) },
            NSNumber(value: PumpEventKind.bolus.rawValue)
        )
        next.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        next.fetchLimit = 1
        let end = try context.fetch(next).first?.date ?? now
        return DateInterval(start: newest, end: Swift.max(newest, end))
    }

    /// The times of the successful loops `[from, to]` (their end, as the heartbeat comes at the end of a loop).
    private static func successfulLoops(from: Date, to: Date, in context: NSManagedObjectContext) throws -> [Date] {
        let fetch = NSFetchRequest<NSDictionary>(entityName: "LoopStatRecord")
        fetch.resultType = .dictionaryResultType
        fetch.propertiesToFetch = ["start", "end"]
        fetch.predicate = NSPredicate(
            format: "loopStatus == %@ AND start >= %@ AND start <= %@",
            "Success",
            from as NSDate,
            to as NSDate
        )
        return try context.fetch(fetch).compactMap { row in
            guard let start = row["start"] as? Date else { return nil }
            return Swift.min((row["end"] as? Date) ?? start, to)
        }
    }

    /// Returns the number of rows it deleted.
    static func batchDelete(
        _ entity: String,
        predicate: NSPredicate?,
        in context: NSManagedObjectContext,
        merge: @Sendable([NSManagedObjectID]) -> Void
    ) throws -> Int {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
        fetch.predicate = predicate
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        let objectIDs = result?.result as? [NSManagedObjectID] ?? []
        if objectIDs.isNotEmpty {
            merge(objectIDs)
        }
        return objectIDs.count
    }

    private static func union(_ intervals: [DateInterval]) -> DateInterval? {
        guard let start = intervals.map(\.start).min(), let end = intervals.map(\.end).max() else { return nil }
        return DateInterval(start: start, end: end)
    }
}

// MARK: - Pump sessions

/// A pump driver's change event (LoopKit's `.replaceComponent`), as the session rules take it (LoopKit-free).
struct PumpLifecycleEvent: Sendable, Equatable {
    enum Component: String, Sendable, Equatable {
        /// a pod or patch put on (Omnipod, Medtrum)
        case pump
        /// an infusion set (a tube pump's cannula prime: Dana, Minimed)
        case infusionSet
        /// a reservoir refilled (Dana): no session boundary
        case reservoir
    }

    /// the pump manager's `pluginIdentifier`
    let plugin: String
    let component: Component
    let date: Date
}

extension PumpLifecycleEvent {
    /// The change event of a pump manager's event; nil for any other event.
    init?(_ event: NewPumpEvent, plugin: String) {
        guard case let .replaceComponent(componentType) = event.type,
              let component = Component(rawValue: componentType.rawValue)
        else { return nil }
        self.init(plugin: plugin, component: component, date: event.date)
    }
}

/// One pod or patch, or one infusion set of a tube pump (a site): the time it was covered, `[start, lastSeen]` without
/// its `gaps`. The value of a `PumpSession` row (`.temp/pump-session-redesign.md` §2.1, R3.3); written by
/// `PumpSessionRules` only.
///
/// - **Start:** the pump driver's change event (`PumpLifecycleEvent`), a Nightscout Site Change, or a heartbeat's
///   fallback when no event came (`awaitingEvent`; the event that comes later is taken: the activation its date, the
///   start moved back to it).
/// - **Gaps:** more than the slack without a heartbeat is a gap, for every pump (the time iAPS was not running is not
///   covered). The doses the pump reports after a reconnect still count, and the per-24 h basal is scaled by the
///   covered time (the Insulin tab's rule).
/// - **Partial:** started more than the slack after its activation (`isPartial`): its numbers count from `start`. An
///   event-started session never is; a late fallback start, a pruned one, a Nightscout one with late evidence are.
/// - **Nightscout sessions** are covered by the evidence (`PumpEventStore.nightscoutCoverage`: the temps' stretches,
///   split at `nightscoutCoverageGap`): an upload outage longer than the slack is a gap, as the local dead time.
/// - **Zero-length sessions** (`span.duration == 0`: an event without a heartbeat after it, a unit that never
///   delivered, a split at a start) can be written; the readers (C4) filter them out.
/// - **End reasons (C3):** MedtrumKit's "patch will expire soon" reminder is not an `.expired` end; only an alarm that
///   stops the unit ends a session.
struct PumpSessionValue: Sendable, Equatable, Identifiable {
    /// where an entered field's value came from
    enum FieldSource: Int16, Sendable, Hashable {
        case none = 0
        case pump = 1
        case nightscout = 2
        case user = 3

        /// which one wins: the user's, then the pump's, then Nightscout's
        var rank: Int {
            switch self {
            case .none: 0
            case .nightscout: 1
            case .pump: 2
            case .user: 3
            }
        }
    }

    struct Flags: OptionSet, Sendable, Hashable {
        let rawValue: Int16

        /// its start comes from the successful loops (`LoopStatRecord`), not from a heartbeat
        static let seeded = Flags(rawValue: 1 << 0)
        /// a Nightscout session: the plugin is the current pump's, assumed
        static let pluginAssumed = Flags(rawValue: 1 << 1)
        /// it ended somewhere after `lastSeen`: closed more than the slack after it, or a Nightscout bound
        static let endApproximate = Flags(rawValue: 1 << 2)
        /// a tube pump's infusion set (`.infusionSet`), not a pod or patch (`.pump`)
        static let site = Flags(rawValue: 1 << 3)
        /// started without its change event (a heartbeat's fallback, the seed): the event, if it comes, is taken
        /// (`PumpSessionRules.change`)
        static let awaitingEvent = Flags(rawValue: 1 << 4)
    }

    var id: UUID
    var source: PumpEventSource
    /// `pumpManager.pluginIdentifier` ("Medtrum", "Omni", "Dana", …); nil: unknown (a Nightscout session without a
    /// current pump)
    var plugin: String?
    /// when the unit or the set was put in: the change event's own date (not clamped: its identity for the re-sends),
    /// the Site Change's, or `podActivatedAt` (a fallback or the seed; nil for a tube pump's), the event's when one is
    /// taken later. No heartbeat updates it.
    var activation: Date?
    /// covered from
    var start: Date
    /// the first local heartbeat, event or seed start; nil for a Nightscout session. Nightscout may write
    /// `[start, localStart)`, never after.
    var localStart: Date?
    /// covered until: the last heartbeat while its unit delivered, or the end of the Nightscout evidence
    var lastSeen: Date
    /// nil while it can go on; set when it closed, or from a Nightscout alarm or bound
    var end: Date?
    /// inside `[start, lastSeen]`, sorted
    var gaps: [DateInterval] = []
    var flags: Flags = []
    var site: String?
    /// U
    var filledUnits: Double?
    var fillSource: FieldSource = .none
    var endReason: PatchEndReason?
    var endReasonSource: FieldSource = .none

    /// `[start, lastSeen]`
    var span: DateInterval { DateInterval(start: start, end: Swift.max(start, lastSeen)) }

    /// the span without the gaps, oldest first
    var covered: [DateInterval] {
        span.duration > 0 ? PumpEventStore.subtract([span], gaps) : []
    }

    /// activated more than the slack before its start
    var isPartial: Bool {
        guard let activation else { return false }
        return start.timeIntervalSince(activation) > PumpSessionRules.Config.slack
    }

    /// a site, a fill or an end reason the user entered
    var hasUserFields: Bool {
        site != nil || fillSource == .user || endReasonSource == .user
    }

    /// The gaps as stored: `[[start, end], …]` in seconds since the reference date (Core Data's own date base: the
    /// times round-trip exactly, sub-second ones too); nil without gaps.
    static func encodeGaps(_ gaps: [DateInterval]) -> String? {
        let pairs = gaps.map { [$0.start.timeIntervalSinceReferenceDate, $0.end.timeIntervalSinceReferenceDate] }
        guard pairs.isNotEmpty, let data = try? JSONEncoder().encode(pairs) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The stored gaps, sorted, read entry by entry: the first two elements of each are its start and end (numbers,
    /// not booleans), further ones are ignored (a later format); an entry that isn't that drops alone.
    static func decodeGaps(_ json: String?) -> [DateInterval] {
        guard let data = json?.data(using: .utf8),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        else { return [] }
        func seconds(_ element: Any) -> Double? {
            guard let number = element as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        return entries.compactMap { entry -> DateInterval? in
            guard let pair = entry as? [Any], pair.count >= 2, let start = seconds(pair[0]), let end = seconds(pair[1]),
                  end >= start
            else { return nil }
            return DateInterval(
                start: Date(timeIntervalSinceReferenceDate: start),
                end: Date(timeIntervalSinceReferenceDate: end)
            )
        }
        .sorted { $0.start < $1.start }
    }
}

/// What delivers: the pump plugin, and its pod's or patch's activation (nil for a tube pump).
struct PumpUnit: Sendable, Equatable {
    let plugin: String
    let activation: Date?
}

/// One reconcile's view of the pump.
struct PumpHeartbeat: Sendable, Equatable {
    enum State: Sendable, Equatable {
        /// no pump info (not there yet at a cold start, none set up) or not onboarded
        case unknown
        /// onboarded, not delivering (`deliveryUnitActive == false`): no pod or patch, faulted, empty, expired, stopped
        case inactive(plugin: String)
        /// delivering (`KnownPlugins.hasActiveDeliveryUnit`)
        case active(PumpUnit)
    }

    let state: State
    let now: Date

    init(state: State, now: Date) {
        self.state = state
        self.now = now
    }

    init(info: PumpDisplayInfo?, now: Date) {
        self.now = now
        guard let info, info.isOnboarded else {
            state = .unknown
            return
        }
        // a pod or patch plugin delivering without an activation can't be: read as none
        if KnownPlugins.hasActiveDeliveryUnit(info),
           info.podActivatedAt != nil || !PumpSessionRules.isPodOrPatch(info.identifier)
        {
            state = .active(PumpUnit(plugin: info.identifier, activation: info.podActivatedAt))
        } else {
            state = .inactive(plugin: info.identifier)
        }
    }
}

/// What one heartbeat writes (`PumpSessionRules.step`).
enum PumpSessionStep: Sendable, Equatable {
    /// nothing
    case none
    /// the open session goes on to now (a gap before it when it is late), clamped first when it was ahead
    case extend(PumpSessionValue)
    /// the open session clamped (a clock set ahead, then corrected), nothing else
    case update(PumpSessionValue)
    /// the open session closes at its `lastSeen`
    case close(PumpSessionValue)
    /// a fallback start (no change event came), the open session of another plugin (if any) closing
    case start(PumpSessionValue, closing: PumpSessionValue?)
    /// there is no pump session at all: the unit's first one is seeded from the loops (`PumpSessionRules.seed`)
    case seed(PumpUnit)
}

/// What one change event writes (`PumpSessionRules.change`).
enum PumpSessionChange: Sendable, Equatable {
    /// nothing: a re-send, out of order, a reservoir
    case none
    /// the session started without its event takes it
    case update(PumpSessionValue)
    /// a new session, the open one (if any) closing at the event (split when the event came late)
    case start(PumpSessionValue, closing: PumpSessionValue?)
}

/// A Nightscout alarm Announcement that ends a pod or patch, its text already mapped (unknown alarms dropped).
struct NightscoutAlarm: Sendable, Equatable {
    let date: Date
    let reason: PatchEndReason
}

/// What a Nightscout import writes (`PumpSessionRules.nightscoutSessions`).
struct NightscoutSessions: Sendable, Equatable {
    /// the window the import replaces: the stored Nightscout sessions starting in it go, except `kept`; nil: none
    var window: DateInterval?
    /// oldest first: they replace the stored Nightscout sessions starting in the window
    var sessions: [PumpSessionValue] = []
    /// the oldest pump session with its prefix from Nightscout; nil when no piece is its
    var prefixed: PumpSessionValue?
    /// stored Nightscout sessions in the window no new one took over that hold the user's fields: kept as they are
    var kept: [PumpSessionValue] = []
}

/// The pump session rules, as pure functions: no Core Data, no `Date()`.
///
/// **Events.** A session starts at the pump driver's change event: `.pump` a pod's or patch's, `.infusionSet` a tube
/// pump's site (`site`; the kind comes from the plugin); `.reservoir` is none. The event's date is the session's
/// activation; its start is clamped to now (a pump clock ahead). A re-send (the drivers re-send with the same date) is
/// the session of the same plugin and kind activated within `dedupWindow`: 2 min for a pod or patch, 15 min for a site
/// (the Nightscout cluster is 15 min for both). The open session a heartbeat started without an event takes it, its
/// activation the event's date, its start moved back to it. An event older than the newest session's start is ignored. A
/// new one closes the open session at the event, splitting it when the event came late and is of its plugin and kind.
///
/// **Lost events.** A pod or patch: its inactive heartbeat closes the old session, the new one's first delivering
/// heartbeat starts one (late, partial). A tube pump is always delivering: a lost `.infusionSet` leaves the old site's
/// session going on (no fallback), and its seed or fallback sessions get no Nightscout prefix (no activation to match).
/// Medtrum's lost-answer path (the change event dated when MedtrumKit starts the session, after the real activation)
/// is fixed in MedtrumKit: `replacedPump` is dated at the real activation.
///
/// **Heartbeats** never compare activations. They extend the open session (`lastSeen`), close it on the first inactive
/// heartbeat once its unit was seen delivering, close it on another plugin, and start a session without an event
/// (`awaitingEvent`: a lost event degrades to a late, partial session) when none is open.
///
/// **Gaps.** More than the slack without a heartbeat is a gap `[lastSeen, now]`, for every pump. A recorded gap is
/// longer than the slack; clipping (the clamp, the prune, a split) can leave a shorter rest, which stays.
enum PumpSessionRules {
    enum Config {
        /// a heartbeat within this of the last one extends the session without a gap
        static let slack: TimeInterval = PumpEventStore.Config.coverageSlack
        /// a pod's or patch's change event this close to a session's activation (same plugin) is its re-send; also how
        /// far after a fallback's start its event can be (`dedupWindow`)
        static let eventCluster: TimeInterval = .minutes(2)
        /// Nightscout Site Changes this close (to a cluster's first) are one change: Medtrum's pair, a tube pump's
        /// primes of one set change; also a local site's re-send window (`dedupWindow`), the sameness of a stored
        /// Nightscout session and of the seed's adoption
        static let siteChangeCluster: TimeInterval = .minutes(15)
        /// a Nightscout alarm ends a pod or patch up to this long after its `maxLife`; a later one is another unit's
        static let alarmMargin: TimeInterval = .hours(12)
    }

    /// Medtrum and Omnipod: activated, worn, replaced.
    static func isPodOrPatch(_ plugin: String?) -> Bool {
        maxLife(plugin) != nil
    }

    /// The longest a pod or patch delivers (`PatchStatsEngine.maximumLife`; a Medtrum patch run past it is not
    /// supported): it caps the Nightscout pieces. nil for the others.
    static func maxLife(_ plugin: String?) -> TimeInterval? {
        PatchStatsEngine.maximumLife(plugin: plugin)
    }

    /// A session's kind for the plugin: a tube pump's are sites.
    private static func kind(_ plugin: String?) -> PumpSessionValue.Flags {
        plugin != nil && !isPodOrPatch(plugin) ? .site : []
    }

    // MARK: Events

    /// The window a change event of the kind is its session's re-send in: 2 min for a pod's or patch's (the drivers
    /// re-send with the same date), 15 min for a tube pump's site (a cannula primed again minutes later is one site,
    /// as the Nightscout cluster has it).
    static func dedupWindow(site: Bool) -> TimeInterval {
        site ? Config.siteChangeCluster : Config.eventCluster
    }

    /// One change event against the sessions in its reach: see the type's doc.
    /// - The kind comes from the plugin (a pod's or patch's are `.pump`, a tube pump's sites); an `.infusionSet` of a
    ///   pod or patch plugin and a `.reservoir` are none.
    /// - The event's own date is the session's `activation` (its identity: the re-sends are compared with it, also
    ///   with a pump clock ahead); only `start`, `localStart` and `lastSeen` are clamped to now.
    /// - **Taking it:** the open newest pump session, started without its event (`awaitingEvent`), of the plugin and
    ///   kind, its start at most `eventCluster` before the event: its activation becomes the event's own date (its
    ///   identity for the re-sends; after the start by up to `eventCluster`, or more with a pump clock ahead: not
    ///   partial), and its `start` (not `localStart`: `prefixed` owns `[start, localStart)`, and on a Nightscout re-run
    ///   it owns this start of the oldest pump session) moves back to the event, never before the end of the newest
    ///   older session of either source, the time to its old start a gap when longer than the slack.
    /// - A new session never starts before the end of an older session of either source the event falls in (but the
    ///   first pump session: no Nightscout session moves it, the store's `tidy` ends that one at it); an open
    ///   one of another plugin or kind is not split: it closes at its `lastSeen`, the new one starting there (partial).
    /// - The pump sessions are clamped first (`clamp`): one dated ahead can't make a real event look out of order.
    /// - Parameter sessions: every session in reach, both sources: at least the pump sessions activated within the
    ///   dedup window of the event and the newest two of each source (all of them is simplest). A batch goes through
    ///   `changes`.
    static func change(
        _ event: PumpLifecycleEvent,
        sessions: [PumpSessionValue],
        now: Date,
        newID: UUID = UUID()
    ) -> PumpSessionChange {
        let kind = Self.kind(event.plugin)
        switch event.component {
        case .reservoir: return .none
        case .infusionSet where kind.isEmpty: return .none
        case .infusionSet,
             .pump: break
        }
        let window = dedupWindow(site: kind.contains(.site))
        let date = Swift.min(event.date, now)
        let pump = sessions.filter { $0.source == .pump }.map { clamp($0, now: now) }.sorted { $0.start < $1.start }
        // the first pump session wins over Nightscout: its start is the event's (`tidy` then ends the one it falls in)
        let others = pump.isEmpty ? [] : sessions.filter { $0.source != .pump }
        func isOfEvent(_ session: PumpSessionValue) -> Bool {
            session.plugin == event.plugin && session.flags.intersection(.site) == kind
        }
        /// the latest end of the sessions (both sources) starting before the date, but `except`
        func floor(before date: Date, except id: UUID?) -> Date? {
            (pump + others).filter { $0.id != id && $0.start < date }.map { $0.end ?? $0.lastSeen }.max()
        }

        // a re-send
        if pump.contains(where: { session in
            isOfEvent(session) && !session.flags.contains(.awaitingEvent)
                && session.activation.map { abs($0.timeIntervalSince(event.date)) <= window } == true
        }) {
            return .none
        }

        let newest = pump.last
        // the event of the open session a heartbeat started without one
        if let newest, newest.end == nil, newest.flags.contains(.awaitingEvent), isOfEvent(newest),
           date.timeIntervalSince(newest.start) <= Config.eventCluster
        {
            var taken = newest
            taken.activation = event.date
            taken.flags.remove(.awaitingEvent)
            let bound = floor(before: newest.start, except: newest.id)
            let start = Swift.max(Swift.min(newest.start, date), bound ?? date)
            if start < newest.start {
                if newest.start.timeIntervalSince(start) > Config.slack {
                    taken.gaps.insert(DateInterval(start: start, end: newest.start), at: 0)
                }
                taken.start = start
            }
            return .update(taken)
        }

        // out of order
        if let newest, date < newest.start {
            return .none
        }

        var started = PumpSessionValue(
            id: newID,
            source: .pump,
            plugin: event.plugin,
            activation: event.date,
            start: date,
            localStart: date,
            lastSeen: date,
            flags: kind
        )
        func starting(at start: Date) {
            started.start = start
            started.localStart = start
            started.lastSeen = Swift.max(started.lastSeen, start)
        }
        let openSession = pump.last { $0.end == nil }
        if let bound = floor(before: date, except: openSession?.id), bound > date {
            starting(at: bound)
        }
        guard let open = openSession else {
            return .start(started, closing: nil)
        }
        guard started.start < open.lastSeen else {
            var closing = open
            closing.end = open.lastSeen
            if date.timeIntervalSince(open.lastSeen) > Config.slack {
                closing.flags.insert(.endApproximate)
            }
            return .start(started, closing: closing)
        }
        guard isOfEvent(open) else {
            // another plugin's or kind's unit delivered up to its `lastSeen`: closed there, the new one from there
            var closing = open
            closing.end = open.lastSeen
            starting(at: Swift.max(started.start, open.lastSeen))
            return .start(started, closing: closing)
        }
        // the event came late: the open session's time from the new one's start on is the new one's
        let parts = split(open, at: started.start)
        started.lastSeen = open.lastSeen
        started.gaps = clipped(parts.after, to: started.span)
        guard let before = parts.before else {
            // nothing before it: the new one takes the open session's row (its entered fields too)
            started.id = open.id
            return .update(withEnteredFields(of: open, in: started))
        }
        return .start(started, closing: before)
    }

    /// A batch of change events (one `hasNewPumpEvents` call), applied in date order against the sessions in reach;
    /// returns the sessions written, each as it ends up. Of the events of the plugin and kind of an open session
    /// awaiting its event, the newest at or before its start + `eventCluster` is applied first: it is the one taken
    /// (the older ones are then out of order), not the oldest.
    static func changes(
        _ events: [PumpLifecycleEvent],
        sessions: [PumpSessionValue],
        now: Date,
        makeID: () -> UUID = { UUID() }
    ) -> [PumpSessionValue] {
        var all = sessions
        var written: [UUID] = []
        func write(_ session: PumpSessionValue) {
            if let index = all.firstIndex(where: { $0.id == session.id }) {
                all[index] = session
            } else {
                all.append(session)
            }
            if !written.contains(session.id) {
                written.append(session.id)
            }
        }
        var ordered = events.sorted { $0.date < $1.date }
        if let awaiting = all.filter({ $0.source == .pump }).max(by: { $0.start < $1.start }),
           awaiting.end == nil, awaiting.flags.contains(.awaitingEvent),
           let index = ordered.lastIndex(where: { event in
               event.plugin == awaiting.plugin && kind(event.plugin) == awaiting.flags.intersection(.site)
                   && event.component != .reservoir
                   && Swift.min(event.date, now).timeIntervalSince(awaiting.start) <= Config.eventCluster
           })
        {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        for event in ordered {
            switch change(event, sessions: all, now: now, newID: makeID()) {
            case .none: break
            case let .update(session):
                write(session)
            case let .start(session, closing):
                if let closing {
                    write(closing)
                }
                write(session)
            }
        }
        return written.compactMap { id in all.first { $0.id == id } }
    }

    /// The session split at a date inside its span: the part before it, closed there (exactly; nil when the date is
    /// at or before its start: nothing before it), and the gaps after.
    static func split(_ session: PumpSessionValue, at date: Date) -> (before: PumpSessionValue?, after: [DateInterval]) {
        let after = clipped(
            session.gaps,
            to: DateInterval(start: Swift.max(session.start, date), end: Swift.max(session.start, date, session.lastSeen))
        )
        guard date > session.start else { return (nil, after) }
        var before = session
        before.lastSeen = date
        before.end = date
        before.gaps = clipped(session.gaps, to: before.span)
        return (before, after)
    }

    // MARK: Heartbeat

    /// A session with a date past now + the slack (a clock set ahead, then corrected): each of its dates past now
    /// (`start`, `localStart`, `lastSeen`, `end`) goes to now, the activation kept, the gaps clipped. The same value
    /// when nothing is ahead. The store clamps a closed newest session with it; `step` clamps the open one.
    static func clamp(_ session: PumpSessionValue, now: Date) -> PumpSessionValue {
        let horizon = now.addingTimeInterval(Config.slack)
        let dates = [session.start, session.localStart, session.lastSeen, session.end].compactMap { $0 }
        guard dates.contains(where: { $0 > horizon }) else { return session }
        var clamped = session
        clamped.start = Swift.min(session.start, now)
        clamped.localStart = session.localStart.map { Swift.min($0, now) }
        clamped.lastSeen = Swift.min(session.lastSeen, now)
        clamped.end = session.end.map { Swift.min($0, now) }
        clamped.gaps = clipped(session.gaps, to: clamped.span)
        return clamped
    }

    /// One heartbeat (`PumpHeartbeat.state`) against the open pump session, clamped first (`clamp`):
    /// - `unknown`: nothing;
    /// - no open session: `inactive` nothing; `active` a fallback start at the latest of now and the newest session's
    ///   end (`awaitingEvent`, its activation the unit's: partial when late), or the seed without any pump session;
    /// - an open session of another plugin: it closes at its `lastSeen`; `active` also a fallback start;
    /// - its plugin `inactive`: it closes at its `lastSeen`, once its unit was seen delivering (`lastSeen > start`: a
    ///   pump info lagging the event can't close the session the event just started), or once the slack has passed
    ///   since its start without that (a unit that never delivers);
    /// - its plugin `active`: `lastSeen = now`, with the gap `[lastSeen, now]` when that is longer than the slack;
    ///   nothing while now is before `lastSeen` (the clock went back by less than the slack).
    /// A close is `endApproximate` when now is more than the slack after `lastSeen`.
    /// - Parameters:
    ///   - open: the open `source = pump` session (`end == nil`); a closed one passed is ignored
    ///   - newestEnd: the newest pump session's end (or `lastSeen`); nil: there is no pump session (the seed)
    ///   - newID: the id of a session started
    static func step(
        open: PumpSessionValue?,
        newestEnd: Date?,
        heartbeat: PumpHeartbeat,
        newID: UUID = UUID()
    ) -> PumpSessionStep {
        let now = heartbeat.now
        guard let open, open.end == nil else {
            guard case let .active(unit) = heartbeat.state else { return .none }
            guard let newestEnd else { return .seed(unit) }
            return .start(fallback(unit, at: Swift.max(now, newestEnd), id: newID), closing: nil)
        }
        var session = clamp(open, now: now)
        let unchanged: PumpSessionStep = session != open ? .update(session) : .none

        switch heartbeat.state {
        case .unknown:
            return unchanged
        case let .inactive(plugin):
            // not seen delivering yet: a pump info lagging the event, for the slack; a unit that never delivers closes
            if plugin == session.plugin, session.lastSeen <= session.start,
               now.timeIntervalSince(session.start) <= Config.slack
            {
                return unchanged
            }
            return .close(closed(session, now: now))
        case let .active(unit):
            guard unit.plugin == session.plugin else {
                let closing = closed(session, now: now)
                return .start(fallback(unit, at: Swift.max(now, closing.lastSeen), id: newID), closing: closing)
            }
            guard now > session.lastSeen else { return unchanged }
            if now.timeIntervalSince(session.lastSeen) > Config.slack {
                session.gaps.append(DateInterval(start: session.lastSeen, end: now))
            }
            session.lastSeen = now
            return .extend(session)
        }
    }

    /// The session closed at its `lastSeen`, `endApproximate` when now is more than the slack after it.
    private static func closed(_ session: PumpSessionValue, now: Date) -> PumpSessionValue {
        var closed = session
        closed.end = session.lastSeen
        if now.timeIntervalSince(session.lastSeen) > Config.slack {
            closed.flags.insert(.endApproximate)
        }
        return closed
    }

    /// A session a heartbeat starts without a change event.
    private static func fallback(_ unit: PumpUnit, at date: Date, id: UUID) -> PumpSessionValue {
        PumpSessionValue(
            id: id,
            source: .pump,
            plugin: unit.plugin,
            activation: unit.activation,
            start: date,
            localStart: date,
            lastSeen: date,
            flags: kind(unit.plugin).union(.awaitingEvent)
        )
    }

    /// The first pump session (a fresh install, after a wipe, after the model change): from the first successful loop
    /// at or after the activation on, up to now; its gaps the stretches longer than the slack between the loops, and
    /// from the last one to now. Without loops it starts at now. It awaits its event (`awaitingEvent`).
    /// - Parameters:
    ///   - loops: the successful loops' times in the store's bound: from the latest of the activation, the oldest
    ///     local pump dose row and the retention's start
    ///   - nightscout: a Nightscout session of the same change, whatever its end: of the plugin, its activation from
    ///     `siteChangeCluster` before the unit's to `siteChangeCluster` after the later of the unit's and the seed's
    ///     start (an Omnipod pod's change event, and so its Site Change, comes at the setup's completion, which can be
    ///     more than that after `activatedAt`). Adopted: its id, its earlier start through `prefixed`, its entered
    ///     fields (a Nightscout end reason dropped); open. A tube pump's unit has no activation: it adopts none (no Nightscout prefix for a tube pump's
    ///     seed). The store passes only such a candidate (`seedCandidate`): the newest Nightscout session of the
    ///     plugin activated in that range, never an older unit's whose piece reaches past the activation.
    static func seed(
        _ unit: PumpUnit,
        loops: [Date],
        now: Date,
        adopting nightscout: PumpSessionValue? = nil,
        newID: UUID = UUID()
    ) -> PumpSessionValue {
        let times = loops.filter { time in time <= now && unit.activation.map { time >= $0 } != false }.sorted()
        let start = times.first ?? now
        var session = PumpSessionValue(
            id: newID,
            source: .pump,
            plugin: unit.plugin,
            activation: unit.activation,
            start: start,
            localStart: start,
            lastSeen: now,
            flags: kind(unit.plugin).union(times.isEmpty ? .awaitingEvent : [.awaitingEvent, .seeded])
        )
        for (previous, next) in zip(times, times.dropFirst() + [now]) where next.timeIntervalSince(previous) > Config.slack {
            session.gaps.append(DateInterval(start: previous, end: next))
        }
        guard let nightscout, nightscout.source == .nightscout, nightscout.plugin == unit.plugin || nightscout.plugin == nil,
              let activation = unit.activation
        else { return session }
        // its activation from the cluster before the unit's to the cluster after the unit's or the seed's start
        // (Omnipod's Site Change at the setup's completion); an older unit's piece reaching past them is not it
        let reach = activation.addingTimeInterval(-Config.siteChangeCluster) ...
            Swift.max(activation, start).addingTimeInterval(Config.siteChangeCluster)
        guard let other = nightscout.activation, reach.contains(other) else { return session }

        var adopted = prefixed(session, with: nightscout)
        adopted.id = nightscout.id
        adopted.end = nil
        adopted = withEnteredFields(of: nightscout, in: adopted)
        // open: Nightscout's end reason (an alarm of its piece) isn't this session's; the pump's or the user's stays
        if adopted.endReasonSource == .nightscout {
            adopted.endReason = nil
            adopted.endReasonSource = .none
        }
        return adopted
    }

    /// The seed's Nightscout session (`seed(adopting:)`): of the unit's plugin or of none (imported without a pump: it
    /// takes the unit's), activated from `siteChangeCluster`
    /// before the unit's activation to `siteChangeCluster` after the later of it and the seed's start; the newest of
    /// them. Never an older unit's piece reaching past the activation (its own activation is older), nor one without an
    /// activation. nil for a tube pump's unit (no activation) or when none is.
    /// - Parameters:
    ///   - seedStart: the seed's start without adopting (its first loop at or after the activation, or now)
    ///   - sessions: the stored sessions (the Nightscout ones are looked at)
    static func seedCandidate(
        for unit: PumpUnit,
        seedStart: Date,
        among sessions: [PumpSessionValue]
    ) -> PumpSessionValue? {
        guard let activation = unit.activation else { return nil }
        let reach = activation.addingTimeInterval(-Config.siteChangeCluster) ...
            Swift.max(activation, seedStart).addingTimeInterval(Config.siteChangeCluster)
        return sessions
            .filter { session in
                session.source == .nightscout && (session.plugin == unit.plugin || session.plugin == nil)
                    && session.activation.map { reach.contains($0) } == true
            }
            .max { ($0.activation ?? .distantPast) < ($1.activation ?? .distantPast) }
    }

    /// The Nightscout sessions when the first pump session is written (a seed that adopted none, a change event): the
    /// ones starting at or after its start without the user's fields go, the one spanning it ends there
    /// (`endApproximate`, its `lastSeen` and gaps clipped). Nightscout fills no local time, as each import keeps it
    /// (`storeNightscoutSessions`); this keeps it at once when the import ran before the pump sessions: another
    /// unit's change, a tube pump's site, none adopted. A trimmed row loses a Nightscout end reason (its end moved);
    /// one with the user's fields is trimmed too: its time changes, its fields don't. One with the user's fields
    /// starting after the start stays where it is, over local time (C4 shows it as an annotation).
    /// - Parameters:
    ///   - sessions: the stored sessions (the Nightscout ones are looked at)
    ///   - except: the sessions written with the first pump session (an adopted one)
    static func tidy(
        _ sessions: [PumpSessionValue],
        from start: Date,
        except: Set<UUID> = []
    ) -> (deleted: [UUID], trimmed: [PumpSessionValue]) {
        var deleted: [UUID] = []
        var trimmed: [PumpSessionValue] = []
        for session in sessions where session.source == .nightscout && !except.contains(session.id) {
            if session.start >= start {
                if !session.hasUserFields {
                    deleted.append(session.id)
                }
            } else if (session.end ?? session.lastSeen) > start {
                var ended = session
                ended.lastSeen = Swift.min(session.lastSeen, start)
                ended.end = start
                ended.gaps = clipped(session.gaps, to: ended.span)
                ended.flags.insert(.endApproximate)
                trimmed.append(withoutNightscoutReason(ended))
            }
        }
        return (deleted, trimmed)
    }

    // MARK: Nightscout

    /// The changes of the Site Changes, oldest first: those within `siteChangeCluster` of a cluster's first are one
    /// (no chain), at the earliest. That joins both upload schemes' copies (`.temp/pump-session-redesign.md`,
    /// "Decisions 2026-11-05"): the old one's Medtrum pair (the phone's time, then the patch clock's, seconds apart) and
    /// a tube pump's primes of one set change (Minimed's manual tube primes and the fixed prime; Dana's cannula primes);
    /// the new one's single Site Change per change event; a hand-entered copy.
    static func activations(_ siteChanges: [Date]) -> [Date] {
        var activations: [Date] = []
        for time in siteChanges.sorted() {
            if let first = activations.last, time.timeIntervalSince(first) <= Config.siteChangeCluster {
                continue
            }
            activations.append(time)
        }
        return activations
    }

    /// A piece of the window: one change's from its activation, or one without (before the first activation, after a
    /// `maxLife` without an alarm). `alarmsUntil`: a pod's or patch's alarms count before it; nil: none count.
    private struct Piece {
        let span: DateInterval
        let activation: Date?
        let alarmsUntil: Date?
        /// the piece before the first activation
        let isFirst: Bool
    }

    /// The Nightscout sessions of `[from, to)`, for every current pump (or none: no plugin).
    /// - The window is split at the activations (`activations`) and the oldest pump session's activation. A piece
    ///   with an activation is that change's: a pod's or patch's (at most its `maxLife`), or a tube pump's site
    ///   (`site`). The plugin is the current pump's (`pluginAssumed`). Before the first activation, and after a
    ///   `maxLife` without an alarm up to the next one, are pieces without an activation.
    /// - Every piece is covered by the evidence in it, its gaps the time between longer than the slack; it starts at
    ///   its activation when the evidence does within the slack of it, otherwise at the evidence (partial).
    /// - A pod's or patch's first alarm at or after its first evidence, before the next activation and at most
    ///   `alarmMargin` after its `maxLife`, ends it there with its reason (the alarm repeats; a later one is another
    ///   unit's or none; the time from the last evidence a gap when longer than the slack). After it nothing is written
    ///   up to the next activation (the stopped unit's loops, or an unrecorded unit's: no piece between two pods).
    ///   Without one it ends at its last evidence, `endApproximate`. A tube pump's alarms end nothing.
    /// - A Nightscout session is never open. A piece without evidence makes no session; nothing before the retention's
    ///   `cutoff` is written. An alarm after its piece's `maxLife` ends it there, `endApproximate`.
    /// - A re-run whose evidence ends earlier (the server pruned, an upload deleted) shrinks the sessions' tails: their
    ///   `lastSeen` and `end` move back, the store's change signal covering the time between (`touched`); the time
    ///   after the new `lastSeen` stays as uncovered as the server now says.
    /// - The last piece, when it is the oldest pump session's change (its activation within `siteChangeCluster`, or the
    ///   window starting inside its unit's life): that session's prefix (`prefixed`, evidence or not), of its own
    ///   plugin (a pump switched since is the current pump's, not its).
    /// - A stored Nightscout session of the same activation (or, without one, the same start) within
    ///   `siteChangeCluster` keeps its id, and its entered fields win where they rank higher (`FieldSource.rank`); one
    ///   that matches the prefix gives the pump session its entered fields. Those that match none and hold the user's
    ///   are `kept`.
    /// - Parameters:
    ///   - siteChanges: the Site Changes' times, both upload schemes
    ///   - evidence: the Nightscout coverage intervals (`PumpEventStore.nightscoutCoverage`)
    ///   - from: the oldest record fetched (older stored sessions are left as they are). A stored Nightscout session
    ///     it falls inside is kept: the window starts at the first activation after that one's end.
    ///   - to: the oldest pump session's `localStart`, or now without one. Nothing when not after `from`.
    ///   - currentPlugin: the current pump's
    ///   - existing: the stored Nightscout sessions reaching into the window
    ///   - local: the oldest pump session
    ///   - cutoff: the retention's start
    static func nightscoutSessions(
        siteChanges: [Date],
        alarms: [NightscoutAlarm],
        evidence: [DateInterval],
        from: Date,
        to: Date,
        currentPlugin plugin: String?,
        existing: [PumpSessionValue],
        local: PumpSessionValue?,
        cutoff: Date? = nil,
        makeID: () -> UUID = { UUID() }
    ) -> NightscoutSessions {
        guard from < to else { return NightscoutSessions() }
        let life = maxLife(plugin)
        var allCuts = activations(siteChanges)
        if let activation = local?.activation,
           !allCuts.contains(where: { abs($0.timeIntervalSince(activation)) <= Config.siteChangeCluster })
        {
            allCuts = (allCuts + [activation]).sorted()
        }

        // a stored session the window starts inside is kept: from the first activation after its end
        let stored = existing.filter { $0.source == .nightscout }.sorted { $0.start < $1.start }
        var windowStart = from
        for session in stored where session.start < windowStart {
            windowStart = Swift.max(windowStart, session.end ?? session.lastSeen)
        }
        if windowStart > from {
            windowStart = allCuts.first { $0 >= windowStart } ?? to
        }
        guard windowStart < to else { return NightscoutSessions() }
        let window = DateInterval(start: windowStart, end: to)
        var result = NightscoutSessions(window: window)

        let evidence = PumpEventStore.merge(PumpEventStore.intersect(evidence, with: window))
        let alarms = life == nil ? [] : alarms.sorted { $0.date < $1.date }

        var pieces: [Piece] = []
        let cuts = allCuts.filter { (window.start ..< window.end).contains($0) }
        let firstCut = cuts.first ?? window.end
        if firstCut > window.start {
            pieces.append(Piece(
                span: DateInterval(start: window.start, end: firstCut),
                activation: nil,
                alarmsUntil: life == nil ? nil : firstCut,
                isFirst: true
            ))
        }
        for (index, activation) in cuts.enumerated() {
            let next = index + 1 < cuts.count ? cuts[index + 1] : window.end
            // the oldest pump session's change: its own unit's life (a pump switched since has another)
            let isLocal = local.flatMap(\.activation).map { abs($0.timeIntervalSince(activation)) <= Config.siteChangeCluster }
                ?? false
            let pieceLife = isLocal ? maxLife(local?.plugin) : life
            guard let life = pieceLife else {
                pieces
                    .append(Piece(
                        span: DateInterval(start: activation, end: next),
                        activation: activation,
                        alarmsUntil: nil,
                        isFirst: false
                    ))
                continue
            }
            let expiry = activation.addingTimeInterval(life)
            let end = Swift.min(next, expiry)
            let until = Swift.min(next, expiry.addingTimeInterval(Config.alarmMargin))
            pieces
                .append(Piece(
                    span: DateInterval(start: activation, end: end),
                    activation: activation,
                    alarmsUntil: until,
                    isFirst: false
                ))
            // the same alarm as its session takes: from its first evidence on
            let firstEvidence = evidence.first { $0.end > activation && $0.start < end }.map { Swift.max($0.start, activation) }
            let alarmed = alarms.contains { $0.date >= (firstEvidence ?? activation) && $0.date < until }
            if !alarmed, end < next {
                pieces.append(Piece(span: DateInterval(start: end, end: next), activation: nil, alarmsUntil: nil, isFirst: false))
            }
        }

        var unused = stored.filter { (window.start ..< window.end).contains($0.start) }
        for (index, piece) in pieces.enumerated() {
            let covered = PumpEventStore.intersect(evidence, with: piece.span)
            func gaps(_ span: DateInterval) -> [DateInterval] {
                PumpEventStore.subtract([span], covered).filter { $0.duration > Config.slack }
            }
            // from the activation when the evidence starts within the slack of it (as the seed from its first loop)
            var begin = covered.first?.start
            if let activation = piece.activation, let first = begin, first.timeIntervalSince(activation) <= Config.slack {
                begin = activation
            }

            // the oldest pump session's change, evidence or not: its prefix
            if index == pieces.count - 1, let local, local.source == .pump, let localActivation = local.activation,
               piece.activation.map({ abs($0.timeIntervalSince(localActivation)) <= Config.siteChangeCluster })
               ?? (piece.isFirst && localActivation <= piece.span.start)
            {
                let pieceStart = begin ?? piece.activation ?? piece.span.start
                let lastSeen = covered.last?.end ?? pieceStart
                let nightscout = PumpSessionValue(
                    id: local.id,
                    source: .nightscout,
                    plugin: local.plugin,
                    activation: piece.activation,
                    start: pieceStart,
                    lastSeen: lastSeen,
                    gaps: gaps(DateInterval(start: pieceStart, end: Swift.max(pieceStart, lastSeen)))
                )
                var prefix = prefixed(local, with: nightscout, cutoff: cutoff)
                if let match = unused.firstIndex(where: { isSame($0, nightscout) }) {
                    let stored = unused[match]
                    prefix = withEnteredFields(of: withoutNightscoutReason(stored), in: prefix)
                    // a user's value the pump session had its own of stays on the stored row (`kept`)
                    if !hasTransferred(stored, to: prefix) {
                        result.prefixed = prefix
                        continue
                    }
                    unused.remove(at: match)
                }
                result.prefixed = prefix
                continue
            }

            guard let start = begin, let first = covered.first, var lastSeen = covered.last?.end else { continue }
            let alarm = piece.alarmsUntil.flatMap { until in alarms.first { $0.date >= first.start && $0.date < until } }
            if let alarm {
                lastSeen = Swift.min(alarm.date, piece.span.end)
            }
            let span = DateInterval(start: start, end: Swift.max(start, lastSeen))
            var session = PumpSessionValue(
                id: UUID(),
                source: .nightscout,
                plugin: plugin,
                activation: piece.activation,
                start: span.start,
                lastSeen: span.end,
                gaps: gaps(span),
                flags: plugin == nil ? [] : kind(plugin).union(.pluginAssumed)
            )
            if let alarm {
                session.end = alarm.date
                session.endReason = alarm.reason
                session.endReasonSource = .nightscout
                // after its `maxLife` (within `alarmMargin`): the time between is unknown
                if alarm.date > session.lastSeen {
                    session.flags.insert(.endApproximate)
                }
            } else {
                session.end = session.lastSeen
                session.flags.insert(.endApproximate)
            }
            if let cutoff {
                guard session.lastSeen >= cutoff else { continue }
                if session.start < cutoff {
                    session.start = cutoff
                    session.gaps = clipped(session.gaps, to: session.span)
                }
            }

            if let match = unused.firstIndex(where: { isSame($0, session) }) {
                session.id = unused[match].id
                session = withEnteredFields(of: withoutNightscoutReason(unused[match]), in: session)
                unused.remove(at: match)
            } else {
                session.id = makeID()
            }
            result.sessions.append(session)
        }
        result.kept = unused.filter(\.hasUserFields)
        return result
    }

    /// A pump session with a Nightscout piece of its change before it: from the piece's start (or its own local start,
    /// if that is earlier; never before the cutoff) on, its activation the earlier one. The activation only moves
    /// earlier: a Nightscout Site Change of the prefix later corrected (moved later, deleted) leaves it where it went;
    /// accepted (within `siteChangeCluster` of the local one). Its gaps before `localStart`
    /// are the piece's, and the time from the piece's last evidence to the local start when longer than the slack (no
    /// evidence: all of it). Nothing else changes.
    static func prefixed(_ local: PumpSessionValue, with piece: PumpSessionValue, cutoff: Date? = nil) -> PumpSessionValue {
        var session = local
        let localStart = local.localStart ?? local.start
        session.start = Swift.min(piece.start, localStart)
        if let cutoff {
            session.start = Swift.min(Swift.max(session.start, cutoff), localStart)
        }
        if let activation = piece.activation, let earliest = local.activation, activation < earliest {
            session.activation = activation
        }
        let prefix = DateInterval(start: session.start, end: localStart)
        var bridge: [DateInterval] = []
        let evidenceEnd = Swift.max(piece.lastSeen, session.start)
        if localStart.timeIntervalSince(evidenceEnd) > Config.slack {
            bridge = [DateInterval(start: evidenceEnd, end: localStart)]
        }
        session.gaps = clipped(piece.gaps, to: prefix) + bridge + local.gaps.filter { $0.start >= localStart }
        return session
    }

    /// Two Nightscout sessions are the same one: by activation, or (both without) by start or end, within
    /// `siteChangeCluster`: the first piece clipped by the cutoff starts later on each run (the cutoff moves with the
    /// day) and keeps its end.
    private static func isSame(_ a: PumpSessionValue, _ b: PumpSessionValue) -> Bool {
        switch (a.activation, b.activation) {
        case let (x?, y?): abs(x.timeIntervalSince(y)) <= Config.siteChangeCluster
        case (nil, nil):
            abs(a.start.timeIntervalSince(b.start)) <= Config.siteChangeCluster
                || abs((a.end ?? a.lastSeen).timeIntervalSince(b.end ?? b.lastSeen)) <= Config.siteChangeCluster
        default: false
        }
    }

    /// A stored Nightscout session's entered fields as a rebuilt one or a prefix takes them: without a Nightscout end
    /// reason (the rebuilt piece has its own alarm or none; an open pump session has no end).
    static func withoutNightscoutReason(_ session: PumpSessionValue) -> PumpSessionValue {
        guard session.endReasonSource == .nightscout else { return session }
        var result = session
        result.endReason = nil
        result.endReasonSource = .none
        return result
    }

    /// Whether every user value of `stored` (its site, a user's fill or end reason) is on `merged`.
    private static func hasTransferred(_ stored: PumpSessionValue, to merged: PumpSessionValue) -> Bool {
        let site = stored.site == nil || merged.site == stored.site
        let fill = stored.fillSource != .user || (merged.fillSource == .user && merged.filledUnits == stored.filledUnits)
        let reason = stored.endReasonSource != .user || (merged.endReasonSource == .user && merged.endReason == stored.endReason)
        return site && fill && reason
    }

    /// The session with the other's entered fields where the session has none, or the other's rank higher
    /// (`FieldSource.rank`: the user's are never overwritten); a site where it has none.
    static func withEnteredFields(of other: PumpSessionValue, in session: PumpSessionValue) -> PumpSessionValue {
        var result = session
        if result.site == nil {
            result.site = other.site
        }
        if other.filledUnits != nil, result.filledUnits == nil || other.fillSource.rank > result.fillSource.rank {
            result.filledUnits = other.filledUnits
            result.fillSource = other.fillSource
        }
        if other.endReason != nil, result.endReason == nil || other.endReasonSource.rank > result.endReasonSource.rank {
            result.endReason = other.endReason
            result.endReasonSource = other.endReasonSource
        }
        return result
    }

    // MARK: Local time

    /// The pump's local time: where the pump's own rows are the truth and Nightscout is never a source. The backfill
    /// skips a Nightscout record there, the reconcile, the change events and the prune delete a Nightscout dose row there,
    /// and the statistics drop a Nightscout event there (`InsulinStatsEngine.usableEvents`, from `CoreDataStorage.coverage`'s
    /// `pump` entries): one rule, written and read.
    /// - Every pump session's whole `[localStart, lastSeen]`, its gaps included (app-dead time is the pump's too: it
    ///   reports the doses after a reconnect), a zero-length one too (its instant);
    /// - the pump's dose rows no session covers: `[oldestPumpDose, the oldest pump session's localStart]` (a store whose
    ///   doses go back further than its sessions: the model change, `wipeSessions`, a lost answer), from
    ///   `oldestPumpDose` on without a pump session.
    /// - **Closed intervals, both ends local**, everywhere (`isLocal`). Sorted; overlapping or touching ones merged.
    /// Nightscout keeps the time before it and between the sessions (after one's `lastSeen`, before the next one's
    /// `localStart`), and a pump session's Nightscout prefix (`[start, localStart)`) when no pump dose row is there.
    static func localTime(_ sessions: [PumpSessionValue], oldestPumpDose: Date?) -> [DateInterval] {
        let pump = sessions.filter { $0.source == .pump }
        var intervals = pump.map { session in
            let start = session.localStart ?? session.start
            return DateInterval(start: start, end: Swift.max(start, session.lastSeen))
        }
        if let oldestPumpDose {
            let firstLocal = pump.map { $0.localStart ?? $0.start }.min() ?? .distantFuture
            if oldestPumpDose < firstLocal {
                intervals.append(DateInterval(start: oldestPumpDose, end: firstLocal))
            }
        }
        return mergedClosed(intervals)
    }

    /// Closed intervals sorted, overlapping or touching ones merged; zero-length ones kept.
    static func mergedClosed(_ intervals: [DateInterval]) -> [DateInterval] {
        StatsIntervals.mergedKeepingEmpty(intervals)
    }

    /// The date is in the local time (`localTime` or `mergedClosed`: sorted, merged), both ends included.
    static func isLocal(_ date: Date, in local: [DateInterval]) -> Bool {
        let low = local.partitionIndex { $0.end >= date }
        return low < local.count && local[low].start <= date
    }

    // MARK: Prune

    /// The retention: the sessions last seen before the cutoff go; one spanning it starts there (partial; its
    /// activation kept), its gaps clipped.
    static func prune(
        _ sessions: [PumpSessionValue],
        cutoff: Date
    ) -> (deleted: [UUID], clipped: [PumpSessionValue]) {
        var deleted: [UUID] = []
        var clippedSessions: [PumpSessionValue] = []
        for session in sessions {
            if session.lastSeen < cutoff {
                deleted.append(session.id)
            } else if session.start < cutoff {
                var clipped = session
                clipped.start = cutoff
                clipped.localStart = session.localStart.map { Swift.max($0, cutoff) }
                clipped.gaps = Self.clipped(session.gaps, to: clipped.span)
                clippedSessions.append(clipped)
            }
        }
        return (deleted, clippedSessions)
    }

    /// The gaps' parts inside the span, empty ones dropped (a short rest stays: the slack is a rule for recording one).
    static func clipped(_ gaps: [DateInterval], to span: DateInterval) -> [DateInterval] {
        PumpEventStore.intersect(gaps, with: span)
    }
}
