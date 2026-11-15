@testable import FreeAPS
import XCTest

private typealias Engine = PatchStatsEngine

/// The pods, patches and sites from the pump sessions (both sources), the reader's rules, their numbers by wear day,
/// the period's pick and Today's comparison.
final class PatchStatsEngineTests: XCTestCase {
    // MARK: - Fixtures

    private static let calendar = StatsFixtures.berlin

    private var calendar: Calendar { Self.calendar }

    /// 2026-10-10 00:00 Europe/Berlin (CEST): no DST change for weeks after
    private static let t0 = StatsFixtures.week

    private let accuracy = 1E-6

    private func at(_ hours: Double) -> Date {
        Self.t0.addingTimeInterval(.hours(hours))
    }

    /// The same id for the same start (and source), so two reads of the same rows have the same sessions.
    private func id(_ start: Double, _ source: PumpEventSource) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-%04ld-%012lld",
            Int(source.rawValue),
            Int64((start + 100_000) * 1000)
        ))!
    }

    /// A pump session (or a Nightscout one) `[from, to]` h, closed at its last seen unless open; a tube pump's is a site.
    private func record(
        _ plugin: String? = "Medtrum",
        source: PumpEventSource = .pump,
        activatedAt activation: Double?,
        from start: Double? = nil,
        to lastSeen: Double,
        open: Bool = false,
        gaps: [(Double, Double)] = [],
        localStart: Double? = nil,
        site: String? = nil,
        id explicitID: UUID? = nil
    ) -> PumpSessionValue {
        let start = start ?? activation ?? 0
        var flags: PumpSessionValue.Flags = source == .nightscout && plugin != nil ? .pluginAssumed : []
        if plugin != nil, !PumpSessionRules.isPodOrPatch(plugin) {
            flags.insert(.site)
        }
        return PumpSessionValue(
            id: explicitID ?? id(start, source),
            source: source,
            plugin: plugin,
            activation: activation.map { at($0) },
            start: at(start),
            localStart: source == .pump ? at(localStart ?? start) : nil,
            lastSeen: at(lastSeen),
            end: open ? nil : at(lastSeen),
            gaps: gaps.map { DateInterval(start: at($0.0), end: at($0.1)) },
            flags: flags,
            site: site
        )
    }

    private var flatSchedule: BasalScheduleRecordValue {
        BasalScheduleRecordValue(
            date: at(-24 * 400),
            source: .local,
            entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
        )
    }

    private let bands = StatsBands(low: 70, high: 180, units: .mgdL)

    /// A reading every 5 minutes in `[start, end)` h.
    private func readings(_ start: Double, _ end: Double, mgdl: Int16 = 120) -> [GlucosePoint] {
        stride(from: start * 60, to: end * 60, by: 5).map { GlucosePoint(time: at($0 / 60), mgdl: mgdl) }
    }

    /// A session covered from its activation for `hours`, without gaps.
    private func session(
        activatedAt start: Double,
        wear hours: Double,
        plugin: String = "Medtrum",
        open: Bool = false
    ) -> [PumpSessionValue] {
        [record(plugin, activatedAt: start, to: start + hours, open: open)]
    }

    private func stats(
        _ sessions: [PatchSession],
        rows: [PumpSessionValue],
        events: [PumpEventRecord] = [],
        iob: [IOBPoint] = [],
        glucose: [GlucosePoint] = [],
        deliveringPlugin: String? = nil
    ) -> [PatchStats] {
        Engine.stats(
            sessions,
            input: PatchInput(
                insulin: InsulinInput(events: events, coverage: StatsFixtures.covered(rows), schedules: [flatSchedule], iob: iob),
                glucose: glucose
            ),
            bands: bands,
            allowOneMinuteLoop: false,
            inUseID: Engine.inUse(sessions, deliveringPlugin: deliveringPlugin)?.id,
            now: at(24 * 60),
            calendar: calendar
        )
    }

    // MARK: - Sessions

    /// The pump sessions of both sources, one to one: the row's id, plugin and kind, from the activation to the end,
    /// the stretches without coverage inside of 15 minutes or more its gaps (a shorter rest of one is none). The entered
    /// fields stay undisplayed.
    func testSessionsFromBothSources() {
        var nightscout = record(source: .nightscout, activatedAt: -80, to: -10, gaps: [(-50, -40)])
        nightscout.endReason = .ranEmpty
        nightscout.endReasonSource = .nightscout
        let pump = record(activatedAt: 0, to: 50, gaps: [(10, 10 + 40.0 / 60), (20, 20.1), (40, 41)], site: "abdomen")
        let sessions = Engine.sessions([nightscout, pump])
        XCTAssertEqual(sessions.map(\.id), [pump.id.uuidString, nightscout.id.uuidString])
        XCTAssertEqual(sessions.map(\.plugin), ["Medtrum", "Medtrum"])
        XCTAssertEqual(sessions.map(\.kind), [.patch, .patch])

        let session = sessions[0]
        XCTAssertEqual(session.activation, at(0))
        XCTAssertTrue(session.isActivationKnown)
        XCTAssertEqual(session.end, at(50))
        XCTAssertEqual(session.dataStart, at(0))
        XCTAssertFalse(session.isPartial)
        XCTAssertFalse(session.isOpen)
        XCTAssertEqual(session.wear, .hours(50), accuracy: accuracy)
        XCTAssertEqual(session.gaps, [
            DateInterval(start: at(10), end: at(10 + 40.0 / 60)),
            DateInterval(start: at(40), end: at(41))
        ])
        XCTAssertEqual(session.gapSeconds, .minutes(100), accuracy: accuracy)
        XCTAssertNil(session.site)
        XCTAssertNil(session.filledUnits)
        XCTAssertNil(sessions[1].endReason)
        XCTAssertEqual(sessions[1].gaps, [DateInterval(start: at(-50), end: at(-40))])
        XCTAssertEqual(sessions[1].wear, .hours(70), accuracy: accuracy)
        XCTAssertFalse(sessions[1].isPartial)

        // started within the slack of its activation (the wait for the first heartbeat): whole, no gap
        let late = Engine.sessions([record(activatedAt: 0, from: 0.2, to: 30)])
        XCTAssertFalse(late[0].isPartial)
        XCTAssertEqual(late[0].dataStart, at(0))
        XCTAssertEqual(late[0].gaps, [])

        // an Omnipod pod, a Dana site
        XCTAssertEqual(Engine.sessions(self.session(activatedAt: 0, wear: 72, plugin: "Omni")).map(\.kind), [.pod])
        XCTAssertEqual(Engine.sessions(self.session(activatedAt: 0, wear: 72, plugin: "Dana")).map(\.kind), [.site])
        XCTAssertEqual(Engine.sessions([record(nil, source: .nightscout, activatedAt: 0, to: 72)]).map(\.kind), [.site])
    }

    /// Zero-length sessions (nothing covered) are left out, of both sources; the open pump session is not (its next
    /// heartbeat extends it: the patch just changed is in use at once).
    func testZeroLengthSessionsAreLeftOut() {
        let rows = [
            record(activatedAt: 0, to: 0),
            record(source: .nightscout, activatedAt: 10, to: 10),
            record(activatedAt: 20, to: 60),
            record(activatedAt: 61, to: 61, open: true)
        ]
        let sessions = Engine.sessions(rows)
        XCTAssertEqual(sessions.map(\.activation), [at(61), at(20)])
        XCTAssertTrue(sessions[0].isOpen)
        XCTAssertEqual(sessions[0].wear, 0)
        XCTAssertEqual(Engine.inUse(sessions, deliveringPlugin: "Medtrum")?.id, rows[3].id.uuidString)
    }

    /// In use: the open pump session of the plugin delivering now; none while nothing delivers (nil), for another
    /// plugin, or with every session closed.
    func testInUseIsTheOpenSessionOfTheDeliveringPlugin() {
        let rows = session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 20, open: true)
        let sessions = Engine.sessions(rows)
        XCTAssertEqual(Engine.inUse(sessions, deliveringPlugin: "Medtrum")?.activation, at(80))
        XCTAssertNil(Engine.inUse(sessions, deliveringPlugin: nil))
        XCTAssertNil(Engine.inUse(sessions, deliveringPlugin: "Omni"))
        XCTAssertNil(Engine.inUse(Engine.sessions(session(activatedAt: 0, wear: 72)), deliveringPlugin: "Medtrum"))
        // a Nightscout session is never open; a tube pump's open site is in use while it delivers
        let site = Engine.sessions([record("Dana", activatedAt: nil, from: 0, to: 30, open: true)])
        XCTAssertEqual(Engine.inUse(site, deliveringPlugin: "Dana")?.kind, .site)
    }

    /// Without a known activation (a Nightscout piece before the first Site Change, a tube site seeded or started
    /// without its event) or started more than the slack after it (a late fallback, a pruned one): partial, its
    /// numbers from its start, its first wear days without time. Without an activation its wear counts from its start,
    /// and it pools in no wear day.
    func testPartialSessions() {
        let rows = [
            record(activatedAt: 0, from: 30, to: 70),
            record(activatedAt: 70.5, to: 100)
        ]
        let sessions = Engine.sessions(rows)
        XCTAssertEqual(sessions.count, 2)
        let partial = sessions[1]
        XCTAssertTrue(partial.isPartial)
        XCTAssertTrue(partial.isActivationKnown)
        XCTAssertEqual(partial.activation, at(0))
        XCTAssertEqual(partial.dataStart, at(30))
        XCTAssertEqual(partial.gaps, [])
        XCTAssertFalse(sessions[0].isPartial)

        let hours = Engine.hours(of: partial)
        XCTAssertEqual(hours.count, 70)
        XCTAssertEqual(hours.prefix(30).compactMap { $0 }, [])
        XCTAssertEqual(hours[30], DateInterval(start: at(30), end: at(31)))
        XCTAssertEqual(hours[69], DateInterval(start: at(69), end: at(70)))

        let result = stats([partial], rows: rows, glucose: readings(-48, 100))
        XCTAssertEqual(result[0].whole.seconds, .hours(40), accuracy: accuracy)
        XCTAssertEqual(result[0].whole.glucoseSeconds, .hours(40), accuracy: accuracy)
        XCTAssertEqual(result[0].wearDays.map(\.seconds), [0, .hours(18), .hours(22)])

        // the first Nightscout piece: no activation
        let piece = record(source: .nightscout, activatedAt: nil, from: 100, to: 140)
        let unknown = Engine.sessions([piece])[0]
        XCTAssertTrue(unknown.isPartial)
        XCTAssertFalse(unknown.isActivationKnown)
        XCTAssertEqual(unknown.activation, at(100))
        XCTAssertEqual(unknown.dataStart, at(100))
        XCTAssertEqual(unknown.wear, .hours(40), accuracy: accuracy)
        // no wear days pooled from it
        let all = Engine.sessions(rows + [piece])
        let pooled = Engine.byWearDay(stats(all, rows: rows + [piece]))
        // the 29.5 h one in Day 1 and 2, the partial one in Day 2 and 3 (its Day 1 has no time)
        XCTAssertEqual(pooled.map(\.sessions), [1, 2, 1])
    }

    /// A partial pod or patch longer than its plugin's maximum life is left out (more than one unit); a shorter one, a
    /// site (no maximum life), a whole one (its activation known, from it) and the open one stay.
    func testOverLongPartialPiecesAreLeftOut() {
        let life = Engine.maximumLife(plugin: "Medtrum")! / .hours(1)
        let rows = [
            record(source: .nightscout, activatedAt: nil, from: 0, to: life + 1),
            record(source: .nightscout, activatedAt: nil, from: 200, to: 200 + life - 1),
            record("Dana", source: .nightscout, activatedAt: nil, from: 400, to: 700),
            record(activatedAt: 800, to: 800 + life + 1),
            record("Omni", activatedAt: 1000, from: 1010, to: 1100, open: true)
        ]
        let sessions = Engine.sessions(rows)
        XCTAssertEqual(sessions.map(\.dataStart), [at(1010), at(800), at(400), at(200)])
        XCTAssertEqual(Engine.maximumLife(plugin: "Omni"), .hours(80))
        XCTAssertNil(Engine.maximumLife(plugin: "Dana"))
        XCTAssertNil(Engine.maximumLife(plugin: nil))
    }

    /// A tube site without its change (seeded: no activation) and the Nightscout site of that set change before it
    /// (ending at its start, or within 15 minutes) are one site: from the Nightscout one's start, with its activation.
    /// Another plugin's, or one ending earlier, stays apart; one imported without a pump joins.
    func testTubeSiteJoinsTheNightscoutSiteBeforeIt() {
        let seeded = record("Dana", activatedAt: nil, from: 50, to: 90, open: true)
        let before = record("Dana", source: .nightscout, activatedAt: 0, to: 49.8, gaps: [(10, 12)])
        let sessions = Engine.sessions([seeded, before])
        XCTAssertEqual(sessions.count, 1)
        let site = sessions[0]
        XCTAssertEqual(site.id, seeded.id.uuidString)
        XCTAssertEqual(site.activation, at(0))
        XCTAssertTrue(site.isActivationKnown)
        XCTAssertFalse(site.isPartial)
        XCTAssertEqual(site.end, at(90))
        XCTAssertTrue(site.isOpen)
        // its gaps: the Nightscout one's, and the time between (12 minutes: none)
        XCTAssertEqual(site.gaps, [DateInterval(start: at(10), end: at(12))])

        // 20 minutes before: apart (the seeded one partial)
        let apart = Engine.sessions([seeded, record("Dana", source: .nightscout, activatedAt: 0, to: 50 - 20.0 / 60)])
        XCTAssertEqual(apart.count, 2)
        XCTAssertTrue(apart[0].isPartial)
        XCTAssertFalse(apart[0].isActivationKnown)
        // another plugin's: apart
        XCTAssertEqual(Engine.sessions([seeded, record("Minimed", source: .nightscout, activatedAt: 0, to: 50)]).count, 2)
        // imported without a pump: joins
        let joined = Engine.sessions([seeded, record(nil, source: .nightscout, activatedAt: 1, to: 50)])
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined[0].activation, at(1))
        // a pod's seeded session has its activation: nothing joins
        XCTAssertEqual(Engine.sessions([
            record("Omni", activatedAt: 40, from: 50, to: 90, open: true),
            record("Omni", source: .nightscout, activatedAt: 0, to: 50)
        ]).count, 2)
    }

    /// A Nightscout session kept for the user's fields that overlaps another (a pump session, a rebuilt Nightscout one,
    /// an older such one) is not shown; one before the local time (ended at it) is.
    func testAnnotatedNightscoutSessionOverAnotherIsHidden() {
        let pump = record(activatedAt: 100, to: 170, open: true)
        let rebuilt = record(source: .nightscout, activatedAt: 20, to: 90)
        let overPump = record(source: .nightscout, activatedAt: 120, to: 150, site: "arm")
        let overRebuilt = record(source: .nightscout, activatedAt: 30, to: 80, site: "thigh")
        let before = record(source: .nightscout, activatedAt: -100, to: -30, site: "abdomen")
        let olderAnnotated = record(source: .nightscout, activatedAt: -60, from: -29, to: 10, site: "abdomen")
        let newerAnnotated = record(source: .nightscout, activatedAt: -10, from: -5, to: 15, site: "arm")
        let endedAtLocal = record(source: .nightscout, activatedAt: 90.5, to: 100, site: "arm")
        let sessions = Engine.sessions([
            pump, rebuilt, overPump, overRebuilt, before, olderAnnotated, newerAnnotated, endedAtLocal
        ])
        XCTAssertEqual(
            Set(sessions.map(\.id)),
            Set([pump, rebuilt, before, olderAnnotated, endedAtLocal].map(\.id.uuidString))
        )
    }

    /// The topic's naming: the current pump's kind (Patches for Medtrum, Pods for Omnipod, Sites for a tube pump),
    /// whatever the sessions are of; without a pump the newest session's. Hidden only without sessions.
    @MainActor func testNamingPerKind() {
        let sessions = Engine.sessions(session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 72, plugin: "Omni"))
        XCTAssertEqual(Engine.topic(sessions, currentPlugin: nil), PatchTopic(kind: .pod))
        XCTAssertTrue(Engine.topic(sessions, currentPlugin: nil)?.isPods == true)
        XCTAssertEqual(Engine.topic(sessions, currentPlugin: "Medtrum"), PatchTopic(kind: .patch))
        XCTAssertFalse(Engine.topic(sessions, currentPlugin: "Medtrum")?.isPods == true)
        XCTAssertEqual(Engine.topic(sessions, currentPlugin: "Dana"), PatchTopic(kind: .site))
        XCTAssertEqual(Engine.topic(sessions, currentPlugin: "Minimed"), PatchTopic(kind: .site))
        let sites = Engine.sessions([record("Dana", activatedAt: nil, from: 0, to: 40)])
        XCTAssertEqual(Engine.topic(sites, currentPlugin: nil), PatchTopic(kind: .site))
        XCTAssertNil(Engine.topic([], currentPlugin: "Medtrum"))
        XCTAssertEqual(PatchTopic(plugin: "Omni").kind, .pod)
        XCTAssertEqual(PatchTopic(plugin: "Medtrum").kind, .patch)
        XCTAssertEqual(PatchTopic(plugin: "Dana").kind, .site)
        XCTAssertEqual(PatchTopic(plugin: nil).kind, .site)

        XCTAssertEqual(Engine.wearLimit(plugin: "Omni"), .days(3))
        XCTAssertEqual(Engine.wearLimit(plugin: "Medtrum"), .days(3))
        XCTAssertNil(Engine.wearLimit(plugin: "Dana"))
        XCTAssertNil(Engine.wearLimit(plugin: nil))

        // the menu and the title
        XCTAssertFalse(StatsViewMenu.offersPatches(Engine.topic([], currentPlugin: "Dana"), shown: .insulin))
        XCTAssertTrue(StatsViewMenu.offersPatches(nil, shown: .patches))
        XCTAssertTrue(StatsViewMenu.offersPatches(Engine.topic(sites, currentPlugin: "Dana"), shown: .insulin))
        XCTAssertEqual(StatsViewMenu.title(StatsTab.patches, patches: PatchTopic(kind: .pod)), "Pods")
        XCTAssertEqual(StatsViewMenu.title(StatsTab.patches, patches: PatchTopic(kind: .patch)), "Patches")
        XCTAssertEqual(StatsViewMenu.title(StatsTab.patches, patches: PatchTopic(kind: .site)), "Sites")
        XCTAssertEqual(StatsViewMenu.title(StatsTopic.patches, patches: PatchTopic(kind: .pod)), "Pods")
        XCTAssertEqual(StatsViewMenu.title(StatsTopic.patches, patches: PatchTopic(kind: .site)), "Sites")
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches, patches: PatchTopic(kind: .pod)), "Pods")
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches, patches: PatchTopic(kind: .site)), "Sites")
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches), "Patches")
        XCTAssertEqual(Stat.RootView.patchesEmptyText(PatchTopic(kind: .site)), "No sites in this period")
        XCTAssertEqual(Stat.RootView.patchesEmptyText(PatchTopic(kind: .pod)), "No pods in this period")
        XCTAssertEqual(Stat.RootView.patchesEmptyText(nil), "No patches in this period")
    }

    /// The covered time read from the sessions (`CoreDataStorage.coverage`): `[start, lastSeen]` without the gaps, of
    /// both sources, a pump session's Nightscout prefix (before its local start) Nightscout's; clipped to the range,
    /// oldest first; nothing of a zero-length session or an empty range.
    func testCoverageFromSessions() {
        let rows = [
            record(activatedAt: -10, from: -10, to: 30, open: true, gaps: [(-2, 0), (10, 12)], localStart: 0),
            record(source: .nightscout, activatedAt: -80, to: -20, gaps: [(-50, -40)]),
            record(activatedAt: 40, to: 40)
        ]
        let all = CoreDataStorage.coverage(rows, from: at(-100), to: at(100))
        XCTAssertEqual(all.filter(\.isCovered), [
            CoveredInterval(interval: DateInterval(start: at(-80), end: at(-50)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(-40), end: at(-20)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(-10), end: at(-2)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(0), end: at(10)), source: .pump),
            CoveredInterval(interval: DateInterval(start: at(12), end: at(30)), source: .pump)
        ])
        // the local time (`PumpSessionRules.localTime`): the pump sessions' whole `[localStart, lastSeen]`, gaps and a
        // zero-length one's instant included; it fills nothing
        XCTAssertEqual(all.filter { !$0.isCovered }, [
            CoveredInterval(interval: DateInterval(start: at(0), end: at(30)), source: .pump, isCovered: false),
            CoveredInterval(interval: DateInterval(start: at(40), end: at(40)), source: .pump, isCovered: false)
        ])
        XCTAssertEqual(InsulinStatsEngine.coveredIntervals(all).reduce(0) { $0 + $1.duration }, .hours(30 + 20 + 8 + 10 + 18))
        XCTAssertEqual(CoreDataStorage.coverage(rows, from: at(-45), to: at(5)), [
            CoveredInterval(interval: DateInterval(start: at(-40), end: at(-20)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(-10), end: at(-2)), source: .nightscout),
            CoveredInterval(interval: DateInterval(start: at(0), end: at(5)), source: .pump),
            CoveredInterval(interval: DateInterval(start: at(0), end: at(5)), source: .pump, isCovered: false)
        ])
        XCTAssertEqual(CoreDataStorage.coverage(rows, from: at(5), to: at(5)), [])
        // the engine: a Nightscout event is dropped inside the pump's local time only (a gap and a zero-length session's
        // instant too); one in the prefix or after the last heartbeat counts
        let events = [-5.0, 5, 11, 30, 35, 40].map { PumpEventRecord(date: at($0), kind: .bolus, source: .nightscout, units: 1) }
        XCTAssertEqual(InsulinStatsEngine.usableEvents(events, coverage: all).map(\.date), [at(-5), at(35)])
    }

    /// The wear days go as far as the longest session (107 h: 5 days, no fixed grace row); each pools the sessions'
    /// time in it, a session at exactly 72 h has 3. The numbers: the scheduled basal by covered time, the readings by
    /// their time.
    func testWearDaysPoolBeyondThreeDays() {
        let rows = session(activatedAt: 0, wear: 107) + session(activatedAt: 108, wear: 72)
            + session(activatedAt: 181, wear: 50)
        let sessions = Engine.sessions(rows)
        XCTAssertEqual(sessions.map(\.wear), [.hours(50), .hours(72), .hours(107)])
        XCTAssertEqual(Engine.wearDayCount(sessions), 5)
        XCTAssertEqual(Engine.dayIndex(at: sessions[1].wear) + 1, 3)
        XCTAssertEqual(Engine.dayIndex(at: .hours(72)), 2)
        XCTAssertEqual(Engine.dayIndex(at: .hours(72) + 1), 3)
        XCTAssertEqual(Engine.dayIndex(at: 0), 0)

        let result = stats(sessions, rows: rows, glucose: readings(0, 240) + readings(-1, 0, mgdl: 300))
        let days = Engine.byWearDay(result)
        XCTAssertEqual(days.map(\.index), [0, 1, 2, 3, 4])
        XCTAssertEqual(days.map(\.sessions), [3, 3, 3, 1, 1])
        XCTAssertEqual(days[2].numbers.seconds, .hours(24 + 24 + 2), accuracy: accuracy)
        XCTAssertEqual(days[4].numbers.seconds, .hours(11), accuracy: accuracy)
        // 1 U/h scheduled, covered throughout: 24 U per 24 h, every day
        for day in days {
            XCTAssertEqual(day.numbers.perDay ?? 0, 24, accuracy: 1E-6, "\(day.index)")
            XCTAssertEqual(day.numbers.inRangePercent, 100, "\(day.index)")
            XCTAssertEqual(day.numbers.mean ?? 0, 120, accuracy: 1E-6, "\(day.index)")
        }
        XCTAssertEqual(days[0].numbers.basal, 72, accuracy: 1E-6)
        for (stats, total) in zip(result, [50.0, 72, 107]) {
            XCTAssertEqual(stats.whole.total, total, accuracy: 1E-6)
        }
    }

    /// The period's sessions: those overlapping it, each whole; one that ended at its start isn't.
    func testPickOverlappingTheWindow() {
        let sessions = Engine.sessions(
            session(activatedAt: 0, wear: 72) + session(activatedAt: 72, wear: 72) + session(activatedAt: 150, wear: 72)
                + session(activatedAt: 230, wear: 20)
        )
        let picked = Engine.pick(sessions, overlapping: DateInterval(start: at(144), end: at(240)))
        XCTAssertEqual(picked.map(\.activation), [at(230), at(150)])
        let wider = Engine.pick(sessions, overlapping: DateInterval(start: at(143), end: at(240)))
        XCTAssertEqual(wider.map(\.activation), [at(230), at(150), at(72)])
        XCTAssertEqual(Engine.pick(sessions, overlapping: DateInterval(start: at(300), end: at(400))), [])
    }

    /// Today: the patch in use (the open session of the plugin delivering) against the 10 before it, those worn at
    /// least its age; each counted up to that age, by wear day too.
    func testTodayAgainstPreviousAtTheSameAge() {
        // 12 sessions, 80 h apart; the newest in use, 50 h old
        let wears: [Double] = [79, 40, 79, 49.9, 79, 79, 50, 79, 79, 79, 79, 79]
        var rows: [PumpSessionValue] = []
        for (index, wear) in wears.enumerated() {
            rows += session(activatedAt: Double(index) * 80, wear: wear)
        }
        rows += session(activatedAt: 12 * 80, wear: 50, open: true)
        let sessions = Engine.sessions(rows)
        XCTAssertEqual(sessions.count, 13)

        let inUse = Engine.inUse(sessions, deliveringPlugin: "Medtrum")
        XCTAssertEqual(inUse?.activation, at(12 * 80))
        XCTAssertNil(Engine.inUse(sessions, deliveringPlugin: nil))
        XCTAssertNil(Engine.inUse(sessions, deliveringPlugin: "Dana"))

        let age: TimeInterval = .hours(50)
        let previous = Engine.previous(sessions, before: inUse!, age: age)
        // the 10 before it (indices 11 down to 2), less the 49.9 h one (index 3); the 50 h one stays
        XCTAssertEqual(previous.map(\.activation), [11, 10, 9, 8, 7, 6, 5, 4, 2].map { at(Double($0) * 80) })

        let result = stats([inUse!] + previous, rows: rows, deliveringPlugin: "Medtrum")
        XCTAssertTrue(result[0].isInUse)
        XCTAssertFalse(result.dropFirst().contains(where: \.isInUse))
        for stats in result {
            XCTAssertEqual(stats.numbers(to: age).seconds, age, accuracy: accuracy)
            XCTAssertEqual(stats.wearDays(upTo: age).map(\.seconds), [.hours(24), .hours(24), .hours(2)])
        }
        XCTAssertEqual(result[1].whole.seconds, .hours(79), accuracy: accuracy)
        // an age inside an hour: that hour prorated
        XCTAssertEqual(result[1].numbers(to: .hours(10.25)).seconds, .hours(10.25), accuracy: accuracy)
        XCTAssertEqual(result[1].numbers(to: .hours(10.25)).basal, 10.25, accuracy: 1E-6)
        let usual = Engine.byWearDay(Array(result.dropFirst()), upTo: age)
        XCTAssertEqual(usual.map(\.sessions), [9, 9, 9])
        XCTAssertEqual(usual[2].numbers.seconds, .hours(2 * 9), accuracy: accuracy)
        XCTAssertEqual(PatchNumbers.pooled(result.dropFirst().map { $0.numbers(to: age) }).total, 50 * 9, accuracy: 1E-6)
    }

    /// The numbers pool by `+`: the shares and rates are of the sums.
    func testNumbersPool() {
        var a = PatchNumbers()
        a.seconds = .hours(12)
        a.coveredSeconds = .hours(6)
        a.basal = 6
        a.bolus = 3
        a.glucoseSeconds = 100
        a.bandSeconds = [0, 0, 100, 0, 0]
        a.glucoseSum = 100 * 100
        a.glucoseSquares = 100 * 100 * 100
        var b = PatchNumbers()
        b.seconds = .hours(12)
        b.coveredSeconds = .hours(12)
        b.basal = 12
        b.smb = 2
        b.glucoseSeconds = 100
        b.bandSeconds = [0, 0, 0, 100, 0]
        b.glucoseSum = 200 * 100
        b.glucoseSquares = 200 * 200 * 100
        let pooled = a + b
        // the basal scaled by 24 h / 18 h covered
        XCTAssertEqual(pooled.scaledBasal, 18 * 24 / 18, accuracy: 1E-9)
        XCTAssertEqual(pooled.perDay ?? 0, 24 + 2 + 3, accuracy: 1E-9)
        XCTAssertEqual(pooled.inRangePercent, 50)
        XCTAssertEqual(pooled.mean ?? 0, 150, accuracy: 1E-9)
        XCTAssertEqual(pooled.cv ?? 0, 50 / 150 * 100, accuracy: 1E-9)
        XCTAssertNil(PatchNumbers().perDay)
        XCTAssertNil(PatchNumbers().inRangePercent)
    }

    /// Today's previous ones are of the plugin in use and recorded whole: a partial one and another plugin's are left
    /// out (the 10 counted among the plugin's).
    func testTodayLeavesOutPartialAndOtherPlugins() {
        // the oldest starts 10 h after its activation: partial
        var rows = [record(activatedAt: 0, from: 10, to: 79)]
        rows += session(activatedAt: 80, wear: 79, plugin: "Omni")
        rows += session(activatedAt: 160, wear: 79)
        rows += session(activatedAt: 240, wear: 30)
        let sessions = Engine.sessions(rows)
        XCTAssertTrue(sessions[3].isPartial)
        let previous = Engine.previous(sessions, before: sessions[0], age: .hours(20))
        XCTAssertEqual(previous.map(\.activation), [at(160)])
    }

    /// The hours sum to the numbers counted directly: readings straddling the hours' edges (their mean, CV and bands),
    /// IOB rows straddling them too, a temp; the whole and a wear day.
    func testHoursSumToTheDirectNumbers() {
        let rows = session(activatedAt: 0, wear: 50.5)
        let values: [Int16] = [48, 62, 95, 140, 181, 230, 260, 300, 120, 75]
        let glucose = stride(from: 2.5, to: 51 * 60, by: 5.0).enumerated().map { index, minute in
            GlucosePoint(time: at(minute / 60), mgdl: values[index % values.count])
        }
        let iob = stride(from: 3.0, to: 51 * 60, by: 7.0).enumerated().map { index, minute in
            IOBPoint(time: at(minute / 60), iob: index % 5 == 0 ? -0.3 : 0.8)
        }
        let events = [
            PumpEventRecord(date: at(5.75), kind: .tempBasal, source: .pump, units: -1, rate: 2.5, durationMin: 45.1)
        ]
        let sessions = Engine.sessions(rows)
        let summed = stats(sessions, rows: rows, events: events, iob: iob, glucose: glucose)[0]
        let direct = Engine.numbers(
            [sessions[0].dataSpan, DateInterval(start: at(24), end: at(48))],
            input: PatchInput(
                insulin: InsulinInput(events: events, coverage: StatsFixtures.covered(rows), schedules: [flatSchedule], iob: iob),
                glucose: glucose
            ),
            bands: bands,
            now: at(24 * 60),
            calendar: calendar
        )
        for (hours, counted) in [(summed.whole, direct[0]), (summed.wearDays[1], direct[1])] {
            XCTAssertEqual(hours.seconds, counted.seconds, accuracy: 1E-6)
            XCTAssertEqual(hours.basal, counted.basal, accuracy: 1E-6)
            XCTAssertEqual(hours.glucoseSeconds, counted.glucoseSeconds, accuracy: 1E-6)
            for band in 0 ..< 5 {
                XCTAssertEqual(hours.bandSeconds[band], counted.bandSeconds[band], accuracy: 1E-6)
            }
            XCTAssertEqual(hours.mean ?? 0, counted.mean ?? -1, accuracy: 1E-6)
            XCTAssertEqual(hours.cv ?? 0, counted.cv ?? -1, accuracy: 1E-6)
            XCTAssertEqual(hours.iobSeconds, counted.iobSeconds, accuracy: 1E-6)
            XCTAssertEqual(hours.negativeIOBSeconds, counted.negativeIOBSeconds, accuracy: 1E-6)
        }
        XCTAssertGreaterThan(direct[0].cv ?? 0, 10)
        XCTAssertGreaterThan(direct[0].negativeIOBSeconds, 0)
    }

    /// The boluses by kind: SMBs, the pump's boluses, External Insulin (a pen) apart; the total is the reservoir's,
    /// the insulin per 24 h has the pen's too (the Insulin tab's rule).
    func testExternalInsulinIsNotFromThePatch() {
        let rows = session(activatedAt: 0, wear: 24)
        let events = [
            PumpEventRecord(date: at(2), kind: .bolus, source: .pump, units: 5),
            PumpEventRecord(date: at(3), kind: .bolus, source: .pump, units: 0.5, isSMB: true),
            PumpEventRecord(date: at(4), kind: .bolus, source: .pump, units: 2, isExternal: true)
        ]
        let whole = stats(Engine.sessions(rows), rows: rows, events: events)[0].whole
        XCTAssertEqual(whole.bolus, 5, accuracy: 1E-9)
        XCTAssertEqual(whole.smb, 0.5, accuracy: 1E-9)
        XCTAssertEqual(whole.external, 2, accuracy: 1E-9)
        XCTAssertEqual(whole.total, 24 + 5.5, accuracy: 1E-6)
        XCTAssertEqual(whole.perDay ?? 0, 24 + 5.5 + 2, accuracy: 1E-6)
        XCTAssertEqual(whole.partsPerDay?[2] ?? 0, 7, accuracy: 1E-6)
    }

    /// The time below zero per 24 h of IOB time: 2 h of 24.
    func testNegativeIOB() {
        let rows = session(activatedAt: 0, wear: 24)
        let iob = stride(from: 0, to: 24 * 60, by: 5).map { minute in
            IOBPoint(time: at(Double(minute) / 60), iob: (120 ..< 240).contains(minute) ? -0.2 : 0.5)
        }
        let whole = stats(Engine.sessions(rows), rows: rows, iob: iob)[0].whole
        XCTAssertEqual(whole.iobSeconds, .hours(24), accuracy: 1E-6)
        XCTAssertEqual(whole.negativeIOBSeconds, .hours(2), accuracy: 1E-6)
        XCTAssertEqual(whole.negativeIOBPerDay ?? 0, .hours(2), accuracy: 1E-6)
    }

    /// A session covering a calendar day exactly: its insulin per 24 h is the Insulin tab's for the day (a temp, a
    /// bolus, an SMB, a pen's).
    func testPerDayMatchesTheInsulinTab() {
        let rows = session(activatedAt: 0, wear: 24)
        let events = [
            PumpEventRecord(date: at(6), kind: .tempBasal, source: .pump, units: -1, rate: 2, durationMin: 30.1),
            PumpEventRecord(date: at(8), kind: .bolus, source: .pump, units: 4),
            PumpEventRecord(date: at(9), kind: .bolus, source: .pump, units: 0.4, isSMB: true),
            PumpEventRecord(date: at(12), kind: .bolus, source: .pump, units: 1.5, isExternal: true)
        ]
        let input = InsulinInput(events: events, coverage: StatsFixtures.covered(rows), schedules: [flatSchedule])
        let day = InsulinStatsEngine.days(
            [DateInterval(start: at(0), end: at(24))],
            input: input,
            now: at(24 * 60),
            calendar: calendar
        )[0]
        let patch = stats(Engine.sessions(rows), rows: rows, events: events)[0]
        XCTAssertEqual(patch.wearDays.count, 1)
        XCTAssertEqual(patch.wearDays[0].perDay ?? 0, day.scaledTotal, accuracy: 1E-6)
        XCTAssertEqual(patch.wearDays[0].basal, day.basal, accuracy: 1E-6)
        XCTAssertEqual(patch.wearDays[0].basal, 24.5, accuracy: 1E-6)
    }

    /// A wear day gets a row from an hour of pooled time: a session of 72 h and a second adds no Day 4.
    func testAWearDayNeedsAnHour() {
        let rows = session(activatedAt: 0, wear: 72 + 1.0 / 3600) + session(activatedAt: 80, wear: 72)
        let result = stats(Engine.sessions(rows), rows: rows)
        XCTAssertEqual(result[1].wearDays.count, 4)
        XCTAssertEqual(Engine.byWearDay(result).map(\.index), [0, 1, 2])
        let longer = session(activatedAt: 160, wear: 73)
        let withLonger = stats(Engine.sessions(rows + longer), rows: rows + longer)
        XCTAssertEqual(Engine.byWearDay(withLonger).map(\.index), [0, 1, 2, 3])
    }

    /// The wear bars' scale: sessions worn over 14 days (a clock set back) don't set it.
    func testScaleWearIgnoresJunk() {
        let sessions = Engine.sessions(session(activatedAt: 0, wear: 107) + session(activatedAt: 200, wear: 24 * 30))
        XCTAssertEqual(Engine.scaleWear(sessions), .hours(107))
        XCTAssertEqual(Engine.scaleWear([]), 0)
    }

    /// A pod or patch worn to its maximum life without an alarm: the Nightscout evidence up to the next Site Change is a
    /// piece without an activation from its `activation + maximumLife`. Not shown (its time still covers), whatever lies
    /// between them; a piece starting later than the slack after it, of another plugin, or longer than 3 h is. An
    /// annotated row over the left-out piece only is shown.
    func testExpiryTailsAreLeftOut() {
        let pods = [
            record("Omni", source: .nightscout, activatedAt: 0, to: 80),
            record("Omni", source: .nightscout, activatedAt: nil, from: 80, to: 82),
            record("Omni", source: .nightscout, activatedAt: 82, to: 150)
        ]
        XCTAssertEqual(Engine.sessions(pods).map(\.activation), [at(82), at(0)])
        XCTAssertEqual(
            StatsFixtures.covered(pods).reduce(0) { $0 + $1.interval.duration },
            .hours(150),
            accuracy: accuracy
        )
        let patches = [
            record(source: .nightscout, activatedAt: 0, to: 120),
            record(source: .nightscout, activatedAt: nil, from: 120.1, to: 123),
            record(source: .nightscout, activatedAt: 123, to: 190)
        ]
        XCTAssertEqual(Engine.sessions(patches).map(\.activation), [at(123), at(0)])
        // 2 h after the expiry: shown
        let later = [
            record("Omni", source: .nightscout, activatedAt: 0, to: 78),
            record("Omni", source: .nightscout, activatedAt: nil, from: 82, to: 90)
        ]
        XCTAssertEqual(Engine.sessions(later).map(\.dataStart), [at(82), at(0)])
        // a site has no maximum life: nothing is a tail
        let sites = [
            record("Dana", source: .nightscout, activatedAt: 0, to: 80),
            record("Dana", source: .nightscout, activatedAt: nil, from: 80, to: 82)
        ]
        XCTAssertEqual(Engine.sessions(sites).count, 2)

        // an annotated row between the pod and its tail, a session of another pump between them: still its tail
        let between = record("Omni", source: .nightscout, activatedAt: 40, from: 40, to: 60, site: "arm", id: UUID())
        let switched = record("Dana", activatedAt: nil, from: 79.5, to: 79.9)
        XCTAssertEqual(
            Set(Engine.sessions(pods + [between, switched]).map(\.id)),
            Set([pods[0], pods[2], switched].map(\.id.uuidString))
        )
        // another plugin's unit worn to its end at the same time: not this piece's
        let otherPlugin = [
            record("Medtrum", source: .nightscout, activatedAt: 0, to: 70),
            record("Omni", source: .nightscout, activatedAt: nil, from: 120, to: 122)
        ]
        XCTAssertEqual(Engine.sessions(otherPlugin).count, 2)
        // longer than the evidence join (3 h): another unit whose Site Change is missing, shown, its activation unknown
        let missing = [
            record("Omni", source: .nightscout, activatedAt: 0, to: 80),
            record("Omni", source: .nightscout, activatedAt: nil, from: 80, to: 83.5)
        ]
        let shownMissing = Engine.sessions(missing)
        XCTAssertEqual(shownMissing.map(\.isActivationKnown), [false, true])
        XCTAssertEqual(Engine.expiryTailLimit, .hours(3))

        // the order: the tail is left out before the annotated rows are looked at
        let annotated = record("Omni", source: .nightscout, activatedAt: 80.2, from: 80.3, to: 81.5, site: "arm")
        let shown = Engine.sessions(pods + [annotated])
        XCTAssertEqual(shown.map(\.id), [pods[2], annotated, pods[0]].map(\.id.uuidString))
    }

    /// Two annotated Nightscout rows with the same start: neither is the older, both are shown.
    func testAnnotatedRowsWithTheSameStartAreBothShown() {
        let a = record(source: .nightscout, activatedAt: 0, to: 70, site: "arm", id: UUID())
        let b = record(source: .nightscout, activatedAt: 0, to: 60, site: "thigh", id: UUID())
        XCTAssertEqual(Set(Engine.sessions([a, b]).map(\.id)), [a.id.uuidString, b.id.uuidString])
    }

    /// A site of months (a tube pump's seeded or lost-event site, over `scaleWearLimit`) is listed, its wear in no wear
    /// day; the others count.
    func testASiteOfMonthsCountsNoWear() {
        let rows = [
            record("Dana", activatedAt: 0, to: 24 * 20),
            record("Dana", activatedAt: 24 * 20, to: 24 * 20 + 60)
        ]
        let sessions = Engine.sessions(rows)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.isWearCounted), [true, false])
        let days = Engine.byWearDay(stats(sessions, rows: rows))
        XCTAssertEqual(days.map(\.index), [0, 1, 2])
        XCTAssertEqual(days.map(\.sessions), [1, 1, 1])
        // a pod's or patch's wear counts however long (the scale leaves it out, `scaleWear`)
        XCTAssertTrue(Engine.sessions(session(activatedAt: 0, wear: 24 * 20)).allSatisfy(\.isWearCounted))
    }

    /// Today compares only a session with a known age and pump data (`isComparable`).
    func testComparable() {
        XCTAssertTrue(Engine.sessions(session(activatedAt: 0, wear: 10, open: true))[0].isComparable)
        let zero = Engine.sessions([record(activatedAt: 0, to: 0, open: true)])[0]
        XCTAssertEqual(zero.coveredSeconds, 0)
        XCTAssertFalse(zero.isComparable)
        XCTAssertFalse(Engine.sessions([record("Dana", activatedAt: nil, from: 0, to: 10, open: true)])[0].isComparable)
        let gapped = Engine.sessions([record(activatedAt: 0, to: 10, gaps: [(2, 4)])])[0]
        XCTAssertEqual(gapped.coveredSeconds, .hours(8), accuracy: accuracy)
    }

    /// A prune that clips the oldest session at the cutoff: its kept numbers are not reused (the session changed, and
    /// the prune's signal, widened by the service's reach, touches it), and are computed again.
    func testAPruneClipAtTheCutoffReadsTheSessionAgain() async throws {
        let rows = session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 72)
            + session(activatedAt: 160, wear: 30, open: true)
        let sessions = Engine.sessions(rows)
        let all = stats(sessions, rows: rows, deliveringPlugin: "Medtrum")
        let cutoff = at(30)
        let pruned = PumpSessionRules.prune(rows, cutoff: cutoff)
        XCTAssertEqual(pruned.clipped.map(\.id), [rows[0].id])
        let after = rows.map { row in pruned.clipped.first { $0.id == row.id } ?? row }
        let clippedSessions = Engine.sessions(after)
        XCTAssertEqual(clippedSessions[2].dataStart, cutoff)
        XCTAssertTrue(clippedSessions[2].isPartial)
        let kept = Dictionary(all.filter { !$0.isInUse }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(
            Set(Engine.reusable(kept, for: clippedSessions, inUseID: clippedSessions[0].id).keys),
            [sessions[1].id]
        )

        // through the cache: the prune's change (from the old start to the cutoff), widened by the hour
        let cache = PatchesCache()
        let key = Stat.PatchesCacheKey(bands: bands, allowOneMinuteLoop: false, generation: 0, timeZone: "Europe/Berlin")
        let keptSeen = Recorder()
        var log = Stat.PatchChangeLog(insulinSeq: 0, glucoseSeq: 0)
        _ = try await cache.stats(key: key, deliveringPlugin: "Medtrum", changes: log) { _ in all }
        log.noteInsulin(StatsChange(
            seq: 1,
            interval: DateInterval(start: at(0).addingTimeInterval(-.hours(1)), end: cutoff.addingTimeInterval(.hours(1)))
        ))
        _ = try await cache.stats(key: key, deliveringPlugin: "Medtrum", changes: log) { kept in
            await keptSeen.record(Array(kept.keys))
            return all
        }
        let seen = await keptSeen.last
        XCTAssertEqual(Set(seen), [sessions[1].id])
    }

    // MARK: - Kept numbers

    /// The kept numbers are reused for a session that is the same now and not in use; a change touches a session's data
    /// span (an hour around it), one without an interval all.
    func testReusableAndTouched() {
        let rows = session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 72)
            + session(activatedAt: 160, wear: 30, open: true)
        let sessions = Engine.sessions(rows)
        let inUseID = sessions[0].id
        let all = stats(sessions, rows: rows, deliveringPlugin: "Medtrum")
        XCTAssertEqual(all.filter(\.isInUse).map(\.id), [inUseID])
        let kept = Dictionary(all.filter { !$0.isInUse }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(Set(Engine.reusable(kept, for: sessions, inUseID: inUseID).keys), [sessions[1].id, sessions[2].id])
        // the newest one's span grew: not reused
        let grown = Engine.sessions(session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 73))
        XCTAssertEqual(Set(Engine.reusable(kept, for: grown, inUseID: nil).keys), [sessions[2].id])
        XCTAssertEqual(Engine.assembled(sessions, reused: kept, computed: [all[0]]).map(\.id), sessions.map(\.id))

        // no reach of its own: the services widen their intervals
        XCTAssertTrue(Engine.touches(nil, sessions[2]))
        XCTAssertTrue(Engine.touches(DateInterval(start: at(71.5), end: at(72.5)), sessions[2]))
        XCTAssertFalse(Engine.touches(DateInterval(start: at(72.5), end: at(73)), sessions[2]))
        XCTAssertTrue(Engine.touches(DateInterval(start: at(79), end: at(80)), sessions[1]))
        XCTAssertFalse(Engine.touches(DateInterval(start: at(78.5), end: at(79)), sessions[1]))
    }

    /// The cache: an ended session is reused while no change touches it, computed again when one does (or a change it
    /// missed, or another key); the patch in use always.
    func testCacheKeepsUntouchedSessions() async throws {
        let rows = session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 72)
            + session(activatedAt: 160, wear: 30, open: true)
        let sessions = Engine.sessions(rows)
        let inUseID = sessions[0].id
        let all = stats(sessions, rows: rows, deliveringPlugin: "Medtrum")
        XCTAssertEqual(all.filter(\.isInUse).map(\.id), [inUseID])
        let cache = PatchesCache()
        let key = Stat.PatchesCacheKey(bands: bands, allowOneMinuteLoop: false, generation: 0, timeZone: "Europe/Berlin")
        // what each computation reused (the provider's rule), and computed
        let computedIDs = Recorder()
        let compute: @Sendable([String: PatchStats]) async throws -> [PatchStats] = { kept in
            let reused = PatchStatsEngine.reusable(kept, for: sessions, inUseID: inUseID)
            let computed = all.filter { reused[$0.id] == nil }
            await computedIDs.record(computed.map(\.id))
            return PatchStatsEngine.assembled(sessions, reused: reused, computed: computed)
        }
        var log = Stat.PatchChangeLog(insulinSeq: 3, glucoseSeq: 7)

        _ = try await cache.stats(key: key, deliveringPlugin: nil, changes: log, compute: compute)
        var last = await computedIDs.last
        XCTAssertEqual(Set(last), Set(sessions.map(\.id)))
        let kept = await cache.keptIDs
        XCTAssertEqual(kept, [sessions[1].id, sessions[2].id])

        // a change in the in use one's time only: the ended ones kept
        log.noteInsulin(StatsChange(seq: 4, interval: DateInterval(start: at(180), end: at(181))))
        _ = try await cache.stats(key: key, deliveringPlugin: "x", changes: log, compute: compute)
        last = await computedIDs.last
        XCTAssertEqual(last, [inUseID])

        // a glucose change in the oldest one's time: it and the one in use
        log.noteGlucose(StatsChange(seq: 8, interval: DateInterval(start: at(10), end: at(11))))
        _ = try await cache.stats(key: key, deliveringPlugin: "y", changes: log, compute: compute)
        last = await computedIDs.last
        XCTAssertEqual(Set(last), [inUseID, sessions[2].id])

        // a change the log doesn't hold (seq 5 missing): everything
        log.noteInsulin(StatsChange(seq: 6, interval: DateInterval(start: at(180), end: at(181))))
        _ = try await cache.stats(key: key, deliveringPlugin: "z", changes: log, compute: compute)
        last = await computedIDs.last
        XCTAssertEqual(Set(last), Set(sessions.map(\.id)))

        // another key: everything
        let other = Stat.PatchesCacheKey(bands: bands, allowOneMinuteLoop: false, generation: 1, timeZone: "Europe/Berlin")
        _ = try await cache.stats(key: other, deliveringPlugin: "z", changes: log, compute: compute)
        last = await computedIDs.last
        XCTAssertEqual(Set(last), Set(sessions.map(\.id)))
    }

    /// 7–90 d: the result picks the sessions overlapping the period from every session's numbers.
    func testPeriodPickFromAllSessions() {
        let rows = session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 72) + session(activatedAt: 160, wear: 72)
        let all = stats(Engine.sessions(rows), rows: rows)
        let now = at(240)
        let result = Stat.Provider.patchesResult(all, period: .days7, currentPlugin: nil, now: now, calendar: calendar)
        let window = GlucoseStatsEngine.window(for: .days7, now: now, end: now, calendar: calendar)
        XCTAssertEqual(result.sessions.map(\.id), all.filter { $0.session.end > window.start }.map(\.id))
        XCTAssertEqual(result.scaleWear, .hours(72))
        XCTAssertNil(result.inUse)
    }

    /// The oldest schedule record keys the cache when the time before it is assumed (inside the window); runs group
    /// adjacent sessions.
    func testAssumedScheduleAndRuns() {
        let start = at(0)
        let entries = [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
        let inside = [BasalScheduleRecordValue(date: at(10), source: .nightscout, entries: entries)]
        XCTAssertNotNil(AssumedSchedule.oldest(inside, after: start))
        XCTAssertNotEqual(
            AssumedSchedule.oldest(inside, after: start),
            AssumedSchedule.oldest(
                [BasalScheduleRecordValue(
                    date: at(10),
                    source: .nightscout,
                    entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1.2)]
                )],
                after: start
            )
        )
        XCTAssertNil(AssumedSchedule.oldest([flatSchedule] + inside, after: start))
        XCTAssertNil(AssumedSchedule.oldest([], after: start))
        XCTAssertEqual(StatsIntervals.runs([0, 1, 3, 4, 5, 8]), [[0, 1], [3, 4, 5], [8]])
        XCTAssertEqual(StatsIntervals.runs([]), [])
    }

    // MARK: - The cache's concurrency

    private var cacheKey: Stat.PatchesCacheKey {
        Stat.PatchesCacheKey(bands: bands, allowOneMinuteLoop: false, generation: 0, timeZone: "Europe/Berlin")
    }

    /// Three sessions (the newest in use) and their numbers.
    private func cacheFixture() -> (sessions: [PatchSession], all: [PatchStats]) {
        let rows = session(activatedAt: 0, wear: 72) + session(activatedAt: 80, wear: 72)
            + session(activatedAt: 160, wear: 30, open: true)
        let sessions = Engine.sessions(rows)
        return (sessions, stats(sessions, rows: rows, deliveringPlugin: "Medtrum"))
    }

    /// A computation that waits at `gate`, then (with `checks`) throws when cancelled, and returns `result`.
    private func gated(
        _ gate: Gate,
        _ result: [PatchStats],
        checks: Bool = false
    ) -> @Sendable([String: PatchStats]) async throws -> [PatchStats] {
        { _ in
            await gate.wait()
            if checks {
                try Task.checkCancellation()
            }
            return result
        }
    }

    /// Lets the other tasks run until `gate` has `count` computations waiting at it.
    private func waitUntilEntered(_ gate: Gate, _ count: Int = 1) async {
        for _ in 0 ..< 100_000 {
            if await gate.entered >= count { return }
            await Task.yield()
        }
        XCTFail("the computation didn't start")
    }

    /// A change applied while a computation runs: the session it touches isn't stored from that computation.
    func testCacheDropsWhatAChangeTouchedDuringACompute() async throws {
        let (sessions, all) = cacheFixture()
        let cache = PatchesCache()
        let key = cacheKey
        var log = Stat.PatchChangeLog(insulinSeq: 0, glucoseSeq: 0)
        let first = Gate()
        let older = Task { try await cache.stats(key: key, deliveringPlugin: "a", changes: log, compute: gated(first, all)) }
        await waitUntilEntered(first)
        // a change in the oldest one's time, with a newer read
        log.noteInsulin(StatsChange(seq: 1, interval: DateInterval(start: at(10), end: at(11))))
        let second = Gate()
        let newer = Task { try await cache.stats(key: key, deliveringPlugin: "a", changes: log, compute: gated(second, all)) }
        await waitUntilEntered(second)
        await first.open()
        _ = try await older.value
        // the older one stored only what the change didn't touch
        let kept = await cache.keptIDs
        XCTAssertEqual(kept, [sessions[1].id])
        await second.open()
        _ = try await newer.value
        let keptAfter = await cache.keptIDs
        XCTAssertEqual(keptAfter, [sessions[1].id, sessions[2].id])
    }

    /// A newer computation's numbers are never replaced by an older one finishing after it.
    func testCacheNeverStoresAnOlderOverANewer() async throws {
        let (sessions, all) = cacheFixture()
        let cache = PatchesCache()
        let key = cacheKey
        let first = Gate()
        let older = Task {
            try await cache
                .stats(key: key, deliveringPlugin: "a", changes: .init(insulinSeq: 0, glucoseSeq: 0), compute: gated(first, all))
        }
        await waitUntilEntered(first)
        let second = Gate()
        // the newer one has the in use one and the middle one only
        let newerResult = Array(all.prefix(2))
        let newer = Task { try await cache.stats(
            key: key,
            deliveringPlugin: "b",
            changes: .init(insulinSeq: 0, glucoseSeq: 0),
            compute: gated(second, newerResult)
        ) }
        await waitUntilEntered(second)
        await second.open()
        _ = try await newer.value
        await first.open()
        _ = try await older.value
        let kept = await cache.keptIDs
        XCTAssertEqual(kept, [sessions[1].id])
    }

    /// The same read again while one is in flight joins it (one computation); another one cancels it, its caller gets
    /// `CancellationError`.
    func testCacheJoinsTheSameReadAndCancelsAnother() async throws {
        let (_, all) = cacheFixture()
        let cache = PatchesCache()
        let key = cacheKey
        let changes = Stat.PatchChangeLog(insulinSeq: 0, glucoseSeq: 0)
        let gate = Gate()
        let compute = gated(gate, all, checks: true)
        let first = Task { try await cache.stats(key: key, deliveringPlugin: "a", changes: changes, compute: compute) }
        await waitUntilEntered(gate)
        let joined = Task { try await cache.stats(key: key, deliveringPlugin: "a", changes: changes, compute: compute) }
        for _ in 0 ..< 1000 {
            await Task.yield()
        }
        let entered = await gate.entered
        XCTAssertEqual(entered, 1)
        await gate.open()
        let firstResult = try await first.value
        let joinedResult = try await joined.value
        XCTAssertEqual(firstResult.map(\.id), joinedResult.map(\.id))

        let blocked = Gate()
        let cancelled = Task {
            try await cache.stats(key: key, deliveringPlugin: "b", changes: changes, compute: gated(blocked, all, checks: true)) }
        await waitUntilEntered(blocked)
        let other = Gate()
        let replacing = Task {
            try await cache.stats(key: key, deliveringPlugin: "c", changes: changes, compute: gated(other, all, checks: true)) }
        await waitUntilEntered(other)
        await blocked.open()
        do {
            _ = try await cancelled.value
            XCTFail("the replaced read returned")
        } catch is CancellationError {}
        await other.open()
        let replaced = try await replacing.value
        XCTAssertEqual(replaced.count, all.count)
    }

    /// A read whose task was cancelled before it reached the cache changes nothing and computes nothing.
    func testCacheIgnoresAStaleRead() async throws {
        let (_, all) = cacheFixture()
        let cache = PatchesCache()
        let key = cacheKey
        let start = Gate()
        let compute = Gate()
        let stale = Task {
            await start.wait()
            return try await cache.stats(
                key: key,
                deliveringPlugin: "a",
                changes: .init(insulinSeq: 0, glucoseSeq: 0),
                compute: gated(compute, all)
            )
        }
        await waitUntilEntered(start)
        stale.cancel()
        await start.open()
        do {
            _ = try await stale.value
            XCTFail("the stale read returned")
        } catch is CancellationError {}
        let entered = await compute.entered
        XCTAssertEqual(entered, 0)
        let kept = await cache.keptIDs
        XCTAssertEqual(kept, [])
    }
}

/// The ids each computation computed (the cache test's).
private actor Recorder {
    private(set) var last: [String] = []

    func record(_ ids: [String]) {
        last = ids
    }
}

/// A computation's gate (the `PatchesCache` tests'): it waits until opened, counting who came.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var entered = 0

    func wait() async {
        entered += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}
