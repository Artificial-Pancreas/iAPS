@testable import FreeAPS
import SwiftUI
import XCTest

/// The Insulin and Meals topics: the topics and their views (the title menu), the content after a failed read, the
/// charts' plots and the formatting, from the engines' results (the views only lay them out).
final class InsulinMealsTabsTests: XCTestCase {
    // MARK: - Fixtures

    private static let calendar = StatsFixtures.berlin

    private var calendar: Calendar { Self.calendar }

    /// An expected string with its decimal points as the locale writes them (the amounts are formatted for the locale).
    private func d(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    /// 2026-10-10: a week without a DST change
    private static let week = StatsFixtures.week

    /// The start of the day `offset` days after `week`.
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Self.week)!
    }

    /// The local clock time of the day `offset` days after `week`.
    private func clock(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
    }

    /// 2026-10-16 12:00: the 7 days are 10–16 Oct, the 16th today
    private var now: Date { clock(6, 12) }

    private func bolus(_ date: Date, _ units: Double, smb: Bool = false) -> PumpEventRecord {
        PumpEventRecord(date: date, kind: .bolus, source: .pump, units: units, isSMB: smb)
    }

    private func coverage(_ start: Date, _ end: Date) -> CoveredInterval {
        CoveredInterval(interval: DateInterval(start: start, end: end), source: .pump)
    }

    private var flatSchedule: BasalScheduleRecordValue {
        BasalScheduleRecordValue(
            date: day(-400),
            source: .local,
            entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
        )
    }

    /// Seven days at a flat 1 U/h, a 5 U bolus at 08:00 and a 0.5 U SMB at 09:00 every day; the pump data covers every
    /// day but `uncovered` up to `now`.
    private func insulinResult(
        uncovered: Set<Int> = [],
        boluses: Bool = true,
        days: ClosedRange<Int> = 0 ... 6
    ) -> Stat.InsulinResult {
        var events: [PumpEventRecord] = []
        var rows: [CoveredInterval] = []
        for offset in days {
            if boluses, clock(offset, 9) <= now {
                events += [bolus(clock(offset, 8), 5), bolus(clock(offset, 9), 0.5, smb: true)]
            }
            if !uncovered.contains(offset) {
                rows.append(coverage(day(offset), Swift.min(day(offset + 1), now)))
            }
        }
        let input = InsulinInput(events: events, coverage: rows, schedules: [flatSchedule])
        let period = InsulinStatsEngine.period(.days7, input: input, now: now, calendar: calendar)
        return Stat.InsulinResult(period: .days7, insulin: period, calendar: calendar)
    }

    // MARK: - Tabs

    /// Insulin and Meals are topics of their own, after Glucose; Today first, then 7/14/30/90 d, 24 h shown as Today;
    /// Today mapped to 7 d (the Insulin tab's label, the Meals tab's computation).
    @MainActor func testTabsAndTheirPeriods() {
        XCTAssertEqual(
            StatsTab.allCases,
            [
                .overview, .trace, .agp, .goodBadDays, .daily, .hourOfDay, .weekday, .weekly, .insulin, .patches,
                .meals, .cgmOverview, .cgmSensors, .cgmSmoothing
            ]
        )
        XCTAssertEqual(
            StatsTab.allCases.filter { !$0.isGlucose && !$0.isCGM },
            [.insulin, .patches, .meals]
        )
        XCTAssertEqual(StatsTab.insulin.topic, .insulin)
        XCTAssertEqual(StatsTab.meals.topic, .meals)
        XCTAssertTrue(StatsTab.insulin.hasPeriodControl)
        XCTAssertTrue(StatsTab.meals.hasPeriodControl)
        XCTAssertEqual(StatsTab.insulin.validPeriods, [.today, .days7, .days14, .days30, .days90])
        XCTAssertEqual(StatsTab.meals.validPeriods, [.today, .days7, .days14, .days30, .days90])
        XCTAssertFalse(StatsTab.insulin.isGlucose)
        XCTAssertFalse(StatsTab.meals.isGlucose)
        for tab: StatsTab in [.insulin, .meals] {
            XCTAssertEqual(Stat.StateModel.nearest(.today, in: tab.validPeriods), .today)
            XCTAssertEqual(Stat.StateModel.nearest(.last24h, in: tab.validPeriods), .today)
            XCTAssertEqual(Stat.StateModel.nearest(.weeks5, in: tab.validPeriods), .days30)
            XCTAssertEqual(Stat.StateModel.nearest(.weeks13, in: tab.validPeriods), .days90)
        }
        // computed: Today (and 24 h) as 7 d, shown as Today
        XCTAssertEqual(Stat.Provider.insulinAndMealsPeriod(.today), .days7)
        XCTAssertEqual(Stat.Provider.insulinAndMealsShownPeriod(.today), .today)
        XCTAssertEqual(Stat.Provider.insulinAndMealsShownPeriod(.last24h), .today)
        XCTAssertEqual(Stat.Provider.insulinAndMealsShownPeriod(.days14), .days14)
        XCTAssertEqual(Stat.Provider.insulinAndMealsShownPeriod(.weeks5), .days30)
        // the glucose tabs keep their periods (no Today there)
        XCTAssertEqual(StatsTab.agp.validPeriods, [.days7, .days14, .days30, .days90])
        XCTAssertEqual(StatsViewMenu.title(StatsTopic.insulin), "Insulin")
        XCTAssertEqual(StatsViewMenu.title(StatsTopic.meals), "Meals")
    }

    /// Five topics, Glucose first, in the title menu: Glucose's eight views in order (under its heading), then Insulin,
    /// Patches and Meals, one view each, and CGM's four last; each view with a symbol, in its topic's list once. The title
    /// is the view shown, a glucose or CGM view after its topic.
    @MainActor func testTopicsAndTheirViews() {
        XCTAssertEqual(StatsTopic.allCases, [.glucose, .insulin, .patches, .meals, .cgm])
        XCTAssertEqual(StatsTopic.glucose.views, [.overview, .trace, .agp, .goodBadDays, .daily, .hourOfDay, .weekday, .weekly])
        XCTAssertEqual(StatsTopic.insulin.views, [.insulin])
        XCTAssertEqual(StatsTopic.patches.views, [.patches])
        XCTAssertEqual(StatsTopic.meals.views, [.meals])
        XCTAssertEqual(StatsTopic.allCases.flatMap(\.views), StatsTab.allCases)
        for tab in StatsTab.allCases {
            XCTAssertEqual(StatsTopic.allCases.filter { $0.views.contains(tab) }, [tab.topic], "\(tab)")
            XCTAssertNotNil(UIImage(systemName: StatsViewMenu.systemImage(tab)), "\(tab)")
        }
        XCTAssertEqual(
            StatsTopic.allCases.map { StatsViewMenu.title($0) },
            ["Glucose", "Insulin", "Patches", "Meals", "CGM"]
        )
        XCTAssertEqual(
            StatsTopic.glucose.views.map { StatsViewMenu.title($0) },
            ["Overview", "Day", "AGP", "Good & bad days", "In range by day", "By hour", "By weekday", "Weekly"]
        )
        XCTAssertEqual(
            StatsTab.allCases.map { StatsViewMenu.navigationTitle($0) },
            [
                "Glucose · Overview",
                "Glucose · Day",
                "Glucose · AGP",
                "Glucose · Good & bad days",
                "Glucose · In range by day",
                "Glucose · By hour",
                "Glucose · By weekday",
                "Glucose · Weekly",
                "Insulin",
                "Patches",
                "Meals",
                "CGM · Overview",
                "CGM · Sensors",
                "CGM · Smoothing"
            ]
        )
    }

    // MARK: - Patches

    /// A pump session (or a Nightscout one), `[from, to]`, closed at its end unless open; the id by its start.
    private func patchRecord(
        _ plugin: String = "Medtrum",
        source: PumpEventSource = .pump,
        activation: Date?,
        from start: Date? = nil,
        to end: Date,
        open: Bool = false
    ) -> PumpSessionValue {
        let start = start ?? activation ?? end
        let seconds = Int64(start.timeIntervalSince1970)
        return PumpSessionValue(
            id: UUID(uuidString: String(format: "00000000-0000-0000-%04ld-%012lld", Int(source.rawValue), seconds))!,
            source: source,
            plugin: plugin,
            activation: activation,
            start: start,
            localStart: source == .pump ? start : nil,
            lastSeen: end,
            end: open ? nil : end,
            flags: PumpSessionRules.isPodOrPatch(plugin) ? [] : .site
        )
    }

    /// Patches of 72 h, 80 h apart, covered throughout, from `start`.
    private func patchRows(count: Int, plugin: String = "Medtrum", start: Date) -> [PumpSessionValue] {
        (0 ..< count).map { index in
            let activation = start.addingTimeInterval(.hours(80 * Double(index)))
            return patchRecord(plugin, activation: activation, to: activation.addingTimeInterval(.hours(72)))
        }
    }

    /// Every session of the rows, none in use.
    private func patchesResult(
        _ rows: [PumpSessionValue],
        period: StatsPeriod = .days30,
        currentPlugin: String? = nil
    ) -> Stat.PatchesResult {
        let sessions = PatchStatsEngine.sessions(rows)
        let stats = PatchStatsEngine.stats(
            sessions,
            input: PatchInput(insulin: InsulinInput(coverage: StatsFixtures.covered(rows), schedules: [flatSchedule])),
            bands: StatsBands(low: 70, high: 180, units: .mgdL),
            allowOneMinuteLoop: false,
            inUseID: nil,
            now: now,
            calendar: calendar
        )
        return Stat.PatchesResult(
            period: period,
            window: GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar),
            asOf: now,
            topic: PatchStatsEngine.topic(sessions, currentPlugin: currentPlugin),
            sessions: period == .today ? [] : stats,
            inUse: nil,
            previous: [],
            scaleWear: PatchStatsEngine.scaleWear(sessions),
            recordingStart: sessions.map(\.dataStart).min()
        )
    }

    /// Patches is a topic of its own, after Insulin (Pods for Omnipod), with the Insulin tab's periods and its time in
    /// range by the bands. Its summary counts the sessions, newest first; Today
    /// without a patch in use says so.
    @MainActor func testPatchesTopic() {
        XCTAssertEqual(StatsTab.patches.topic, .patches)
        XCTAssertEqual(StatsTab.patches.validPeriods, [.today, .days7, .days14, .days30, .days90])
        XCTAssertTrue(StatsTab.patches.hasPeriodControl)
        XCTAssertTrue(StatsTab.patches.usesBands)
        XCTAssertFalse(StatsTab.patches.isGlucose)
        XCTAssertFalse(StatsTab.insulin.usesBands)
        XCTAssertTrue(StatsTab.overview.usesBands)
        XCTAssertEqual(StatsViewMenu.systemImage(.patches), "bandage")
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches, patches: PatchTopic(plugin: "Omni")), "Pods")
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches, patches: PatchTopic(plugin: "Medtrum")), "Patches")
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches, patches: PatchTopic(plugin: "Dana")), "Sites")

        let settings = Stat.StatsSettings(FreeAPSSettings())
        let start = day(-20)
        let few = Stat.Patches(patchesResult(patchRows(count: 3, start: start)), settings: settings)
        XCTAssertEqual(few.naming.title, "Patches")
        XCTAssertEqual(few.naming.byOne, "Patch by patch")
        XCTAssertEqual(few.count, "3")
        XCTAssertEqual(few.countUnit, "patches")
        XCTAssertEqual(few.countDetail, "3 ended")
        XCTAssertEqual(few.tiles.map(\.title), ["Wear time", "Per patch", "Insulin", "In range"])
        XCTAssertEqual(few.tiles[0].value, "3 d 0 h")
        XCTAssertEqual(few.tiles[1].value, "72")
        XCTAssertEqual(few.tiles[2].value, d("24.0"))
        XCTAssertEqual(
            few.wearDayNote,
            "Day 1 is the first 24 hours from activation. Each row pools the time in that day; the one in use counts in the days it has reached."
        )
        // newest first
        XCTAssertEqual(few.rows.map(\.index), [0, 1, 2])
        XCTAssertEqual(
            few.stats.map(\.session.activation),
            [2.0, 1, 0].map { start.addingTimeInterval(.hours(80 * $0)) }
        )
        XCTAssertEqual(few.rangeRows.map(\.name), ["Day 1", "Day 2", "Day 3"])
        XCTAssertEqual(few.wearDayDetail, "3 patches")
        XCTAssertEqual(
            few.detail(at: 0).facts.map(\.name),
            ["Activated", "Last delivery", "Wear time", "Grace used", "Gaps in pump data"]
        )
        XCTAssertEqual(few.detail(at: 0).facts[3].value, "none · ended at 3 d 0 h")

        let enough = Stat.Patches(patchesResult(patchRows(count: 5, start: day(-30))), settings: settings)
        XCTAssertEqual(
            enough.wearDayNote,
            "Day 1 is the first 24 hours from activation. Each row pools the time in that day; the one in use counts in the days it has reached."
        )

        let pods = Stat.Patches(patchesResult(patchRows(count: 1, plugin: "Omni", start: start)), settings: settings)
        XCTAssertEqual(pods.naming.title, "Pods")
        XCTAssertEqual(pods.countUnit, "pod")
        XCTAssertEqual(pods.naming.byOne, "Pod by pod")
        XCTAssertEqual(pods.detail(at: 0).subtitle, "Omnipod · 3 d 0 h 00 m")
        XCTAssertFalse(pods.namesKinds)

        // a tube pump's sites: no 3-day tick, no grace
        let site = patchRecord("Dana", activation: start, to: start.addingTimeInterval(.hours(60)))
        let sites = Stat.Patches(patchesResult([site], currentPlugin: "Dana"), settings: settings)
        XCTAssertEqual(sites.naming.title, "Sites")
        XCTAssertEqual(sites.countUnit, "site")
        XCTAssertEqual(sites.naming.byOne, "Site by site")
        XCTAssertEqual(sites.naming.inUse, "Site in use")
        XCTAssertEqual(sites.naming.noneInUse, "No site in use")
        XCTAssertFalse(sites.namesKinds)
        XCTAssertEqual(sites.detail(at: 0).subtitle, "Dana · 2 d 12 h 00 m")
        XCTAssertEqual(
            sites.detail(at: 0).facts.map(\.name),
            ["Activated", "Last delivery", "Wear time", "Gaps in pump data"]
        )
        XCTAssertNil(sites.rows[0].bar.limit)

        // a switch from Omnipod to Dana: each one says its kind where its pump is named
        let mixed = Stat.Patches(
            patchesResult(
                patchRows(count: 1, plugin: "Omni", start: start) + [patchRecord(
                    "Dana",
                    activation: start.addingTimeInterval(.hours(80)),
                    to: start.addingTimeInterval(.hours(140))
                )],
                currentPlugin: "Dana"
            ),
            settings: settings
        )
        XCTAssertEqual(mixed.naming.title, "Sites")
        XCTAssertTrue(mixed.namesKinds)
        XCTAssertEqual(mixed.detail(at: 0).subtitle, "Dana site · 2 d 12 h 00 m")
        XCTAssertEqual(mixed.detail(at: 1).subtitle, "Omnipod pod · 3 d 0 h 00 m")
        // only pods under the tube pump's title: they say so too
        let podsOnly = Stat.Patches(
            patchesResult(patchRows(count: 1, plugin: "Omni", start: start), currentPlugin: "Dana"),
            settings: settings
        )
        XCTAssertEqual(podsOnly.naming.title, "Sites")
        XCTAssertEqual(podsOnly.detail(at: 0).subtitle, "Omnipod pod · 3 d 0 h 00 m")

        // no activation known (the first Nightscout piece): partial, a dashed lead, no wear time
        let unknown = Stat.Patches(
            patchesResult([patchRecord(
                source: .nightscout,
                activation: nil,
                from: start,
                to: start.addingTimeInterval(.hours(40))
            )]),
            settings: settings
        )
        XCTAssertTrue(unknown.rows[0].isPartial)
        XCTAssertTrue(unknown.rows[0].bar.isStartUnknown)
        XCTAssertEqual(unknown.rows[0].bar.dataStart, 0)
        XCTAssertEqual(unknown.detail(at: 0).facts.map(\.name), [
            "Activated", "Recorded from", "Last delivery", "Wear time", "Gaps in pump data"
        ])
        XCTAssertEqual(unknown.detail(at: 0).facts[0].value, "–")
        XCTAssertEqual(unknown.tiles[0].value, "–")
        XCTAssertTrue(unknown.barNote.hasSuffix("A short dashed lead: its activation isn't known."))
        XCTAssertFalse(unknown.barNote.contains("before the recording began"))
        // no 3-day tick, no grace for it
        XCTAssertNil(unknown.rows[0].bar.limit)
        // the big bar: no day names (they count from the activation)
        let big = Stat.Patches.bar(unknown.stats[0], scale: 80, big: true)
        XCTAssertTrue(big.isBig)
        XCTAssertEqual(big.dayNames, [])
        XCTAssertEqual(
            unknown.periodNote?.contains("Other marked ones count from where their pump data starts"),
            true
        )
        XCTAssertEqual(unknown.periodNote?.contains("The pump data is recorded since"), false)

        // partial ones, per session: the oldest activated before the recording began, one in the middle recorded late
        let partials = Stat.Patches(
            patchesResult([
                patchRecord(
                    activation: start,
                    from: start.addingTimeInterval(.hours(10)),
                    to: start.addingTimeInterval(.hours(72))
                ),
                patchRecord(activation: start.addingTimeInterval(.hours(80)), to: start.addingTimeInterval(.hours(150))),
                patchRecord(
                    activation: start.addingTimeInterval(.hours(160)),
                    from: start.addingTimeInterval(.hours(170)),
                    to: start.addingTimeInterval(.hours(230))
                )
            ]),
            settings: settings
        )
        XCTAssertEqual(partials.rows.map(\.isPartial), [true, false, true])
        XCTAssertTrue(partials.barNote.hasSuffix("Dashed: before its pump data begins."))
        XCTAssertEqual(partials.periodNote?.contains("The pump data is recorded since"), true)
        XCTAssertEqual(partials.periodNote?.contains("Other marked ones"), true)

        let today = patchesResult(patchRows(count: 2, start: start), period: .today)
        XCTAssertFalse(today.isEmpty)
        let none = Stat.Patches(today, settings: settings)
        XCTAssertNotNil(none.today)
        XCTAssertNil(none.today?.inUse)
        XCTAssertEqual(none.naming.noneInUse, "No patch in use")
    }

    /// The sessions' numbers of the rows, the open one of `delivering` in use.
    private func patchStats(_ rows: [PumpSessionValue], delivering: String? = nil) -> [PatchStats] {
        let sessions = PatchStatsEngine.sessions(rows)
        return PatchStatsEngine.stats(
            sessions,
            input: PatchInput(insulin: InsulinInput(coverage: StatsFixtures.covered(rows), schedules: [flatSchedule])),
            bands: StatsBands(low: 70, high: 180, units: .mgdL),
            allowOneMinuteLoop: false,
            inUseID: PatchStatsEngine.inUse(sessions, deliveringPlugin: delivering)?.id,
            now: now,
            calendar: calendar
        )
    }

    /// Today with a patch in use: its day, so far, against the ones before it at its age (the usual's title and
    /// values, by wear day).
    @MainActor func testPatchesToday() {
        let settings = Stat.StatsSettings(FreeAPSSettings())
        let start = day(-30)
        /// - Parameters:
        ///   - wear: the one in use's, h (the ones before it are worn 72 h)
        ///   - outOfRange: the pump data stopped this long before `asOf`
        func today(previous count: Int, wear: Double = 50, outOfRange: TimeInterval = 0) -> Stat.Patches.Today.InUse? {
            var rows = patchRows(count: count, start: start)
            // the one in use: 50 h old at `asOf`, covered up to it
            let activation = start.addingTimeInterval(.hours(80 * Double(count)))
            rows.append(patchRecord(activation: activation, to: activation.addingTimeInterval(.hours(wear)), open: true))
            let result = Stat.Provider.patchesResult(
                patchStats(rows, delivering: "Medtrum"),
                period: .today,
                currentPlugin: "Medtrum",
                now: activation.addingTimeInterval(.hours(wear) + outOfRange),
                calendar: calendar
            )
            XCTAssertEqual(result.previous.count, wear <= 72 ? count : 0)
            return Stat.Patches(result, settings: settings).today?.inUse
        }

        let few = today(previous: 3)
        XCTAssertEqual(few?.dayName, "Day 3")
        XCTAssertEqual(few?.age, "2 d 2 h 00 m old")
        XCTAssertEqual(few?.usualTitle, "by 2 d 2 h · 3 before")
        XCTAssertEqual(
            few?.rows.map(\.name),
            ["Insulin", "In range", "Mean, " + settings.units.rawValue, "Negative IOB per day"]
        )
        // 1 U/h: 50 U by 50 h, this one and the usual
        XCTAssertEqual(few?.rows[0].value, d("50.0 U"))
        XCTAssertEqual(few?.usual[0], d("50.0 U"))
        XCTAssertEqual(few?.usual[1], "–")
        XCTAssertEqual(few?.days.map(\.name), ["Day 1", "Day 2", "Day 3 so far"])
        XCTAssertEqual(few?.days.map(\.perDay), [d("24.0"), d("24.0"), d("24.0")])
        XCTAssertEqual(few?.days.map(\.usualPerDay), [d("24.0"), d("24.0"), d("24.0")])
        XCTAssertEqual(few?.tiles.map(\.title), ["Expires", "Grace ends"])
        XCTAssertEqual(
            few?.note,
            "Usual: the 3 before this one, each up to the same age (2 d 2 h); one that ended sooner is left out."
        )

        let enough = today(previous: 6)
        XCTAssertEqual(enough?.usualTitle, "by 2 d 2 h · 6 before")

        // an hour out of the pump's range: compared at its covered age (50 h), its own age 51 h
        let away = today(previous: 3, outOfRange: .hours(1))
        XCTAssertEqual(away?.age, "2 d 3 h 00 m old")
        XCTAssertEqual(away?.usualTitle, "by 2 d 2 h · 3 before")
        XCTAssertEqual(away?.rows[0].value, d("50.0 U"))
        XCTAssertEqual(away?.usual[0], d("50.0 U"))

        // none before it: no comparison
        // none before it: its own numbers, no usual
        let first = today(previous: 0)
        XCTAssertEqual(first?.note, "No earlier patches to compare yet")
        XCTAssertNil(first?.usualTitle)
        XCTAssertEqual(first?.rows[0].value, d("50.0 U"))
        XCTAssertEqual(first?.usual, ["–", "–", "–", "–"])
        XCTAssertEqual(first?.days.map(\.name), ["Day 1", "Day 2", "Day 3 so far"])
        XCTAssertEqual(first?.days.map(\.usualPerDay), ["–", "–", "–"])

        // in its grace (75 h): the ones before it ended sooner, none reached this age
        let grace = today(previous: 2, wear: 75)
        XCTAssertEqual(grace?.note, "No earlier patch reached this age yet")
        XCTAssertNil(grace?.usualTitle)
        XCTAssertEqual(grace?.rows[0].value, d("75.0 U"))
        XCTAssertEqual(grace?.days.map(\.name), ["Day 1", "Day 2", "Day 3", "Day 4 so far"])
        XCTAssertEqual(grace?.usual[0], "–")
    }

    /// Today with a session in use that has no known activation (a tube site seeded without its event), or no pump
    /// data yet (an event just in): its own numbers, not compared (no usual, no wear days), the note says why; an unknown
    /// start has no day name and its age is the time recorded.
    @MainActor func testPatchesTodayNotCompared() {
        let settings = Stat.StatsSettings(FreeAPSSettings())
        let start = day(-20)
        let earlier = (0 ..< 3).map { index in
            let activation = start.addingTimeInterval(.hours(80 * Double(index)))
            return patchRecord("Dana", activation: activation, to: activation.addingTimeInterval(.hours(72)))
        }
        let from = start.addingTimeInterval(.hours(240))
        let seeded = patchRecord("Dana", activation: nil, from: from, to: from.addingTimeInterval(.hours(30)), open: true)
        let result = Stat.Provider.patchesResult(
            patchStats(earlier + [seeded], delivering: "Dana"),
            period: .today,
            currentPlugin: "Dana",
            now: from.addingTimeInterval(.hours(30)),
            calendar: calendar
        )
        XCTAssertEqual(result.previous, [])
        let unknown = Stat.Patches(result, settings: settings).today?.inUse
        XCTAssertNil(unknown?.dayName)
        XCTAssertEqual(unknown?.age, "recorded for 1 d 6 h")
        XCTAssertEqual(unknown?.since, "since " + Stat.Patches.dayAndTime(from))
        // its own column alone: the rows without a usual, no wear days
        XCTAssertEqual(unknown?.compares, false)
        XCTAssertEqual(
            unknown?.rows.map(\.name),
            ["Insulin", "In range", "Mean, " + settings.units.rawValue, "Negative IOB per day"]
        )
        XCTAssertEqual(unknown?.usual, [])
        XCTAssertEqual(unknown?.days, [])
        XCTAssertEqual(unknown?.bar.dayNames, [])
        XCTAssertNil(unknown?.usualTitle)
        XCTAssertEqual(unknown?.tiles, [])
        XCTAssertEqual(unknown?.rows.first?.value, d("30.0 U"))
        XCTAssertEqual(
            unknown?.note,
            "Its activation isn't known, so neither is its age: it isn't compared with earlier ones."
        )
        XCTAssertNil(unknown?.bar.limit)

        // a patch just changed: no pump data yet
        let patches = patchRows(count: 3, start: start)
        let changed = start.addingTimeInterval(.hours(240))
        let fresh = Stat.Provider.patchesResult(
            patchStats(patches + [patchRecord(activation: changed, to: changed, open: true)], delivering: "Medtrum"),
            period: .today,
            currentPlugin: "Medtrum",
            now: changed.addingTimeInterval(.minutes(2)),
            calendar: calendar
        )
        XCTAssertEqual(fresh.previous, [])
        let empty = Stat.Patches(fresh, settings: settings).today?.inUse
        XCTAssertEqual(empty?.dayName, "Day 1")
        XCTAssertEqual(empty?.compares, false)
        XCTAssertEqual(empty?.rows.count, 4)
        XCTAssertEqual(empty?.usual, [])
        XCTAssertEqual(empty?.days, [])
        XCTAssertEqual(empty?.note, "No pump data for it yet: it is compared with the ones before it once there is.")
    }

    /// The stats of three sessions from `start`: the oldest activated 10 h before its data, a whole one, a recorded-late
    /// one.
    @MainActor private func partialsFixture(_ start: Date) -> [PatchStats] {
        patchStats([
            patchRecord(activation: start, from: start.addingTimeInterval(.hours(10)), to: start.addingTimeInterval(.hours(72))),
            patchRecord(activation: start.addingTimeInterval(.hours(80)), to: start.addingTimeInterval(.hours(150)))
        ])
    }

    /// "Activated before the recording began" is said against the recording's start over every session read, not
    /// the period's: in 7 d the oldest one picked, recorded late, is no "recorded since" its start while older ones sit
    /// before the period.
    @MainActor func testPartialWordingAgainstTheWholeRecording() {
        let settings = Stat.StatsSettings(FreeAPSSettings())
        let late = patchRecord(activation: day(2), from: day(2).addingTimeInterval(.hours(10)), to: day(5))
        let stats = patchStats(patchRows(count: 2, start: day(-20)) + [late])
        let result = Stat.Provider.patchesResult(stats, period: .days7, currentPlugin: "Medtrum", now: now, calendar: calendar)
        XCTAssertEqual(result.sessions.map(\.session.dataStart), [day(2).addingTimeInterval(.hours(10))])
        XCTAssertEqual(result.recordingStart, day(-20))
        let patches = Stat.Patches(result, settings: settings)
        XCTAssertTrue(patches.rows[0].isPartial)
        XCTAssertEqual(patches.periodNote?.contains("The pump data is recorded since"), false)
        XCTAssertEqual(patches.periodNote?.contains("Other marked ones"), true)
        XCTAssertTrue(patches.barNote.hasSuffix("Dashed: before its pump data begins."))
        // the same session as the oldest read: activated before the recording began
        let alone = Stat.Patches(
            Stat.Provider.patchesResult(
                patchStats([late]),
                period: .days7,
                currentPlugin: "Medtrum",
                now: now,
                calendar: calendar
            ),
            settings: settings
        )
        XCTAssertEqual(alone.periodNote?.contains("The pump data is recorded since"), true)
    }

    /// The topic and the title from a read: the current pump's kind names it, the menu offers it while there is a
    /// session (or it is shown); without sessions no topic.
    @MainActor func testPatchesTopicAndTitleFlow() {
        let settings = Stat.StatsSettings(FreeAPSSettings())
        let stats = patchStats(patchRows(count: 2, start: day(-20)))
        let switched = Stat.Provider.patchesResult(stats, period: .days30, currentPlugin: "Dana", now: now, calendar: calendar)
        XCTAssertEqual(switched.topic, PatchTopic(kind: .site))
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches, patches: switched.topic), "Sites")
        XCTAssertTrue(StatsViewMenu.offersPatches(switched.topic, shown: .insulin))
        XCTAssertEqual(Stat.Patches(switched, settings: settings).naming.title, "Sites")
        let noPump = Stat.Provider.patchesResult(stats, period: .days30, currentPlugin: nil, now: now, calendar: calendar)
        XCTAssertEqual(StatsViewMenu.navigationTitle(.patches, patches: noPump.topic), "Patches")
        let none = Stat.Provider.patchesResult([], period: .days30, currentPlugin: "Omni", now: now, calendar: calendar)
        XCTAssertNil(none.topic)
        XCTAssertFalse(StatsViewMenu.offersPatches(none.topic, shown: .insulin))
        XCTAssertTrue(StatsViewMenu.offersPatches(none.topic, shown: .patches))
        XCTAssertEqual(Stat.RootView.patchesEmptyText(none.topic), "No patches in this period")
    }

    /// The durations to the minute and to the hour, rounded; a time relative to now.
    @MainActor func testPatchesFormatting() {
        typealias Patches = Stat.Patches
        XCTAssertEqual(Patches.duration(0), "0 m")
        XCTAssertEqual(Patches.duration(.minutes(25)), "25 m")
        XCTAssertEqual(Patches.duration(.minutes(7 * 60 + 5)), "7 h 05 m")
        XCTAssertEqual(Patches.duration(.days(3) + .hours(7) + .minutes(15)), "3 d 7 h 15 m")
        // 3 d 23 h 59 m 40 s rounds to 4 d
        XCTAssertEqual(Patches.duration(.days(4) - 20), "4 d 0 h 00 m")
        XCTAssertEqual(Patches.hours(.minutes(89)), "1 h")
        XCTAssertEqual(Patches.hours(.minutes(90)), "2 h")
        XCTAssertEqual(Patches.hours(.minutes(23 * 60 + 40)), "1 d 0 h")
        XCTAssertEqual(Patches.hours(.days(3) + .hours(7)), "3 d 7 h")

        let now = clock(6, 12)
        XCTAssertEqual(Patches.relative(clock(6, 17, 5), now: now, calendar: calendar), "today · in 5 h 05 m")
        XCTAssertEqual(Patches.relative(clock(7, 9), now: now, calendar: calendar), "tomorrow · in 21 h 00 m")
        XCTAssertEqual(Patches.relative(clock(6, 10), now: now, calendar: calendar), "today · 2 h 00 m ago")
        let later = clock(9, 12)
        XCTAssertEqual(
            Patches.relative(later, now: now, calendar: calendar),
            later.formatted(.dateTime.weekday(.abbreviated)) + " · in 3 d 0 h 00 m"
        )
    }

    /// The wear bars: the scale (the longest wear up to 14 days, at least the limit and its grace), the recording's
    /// start, the tick, the rest of the one in use outlined.
    @MainActor func testPatchesWearBar() {
        typealias Patches = Stat.Patches
        XCTAssertEqual(Patches.barScale(longestWear: .hours(107), plugins: ["Medtrum"]), 107)
        XCTAssertEqual(Patches.barScale(longestWear: .hours(50), plugins: ["Medtrum"]), 80)
        XCTAssertEqual(Patches.barScale(longestWear: .hours(10), plugins: ["Dana"]), 24)
        let junk = PatchStatsEngine.sessions(
            patchRows(count: 1, start: day(-30))
                + [patchRecord(activation: day(-25), to: day(-25).addingTimeInterval(.days(20)))]
        )
        XCTAssertEqual(PatchStatsEngine.scaleWear(junk), .hours(72))

        let start = day(-20)
        let activation = start.addingTimeInterval(.hours(80))
        let rows = [
            // activated 10 h before its data began
            patchRecord(
                activation: start,
                from: start.addingTimeInterval(.hours(10)),
                to: start.addingTimeInterval(.hours(72))
            ),
            patchRecord(activation: activation, to: activation.addingTimeInterval(.hours(30)), open: true)
        ]
        let stats = patchStats(rows, delivering: "Medtrum")
        let partial = Patches.bar(stats[1], scale: 80, big: true)
        XCTAssertEqual(partial.dataStart, 10, accuracy: 1E-9)
        XCTAssertEqual(partial.wear, 72, accuracy: 1E-9)
        XCTAssertEqual(partial.limit, 72)
        XCTAssertNil(partial.restEnd)
        XCTAssertEqual(partial.dayNames, ["Day 1", "Day 2", "Day 3", "Day 4"])
        let inUse = Patches.bar(stats[0], scale: 107, big: false, age: .hours(31))
        XCTAssertTrue(inUse.isInUse)
        XCTAssertEqual(inUse.dataStart, 0)
        XCTAssertEqual(inUse.wear, 31, accuracy: 1E-9)
        XCTAssertEqual(inUse.restEnd, 80)
        XCTAssertEqual(inUse.dayNames, [])
    }

    /// The pushed detail follows its session by id: at its index, the previous content's while reading (waiting
    /// without it), gone (the detail pops) when a refresh drops it or nothing is shown.
    @MainActor func testPatchDetailByID() {
        typealias Patches = Stat.Patches
        let settings = Stat.StatsSettings(FreeAPSSettings())
        let three = Patches(patchesResult(patchRows(count: 3, start: day(-20))), settings: settings)
        let two = Patches(patchesResult(patchRows(count: 2, start: day(-20))), settings: settings)
        let oldest = three.stats[2].id
        XCTAssertEqual(Patches.detailPlace(of: oldest, in: .loaded(three)), .index(2))
        XCTAssertEqual(Patches.detailPlace(of: three.stats[0].id, in: .loaded(three)), .index(0))
        // a refresh dropped the newest: gone; the others moved
        XCTAssertEqual(Patches.detailPlace(of: three.stats[0].id, in: .loaded(two)), .gone)
        XCTAssertEqual(Patches.detailPlace(of: oldest, in: .loaded(two)), .index(1))
        XCTAssertEqual(Patches.detailPlace(of: oldest, in: .loading(previous: three)), .index(2))
        XCTAssertEqual(Patches.detailPlace(of: three.stats[0].id, in: .loading(previous: two)), .waiting)
        XCTAssertEqual(Patches.detailPlace(of: oldest, in: .loading(previous: nil)), .waiting)
        XCTAssertEqual(Patches.detailPlace(of: oldest, in: .empty), .gone)
        XCTAssertEqual(Patches.detailPlace(of: oldest, in: .failed), .gone)
    }

    /// External Insulin in a session: out of its total ("Per patch", the detail's), on a line of its own, in the
    /// insulin per 24 h.
    @MainActor func testPatchesExternalInsulin() {
        let rows = patchRows(count: 1, start: day(-20))
        let activation = day(-20)
        let events = [
            PumpEventRecord(date: activation.addingTimeInterval(.hours(2)), kind: .bolus, source: .pump, units: 4),
            PumpEventRecord(
                date: activation.addingTimeInterval(.hours(3)),
                kind: .bolus,
                source: .pump,
                units: 2,
                isExternal: true
            )
        ]
        let sessions = PatchStatsEngine.sessions(rows)
        let stats = PatchStatsEngine.stats(
            sessions,
            input: PatchInput(insulin: InsulinInput(
                events: events,
                coverage: StatsFixtures.covered(rows),
                schedules: [flatSchedule]
            )),
            bands: StatsBands(low: 70, high: 180, units: .mgdL),
            allowOneMinuteLoop: false,
            inUseID: nil,
            now: now,
            calendar: calendar
        )
        let patches = Stat.Patches(
            Stat.Provider.patchesResult(stats, period: .days30, currentPlugin: nil, now: now, calendar: calendar),
            settings: Stat.StatsSettings(FreeAPSSettings())
        )
        XCTAssertEqual(patches.tiles[1].value, "76")
        let detail = patches.detail(at: 0)
        XCTAssertEqual(detail.total, d("76.0"))
        XCTAssertEqual(detail.external, d("+ 2.0 U pen, not from the patch"))
        XCTAssertEqual(detail.perDay, d("26.0 U per day"))
    }

    // MARK: - A failed read

    /// The content on screen stays when it is the request's own; nothing of another period is shown as the request's.
    func testAFailedReadKeepsOnlyTheRequestsOwnContent() {
        typealias Content = Stat.ViewContent<Int>
        let samePeriod: (Int) -> Bool = { $0 == 7 }
        // a live update's (in place)
        XCTAssertEqual(Content.loaded(7).keepingPrevious(isCurrent: samePeriod), .loaded(7))
        // dimmed while the same period was read again: shown again, not dimmed
        XCTAssertEqual(Content.loading(previous: 7).keepingPrevious(isCurrent: samePeriod), .loaded(7))
        // another period's dimmed: not shown as this one's
        XCTAssertEqual(Content.loading(previous: 14).keepingPrevious(isCurrent: samePeriod), .failed)
        // the first read
        XCTAssertEqual(Content.loading(previous: nil).keepingPrevious(isCurrent: samePeriod), .failed)
        XCTAssertEqual(Content.empty.keepingPrevious(isCurrent: samePeriod), .empty)
        XCTAssertEqual(Content.failed.keepingPrevious(isCurrent: samePeriod), .failed)
        XCTAssertNil(Content.failed.value)
        XCTAssertFalse(Content.failed.isLoading)
    }

    // MARK: - Plots

    func testBarAxisLevels() {
        XCTAssertEqual(StatsBarAxis.levels(maximum: 0, unit: 15, divisions: 3), [0, 5, 10, 15])
        XCTAssertEqual(StatsBarAxis.levels(maximum: 38.2, unit: 15, divisions: 3), [0, 15, 30, 45])
        XCTAssertEqual(StatsBarAxis.levels(maximum: 45, unit: 15, divisions: 3), [0, 15, 30, 45])
        XCTAssertEqual(StatsBarAxis.levels(maximum: 145, unit: 60, divisions: 3), [0, 60, 120, 180])
        XCTAssertEqual(StatsBarAxis.levels(maximum: 0.71, unit: 0.5, divisions: 2), [0, 0.5, 1])
        XCTAssertEqual(StatsBarAxis.levels(maximum: -3, unit: 10, divisions: 2), [0, 5, 10])
    }

    /// The nonzero values stacked in order; the dot only on a day with a bar.
    func testDayBarsStackTheNonzeroParts() {
        let days = (0 ..< 3).map { DateInterval(start: day($0), end: day($0 + 1)) }
        let style = StatsBarStyle(fill: .blue)
        let plot = StatsDayBars.Plot(
            days: days,
            labels: [],
            values: [[10, 0, 5], [], [0, 0, 0]],
            styles: [style, style, style],
            marked: [true, true, false],
            levels: [0, 5, 10, 15],
            levelLabels: [],
            average: 7.5
        )
        XCTAssertEqual(plot.domain, DateInterval(start: day(0), end: day(3)))
        XCTAssertEqual(plot.parts.map(\.series), [0, 2])
        XCTAssertEqual(plot.parts.map(\.lower), [0, 10])
        XCTAssertEqual(plot.parts.map(\.upper), [10, 15])
        XCTAssertEqual(plot.days.map(\.top), [15, 0, 0])
        XCTAssertEqual(plot.days.map(\.isMarked), [true, false, false])
        XCTAssertEqual(plot.axisTop, 15)
        XCTAssertEqual(plot.index(containing: day(1).addingTimeInterval(60)), 1)
    }

    /// One run per stretch of hours with a level, each hour from its start to its end.
    func testHourStepLineRuns() {
        let points = StatsHourBars.Plot.stepPoints([0.8, 0.8, nil, 1.0])
        XCTAssertEqual(points.map(\.x), [0, 1, 1, 2, 3, 4])
        XCTAssertEqual(points.map(\.y), [0.8, 0.8, 0.8, 0.8, 1.0, 1.0])
        XCTAssertEqual(points.map(\.run), [0, 0, 0, 0, 1, 1])
        let style = StatsBarStyle(fill: .blue)
        let parts = StatsHourBars.Plot.stacked([[0.5, 0.25, 0], [0, 0, 0.2]], styles: [style, style, style])
        XCTAssertEqual(parts.map(\.hour), [0, 0, 1])
        XCTAssertEqual(parts.map(\.series), [0, 1, 2])
        XCTAssertEqual(parts.map(\.lower), [0, 0.5, 0])
        XCTAssertEqual(parts.map(\.upper), [0.5, 0.75, 0.2])
    }

    /// Basal vs scheduled: from 100% up or down, a symmetric scale in steps of 25 points up to 100.
    func testBasalVsScheduledScale() {
        XCTAssertEqual(Stat.Insulin.vsSpan([]), 25)
        XCTAssertEqual(Stat.Insulin.vsSpan([101, 92]), 25)
        XCTAssertEqual(Stat.Insulin.vsSpan([126]), 50)
        XCTAssertEqual(Stat.Insulin.vsSpan([20]), 100)
        XCTAssertEqual(Stat.Insulin.vsSpan([340]), 100)

        func hour(_ hour: Int, _ share: Double?) -> InsulinHourSummary {
            InsulinHourSummary(
                hour: hour,
                days: 6,
                coveredHours: 6,
                basal: 1,
                scheduled: 1,
                zeroBasalSeconds: 0,
                smb: 0,
                bolus: 0,
                basalVsScheduled: share
            )
        }
        let plot = Stat.Insulin.vsPlot([hour(0, 1.2), hour(1, 1), hour(2, 0.7), hour(3, nil), hour(4, 2.6)])
        XCTAssertEqual(plot.yDomain, 0 ... 200)
        XCTAssertEqual(plot.levelLabels, ["0%", "100%", "200%"])
        XCTAssertEqual(plot.baseline, 100)
        // at 100% and without a schedule: no bar; 260% drawn at the edge
        XCTAssertEqual(plot.parts.map(\.hour), [0, 2, 4])
        XCTAssertEqual(plot.parts.map(\.lower), [100, 70, 100])
        XCTAssertEqual(plot.parts.map(\.upper), [120, 100, 200])
        XCTAssertEqual(plot.parts.map(\.style), [
            Stat.Insulin.moreThanScheduled,
            Stat.Insulin.lessThanScheduled,
            Stat.Insulin.moreThanScheduled
        ])
    }

    // MARK: - Insulin

    /// Six complete days, every one covered: the TDD over them (rule a), today not in it but shown "so far".
    @MainActor func testInsulinFormattingOfCompleteDays() {
        let result = insulinResult()
        let insulin = Stat.Insulin(result)
        let summary = result.insulin.summary
        XCTAssertEqual(summary.headlineDays, 6)
        XCTAssertFalse(summary.isLimited)

        XCTAssertEqual(insulin.period, .days7)
        XCTAssertEqual(insulin.tdd, d("29.5"))
        XCTAssertFalse(insulin.needsCompleteDay)
        XCTAssertNil(insulin.limitedNote)
        XCTAssertEqual(insulin.daysWithData, "Days with pump data 7 of 7")
        XCTAssertEqual(insulin.rows.map(\.value), [d("24.0 U"), d("0.5 U"), d("5.0 U")])
        // 81.4 / 1.7 / 16.9 by largest remainder
        XCTAssertEqual(insulin.rows.map(\.percent), ["81%", "2%", "17%"])
        XCTAssertEqual(insulin.split.map(\.id), [0, 1, 2])
        XCTAssertEqual(insulin.basalVsScheduled, "100%")
        XCTAssertEqual(insulin.scheduled, d("24.0"))
        XCTAssertEqual(insulin.zeroBasal, "0 m")
        // no IOB rows
        XCTAssertEqual(insulin.negativeCard.headline, "–")
        XCTAssertNil(insulin.profileAssumedNote)

        // the day chart: every day's bar, the TDD as the average, no dot
        XCTAssertEqual(insulin.dayPlot.days.count, 7)
        XCTAssertEqual(insulin.dayPlot.days.map(\.top).prefix(6), Array(repeating: 29.5, count: 6)[...])
        XCTAssertEqual(insulin.dayPlot.average, 29.5)
        XCTAssertEqual(insulin.dayPlot.levels, [0, 10, 20, 30])
        XCTAssertEqual(insulin.dayPlot.levelLabels, ["0 U", "10", "20", "30"])
        XCTAssertFalse(insulin.dayPlot.days.contains(where: \.isMarked))
        XCTAssertEqual(insulin.dayLegend.map(\.title), ["Basal", "SMB", "Bolus", d("Average 29.5 U")])

        // today: so far, not in the average, no notes
        let today = insulin.card(at: 6)
        XCTAssertEqual(today.title, "Today")
        XCTAssertTrue(today.soFar)
        XCTAssertEqual(today.total, d("17.5"))
        XCTAssertEqual(today.notes, [])
        XCTAssertEqual(today.rows.map(\.value), [d("12.0 U"), d("0.5 U"), d("5.0 U")])
        let past = insulin.card(at: 2)
        XCTAssertFalse(past.soFar)
        XCTAssertEqual(past.total, d("29.5"))
        XCTAssertEqual(past.vsScheduled, "100%")
        XCTAssertEqual(past.notes, [])
        XCTAssertFalse(past.profileAssumed)

        // by hour: the 6 complete days; 08:00 has the bolus, every hour 1 U/h scheduled
        let eight = insulin.hourReadouts[8]
        XCTAssertEqual(eight.subtitle, "6 days · 6 hours of data")
        XCTAssertEqual(eight.rows.map(\.value), [d("1.00 U"), d("1.00 U"), d("0.00 U"), d("5.00 U"), d("6.00 U")])
        XCTAssertEqual(eight.vsScheduled, "100%")
        XCTAssertEqual(insulin.hourPlot.levels, [0, 3, 6])
        XCTAssertEqual(insulin.hourPlot.steps.count, 48)
        XCTAssertEqual(insulin.vsPlot.parts, [])
    }

    /// A day without pump coverage but with boluses: its basal unknown ("–", no basal in its bar), the day marked
    /// partial and out of the average; the headline limited (a mark, the count in the header).
    @MainActor func testInsulinFormattingOfALimitedPeriod() {
        let result = insulinResult(uncovered: [2])
        let insulin = Stat.Insulin(result)
        XCTAssertEqual(result.insulin.summary.headlineDays, 5)
        XCTAssertTrue(result.insulin.summary.isLimited)
        XCTAssertNotNil(insulin.limitedNote)
        XCTAssertEqual(insulin.tdd, d("29.5"))
        XCTAssertFalse(insulin.limitedNote!.contains("5"), "no counts in the note")

        // its bar: the boluses only, with the dot
        XCTAssertEqual(insulin.dayPlot.days[2].top, 5.5)
        XCTAssertTrue(insulin.dayPlot.days[2].isMarked)
        XCTAssertEqual(insulin.dayLegend.last?.title, "Partial pump data")
        let card = insulin.card(at: 2)
        XCTAssertTrue(card.hasData)
        XCTAssertEqual(card.total, "–")
        XCTAssertEqual(card.rows.map(\.value), ["–", d("0.5 U"), d("5.0 U")])
        XCTAssertEqual(card.rows.map(\.percent), ["–", "–", "–"])
        XCTAssertEqual(card.split, [])
        XCTAssertEqual(card.notes, ["Pump data for 0 m of 24 h", "Not in the average"])
        XCTAssertEqual(card.vsScheduled, "–")
        XCTAssertEqual(card.zeroBasal, "–")
        XCTAssertTrue(Stat.Insulin.isPartial(result.insulin.days[2]))
        XCTAssertEqual(Stat.Insulin.dayValues(result.insulin.days[2]), [0, 0.5, 5])
        XCTAssertFalse(Stat.Insulin.isPartial(result.insulin.days[6]), "today is never partial")
    }

    /// A temp on a day without coverage counts as delivered insulin in the engine, but the day's basal is unknown (no
    /// scheduled fill around it): neither its bar nor its card shows a basal.
    @MainActor func testATempOutsideCoverageIsNoBasalOfTheDay() {
        let base = insulinResult(uncovered: [2])
        var events = [bolus(clock(2, 8), 5)]
        events.append(PumpEventRecord(date: clock(2, 10), kind: .tempBasal, source: .pump, units: -1, rate: 2, durationMin: 30.1))
        let input = InsulinInput(events: events, coverage: [], schedules: [flatSchedule])
        let day = InsulinStatsEngine.days([base.insulin.days[2].day], input: input, now: now, calendar: calendar)[0]
        XCTAssertGreaterThan(day.basal, 0)
        XCTAssertEqual(day.coveredSeconds, 0)
        XCTAssertEqual(Stat.Insulin.dayValues(day), [0, 0, 5])
        let result = Stat.InsulinResult(
            period: .days7,
            insulin: InsulinPeriod(summary: base.insulin.summary, days: [day], hours: base.insulin.hours),
            calendar: calendar
        )
        let insulin = Stat.Insulin(result)
        XCTAssertEqual(insulin.dayPlot.days[0].top, 5)
        XCTAssertEqual(insulin.card(at: 0).rows.map(\.value), ["–", d("0.0 U"), d("5.0 U")])
        XCTAssertEqual(insulin.card(at: 0).total, "–")
    }

    /// Only today has pump data (rule a): "–" with "Needs one complete day", no mark; the days before without data
    /// show "No pump data".
    @MainActor func testInsulinWithoutACompleteDay() {
        let result = insulinResult(uncovered: [0, 1, 2, 3, 4, 5], boluses: true, days: 6 ... 6)
        let insulin = Stat.Insulin(result)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(insulin.needsCompleteDay)
        XCTAssertEqual(insulin.tdd, "–")
        XCTAssertNil(insulin.limitedNote)
        XCTAssertEqual(insulin.rows.map(\.value), ["–", "–", "–"])
        XCTAssertEqual(insulin.rows.map(\.percent), ["–", "–", "–"])
        XCTAssertEqual(insulin.split, [])
        XCTAssertNil(insulin.dayPlot.average)
        XCTAssertEqual(insulin.dayLegend.map(\.title), ["Basal", "SMB", "Bolus"])
        let empty = insulin.card(at: 0)
        XCTAssertFalse(empty.hasData)
        XCTAssertEqual(insulin.card(at: 6).total, d("17.5"))
    }

    // MARK: - Meals

    /// Two entries (08:00 40 g, 13:00 60 g) on every complete day but `skipped`, one of them with fat and protein when
    /// `fat`; today 30 g at 08:00.
    private func mealsResult(fat: Bool = true, skipped: Set<Int> = [3]) -> Stat.MealsResult {
        var points: [MealPoint] = []
        for offset in 0 ... 5 where !skipped.contains(offset) {
            points.append(MealPoint(id: "b\(offset)", actualDate: clock(offset, 8, 10), carbs: 40))
            let withFat = fat && offset == 1
            points.append(MealPoint(
                id: "l\(offset)",
                actualDate: clock(offset, 13, 5),
                carbs: 60,
                fat: withFat ? 20 : 0,
                protein: withFat ? 30 : 0
            ))
        }
        points.append(MealPoint(id: "t", actualDate: clock(6, 8), carbs: 30))
        return Stat.Provider.mealsResult(points, period: .days7, factor: 0.5, now: now, calendar: calendar)
    }

    /// The averages over the complete days with entries, the count in the header and the mark (no counts) when not
    /// every complete day has entries; fat, protein and the equivalents for someone who logs them.
    @MainActor func testMealsFormatting() {
        let result = mealsResult()
        let meals = Stat.Meals(result)
        XCTAssertEqual(result.meals.summary.daysWithEntries, 5)
        XCTAssertEqual(meals.period, .days7)
        XCTAssertEqual(meals.carbs, "100")
        XCTAssertEqual(meals.daysWithEntries, "Days with entries 5 of 6")
        XCTAssertNotNil(meals.limitedNote)
        XCTAssertFalse(meals.limitedNote!.contains("5"), "no counts in the note")
        XCTAssertTrue(meals.logsFatOrProtein)
        XCTAssertEqual(meals.tiles.map(\.title), ["Entries", "Per entry", "Fat", "Protein", "Carb equivalents"])
        // 10 entries over 5 days, 500 g; fat 20 g, protein 30 g, equivalents (4 × 30 + 9 × 20) / 10 × 0.5 = 15 g
        XCTAssertEqual(meals.tiles.map(\.value), [d("2.0"), "50", "4", "6", "3"])

        // the day chart: carbs and equivalents stacked, the average, the axis in 60 g
        XCTAssertEqual(meals.dayPlot.days[1].top, 115)
        XCTAssertEqual(meals.dayPlot.parts.filter { $0.day == day(1) }.map(\.series), [0, 1])
        XCTAssertEqual(meals.dayPlot.average, 100)
        XCTAssertEqual(meals.dayPlot.levels, [0, 40, 80, 120])
        XCTAssertEqual(meals.dayPlot.levelLabels, ["0 g", "40", "80", "120"])
        XCTAssertEqual(meals.dayLegend.map(\.title), ["Carbs", "Carb equivalents", "Average 100 g"])

        // a day with fat and protein
        let withFat = meals.card(at: 1)
        XCTAssertEqual(withFat.carbs, "100")
        XCTAssertEqual(withFat.entryCount, "2 entries")
        XCTAssertEqual(withFat.entries.map(\.carbs), ["40 g", "60 g"])
        XCTAssertEqual(withFat.entries.map(\.detail), [nil, "fat 20 g · protein 30 g"])
        XCTAssertEqual(withFat.carbEquivalents, "15 g")
        // a day without entries
        let skipped = meals.card(at: 3)
        XCTAssertNil(skipped.entryCount)
        XCTAssertEqual(skipped.entries, [])
        // today, so far
        let today = meals.card(at: 6)
        XCTAssertEqual(today.title, "Today")
        XCTAssertTrue(today.soFar)
        XCTAssertEqual(today.carbs, "30")
        XCTAssertEqual(today.entryCount, "1 entry")

        // by time of day: over the 5 days with entries, today not in it
        let lunch = meals.hourReadouts[13]
        XCTAssertEqual(lunch.subtitle, "5 days")
        XCTAssertEqual(lunch.rows.map(\.value), ["60 g per day", "on 5 of 5 days", "60 g", "60%"])
        XCTAssertEqual(meals.hourReadouts[3].rows.map(\.value), ["0 g", "on 0 of 5 days", "–", "0%"])
        XCTAssertEqual(meals.hourPlot.levels, [0, 30, 60])
        XCTAssertEqual(meals.hourPlot.levelLabels, ["0 g", "30 g", "60 g"])
        XCTAssertEqual(meals.topHours.map(\.hour), [13, 8])
        XCTAssertEqual(meals.topHours.map(\.percent), ["60%", "40%"])
        XCTAssertEqual(
            meals.topHours.map(\.subtitle),
            ["entries on 5 of 5 days · 60 g each", "entries on 5 of 5 days · 40 g each"]
        )
    }

    /// Someone who doesn't log fat or protein (D6): no fat, protein or equivalent tiles, no equivalents in the chart,
    /// the day card or the entries; every complete day with entries: no mark.
    @MainActor func testMealsWithoutFatOrProtein() {
        let meals = Stat.Meals(mealsResult(fat: false, skipped: []))
        XCTAssertFalse(meals.logsFatOrProtein)
        XCTAssertNil(meals.limitedNote)
        XCTAssertEqual(meals.tiles.map(\.title), ["Entries", "Per entry"])
        XCTAssertEqual(meals.dayPlot.parts.map(\.series).filter { $0 == 1 }, [])
        XCTAssertEqual(meals.dayLegend.map(\.title), ["Carbs", "Average 100 g"])
        let card = meals.card(at: 1)
        XCTAssertNil(card.carbEquivalents)
        XCTAssertEqual(card.entries.map(\.detail), [nil, nil])
    }

    /// Entries only today: "–" with "No entries on a complete day yet", no mark, no average; the hours count nothing.
    @MainActor func testMealsOnlyToday() {
        let meals = Stat.Meals(mealsResult(fat: false, skipped: [0, 1, 2, 3, 4, 5]))
        XCTAssertTrue(meals.needsCompleteDay)
        XCTAssertEqual(meals.carbs, "–")
        XCTAssertNil(meals.limitedNote)
        XCTAssertEqual(meals.hourReadouts[8].subtitle, "No entries on a complete day yet")
        XCTAssertEqual(meals.hourReadouts[8].rows[1].value, "–")
        XCTAssertNil(meals.dayPlot.average)
        XCTAssertEqual(meals.topHours, [])
        XCTAssertEqual(Stat.Meals.entryCount(1), "1 entry")
        XCTAssertEqual(Stat.Meals.entryCount(3), "3 entries")
        XCTAssertEqual(StatsAmount.grams(12.5), d("12.5 g"))
        XCTAssertEqual(StatsAmount.grams(12), "12 g")
    }

    /// One day averaged: "1 day", never "1 days"; none: no "0 days · 0 hours".
    @MainActor func testOneDayAndNoDayAreSaidSo() {
        XCTAssertEqual(Stat.Insulin.hourDataNote(hours: 6, days: 6), "6 days · 6 hours of data")
        XCTAssertEqual(Stat.Insulin.hourDataNote(hours: 3, days: 1), "1 day · 3 hours of data")
        XCTAssertEqual(Stat.Insulin.hourDataNote(hours: 1, days: 1), "1 day · 1 hour of data")
        XCTAssertEqual(Stat.Insulin.hourDataNote(hours: 0.4, days: 1), "1 day · less than 1 hour of data")
        XCTAssertEqual(Stat.Insulin.hourDataNote(hours: 0, days: 0), "Needs one complete day")
        XCTAssertEqual(Stat.Meals.hourDays(0), "No entries on a complete day yet")
        XCTAssertEqual(Stat.Meals.hourDays(1), "1 day")
        XCTAssertEqual(Stat.Meals.hourDays(5), "5 days")
        XCTAssertEqual(Stat.Meals.entriesOn(1, of: 1), "entries on 1 of 1 day")
        XCTAssertEqual(Stat.Meals.entriesOn(2, of: 5), "entries on 2 of 5 days")

        // one complete day of pump data
        let insulin = Stat.Insulin(insulinResult(uncovered: [0, 1, 2, 3, 4], days: 5 ... 6))
        XCTAssertEqual(insulin.hourReadouts[8].subtitle, "1 day · 1 hour of data")
        // one complete day with entries
        let meals = Stat.Meals(mealsResult(fat: false, skipped: [0, 1, 2, 3, 4]))
        XCTAssertEqual(meals.hourReadouts[13].subtitle, "1 day")
        XCTAssertEqual(meals.hourReadouts[13].rows[1].value, "on 1 of 1 day")
        XCTAssertEqual(meals.topHours.first?.subtitle, "entries on 1 of 1 day · 60 g each")
    }

    /// The light-mode contrast fixes: basal and carbs carry an outline (`StatsBarStyle.stroke`).
    func testBasalAndCarbsAreOutlined() {
        XCTAssertNotNil(InsulinPart.basal.style.stroke)
        XCTAssertNil(InsulinPart.smb.style.stroke)
        XCTAssertNil(InsulinPart.bolus.style.stroke)
        XCTAssertNotNil(Stat.Meals.Part.carbs.style.stroke)
        XCTAssertNotNil(Stat.Meals.Part.carbEquivalents.style.stroke)
    }

    // MARK: - Nutrients

    /// Two foods with nutrient data on the `logged` complete days (08:10 40 g: fiber 5 g, salt 7 g, vitamin C 47.5 mg,
    /// folate 0.165 mg as stored; 13:05 60 g: fiber 15 g, iron 8 mg), the first of them alone with data on the
    /// `partly` days (13:05 60 g without); today 08:00 30 g with fiber 3 g.
    private func nutrientsResult(logged: Set<Int> = [0, 1, 2, 4, 5], partly: Set<Int> = []) -> Stat.MealsResult {
        var points: [MealPoint] = []
        for offset in 0 ... 5 where logged.contains(offset) || partly.contains(offset) {
            points.append(MealPoint(
                id: "b\(offset)",
                actualDate: clock(offset, 8, 10),
                carbs: 40,
                fiber: 5,
                micronutrients: [.salt: 7, .vitaminC: 47.5, .vitaminB9: 0.165]
            ))
            points.append(MealPoint(
                id: "l\(offset)",
                actualDate: clock(offset, 13, 5),
                carbs: 60,
                fiber: logged.contains(offset) ? 15 : 0,
                micronutrients: logged.contains(offset) ? [.iron: 8] : [:]
            ))
        }
        points.append(MealPoint(id: "t", actualDate: clock(6, 8), carbs: 30, fiber: 3))
        return Stat.Provider.mealsResult(points, period: .days7, factor: 0.5, now: now, calendar: calendar)
    }

    /// a woman of 41
    private var woman: NutrientReferences {
        NutrientReferences(
            .init(sexSetting: 0, birthDate: calendar.date(byAdding: .year, value: -41, to: now)!),
            now: now,
            calendar: calendar
        )!
    }

    /// The Fiber tile and the way in, the rows by the share of the reference (salt above its limit in orange, its bar
    /// split at the tick), the basis line; a nutrient's screen and its days.
    @MainActor func testNutrientsFormatting() {
        let meals = Stat.Meals(nutrientsResult(), references: woman)
        let nutrients = meals.nutrients
        XCTAssertEqual(meals.tiles.map(\.title), ["Entries", "Per entry", "Fiber"])
        XCTAssertEqual(meals.tiles.last?.value, "20")
        XCTAssertNil(meals.tiles.last?.limitedNote)
        XCTAssertTrue(nutrients.logsNutrients)
        XCTAssertEqual(nutrients.daysWithData, "Nutrient data on 5 of 6 days")
        XCTAssertEqual(nutrients.coverage, "Days with nutrient data 5 of 6")
        XCTAssertNil(nutrients.limitedNote)
        XCTAssertNil(nutrients.emptyTitle)
        XCTAssertEqual(
            nutrients.basis,
            "EFSA reference intakes for a woman, 41 (Settings › About You). Salt: the 5 g a day limit."
        )
        XCTAssertEqual(nutrients.legendTick, "Reference intake = 100%")

        XCTAssertEqual(nutrients.sections.count, 1)
        let rows = nutrients.sections[0].rows
        XCTAssertEqual(rows.count, 25)
        // salt 140%, fiber 80%, then the 50% ones in the app's order
        XCTAssertEqual(rows.prefix(5).map(\.name), ["Salt", "Fiber", "Vitamin B9", "Vitamin C", "Iron"])
        let salt = rows[0]
        XCTAssertEqual(salt.amount, d("7.0 g"))
        XCTAssertEqual(salt.percent, "140%")
        XCTAssertTrue(salt.isOverLimit)
        XCTAssertEqual(salt.subtitle, "Above the 5 g limit")
        XCTAssertEqual(salt.bar?.filled ?? 0, Stat.Nutrients.Bar.tick, accuracy: 1E-9)
        XCTAssertEqual(salt.bar?.over ?? 0, 140.0 / 150 - Stat.Nutrients.Bar.tick, accuracy: 1E-9)
        XCTAssertEqual(rows[1].bar?.filled ?? 0, 80.0 / 150, accuracy: 1E-9)
        XCTAssertEqual(rows[1].bar?.over, 0)
        // folate stored in mg, shown in µg
        let folate = rows[2]
        XCTAssertEqual(folate.subtitle, "Folate")
        XCTAssertEqual(folate.amount, "165 " + MicroNutrient.vitaminB12.unit)
        XCTAssertFalse(folate.isOverLimit)
        XCTAssertEqual(rows.last?.percent, "0%")
        XCTAssertEqual(rows.last?.amount, "0 " + MicroNutrient.iodine.unit)

        // salt's screen: the counted days solid, the limit's line, the average
        let detail = nutrients.detail(.micro(.salt))
        XCTAssertEqual(detail.name, "Salt")
        XCTAssertEqual(detail.average, d("7.0"))
        XCTAssertEqual(detail.reference, "140% of the 5 g limit")
        XCTAssertTrue(detail.isOverLimit)
        XCTAssertEqual(detail.plot.average, 7)
        XCTAssertEqual(detail.plot.reference?.value, 5)
        XCTAssertEqual(detail.plot.levels, [0, 2.5, 5, 7.5])
        XCTAssertEqual(detail.plot.levelLabels, ["0 g", d("2.5"), "5", d("7.5")])
        XCTAssertEqual(detail.plot.parts.map(\.series), [0, 0, 0, 0, 0])
        XCTAssertEqual(
            detail.legend.map(\.title),
            ["Salt, days in the average", "Not in the average", d("Average 7.0 g"), "Limit 5 g"]
        )

        // a counted day: the foods listing salt, and one with nutrient data that doesn't
        let counted = nutrients.card(at: 0, for: .micro(.salt))
        XCTAssertEqual(counted.amount, d("7.0"))
        XCTAssertEqual(counted.percent, "140%")
        XCTAssertTrue(counted.isOverLimit)
        XCTAssertEqual(counted.status, "In the average · nutrient data on 2 of 2 entries")
        XCTAssertEqual(counted.entries.map(\.value), [d("7.0 g"), "not listed"])
        XCTAssertEqual(counted.entries.map(\.isListed), [true, false])
        // a day without entries
        let empty = nutrients.card(at: 3, for: .micro(.salt))
        XCTAssertEqual(empty.amount, "–")
        XCTAssertNil(empty.percent)
        XCTAssertEqual(empty.status, "No carb entries")
        // today: outlined, "so far"
        let fiber = nutrients.detail(.fiber)
        XCTAssertEqual(fiber.plot.parts.filter { $0.day == day(6) }.map(\.series), [1])
        XCTAssertEqual(fiber.reference, "80% of the 25 g reference intake")
        let today = nutrients.card(at: 6, for: .fiber)
        XCTAssertEqual(today.title, "Today")
        XCTAssertTrue(today.soFar)
        XCTAssertEqual(today.amount, d("3.0"))
        XCTAssertEqual(today.percent, "12%")
        XCTAssertFalse(today.isOverLimit)
        XCTAssertEqual(today.status, "So far · nutrient data on 1 of 1 entry · averaged from midnight")
    }

    /// Without the sex or the birth date: the rows grouped (fiber, vitamins, minerals) in the app's order, no percent
    /// or bar but salt's (its limit needs neither); no reference line but salt's.
    @MainActor func testNutrientsWithoutReferences() {
        let nutrients = Stat.Meals(nutrientsResult()).nutrients
        XCTAssertFalse(nutrients.hasReferences)
        XCTAssertEqual(nutrients.basis, "Salt: the EFSA limit of 5 g a day.")
        XCTAssertEqual(nutrients.legendTick, "Salt limit = 100%")
        XCTAssertEqual(
            Stat.Nutrients.noReferencesNote,
            "Set sex and birth date for reference intakes"
        )
        XCTAssertEqual(nutrients.sections.map(\.title), [nil, "Vitamins", "Minerals"])
        XCTAssertEqual(nutrients.sections.map(\.rows.count), [1, 13, 11])
        let rows = nutrients.sections.flatMap(\.rows)
        XCTAssertEqual(rows.map(\.nutrient), StatsNutrient.all)
        XCTAssertEqual(rows.compactMap(\.percent), ["140%"])
        XCTAssertEqual(rows.compactMap(\.bar).count, 1)
        let salt = rows.last!
        XCTAssertTrue(salt.isOverLimit)
        XCTAssertEqual(salt.subtitle, "Above the 5 g limit")
        XCTAssertNotNil(salt.bar)
        let detail = nutrients.detail(.micro(.salt))
        XCTAssertEqual(detail.reference, "140% of the 5 g limit")
        XCTAssertEqual(detail.plot.reference?.value, 5)
        XCTAssertEqual(detail.legend.map(\.title).last, "Limit 5 g")
        XCTAssertEqual(nutrients.card(at: 0, for: .micro(.salt)).percent, "140%")
        let fiber = nutrients.detail(.fiber)
        XCTAssertNil(fiber.reference)
        XCTAssertNil(fiber.plot.reference)
        XCTAssertEqual(fiber.legend.map(\.title).last, d("Average 20 g"))
        XCTAssertNil(nutrients.card(at: 0, for: .fiber).percent)

        // "other" counts as not set
        let other = NutrientReferences(
            .init(sexSetting: 2, birthDate: calendar.date(byAdding: .year, value: -41, to: now)!),
            now: now,
            calendar: calendar
        )
        XCTAssertNil(other)
    }

    /// No nutrient data: no Fiber tile and no way in; only partly logged days: "–", the empty note; too few days
    /// counted: the mark on the Fiber tile and the coverage.
    @MainActor func testNutrientsEmptyPartlyAndLimited() {
        let none = Stat.Meals(mealsResult(fat: false), references: woman)
        XCTAssertFalse(none.nutrients.logsNutrients)
        XCTAssertNil(none.nutrients.fiberTile)
        XCTAssertEqual(none.tiles.map(\.title), ["Entries", "Per entry"])
        XCTAssertEqual(none.nutrients.emptyTitle, "No nutrient data in this period")
        XCTAssertEqual(none.nutrients.sections, [])

        let partly = Stat.Meals(nutrientsResult(logged: [], partly: [1, 2]), references: woman)
        XCTAssertTrue(partly.nutrients.logsNutrients)
        XCTAssertEqual(partly.tiles.last?.value, "–")
        XCTAssertEqual(partly.nutrients.emptyTitle, "No day with enough nutrient data yet")
        XCTAssertNil(partly.nutrients.limitedNote)
        XCTAssertNil(partly.nutrients.basis)
        let detail = partly.nutrients.detail(.fiber)
        XCTAssertNil(detail.average)
        XCTAssertNil(detail.reference)
        XCTAssertNil(detail.plot.average)
        // 40 of 100 g with nutrient data
        XCTAssertEqual(
            partly.nutrients.card(at: 1, for: .fiber).status,
            "Not in the average · foods with nutrient data are 40% of the carbs"
        )
        XCTAssertEqual(partly.nutrients.card(at: 0, for: .fiber).status, "No carb entries")

        let limited = Stat.Meals(nutrientsResult(logged: [0, 1], partly: [2]), references: woman)
        XCTAssertEqual(limited.nutrients.coverage, "Days with nutrient data 2 of 6")
        XCTAssertNotNil(limited.nutrients.limitedNote)
        XCTAssertEqual(limited.tiles.last?.limitedNote, limited.nutrients.limitedNote)
    }

    /// The amounts: whole from 10, one decimal from 1, two below; the references as the table has them.
    func testNutrientAmounts() {
        XCTAssertEqual(Stat.Nutrients.number(0), "0")
        XCTAssertEqual(Stat.Nutrients.number(0.05), d("0.05"))
        XCTAssertEqual(Stat.Nutrients.number(1.06), d("1.1"))
        XCTAssertEqual(Stat.Nutrients.number(12.4), "12")
        XCTAssertEqual(Stat.Nutrients.referenceAmount(5, unit: "g"), "5 g")
        XCTAssertEqual(Stat.Nutrients.referenceAmount(1.1, unit: "mg"), d("1.1 mg"))
        XCTAssertEqual(Stat.Nutrients.bar(percent: 300, isOverLimit: false), Stat.Nutrients.Bar(filled: 1, over: 0))
        XCTAssertEqual(Stat.Nutrients.bar(percent: 75, isOverLimit: false), Stat.Nutrients.Bar(filled: 0.5, over: 0))
        // above 0, below what two decimals show: not "0.00" (copper's 0.004 mg)
        XCTAssertEqual(Stat.Nutrients.number(0.004), d("< 0.01"))
        XCTAssertEqual(Stat.Nutrients.amount(0.004, unit: "mg"), d("< 0.01 mg"))
        XCTAssertEqual(Stat.Nutrients.number(0.005), d("0.01"))
    }

    /// A day not in the average: the share of its carbs with nutrient data rounded down (79.6% isn't the "80%" it
    /// would need), a whole share exact (29 of 100 g isn't 28.999…).
    @MainActor func testNotInTheAverageShareIsRoundedDown() {
        func status(_ carbsWithData: Double, of carbs: Double) -> String {
            Stat.Nutrients.status(DayNutrients(
                day: DateInterval(start: day(1), end: day(2)),
                isToday: false,
                entries: 2,
                entriesWithData: 1,
                carbs: carbs,
                carbsWithData: carbsWithData,
                amounts: [.fiber: 1],
                isCounted: false,
                points: []
            ))
        }
        XCTAssertEqual(status(79.6, of: 100), "Not in the average · foods with nutrient data are 79% of the carbs")
        XCTAssertEqual(status(79.99, of: 100), "Not in the average · foods with nutrient data are 79% of the carbs")
        XCTAssertEqual(status(29, of: 100), "Not in the average · foods with nutrient data are 29% of the carbs")
        XCTAssertEqual(status(40, of: 100), "Not in the average · foods with nutrient data are 40% of the carbs")
    }

    /// A supplement (nutrient data without carbs, fat or protein) isn't on the Meals tab. On a nutrient's day card it is
    /// an entry at its time with its amount and no carbs figure; a day of it alone isn't counted: "no carbs".
    @MainActor func testNutrientOnlyEntryOnTheDayCard() {
        let points = [
            MealPoint(id: "b", actualDate: clock(0, 8, 10), carbs: 40, fiber: 5),
            MealPoint(id: "d0", actualDate: clock(0, 7), carbs: 0, micronutrients: [.vitaminD: 20]),
            MealPoint(id: "d1", actualDate: clock(1, 7), carbs: 0, micronutrients: [.vitaminD: 20])
        ]
        let result = Stat.Provider.mealsResult(points, period: .days7, factor: 0.5, now: now, calendar: calendar)
        XCTAssertEqual(result.meals.summary.entries, 1)
        XCTAssertTrue(result.meals.days[1].entries.isEmpty)
        let nutrients = Stat.Meals(result).nutrients
        let card = nutrients.card(at: 0, for: .micro(.vitaminD))
        XCTAssertEqual(card.entries.map(\.carbs), [nil, "40 g"])
        XCTAssertEqual(card.entries.map(\.value), ["20 " + MicroNutrient.vitaminD.unit, "not listed"])
        XCTAssertEqual(card.amount, "20")
        XCTAssertEqual(card.status, "In the average · nutrient data on 2 of 2 entries")
        let alone = nutrients.card(at: 1, for: .micro(.vitaminD))
        XCTAssertEqual(alone.amount, "20")
        XCTAssertEqual(alone.status, "Not in the average · no carbs on this day")
    }

    /// Salt just above its limit but shown as "100%" (5.02 g, "5.0 g"): not marked above it on the row, the screen or
    /// the day; at "101%" (5.03 g) it is.
    @MainActor func testSaltAtTheShownLimitIsNotAboveIt() {
        func nutrients(salt: Double) -> Stat.Nutrients {
            let points = (0 ... 5).map { offset in
                MealPoint(id: "b\(offset)", actualDate: clock(offset, 8, 10), carbs: 40, fiber: 5, micronutrients: [.salt: salt])
            }
            return Stat.Meals(Stat.Provider.mealsResult(points, period: .days7, factor: 0.5, now: now, calendar: calendar))
                .nutrients
        }
        func saltRow(_ nutrients: Stat.Nutrients) -> Stat.Nutrients.Row? {
            nutrients.sections.flatMap(\.rows).first { $0.nutrient == .micro(.salt) }
        }

        let atLimit = nutrients(salt: 5.02)
        let row = saltRow(atLimit)
        XCTAssertEqual(row?.amount, d("5.0 g"))
        XCTAssertEqual(row?.percent, "100%")
        XCTAssertEqual(row?.isOverLimit, false)
        XCTAssertNil(row?.subtitle)
        XCTAssertEqual(row?.bar?.over, 0)
        let detail = atLimit.detail(.micro(.salt))
        XCTAssertEqual(detail.reference, "100% of the 5 g limit")
        XCTAssertFalse(detail.isOverLimit)
        let card = atLimit.card(at: 0, for: .micro(.salt))
        XCTAssertEqual(card.percent, "100%")
        XCTAssertFalse(card.isOverLimit)

        let above = nutrients(salt: 5.03)
        XCTAssertEqual(saltRow(above)?.percent, "101%")
        XCTAssertEqual(saltRow(above)?.isOverLimit, true)
        XCTAssertEqual(saltRow(above)?.subtitle, "Above the 5 g limit")
        XCTAssertTrue(above.detail(.micro(.salt)).isOverLimit)
        XCTAssertTrue(above.card(at: 0, for: .micro(.salt)).isOverLimit)
    }

    // MARK: - Selection

    /// A day picked on a chart of days: today kept as nil (it follows midnight), a past day from its start, kept inside
    /// the days shown.
    @MainActor func testDaySelectionOnAChartOfDays() {
        let days = (0 ..< 7).map { DateInterval(start: day($0), end: day($0 + 1)) }
        let selection = DailySelection()
        XCTAssertEqual(selection.index(in: days), 6)
        XCTAssertNil(selection.index(in: []))
        selection.pick(2, in: days)
        XCTAssertEqual(selection.day, day(2))
        XCTAssertEqual(selection.index(in: days), 2)
        // a shorter period: the nearest day
        XCTAssertEqual(selection.index(in: Array(days.suffix(3))), 0)
        selection.pick(6, in: days)
        XCTAssertNil(selection.day)
        selection.pick(9, in: days)
        XCTAssertNil(selection.day)
    }

    /// The Statistics pages (`StateModel.appear` / `disappear`): up with the first page in; a pop or a push in either
    /// order (the old page gone before the new one comes, or after) keeps it up, nothing torn down and begun again; the
    /// last page gone (Close, the dismiss) takes it down one main-actor turn later, once.
    @MainActor func testStatisticsPagesStayUpAcrossAPopInEitherOrder() async {
        @MainActor final class Log {
            var events: [String] = []
        }
        let log = Log()
        let pages = StatsPageSet<Stat.StateModel.Page>()
        func appear(_ page: Stat.StateModel.Page) {
            if pages.appear(page) {
                log.events.append("up")
            }
        }
        func disappear(_ page: Stat.StateModel.Page) {
            pages.disappear(page) { log.events.append("down") }
        }
        /// the main-actor jobs queued so far run
        func settle() async {
            for _ in 0 ..< 10 {
                await Task.yield()
            }
        }

        appear(.root)
        XCTAssertEqual(log.events, ["up"])
        // a push: the new page first, then the old one goes
        appear(.nutrients)
        disappear(.root)
        // a push: the old page goes first
        disappear(.nutrients)
        appear(.nutrient)
        await settle()
        XCTAssertEqual(log.events, ["up"])
        // a pop, the old page gone first, then the new one in the same turn
        disappear(.nutrient)
        appear(.root)
        await settle()
        XCTAssertEqual(log.events, ["up"])
        XCTAssertTrue(pages.isUp)
        // a page that isn't shown: nothing
        disappear(.nutrients)
        await settle()
        XCTAssertEqual(log.events, ["up"])

        // Close: the last page gone, down one turn later (not at once), once
        disappear(.root)
        XCTAssertEqual(log.events, ["up"])
        XCTAssertTrue(pages.isUp)
        disappear(.root)
        await settle()
        XCTAssertEqual(log.events, ["up", "down"])
        XCTAssertFalse(pages.isUp)
        // opened again
        appear(.root)
        XCTAssertEqual(log.events, ["up", "down", "up"])
    }

    /// No clock on Statistics: an interaction that reads nothing of its own reads again in place only when the day of
    /// the last request isn't today (a midnight, or a time zone change, passed on screen); never before the first
    /// request.
    func testStatisticsReadsAgainOnAnInteractionOnlyAfterMidnight() {
        typealias Model = Stat.StateModel
        let today = calendar.startOfDay(for: clock(6, 12))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        XCTAssertFalse(Model.dayMovedOn(since: nil, today: today))
        XCTAssertFalse(Model.dayMovedOn(since: today, today: today))
        XCTAssertTrue(Model.dayMovedOn(since: yesterday, today: today))
        // a time zone change moved the start of today
        XCTAssertTrue(Model.dayMovedOn(since: today.addingTimeInterval(.hours(1)), today: today))
    }

    /// The latest task wins (`StatsLatestTask`, the state model's refresh and loads): a start cancels the load in flight,
    /// which is no longer current after its awaits; a task the caller started after `begin` (a refresh's) is current
    /// until the next start; a cancel drops the current one.
    @MainActor func testTheLatestTaskWins() async {
        @MainActor final class Log {
            var current: [String: Bool] = [:]
        }
        let log = Log()
        let latest = StatsLatestTask()
        XCTAssertEqual(latest.seq, 0)

        // both started before either runs: only the second is current, after an await too
        let first = latest.start { isCurrent in
            log.current["first"] = isCurrent()
        }
        let second = latest.start { isCurrent in
            await Task.yield()
            log.current["second"] = isCurrent()
        }
        await first.value
        await second.value
        XCTAssertEqual(log.current, ["first": false, "second": true])
        XCTAssertTrue(first.isCancelled)
        XCTAssertFalse(second.isCancelled)
        XCTAssertEqual(latest.seq, 2)

        // the caller's own task, its seq taken first (`begin`): current until the next start, which cancels it
        let seq = latest.begin()
        XCTAssertEqual(seq, 3)
        let adopted = Task { @MainActor in
            log.current["adopted"] = latest.isCurrent(seq)
        }
        latest.adopt(adopted)
        XCTAssertTrue(latest.isCurrent(seq))
        let third = latest.start { isCurrent in
            log.current["third"] = isCurrent()
        }
        XCTAssertFalse(latest.isCurrent(seq))
        await adopted.value
        await third.value
        XCTAssertEqual(log.current["third"], true)
        XCTAssertTrue(adopted.isCancelled)
        XCTAssertEqual(log.current["adopted"], false)

        // a cancel: none is current
        let fourth = latest.start { isCurrent in
            await Task.yield()
            log.current["fourth"] = isCurrent()
        }
        latest.cancel()
        await fourth.value
        XCTAssertEqual(log.current["fourth"], false)
        XCTAssertTrue(fourth.isCancelled)
        XCTAssertEqual(latest.seq, 6)
    }

    /// The usual day's loads (`UsualDayLoads`): due until asked for today, and again after midnight or a change that
    /// reaches the baseline (a day before today, a change missed in between), not after a reading of today alone or a
    /// change its load read; a drop makes it due and its load in flight no longer current.
    @MainActor func testTheUsualDayIsLoadedAgainOnlyWhenDue() async {
        @MainActor final class Log {
            var current: Bool?
        }
        let today = calendar.startOfDay(for: clock(6, 12))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        func change(_ seq: Int, at start: Date) -> StatsChange {
            StatsChange(seq: seq, interval: DateInterval(start: start, duration: .minutes(5)))
        }
        let loads = UsualDayLoads()
        XCTAssertTrue(loads.isDue(today: today))
        await loads.start(today: today, changeSeq: 3) { _ in }.value
        XCTAssertFalse(loads.isDue(today: today))
        // midnight moved its window
        XCTAssertTrue(loads.isDue(today: tomorrow))

        // a reading of today, and a change older than the load's: not due
        loads.noteChange(change(4, at: today.addingTimeInterval(.hours(10))), today: today)
        loads.noteChange(StatsChange(seq: 2, interval: nil), today: today)
        XCTAssertFalse(loads.isDue(today: today))
        // a day before today
        loads.noteChange(change(5, at: today.addingTimeInterval(.hours(-3))), today: today)
        XCTAssertTrue(loads.isDue(today: today))

        // loaded again, then a change missed in between (only the newest is delivered): due
        await loads.start(today: today, changeSeq: 5) { _ in }.value
        XCTAssertFalse(loads.isDue(today: today))
        loads.noteChange(change(7, at: today.addingTimeInterval(.hours(10))), today: today)
        XCTAssertTrue(loads.isDue(today: today))
        // a change its load read: not due
        await loads.start(today: today, changeSeq: 9) { _ in }.value
        loads.noteChange(StatsChange(seq: 9, interval: nil), today: today)
        XCTAssertFalse(loads.isDue(today: today))

        // dropped
        let log = Log()
        let load = loads.start(today: today, changeSeq: 9) { isCurrent in
            await Task.yield()
            log.current = isCurrent()
        }
        loads.clear()
        await load.value
        XCTAssertEqual(log.current, false)
        XCTAssertTrue(loads.isDue(today: today))
    }

    /// Every pick calls the selection's `onPick` (the state model's midnight check), the one picked again too: a tap, a
    /// step, a point of a chart.
    @MainActor func testSelectionsReportEveryPick() {
        var picks = 0
        let hour = HourSelection()
        hour.onPick = { picks += 1 }
        hour.select(5)
        hour.select(5)
        hour.step(by: 1)
        XCTAssertEqual(hour.hour, 6)
        XCTAssertEqual(picks, 3)

        let agp = AGPSelection()
        agp.onPick = { picks += 1 }
        agp.select(3)
        agp.select(3)
        XCTAssertEqual(picks, 5)

        let day = DailySelection()
        day.onPick = { picks += 1 }
        day.select(nil)
        day.select(clock(2, 0))
        XCTAssertEqual(day.day, clock(2, 0))
        XCTAssertEqual(picks, 7)

        // By weekday's cell, its stepper and its metric; entering the view clears the cell without a pick
        let weekday = WeekdaySelection()
        weekday.onPick = { picks += 1 }
        weekday.select(weekday: 7, hour: 10)
        weekday.select(weekday: 7, hour: 10)
        weekday.step(by: 1, hoursPerRow: 3)
        XCTAssertEqual(weekday.weekday, 7)
        XCTAssertEqual(weekday.hour, 12)
        weekday.step(by: -1, hoursPerRow: 1)
        XCTAssertEqual(weekday.hour, 11)
        weekday.select(metric: .mean)
        weekday.select(metric: .mean)
        XCTAssertEqual(weekday.metric, .mean)
        XCTAssertEqual(picks, 13)
        weekday.clear()
        XCTAssertNil(weekday.weekday)
        // no cell: the stepper picks none
        weekday.step(by: 1, hoursPerRow: 1)
        XCTAssertNil(weekday.weekday)
        XCTAssertEqual(picks, 13)
    }

    // MARK: - Home meal card

    private typealias MealCard = HomeMealsCard.Content

    /// `mealsResult`'s entries: 40 g at 08:10 and 60 g at 13:05 on every complete day but `skipped`, the lunch of day 1
    /// with 20 g fat and 30 g protein when `fat`; today 30 g at 08:00.
    private func mealPoints(fat: Bool = true, skipped: Set<Int> = [3]) -> [MealPoint] {
        var points: [MealPoint] = []
        for offset in 0 ... 5 where !skipped.contains(offset) {
            points.append(MealPoint(id: "b\(offset)", actualDate: clock(offset, 8, 10), carbs: 40))
            let withFat = fat && offset == 1
            points.append(MealPoint(
                id: "l\(offset)",
                actualDate: clock(offset, 13, 5),
                carbs: 60,
                fat: withFat ? 20 : 0,
                protein: withFat ? 30 : 0
            ))
        }
        points.append(MealPoint(id: "t", actualDate: clock(6, 8), carbs: 30))
        return points
    }

    /// `nutrientsResult`'s entries: foods with nutrient data on the `logged` complete days (fiber 5 + 15 g), the
    /// breakfast alone with data on the `partly` ones; today 30 g at 08:00 with fiber 3 g.
    private func nutrientPoints(logged: Set<Int> = [0, 1, 2, 4, 5], partly: Set<Int> = []) -> [MealPoint] {
        var points: [MealPoint] = []
        for offset in 0 ... 5 where logged.contains(offset) || partly.contains(offset) {
            points.append(MealPoint(id: "b\(offset)", actualDate: clock(offset, 8, 10), carbs: 40, fiber: 5))
            points.append(MealPoint(
                id: "l\(offset)",
                actualDate: clock(offset, 13, 5),
                carbs: 60,
                fiber: logged.contains(offset) ? 15 : 0,
                micronutrients: logged.contains(offset) ? [.iron: 8] : [:]
            ))
        }
        points.append(MealPoint(id: "t", actualDate: clock(6, 8), carbs: 30, fiber: 3))
        return points
    }

    /// Today (since local midnight, up to the read): the window's totals (yesterday's dinner and an entry dated later
    /// not in them), the nutrient data counted in entries, the mark when the entries with it carry less than 80% of the
    /// carbs; no footer (no basis, no entry count); a later read counts the later entry.
    @MainActor func testHomeMealCardToday() throws {
        let points = [
            MealPoint(id: "y", actualDate: clock(5, 20), carbs: 40, fat: 10, protein: 20),
            MealPoint(id: "b", actualDate: clock(6, 8), carbs: 30, fiber: 3),
            MealPoint(id: "s", actualDate: clock(6, 11), carbs: 20),
            // after now
            MealPoint(id: "l", actualDate: clock(6, 13), carbs: 50, fiber: 6)
        ]
        let today = MealCard(points: points, now: now, calendar: calendar)
        XCTAssertEqual(today.tiles.map(\.title), ["Carbs", "Fat", "Protein", "Energy"])
        XCTAssertEqual(today.tiles.map(\.unit), ["g", "g", "g", "kcal"])
        XCTAssertEqual(today.tiles.map(\.value), ["50", "0", "0", "200"])
        // the tiles and the Nutrients row: no footer line
        XCTAssertEqual(Mirror(reflecting: today).children.map(\.label), ["tiles", "nutrients"])
        let todayNutrients = try XCTUnwrap(today.nutrients)
        XCTAssertEqual(todayNutrients.coverage, "Data on 1 of 2 entries")
        // whole grams, as the Meals tab's Fiber tile
        XCTAssertEqual(todayNutrients.fiber, "3")
        XCTAssertEqual(todayNutrients.fiberUnit, "g")
        // 30 of 50 g
        XCTAssertTrue(todayNutrients.isLimited)
        // read after the later entry's time: it counts
        let later = MealCard(points: points, now: clock(6, 13), calendar: calendar)
        XCTAssertEqual(later.tiles.first?.value, "100")
        XCTAssertEqual(later.nutrients?.coverage, "Data on 2 of 3 entries")
        // read the next day: a new today, yesterday's entries out
        let tomorrow = MealCard(points: points, now: clock(7, 9), calendar: calendar)
        XCTAssertEqual(tomorrow.tiles.map(\.value), ["0", "0", "0", "0"])
        XCTAssertNil(tomorrow.nutrients)
    }

    /// One entry: "of 1 entry"; a supplement adds its fiber and counts in the coverage as on the Nutrients screen's
    /// today status (which the row opens) but isn't a Meals entry, and alone shows no row; nothing today: zeros and no
    /// row; a large day's energy grouped as the locale writes it.
    @MainActor func testHomeMealCardOneEntryNoneAndSupplements() throws {
        let one = [MealPoint(id: "b", actualDate: clock(6, 8), carbs: 30, fiber: 3)]
        let card = MealCard(points: one, now: now, calendar: calendar)
        let nutrients = try XCTUnwrap(card.nutrients)
        XCTAssertEqual(nutrients.coverage, "Data on 1 of 1 entry")
        XCTAssertFalse(nutrients.isLimited)

        let supplement = MealPoint(id: "p", actualDate: clock(6, 9), carbs: 0, fiber: 5)
        let withSupplement = MealCard(points: one + [supplement], now: now, calendar: calendar)
        XCTAssertEqual(withSupplement.tiles.first?.value, "30")
        XCTAssertEqual(withSupplement.nutrients?.fiber, "8")
        XCTAssertEqual(withSupplement.nutrients?.coverage, "Data on 2 of 2 entries")
        // the Nutrients screen's today: the same count
        let screen = Stat.Meals(
            Stat.Provider.mealsResult(one + [supplement], period: .days7, factor: 0.5, now: now, calendar: calendar)
        ).nutrients
        XCTAssertTrue(screen.card(at: 6, for: .fiber).status.contains("nutrient data on 2 of 2 entries"))
        let supplementOnly = [MealPoint(id: "c", actualDate: clock(6, 8), carbs: 30), supplement]
        XCTAssertNil(MealCard(points: supplementOnly, now: now, calendar: calendar).nutrients)

        let none = MealCard(points: [], now: now, calendar: calendar)
        XCTAssertEqual(none.tiles.map(\.value), ["0", "0", "0", "0"])
        XCTAssertNil(none.nutrients)

        // 4 × (300 + 60) + 9 × 50 = 1,890 kcal
        let large = [MealPoint(id: "x", actualDate: clock(6, 9), carbs: 300, fat: 50, protein: 60)]
        XCTAssertEqual(
            MealCard(points: large, now: now, calendar: calendar).tiles.last?.value,
            StatsAmount.number(1890, digits: 0 ... 0)
        )
    }

    /// The Nutrients row needs food with nutrient data logged in the last 90 days (`logsNutrients`) and today: the
    /// days before today don't show it, nor count in it.
    @MainActor func testHomeMealCardNutrientsAreToday() throws {
        // nutrient data on the days before only: no row
        XCTAssertNil(MealCard(points: nutrientPoints().filter { $0.id != "t" }, now: now, calendar: calendar).nutrients)
        // and today's entry: today's alone count
        let nutrients = try XCTUnwrap(MealCard(points: nutrientPoints(), now: now, calendar: calendar).nutrients)
        XCTAssertEqual(nutrients.coverage, "Data on 1 of 1 entry")
        XCTAssertEqual(nutrients.fiber, "3")
    }

    /// A window of fat and protein alone, with nutrient data: the row (food with nutrient data, logged with carbs the
    /// day before), never limited (no carbs to carry 80% of).
    @MainActor func testHomeMealCardFatAndProteinOnlyWithNutrientData() throws {
        let points = [
            // yesterday, out of Today: food with nutrient data logged (`logsNutrients`)
            MealPoint(id: "y", actualDate: clock(5, 13), carbs: 40, fiber: 4),
            MealPoint(id: "e", actualDate: clock(6, 7), carbs: 0, fat: 15, protein: 20, fiber: 2)
        ]
        let card = MealCard(points: points, now: now, calendar: calendar)
        // 4 × (0 + 20) + 9 × 15 = 215 kcal
        XCTAssertEqual(card.tiles.map(\.value), ["0", "15", "20", "215"])
        let nutrients = try XCTUnwrap(card.nutrients)
        XCTAssertEqual(nutrients.coverage, "Data on 1 of 1 entry")
        XCTAssertEqual(nutrients.fiber, "2")
        XCTAssertFalse(nutrients.isLimited)
    }

    /// Today: rows with the same id are one (`MealStatsEngine.clean`'s, the leftover copies of the old Nightscout save),
    /// a supplement's too.
    @MainActor func testHomeMealCardTodayDeduplicates() throws {
        let points = [
            MealPoint(id: "b", actualDate: clock(6, 8), carbs: 30, fat: 5, fiber: 3),
            MealPoint(id: "b", actualDate: clock(6, 8, 5), carbs: 30, fat: 5, fiber: 3),
            MealPoint(id: "p", actualDate: clock(6, 9), carbs: 0, fiber: 2),
            MealPoint(id: "p", actualDate: clock(6, 9, 5), carbs: 0, fiber: 2)
        ]
        let card = MealCard(points: points, now: now, calendar: calendar)
        // 4 × 30 + 9 × 5 = 165 kcal
        XCTAssertEqual(card.tiles.map(\.value), ["30", "5", "0", "165"])
        let nutrients = try XCTUnwrap(card.nutrients)
        XCTAssertEqual(nutrients.coverage, "Data on 2 of 2 entries")
        XCTAssertEqual(nutrients.fiber, "5")
    }

    // MARK: - Home insulin card

    /// An Overview period on the Insulin and Meals tabs (the Home cards' taps open them on Today): Today and 24 h show
    /// Today, the others their own; back on Overview the period again (the preferred period is not changed by the tab's
    /// nearest one).
    @MainActor func testTheHomeRangeOnTheInsulinTab() {
        XCTAssertEqual(StatsPeriod.homeRanges, [.today, .last24h, .days7, .days14, .days30, .days90])
        for tab: StatsTab in [.insulin, .meals] {
            XCTAssertEqual(
                StatsPeriod.homeRanges.map { Stat.StateModel.nearest($0, in: tab.validPeriods) },
                [.today, .today, .days7, .days14, .days30, .days90]
            )
        }
        for range in StatsPeriod.homeRanges {
            XCTAssertEqual(Stat.StateModel.nearest(range, in: StatsTab.overview.validPeriods), range)
        }
    }

    private typealias InsulinCard = HomeInsulinCard.Content

    /// The period's days up to `now` as the service gives them: a flat 1 U/h, a 5 U bolus at 08:00 and a 0.5 U SMB at
    /// 09:00 on each of the `withData` days (offsets from `week`; all of the period's when nil), covered but
    /// `uncovered`; IOB rows every 5 minutes on them, negative from 03:00 for `negativeMinutes` (none at all when 0).
    /// Today is `InsulinStatsService.today`'s read: the 7 days before today (offsets -1 ... 5) and today, the summary
    /// without a period; the others `InsulinStatsEngine.period`.
    private func insulinPeriod(
        _ period: StatsPeriod,
        now: Date,
        withData: [Int]? = nil,
        uncovered: Set<Int> = [],
        negativeMinutes: Int = 0
    ) -> InsulinPeriod {
        let withData = withData ?? (period == .today ? Array(-1 ... 6) : Array(0 ... 6))
        var events: [PumpEventRecord] = []
        var rows: [CoveredInterval] = []
        var iob: [IOBPoint] = []
        for offset in withData {
            if clock(offset, 9) <= now {
                events += [bolus(clock(offset, 8), 5), bolus(clock(offset, 9), 0.5, smb: true)]
            }
            if !uncovered.contains(offset) {
                rows.append(coverage(day(offset), Swift.min(day(offset + 1), now)))
            }
            guard negativeMinutes > 0 else { continue }
            for slot in 0 ..< 288 {
                let time = day(offset).addingTimeInterval(.minutes(slot * 5))
                guard time < now else { break }
                let minute = slot * 5
                iob.append(IOBPoint(time: time, iob: minute >= 180 && minute < 180 + negativeMinutes ? -0.5 : 1))
            }
        }
        let input = InsulinInput(events: events, coverage: rows, schedules: [flatSchedule], iob: iob)
        guard period == .today else {
            return InsulinStatsEngine.period(
                Stat.Provider.insulinAndMealsPeriod(period),
                input: input,
                now: now,
                calendar: calendar
            )
        }
        let days = InsulinStatsEngine.days(
            InsulinStatsEngine.lastDays(InsulinStatsEngine.usualDays + 1, now: now, calendar: calendar),
            input: input,
            now: now,
            calendar: calendar
        )
        return todayRead(days)
    }

    /// `InsulinStatsService.today`'s result of its days: the summary without a period, the hours.
    private func todayRead(_ days: [DayInsulin]) -> InsulinPeriod {
        InsulinPeriod(
            summary: InsulinStatsEngine.summary(days, period: nil),
            days: days,
            hours: InsulinStatsEngine.hours(days)
        )
    }

    /// The headline days' insulin by now's clock time: the hours before it in full, its hour by the minutes passed
    /// (prorated); today and the days under half covered left out; nil without a headline day.
    func testClockAverage() {
        let lunch = clock(6, 12, 30)
        let days = insulinPeriod(.days7, now: lunch).days
        // 12 h at 1 U/h, 5 + 0.5 U, half of 12:00's 1 U
        XCTAssertEqual(InsulinStatsEngine.clockAverage(days)!.value(at: lunch, calendar: calendar), 18, accuracy: 1E-9)
        // 8 h, half of 08:00's 1 + 5 U
        XCTAssertEqual(
            InsulinStatsEngine.clockAverage(days)!.value(at: clock(6, 8, 30), calendar: calendar),
            11,
            accuracy: 1E-9
        )
        XCTAssertEqual(InsulinStatsEngine.clockAverage(days)!.value(at: clock(6, 0), calendar: calendar), 0, accuracy: 1E-9)
        // the seconds count too: 12:45:30 is 0.758 of 12:00
        XCTAssertEqual(
            InsulinStatsEngine.clockAverage(days)!.value(at: clock(6, 12, 45).addingTimeInterval(30), calendar: calendar),
            17.5 + 45.5 / 60,
            accuracy: 1E-9
        )
        // by the end of the day: the TDD
        XCTAssertEqual(
            InsulinStatsEngine.clockAverage(days)!.value(hour: 23, passed: 1),
            InsulinStatsEngine.summary(days, period: .days7).tdd!,
            accuracy: 1E-9
        )
        // a day without coverage (its boluses only) is no headline day: the same mean over the 5 others
        let gap = insulinPeriod(.days7, now: lunch, uncovered: [2]).days
        XCTAssertEqual(gap.filter(\.isHeadline).count, 5)
        XCTAssertEqual(InsulinStatsEngine.clockAverage(gap)!.value(at: lunch, calendar: calendar), 18, accuracy: 1E-9)
        // today only
        let todayOnly = insulinPeriod(.days7, now: lunch, withData: [6]).days
        XCTAssertNil(InsulinStatsEngine.clockAverage(todayOnly))
    }

    /// Whole past days at a flat 1 U/h, a 5 U bolus at 08:00 on each, each covered from its start to `coveredUntil`
    /// hours into it (all of it when nil): `InsulinStatsEngine.days` as the service gives them, none of them today.
    private func pastDays(_ starts: [Date], coveredHours: [Double?]) -> [DayInsulin] {
        var events: [PumpEventRecord] = []
        var rows: [CoveredInterval] = []
        var intervals: [DateInterval] = []
        for (index, start) in starts.enumerated() {
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            intervals.append(DateInterval(start: start, end: end))
            events.append(bolus(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: start)!, 5))
            rows.append(coverage(start, coveredHours[index].map { start.addingTimeInterval(.hours($0)) } ?? end))
        }
        let input = InsulinInput(events: events, coverage: rows, schedules: [flatSchedule])
        let now = intervals.last!.end.addingTimeInterval(.hours(12))
        return InsulinStatsEngine.days(intervals, input: input, now: now, calendar: calendar)
    }

    /// A partly covered headline day: its basal scaled to the whole day as the TDD's (`DayInsulin.scaledBasal`, the
    /// same factor every hour), so it isn't low by now and the day's end is the TDD.
    func testClockAverageScalesAPartlyCoveredDay() {
        // day 1 covered in full; day 2 up to 18:00 (75%: still a headline day), its basal × 24 / 18
        let days = pastDays([day(1), day(2)], coveredHours: [nil, 18])
        XCTAssertEqual(days.filter(\.isHeadline).count, 2)
        XCTAssertEqual(days[1].basal, 18, accuracy: 1E-9)
        // by 12:00: (12 + 5) and (12 × 4/3 + 5 = 21); delivered as is it would be (17 + 17) / 2
        XCTAssertEqual(InsulinStatsEngine.clockAverage(days)!.value(at: clock(6, 12), calendar: calendar), 19, accuracy: 1E-9)
        // by the end: (29 + 29) / 2, the TDD
        let average = InsulinStatsEngine.clockAverage(days)!
        XCTAssertEqual(average.value(hour: 23, passed: 1), 29, accuracy: 1E-9)
        XCTAssertEqual(average.value(hour: 23, passed: 1), InsulinStatsEngine.summary(days, period: nil).tdd!, accuracy: 1E-9)
    }

    /// DST, by clock hour: the 25-hour day's repeated 02:00 holds both passes (an hour more by the clock from there
    /// on, both prorated together inside it), the 23-hour day's skipped 02:00 nothing (an hour less); each ends at its
    /// own total, the TDD.
    func testClockAverageOnDSTDays() {
        let fallBack = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let springForward = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        for (start, hours) in [(fallBack, 25.0), (springForward, 23.0)] {
            let days = pastDays([start], coveredHours: [nil])
            XCTAssertEqual(days[0].day.duration, .hours(hours))
            XCTAssertTrue(days[0].isHeadline)
            let average = InsulinStatsEngine.clockAverage(days)!
            // by 01:00, before the change: as any day
            XCTAssertEqual(average.value(hour: 1, passed: 0), 1, accuracy: 1E-9)
            // by 12:00 (another day's clock): 13 h or 11 h of basal, the 5 U bolus
            XCTAssertEqual(
                InsulinStatsEngine.clockAverage(days)!.value(at: clock(6, 12), calendar: calendar),
                hours - 12 + 5,
                accuracy: 1E-9
            )
            // half into 02:00: both passes (2 U) by half, or nothing to prorate
            XCTAssertEqual(average.value(hour: 2, passed: 0.5), 2 + (hours - 23) / 2, accuracy: 1E-9)
            XCTAssertEqual(average.value(hour: 23, passed: 1), hours + 5, accuracy: 1E-9)
            XCTAssertEqual(average.value(hour: 23, passed: 1), InsulinStatsEngine.summary(days, period: nil).tdd!, accuracy: 1E-9)
        }
    }

    /// A day's insulin by the local clock time of `date` (`scaledInsulin(hour:passed:)` at its clock, as the card's).
    private func scaledInsulin(_ day: DayInsulin, at date: Date) -> Double {
        let clock = InsulinClockAverage.clock(of: date, calendar: calendar)
        return day.scaledInsulin(hour: clock.hour, passed: clock.passed)
    }

    /// A day's insulin by the clock time (the card's bars by now): the hours before it in full, its own prorated by the
    /// minutes passed; by the end of the day its TDD; the mean over the headline days is the usual (`clockAverage`).
    func testDayInsulinByTheClockTime() {
        let lunch = clock(6, 12, 30)
        let days = insulinPeriod(.days7, now: lunch).days
        let past = days[0]
        // 12 h at 1 U/h, 5 + 0.5 U, half of 12:00's 1 U
        XCTAssertEqual(scaledInsulin(past, at: lunch), 18, accuracy: 1E-9)
        XCTAssertEqual(past.scaledInsulin(hour: 12, passed: 0.5), 18, accuracy: 1E-9)
        // 8 h, half of 08:00's 1 + 5 U
        XCTAssertEqual(scaledInsulin(past, at: clock(6, 8, 30)), 11, accuracy: 1E-9)
        // the seconds count too: 12:45:30 is 0.758 of 12:00
        XCTAssertEqual(
            scaledInsulin(past, at: clock(6, 12, 45).addingTimeInterval(30)),
            17.5 + 45.5 / 60,
            accuracy: 1E-9
        )
        XCTAssertEqual(past.scaledInsulin(hour: 0, passed: 0), 0, accuracy: 1E-9)
        // the share clamped
        XCTAssertEqual(past.scaledInsulin(hour: 12, passed: 2), past.scaledInsulin(hour: 13, passed: 0), accuracy: 1E-9)
        // by the end of the day: the day's TDD
        XCTAssertEqual(past.scaledTotal, 29.5, accuracy: 1E-9)
        XCTAssertEqual(past.scaledInsulin(hour: 23, passed: 1), past.scaledTotal, accuracy: 1E-9)
        // the mean over the headline days: the usual
        let headline = days.filter(\.isHeadline)
        let average = InsulinStatsEngine.clockAverage(days)!
        for time in [clock(6, 0, 10), clock(6, 8, 30), lunch, clock(6, 23, 59)] {
            let mean = headline.reduce(0) { $0 + scaledInsulin($1, at: time) } / Double(headline.count)
            XCTAssertEqual(mean, average.value(at: time, calendar: calendar), accuracy: 1E-9)
        }
    }

    /// A partly covered day by the clock time: its basal scaled to the whole day by its covered time in every hour (as
    /// `scaledBasal`, the TDD's), the boluses as delivered.
    func testDayInsulinByTheClockTimeScalesByCoverage() {
        // day 1 covered in full; day 2 up to 18:00 (75%), its basal × 24 / 18
        let days = pastDays([day(1), day(2)], coveredHours: [nil, 18])
        let noon = clock(6, 12)
        XCTAssertEqual(days[0].scaledInsulin(hour: 12, passed: 0), 17, accuracy: 1E-9)
        // 12 × 4/3 + 5; delivered as is 17 (`deliveredInsulin`)
        XCTAssertEqual(days[1].scaledInsulin(hour: 12, passed: 0), 21, accuracy: 1E-9)
        XCTAssertEqual(days[1].deliveredInsulin(hour: 12, passed: 0), 17, accuracy: 1E-9)
        XCTAssertEqual(days[1].deliveredInsulin(hour: 12, passed: 0.5), 17.5, accuracy: 1E-9)
        XCTAssertEqual(days[1].deliveredInsulin(hour: 23, passed: 1), days[1].total, accuracy: 1E-9)
        XCTAssertEqual(days[1].total, 23, accuracy: 1E-9)
        // in full: the same
        XCTAssertEqual(days[0].deliveredInsulin(hour: 12, passed: 0), 17, accuracy: 1E-9)
        // by the end of the day: 24 + 5, the TDD
        XCTAssertEqual(days[1].scaledTotal, 29, accuracy: 1E-9)
        XCTAssertEqual(days[1].scaledInsulin(hour: 23, passed: 1), 29, accuracy: 1E-9)
        XCTAssertEqual(
            days.reduce(0) { $0 + $1.scaledTotal } / 2,
            InsulinStatsEngine.summary(days, period: nil).tdd!,
            accuracy: 1E-9
        )
        // the mean of the two by noon: the usual
        XCTAssertEqual(InsulinStatsEngine.clockAverage(days)!.value(at: noon, calendar: calendar), 19, accuracy: 1E-9)
    }

    /// The last N whole days end with today: 7 are the 7 d period's (6 and today), 8 the 7 before today and today;
    /// whole days across a DST change.
    func testTheLastDaysEndWithToday() {
        let lunch = clock(6, 12, 30)
        XCTAssertEqual(
            InsulinStatsEngine.lastDays(7, now: lunch, calendar: calendar),
            InsulinStatsEngine.periodDays(.days7, now: lunch, calendar: calendar)
        )
        let eight = InsulinStatsEngine.lastDays(8, now: lunch, calendar: calendar)
        XCTAssertEqual(eight.map(\.start), (-1 ... 6).map { day($0) })
        XCTAssertEqual(eight.last, DateInterval(start: day(6), end: day(7)))
        // at midnight the new day is today
        XCTAssertEqual(
            InsulinStatsEngine.lastDays(1, now: day(6), calendar: calendar),
            [DateInterval(start: day(6), end: day(7))]
        )
        // the fall-back day: 25 h
        let fallBack = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let after = calendar.date(byAdding: .day, value: 1, to: fallBack)!.addingTimeInterval(.hours(12))
        XCTAssertEqual(InsulinStatsEngine.lastDays(3, now: after, calendar: calendar).map(\.duration), [
            .hours(24),
            .hours(25),
            .hours(24)
        ])
        XCTAssertEqual(InsulinStatsEngine.lastDays(0, now: lunch, calendar: calendar), [])
    }

    /// Home's insulin card read (`InsulinStatsService.days(last: 8)`): the 7 days before today and today (offsets
    /// -1 ... 6 from `week`, today the 16th) up to `now`, as `insulinPeriod`'s: a flat 1 U/h, a 5 U bolus at 08:00 and a
    /// 0.5 U SMB at 09:00 on each of the `withData` days, covered but `uncovered`; `evening`: (offset + 1) U more at
    /// 18:00 on the past days (their whole days differ, not by noon); `extraToday` U at 10:00 today; `coveredHours`: a
    /// day covered only that many hours from its start; `bolusFree`: days without the boluses; `extra` events.
    private func cardDays(
        now: Date,
        withData: [Int] = Array(-1 ... 6),
        uncovered: Set<Int> = [],
        coveredHours: [Int: Double] = [:],
        bolusFree: Set<Int> = [],
        evening: Bool = false,
        extraToday: Double = 0,
        extra: [PumpEventRecord] = []
    ) -> [DayInsulin] {
        var events: [PumpEventRecord] = extra
        var rows: [CoveredInterval] = []
        for offset in withData {
            if clock(offset, 9) <= now, !bolusFree.contains(offset) {
                events += [bolus(clock(offset, 8), 5), bolus(clock(offset, 9), 0.5, smb: true)]
            }
            if evening, (0 ..< 6).contains(offset) {
                events.append(bolus(clock(offset, 18), Double(offset + 1)))
            }
            if !uncovered.contains(offset) {
                let end = coveredHours[offset].map { day(offset).addingTimeInterval(.hours($0)) } ?? day(offset + 1)
                rows.append(coverage(day(offset), Swift.min(end, now)))
            }
        }
        if extraToday > 0 {
            events.append(bolus(clock(6, 10), extraToday))
        }
        let input = InsulinInput(events: events, coverage: rows, schedules: [flatSchedule])
        let days = InsulinStatsEngine.lastDays(InsulinCard.pastDays + 1, now: now, calendar: calendar)
        return InsulinStatsEngine.days(days, input: input, now: now, calendar: calendar)
    }

    /// A value as a share of the card's plot whose tallest is `top` (with the headroom), rounded as the card's.
    private func share(_ value: Double, top: Double) -> Double {
        (value / (top * InsulinCard.headroom) / InsulinCard.fractionStep).rounded() * InsulinCard.fractionStep
    }

    /// Today at 12:30, the 7 days before it whole 29.5 to 35.5 U (by 12:30 18.0 U each): so far 18.0 U; the bars, their
    /// whole day and by now (no value printed on yesterday's); yesterday by 12:30 under so far; the mean day 32.5 U
    /// ("daily avg"), the usual by 12:30 18.0 U, on the rail; the weekdays.
    @MainActor func testHomeInsulinCard() {
        XCTAssertEqual(InsulinCard.pastDays, 7)
        let lunch = clock(6, 12, 30)
        let card = InsulinCard(days: cardDays(now: lunch, evening: true), now: lunch, calendar: calendar)
        XCTAssertEqual(card.title, "Insulin")
        XCTAssertEqual(card.value, d("18.0"))
        XCTAssertFalse(card.isLimited)

        // the top: the tallest whole day, the 15th's 35.5 U
        let top = 35.5
        XCTAssertEqual(card.days.count, 7)
        XCTAssertEqual(card.days.map(\.whole), (0 ..< 7).map { Double?(share(29.5 + Double($0), top: top)) })
        XCTAssertEqual(card.days[0].whole ?? 0, 0.799, accuracy: 1E-9)
        XCTAssertEqual(card.days[6].whole ?? 0, 0.962, accuracy: 1E-9)
        XCTAssertEqual(card.days.map(\.byNow), [Double?](repeating: share(18, top: top), count: 7))
        // yesterday by now: under so far, in the read's clock format, not on its bar
        let time = InsulinCard.clockTime(lunch, calendar: calendar)
        XCTAssertEqual(card.yesterday, InsulinCard.Yesterday(label: "yesterday by \(time)", value: d("18.0 U")))
        XCTAssertEqual(Mirror(reflecting: card.days[6]).children.map(\.label), ["label", "whole", "byNow", "wholeText"])
        // each day's whole day above its bar, over 20 U in whole units: 29.5 to 35.5 U half away from zero, "30" to "36"
        XCTAssertEqual(card.days.map(\.wholeText), (30 ... 36).map { String?("\($0)") })
        // Friday the 9th to Thursday the 15th, then Today
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        XCTAssertEqual(card.days.map(\.label), [6, 7, 1, 2, 3, 4, 5].map { symbols[$0 - 1] })
        XCTAssertEqual(card.todayLabel, "Today")

        XCTAssertEqual(
            card.today,
            InsulinCard.Today(soFar: share(18, top: top), meanDay: share(32.5, top: top), usual: share(18, top: top))
        )
        XCTAssertFalse(HomeInsulinChart.drawsMeanDayLine(card.today))
        XCTAssertEqual(card.rail.map(\.name), ["daily avg", "usual"])
        XCTAssertEqual(card.rail.map(\.value), [d("32.5"), d("18.0")])
        XCTAssertEqual(card.rail.map(\.height), [share(32.5, top: top), share(18, top: top)])
    }

    /// As of the read's time: the 12:30 data read at 13:15 (no newer data yet) shows so far as read, the days and the
    /// usual by 13:15 (12 + 5.5 + 1 + a quarter of 13:00's 1 U), to the minute.
    @MainActor func testHomeInsulinCardAsOfTheReadTime() {
        let days = cardDays(now: clock(6, 12, 30))
        let at1230 = InsulinCard(days: days, now: clock(6, 12, 30), calendar: calendar)
        let later = InsulinCard(days: days, now: clock(6, 13, 15).addingTimeInterval(40), calendar: calendar)
        XCTAssertEqual(later.value, at1230.value)
        XCTAssertEqual(later.today.soFar, at1230.today.soFar)
        // every day whole 29.5 U
        XCTAssertEqual(later.days.map(\.byNow), [Double?](repeating: share(18.75, top: 29.5), count: 7))
        XCTAssertEqual(later.rail.map(\.value), [d("29.5"), d("18.8")])
        let time = InsulinCard.clockTime(clock(6, 13, 15), calendar: calendar)
        XCTAssertEqual(later.yesterday, InsulinCard.Yesterday(label: "yesterday by \(time)", value: d("18.8 U")))
        XCTAssertNotEqual(later, at1230)
    }

    /// So far above the mean day: the top is so far's (nothing clips), the fill past the outline (its top drawn across
    /// the fill), the mean day and the usual labelled inside the fill. Just below the mean day (within the outline's
    /// stroke, in points): the line too.
    @MainActor func testHomeInsulinCardPastTheMeanDay() {
        let lunch = clock(6, 12, 30)
        let card = InsulinCard(days: cardDays(now: lunch, extraToday: 15), now: lunch, calendar: calendar)
        // 18.0 + 15 U so far
        XCTAssertEqual(card.value, d("33.0"))
        let top = 33.0
        XCTAssertEqual(card.today.soFar ?? 0, 0.962, accuracy: 1E-9)
        XCTAssertEqual(card.today.meanDay, share(29.5, top: top))
        XCTAssertEqual(card.today.usual, share(18, top: top))
        XCTAssertTrue(HomeInsulinChart.drawsMeanDayLine(card.today))
        XCTAssertEqual(card.days.map(\.whole), [Double?](repeating: share(29.5, top: top), count: 7))
        XCTAssertEqual(card.rail.map(\.height), [share(29.5, top: top), share(18, top: top)])
        XCTAssertTrue(card.rail.allSatisfy { $0.height < card.today.soFar ?? 0 })
        // at the mean day exactly: the line (the fill covers the outline's top)
        func line(_ soFar: Double?, _ meanDay: Double?) -> Bool {
            HomeInsulinChart.drawsMeanDayLine(InsulinCard.Today(soFar: soFar, meanDay: meanDay, usual: 0.3))
        }
        XCTAssertTrue(line(0.5, 0.5))
        // just below it, within the stroke's reach (2 pt of the 84 pt plot: 0.024): the line too; further below, not
        let plot = HomeInsulinChart.plotHeight - HomeInsulinChart.topInset
        XCTAssertEqual(HomeInsulinChart.meanDayLineReach / plot, 2 / 84, accuracy: 1E-9)
        XCTAssertTrue(line(0.49, 0.5))
        XCTAssertTrue(line(0.477, 0.5))
        XCTAssertFalse(line(0.47, 0.5))
        XCTAssertFalse(line(0.3, 0.5))
        XCTAssertFalse(line(nil, 0.5))
        XCTAssertFalse(line(0.5, nil))
        // so far a moment below the mean day by the data: just below it on the card, the line drawn
        let close = InsulinCard(days: cardDays(now: lunch, extraToday: 11), now: lunch, calendar: calendar)
        XCTAssertLessThan(close.today.soFar ?? 1, close.today.meanDay ?? 0)
        XCTAssertTrue(HomeInsulinChart.drawsMeanDayLine(close.today))
    }

    /// Pump data only from the 13th: the 4 days before a dash, the mean day over the 3 complete ones ("3 d avg"), the
    /// limited marker, yesterday by now.
    @MainActor func testHomeInsulinCardWithThreeCompleteDays() {
        let lunch = clock(6, 12, 30)
        let card = InsulinCard(days: cardDays(now: lunch, withData: [3, 4, 5, 6]), now: lunch, calendar: calendar)
        XCTAssertTrue(card.isLimited)
        XCTAssertEqual(card.days.map { $0.whole == nil }, [true, true, true, true, false, false, false])
        XCTAssertEqual(card.days.prefix(4).map(\.byNow), [nil, nil, nil, nil])
        XCTAssertEqual(card.yesterday?.value, d("18.0 U"))
        XCTAssertEqual(card.rail.map(\.name), ["3 d avg", "usual"])
        XCTAssertEqual(card.rail.map(\.value), [d("29.5"), d("18.0")])
    }

    /// A past day without coverage (its boluses alone): a bar of them, no complete day ("6 d avg").
    @MainActor func testHomeInsulinCardADayWithoutCoverage() {
        let lunch = clock(6, 12, 30)
        let card = InsulinCard(days: cardDays(now: lunch, uncovered: [2]), now: lunch, calendar: calendar)
        // the 12th: 5 + 0.5 U, all by 12:30
        XCTAssertEqual(card.days[3].whole, share(5.5, top: 29.5))
        XCTAssertEqual(card.days[3].byNow, share(5.5, top: 29.5))
        XCTAssertTrue(card.isLimited)
        XCTAssertEqual(card.rail.map(\.name), ["6 d avg", "usual"])
        XCTAssertEqual(card.rail.map(\.value), [d("29.5"), d("18.0")])
    }

    /// No pump data yesterday (the others with): its dash, no yesterday line under so far; the rest as ever.
    @MainActor func testHomeInsulinCardWithoutYesterday() {
        let lunch = clock(6, 12, 30)
        let card = InsulinCard(days: cardDays(now: lunch, withData: [-1, 0, 1, 2, 3, 4, 6]), now: lunch, calendar: calendar)
        XCTAssertNil(card.days.last?.whole)
        XCTAssertNil(card.yesterday)
        XCTAssertEqual(card.value, d("18.0"))
        XCTAssertEqual(card.rail.map(\.name), ["6 d avg", "usual"])
    }

    /// A past day barely covered (3 h, 12.5%) running a high temp: no complete day, so drawn as delivered (not its
    /// basal × 8), and it doesn't set the top: the complete days aren't flattened. Delivered above them, it is clipped
    /// at the top, which stays theirs.
    @MainActor func testHomeInsulinCardABarelyCoveredDayIsDrawnAsDelivered() {
        let lunch = clock(6, 12, 30)
        func card(rate: Double) -> InsulinCard {
            // the 12th: 00:00–03:00 covered, a temp at `rate` U/h 01:00–03:00
            let temp = PumpEventRecord(
                date: clock(2, 1),
                kind: .tempBasal,
                source: .pump,
                units: -1,
                rate: rate,
                durationMin: 120.1
            )
            let days = cardDays(now: lunch, coveredHours: [2: 3], extra: [temp])
            XCTAssertFalse(days[3].isHeadline)
            XCTAssertEqual(days[3].coverageFraction, 0.125, accuracy: 1E-9)
            // scaled it would be 8 × its basal
            XCTAssertEqual(days[3].scaledBasal, 8 * days[3].basal, accuracy: 1E-9)
            return InsulinCard(days: days, now: lunch, calendar: calendar)
        }

        // 1 + 2 × 10 U basal, 5 + 0.5 U: 26.5 U, all of it by 12:30; the top the complete days' 29.5 U
        let high = card(rate: 10)
        XCTAssertEqual(high.days[3].whole, share(26.5, top: 29.5))
        XCTAssertEqual(high.days[3].byNow, share(26.5, top: 29.5))
        XCTAssertEqual(high.days.enumerated().filter { $0.offset != 3 }.map(\.element.whole), [Double?](
            repeating: share(29.5, top: 29.5),
            count: 6
        ))
        XCTAssertEqual(high.days[0].byNow, share(18, top: 29.5))
        XCTAssertTrue(high.isLimited)
        XCTAssertEqual(high.rail.map(\.name), ["6 d avg", "usual"])
        XCTAssertEqual(high.rail.map(\.value), [d("29.5"), d("18.0")])

        // 1 + 2 × 30 + 5.5 = 66.5 U: above the complete days, clipped at the top; the others as before
        let higher = card(rate: 30)
        XCTAssertEqual(higher.days[3].whole ?? 0, 1, accuracy: 1E-9)
        XCTAssertEqual(higher.days[3].byNow ?? 0, 1, accuracy: 1E-9)
        XCTAssertEqual(higher.days[0].whole, share(29.5, top: 29.5))
        XCTAssertEqual(higher.today.meanDay, share(29.5, top: 29.5))
    }

    /// A day with pump data but no insulin (suspended all day): 0 U, not a "no pump data" dash: a stub of the bar in the
    /// insulin colour (`HomeInsulinChart.barHeight`), as today's fill at 0 U.
    @MainActor func testHomeInsulinCardADayWithoutInsulin() {
        let lunch = clock(6, 12, 30)
        let suspended = [
            PumpEventRecord(date: day(-1), kind: .suspend, source: .pump),
            PumpEventRecord(date: day(0), kind: .resume, source: .pump)
        ]
        let days = cardDays(now: lunch, bolusFree: [-1], extra: suspended)
        XCTAssertTrue(days[0].hasData)
        XCTAssertEqual(days[0].total, 0, accuracy: 1E-9)
        let card = InsulinCard(days: days, now: lunch, calendar: calendar)
        XCTAssertEqual(card.days[0].whole, 0)
        XCTAssertEqual(card.days[0].byNow, 0)
        // pump data: its total, 0 (up to 20 U with a decimal)
        XCTAssertEqual(card.days[0].wholeText, d("0.0"))
        // the other days as ever
        XCTAssertEqual(card.days[1].whole, share(29.5, top: 29.5))

        // the stub: 1 pt, under it a bar is drawn as the stub; above it, as tall as it is
        XCTAssertEqual(HomeInsulinChart.stubHeight, 1)
        XCTAssertEqual(HomeInsulinChart.barHeight(0).height, 1)
        XCTAssertTrue(HomeInsulinChart.barHeight(0).isStub)
        XCTAssertTrue(HomeInsulinChart.barHeight(0.01).isStub)
        XCTAssertEqual(HomeInsulinChart.barHeight(0.5).height, 42, accuracy: 1E-9)
        XCTAssertFalse(HomeInsulinChart.barHeight(0.5).isStub)
        XCTAssertFalse(HomeInsulinChart.barHeight(1 / 84).isStub)
    }

    /// Statistics › Insulin › Today and Home's card read the same 7 days before today (`InsulinStatsEngine.usualDays`):
    /// the same usual by now, also when the oldest of them differs from the others (a 7 d period, 6 and today, would
    /// leave it out).
    @MainActor func testStatisticsTodaysUsualIsHomes() {
        XCTAssertEqual(InsulinCard.pastDays, InsulinStatsEngine.usualDays)
        let lunch = clock(6, 12, 30)
        // the 9th, the oldest: 7 U more at 10:00; by 12:30 (18 + 7 + 6 × 18) / 7 = 19.0 U
        let days = cardDays(now: lunch, extra: [bolus(clock(-1, 10), 7)])
        XCTAssertEqual(days.count, 8)
        let home = InsulinCard(days: days, now: lunch, calendar: calendar)
        let result = Stat.InsulinResult(period: .days7, insulin: todayRead(days), shown: .today, asOf: lunch, calendar: calendar)
        let today = Stat.Insulin(result, calendar: calendar).today!
        XCTAssertEqual(today.usual, d("19.0 U"))
        XCTAssertEqual(home.rail.last?.name, "usual")
        XCTAssertEqual(home.rail.last?.value, d("19.0"))
        // the label unchanged: 7 d
        XCTAssertEqual(today.usualTitle, "Usual by \(lunch.formatted(date: .omitted, time: .shortened)) · 7 d")
        // the test read is the Today read: the 7 days before today and today
        XCTAssertEqual(insulinPeriod(.today, now: lunch).days.map(\.day.start), (-1 ... 6).map { day($0) })
        // the 7 d period's 6 days: 18.0 U
        let week = Stat.InsulinResult(
            period: .days7,
            insulin: todayRead(Array(days.dropFirst())),
            shown: .today,
            asOf: lunch,
            calendar: calendar
        )
        XCTAssertEqual(Stat.Insulin(week, calendar: calendar).today?.usual, d("18.0 U"))
    }

    /// No pump data at all: "–", every day a dash, today without a bar, nothing on the rail.
    @MainActor func testHomeInsulinCardWithoutData() {
        let card = InsulinCard(days: cardDays(now: now, withData: []), now: now, calendar: calendar)
        XCTAssertEqual(card.value, "–")
        XCTAssertTrue(card.isLimited)
        XCTAssertEqual(card.days.count, 7)
        XCTAssertTrue(card.days.allSatisfy { $0.whole == nil && $0.byNow == nil })
        XCTAssertNil(card.yesterday)
        XCTAssertTrue(card.days.allSatisfy { $0.wholeText == nil })
        XCTAssertEqual(card.today, InsulinCard.Today(soFar: nil, meanDay: nil, usual: nil))
        XCTAssertEqual(card.rail, [])
        // no days at all (not expected)
        let none = InsulinCard(days: [], now: now, calendar: calendar)
        XCTAssertEqual(none.value, "–")
        XCTAssertEqual(none.days, [])
        XCTAssertEqual(none.rail, [])
        XCTAssertNil(none.yesterday)
    }

    /// Early in the morning, 00:30: half an hour so far, by now on every day, the usual; the mean day the whole day's.
    @MainActor func testHomeInsulinCardEarlyInTheMorning() {
        let early = clock(6, 0, 30)
        let card = InsulinCard(days: cardDays(now: early), now: early, calendar: calendar)
        XCTAssertEqual(card.value, d("0.5"))
        let top = 29.5
        XCTAssertEqual(
            card.today,
            InsulinCard.Today(soFar: share(0.5, top: top), meanDay: share(29.5, top: top), usual: share(0.5, top: top))
        )
        XCTAssertEqual(card.days.map(\.byNow), [Double?](repeating: share(0.5, top: top), count: 7))
        XCTAssertEqual(card.days.map(\.whole), [Double?](repeating: share(29.5, top: top), count: 7))
        let time = InsulinCard.clockTime(early, calendar: calendar)
        XCTAssertEqual(card.yesterday, InsulinCard.Yesterday(label: "yesterday by \(time)", value: d("0.5 U")))
        XCTAssertEqual(card.rail.map(\.value), [d("29.5"), d("0.5")])
    }

    /// The rail's labels: at their marks, pushed apart top to bottom by the gap, inside the plot (the last one pulled up,
    /// the ones above with it); in the order given.
    func testHomeInsulinRailLabelsPushedApart() {
        func place(_ ys: [CGFloat]) -> [CGFloat] {
            HomeInsulinChart.railPositions(ys, gap: 13, minY: 6.5, maxY: 85.5)
        }
        // apart already: where they are
        XCTAssertEqual(place([20, 60]), [20, 60])
        // in the order given, the lower one pushed down
        XCTAssertEqual(place([50, 40]), [53, 40])
        // at the top: not above minY
        XCTAssertEqual(place([2, 3]), [6.5, 19.5])
        // at the bottom: the last one pulled up to maxY, the one above with it, the top one left
        XCTAssertEqual(place([10, 88, 89]), [10, 72.5, 85.5])
        XCTAssertEqual(place([]), [])
    }

    /// The usual: a thin tick on each side of today's bar, outside its edges, centred on the usual's height; the
    /// leaders start past the right one, 3 pt clear of it (one at the usual's height is in line with it), and end
    /// before the labels.
    func testHomeInsulinUsualTicks() {
        let ticks = HomeInsulinChart.usualTicks(barX: 100, barWidth: 28, y: 40)
        XCTAssertEqual(ticks.count, 2)
        let (left, right) = (ticks[0], ticks[1])
        XCTAssertEqual(left, CGRect(x: 94.5, y: 39.25, width: 4, height: 1.5))
        XCTAssertEqual(right, CGRect(x: 129.5, y: 39.25, width: 4, height: 1.5))
        // outside the bar, both
        XCTAssertLessThan(left.maxX, 100)
        XCTAssertGreaterThan(right.minX, 128)
        XCTAssertEqual(left.midY, 40)
        XCTAssertEqual(right.midY, 40)
        XCTAssertGreaterThanOrEqual(HomeInsulinChart.leaderStart - (right.maxX - 128), 3)
        XCTAssertEqual(HomeInsulinChart.leaderStart, 8.5)
        // the leader's level part, then its slanted part to the label, as long as before the clearance
        XCTAssertLessThan(HomeInsulinChart.leaderStart + 2, HomeInsulinChart.leaderSpace - 3)
        XCTAssertEqual(HomeInsulinChart.leaderSpace - 3 - (HomeInsulinChart.leaderStart + 2), 4.5)
    }

    /// A past day's total, rotated above its bar: `totalGap` above the bar; not when it is thicker than its slot (less
    /// 1 pt) or longer than the room above. A bar of the plot's
    /// tallest (1 / headroom of it) leaves room for a total at the default size, measured: inside the canvas.
    func testHomeInsulinTotalLabelLayout() {
        XCTAssertEqual(HomeInsulinChart.totalGap, 4)
        let size = CGSize(width: 22, height: 13)
        // above the bar
        XCTAssertEqual(HomeInsulinChart.totalLabelBottom(barTop: 50, size: size, slot: 28), 46)
        // just fits: its length up to the canvas's top
        XCTAssertEqual(HomeInsulinChart.totalLabelBottom(barTop: 26, size: size, slot: 28), 22)
        // too long for the room above, too thick for the slot: skipped
        XCTAssertNil(HomeInsulinChart.totalLabelBottom(barTop: 25, size: size, slot: 28))
        XCTAssertNil(HomeInsulinChart.totalLabelBottom(barTop: 50, size: size, slot: 13.5))
        XCTAssertNotNil(HomeInsulinChart.totalLabelBottom(barTop: 50, size: size, slot: 14))

        // the tallest bar's top (1 / headroom, as rounded to the fraction step) leaves the room for the longest total
        // with a decimal ("18.8", every digit as wide; the tallest bar on a card of low totals) at the default size, a
        // step under caption2, and the gap: drawn, its start the gap above the bar, its end inside the canvas; the bars
        // as tall as before
        let caption2 = UIFont.preferredFont(
            forTextStyle: .caption2,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        XCTAssertEqual(HomeInsulinChart.totalFontSize, caption2.pointSize - 1)
        let font = UIFont.monospacedDigitSystemFont(ofSize: HomeInsulinChart.totalFontSize, weight: .regular)
        let longest = InsulinCard.totalText(18.8)
        XCTAssertEqual(longest, d("18.8"))
        let total = (longest as NSString).size(withAttributes: [.font: font])
        let fraction = (1 / InsulinCard.headroom / InsulinCard.fractionStep).rounded() * InsulinCard.fractionStep
        let tallest = HomeInsulinChart.plotHeight - HomeInsulinChart.height(fraction)
        let bottom = HomeInsulinChart.totalLabelBottom(barTop: tallest, size: total, slot: 30)
        XCTAssertEqual(bottom, tallest - HomeInsulinChart.totalGap)
        XCTAssertLessThanOrEqual(bottom ?? .infinity, tallest - 4)
        XCTAssertGreaterThanOrEqual((bottom ?? 0) - total.width, 0)
        func measured(_ whole: Double) -> CGSize {
            (InsulinCard.totalText(whole) as NSString).size(withAttributes: [.font: font])
        }
        // shorter: two and three digits, drawn
        XCTAssertLessThan(measured(99.4).width, total.width)
        XCTAssertLessThan(measured(999).width, total.width)
        XCTAssertEqual(InsulinCard.totalText(102.5), "103")
        XCTAssertNotNil(HomeInsulinChart.totalLabelBottom(barTop: tallest, size: measured(102.5), slot: 30))
        XCTAssertNotNil(HomeInsulinChart.totalLabelBottom(barTop: tallest, size: measured(199.4), slot: 30))
        // a four-digit total doesn't fit: skipped, not clipped
        XCTAssertNil(HomeInsulinChart.totalLabelBottom(barTop: tallest, size: measured(1000), slot: 30))
        XCTAssertEqual(HomeInsulinChart.plotHeight - HomeInsulinChart.topInset, 84)
        XCTAssertEqual(HomeInsulinChart.topInset, 25)
    }

    /// A past day's total without the unit, rounded half away from zero (`StatsAmount.number`), as the locale writes
    /// numbers: up to 20 U (the unrounded total) with a decimal, above it in whole units.
    func testHomeInsulinTotalText() {
        XCTAssertEqual(InsulinCard.totalDecimalLimit, 20)
        XCTAssertEqual(InsulinCard.totalText(45.4), "45")
        XCTAssertEqual(InsulinCard.totalText(45.5), "46")
        XCTAssertEqual(InsulinCard.totalText(45.49), "45")
        XCTAssertEqual(InsulinCard.totalText(102.5), "103")
        // the boundary: by the unrounded total
        XCTAssertEqual(InsulinCard.totalText(20.04), "20")
        XCTAssertEqual(InsulinCard.totalText(20.0), d("20.0"))
        XCTAssertEqual(InsulinCard.totalText(19.96), d("20.0"))
        XCTAssertEqual(InsulinCard.totalText(18.44), d("18.4"))
        XCTAssertEqual(InsulinCard.totalText(0.4), d("0.4"))
        XCTAssertEqual(InsulinCard.totalText(0), d("0.0"))
    }

    // MARK: - Home cards' display choices

    /// An empty store of its own, removed after the test
    private func displayPreferences() -> StatsDisplayPreferences {
        let name = "test-stats-display-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return StatsDisplayPreferences(defaults: defaults)
    }

    /// Nothing stored (a fresh install's, a tester's after the choices left the settings): the stats bar on 24 h, both
    /// On board lanes on, the usual day off over the last 14 days.
    func testStatsDisplayPreferencesDefaults() {
        XCTAssertEqual(StatsPeriod.homeStatsRanges, [.today, .last24h])
        let preferences = displayPreferences()
        XCTAssertEqual(preferences.homeStatsRange, .last24h)
        XCTAssertTrue(preferences.homeOnBoardGlucose)
        XCTAssertTrue(preferences.homeOnBoardCOB)
        XCTAssertFalse(preferences.usualDayShown)
        XCTAssertEqual(preferences.usualDayPeriod, .days14)
    }

    /// Written and read back, also by another store on the same defaults (the next launch), under the keys.
    func testStatsDisplayPreferencesRoundTrip() {
        let preferences = displayPreferences()
        for range in StatsPeriod.homeStatsRanges {
            preferences.homeStatsRange = range
            XCTAssertEqual(preferences.homeStatsRange, range)
        }
        for period in StatsPeriod.usualDayPeriods {
            preferences.usualDayPeriod = period
            XCTAssertEqual(preferences.usualDayPeriod, period)
        }
        preferences.homeStatsRange = .today
        preferences.homeOnBoardGlucose = false
        preferences.homeOnBoardCOB = false
        preferences.usualDayShown = true
        preferences.usualDayPeriod = .days30

        let next = StatsDisplayPreferences(defaults: preferences.defaults)
        XCTAssertEqual(next.homeStatsRange, .today)
        XCTAssertFalse(next.homeOnBoardGlucose)
        XCTAssertFalse(next.homeOnBoardCOB)
        XCTAssertTrue(next.usualDayShown)
        XCTAssertEqual(next.usualDayPeriod, .days30)

        typealias Key = StatsDisplayPreferences.Key
        let defaults = preferences.defaults
        XCTAssertEqual(defaults.string(forKey: Key.homeStatsRange), "today")
        XCTAssertEqual(defaults.object(forKey: Key.homeOnBoardGlucose) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: Key.homeOnBoardCOB) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: Key.usualDayShown) as? Bool, true)
        XCTAssertEqual(defaults.string(forKey: Key.usualDayPeriod), "days30")
        let keys = [Key.homeStatsRange, Key.homeOnBoardGlucose, Key.homeOnBoardCOB, Key.usualDayShown, Key.usualDayPeriod]
        for key in keys {
            XCTAssertTrue(key.hasPrefix("iAPS.stats."), key)
        }
    }

    /// The stats bar's "Show TITR": off by default, kept, and a stored value of another type reads as off.
    func testStatsDisplayPreferencesTITR() {
        let preferences = displayPreferences()
        XCTAssertFalse(preferences.homeStatsTITR)
        preferences.homeStatsTITR = true
        XCTAssertTrue(StatsDisplayPreferences(defaults: preferences.defaults).homeStatsTITR)
        XCTAssertEqual(preferences.defaults.object(forKey: StatsDisplayPreferences.Key.homeStatsTITR) as? Bool, true)
        XCTAssertTrue(StatsDisplayPreferences.Key.homeStatsTITR.hasPrefix("iAPS.stats."))
        preferences.homeStatsTITR = false
        XCTAssertFalse(preferences.homeStatsTITR)
        preferences.defaults.set("on", forKey: StatsDisplayPreferences.Key.homeStatsTITR)
        XCTAssertFalse(preferences.homeStatsTITR)
    }

    /// Only a value the choice offers: a stored one it doesn't (an older build's 7–90 d, another view's period, an
    /// unknown raw value, another type) reads as the default, and one it doesn't offer is never written.
    func testStatsDisplayPreferencesInvalidValues() {
        typealias Key = StatsDisplayPreferences.Key
        let preferences = displayPreferences()
        let defaults = preferences.defaults
        for raw in ["days7", "days14", "days90", "weeks13", "days365", ""] {
            defaults.set(raw, forKey: Key.homeStatsRange)
            XCTAssertEqual(preferences.homeStatsRange, .last24h, raw)
        }
        for raw in ["today", "last24h", "days7", "weeks8", "days365", ""] {
            defaults.set(raw, forKey: Key.usualDayPeriod)
            XCTAssertEqual(preferences.usualDayPeriod, .days14, raw)
        }
        defaults.set(3, forKey: Key.homeStatsRange)
        XCTAssertEqual(preferences.homeStatsRange, .last24h)
        defaults.set("off", forKey: Key.homeOnBoardGlucose)
        defaults.set("off", forKey: Key.homeOnBoardCOB)
        defaults.set("on", forKey: Key.usualDayShown)
        XCTAssertTrue(preferences.homeOnBoardGlucose)
        XCTAssertTrue(preferences.homeOnBoardCOB)
        XCTAssertFalse(preferences.usualDayShown)

        // not offered: the stored value stays
        preferences.homeStatsRange = .today
        preferences.homeStatsRange = .days7
        XCTAssertEqual(preferences.homeStatsRange, .today)
        XCTAssertEqual(defaults.string(forKey: Key.homeStatsRange), "today")
        preferences.usualDayPeriod = .days30
        preferences.usualDayPeriod = .last24h
        XCTAssertEqual(preferences.usualDayPeriod, .days30)
        XCTAssertEqual(defaults.string(forKey: Key.usualDayPeriod), "days30")
    }

    /// The display choices aren't settings: an older build's file with their keys (and the earlier builds' removed
    /// ones) reads as before without them, and they are never written again. Their values aren't carried over: they
    /// were never released, so they start at the defaults once.
    func testStatsDisplayChoicesAreNotSettings() throws {
        let moved = ["homeStatsRange", "homeOnBoardGlucose", "homeOnBoardCOB", "statsUsualDay", "statsUsualDayPeriod"]
        let removed = ["homeStatsDisplay", "homeLoopsRange", "homeMealsRange", "homeInsulinRange", "skipGlucoseChart"]
        let oldFile = try FreeAPSSettings.decodeFrom(json: #"""
        {"homeStatsRange": "today", "homeOnBoardGlucose": false, "homeOnBoardCOB": false, "statsUsualDay": true,
         "statsUsualDayPeriod": "days30", "homeStatsDisplay": "averages", "homeLoopsRange": "days7",
         "homeMealsRange": "days90", "homeInsulinRange": "days30", "skipGlucoseChart": true, "hours": 9}
        """#)
        XCTAssertEqual(oldFile.hours, 9)
        XCTAssertEqual(oldFile, try FreeAPSSettings.decodeFrom(json: #"{"hours": 9}"#))
        for key in moved + removed {
            XCTAssertNil(oldFile.dictionaryRepresentation?[key], key)
            XCTAssertNil(FreeAPSSettings().dictionaryRepresentation?[key], key)
        }
    }

    /// The stats bar's config: its range and the settings' stats part (the bands, the HbA1c unit); the Loops card's
    /// follows the 1-minute loop alone, which the stats bar's doesn't.
    func testHomeCardConfigs() {
        let settings = FreeAPSSettings()
        let stats = Stat.StatsSettings(settings)
        XCTAssertNotEqual(
            Home.StatsConfig(range: .today, settings: stats),
            Home.StatsConfig(range: .last24h, settings: stats)
        )
        var oneMinute = settings
        oneMinute.allowOneMinuteLoop.toggle()
        XCTAssertNotEqual(Home.LoopsConfig(oneMinute), Home.LoopsConfig(settings))
        XCTAssertEqual(Stat.StatsSettings(oneMinute), stats)
        // the Loops card's one range
        XCTAssertEqual(Home.loopsRange, .last24h)
    }

    // MARK: - Home On board card

    private typealias OnBoard = HomeOnBoardCard.Content

    /// The lanes' y domains: the IOB chart's rule (min(0, lowest × 1.3) ... highest × 1.1, at least 1 U tall, 0 always
    /// inside), COB 0 ... highest × 1.1 (at least 10 g), glucose min(low − 10, lowest × 0.9) ... max(high + 20, highest ×
    /// 1.05) mg/dL (70–180: 60 ... 200).
    func testOnBoardDomains() {
        func assertDomain(
            _ domain: ClosedRange<Double>,
            _ lower: Double,
            _ upper: Double,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(domain.lowerBound, lower, accuracy: 1E-9, file: file, line: line)
            XCTAssertEqual(domain.upperBound, upper, accuracy: 1E-9, file: file, line: line)
        }
        assertDomain(OnBoard.iobDomain([]), 0, 1)
        assertDomain(OnBoard.iobDomain([1, 2]), 0, 2.2)
        assertDomain(OnBoard.iobDomain([-0.5, 3]), -0.65, 3.3)
        assertDomain(OnBoard.iobDomain([0.2, 0.5]), 0, 1)
        // all below zero: up to 0 at least (the areas' base), 1 U tall
        assertDomain(OnBoard.iobDomain([-1, -0.5]), -1.3, 0)
        assertDomain(OnBoard.iobDomain([-3, -2]), -3.9, 0)
        assertDomain(OnBoard.iobDomain([-0.5, -0.2]), -0.65, 0.35)

        assertDomain(OnBoard.cobDomain([]), 0, 10)
        assertDomain(OnBoard.cobDomain([0, 0]), 0, 10)
        assertDomain(OnBoard.cobDomain([0, 40]), 0, 44)

        assertDomain(OnBoard.glucoseDomain([], inRange: 70 ... 180), 60, 200)
        assertDomain(OnBoard.glucoseDomain([100, 150], inRange: 70 ... 180), 60, 200)
        assertDomain(OnBoard.glucoseDomain([40, 300], inRange: 70 ... 180), 36, 315)
        // the user's band: its rules inside (10 below, 20 above at least)
        assertDomain(OnBoard.glucoseDomain([100, 150], inRange: 80 ... 250), 70, 270)
        assertDomain(OnBoard.glucoseDomain([100, 150], inRange: 65 ... 140), 55, 160)
    }

    /// About three round values inside the domain (a step of 1, 2, 2.5 or 5 × 10ⁿ), never -0; the unit on the top one.
    func testOnBoardTicks() {
        XCTAssertEqual(OnBoard.ticks(0 ... 44), [0, 20, 40])
        XCTAssertEqual(OnBoard.ticks(0 ... 10), [0, 5, 10])
        XCTAssertEqual(OnBoard.ticks(0 ... 1), [0, 0.5, 1])
        XCTAssertEqual(OnBoard.ticks(-0.65 ... 3.3), [0, 2])
        XCTAssertEqual(OnBoard.ticks(-1.3 ... -0.3), [-1, -0.5])
        XCTAssertEqual(OnBoard.ticks(-2.6 ... 3.3), [-2.5, 0, 2.5])
        XCTAssertEqual(OnBoard.ticks(0 ... 0), [])
        // the first one from just below zero: 0, not -0
        XCTAssertEqual(OnBoard.ticks(-0.39 ... 3.3).first?.sign, .plus)

        XCTAssertEqual(OnBoard.niceStep(17.6), 20)
        XCTAssertEqual(OnBoard.niceStep(1.58), 2)
        XCTAssertEqual(OnBoard.niceStep(0.4), 0.5, accuracy: 1E-12)
        XCTAssertEqual(OnBoard.niceStep(2.2), 2.5)
        XCTAssertEqual(OnBoard.niceStep(6), 10)

        XCTAssertEqual(OnBoard.labels([0, 20, 40], unit: " g").map(\.text), ["0", "20", "40 g"])
        XCTAssertEqual(OnBoard.labels([0, 0.5, 1], unit: " U").map(\.text), ["0", d("0.5"), "1 U"])
        XCTAssertEqual(OnBoard.labels([], unit: " U"), [])
    }

    /// The IOB line and areas: a point at 0 where the IOB crosses zero, by the straight line between two rows; not at
    /// a row at 0.
    func testOnBoardIOBSeries() {
        let start = clock(6, 12)
        let at = { (minutes: Double) in start.addingTimeInterval(.minutes(minutes)) }
        let rows: [HomeOnBoardCard.Point] = [
            .init(date: at(0), value: 1),
            .init(date: at(5), value: -1),
            .init(date: at(10), value: -0.5),
            .init(date: at(15), value: 0.5),
            .init(date: at(20), value: 0),
            .init(date: at(25), value: -0.5)
        ]
        XCTAssertEqual(OnBoard.iobSeries(rows), [
            .init(date: at(0), value: 1),
            .init(date: at(2.5), value: 0),
            .init(date: at(5), value: -1),
            .init(date: at(10), value: -0.5),
            .init(date: at(12.5), value: 0),
            .init(date: at(15), value: 0.5),
            .init(date: at(20), value: 0),
            .init(date: at(25), value: -0.5)
        ])
        XCTAssertEqual(OnBoard.iobSeries([]), [])
    }

    /// The negative IOB of the last 24 h: the Statistics' rule (`InsulinStatsEngine.iobSpans`), cut at the window.
    func testOnBoardNegativeIOB() {
        let now = clock(6, 12)
        let window = DateInterval(start: now.addingTimeInterval(-OnBoard.duration), end: now)
        let before = { (minutes: Double) in now.addingTimeInterval(-.minutes(minutes)) }
        // a row stands for the time up to the next one (at most 7.5 min), else 5 min: 2 × 5 min
        XCTAssertEqual(OnBoard.negativeIOBSeconds([
            IOBPoint(time: before(20), iob: 1),
            IOBPoint(time: before(15), iob: -0.2),
            IOBPoint(time: before(10), iob: -0.3),
            IOBPoint(time: before(5), iob: 1)
        ], window: window), .minutes(10))
        // a gap: the row before it for 5 min; a row next to another (a failed loop's) is one
        XCTAssertEqual(OnBoard.negativeIOBSeconds([
            IOBPoint(time: before(60), iob: -0.2),
            IOBPoint(time: before(60).addingTimeInterval(5), iob: 1),
            IOBPoint(time: before(30), iob: 1)
        ], window: window), .minutes(5))
        // the newest not past the window's end: 2 min
        XCTAssertEqual(OnBoard.negativeIOBSeconds([
            IOBPoint(time: before(7), iob: 1),
            IOBPoint(time: before(2), iob: -0.1)
        ], window: window), .minutes(2))
        // cut at the window's start: a row 2 min before it stands for 5 min, 3 of them inside
        let start = window.start
        XCTAssertEqual(OnBoard.negativeIOBSeconds([
            IOBPoint(time: start.addingTimeInterval(-.minutes(2)), iob: -0.5),
            IOBPoint(time: start.addingTimeInterval(.minutes(3)), iob: 0.5)
        ], window: window), .minutes(3), accuracy: 1E-6)
        XCTAssertEqual(OnBoard.negativeIOBSeconds([], window: window), 0)
    }

    /// The card's negative IOB from the read's rows, also the one before its window (the read takes 7.5 min more,
    /// `Home.StateModel.setupData`): the part of its span inside counts; it isn't drawn.
    @MainActor func testOnBoardNegativeIOBAtTheWindowStart() {
        let now = clock(6, 14, 35)
        let start = now.addingTimeInterval(-OnBoard.duration)
        let rows = [
            IOBData(date: now.addingTimeInterval(-.minutes(5)), iob: 1, cob: 0),
            IOBData(date: now.addingTimeInterval(-.minutes(10)), iob: 1, cob: 0),
            IOBData(date: start.addingTimeInterval(.minutes(3)), iob: 0.5, cob: 0),
            // 2 min before the window, up to the next row: 3 min of it inside
            IOBData(date: start.addingTimeInterval(-.minutes(2)), iob: -0.5, cob: 0)
        ]
        let content = OnBoard(
            iob: rows,
            readings: [],
            bands: StatsBands(low: 70, high: 180, units: .mgdL),
            units: .mgdL,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(content.window.start, start)
        XCTAssertEqual(content.negativeIOB, HomeLoopsCard.duration(.minutes(3)))
        XCTAssertEqual(content.rowCount, 3)
        XCTAssertEqual(content.iob.first?.date, start.addingTimeInterval(.minutes(3)))
        XCTAssertEqual(content.iob.map(\.value), [0.5, 1, 1])
    }

    /// The window: the last 24 h up to now to the minute (builds seconds apart are the same card), or up to a newer row
    /// or reading at most 5 min ahead (a date further ahead is left out, the window not moved); the card shows with
    /// more than 3 rows in it.
    @MainActor func testOnBoardWindow() {
        let minute = clock(6, 14, 35)
        let bands = StatsBands(low: 70, high: 180, units: .mgdL)
        let rows = (1 ... 4).map { IOBData(date: minute.addingTimeInterval(-.minutes(Double($0) * 5)), iob: 1, cob: 0) }
        let readings = (1 ... 4).map {
            HomeOnBoardCard.Reading(date: minute.addingTimeInterval(-.minutes(Double($0) * 5)), mgdl: 100)
        }
        let build = { (now: Date, rows: [IOBData], readings: [HomeOnBoardCard.Reading]) in
            OnBoard(iob: rows, readings: readings, bands: bands, units: .mgdL, now: now, calendar: self.calendar)
        }

        let early = build(minute.addingTimeInterval(10), rows, readings)
        let late = build(minute.addingTimeInterval(42), rows, readings)
        XCTAssertEqual(early.window, DateInterval(start: minute.addingTimeInterval(-.hours(24)), end: minute))
        XCTAssertEqual(early, late)
        XCTAssertTrue(early.hasRows)

        // a reading a minute ahead of the clock: the window ends at it, it is drawn
        let ahead = minute.addingTimeInterval(.minutes(1))
        let aheadReading = HomeOnBoardCard.Reading(date: ahead, mgdl: 140)
        let aheadContent = build(minute.addingTimeInterval(10), rows, readings + [aheadReading])
        XCTAssertEqual(aheadContent.window.end, ahead)
        XCTAssertEqual(aheadContent.glucose.last?.mgdl, 140)
        // a row ahead too: the newer of them
        let rowAhead = minute.addingTimeInterval(.minutes(2))
        XCTAssertEqual(
            build(minute, rows + [IOBData(date: rowAhead, iob: 1, cob: 0)], readings + [aheadReading]).window.end,
            rowAhead
        )
        // an hour ahead: left out, the window as of the clock
        let farReading = HomeOnBoardCard.Reading(date: minute.addingTimeInterval(.hours(1)), mgdl: 140)
        let farAhead = build(minute, rows, readings + [farReading])
        XCTAssertEqual(farAhead.window.end, minute)
        XCTAssertEqual(farAhead.glucose.map(\.mgdl), [100, 100, 100, 100])

        // 3 rows in the window: no card; the readings moved the window past the rows of a stopped loop: no card
        XCTAssertFalse(build(minute, Array(rows.prefix(3)), readings).hasRows)
        XCTAssertEqual(build(minute, Array(rows.prefix(3)), readings).rowCount, 3)
        let stopped = build(minute.addingTimeInterval(TimeInterval.hours(24) - TimeInterval.minutes(12)), rows, readings)
        XCTAssertEqual(stopped.rowCount, 2)
        XCTAssertFalse(stopped.hasRows)
    }

    /// At most one dot per 5 min: from the newest back, a reading at least 4.5 min before the last one kept; a 5-minute
    /// CGM's readings (a little early or late) all stay. The domain from every reading.
    @MainActor func testOnBoardGlucoseThinned() {
        let now = clock(6, 14, 35)
        let minutely = (0 ..< 20).reversed().map {
            HomeOnBoardCard.Reading(date: now.addingTimeInterval(-.minutes(Double($0))), mgdl: 100 + $0)
        }
        let thinned = OnBoard.thinned(minutely)
        XCTAssertEqual(thinned.map(\.date), [15, 10, 5, 0].map { now.addingTimeInterval(-.minutes(Double($0))) })
        XCTAssertEqual(thinned.last, minutely.last)

        let offsets: [Double] = [0, 4 * 60 + 58, 9 * 60 + 57, 15 * 60 + 2]
        let fiveMinute = offsets.reversed().map {
            HomeOnBoardCard.Reading(date: now.addingTimeInterval(-$0), mgdl: 100)
        }
        XCTAssertEqual(OnBoard.thinned(fiveMinute), fiveMinute)
        XCTAssertEqual(OnBoard.thinned([]), [])

        // a low reading between two dots: not drawn, still in the domain
        var readings = minutely
        readings[17] = HomeOnBoardCard.Reading(date: readings[17].date, mgdl: 40)
        let content = OnBoard(
            iob: [],
            readings: readings,
            bands: StatsBands(low: 70, high: 180, units: .mgdL),
            units: .mgdL,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(content.glucose.count, 4)
        XCTAssertFalse(content.glucose.contains { $0.mgdl == 40 })
        XCTAssertEqual(content.glucoseDomain, OnBoard.glucoseDomain(readings.map(\.mgdl), inRange: 70 ... 180))
    }

    /// The hours 2 h apart also over a DST change, the newest even: spring forward (Berlin, 29 Mar 2026, 02:00 -> 03:00)
    /// has the hours before it odd.
    func testOnBoardHourTicksSpringForward() {
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        let window = DateInterval(start: end.addingTimeInterval(-OnBoard.duration), end: end)
        let ticks = OnBoard.hourTicks(window, calendar: calendar)
        XCTAssertEqual(
            ticks.map(\.label),
            ["11", "13", "15", "17", "19", "21", "23", "01", "04", "06", "08", "10", "12"]
        )
        XCTAssertEqual(ticks.first?.date, window.start)
        XCTAssertEqual(ticks.last?.date, end)
        for (earlier, later) in zip(ticks, ticks.dropFirst()) {
            XCTAssertEqual(later.date.timeIntervalSince(earlier.date), .hours(2))
            XCTAssertEqual(later.fraction - earlier.fraction, 1.0 / 12, accuracy: 1E-9)
        }
    }

    /// The lanes shown, from the top: glucose when on and with readings, COB when on (with carbs or not: flat at 0
    /// without, the card keeps its shape), IOB always; IOB taller the fewer lanes there are.
    func testOnBoardLanes() {
        func lanes(_ glucose: Bool, _ cob: Bool, readings: Bool) -> [HomeOnBoardCard.Lane] {
            OnBoard.lanes(showGlucose: glucose, showCOB: cob, hasReadings: readings)
        }
        XCTAssertEqual(lanes(true, true, readings: true), [.glucose, .cob, .iob])
        XCTAssertEqual(lanes(true, true, readings: false), [.cob, .iob])
        XCTAssertEqual(lanes(true, false, readings: true), [.glucose, .iob])
        XCTAssertEqual(lanes(false, true, readings: true), [.cob, .iob])
        XCTAssertEqual(lanes(false, false, readings: true), [.iob])
        XCTAssertEqual(lanes(true, false, readings: false), [.iob])

        XCTAssertFalse(OnBoard.hasCarbs([]))
        XCTAssertFalse(OnBoard.hasCarbs([0, 0, 0]))
        XCTAssertTrue(OnBoard.hasCarbs([0, 0.1, 0]))

        let all: [HomeOnBoardCard.Lane] = [.glucose, .cob, .iob]
        XCTAssertEqual(all.map { OnBoard.height(of: $0, in: all) }, [56, 40, 64])
        XCTAssertEqual([HomeOnBoardCard.Lane.cob, .iob].map { OnBoard.height(of: $0, in: [.cob, .iob]) }, [48, 76])
        XCTAssertEqual(OnBoard.height(of: .iob, in: [.glucose, .iob]), 76)
        XCTAssertEqual(OnBoard.height(of: .iob, in: [.iob]), 104)
    }

    /// The card from the IOB rows and the readings: the last 24 h up to now (rows outside it dropped), oldest -> newest;
    /// the even hours; the 70 and 180 rules in the units.
    @MainActor func testOnBoardContent() {
        // 2026-10-16 14:35 Europe/Berlin
        let now = clock(6, 14, 35)
        let before = { (minutes: Double) in now.addingTimeInterval(-.minutes(minutes)) }
        let rows = [
            IOBData(date: before(5), iob: -0.5, cob: 0),
            IOBData(date: before(10), iob: 1, cob: 20),
            IOBData(date: before(15), iob: 0.4, cob: 30),
            // outside the window: dropped (an hour ahead of the clock too, the window not moved)
            IOBData(date: before(25 * 60), iob: 9, cob: 99),
            IOBData(date: now.addingTimeInterval(.hours(1)), iob: 9, cob: 99)
        ]
        let readings = [
            HomeOnBoardCard.Reading(date: before(5), mgdl: 112),
            HomeOnBoardCard.Reading(date: before(10), mgdl: 62),
            HomeOnBoardCard.Reading(date: before(15), mgdl: 245),
            HomeOnBoardCard.Reading(date: before(25 * 60), mgdl: 400)
        ]
        let bands = StatsBands(low: 70, high: 180, units: .mgdL)
        let content = OnBoard(iob: rows, readings: readings, bands: bands, units: .mgdL, now: now, calendar: calendar)

        XCTAssertEqual(content.window, DateInterval(start: now.addingTimeInterval(-.hours(24)), end: now))
        // 1 to -0.5 in 5 min: 0 two thirds of the way
        XCTAssertEqual(content.iob.map(\.value), [0.4, 1, 0, -0.5])
        XCTAssertEqual(content.iob.count, 4)
        XCTAssertEqual(content.iob[0].date, before(15))
        XCTAssertEqual(content.iob[1].date, before(10))
        XCTAssertEqual(content.iob[2].date.timeIntervalSince(before(10)), 200, accuracy: 1E-6)
        XCTAssertEqual(content.iob[3].date, before(5))
        XCTAssertEqual(content.cob.map(\.value), [30, 20, 0])
        XCTAssertTrue(content.hasCarbs)
        XCTAssertEqual(content.glucose.map(\.mgdl), [245, 62, 112])
        XCTAssertEqual(content.glucose.map(\.band), [.high, .low, .inRange])
        XCTAssertEqual(content.glucoseLevels.map(\.value), [70, 180])
        XCTAssertEqual(content.glucoseLevels.map(\.text), ["70", "180"])
        // the bands' high at their low (the bands allow it): one rule, one label (the values are the views' ids)
        let narrow = StatsBands(low: 120, high: 120, units: .mgdL)
        XCTAssertEqual(narrow.low, narrow.high)
        XCTAssertEqual(OnBoard.levels(narrow), [120])
        XCTAssertEqual(OnBoard.levels(bands), [70, 180])
        let single = OnBoard(iob: rows, readings: readings, bands: narrow, units: .mgdL, now: now, calendar: calendar)
        XCTAssertEqual(single.glucoseLevels, [HomeOnBoardCard.AxisLabel(value: 120, text: "120")])
        XCTAssertEqual(content.iobDomain, OnBoard.iobDomain([0.4, 1, -0.5]))
        XCTAssertEqual(content.cobLabels.map(\.value), OnBoard.ticks(content.cobDomain))
        // 0 ... 33: 0 and 20
        XCTAssertEqual(content.cobLabels.map(\.text), ["0", "20 g"])
        XCTAssertEqual(content.negativeIOB, HomeLoopsCard.duration(.minutes(5)))

        // every 2 h on the even hours, from 16:00 yesterday to 14:00
        XCTAssertEqual(content.hourTicks.map(\.label), ["16", "18", "20", "22", "00", "02", "04", "06", "08", "10", "12", "14"])
        XCTAssertEqual(content.hourTicks.first?.date, clock(5, 16))
        XCTAssertEqual(content.hourTicks.first?.fraction ?? 0, 85.0 / 1440, accuracy: 1E-9)
        XCTAssertEqual(content.hourTicks.last?.date, clock(6, 14))

        // mmol: the edges that display as 3.9 and 10.0
        let mmol = OnBoard(
            iob: rows,
            readings: readings,
            bands: StatsBands(low: 70, high: 180, units: .mmolL),
            units: .mmolL,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(mmol.glucoseLevels.map(\.value), [70, 181])
        XCTAssertEqual(mmol.glucoseLevels.map(\.text), [d("3.9"), d("10.0")])

        // no readings: no glucose lane, whatever the toggle; no carbs: the carbs lane all the same (flat at 0, its
        // domain the 10 g minimum), and the menu's toggle with it
        let bare = OnBoard(
            iob: [IOBData(date: before(10), iob: 1, cob: 0), IOBData(date: before(5), iob: 0.5, cob: 0)],
            readings: [],
            bands: bands,
            units: .mgdL,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(bare.hasCarbs)
        XCTAssertEqual(bare.lanes(showGlucose: true, showCOB: true), [.cob, .iob])
        XCTAssertEqual(bare.lanes(showGlucose: true, showCOB: false), [.iob])
        XCTAssertEqual(bare.cob.map(\.value), [0, 0])
        XCTAssertEqual(bare.cobDomain, 0 ... 10)
        // the same shape as with carbs: the lane's height doesn't depend on them
        let lanes = bare.lanes(showGlucose: true, showCOB: true)
        XCTAssertEqual(lanes.map { OnBoard.height(of: $0, in: lanes) }, [48, 76])
        XCTAssertEqual(bare.negativeIOB, HomeLoopsCard.duration(0))
    }

    /// The dots in the Statistics' band colours (`GlucoseBand.color`) by the user's bands (`StatsBands`, as Statistics
    /// makes them), the dashed rules at that in-range band's edges, inside the domain: dots and rules agree.
    @MainActor func testOnBoardGlucoseBandsAreTheStatistics() {
        let now = clock(6, 14, 35)
        let values = [50, 75, 80, 160, 161, 251]
        let readings = values.enumerated().map { index, mgdl in
            HomeOnBoardCard.Reading(
                date: now.addingTimeInterval(-.minutes(Double(values.count - index) * 5)),
                mgdl: mgdl
            )
        }
        let bands = StatsBands(low: 80, high: 160, units: .mgdL)
        let content = OnBoard(iob: [], readings: readings, bands: bands, units: .mgdL, now: now, calendar: calendar)
        XCTAssertEqual(content.glucose.map(\.mgdl), values)
        XCTAssertEqual(content.glucose.map(\.band), [.veryLow, .low, .inRange, .inRange, .high, .veryHigh])
        XCTAssertEqual(content.glucose.map(\.band), values.map(bands.band))
        XCTAssertEqual(
            content.glucose.map(\.band.color),
            [Color.statsVeryLow, .statsLow, .statsInRange, .statsInRange, .statsHigh, .statsVeryHigh]
        )
        // the rules where the dots change colour: 80 in range, 79 low; 160 in range, 161 high
        XCTAssertEqual(content.glucoseLevels.map(\.value), [80, 160])
        XCTAssertEqual(content.glucoseLevels.map(\.text), ["80", "160"])
        XCTAssertEqual(bands.band(79), .low)
        XCTAssertEqual(bands.band(80), .inRange)
        XCTAssertEqual(bands.band(160), .inRange)
        XCTAssertTrue(content.glucoseLevels.allSatisfy { content.glucoseDomain.contains($0.value) })

        // a high edge of 250: its rule inside the domain without readings near it
        let wide = StatsBands(low: 70, high: 250, units: .mgdL)
        let low = OnBoard(
            iob: [],
            readings: Array(readings.prefix(2)),
            bands: wide,
            units: .mgdL,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(low.glucoseLevels.map(\.value), [70, 250])
        XCTAssertTrue(low.glucoseLevels.allSatisfy { low.glucoseDomain.contains($0.value) })
    }

    // MARK: - Today on the Insulin and Meals tabs

    /// The parts by now: the basal scaled as the total's (by the day's coverage), the SMBs and boluses as delivered; in
    /// every hour, and by every clock time, they sum to the total; by the end of the day each is the summary's mean.
    func testClockAverageParts() {
        // day 1 covered in full; day 2 up to 18:00 (75%), its basal × 24 / 18
        let days = pastDays([day(1), day(2)], coveredHours: [nil, 18])
        let average = InsulinStatsEngine.clockAverage(days)!
        let noon = clock(6, 12)
        let parts = average.parts(at: noon, calendar: calendar)
        // basal by 12:00: (12 + 12 × 4/3) / 2; no SMB; the 5 U bolus at 08:00
        XCTAssertEqual(parts[0], 14, accuracy: 1E-9)
        XCTAssertEqual(parts[1], 0, accuracy: 1E-9)
        XCTAssertEqual(parts[2], 5, accuracy: 1E-9)
        XCTAssertEqual(parts.reduce(0, +), average.value(at: noon, calendar: calendar), accuracy: 1E-9)
        for hour in 0 ..< 24 {
            XCTAssertEqual(average.parts.reduce(0) { $0 + $1.within[hour] }, average.within[hour], accuracy: 1E-9)
            for passed in [0, 0.4, 1] {
                XCTAssertEqual(
                    average.parts.reduce(0) { $0 + $1.value(hour: hour, passed: passed) },
                    average.value(hour: hour, passed: passed),
                    accuracy: 1E-9
                )
            }
        }
        // by the end of the day: the summary's means, the basal scaled
        let summary = InsulinStatsEngine.summary(days, period: nil)
        XCTAssertEqual(average.parts[0].value(hour: 23, passed: 1), summary.basal!, accuracy: 1E-9)
        XCTAssertEqual(average.parts[1].value(hour: 23, passed: 1), summary.smb!, accuracy: 1E-9)
        XCTAssertEqual(average.parts[2].value(hour: 23, passed: 1), summary.bolus!, accuracy: 1E-9)
        XCTAssertNil(average.negativeIOBSeconds, "no IOB rows")

        // the SMBs too: 0.5 U at 09:00 every day
        let week = InsulinStatsEngine.clockAverage(insulinPeriod(.days7, now: clock(6, 12, 30)).days)!
        XCTAssertEqual(week.parts(at: clock(6, 8, 59), calendar: calendar)[1], 0, accuracy: 1E-9)
        XCTAssertEqual(week.parts(at: clock(6, 10), calendar: calendar)[1], 0.5, accuracy: 1E-9)
    }

    /// The negative IOB by now: the headline days' negative time by then over all their IOB time, per day of it; by the
    /// end of the day the summary's.
    func testClockAverageNegativeIOB() {
        let lunch = clock(6, 12, 30)
        let days = insulinPeriod(.days7, now: lunch, negativeMinutes: 25).days
        let negative = InsulinStatsEngine.clockAverage(days)!.negativeIOBSeconds!
        XCTAssertEqual(negative.value(hour: 2, passed: 1), 0, accuracy: 1E-6)
        // 03:00–03:25 negative on every day
        XCTAssertEqual(negative.value(hour: 3, passed: 1), .minutes(25), accuracy: 1E-6)
        XCTAssertEqual(negative.value(at: lunch, calendar: calendar), .minutes(25), accuracy: 1E-6)
        XCTAssertEqual(
            negative.value(hour: 23, passed: 1),
            InsulinStatsEngine.summary(days, period: .days7).negativeIOBSecondsPerDay!,
            accuracy: 1E-6
        )
    }

    /// Today keeps all its boluses, oldest -> newest; a cached past day only those that aren't SMBs (its SMBs are in
    /// its hours), for Good & bad days. The Today card lists today's alone.
    func testTodayKeepsAllItsBolusesAPastDayNotItsSMBs() {
        let days = insulinPeriod(.days7, now: clock(6, 12, 30)).days
        for day in days.dropLast() {
            XCTAssertEqual(day.boluses.map(\.isSMB), [false])
            XCTAssertEqual(day.boluses.map(\.units), [5])
            XCTAssertEqual(day.smb, 0.5, accuracy: 1E-9)
        }
        XCTAssertEqual(days.last?.boluses.map(\.date), [clock(6, 8), clock(6, 9)])
        XCTAssertEqual(days.last?.boluses.map(\.isSMB), [false, true])
        XCTAssertEqual(days.last?.boluses.map(\.units), [5, 0.5])
    }

    /// The Insulin tab on Today read at `now`, its data up to `dataUntil` (`now` when nil): `insulinPeriod`'s (the 7
    /// days before today and today; `withData` all of them when nil).
    @MainActor private func insulinToday(
        at now: Date,
        dataUntil: Date? = nil,
        withData: [Int]? = nil,
        negativeMinutes: Int = 0
    ) -> Stat.Insulin {
        let insulin = insulinPeriod(.today, now: dataUntil ?? now, withData: withData, negativeMinutes: negativeMinutes)
        let result = Stat.InsulinResult(period: .days7, insulin: insulin, shown: .today, asOf: now, calendar: calendar)
        return Stat.Insulin(result, calendar: calendar)
    }

    /// Today at 12:30: 18.0 U so far against the usual by 12:30 (the 7 complete days', the same), by its sign alone;
    /// the parts with their usual; the hours up to 12:00 stacked, 12:00 outlined (its 0.5 U so far), the usual by hour
    /// dashed; the basal so far; the bolus and the SMBs counted.
    @MainActor func testInsulinToday() {
        let lunch = clock(6, 12, 30)
        let insulin = insulinToday(at: lunch, negativeMinutes: 25)
        XCTAssertEqual(insulin.shown, .today)
        XCTAssertEqual(insulin.period, .days7)
        let today = insulin.today!
        XCTAssertEqual(
            today.dateRange,
            StatsFormatting.dateRange(DateInterval(start: day(6), end: day(7)), period: .today, now: lunch)
        )
        XCTAssertTrue(today.hasData)
        XCTAssertEqual(today.total, d("18.0"))
        XCTAssertEqual(today.usualTitle, "Usual by \(lunch.formatted(date: .omitted, time: .shortened)) · 7 d")
        XCTAssertEqual(today.usual, d("18.0 U"))
        XCTAssertEqual(today.difference, d("±0.0 U"))
        XCTAssertFalse(today.needsCompleteDay)
        XCTAssertEqual(today.rows.map(\.value), [d("12.5 U"), d("0.5 U"), d("5.0 U")])
        XCTAssertEqual(today.rows.map(\.percent), ["69%", "3%", "28%"])
        XCTAssertEqual(today.rows.map(\.usual), [d("12.5 U"), d("0.5 U"), d("5.0 U")])
        XCTAssertEqual(today.split.map(\.id), [0, 1, 2])

        // by hour: 12 basal parts, 08:00's bolus and 09:00's SMB, 12:00 outlined; the usual over the 24 hours
        let plot = today.hourPlot
        XCTAssertEqual(plot.parts.filter { $0.hour < 12 }.count, 14)
        let current = plot.parts.filter { $0.hour == 12 }
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current.first?.upper ?? 0, 0.5, accuracy: 1E-9)
        XCTAssertEqual(current.first?.style, Stat.Insulin.Today.currentHourStyle)
        XCTAssertTrue(plot.parts.allSatisfy { $0.hour <= 12 })
        XCTAssertEqual(plot.usual.count, 24)
        XCTAssertEqual(plot.steps, [])
        XCTAssertEqual(plot.levels, [0, 3, 6])
        XCTAssertTrue(today.hourLegend.contains { $0.key == .tick && $0.title == "Usual · 7 d" })
        XCTAssertEqual(today.hourReadouts[8].rows.map(\.key), [.swatch(Stat.Insulin.Today.todayHourStyle), .tick])
        XCTAssertEqual(today.hourReadouts[8].rows.map(\.value), [d("6.00 U"), d("6.00 U")])
        XCTAssertEqual(today.hourReadouts[12].rows.map(\.value), [d("0.50 U"), d("1.00 U")])
        XCTAssertEqual(today.hourReadouts[12].subtitle, "so far")
        XCTAssertEqual(today.hourReadouts[13].rows.map(\.value), ["–", d("1.00 U")])
        XCTAssertNil(today.hourReadouts[13].subtitle)
        // the "Today" row's swatch: the insulin colour of the hour's bars, not a part's
        XCTAssertEqual(today.hourReadouts[8].rows.first?.key, .swatch(Stat.Insulin.Today.todayHourStyle))

        // basal so far: as scheduled, no zero basal; 25 min negative against the usual 25 min (the Negative IOB card)
        XCTAssertEqual(today.vsScheduled, "100%")
        XCTAssertEqual(today.scheduledSoFar, d("of 12.5 U"))
        XCTAssertEqual(today.zeroBasal, "0 m")
        XCTAssertEqual(today.negativeCard.headline, "25 m")
        XCTAssertNil(today.negativeCard.subtitle)
        XCTAssertFalse(today.profileAssumed)

        // the bolus listed, the SMBs counted
        XCTAssertEqual(today.boluses.map(\.time), [clock(6, 8).formatted(date: .omitted, time: .shortened)])
        XCTAssertEqual(today.boluses.map(\.name), ["Bolus"])
        XCTAssertEqual(today.boluses.map(\.units), [d("5.0 U")])
        XCTAssertEqual(today.smbCount, "1 SMB")
        XCTAssertEqual(today.smbTotal, d("0.5 U"))

        // a read at 14:00 of the data up to 12:30: the usual by 14:00 (14 h of basal, the SMB, the bolus) in the Usual
        // column, today's parts in theirs; 13:00, past without pump data, "–" (not "0.00 U"), as 14:00 (the current
        // hour, the coverage not reaching into 13:00)
        let later = insulinToday(at: clock(6, 14), dataUntil: lunch).today!
        XCTAssertEqual(later.rows.map(\.value), [d("12.5 U"), d("0.5 U"), d("5.0 U")])
        XCTAssertEqual(later.rows.map(\.usual), [d("14.0 U"), d("0.5 U"), d("5.0 U")])
        XCTAssertEqual(later.usual, d("19.5 U"))
        XCTAssertEqual(later.difference, d("−1.5 U"))
        XCTAssertEqual(later.hourReadouts[12].rows.map(\.value), [d("0.50 U"), d("1.00 U")])
        XCTAssertEqual(later.hourReadouts[13].rows.map(\.value), ["–", d("1.00 U")])
        XCTAssertEqual(later.hourReadouts[14].rows.map(\.value), ["–", d("1.00 U")])
        XCTAssertEqual(later.hourReadouts[14].subtitle, "so far")
        // no pump data today at all: every hour so far "–"
        let noData = insulinToday(at: lunch, withData: Array(0 ... 5)).today!
        XCTAssertEqual(noData.hourReadouts.prefix(13).map { $0.rows[0].value }, [String](repeating: "–", count: 13))

        // 7–90 d: no Today view
        XCTAssertNil(Stat.Insulin(insulinResult()).today)
        XCTAssertEqual(Stat.Insulin(insulinResult()).shown, .days7)
    }

    /// The difference by its sign alone, no percentage: more, less, and none as rounded.
    @MainActor func testInsulinTodayDifference() {
        XCTAssertEqual(Stat.Insulin.signedUnits(1.25), d("+1.3 U"))
        XCTAssertEqual(Stat.Insulin.signedUnits(-0.44), d("−0.4 U"))
        XCTAssertEqual(Stat.Insulin.signedUnits(0.04), d("±0.0 U"))
        XCTAssertEqual(Stat.Insulin.signedUnits(-0.04), d("±0.0 U"))
        // a read later than the data (12:30): the usual by 13:15 (12 + 5.5 + 1 + a quarter of 1 U) is ahead of today's
        // 18.0 U
        let later = insulinToday(at: clock(6, 13, 15), dataUntil: clock(6, 12, 30)).today!
        XCTAssertEqual(later.total, d("18.0"))
        XCTAssertEqual(later.usual, d("18.8 U"))
        XCTAssertEqual(later.difference, d("−0.8 U"))
        XCTAssertEqual(
            later.usualTitle,
            "Usual by \(clock(6, 13, 15).formatted(date: .omitted, time: .shortened)) · 7 d"
        )
    }

    /// Without a complete day in the 7 before today: today's numbers, no usual ("–", "Needs one complete day"), no dashed line.
    @MainActor func testInsulinTodayWithoutACompleteDay() {
        let today = insulinToday(at: clock(6, 12, 30), withData: [6]).today!
        XCTAssertTrue(today.needsCompleteDay)
        XCTAssertEqual(today.total, d("18.0"))
        XCTAssertEqual(today.usual, "–")
        XCTAssertNil(today.difference)
        XCTAssertEqual(today.rows.map(\.usual), ["–", "–", "–"])
        XCTAssertEqual(today.hourPlot.usual, [])
        XCTAssertFalse(today.hourLegend.contains { $0.key == .tick })
        XCTAssertEqual(today.negativeCard.headline, "–")
        XCTAssertNil(today.negativeCard.subtitle)
    }

    // MARK: - IOB cards

    /// 7 d, every complete day 25 minutes below zero from 03:00 (-0.5 U, else 1 U): the Negative IOB card's numbers,
    /// its hours hanging from the top, the hour readout's and the selected day's IOB rows; the IOB card's bands.
    @MainActor func testNegativeIOBCardOverAPeriod() {
        let result = Stat.InsulinResult(
            period: .days7,
            insulin: insulinPeriod(.days7, now: now, negativeMinutes: 25),
            calendar: calendar
        )
        let insulin = Stat.Insulin(result, calendar: calendar)
        let card = insulin.negativeCard
        XCTAssertEqual(card.headline, "25 m")
        XCTAssertEqual(card.headlineUnit, "per day")
        XCTAssertEqual(card.subtitle, "2% of the time")
        XCTAssertNil(card.limitedNote)
        XCTAssertEqual(card.tiles.map(\.title), ["Mean depth", "Lowest"])
        XCTAssertEqual(card.tiles.map(\.value), [d("−0.50"), d("−0.50")])
        let firstDay = result.labels[0].title
        XCTAssertEqual(
            card.tiles.map(\.unit),
            ["U", "U · \(firstDay), \(clock(0, 3).formatted(date: .omitted, time: .shortened))"]
        )
        XCTAssertTrue(card.hourLegend.isEmpty)

        // the hours: 03:00's 25 minutes per day hanging from 0 at the top
        let plot = card.hourPlot
        XCTAssertEqual(plot.parts.map(\.hour), [3])
        XCTAssertEqual(plot.parts.first?.lower ?? 0, -25, accuracy: 1E-9)
        XCTAssertEqual(plot.parts.first?.upper, 0)
        XCTAssertEqual(plot.parts.first?.style, Stat.Insulin.negativeHourStyle)
        XCTAssertEqual(plot.yDomain.lowerBound, -30)
        // a little room above the top edge's 0
        XCTAssertEqual(plot.yDomain.upperBound, 30 * Stat.Insulin.topInset, accuracy: 1E-9)
        XCTAssertEqual(plot.levels, [-30, -15, 0])
        XCTAssertEqual(plot.levelLabels, ["30 m", "15 m", "0"])
        XCTAssertEqual(insulin.hourReadouts[3].negativeIOB, "25 m")
        XCTAssertEqual(insulin.hourReadouts[4].negativeIOB, "0 m")
        XCTAssertEqual(insulin.card(at: 0).lowestIOB, d("−0.50 U"))
        XCTAssertEqual(Stat.Insulin(insulinResult()).card(at: 0).lowestIOB, "–")

        // the IOB card: six complete days, the bands; the axis −1 … 2 U
        let iob = insulin.iobCard
        XCTAssertNil(iob.note)
        XCTAssertEqual(iob.legend.map(\.title), ["Median", "25–75%", "10–90%", "Negative"])
        XCTAssertEqual(iob.plot.outer.count, 96)
        XCTAssertEqual(iob.plot.inner.count, 96)
        XCTAssertEqual(iob.plot.median.count, 96)
        XCTAssertTrue(iob.plot.dayLines.isEmpty)
        XCTAssertFalse(iob.plot.isUsual)
        XCTAssertEqual(iob.plot.yDomain, -1 ... 2)
        XCTAssertEqual(iob.plot.levels, [-1, 0, 1, 2])
        XCTAssertEqual(iob.plot.levelLabels, ["−1", "0 U", "1", "2"])
    }

    /// Fewer than 3 complete days: the day as a line, with the note; none: "Needs one complete day", nothing drawn.
    /// Pump data not covering every complete day: the limited note on the Negative IOB card's headline.
    @MainActor func testIOBCardsWithShortData() {
        let short = insulinPeriod(.days7, now: now, withData: [5, 6], negativeMinutes: 25)
        let result = Stat.InsulinResult(period: .days7, insulin: short, calendar: calendar)
        let insulin = Stat.Insulin(result, calendar: calendar)
        XCTAssertEqual(insulin.iobCard.note, "The percentile bands need 3 complete days: the day is drawn as a line.")
        XCTAssertEqual(insulin.iobCard.legend.map(\.title), [result.labels[5].title, "Negative"])
        XCTAssertEqual(insulin.iobCard.plot.dayLines.count, 96)
        XCTAssertTrue(insulin.iobCard.plot.median.isEmpty)
        XCTAssertTrue(insulin.iobCard.plot.outer.isEmpty)
        XCTAssertNotNil(insulin.negativeCard.limitedNote)
        XCTAssertEqual(insulin.negativeCard.headline, "25 m")

        let none = Stat.Insulin(
            Stat.InsulinResult(
                period: .days7,
                insulin: insulinPeriod(.days7, now: now, withData: [6], negativeMinutes: 25),
                calendar: calendar
            ),
            calendar: calendar
        )
        XCTAssertEqual(none.iobCard.note, "Needs one complete day")
        XCTAssertTrue(none.iobCard.plot.isEmpty)
        XCTAssertTrue(none.iobCard.legend.isEmpty)
        XCTAssertEqual(none.negativeCard.headline, "–")
        XCTAssertEqual(none.negativeCard.tiles.map(\.value), ["–", "–"])
        XCTAssertTrue(none.negativeCard.hourPlot.parts.isEmpty)
    }

    /// Today at 12:30, 25 minutes below zero from 03:00 every day: so far, the lowest, the hours over the usual dashed (no
    /// usual by now); the IOB card's line over the usual (25–75%, the median dashed), split at zero.
    @MainActor func testIOBCardsToday() {
        let lunch = clock(6, 12, 30)
        let today = insulinToday(at: lunch, negativeMinutes: 25).today!
        let card = today.negativeCard
        XCTAssertEqual(card.headline, "25 m")
        XCTAssertEqual(card.headlineUnit, "so far")
        XCTAssertNil(card.subtitle)
        XCTAssertEqual(card.tiles.map(\.title), ["Lowest"])
        XCTAssertEqual(card.tiles.map(\.value), [d("−0.50")])
        let three = clock(6, 3).formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(card.tiles.map(\.unit), ["U · \(three)"])
        XCTAssertEqual(card.hourPlot.parts.map(\.hour), [3])
        XCTAssertEqual(card.hourPlot.steps, [])
        XCTAssertEqual(card.hourPlot.usual.filter { $0.level < 0 }.map(\.hour), [3])
        XCTAssertEqual(card.hourLegend.map(\.title), ["Today", "Usual · 7 d"])

        let iob = today.iobCard
        XCTAssertNil(iob.note)
        XCTAssertTrue(iob.plot.isUsual)
        XCTAssertTrue(iob.plot.outer.isEmpty)
        XCTAssertEqual(iob.plot.inner.count, 96)
        XCTAssertEqual(iob.plot.now, 750)
        // 02:45's 1 U to 03:00's −0.5 U: below zero from 03:02:30 (the bins' middles 02:52:30 and 03:07:30), back at
        // 03:15's 0 U (03:15–03:25 at −0.5, then 1)
        let below = iob.plot.todayBelow
        XCTAssertEqual(below.count, 3)
        for (point, expected) in zip(below, [(182.5, 0.0), (187.5, -0.5), (202.5, 0.0)]) {
            XCTAssertEqual(point.minute, expected.0, accuracy: 1E-9)
            XCTAssertEqual(point.value, expected.1, accuracy: 1E-9)
        }
        XCTAssertEqual(iob.plot.todayAbove.last?.minute, Stat.Insulin.iobMinute(ofBin: 49))
        XCTAssertEqual(iob.legend.map(\.title), ["Today", "Today, negative", "Usual · 7 d", "25–75%", "Negative"])

        // one complete day before today: no usual band, the note; the negative IOB's usual still by now
        let short = insulinToday(at: lunch, withData: [5, 6], negativeMinutes: 25).today!
        XCTAssertEqual(short.iobCard.note, "The usual needs 3 complete days.")
        XCTAssertTrue(short.iobCard.plot.inner.isEmpty)
        XCTAssertFalse(short.iobCard.legend.contains { $0.title == "Usual · 7 d" })
        XCTAssertNil(short.negativeCard.subtitle)
        XCTAssertEqual(short.negativeCard.hourLegend.map(\.title), ["Today", "Usual · 7 d"])
    }

    /// Pump data on every day (0 ... 6, today the 6th; Today: from the day before them), IOB rows every 5 minutes only
    /// on `iobDays`: 1 U, −0.5 U inside `negative`, up to `now`.
    private func insulinWithIOB(
        _ period: StatsPeriod,
        now: Date,
        iobDays: [Int],
        negative: [DateInterval],
        uncovered: Set<Int> = []
    ) -> InsulinPeriod {
        let dataDays = period == .today ? Array(-1 ... 6) : Array(0 ... 6)
        var rows: [CoveredInterval] = []
        for offset in dataDays where !uncovered.contains(offset) {
            rows.append(coverage(day(offset), Swift.min(day(offset + 1), now)))
        }
        var iob: [IOBPoint] = []
        for offset in iobDays {
            for slot in 0 ..< 288 {
                let time = day(offset).addingTimeInterval(.minutes(slot * 5))
                guard time < now else { break }
                iob.append(IOBPoint(time: time, iob: negative.contains { $0.contains(time) && time < $0.end } ? -0.5 : 1))
            }
        }
        let input = InsulinInput(coverage: rows, schedules: [flatSchedule], iob: iob)
        guard period == .today else {
            return InsulinStatsEngine.period(period, input: input, now: now, calendar: calendar)
        }
        let days = InsulinStatsEngine.days(
            InsulinStatsEngine.lastDays(InsulinStatsEngine.usualDays + 1, now: now, calendar: calendar),
            input: input,
            now: now,
            calendar: calendar
        )
        return todayRead(days)
    }

    /// 03:00–03:25 below zero on each of the days.
    private func earlyNegative(_ days: [Int]) -> [DateInterval] {
        days.map { DateInterval(start: clock($0, 3), end: clock($0, 3, 25)) }
    }

    /// The pump data covers every day, the IOB rows only some: the time is per day of IOB time, the IOB card's days are
    /// the ones with IOB rows, the Negative IOB card's note says the IOB doesn't cover the days.
    @MainActor func testIOBMissingOnSomeHeadlineDays() {
        let three = Stat.Insulin(
            Stat.InsulinResult(
                period: .days7,
                insulin: insulinWithIOB(.days7, now: now, iobDays: [3, 4, 5, 6], negative: earlyNegative([3, 4, 5, 6])),
                calendar: calendar
            ),
            calendar: calendar
        )
        XCTAssertEqual(three.negativeCard.headline, "25 m")
        XCTAssertEqual(three.negativeCard.tiles.map(\.value), [d("−0.50"), d("−0.50")])
        XCTAssertEqual(
            three.negativeCard.limitedNote,
            "IOB data doesn't cover every complete day of this period, so these numbers may not represent it."
        )
        XCTAssertNil(three.limitedNote)
        XCTAssertNil(three.iobCard.note)

        let two = Stat.Insulin(
            Stat.InsulinResult(
                period: .days7,
                insulin: insulinWithIOB(.days7, now: now, iobDays: [4, 5, 6], negative: earlyNegative([4, 5, 6])),
                calendar: calendar
            ),
            calendar: calendar
        )
        XCTAssertEqual(two.iobCard.note, "The percentile bands need 3 complete days: the days are drawn as lines.")
        XCTAssertEqual(two.iobCard.legend.first?.title, "Each day")
        XCTAssertEqual(two.iobCard.plot.dayLines.count, 2 * 96)
    }

    /// No IOB rows at all: "No IOB data" (not the lines' note, nor "Needs one complete day"), every number "–", no IOB
    /// note; Today's lowest "–".
    @MainActor func testNoIOBRows() {
        let insulin = Stat.Insulin(
            Stat.InsulinResult(
                period: .days7,
                insulin: insulinWithIOB(.days7, now: now, iobDays: [], negative: []),
                calendar: calendar
            ),
            calendar: calendar
        )
        XCTAssertNil(insulin.iobCard.note)
        XCTAssertTrue(insulin.iobCard.plot.isEmpty)
        XCTAssertEqual(insulin.negativeCard.headline, "–")
        XCTAssertNil(insulin.negativeCard.subtitle)
        XCTAssertEqual(insulin.negativeCard.tiles.map(\.value), ["–", "–"])
        XCTAssertNil(insulin.negativeCard.limitedNote)

        // two complete days, no IOB rows: still "No IOB data"
        let short = Stat.Insulin(
            Stat.InsulinResult(
                period: .days7,
                insulin: insulinWithIOB(.days7, now: now, iobDays: [], negative: [], uncovered: [0, 1, 2, 3]),
                calendar: calendar
            ),
            calendar: calendar
        )
        XCTAssertNil(short.iobCard.note)
        XCTAssertTrue(short.iobCard.plot.isEmpty)

        let today = insulinToday(at: clock(6, 12, 30)).today!
        XCTAssertEqual(today.negativeCard.tiles[0].value, "–")
        XCTAssertEqual(today.negativeCard.headline, "–")
    }

    /// Today: a time below zero from before midnight counts today's part alone; the current hour's minutes so far are a
    /// bar as the others (no outline, no legend entry of its own).
    @MainActor func testTodayNegativeIOBFromBeforeMidnightAndTheCurrentHour() {
        let lunch = clock(6, 12, 30)
        let insulin = insulinWithIOB(
            .today,
            now: lunch,
            iobDays: Array(-1 ... 6),
            negative: [
                DateInterval(start: clock(5, 23, 40), end: clock(6, 0, 35)),
                DateInterval(start: clock(6, 12), end: clock(6, 12, 15))
            ]
        )
        let result = Stat.InsulinResult(period: .days7, insulin: insulin, shown: .today, asOf: lunch, calendar: calendar)
        let card = Stat.Insulin(result, calendar: calendar).today!.negativeCard
        // today's time below zero is today's alone
        XCTAssertEqual(card.headline, "50 m")
        XCTAssertEqual(card.hourPlot.parts.map(\.hour), [0, 12])
        XCTAssertEqual(card.hourPlot.parts.last?.lower ?? 0, -15, accuracy: 1E-9)
        XCTAssertTrue(card.hourPlot.parts.allSatisfy { $0.style == Stat.Insulin.negativeHourStyle })
        XCTAssertEqual(card.hourLegend.map(\.title), ["Today", "Usual · 7 d"])
    }

    /// The lowest row at 23:58, running over midnight: its own time, and its own day's title (the day before the
    /// headline day it is found on).
    @MainActor func testLowestRowOverMidnight() {
        var iob: [IOBPoint] = []
        for (time, value) in [
            (clock(4, 23, 50), -0.3), (clock(4, 23, 55), -0.3), (clock(4, 23, 58), -1.0), (clock(5, 0, 3), -0.3),
            (clock(5, 0, 8), 0.5)
        ] {
            iob.append(IOBPoint(time: time, iob: value))
        }
        // day 4 not a headline day: the lowest is found on day 5
        let rows = (0 ... 6).filter { $0 != 4 }.map { coverage(day($0), Swift.min(day($0 + 1), now)) }
        let input = InsulinInput(coverage: rows, schedules: [flatSchedule], iob: iob)
        let period = InsulinStatsEngine.period(.days7, input: input, now: now, calendar: calendar)
        let stats = InsulinStatsEngine.negativeIOB(period.days)
        XCTAssertEqual(stats.lowest, -1.0)
        XCTAssertEqual(stats.lowestAt, clock(4, 23, 58))
        XCTAssertEqual(stats.lowestDay, 5)
        let result = Stat.InsulinResult(period: .days7, insulin: period, calendar: calendar)
        let card = Stat.Insulin(result, calendar: calendar).negativeCard
        XCTAssertEqual(
            card.tiles[1].unit,
            "U · \(result.labels[4].title), \(clock(4, 23, 58).formatted(date: .omitted, time: .shortened))"
        )
    }

    /// A line split where it crosses zero, at the crossing (between the bins' middles); a gap ends a stretch; 0 is
    /// above.
    func testIOBLineSplitAtZero() {
        let (above, below) = Stat.Insulin.signRuns([1, -1, nil, -2, 0])
        typealias Point = Stat.Insulin.IOBCard.Plot.Point
        XCTAssertEqual(above, [
            Point(minute: 7.5, value: 1, series: 0),
            Point(minute: 15, value: 0, series: 0),
            // the bin at 0 ends the stretch below and starts one above, once each
            Point(minute: 67.5, value: 0, series: 3)
        ])
        XCTAssertEqual(below, [
            Point(minute: 15, value: 0, series: 1),
            Point(minute: 22.5, value: -1, series: 1),
            Point(minute: 52.5, value: -2, series: 2),
            Point(minute: 67.5, value: 0, series: 2)
        ])
    }

    /// Meals on Today: the carbs and entries so far, fat, protein, energy (4 / 4 / 9 kcal a gram) and the carb
    /// equivalents for someone who logs fat or protein, the entries; no usual by now.
    @MainActor func testMealsToday() {
        var points = mealPoints(fat: true, skipped: [])
        points.append(MealPoint(id: "t2", actualDate: clock(6, 11), carbs: 45, fat: 20, protein: 30))
        let result = Stat.Provider.mealsResult(points, period: .days7, shown: .today, factor: 0.5, now: now, calendar: calendar)
        XCTAssertEqual(result.shown, .today)
        XCTAssertEqual(result.asOf, now)
        let meals = Stat.Meals(result)
        XCTAssertEqual(meals.shown, .today)
        let today = meals.today!
        XCTAssertEqual(
            today.dateRange,
            StatsFormatting.dateRange(DateInterval(start: day(6), end: day(7)), period: .today, now: now)
        )
        XCTAssertEqual(today.carbs, "75")
        XCTAssertEqual(today.entryCount, "2 entries")
        XCTAssertEqual(today.tiles.map(\.title), ["Fat", "Protein", "Energy", "Carb equiv."])
        // 4 × (75 + 30) + 9 × 20; (4 × 30 + 9 × 20) / 10 × 0.5
        XCTAssertEqual(today.tiles.map(\.value), ["20", "30", "600", "15"])
        XCTAssertEqual(today.tiles.map(\.unit), ["g", "g", "kcal", "g"])
        XCTAssertEqual(today.entries.map(\.carbs), ["30 g", "45 g"])
        XCTAssertEqual(today.entries.map(\.detail), [nil, "fat 20 g · protein 30 g"])
        XCTAssertEqual(Stat.Meals.Today.energy(carbs: 10, fat: 1, protein: 2), 57)

        // without fat or protein logged: no tiles; no entry yet today
        let plain = Stat.Meals(Stat.Provider.mealsResult(
            mealPoints(fat: false).filter { $0.id != "t" },
            period: .days7,
            shown: .today,
            factor: 0.5,
            now: now,
            calendar: calendar
        )).today!
        XCTAssertEqual(plain.tiles, [])
        XCTAssertEqual(plain.carbs, "0")
        XCTAssertEqual(plain.entryCount, "No entries")
        XCTAssertEqual(plain.entries, [])

        // 7–90 d: no Today view
        XCTAssertNil(Stat.Meals(mealsResult()).today)
        XCTAssertNil(Stat.Meals(mealsResult()).nutrients.today)
    }

    /// Nutrients on Today: each nutrient so far against its daily reference (salt against its limit, above it in
    /// orange), the coverage of today's entries; without references the rows grouped, salt's alone with a percent; a
    /// nutrient's screen: today's amount against its reference and today's entries.
    @MainActor func testNutrientsToday() {
        var points = nutrientPoints()
        points.append(MealPoint(id: "t-salt", actualDate: clock(6, 10), carbs: 20, micronutrients: [.salt: 6]))
        points.append(MealPoint(id: "t-plain", actualDate: clock(6, 11), carbs: 25))
        let result = Stat.Provider.mealsResult(points, period: .days7, shown: .today, factor: 0.5, now: now, calendar: calendar)
        let nutrients = Stat.Meals(result, references: woman).nutrients
        let today = nutrients.today!
        XCTAssertEqual(today.coverage, "Nutrient data on 2 of 3 entries")
        XCTAssertNil(today.emptyTitle)
        XCTAssertEqual(today.basis, nutrients.basis)
        XCTAssertEqual(today.index, 6)
        let rows = today.sections.flatMap(\.rows)
        XCTAssertEqual(today.sections.count, 1)
        // salt 6 g of 5: 120%, above the limit; fiber 3 of 25 g: 12%
        XCTAssertEqual(rows.prefix(2).map(\.name), ["Salt", "Fiber"])
        XCTAssertEqual(rows[0].percent, "120%")
        XCTAssertTrue(rows[0].isOverLimit)
        XCTAssertEqual(rows[1].amount, d("3.0 g"))
        XCTAssertEqual(rows[1].percent, "12%")

        let fiber = nutrients.todayDetail(.fiber)!
        XCTAssertEqual(fiber.name, "Fiber")
        XCTAssertEqual(fiber.reference, "12% of the 25 g reference intake")
        // Today's coverage, not the period chart's day status ("… averaged from midnight")
        XCTAssertEqual(fiber.coverage, today.coverage)
        XCTAssertNotEqual(fiber.coverage, fiber.card.status)
        XCTAssertEqual(fiber.card.title, "Today")
        XCTAssertEqual(fiber.card.amount, d("3.0"))
        XCTAssertEqual(fiber.card.entries.count, 3)
        XCTAssertNil(Stat.Meals(nutrientsResult(), references: woman).nutrients.todayDetail(.fiber), "7–90 d")

        // without references: grouped, salt alone with its limit
        let plain = Stat.Meals(result).nutrients.today!
        XCTAssertEqual(plain.sections.map(\.title), [nil, "Vitamins", "Minerals"])
        XCTAssertEqual(plain.sections.flatMap(\.rows).filter { $0.percent != nil }.map(\.name), ["Salt"])
        XCTAssertEqual(plain.basis, "Salt: the EFSA limit of 5 g a day.")

        // no nutrient data today, no entry today
        let noData = Stat.Meals(Stat.Provider.mealsResult(
            nutrientPoints().filter { $0.id != "t" } + [MealPoint(id: "t-plain", actualDate: clock(6, 11), carbs: 25)],
            period: .days7,
            shown: .today,
            factor: 0.5,
            now: now,
            calendar: calendar
        ), references: woman).nutrients.today!
        XCTAssertEqual(noData.emptyTitle, "No nutrient data so far today")
        XCTAssertEqual(noData.sections, [])
        XCTAssertEqual(noData.coverage, "Nutrient data on 0 of 1 entry")
        let noEntries = Stat.Meals(Stat.Provider.mealsResult(
            nutrientPoints().filter { $0.id != "t" },
            period: .days7,
            shown: .today,
            factor: 0.5,
            now: now,
            calendar: calendar
        ), references: woman).nutrients
        let none = noEntries.today!
        XCTAssertEqual(none.emptyTitle, "No carb entries so far today")
        // a nutrient's screen without an entry today: that, not "0 of 0 entries"
        XCTAssertEqual(noEntries.todayDetail(.fiber)?.coverage, "No carb entries so far today")
    }

    /// "Show Today" (today's column picked on 7–90 d) resets the tab's days to the day they open on, so 7–90 d picked
    /// after Today show yesterday again (the Meals tab's nutrients' too), another tab's kept; a period picked in the
    /// control keeps the day picked (as every tab: switching back restores it).
    @MainActor func testShowTodayResetsTheDays() {
        let days = (0 ..< 7).map { DateInterval(start: day($0), end: day($0 + 1)) }
        let insulin = DailySelection(opensOnLastCompleteDay: true)
        let meals = DailySelection(opensOnLastCompleteDay: true)
        let nutrient = DailySelection(opensOnLastCompleteDay: true)
        func pickToday() {
            for selection in [insulin, meals, nutrient] {
                selection.pick(6, in: days)
            }
        }

        pickToday()
        Stat.StateModel.resetDays(showingTodayOn: .insulin, insulin: insulin, meals: meals, nutrient: nutrient)
        XCTAssertNil(insulin.day)
        // 7 d next: yesterday
        XCTAssertEqual(insulin.index(in: days), 5)
        XCTAssertEqual(meals.index(in: days), 6)
        XCTAssertEqual(nutrient.index(in: days), 6)

        pickToday()
        Stat.StateModel.resetDays(showingTodayOn: .meals, insulin: insulin, meals: meals, nutrient: nutrient)
        XCTAssertEqual(insulin.index(in: days), 6)
        XCTAssertEqual(meals.index(in: days), 5)
        XCTAssertEqual(nutrient.index(in: days), 5)

        // the other tabs have no Today period: nothing reset
        pickToday()
        for tab in StatsTab.allCases where tab != .insulin && tab != .meals {
            Stat.StateModel.resetDays(showingTodayOn: tab, insulin: insulin, meals: meals, nutrient: nutrient)
        }
        XCTAssertEqual([insulin, meals, nutrient].map { $0.index(in: days) }, [6, 6, 6])

        // Today picked in the control, then 7 d: the day picked there (today's column, or another) stays
        insulin.pick(2, in: days)
        XCTAssertEqual(insulin.index(in: days), 2)
    }

    /// The Insulin and Meals tabs' days (7–90 d) open on yesterday, the last complete day (today has the Today period):
    /// kept as nil (it follows midnight); today picked is kept by its date; one day alone is that day.
    @MainActor func testDaySelectionOpensOnTheLastCompleteDay() {
        let days = (0 ..< 7).map { DateInterval(start: day($0), end: day($0 + 1)) }
        let selection = DailySelection(opensOnLastCompleteDay: true)
        XCTAssertEqual(selection.defaultIndex(dayCount: 7), 5)
        XCTAssertEqual(selection.index(in: days), 5)
        selection.pick(6, in: days)
        XCTAssertEqual(selection.day, day(6))
        XCTAssertEqual(selection.index(in: days), 6)
        selection.pick(5, in: days)
        XCTAssertNil(selection.day)
        selection.pick(2, in: days)
        XCTAssertEqual(selection.index(in: days), 2)
        selection.select(nil)
        // a longer period: still yesterday
        let longer = (-7 ..< 7).map { DateInterval(start: day($0), end: day($0 + 1)) }
        XCTAssertEqual(selection.index(in: longer), 12)
        // one day: that day; none: nil
        XCTAssertEqual(selection.index(in: [days[6]]), 0)
        XCTAssertNil(selection.index(in: []))
        // the glucose Days tab's: today
        XCTAssertEqual(DailySelection().defaultIndex(dayCount: 7), 6)
    }
}
