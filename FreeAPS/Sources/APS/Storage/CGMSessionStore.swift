import CoreData
import CryptoKit
import Foundation
import LoopKit

/// What a CGM manager says about itself at one moment: the fields of a `CGMSession` row. `DeviceDataManager` reads it
/// off the manager (`KnownPlugins`).
struct CGMSnapshot: Sendable, Equatable {
    /// the manager's `pluginIdentifier`
    var plugin: String
    /// `KnownPlugins.cgmIdForStatistics` (the source app for AppGroup); nil while unknown
    var cgmId: String?
    /// the manager's localized title
    var name: String
    /// `KnownPlugins.sessionStart`; nil if the CGM gives none
    var sensorStart: Date?
    /// seconds from `sensorStart` (`KnownPlugins.cgmExpirationByPluginIdentifier`); nil if unknown
    var expectedLife: TimeInterval?
    /// `KnownPlugins.isOneMinuteReadingsEnabled`
    var oneMinute: Bool
    /// the sensor's serial (`KnownPlugins.sensorId`); nil if the manager gives none
    var sensorId: String?
    /// the `device` iAPS uploads its readings to Nightscout with (`KnownPlugins.nightscoutDevice`): the re-uploads
    /// built from the stored readings take their session's; nil if unknown
    var device: String? = nil

    /// The same state for the CGM sessions, so `DeviceDataManager` records no `.updated` event: every field equal, the
    /// sensor starts both unknown or within `BloodGlucose.sessionTolerance` (LibreTransmitter's and the G5/G6's starts
    /// move by seconds with each reading).
    static func isSameState(_ one: CGMSnapshot?, _ other: CGMSnapshot?) -> Bool {
        guard let one, let other else { return one == nil && other == nil }
        var a = one
        var b = other
        switch (one.sensorStart, other.sensorStart) {
        case (nil, nil): break
        case let (x?, y?) where BloodGlucose.isSameSession(x, y):
            a.sensorStart = nil
            b.sensorStart = nil
        default: return false
        }
        return a == b
    }
}

/// One call of a `DeviceDataManager` hook, with the CGM as it was then.
struct CGMSessionEvent: Sendable, Equatable {
    /// A `.sensorStart` CGM event's fields.
    struct SensorStart: Sendable, Equatable {
        /// the sensor's activation
        var date: Date
        /// the event's warm-up: a manager's session start may be its end (the G7's `sensorFinishesWarmupAt`)
        var warmup: TimeInterval?
        /// the event's device identifier (`KnownPlugins.sensorId(of:cgmManager:)`); nil for a transmitter's
        var sensorId: String?
    }

    enum Kind: Sendable, Equatable {
        /// the CGM manager set, changed or restored at launch; `cgm` nil: removed (or none restored)
        case manager
        /// a `.sensorStart` CGM event
        case sensorStarted(SensorStart)
        /// the manager's state, or its readings, changed (`cgmManagerDidUpdateState`, new readings): its session start
        /// may have moved
        case updated
    }

    var kind: Kind
    var cgm: CGMSnapshot?
    var at: Date
    /// the newest reading before this event (`DeviceDataManager.latestCgmReadingDate`): a new sensor of the same CGM
    /// starts after it (`CGMSessionRules.changes`)
    var lastReadingAt: Date?

    /// The CGM the rules take. A sensor start event is authoritative: unless the manager's own session start agrees
    /// with it (from the activation to the warm-up's end, with the tolerance either side), the manager's state is the
    /// old sensor's (LibreTransmitter updates it on the main queue after it sent the event), and the event's date and
    /// device identifier replace it. When they agree the manager's start is kept, so its later states compare equal.
    var observed: CGMSnapshot? {
        guard var cgm else { return nil }
        guard case let .sensorStarted(event) = kind else { return cgm }
        let tolerance = BloodGlucose.sessionTolerance
        let agrees = cgm.sensorStart.map { start in
            start >= event.date.addingTimeInterval(-tolerance) &&
                start <= event.date.addingTimeInterval((event.warmup ?? 0) + tolerance)
        } ?? false
        if agrees {
            cgm.sensorId = cgm.sensorId ?? event.sensorId
        } else {
            cgm.sensorStart = event.date
            cgm.sensorId = event.sensorId ?? cgm.sensorId
        }
        return cgm
    }
}

/// Where a `CGMSession` row came from (`CGMSession.source`; a row without one is recorded).
enum CGMSessionSource: String, Sendable, Equatable {
    /// written from `DeviceDataManager`'s events (`CGMSessionRules`)
    case recorded
    /// the user's answer to which CGM gave the Unknown readings (`CGMSessionStore.enter`): closed, and never where a
    /// recorded session is
    case entered
    /// named from Nightscout entries' `device` (`NightscoutCGMBackfill`, `CGMSessionStore.storeBackfilled`): closed,
    /// and never where a recorded or an entered session is
    case backfilled
}

/// One `CGMSession` row: one sensor session of a CGM, or a period a sensorless CGM (Nightscout, AppGroup, the
/// simulator) was the CGM. `[start, end)`; `end` nil while open.
struct CGMSessionRecord: Sendable, Equatable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date?
    var plugin: String
    var cgmId: String?
    var name: String
    var sensorStart: Date?
    var expectedLife: TimeInterval?
    var oneMinute: Bool
    var sensorId: String?
    /// the readings' Nightscout `device` (`CGMSnapshot.device`; a backfilled session's: the entries')
    var device: String?
    var source: CGMSessionSource

    init(id: UUID, start: Date, end: Date? = nil, _ cgm: CGMSnapshot, source: CGMSessionSource = .recorded) {
        self.id = id
        self.start = start
        self.end = end
        self.source = source
        plugin = cgm.plugin
        cgmId = cgm.cgmId
        name = cgm.name
        sensorStart = cgm.sensorStart
        expectedLife = cgm.expectedLife
        oneMinute = cgm.oneMinute
        sensorId = cgm.sensorId
        device = cgm.device
    }

    /// The sensor start the statistics take (`CGMStatsEngine.stats`' `sensorStarts`): the sensor's own, else the
    /// session's start.
    var sensorStartOrStart: Date { sensorStart ?? start }

    /// `[start, end)`; an open session has no end.
    func contains(_ date: Date) -> Bool {
        date >= start && (end.map { date < $0 } ?? true)
    }

    /// `[start, end)`, an open session's to the distant future.
    var interval: DateInterval {
        DateInterval(start: start, end: Swift.max(end ?? .distantFuture, start))
    }
}

/// The entered and the backfilled sessions' rules: recorded > entered > backfilled. An entered session holds only
/// the time no recorded session covers, a backfilled one only the time neither covers (the user's answer always wins
/// over Nightscout's). Applied when they are written and again when they are read (recording may add sessions later,
/// a first session after a wipe opens at its sensor start, an answer may come after a backfill). Pure.
enum CGMEnteredSessions {
    /// The parts of `interval` outside every one of `others`, by start; none of zero length.
    static func subtract(_ interval: DateInterval, _ others: [DateInterval]) -> [DateInterval] {
        var parts: [DateInterval] = []
        var cursor = interval.start
        for other in others.sorted(by: { $0.start < $1.start }) where other.end > cursor && other.start < interval.end {
            if other.start > cursor {
                parts.append(DateInterval(start: cursor, end: other.start))
            }
            cursor = Swift.max(cursor, other.end)
        }
        if cursor < interval.end {
            parts.append(DateInterval(start: cursor, end: interval.end))
        }
        return parts
    }

    /// Each session's parts outside `others` (`subtract`): the first part keeps its id, a later one gets `pieceID`.
    static func clipped(_ sessions: [CGMSessionRecord], outside others: [DateInterval]) -> [CGMSessionRecord] {
        sessions.flatMap { session in
            subtract(session.interval, others).enumerated().map { index, part in
                var piece = session
                piece.id = pieceID(session.id, index)
                piece.start = part.start
                piece.end = part.end
                return piece
            }
        }
    }

    /// The entered sessions clipped to the time no recorded session covers, the backfilled ones to the time neither
    /// covers, with the recorded ones, by start.
    static func effective(_ sessions: [CGMSessionRecord]) -> [CGMSessionRecord] {
        let recorded = sessions.filter { $0.source == .recorded }
        let entered = sessions.filter { $0.source == .entered }
        let backfilled = sessions.filter { $0.source == .backfilled }
        guard entered.isNotEmpty || backfilled.isNotEmpty else { return CGMSessionRules.ordered(recorded) }
        let enteredParts = clipped(entered, outside: recorded.map(\.interval))
        let backfilledParts = clipped(backfilled, outside: (recorded + enteredParts).map(\.interval))
        return CGMSessionRules.ordered(recorded + enteredParts + backfilledParts)
    }

    /// The id of a session's part after the first, the same at every read: the id with its last two bytes changed by
    /// the part's index.
    static func pieceID(_ id: UUID, _ index: Int) -> UUID {
        guard index > 0 else { return id }
        var bytes = id.uuid
        bytes.14 ^= 0x5A
        bytes.15 ^= UInt8(truncatingIfNeeded: index)
        return UUID(uuid: bytes)
    }
}

/// The readings of one session (`CGMSessionAttribution.attribute`).
struct CGMSessionReadings<Reading> {
    var session: CGMSessionRecord
    var readings: [Reading]
}

extension CGMSessionReadings: Sendable where Reading: Sendable {}
extension CGMSessionReadings: Equatable where Reading: Equatable {}

/// The readings by session, and the ones no session covers (the Unknown CGM).
struct CGMAttribution<Reading> {
    /// every session given, by start, each with its readings (maybe none)
    var bySession: [CGMSessionReadings<Reading>]
    var unknown: [Reading]
}

extension CGMAttribution: Sendable where Reading: Sendable {}
extension CGMAttribution: Equatable where Reading: Equatable {}

enum CGMSessionAttribution {
    /// Each reading goes to the session whose `[start, end)` holds its time (the latest starting one, should two
    /// overlap), else to `unknown`. The readings keep their order within each group.
    static func attribute<Reading>(
        _ readings: [Reading],
        to sessions: [CGMSessionRecord],
        time: (Reading) -> Date
    ) -> CGMAttribution<Reading> {
        let sorted = CGMSessionRules.ordered(sessions)
        var bySession = sorted.map { CGMSessionReadings<Reading>(session: $0, readings: []) }
        var unknown: [Reading] = []
        for reading in readings {
            let date = time(reading)
            // the sessions starting at or before the reading: the first index after them
            var low = 0
            var high = sorted.count
            while low < high {
                let mid = (low + high) / 2
                if sorted[mid].start <= date {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            // the latest of them holding it (a `while` loop: a Debug build's closures and ranges cost per reading)
            var index = low - 1
            while index >= 0, !sorted[index].contains(date) {
                index -= 1
            }
            if index >= 0 {
                bySession[index].readings.append(reading)
            } else {
                unknown.append(reading)
            }
        }
        return CGMAttribution(bySession: bySession, unknown: unknown)
    }

    static func attribute(_ readings: [GlucosePoint], to sessions: [CGMSessionRecord]) -> CGMAttribution<GlucosePoint> {
        attribute(readings, to: sessions, time: \.time)
    }

    /// The sensor starts `CGMStatsEngine.stats` takes: each session's `sensorStart ?? start`, ascending.
    static func sensorStarts(_ sessions: [CGMSessionRecord]) -> [Date] {
        sessions.map(\.sensorStartOrStart).sorted()
    }
}

/// The CGM sessions' rules: the writes an observed CGM needs against the stored sessions. Pure.
///
/// - Exactly one open session at a time. Opening one closes the previous at the new one's start: never before the
///   previous start, never overlapping.
/// - A different CGM (plugin, or a known `cgmId` that differs) closes the open session now and opens one now: the old
///   CGM gave the readings until the switch, whenever the new sensor started.
/// - The same CGM with a new sensor (a `sensorStart` later than the open one's by more than
///   `BloodGlucose.sessionTolerance`, a first `sensorStart` past the open session's start by more than it, or, while
///   either start is unknown, a known `sensorId` that differs) opens a session at the sensor start when that is after
///   the open one's start and after the old sensor's last reading (`lastReadingAt`) and not in the future, else just
///   after that reading (now when none is known): a sensor inserted or activated ahead (a pre-soaked G7, a Libre 3
///   started a day early) leaves the old sensor every reading it gave, and one that started while the app was down
///   gets its readings.
/// - A sensor start earlier than the open one's (beyond the tolerance) is a stale state (LibreTransmitter's before its
///   observables catch up), not a new sensor: its start and sensor id are ignored, its other fields merged (a clock set
///   back by more than the tolerance leaves a computed start, LibreTransmitter's or the G5/G6's, stale for the rest of
///   the sensor).
/// - A clock set forward by more than the tolerance can open a second session for the same sensor when its start is
///   computed as now − age (LibreTransmitter, the G5/G6), as the readings' `BloodGlucose.isSameSession` does.
/// - Switching CGM and back makes a second row for the same sensor (the Sensors view merges them by `cgmId` and
///   `sensorStart`).
/// - The same CGM and sensor: no new row; the other fields are updated in place (a nil keeps the stored value).
/// - No CGM: the open session closes now.
/// - No open session (the first run, a wipe, after a removal): one opens at the sensor start when it is known, not in
///   the future and not before the last session's end, else now. Everything earlier stays Unknown.
enum CGMSessionRules {
    /// two sensor starts within this are the same sensor: the readings' rule (`BloodGlucose.isSameSession`)
    static let tolerance = BloodGlucose.sessionTolerance
    /// a new sensor's session starts this after the old sensor's last reading (truncated to the second, as the stored
    /// readings are), so that reading stays the old session's (`[start, end)`)
    static let afterLastReading: TimeInterval = 1

    /// The sessions to write (upserted by id), given every stored session. `newID` is the id of a session it opens;
    /// `lastReadingAt` the newest reading before the event (nil: none known; also after an empty `.newData` batch,
    /// which clears `DeviceDataManager.latestCgmReadingDate`, though no shipped plugin sends one: the new sensor's
    /// start then falls back to its sensor start).
    static func changes(
        for cgm: CGMSnapshot?,
        sessions: [CGMSessionRecord],
        now: Date,
        newID: UUID,
        lastReadingAt: Date? = nil
    ) -> [CGMSessionRecord] {
        var sorted = ordered(sessions)
        var writes: [CGMSessionRecord] = []

        // more than one open session (should never happen): each but the last closes at the next one's start
        for index in sorted.indices.dropLast() where sorted[index].end == nil {
            sorted[index].end = max(sorted[index].start, sorted[index + 1].start)
            writes.append(sorted[index])
        }

        func close(_ session: CGMSessionRecord, at date: Date) {
            var closed = session
            closed.end = max(session.start, date)
            writes.append(closed)
        }

        guard let last = sorted.last, last.end == nil else {
            // no open session: from the last one's end on
            if let cgm {
                let after = sorted.last.map { $0.end ?? $0.start } ?? .distantPast
                let start = startDate(cgm.sensorStart, from: after, now: now, inclusive: true)
                writes.append(CGMSessionRecord(id: newID, start: start, cgm))
            }
            return writes
        }

        guard let cgm else {
            close(last, at: now)
            return writes
        }
        if !isSameCGM(last, cgm) {
            let switched = max(now, last.start)
            close(last, at: switched)
            writes.append(CGMSessionRecord(id: newID, start: switched, cgm))
        } else if isNewSensor(last, cgm) {
            let start: Date
            if let lastReadingAt {
                // the new sensor's readings may be in the batch that told: from just after the old one's last on
                let bound = max(last.start, lastReadingAt.truncatedToSecond.addingTimeInterval(afterLastReading))
                let sensorStart = cgm.sensorStart.flatMap { $0 > bound && $0 <= now ? $0 : nil }
                start = sensorStart ?? bound
            } else {
                start = startDate(cgm.sensorStart, from: last.start, now: now, inclusive: false)
            }
            close(last, at: start)
            writes.append(CGMSessionRecord(id: newID, start: start, cgm))
        } else {
            var current = cgm
            if isStale(last, cgm) {
                // the old sensor's start and id; the rest is the CGM's
                current.sensorStart = nil
                current.sensorId = nil
            }
            let updated = merged(last, current)
            if updated != last {
                writes.append(updated)
            }
        }
        return writes
    }

    /// A sensor start earlier than the session's by more than the tolerance: the old sensor's (or a clock set back).
    static func isStale(_ session: CGMSessionRecord, _ cgm: CGMSnapshot) -> Bool {
        guard let stored = session.sensorStart, let current = cgm.sensorStart else { return false }
        return stored.timeIntervalSince(current) > tolerance
    }

    /// By start; at the same start a closed (zero-length) session before the open one.
    static func ordered(_ sessions: [CGMSessionRecord]) -> [CGMSessionRecord] {
        sessions.sorted { ($0.start, $0.end ?? .distantFuture) < ($1.start, $1.end ?? .distantFuture) }
    }

    /// A new session's start: the sensor start when it is known, not in the future and after `bound` (at it too when
    /// `inclusive`), else now (never before `bound`).
    static func startDate(_ sensorStart: Date?, from bound: Date, now: Date, inclusive: Bool) -> Date {
        guard let sensorStart, sensorStart <= now else { return max(now, bound) }
        let isAfter = inclusive ? sensorStart >= bound : sensorStart > bound
        return isAfter ? sensorStart : max(now, bound)
    }

    /// The same plugin, and no two known CGM ids that differ (an AppGroup CGM's source app is nil until a reading).
    static func isSameCGM(_ session: CGMSessionRecord, _ cgm: CGMSnapshot) -> Bool {
        guard session.plugin == cgm.plugin else { return false }
        guard let stored = session.cgmId, let current = cgm.cgmId else { return true }
        return stored == current
    }

    /// With both sensor starts known: the current one later than the stored one by more than the tolerance (an
    /// earlier one is a stale state). The sensor ids decide only while a start is unknown: the managers' ids and their
    /// events' differ in form (the G7's sensor id and serial, LibreTransmitter's serial and UID). Otherwise the first
    /// known sensor start later than the session's start by more than the tolerance (a sensor started inside it).
    static func isNewSensor(_ session: CGMSessionRecord, _ cgm: CGMSnapshot) -> Bool {
        if let stored = session.sensorStart, let current = cgm.sensorStart {
            return current.timeIntervalSince(stored) > tolerance
        }
        if let stored = session.sensorId, let current = cgm.sensorId, stored != current {
            return true
        }
        guard let current = cgm.sensorStart else { return false }
        return current.timeIntervalSince(session.start) > tolerance
    }

    /// The session with the CGM's fields: the first known sensor start kept, a nil keeping the stored value.
    static func merged(_ session: CGMSessionRecord, _ cgm: CGMSnapshot) -> CGMSessionRecord {
        var updated = session
        updated.name = cgm.name
        updated.cgmId = cgm.cgmId ?? session.cgmId
        updated.sensorStart = session.sensorStart ?? cgm.sensorStart
        updated.expectedLife = cgm.expectedLife ?? session.expectedLife
        updated.oneMinute = cgm.oneMinute
        updated.sensorId = cgm.sensorId ?? session.sensorId
        // a device holding the sensor's id is kept: a later string of the same sensor would split Nightscout's delta
        let keeps = NightscoutCGMDevice.hasID(session.device, sensorId: session.sensorId ?? cgm.sensorId)
        updated.device = keeps ? session.device : cgm.device ?? session.device
        return updated
    }
}

/// The store of the CGM sessions (`CGMSession`): which CGM, and which sensor, gave the readings when. The statistics
/// attribute readings to them by time (`CGMSessionAttribution`); readings no session covers are the Unknown CGM.
///
/// - The only writer of `CGMSession`. The events come from `DeviceDataManager` (`record`: the manager set, changed,
///   restored or removed, a `.sensorStart` CGM event, a changed state after new readings or a state update), are
///   buffered (AsyncStream) and applied in order
///   on one `TaskSerializer` with the Settings wipe and the entered sessions' writes, on background contexts only.
///   The CGM and glucose paths never wait for it.
/// - The rules (`CGMSessionRules`: one open session, closing at a new one) see the recorded sessions only and never
///   touch an entered one (`enter`: the user's answer for the Unknown readings) or a backfilled one
///   (`storeBackfilled`: named from Nightscout). Recorded > entered > backfilled: each is clipped to the time the
///   ones before it don't cover when it is written and when it is read (`CGMEnteredSessions`). An answer leaves the
///   backfilled sessions stored: clearing it shows them again.
/// - A state equal to the last one applied is skipped without a read; a relaunch with the same manager and sensor
///   reads the rows and writes nothing.
/// - Retention: all of it (a few rows a month).
actor CGMSessionStore: AppService, LifetimeOwner {
    /// The entity name (the Settings wipe list shows it).
    enum Entity {
        static let sessions = "CGMSession"
    }

    let lifetime = Lifetime()

    private let container: NSPersistentContainer
    private let now: @Sendable() -> Date
    private let serializer = TaskSerializer()
    private let events: AsyncStream<CGMSessionEvent>
    private let eventsContinuation: AsyncStream<CGMSessionEvent>.Continuation

    /// the CGM of the last event applied (nil: none, or removed); `hasApplied` false until the first
    private var lastCGM: CGMSnapshot?
    private var hasApplied = false
    /// the open recorded session after the last write (`currentDevice`, read by the CGM path without waiting)
    private nonisolated let openSession = Locked<CGMSessionRecord?>(nil)
    /// where the Nightscout backfill windows are kept (`backfillWindows`)
    private let defaults: UserDefaults

    /// The defaults key of the Nightscout backfill's windows.
    static let backfillWindowsKey = "CGMSessionStore.backfillWindows"

    init(
        container: NSPersistentContainer = CoreDataStack.shared.persistentContainer,
        now: @escaping @Sendable() -> Date = { Date() },
        defaults: UserDefaults = .standard
    ) {
        self.container = container
        self.now = now
        self.defaults = defaults
        let (stream, continuation) = AsyncStream.makeStream(of: CGMSessionEvent.self)
        events = stream
        eventsContinuation = continuation
    }

    /// Consumes the events; those recorded before it waited in the stream.
    func start() async {
        observe(events) { me, event in
            await me.apply(event)
        }
    }

    /// A `DeviceDataManager` hook's event: queued, returns at once.
    nonisolated func record(_ event: CGMSessionEvent) {
        eventsContinuation.yield(event)
    }

    /// One event against the stored sessions, on the serializer.
    func apply(_ event: CGMSessionEvent) async {
        await serializer.run {
            let cgm = event.observed
            guard !hasApplied || cgm != lastCGM else { return }
            if await write(cgm, at: event.at, lastReadingAt: event.lastReadingAt, reason: Self.describe(event.kind)) {
                hasApplied = true
                lastCGM = cgm
            }
        }
    }

    /// The sessions overlapping the interval (an open one reaches to the future), by start (`CGMSessionRules.ordered`):
    /// the recorded ones, and the entered ones' parts no recorded session covers.
    func sessions(in interval: DateInterval) async -> [CGMSessionRecord] {
        do {
            return try await container.performBackgroundTask { context in
                try Self.sessions(in: interval, context: context)
            }
        } catch {
            warning(.service, "CGM sessions: reading failed", error: error)
            return []
        }
    }

    /// The Nightscout device of the open recorded session, when it is this plugin's and holds its sensor's id
    /// (`NightscoutCGMDevice.hasID`): the device the readings of that sensor are uploaded with
    /// (`NightscoutCGMDevice.live`). As of the last write; returns at once.
    nonisolated func currentDevice(plugin: String) -> String? {
        guard let open = openSession.value, open.plugin == plugin,
              NightscoutCGMDevice.hasID(open.device, sensorId: open.sensorId)
        else { return nil }
        return open.device
    }

    /// The windows the Nightscout backfill named the Unknown readings in (`storeBackfilled`'s), merged, oldest first:
    /// the Unknown card offers the backfill only for readings outside them.
    func backfillWindows() -> [DateInterval] {
        let pairs = defaults.array(forKey: Self.backfillWindowsKey) as? [[Double]] ?? []
        return pairs.compactMap { pair in
            guard pair.count == 2, pair[0] <= pair[1] else { return nil }
            return DateInterval(start: Date(timeIntervalSince1970: pair[0]), end: Date(timeIntervalSince1970: pair[1]))
        }
    }

    private func noteBackfillWindow(_ window: DateInterval) {
        var merged: [DateInterval] = []
        for interval in (backfillWindows() + [window]).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: Swift.max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        defaults.set(
            merged.map { [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] },
            forKey: Self.backfillWindowsKey
        )
    }

    /// The Settings wipe of `CGMSession`: every row goes (the entered and the backfilled ones too, and the backfill's
    /// windows), then a session opens for the current CGM as on the first run (at its sensor start if known, else now).
    func wipe() async {
        await serializer.run {
            openSession.value = nil
            defaults.removeObject(forKey: Self.backfillWindowsKey)
            do {
                try await container.performBackgroundTask { context in
                    let rows = try context.fetch(NSFetchRequest<CGMSession>(entityName: Entity.sessions))
                    rows.forEach(context.delete)
                    if context.hasChanges {
                        try context.save()
                    }
                }
            } catch {
                warning(.service, "CGM sessions: wiping failed", error: error)
                return
            }
            guard hasApplied else { return }
            _ = await write(lastCGM, at: self.now(), lastReadingAt: nil, reason: "the wipe")
        }
    }

    /// The user's answer for the Unknown readings: closed sessions written as entered, each clipped to the time no
    /// recorded session covers. Every stored entered one they overlap, or that overlaps `replacing`, goes whole: an
    /// answer's first session can start a warm-up before the Unknown readings, and a part of the old answer left
    /// there would be a period of its own. One save; returns whether it succeeded.
    @discardableResult func enter(_ sessions: [CGMSessionRecord], replacing: DateInterval? = nil) async -> Bool {
        await writeEntered("entering \(sessions.count)") { context in
            try Self.enter(sessions, replacing: replacing, trims: false, in: context)
        }
    }

    /// The entered sessions' time in the interval goes (a part outside it stays). Returns whether it succeeded.
    @discardableResult func removeEntered(in interval: DateInterval) async -> Bool {
        await writeEntered("removing the entered ones in an interval") { context in
            try Self.enter([], replacing: interval, trims: true, in: context)
        }
    }

    /// Every entered session goes. Returns whether it succeeded.
    @discardableResult func removeAllEntered() async -> Bool {
        await writeEntered("removing every entered one") { context in
            try Self.enter([], replacing: DateInterval(start: .distantPast, end: .distantFuture), trims: false, in: context)
        }
    }

    /// A Nightscout backfill's sessions (`NightscoutCGMBackfill`): the stored backfilled ones' time in `replacing` goes
    /// (their parts outside it stay), the new ones are written as backfilled, each clipped to the time no recorded or
    /// entered session covers. One save; returns whether it succeeded.
    /// The window is noted (`backfillWindows`) when it succeeded.
    @discardableResult func storeBackfilled(_ sessions: [CGMSessionRecord], replacing: DateInterval) async -> Bool {
        let stored = await writeEntered("storing \(sessions.count) backfilled") { context in
            try Self.storeBackfilled(sessions, replacing: replacing, in: context)
        }
        if stored {
            noteBackfillWindow(replacing)
        }
        return stored
    }

    /// One write of the entered (or the backfilled) sessions on the serializer; returns whether it succeeded.
    private func writeEntered(
        _ reason: String,
        _ body: @escaping @Sendable(NSManagedObjectContext) throws -> [String]
    ) async -> Bool {
        await serializer.run {
            do {
                let lines = try await container.performBackgroundTask(body)
                for line in lines {
                    debug(.service, "CGM session (\(reason)): \(line)")
                }
                return true
            } catch {
                warning(.service, "CGM sessions: \(reason) failed", error: error)
                return false
            }
        }
    }

    /// Reads every session, writes the rules' changes, one save. Returns whether it succeeded.
    private func write(_ cgm: CGMSnapshot?, at date: Date, lastReadingAt: Date?, reason: String) async -> Bool {
        do {
            let (lines, open) = try await container.performBackgroundTask { context in
                let lines = try Self.apply(cgm, at: date, newID: UUID(), lastReadingAt: lastReadingAt, in: context)
                let open = try Self.openRecorded(in: context)
                return (lines, open)
            }
            openSession.value = open
            for line in lines {
                debug(.service, "CGM session (\(reason)): \(line)")
            }
            return true
        } catch {
            warning(.service, "CGM sessions: writing failed", error: error)
            return false
        }
    }

    private static func describe(_ kind: CGMSessionEvent.Kind) -> String {
        switch kind {
        case .manager: "the CGM manager"
        case let .sensorStarted(event): "a sensor start at \(event.date.formatted(.iso8601))"
        case .updated: "a CGM state update"
        }
    }

    // MARK: - Core Data

    /// The rules' changes against every stored session, one save; returns a log line per write.
    static func apply(
        _ cgm: CGMSnapshot?,
        at now: Date,
        newID: UUID,
        lastReadingAt: Date? = nil,
        in context: NSManagedObjectContext
    ) throws -> [String] {
        let rows = try context.fetch(NSFetchRequest<CGMSession>(entityName: Entity.sessions))
        // the recorded sessions only: the rules never see or touch an entered one
        let stored = rows.compactMap { row in record(of: row).map { (row: row, record: $0) } }
            .filter { $0.record.source == .recorded }
        let writes = CGMSessionRules.changes(
            for: cgm,
            sessions: stored.map(\.record),
            now: now,
            newID: newID,
            lastReadingAt: lastReadingAt
        )
        var lines: [String] = []
        for write in writes {
            if let entry = stored.first(where: { $0.record.id == write.id }) {
                apply(write, to: entry.row)
                lines.append("updated \(describe(write))")
            } else {
                apply(write, to: CGMSession(context: context))
                lines.append("opened \(describe(write))")
            }
        }
        if context.hasChanges {
            try context.save()
        }
        return lines
    }

    /// The open recorded session (the latest starting, should there be two).
    static func openRecorded(in context: NSManagedObjectContext) throws -> CGMSessionRecord? {
        let request = NSFetchRequest<CGMSession>(entityName: Entity.sessions)
        request.predicate = NSPredicate(format: "end == nil")
        return try context.fetch(request).compactMap(record(of:))
            .filter { $0.source == .recorded }
            .max { $0.start < $1.start }
    }

    /// A backfilled session's id: the same for the same CGM and start at every run (`storeBackfilled`), so a re-run
    /// changes no id it needn't.
    static func backfilledID(cgmId: String?, start: Date) -> UUID {
        let key = "backfilled|\(cgmId ?? "")|\(Int64((start.timeIntervalSince1970 * 1000).rounded()))"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        // a version 4, variant 1 layout
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Every row is read (a few a month): an entered session is clipped against every recorded one, wherever it is.
    static func sessions(in interval: DateInterval, context: NSManagedObjectContext) throws -> [CGMSessionRecord] {
        let rows = try context.fetch(NSFetchRequest<CGMSession>(entityName: Entity.sessions))
        return CGMEnteredSessions.effective(rows.compactMap(record(of:))).filter { session in
            session.start < interval.end && (session.end.map { $0 > interval.start } ?? true)
        }
    }

    /// The new entered sessions (closed ones only), clipped against the recorded ones; the stored entered ones
    /// overlapping the new ones or `replacing` go, whole (`trims`: only that time, the parts outside it kept). One
    /// save; returns a log line per write.
    static func enter(
        _ sessions: [CGMSessionRecord],
        replacing: DateInterval?,
        trims: Bool,
        in context: NSManagedObjectContext
    ) throws -> [String] {
        let rows = try context.fetch(NSFetchRequest<CGMSession>(entityName: Entity.sessions))
        let stored = rows.compactMap { row in record(of: row).map { (row: row, record: $0) } }
        // the backfilled ones don't clip an answer: they are clipped by it when read
        let recorded = stored.filter { $0.record.source == .recorded }.map(\.record.interval)
        let entered = sessions.filter { $0.end != nil }.map { session -> CGMSessionRecord in
            var session = session
            session.source = .entered
            return session
        }
        let replaced = entered.map(\.interval) + (replacing.map { [$0] } ?? [])
        var lines: [String] = []
        // the stored entered ones less the replaced time (trimmed: their parts left as new rows)
        for entry in stored where entry.record.source == .entered {
            let parts = CGMEnteredSessions.subtract(entry.record.interval, replaced)
            guard parts != [entry.record.interval] else { continue }
            guard trims else {
                context.delete(entry.row)
                lines.append("removed \(describe(entry.record))")
                continue
            }
            context.delete(entry.row)
            lines.append("removed \(describe(entry.record))")
            for part in parts {
                var kept = entry.record
                kept.id = UUID()
                kept.start = part.start
                kept.end = part.end
                apply(kept, to: CGMSession(context: context))
                lines.append("kept \(describe(kept))")
            }
        }
        for piece in CGMEnteredSessions.clipped(entered, outside: recorded) {
            var piece = piece
            piece.id = UUID()
            apply(piece, to: CGMSession(context: context))
            lines.append("entered \(describe(piece))")
        }
        if context.hasChanges {
            try context.save()
        }
        return lines
    }

    /// The backfilled sessions (closed ones only) clipped against the recorded and the entered ones; the stored
    /// backfilled ones lose their time in `replacing`, their parts outside it kept as new rows. Their ids come from
    /// their CGM and start (`backfilledID`). One save; returns a log line per write.
    static func storeBackfilled(
        _ sessions: [CGMSessionRecord],
        replacing: DateInterval,
        in context: NSManagedObjectContext
    ) throws -> [String] {
        let rows = try context.fetch(NSFetchRequest<CGMSession>(entityName: Entity.sessions))
        let stored = rows.compactMap { row in record(of: row).map { (row: row, record: $0) } }
        let recorded = stored.filter { $0.record.source == .recorded }.map(\.record)
        let entered = CGMEnteredSessions.clipped(
            stored.filter { $0.record.source == .entered }.map(\.record),
            outside: recorded.map(\.interval)
        )
        var lines: [String] = []
        for entry in stored where entry.record.source == .backfilled {
            let parts = CGMEnteredSessions.subtract(entry.record.interval, [replacing])
            guard parts != [entry.record.interval] else { continue }
            context.delete(entry.row)
            lines.append("removed \(describe(entry.record))")
            for part in parts {
                var kept = entry.record
                kept.id = backfilledID(cgmId: kept.cgmId, start: part.start)
                kept.start = part.start
                kept.end = part.end
                apply(kept, to: CGMSession(context: context))
                lines.append("kept \(describe(kept))")
            }
        }
        let backfilled = sessions.filter { $0.end != nil }.map { session -> CGMSessionRecord in
            var session = session
            session.source = .backfilled
            return session
        }
        for piece in CGMEnteredSessions.clipped(backfilled, outside: (recorded + entered).map(\.interval)) {
            var piece = piece
            piece.id = backfilledID(cgmId: piece.cgmId, start: piece.start)
            apply(piece, to: CGMSession(context: context))
            lines.append("backfilled \(describe(piece))")
        }
        if context.hasChanges {
            try context.save()
        }
        return lines
    }

    /// nil without an id, a start or a plugin, or with a source this version doesn't know.
    static func record(of row: CGMSession) -> CGMSessionRecord? {
        guard let id = row.id, let start = row.start, let plugin = row.plugin else { return nil }
        let source: CGMSessionSource
        if let raw = row.source {
            guard let known = CGMSessionSource(rawValue: raw) else { return nil }
            source = known
        } else {
            source = .recorded
        }
        return CGMSessionRecord(
            id: id,
            start: start,
            end: row.end,
            CGMSnapshot(
                plugin: plugin,
                cgmId: row.cgmId,
                name: row.name ?? plugin,
                sensorStart: row.sensorStart,
                expectedLife: row.expectedLife?.doubleValue,
                oneMinute: row.oneMinute,
                sensorId: row.sensorId,
                device: row.device
            ),
            source: source
        )
    }

    static func apply(_ record: CGMSessionRecord, to row: CGMSession) {
        row.id = record.id
        row.start = record.start
        row.end = record.end
        row.plugin = record.plugin
        row.cgmId = record.cgmId
        row.name = record.name
        row.sensorStart = record.sensorStart
        row.expectedLife = record.expectedLife.map { NSNumber(value: $0) }
        row.oneMinute = record.oneMinute
        row.sensorId = record.sensorId
        row.device = record.device
        row.source = record.source.rawValue
    }

    static func describe(_ session: CGMSessionRecord) -> String {
        let end = session.end.map { $0.formatted(.iso8601) } ?? "open"
        let sensor = session.sensorStart.map { $0.formatted(.iso8601) } ?? "unknown"
        return "\(session.cgmId ?? session.plugin) \(session.start.formatted(.iso8601)) – \(end), sensor \(sensor)" +
            (session.sensorId.map { " (\($0))" } ?? "") + (session.source == .recorded ? "" : ", \(session.source.rawValue)")
    }
}
