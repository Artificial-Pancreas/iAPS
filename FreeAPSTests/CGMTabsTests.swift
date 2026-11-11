@testable import FreeAPS
import SwiftUI
import XCTest

/// The CGM topic: its views and periods (the title menu, CGM last), the result's CGMs and their readings (attributed to
/// the CGM sessions), the sensors merged, the cache, and the smoothing analysis's runs.
final class CGMTabsTests: XCTestCase {
    // MARK: - Fixtures

    private static let calendar = StatsFixtures.berlin

    /// 2026-10-16 12:00: the 7 days are 10–16 Oct
    private var now: Date { StatsFixtures.week.addingTimeInterval(.days(6) + .hours(12)) }
    private var window: DateInterval { DateInterval(start: StatsFixtures.week, end: now) }

    /// A reading every 5 minutes in `[from, to)`: a slow wave, a little deterministic noise.
    private func readings(from: Date, to: Date) -> [GlucosePoint] {
        stride(from: from.timeIntervalSince1970, to: to.timeIntervalSince1970, by: 300).enumerated().map { index, seconds in
            let wave = 40 * sin(Double(index) / 30)
            let noise = Double((index * 37) % 7) - 3
            return GlucosePoint(time: Date(timeIntervalSince1970: seconds), mgdl: Int16(130 + wave + noise))
        }
    }

    private func session(
        _ cgmId: String?,
        name: String,
        start: Date,
        end: Date?,
        sensorStart: Date?,
        life: TimeInterval? = nil,
        id: Int
    ) -> CGMSessionRecord {
        CGMSessionRecord(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", id))!,
            start: start,
            end: end,
            CGMSnapshot(
                plugin: cgmId ?? "AppGroup",
                cgmId: cgmId,
                name: name,
                sensorStart: sensorStart,
                expectedLife: life,
                oneMinute: false,
                sensorId: nil
            )
        )
    }

    private func day(_ offset: Double) -> Date {
        StatsFixtures.week.addingTimeInterval(.days(offset))
    }

    private func result(_ readings: [GlucosePoint], _ sessions: [CGMSessionRecord], generation: Int = 0) -> Stat.CGMResult {
        Stat.Provider.cgmResult(
            readings: readings,
            sessions: sessions,
            period: .days7,
            window: window,
            generation: generation,
            now: now,
            calendar: Self.calendar
        )
    }

    /// Unknown on the first day, a Dexcom G7 for three, a Libre 3 (started two hours ahead) since.
    private var threeCGMs: (readings: [GlucosePoint], sessions: [CGMSessionRecord]) {
        (
            readings(from: window.start, to: now),
            [
                session("dexcomG7", name: "Dexcom G7", start: day(1), end: day(4), sensorStart: day(1), life: .days(10.5), id: 1),
                session(
                    "libre3",
                    name: "Libre 3",
                    start: day(4),
                    end: nil,
                    sensorStart: day(4).addingTimeInterval(-.hours(2)),
                    life: .days(14),
                    id: 2
                )
            ]
        )
    }

    // MARK: - Tabs

    /// Three views in a topic of their own, the last of the title menu, with 7/14/30/90 d (Today and 24 h as 7 d); the
    /// glucose unit is a setting they depend on, the bands aren't.
    @MainActor func testTabsPeriodsAndMenu() {
        XCTAssertEqual(StatsTopic.allCases.last, .cgm)
        XCTAssertEqual(StatsTopic.cgm.views, [.cgmOverview, .cgmSensors, .cgmSmoothing])
        XCTAssertEqual(Array(StatsTab.allCases.suffix(3)), StatsTopic.cgm.views)
        for tab in StatsTopic.cgm.views {
            XCTAssertTrue(tab.isCGM)
            XCTAssertEqual(tab.topic, .cgm)
            XCTAssertEqual(tab.validPeriods, [.days7, .days14, .days30, .days90])
            XCTAssertTrue(tab.hasPeriodControl)
            XCTAssertTrue(tab.usesSettings)
            XCTAssertFalse(tab.usesBands)
            XCTAssertFalse(tab.isGlucose)
            XCTAssertEqual(Stat.StateModel.nearest(.today, in: tab.validPeriods), .days7)
            XCTAssertEqual(Stat.StateModel.nearest(.last24h, in: tab.validPeriods), .days7)
            XCTAssertEqual(Stat.StateModel.nearest(.weeks13, in: tab.validPeriods), .days90)
            XCTAssertNotNil(UIImage(systemName: StatsViewMenu.systemImage(tab)), "\(tab)")
        }
        XCTAssertEqual(StatsViewMenu.title(StatsTopic.cgm), "CGM")
        XCTAssertEqual(StatsTopic.cgm.views.map { StatsViewMenu.title($0) }, ["Overview", "Sensors", "Smoothing"])
        XCTAssertEqual(StatsViewMenu.navigationTitle(.cgmSensors), "CGM · Sensors")
        XCTAssertEqual(
            StatsTopic.cgm.views.map { StatsViewMenu.systemImage($0) },
            [
                "sensor",
                "timeline.selection",
                "point.bottomleft.forward.to.point.topright.scurvepath"
            ]
        )
    }

    // MARK: - The CGMs

    /// The readings go to the session holding them, by CGM; those no session holds are Unknown. The picker lists the
    /// named CGMs by their first reading, Unknown last; no pick pools them.
    @MainActor func testReadingsAttributedToTheirCGM() {
        let (readings, sessions) = threeCGMs
        let result = result(readings, sessions)
        XCTAssertEqual(result.cgms.map(\.pick), [.cgm("dexcomG7"), .cgm("libre3"), .unknown])
        XCTAssertEqual(result.cgms.map(\.name), ["Dexcom G7", "Libre 3", "Unknown"])
        let g7 = readings.filter { $0.time >= day(1) && $0.time < day(4) }.count
        let libre = readings.filter { $0.time >= day(4) }.count
        let unknown = readings.filter { $0.time < day(1) }.count
        XCTAssertEqual(result.picks[.cgm("dexcomG7")]?.stats.readings, g7)
        XCTAssertEqual(result.picks[.cgm("libre3")]?.stats.readings, libre)
        XCTAssertEqual(result.picks[.unknown]?.stats.readings, unknown)
        XCTAssertEqual(result.picks[.cgm("libre3")]?.stats.cadence, 300)
        XCTAssertEqual(result.recordingStart, day(1))
        XCTAssertNil(result.picks[.unknown]?.stats.noiseBySensorDay[1])

        // the picker: the CGMs; a CGM picked is shown, one the period lacks (or none) the newest reading's
        let report = Stat.CGMReport(result, pick: .cgm("dexcomG7"), units: .mmolL, smoothing: .none)
        XCTAssertEqual(report.picker.map(\.pick), [.cgm("dexcomG7"), .cgm("libre3"), .unknown])
        XCTAssertEqual(report.picker.map(\.title), ["Dexcom G7", "Libre 3", "Unknown"])
        XCTAssertEqual(report.picker.map(\.label), ["G7", "Libre 3", "Unknown"])
        XCTAssertEqual(report.pick, .cgm("dexcomG7"))
        XCTAssertNil(report.unknown)
        XCTAssertEqual(result.defaultPick, .cgm("libre3"))
        XCTAssertEqual(result.shown(.cgm("dexcomG6")), .cgm("libre3"))
        XCTAssertEqual(result.shown(nil), .cgm("libre3"))
        XCTAssertEqual(Stat.CGMReport(result, pick: nil, units: .mmolL, smoothing: .none).pick, .cgm("libre3"))
        XCTAssertEqual(report.overview.readings.title, "Dexcom G7")
        // By CGM on every pick of two or more, without the gaps
        XCTAssertEqual(report.overview.comparison?.columns, ["G7", "Libre 3", "Unknown"])
        XCTAssertEqual(
            report.overview.comparison?.rows.map(\.name),
            ["Time", "Cadence", "Coverage", "Noise", "Delta jitter", "Reversals"]
        )
        // Unknown: its explainer, no sensors
        let unknownReport = Stat.CGMReport(result, pick: .unknown, units: .mgdL, smoothing: .none)
        XCTAssertNotNil(unknownReport.unknown)
        XCTAssertEqual(unknownReport.sensors.rows, [])
        XCTAssertTrue(unknownReport.overview.readings.tiles[1].unit?.hasPrefix("mg/dL") ?? false)

        // Unknown alone, or with the newest reading: a named CGM first
        let unknownOnly = self.result(readings, [])
        XCTAssertEqual(unknownOnly.defaultPick, .unknown)
        let laterUnknown = self.result(readings, [sessions[0]])
        XCTAssertEqual(laterUnknown.cgms.map(\.pick), [.cgm("dexcomG7"), .unknown])
        XCTAssertEqual(laterUnknown.defaultPick, .cgm("dexcomG7"))
    }

    /// The picker's short names: every statistics id `KnownPlugins.cgmIdForStatistics` gives (AppGroup's by its source
    /// app), any other CGM its name cut at a word.
    @MainActor func testShortNames() {
        let ids = [
            "dexcomG5": "G5", "dexcomG6": "G6", "dexcomG7": "G7", "libre3": "Libre 3", "libreTransmitter": "Libre 2",
            "eversense": "Eversense", "nightscout": "Nightscout", "simulator": "Simulator", "enlite": "Enlite",
            "xdrip": "xDrip", "glucoseDirect": "Glucose Direct"
        ]
        for (id, short) in ids {
            XCTAssertEqual(CGMFormat.shortName(.cgm(id), name: "A long manager title"), short, id)
        }
        XCTAssertEqual(CGMFormat.shortName(.unknown, name: "Unknown"), "Unknown")
        // another plugin or source app: its name, cut at a word
        XCTAssertEqual(CGMFormat.shortName(.cgm("Spike"), name: "Spike"), "Spike")
        XCTAssertEqual(CGMFormat.shortName(.cgm("plugin:SomeCGM"), name: "Dexcom ONE+ Bridge"), "Dexcom ONE+…")
        XCTAssertEqual(CGMFormat.shortName(.cgm("other"), name: "Supercalifragilistic CGM"), "Supercalifr…")
        XCTAssertEqual(CGMFormat.cut("Twelve chars"), "Twelve chars")
    }

    /// One CGM in the period: no picker, the CGM named; no Unknown without readings no session holds.
    @MainActor func testOneCGMHidesThePicker() {
        let readings = readings(from: window.start, to: now)
        let sessions = [session("dexcomG7", name: "Dexcom G7", start: day(-2), end: nil, sensorStart: day(-2), id: 1)]
        let result = result(readings, sessions)
        XCTAssertEqual(result.cgms.map(\.pick), [.cgm("dexcomG7")])
        XCTAssertNil(result.picks[.unknown])
        XCTAssertEqual(result.shown(nil), .cgm("dexcomG7"))
        XCTAssertEqual(result.shown(.cgm("libre3")), .cgm("dexcomG7"))
        let report = Stat.CGMReport(result, pick: .cgm("libre3"), units: .mmolL, smoothing: .none)
        XCTAssertEqual(report.picker, [])
        XCTAssertEqual(report.pick, .cgm("dexcomG7"))
        XCTAssertEqual(report.overview.readings.title, "Dexcom G7")
        XCTAssertNil(report.overview.comparison)
        // no readings at all: empty
        XCTAssertTrue(self.result([], sessions).isEmpty)
    }

    /// The sensor boundaries: a sensor that started with its session, a session after another; not the first session of
    /// a sensor already running when the recording began, nor one opened without a start.
    func testSensorBoundaries() {
        let first = session("dexcomG7", name: "Dexcom G7", start: day(1), end: day(3), sensorStart: day(-4), id: 1)
        let next = session(
            "dexcomG7",
            name: "Dexcom G7",
            start: day(3),
            end: day(5),
            sensorStart: day(3).addingTimeInterval(.minutes(30)),
            id: 2
        )
        let switched = session("libre3", name: "Libre 3", start: day(5), end: nil, sensorStart: day(2), id: 3)
        let sensorless = session(nil, name: "Nightscout", start: day(8), end: nil, sensorStart: nil, id: 4)
        XCTAssertEqual(
            Stat.Provider.sensorBoundaries([switched, first, next]),
            [day(3).addingTimeInterval(.minutes(30)), day(5)]
        )
        XCTAssertEqual(Stat.Provider.sensorBoundaries([sensorless]), [])
        XCTAssertEqual(Stat.Provider.readingsStart(switched), day(5))
    }

    // MARK: - Sensors

    /// A CGM switched away and back is one sensor: its sessions merged by CGM and sensor start, in use from its first
    /// start; the one between ended at the change, a row with its dates, its bar and no tag.
    @MainActor func testSensorsMergedAcrossASwitch() {
        let g7Start = day(0.5)
        let sessions = [
            session("dexcomG7", name: "Dexcom G7", start: g7Start, end: day(2), sensorStart: g7Start, life: .days(10.5), id: 1),
            session("libre3", name: "Libre 3", start: day(2), end: day(3), sensorStart: day(1.9), life: .days(14), id: 2),
            session(
                "dexcomG7",
                name: "Dexcom G7",
                start: day(3),
                end: nil,
                sensorStart: g7Start.addingTimeInterval(20),
                life: .days(10.5),
                id: 3
            )
        ]
        let groups = Stat.Provider.mergedSensors(sessions)
        XCTAssertEqual(groups.map { $0.map(\.id) }, [[sessions[0].id, sessions[2].id], [sessions[1].id]])

        let result = result(readings(from: window.start, to: now), sessions)
        let g7Sensors = result.picks[.cgm("dexcomG7")]?.sensors ?? []
        XCTAssertEqual(g7Sensors.map(\.name), ["Dexcom G7"])
        let g7 = g7Sensors[0]
        XCTAssertEqual(g7.start, g7Start)
        XCTAssertNil(g7.end)
        XCTAssertTrue(g7.isInUse)
        XCTAssertEqual(g7.grace, Stat.Provider.dexcomG7Grace)
        let libre = result.picks[.cgm("libre3")]?.sensors.first
        XCTAssertEqual(libre?.end, day(3))
        let row = libre.map { Stat.CGMReport.sensorRow($0, now: now, units: .mmolL) }
        XCTAssertEqual(row?.isInUse, false)
        XCTAssertEqual(row?.isEntered, false)
        XCTAssertEqual(row?.isBackfilled, false)
        // from its sensor start: 1.1 of 14 days
        XCTAssertEqual(row?.bar ?? 0, 1.1 / 14, accuracy: 1E-9)

        // the G7 picked: one sensor across the Libre 3's day, its sensor days going on
        let ownG7 = result.picks[.cgm("dexcomG7")]
        XCTAssertEqual(ownG7.map { $0.stats.noiseBySensorDay.keys.sorted() }, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ownG7?.sensorsBySensorDay[1], 1)
        XCTAssertEqual(result.picks[.cgm("libre3")]?.sensorsBySensorDay[1], 1)
    }

    /// A sensor's row: its dates and length, its bar of its life without the grace (a G7's; none for another CGM), its
    /// noise. How it ended isn't shown: a sensor well short of its life has its bar alone.
    @MainActor func testSensorRows() {
        let sessions = [
            session("dexcomG7", name: "Dexcom G7", start: day(0.5), end: day(2), sensorStart: day(0.5), life: .days(10.5), id: 1),
            session("libre3", name: "Libre 3", start: day(2).addingTimeInterval(.hours(2)), end: nil, sensorStart: day(2), id: 2)
        ]
        let result = result(readings(from: window.start, to: now), sessions)
        let g7 = result.picks[.cgm("dexcomG7")]?.sensors.first
        let row = g7.map { Stat.CGMReport.sensorRow($0, now: now, units: .mmolL) }
        XCTAssertEqual(row?.isInUse, false)
        // of its life without the grace: 1.5 of 10 days
        XCTAssertEqual(row?.bar ?? 0, 0.15, accuracy: 1E-9)

        func sensor(length: TimeInterval) -> Stat.CGMSensor {
            Stat.CGMSensor(
                id: UUID(),
                pick: .cgm("dexcomG7"),
                name: "Dexcom G7",
                start: day(-10),
                sensorStart: day(-10),
                end: day(-10).addingTimeInterval(length),
                expectedLife: .days(10.5),
                grace: Stat.Provider.dexcomG7Grace,
                noise: CGMNoise(mgdl: 3, fraction: 0.02, count: 100)
            )
        }
        XCTAssertEqual(Stat.CGMReport.sensorRow(sensor(length: .days(9)), now: now, units: .mgdL).bar ?? 0, 0.9, accuracy: 1E-9)
        // the dates and the length only, no life or grace; the bar full from the end of the life on; the noise
        let row9 = Stat.CGMReport.sensorRow(sensor(length: .days(9) + .hours(13)), now: now, units: .mgdL)
        let start = Stat.Patches.dayAndTime(day(-10))
        let end = Stat.Patches.dayAndTime(day(-1).addingTimeInterval(.hours(13)))
        XCTAssertEqual(row9.span, start + " – " + end + " · 9 d 13 h")
        XCTAssertEqual(row9.bar ?? 0, 9.5417 / 10, accuracy: 1E-4)
        XCTAssertEqual(row9.noise, "noise " + CGMFormat.fine(3, units: .mgdL) + " mg/dL")
        XCTAssertEqual(Stat.CGMReport.sensorRow(sensor(length: .days(10.4)), now: now, units: .mgdL).bar, 1)
        // in use: to now; without a life no bar, without noise no line
        let inUse = Stat.CGMSensor(
            id: UUID(),
            pick: .cgm("libre3"),
            name: "Libre 3",
            start: day(4),
            sensorStart: day(4),
            end: nil,
            expectedLife: nil,
            grace: 0,
            noise: nil
        )
        let inUseRow = Stat.CGMReport.sensorRow(inUse, now: now, units: .mgdL)
        XCTAssertEqual(inUseRow.span, Stat.Patches.dayAndTime(day(4)) + " – now · 2 d 12 h")
        XCTAssertNil(inUseRow.bar)
        XCTAssertNil(inUseRow.noise)
        XCTAssertTrue(inUseRow.isInUse)
    }

    /// A period starting inside a sensor: its sensor days go on from its start, its row from it.
    @MainActor func testAPeriodStartingMidSensor() {
        let sessions =
            [session("libre3", name: "Libre 3", start: day(-3), end: nil, sensorStart: day(-3), life: .days(14), id: 1)]
        let result = result(readings(from: window.start, to: now), sessions)
        let sensor = result.picks[.cgm("libre3")]?.sensors.first
        XCTAssertEqual(sensor?.lifeStart, day(-3))
        XCTAssertEqual(result.picks[.cgm("libre3")].map { $0.stats.noiseBySensorDay.keys.sorted() }, [4, 5, 6, 7, 8, 9, 10])
        let row = sensor.map { Stat.CGMReport.sensorRow($0, now: now, units: .mmolL) }
        XCTAssertTrue(row?.span.hasPrefix(Stat.Patches.dayAndTime(day(-3)) + " – now · 9 d 12 h") ?? false)
        XCTAssertNotNil(row?.noise)
        XCTAssertTrue(row?.isInUse ?? false)
    }

    /// A session without a statistics id is its plugin's, named by the session; without a name either, Unknown. The
    /// Unknown readings all before the first session are said to be; some after it aren't. Whole days without "0 h".
    @MainActor func testNamesAndUnknownWording() {
        let named = session(nil, name: "xDrip4iOS", start: day(1), end: day(3), sensorStart: nil, id: 1)
        let nameless = session(nil, name: "", start: day(4), end: day(5), sensorStart: nil, id: 2)
        let result = result(readings(from: window.start, to: now), [named, nameless])
        XCTAssertEqual(result.cgms.map(\.name), ["xDrip4iOS", "Unknown"])
        XCTAssertEqual(result.cgms.first?.pick, .cgm(Stat.Provider.pluginPickPrefix + "AppGroup"))
        // Unknown before day 1 and after day 3: not all before the recording
        let mixed = Stat.CGMReport(result, pick: .unknown, units: .mmolL, smoothing: .none)
        XCTAssertEqual(mixed.unknown?.detail, "")
        XCTAssertTrue(mixed.unknown?.body.hasPrefix("Readings no recorded CGM session covers") ?? false)
        XCTAssertEqual(mixed.sensors.emptyText, "Sensors weren’t recorded.")

        let (readings, sessions) = threeCGMs
        let before = Stat.CGMReport(self.result(readings, sessions), pick: .unknown, units: .mmolL, smoothing: .none)
        XCTAssertTrue(before.unknown?.detail.hasPrefix("before ") ?? false)
        XCTAssertTrue(before.unknown?.body.hasPrefix("Readings from before iAPS recorded") ?? false)

        XCTAssertEqual(CGMFormat.days(.days(10)), "10 d")
        XCTAssertEqual(CGMFormat.days(.days(6) + .hours(19)), "6 d 19 h")
    }

    // MARK: - Speed

    /// 90 days as a phone has them: 60 days of a 1-minute Libre 3 entered in touching fragments (four per sensor, as an
    /// earlier answer split them), then 30 of a recorded 5-minute G7, a few dropouts; about 95,000 readings. The
    /// topic's compute and its parts, timed and printed; the whole well under the bound.
    @MainActor func testNinetyDaysComputeInTime() {
        let end = now
        let start = end.addingTimeInterval(-.days(90))
        let switchAt = start.addingTimeInterval(.days(60))
        var points: [GlucosePoint] = []
        points.reserveCapacity(100_000)
        var seed: UInt64 = 7
        func noise() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 40) / Double(1 << 24) * 8 - 4
        }
        func add(every step: TimeInterval, from: Date, to: Date) {
            var time = from
            var index = 0
            while time < to {
                // a dropout of 20 minutes every 2 days
                if index % Int(TimeInterval.days(2) / step) >= Int(TimeInterval.minutes(20) / step) {
                    let minutes = time.timeIntervalSince(start) / 60
                    points.append(GlucosePoint(time: time, mgdl: Int16(140 + 50 * sin(minutes / 200) + noise())))
                }
                time = time.addingTimeInterval(step)
                index += 1
            }
        }
        add(every: .minutes(1), from: start, to: switchAt)
        add(every: .minutes(5), from: switchAt, to: end)

        var sessions: [CGMSessionRecord] = []
        var id = 100
        for sensor in 0 ..< 4 {
            let sensorStart = start.addingTimeInterval(.days(15 * Double(sensor)))
            let sensorEnd = Swift.min(sensorStart.addingTimeInterval(.days(15)), switchAt)
            for part in 0 ..< 4 {
                let partStart = sensorStart.addingTimeInterval(sensorEnd.timeIntervalSince(sensorStart) * Double(part) / 4)
                let partEnd = sensorStart.addingTimeInterval(sensorEnd.timeIntervalSince(sensorStart) * Double(part + 1) / 4)
                var fragment = session(
                    "libre3",
                    name: "Libre 3",
                    start: partStart,
                    end: partEnd,
                    sensorStart: partStart,
                    life: .days(14.5),
                    id: id
                )
                fragment.source = .entered
                sessions.append(fragment)
                id += 1
            }
        }
        for sensor in 0 ..< 3 {
            let sensorStart = switchAt.addingTimeInterval(.days(10 * Double(sensor)))
            sessions.append(session(
                "dexcomG7",
                name: "Dexcom G7",
                start: sensorStart,
                end: sensor == 2 ? nil : sensorStart.addingTimeInterval(.days(10)),
                sensorStart: sensorStart,
                life: .days(10.5),
                id: id
            ))
            id += 1
        }
        let window = DateInterval(start: start, end: end)

        func time<T>(_ label: String, _ work: () -> T) -> (T, TimeInterval) {
            let started = Date()
            let value = work()
            let seconds = Date().timeIntervalSince(started)
            print("CGM timing: \(label): \(Int((seconds * 1000).rounded())) ms")
            return (value, seconds)
        }
        print("CGM timing: \(points.count) readings, \(sessions.count) sessions")
        let (attribution, _) = time("attribution") { CGMSessionAttribution.attribute(points, to: sessions) }
        let libre = attribution.bySession.filter { $0.session.cgmId == "libre3" }.flatMap(\.readings)
        let g7 = attribution.bySession.filter { $0.session.cgmId == "dexcomG7" }.flatMap(\.readings)
        let (cleaned, _) = time("cleaning") { CGMStatsEngine.cleaned(libre, in: window, now: end) }
        let starts = sessions.filter { $0.cgmId == "libre3" }.map(\.start)
        let (analysis, _) = time("engine, Libre 3") {
            CGMStatsEngine.analysed(readings: cleaned, sensorStarts: starts, period: window, now: end)
        }
        _ = time("engine, G7") { CGMStatsEngine.stats(readings: g7, sensorStarts: [], period: window, now: end) }
        let libreParts = attribution.bySession.filter { $0.session.cgmId == "libre3" }
        let (own, _) = time("noise, the Libre 3's 16 sensors, alone") {
            libreParts.map { CGMStatsEngine.noise(readings: $0.readings, period: window, now: end) }
        }
        let (reused, _) = time("noise, the Libre 3's 16 sensors, from its segments") {
            libreParts.map {
                CGMStatsEngine.noise(readings: $0.readings, period: window, now: end, reusing: analysis.residuals)
            }
        }
        XCTAssertEqual(reused, own)
        _ = time("joining the entered sessions") { CGMUnknownInference.joinedEntered(sessions, readings: points) }
        let (result, total) = time("cgmResult") {
            Stat.Provider.cgmResult(
                readings: points,
                sessions: sessions,
                period: .days90,
                window: window,
                generation: 0,
                now: end,
                calendar: Self.calendar
            )
        }
        _ = time("report") { Stat.CGMReport(result, pick: nil, units: .mmolL, smoothing: .none) }
        XCTAssertEqual(result.cgms.map(\.pick), [.cgm("libre3"), .cgm("dexcomG7")])
        XCTAssertEqual(result.defaultPick, .cgm("dexcomG7"))
        XCTAssertEqual(result.picks[.cgm("libre3")]?.sensors.count, 16)
        XCTAssertEqual(result.picks[.cgm("dexcomG7")]?.sensors.count, 3)
        XCTAssertLessThan(total, 5)
    }

    // MARK: - The cache

    /// Kept for its key: another generation (a readings change) or other sessions compute it again.
    func testTheCacheKeepsAResultForItsKey() async throws {
        let cache = CGMCache()
        let counter = Counter()
        let value = result([], [])
        let compute: @Sendable() async throws -> Stat.CGMResult = {
            await counter.add()
            return value
        }
        func key(_ generation: Int, _ sessions: [CGMSessionRecord] = []) -> Stat.CGMCacheKey {
            Stat.CGMCacheKey(
                period: .days7,
                windowStart: window.start,
                generation: generation,
                timeZone: "Europe/Berlin",
                sessions: sessions
            )
        }
        _ = try await cache.result(key: key(1), compute: compute)
        _ = try await cache.result(key: key(1), compute: compute)
        let once = await counter.count
        XCTAssertEqual(once, 1)
        _ = try await cache.result(key: key(2), compute: compute)
        let twice = await counter.count
        XCTAssertEqual(twice, 2)
        let changed = [session("libre3", name: "Libre 3", start: day(1), end: nil, sensorStart: day(1), id: 9)]
        _ = try await cache.result(key: key(2, changed), compute: compute)
        let thrice = await counter.count
        XCTAssertEqual(thrice, 3)
    }

    // MARK: - Smoothing

    private func replayResult(lag: Double = 3, levelRelative: Double = 0.1) -> SmoothingReplayResult {
        func scores(_ values: [SmoothingMetric: Double]) -> SmoothingScores {
            SmoothingScores(
                measures: values.mapValues { SmoothingMeasure(value: $0, count: 10) },
                lowsNotCrossed: 0,
                loopTimes: 100
            )
        }
        let none = SmoothingCandidateResult(
            candidate: .none,
            scores: scores([.reversals: 73, .deltaJitter: 3, .wrongWay: 0.06, .lag: 0, .levelError: 2, .deltaError: 3]),
            changes: [:]
        )
        let kalman = SmoothingCandidateResult(
            candidate: .kalman(.balanced),
            scores: scores([.reversals: 50, .deltaJitter: 1.5, .wrongWay: 0.05, .lag: lag, .levelError: 2.2, .deltaError: 2.5]),
            changes: [
                .reversals: SmoothingChange(difference: -23, relative: -23 / 73),
                .lag: SmoothingChange(difference: lag, relative: nil),
                .wrongWay: SmoothingChange(difference: -0.01, relative: -1 / 6),
                .levelError: SmoothingChange(difference: 0.2, relative: levelRelative)
            ]
        )
        return SmoothingReplayResult(
            period: window,
            loopTimes: 100,
            results: [none, kalman],
            referenceReversals: SmoothingMeasure(value: 42, count: 10),
            sensitivity: SmoothingRankingSensitivity(
                halfWidths: SmoothingReplay.referenceHalfWidths,
                deltaErrorOrder: [[.kalman(.balanced), .none], [.kalman(.balanced), .none], [.none, .kalman(.balanced)]],
                lagOrder: [[.none, .kalman(.balanced)], [.none, .kalman(.balanced)], [.none, .kalman(.balanced)]]
            )
        )
    }

    /// The current setting is its candidate, marked in the tables; the difference-only scores (lag) are differences,
    /// the others' changes percents, wrong-way deltas in points; the ranking callout only when it changes.
    @MainActor func testCurrentSettingAndTheTables() {
        var settings = GlucoseSmoothingSettings()
        settings.algorithm = .kalman
        settings.kalman.responsiveness = .balanced
        XCTAssertEqual(SmoothingCandidate(settings), .kalman(.balanced))
        settings.algorithm = .savitzkyGolay
        settings.savitzkyGolay.passes = .two
        XCTAssertEqual(SmoothingCandidate(settings), .savitzkyGolay(.two))
        XCTAssertEqual(SmoothingCandidate(GlucoseSmoothingSettings()), .none)

        let tables = CGMSmoothingTables(replayResult(), current: .kalman(.balanced), units: .mgdL)
        XCTAssertEqual(tables.trendRows.map(\.isCurrent), [false, true])
        XCTAssertEqual(tables.trendRows.map(\.isBaseline), [true, false])
        XCTAssertEqual(tables.trendRows[0].cells, ["73", CGMFormat.fine(3, units: .mgdL), "6%"])
        XCTAssertEqual(tables.trendRows[1].cells[0], "−32%")
        XCTAssertEqual(tables.trendRows[1].cells[2], "−1 pt")
        XCTAssertEqual(tables.referenceRows[1].cells[0], "+3 m")
        XCTAssertEqual(tables.referenceRows[1].cells[3], "+10%")
        XCTAssertNotNil(tables.ranking)
        XCTAssertEqual(CGMSmoothingTables.fullName(.kalman(.balanced)), "Kalman filter · Balanced")
        XCTAssertEqual(CGMSmoothingTables.fullName(.savitzkyGolay(.one)), "Savitzky-Golay · 1 pass")

        let steady = replayResult()
        let unchanged = SmoothingReplayResult(
            period: steady.period,
            loopTimes: steady.loopTimes,
            results: steady.results,
            referenceReversals: steady.referenceReversals,
            sensitivity: SmoothingRankingSensitivity(
                halfWidths: SmoothingReplay.referenceHalfWidths,
                deltaErrorOrder: Array(repeating: [.kalman(.balanced), .none], count: 3),
                lagOrder: Array(repeating: [.none, .kalman(.balanced)], count: 3)
            )
        )
        XCTAssertNil(CGMSmoothingTables(unchanged, current: .none, units: .mmolL).ranking)
    }

    /// Idle, running, done; the same key again is the result kept, no new run; content read after newer readings shows
    /// it noted, and Analyse again runs anew; a run cancelled is idle (or the result it was replacing) and its late
    /// result dropped; a failed read says so.
    @MainActor func testSmoothingRuns() async {
        let runs = CGMSmoothingRuns()
        let key = CGMSmoothingRuns.Key(period: .days30, windowStart: window.start, pick: .cgm("libre3"))
        let analysedAt = now
        XCTAssertEqual(runs.status(key, readingsSeq: 5), .idle)
        let gate = Gate()
        let calls = Counter()
        let result = replayResult()
        let replay: CGMSmoothingRuns.Replay = { _, isCancelled, _ in
            await calls.add()
            await gate.wait()
            return isCancelled() ? nil : result
        }
        runs.analyse(key, readingsSeq: 5, now: analysedAt, replay: replay)
        XCTAssertEqual(runs.status(key, readingsSeq: 5), .running(0))
        await gate.open()
        await runs.finished()
        XCTAssertEqual(runs.status(key, readingsSeq: 5), .done(result, analysedAt: analysedAt, newerReadings: false))

        // the result kept: no new run
        runs.analyse(key, readingsSeq: 5, replay: replay)
        XCTAssertNil(runs.running)
        let once = await calls.count
        XCTAssertEqual(once, 1)

        // newer readings: the result, noted; Analyse again runs anew
        XCTAssertEqual(runs.status(key, readingsSeq: 6), .done(result, analysedAt: analysedAt, newerReadings: true))
        let later = analysedAt.addingTimeInterval(.minutes(20))
        runs.analyse(key, readingsSeq: 6, now: later, replay: replay)
        await runs.finished()
        let twice = await calls.count
        XCTAssertEqual(twice, 2)
        XCTAssertEqual(runs.status(key, readingsSeq: 6), .done(result, analysedAt: later, newerReadings: false))

        // cancelled: idle, its late result dropped
        let other = CGMSmoothingRuns.Key(period: .days14, windowStart: window.start, pick: .cgm("libre3"))
        let held = Gate()
        runs.analyse(other, readingsSeq: 6) { _, isCancelled, _ in
            await held.wait()
            return isCancelled() ? nil : result
        }
        XCTAssertEqual(runs.status(other, readingsSeq: 6), .running(0))
        runs.cancel()
        XCTAssertEqual(runs.status(other, readingsSeq: 6), .idle)
        await held.open()
        await runs.finished()
        XCTAssertEqual(runs.status(other, readingsSeq: 6), .idle)
        XCTAssertNil(runs.results[other])
        XCTAssertEqual(runs.status(key, readingsSeq: 6), .done(result, analysedAt: later, newerReadings: false))

        let failing = CGMSmoothingRuns.Key(period: .days7, windowStart: window.start, pick: .unknown)
        runs.analyse(failing, readingsSeq: 6) { _, _, _ in throw CocoaError(.fileReadUnknown) }
        await runs.finished()
        XCTAssertEqual(runs.status(failing, readingsSeq: 6), .failed)
    }

    /// A readings change in the newest minutes (each new reading) leaves the content as it is; one before them (a
    /// backfill, an edit) or of everything invalidates it; content older than those minutes is read again.
    func testCGMContentInvalidation() {
        typealias Model = Stat.StateModel
        let window = Model.cgmTrailingWindow
        XCTAssertFalse(Model.cgmChangeInvalidates(
            StatsChange(seq: 1, interval: DateInterval(start: now.addingTimeInterval(-.minutes(5)), end: now)),
            now: now
        ))
        XCTAssertTrue(Model.cgmChangeInvalidates(
            StatsChange(seq: 2, interval: DateInterval(start: now.addingTimeInterval(-window - 60), end: now)),
            now: now
        ))
        XCTAssertTrue(Model.cgmChangeInvalidates(StatsChange(seq: 3, interval: nil), now: now))
        XCTAssertFalse(Model.cgmContentIsStale(asOf: now.addingTimeInterval(-.minutes(10)), now: now))
        XCTAssertTrue(Model.cgmContentIsStale(asOf: now.addingTimeInterval(-window - 1), now: now))
        XCTAssertFalse(Model.cgmContentIsStale(asOf: nil, now: now))
    }
}

/// A call count across tasks.
private actor Counter {
    private(set) var count = 0

    func add() {
        count += 1
    }
}

/// Held until opened; open stays open.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
