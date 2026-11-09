@testable import FreeAPS
import XCTest

/// The Unknown readings named by the user: the probable sensors and their suggestions (`CGMUnknownInference`), the
/// sessions the three ways make, and the CGM topic's result with them.
final class CGMUnknownTests: XCTestCase {
    // MARK: - Fixtures

    private static let t0 = StatsFixtures.day0
    private static let day = 1440.0

    /// `t0` plus the minutes
    private func at(_ minutes: Double) -> Date {
        Self.t0.addingTimeInterval(.minutes(minutes))
    }

    private struct Run {
        /// minutes
        let length: Double
        /// minutes between readings
        let every: Double
        /// minutes from the last reading before it
        var gapBefore: Double = 0
        /// mg/dL added to the wave: a new sensor's level step
        var offset: Double = 0
    }

    /// Consecutive runs from `t0`: a slow wave of the time (6 h, ±30 mg/dL: continuous across a gap), a little
    /// deterministic noise.
    private func readings(_ runs: [Run]) -> [GlucosePoint] {
        var points: [GlucosePoint] = []
        var start = 0.0
        for run in runs {
            if let last = points.last {
                start = last.time.timeIntervalSince(Self.t0) / 60 + run.gapBefore
            }
            for minute in stride(from: start, to: start + run.length, by: run.every) {
                let wave = 30 * sin(minute / 360 * 2 * .pi)
                let noise = Double(Int(minute / run.every) * 37 % 5) - 2
                points.append(GlucosePoint(time: at(minute), mgdl: Int16((130 + wave + noise + run.offset).rounded())))
            }
        }
        return points
    }

    private func libre(_ days: Double = 14, gapBefore: Double = 0, offset: Double = 0) -> Run {
        Run(length: days * Self.day, every: 1, gapBefore: gapBefore, offset: offset)
    }

    private func dexcom(_ days: Double = 10, gapBefore: Double = 0, offset: Double = 0) -> Run {
        Run(length: days * Self.day, every: 5, gapBefore: gapBefore, offset: offset)
    }

    private let known = CGMChoice.choices(recorded: [])

    private func choice(_ id: String) -> CGMChoice {
        known.first { $0.cgmId == id }!
    }

    private func suggestion(
        _ cgmId: String,
        _ confidence: CGMProbableSensor.Confidence,
        _ reason: CGMProbableSensor.Reason
    ) -> CGMProbableSensor.Suggestion? {
        CGMProbableSensor.Suggestion(cgmId: cgmId, confidence: confidence, reason: reason)
    }

    private func sensors(_ points: [GlucosePoint], choices: [CGMChoice]? = nil) -> [CGMProbableSensor] {
        CGMUnknownInference.sensors(points, allReadings: points.map(\.time), choices: choices ?? known)
    }

    private func recorded(
        _ cgmId: String,
        start: Date,
        end: Date? = nil,
        sensorStart: Date?,
        life: TimeInterval? = nil
    ) -> CGMSessionRecord {
        let known = choice(cgmId)
        return CGMSessionRecord(
            id: UUID(),
            start: start,
            end: end,
            CGMSnapshot(
                plugin: known.plugin,
                cgmId: cgmId,
                name: known.name,
                sensorStart: sensorStart,
                expectedLife: life ?? known.expectedLife,
                oneMinute: false,
                sensorId: nil
            )
        )
    }

    /// Every Unknown reading in a session: none left Unknown.
    private func assertCovers(
        _ sessions: [CGMSessionRecord],
        _ points: [GlucosePoint],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(CGMSessionAttribution.attribute(points, to: sessions).unknown.count, 0, file: file, line: line)
    }

    // MARK: - The probable sensors

    /// A Libre's 1-minute 14-day sensors, each after its 60-minute warm-up: one each, a Libre suggested (likely), the
    /// gap before each the warm-up.
    func testLibreSensorsAreSplitAtTheWarmupGapsAndSuggestALibre() {
        let points = readings([libre(), libre(gapBefore: 60), libre(gapBefore: 60)])
        let found = sensors(points)
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(found.map(\.readings), [20160, 20160, 20160])
        XCTAssertEqual(found.map(\.cadence), [60, 60, 60])
        XCTAssertEqual(found.map(\.gapBefore), [nil, .minutes(60), .minutes(60)])
        XCTAssertEqual(found.map(\.length), Array(repeating: .minutes(14 * Self.day - 1), count: 3))
        XCTAssertEqual(found.map(\.suggestion), Array(repeating: suggestion("libre3", .likely, .oneMinute), count: 3))
    }

    /// A Dexcom's 5-minute 10-day sensors after 30-minute gaps: one each, a Dexcom suggested (possible), the G7 unless
    /// a recorded session shows another (a G6: its 2-hour warm-up doesn't join them, its 10 days do not hold two).
    func testDexcomSensorsSuggestADexcomTheRecordedOneFirst() {
        let points = readings([dexcom(), dexcom(gapBefore: 30), dexcom(gapBefore: 30)])
        let found = sensors(points)
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(found.map(\.cadence), [300, 300, 300])
        XCTAssertEqual(found.map(\.suggestion), Array(repeating: suggestion("dexcomG7", .possible, .dexcomLength), count: 3))

        let g6 = recorded("dexcomG6", start: at(40 * Self.day), sensorStart: at(40 * Self.day))
        let withG6 = sensors(points, choices: CGMChoice.choices(recorded: [g6]))
        XCTAssertEqual(withG6.map(\.suggestion?.cgmId), ["dexcomG6", "dexcomG6", "dexcomG6"])
        XCTAssertEqual(CGMChoice.choices(recorded: [g6]).first?.isRecorded, true)
        XCTAssertEqual(CGMChoice.choices(recorded: [g6]).filter { $0.cgmId == "dexcomG6" }.count, 1)
    }

    /// 5-minute readings longer than any Dexcom suggest a Libre (possible); shorter than a Dexcom's 10 days, none of
    /// their own: the neighbouring sensor's.
    func testLengthsSuggestALibreOrTheNeighboursCGM() {
        let points = readings([dexcom(12), dexcom(gapBefore: 30), dexcom(4, gapBefore: 30)])
        let found = sensors(points)
        XCTAssertEqual(found.map(\.suggestion), [
            suggestion("libre3", .possible, .longerThanADexcom),
            suggestion("dexcomG7", .possible, .dexcomLength),
            suggestion("dexcomG7", .possible, .neighbour)
        ])
    }

    /// A switch from a Dexcom to a Libre after a 20-minute gap (shorter than a sensor change's): the cadence changes,
    /// so two sensors.
    func testACGMSwitchSplitsAtTheCadenceChange() {
        let points = readings([dexcom(), libre(gapBefore: 20)])
        let found = sensors(points)
        XCTAssertEqual(found.map(\.suggestion?.cgmId), ["dexcomG7", "libre3"])
        XCTAssertEqual(found.map(\.cadence), [300, 60])
        XCTAssertEqual(found.last?.gapBefore, .minutes(20))
    }

    /// A run shorter than 2 hours is no sensor; its readings go with the sensor before it.
    func testAShortRunIsNoSensor() {
        let points = readings([libre(), Run(length: 60, every: 1, gapBefore: 60), libre(gapBefore: 60)])
        let found = sensors(points)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.map(\.readings), [20160, 20160])
        // the gap before the second sensor is from the short run's last reading
        XCTAssertEqual(found.last?.gapBefore, .minutes(60))

        let sessions = CGMUnknownInference.sessions(
            for: .one(choice("libre3")),
            sensors: found,
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(sessions.count, 2)
        assertCovers(sessions, points)
        let shortRun = points[20160]
        XCTAssertTrue(sessions[0].contains(shortRun.time))
    }

    /// Dropouts that are no sensor change: a Dexcom's under 30 minutes, and a Libre's under its hour's warm-up, stay
    /// one sensor, with a jump in the level too while the two parts fit one sensor's life (a new sensor needs its
    /// warm-up between them unless started ahead, and then the two are longer than one lasts). A jump after a Libre's
    /// hour is a sensor change.
    func testDropoutsThatAreNoSensorChange() {
        let dexcomDropouts = readings([dexcom(3), dexcom(3, gapBefore: 10), dexcom(4, gapBefore: 25)])
        XCTAssertEqual(sensors(dexcomDropouts).count, 1)
        XCTAssertEqual(sensors(dexcomDropouts).first?.suggestion?.cgmId, "dexcomG7")

        let libreDropout = readings([libre(6), libre(8, gapBefore: 40)])
        let joined = sensors(libreDropout)
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined.first?.readings, libreDropout.count)

        let libreStep = readings([libre(6), libre(8, gapBefore: 40, offset: 40)])
        XCTAssertEqual(sensors(libreStep).count, 1)
        let libreWarmupStep = readings([libre(6), libre(8, gapBefore: 60, offset: 40)])
        XCTAssertEqual(sensors(libreWarmupStep).count, 2)

        let dexcomStep = readings([dexcom(5), dexcom(5, gapBefore: 20, offset: 40)])
        XCTAssertEqual(sensors(dexcomStep).count, 1)
        let dexcomNoStep = readings([dexcom(5), dexcom(5, gapBefore: 20)])
        XCTAssertEqual(sensors(dexcomNoStep).count, 1)
    }

    /// One sensor, not fragments: a 14-day Libre whose 1-minute readings jump 30–60 mg/dL after dropouts of 3 to 10
    /// minutes; a Dexcom's 10-minute dropout with a 30 mg/dL jump at the top of the wave (a level step: split, then
    /// joined again). Two: Libres after a 60-minute warm-up gap; 20 days of Libres without a gap (the life rule); a
    /// pre-soaked G7, 10 days and 10 days, back after one reading's time with a 40 mg/dL jump.
    func testOneSensorNotFragments() {
        let libreJumps = readings([
            libre(3),
            libre(4, gapBefore: 3, offset: 30),
            libre(4, gapBefore: 6, offset: -20),
            libre(3, gapBefore: 10, offset: 40)
        ])
        XCTAssertEqual(sensors(libreJumps).map(\.readings), [libreJumps.count])

        let dexcomJump = readings([Run(length: 4 * Self.day + 90, every: 5), dexcom(6, gapBefore: 15, offset: 30)])
        let jumpAt = dexcomJump.firstIndex { $0.time > at(4 * Self.day + 90) }!
        XCTAssertTrue(CGMUnknownInference.hasLevelStep(
            dexcomJump,
            before: 0 ..< jumpAt,
            after: jumpAt ..< dexcomJump.count
        ))
        XCTAssertEqual(sensors(dexcomJump).map(\.readings), [dexcomJump.count])

        XCTAssertEqual(sensors(readings([libre(), libre(gapBefore: 60, offset: 40)])).count, 2)
        XCTAssertEqual(
            sensors(readings([libre(10), libre(10, gapBefore: 1, offset: 40)])).map(\.readings),
            [14400, 14400]
        )
        XCTAssertEqual(sensors(readings([dexcom(), dexcom(gapBefore: 5, offset: 40)])).count, 2)
        XCTAssertEqual(sensors(readings([dexcom(), dexcom(gapBefore: 10, offset: 40)])).count, 2)
    }

    /// Dropouts of 45 and 90 minutes inside one sensor are joined again, one sensor without a sensor change: a
    /// Dexcom's (neither part long enough for a suggestion of its own) and a Libre's. Two real sensors aren't:
    /// together they are longer than one lasts.
    func testLongDropoutsInsideOneSensorAreJoined() {
        for gap in [45.0, 90] {
            let dexcomPoints = readings([dexcom(3), dexcom(7, gapBefore: gap)])
            let dexcomSensors = sensors(dexcomPoints)
            XCTAssertEqual(dexcomSensors.count, 1, "\(gap)")
            XCTAssertEqual(dexcomSensors.first?.readings, dexcomPoints.count, "\(gap)")
            XCTAssertEqual(dexcomSensors.first?.suggestion?.cgmId, "dexcomG7", "\(gap)")
            let librePoints = readings([libre(6), libre(8, gapBefore: gap)])
            XCTAssertEqual(sensors(librePoints).count, 1, "\(gap)")
            XCTAssertEqual(sensors(librePoints).first?.readings, librePoints.count, "\(gap)")
        }
        XCTAssertEqual(sensors(readings([dexcom(), dexcom(gapBefore: 45)])).count, 2)
        XCTAssertEqual(sensors(readings([libre(), libre(gapBefore: 90)])).count, 2)
    }

    /// Sensor changes without a long gap: a pre-soaked G7 back after 10 minutes with a jump; a switch to a Libre after
    /// 3 minutes and back to a Dexcom after 2 (the cadence changes); 28 days of 1-minute readings (an overlap: no gap
    /// of a sensor change) split at their largest gap, and, without any gap, at their largest step.
    func testSensorChangesWithoutALongGapAreSplit() {
        let presoaked = sensors(readings([dexcom(), dexcom(gapBefore: 10, offset: 40)]))
        XCTAssertEqual(presoaked.count, 2)
        XCTAssertEqual(presoaked.last?.gapBefore, .minutes(10))

        let switched = sensors(readings([dexcom(), libre(gapBefore: 3), dexcom(gapBefore: 2)]))
        XCTAssertEqual(switched.map(\.cadence), [300, 60, 300])
        XCTAssertEqual(switched.map(\.suggestion?.cgmId), ["dexcomG7", "libre3", "dexcomG7"])

        let overlap = sensors(readings([libre(), libre(gapBefore: 4)]))
        XCTAssertEqual(overlap.count, 2)
        XCTAssertEqual(overlap.last?.gapBefore, .minutes(4))
        XCTAssertEqual(overlap.map(\.readings), [20160, 20160])

        let seamless = sensors(readings([libre(), libre(gapBefore: 1, offset: 40)]))
        XCTAssertEqual(seamless.map(\.readings), [20160, 20160])
    }

    /// 1-minute readings when the only recorded CGM is an AppGroup source (a Libre read through xDrip4iOS): that
    /// source, not the Libre 3.
    func testOneMinuteReadingsSuggestARecordedAppGroupSource() {
        let points = readings([libre(3)])
        let xdrip = recorded("xdrip", start: at(5 * Self.day), sensorStart: nil)
        XCTAssertEqual(sensors(points, choices: CGMChoice.choices(recorded: [xdrip])).first?.suggestion?.cgmId, "xdrip")
        let libre2 = recorded("libreTransmitter", start: at(6 * Self.day), sensorStart: nil)
        XCTAssertEqual(
            sensors(points, choices: CGMChoice.choices(recorded: [xdrip, libre2])).first?.suggestion?.cgmId,
            "libreTransmitter"
        )
    }

    /// A sensor whose first reading is at the start of the readings read (the 90 days) began before them: flagged,
    /// and its session has no sensor start; the next one's has.
    func testASensorCutAtTheStartOfTheReadingsHasNoStart() {
        let points = readings([libre(), libre(gapBefore: 90)])
        let found = CGMUnknownInference.sensors(points, allReadings: points.map(\.time), choices: known, readFrom: at(-3))
        XCTAssertEqual(found.map(\.isCut), [true, false])
        let sessions = CGMUnknownInference.sessions(
            for: .one(choice("libre3")),
            sensors: found,
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(sessions.map(\.sensorStart), [nil, found[1].first.addingTimeInterval(-.hours(1))])
        XCTAssertEqual(sessions.first?.start, found[0].first)
        XCTAssertNil(sessions.first?.expectedLife)
        assertCovers(sessions, points)
        let later = CGMUnknownInference.sensors(points, allReadings: points.map(\.time), choices: known, readFrom: at(-60))
        XCTAssertEqual(later.map(\.isCut), [false, false])
    }

    /// The level step looks past a trend: a rise carried across the gap is no step, a jump off both the level and the
    /// trend is.
    func testALevelStepIsOffTheLevelAndTheTrend() {
        func points(_ values: [(Double, Double)]) -> [GlucosePoint] {
            values.map { GlucosePoint(time: at($0.0), mgdl: Int16($0.1)) }
        }
        // rising 2 mg/dL a minute, 20 minutes missing: 40 up is the trend
        let rising = points((0 ..< 16).map { (Double($0), 100 + 2 * Double($0)) } + [(35, 170), (36, 172), (37, 174)])
        XCTAssertFalse(CGMUnknownInference.hasLevelStep(rising, before: 0 ..< 16, after: 16 ..< 19))
        let flatThenJump = points((0 ..< 16).map { (Double($0), 100) } + [(35, 140), (36, 140), (37, 140)])
        XCTAssertTrue(CGMUnknownInference.hasLevelStep(flatThenJump, before: 0 ..< 16, after: 16 ..< 19))
    }

    // MARK: - The answer's sessions

    /// One CGM for all: a session per sensor, contiguous, covering every Unknown reading; each sensor from its first
    /// reading less the warm-up (the gap holds it), the first from its first reading.
    func testOneCGMForAllMakesASessionPerSensor() {
        let points = readings([libre(), libre(gapBefore: 90), libre(gapBefore: 60)])
        let found = sensors(points)
        let sessions = CGMUnknownInference.sessions(
            for: .one(choice("libre3")),
            sensors: found,
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions.map(\.cgmId), ["libre3", "libre3", "libre3"])
        XCTAssertEqual(sessions.map(\.source), [.entered, .entered, .entered])
        XCTAssertEqual(sessions.map(\.sensorStart), [
            found[0].first,
            found[1].first.addingTimeInterval(-.hours(1)),
            // a 60-minute gap: just after the old sensor's last reading
            found[2].first.addingTimeInterval(-.minutes(60) + 1)
        ])
        XCTAssertEqual(sessions.map(\.start), sessions.map { $0.sensorStart! })
        XCTAssertEqual(sessions[0].end, sessions[1].start)
        XCTAssertEqual(sessions[1].end, sessions[2].start)
        XCTAssertEqual(sessions[2].end, points.last!.time.addingTimeInterval(1))
        XCTAssertEqual(sessions.map(\.expectedLife), Array(repeating: .days(14), count: 3))
        XCTAssertEqual(sessions.map(\.oneMinute), [true, true, true])
        assertCovers(sessions, points)
        // each sensor's readings in its own session
        let attribution = CGMSessionAttribution.attribute(points, to: sessions)
        XCTAssertEqual(attribution.bySession.map(\.readings.count), [20160, 20160, 20160])
    }

    /// A switch date in the gap between two sensors: the sensors before it the first CGM's, after it the second's,
    /// nothing split. Inside a sensor: split there, the second CGM's from the date.
    func testASwitchDateSplitsAtIt() {
        let points = readings([dexcom(), dexcom(gapBefore: 30), libre(gapBefore: 90), libre(gapBefore: 60)])
        let found = sensors(points)
        XCTAssertEqual(found.count, 4)
        let g7 = choice("dexcomG7")
        let libre3 = choice("libre3")

        let inGap = found[2].first.addingTimeInterval(-.minutes(45))
        let atGap = CGMUnknownInference.sessions(
            for: .switched(at: inGap, before: g7, after: libre3),
            sensors: found,
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(atGap.map(\.cgmId), ["dexcomG7", "dexcomG7", "libre3", "libre3"])
        XCTAssertEqual(atGap[2].sensorStart, found[2].first.addingTimeInterval(-.hours(1)))
        assertCovers(atGap, points)

        let inside = found[1].first.addingTimeInterval(.days(2))
        let split = CGMUnknownInference.sessions(
            for: .switched(at: inside, before: g7, after: libre3),
            sensors: found,
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(split.map(\.cgmId), ["dexcomG7", "dexcomG7", "libre3", "libre3", "libre3"])
        XCTAssertEqual(split[1].end, inside)
        XCTAssertEqual(split[2].start, inside)
        XCTAssertEqual(split[2].sensorStart, inside)
        assertCovers(split, points)

        // on a sensor's first reading: that sensor the second CGM's whole, nothing split
        let onFirst = CGMUnknownInference.sessions(
            for: .switched(at: found[2].first, before: g7, after: libre3),
            sensors: found,
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(onFirst.map(\.cgmId), ["dexcomG7", "dexcomG7", "libre3", "libre3"])
        XCTAssertEqual(onFirst[2].sensorStart, found[2].first.addingTimeInterval(-.hours(1)))
        assertCovers(onFirst, points)
    }

    /// Sensor by sensor: each its CGM; one left out stays Unknown.
    func testBySensorLeavesASensorWithoutACGMUnknown() {
        let points = readings([dexcom(), libre(gapBefore: 90), libre(gapBefore: 60)])
        let found = sensors(points)
        let sessions = CGMUnknownInference.sessions(
            for: .bySensor([found[0].id: choice("dexcomG6"), found[2].id: choice("libreTransmitter")]),
            sensors: found,
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(sessions.map(\.cgmId), ["dexcomG6", "libreTransmitter"])
        // no reading before the first sensor: its start is its first reading
        XCTAssertEqual(sessions[0].sensorStart, found[0].first)
        XCTAssertEqual(sessions[0].end, found[1].first)
        let unknown = CGMSessionAttribution.attribute(points, to: sessions).unknown
        XCTAssertEqual(unknown.count, found[1].readings)
        XCTAssertEqual(unknown.first?.time, found[1].first)
    }

    /// Without a probable sensor (only short runs), one CGM for all is one session over them, its sensor start not
    /// known; by sensor there is nothing to name.
    func testWithoutProbableSensorsOneSessionCoversThem() {
        let points = readings([Run(length: 60, every: 5), Run(length: 60, every: 5, gapBefore: 120)])
        XCTAssertEqual(sensors(points), [])
        let one = CGMUnknownInference.sessions(
            for: .one(choice("dexcomG7")),
            sensors: [],
            unknownTimes: points.map(\.time),
            recorded: []
        )
        XCTAssertEqual(one.count, 1)
        XCTAssertNil(one.first?.sensorStart)
        XCTAssertNil(one.first?.expectedLife)
        assertCovers(one, points)
        XCTAssertEqual(
            CGMUnknownInference.sessions(for: .bySensor([:]), sensors: [], unknownTimes: points.map(\.time), recorded: []),
            []
        )
    }

    // MARK: - The CGM topic with entered sessions

    /// 4 Unknown days, then a recorded G7 whose sensor started before its recording, 30 minutes before the first
    /// Unknown reading: named the G7, they are that sensor's (its recorded start, one sensor row marked entered); the
    /// Unknown CGM is gone, the recording still starts at day 4.
    @MainActor func testEnteredSessionsMoveTheReadingsToTheirCGM() {
        let now = at(7 * Self.day)
        let window = DateInterval(start: at(0), end: now)
        let points = readings([dexcom(7)])
        let recordingStart = at(4 * Self.day)
        let g7 = recorded("dexcomG7", start: recordingStart, sensorStart: at(-30))
        let unknown = points.filter { $0.time < recordingStart }

        let input = Stat.Provider.cgmUnknownInput(readings: points, sessions: [g7], window: window)
        XCTAssertEqual(input.unknownTimes, unknown.map(\.time))
        XCTAssertEqual(input.sensors.count, 1)
        XCTAssertEqual(input.choices.first?.cgmId, "dexcomG7")
        XCTAssertEqual(input.choices.first?.isRecorded, true)

        let entered = CGMUnknownInference.sessions(
            for: .one(input.choices[0]),
            sensors: input.sensors,
            unknownTimes: input.unknownTimes,
            recorded: input.recorded
        )
        XCTAssertEqual(entered.map(\.sensorStart), [at(-30)])
        let result = Stat.Provider.cgmResult(
            readings: points,
            sessions: CGMEnteredSessions.effective([g7] + entered),
            period: .days7,
            window: window,
            generation: 0,
            now: now,
            calendar: StatsFixtures.berlin
        )
        XCTAssertEqual(result.cgms.map(\.pick), [.cgm("dexcomG7")])
        XCTAssertEqual(result.recordingStart, recordingStart)
        XCTAssertEqual(result.enteredSessions, 1)
        let g7Result = result.picks[.cgm("dexcomG7")]
        XCTAssertEqual(g7Result?.stats.readings, points.count)
        XCTAssertEqual(g7Result?.sensors.count, 1)
        XCTAssertEqual(g7Result?.sensors.first?.isEntered, true)
        let report = Stat.CGMReport(result, pick: nil, units: .mgdL, smoothing: .none, editor: CGMUnknownEditor())
        XCTAssertEqual(report.pick, .cgm("dexcomG7"))
        XCTAssertNil(report.unknown)
        XCTAssertEqual(report.entered?.text, "1 period entered by you")
        XCTAssertEqual(
            g7Result?.sensors.first.map { Stat.CGMReport.sensorRow($0, now: now, units: .mgdL).isEntered },
            true
        )

        // named a Libre 3 instead: two CGMs, the G7's readings from its recording's start
        let libre = CGMUnknownInference.sessions(
            for: .one(choice("libre3")),
            sensors: input.sensors,
            unknownTimes: input.unknownTimes,
            recorded: input.recorded
        )
        let switched = Stat.Provider.cgmResult(
            readings: points,
            sessions: CGMEnteredSessions.effective([g7] + libre),
            period: .days7,
            window: window,
            generation: 0,
            now: now,
            calendar: StatsFixtures.berlin
        )
        XCTAssertEqual(switched.cgms.map(\.pick), [.cgm("libre3"), .cgm("dexcomG7")])
        XCTAssertEqual(switched.picks[.cgm("dexcomG7")]?.stats.span?.start, recordingStart)
        XCTAssertEqual(switched.picks[.cgm("libre3")]?.stats.readings, unknown.count)

        // the sheet starts from what was entered
        let again = Stat.Provider.cgmUnknownInput(
            readings: points,
            sessions: CGMEnteredSessions.effective([g7] + libre),
            window: window
        )
        XCTAssertEqual(again.unknownTimes, unknown.map(\.time))
        XCTAssertEqual(again.entered, [input.sensors[0].id: "libre3"])
        XCTAssertEqual(again.enteredSessions, 1)
    }

    /// An entered session that ends where a recorded one of another CGM begins: the recorded one's boundary is kept
    /// (a CGM change), though its sensor started before its recording; one of the same sensor has none.
    func testAnEnteredSessionBeforeARecordedOneOfAnotherCGMKeepsTheBoundary() {
        let start = at(4 * Self.day)
        let g7 = recorded("dexcomG7", start: start, sensorStart: at(Self.day))
        var libre = recorded("libre3", start: at(0), end: start, sensorStart: at(0))
        libre.source = .entered
        XCTAssertEqual(Stat.Provider.sensorBoundary(bySession: [libre, g7]), [libre.id: at(0), g7.id: start])
        var sameSensor = recorded("dexcomG7", start: at(0), end: start, sensorStart: at(Self.day))
        sameSensor.source = .entered
        XCTAssertEqual(Stat.Provider.sensorBoundary(bySession: [sameSensor, g7]), [sameSensor.id: at(Self.day)])
    }

    // MARK: - Entered sessions, read

    /// An entered session as the sheet makes it.
    private func entered(
        _ cgmId: String,
        start: Date,
        end: Date,
        sensorStart: Date?,
        life: TimeInterval? = nil
    ) -> CGMSessionRecord {
        var session = recorded(cgmId, start: start, end: end, sensorStart: sensorStart, life: life)
        session.source = .entered
        return session
    }

    /// The first reading of each run (after a gap of more than its cadence).
    private func runFirsts(_ points: [GlucosePoint], every: Double = 1) -> [Date] {
        [points[0].time] + zip(points, points.dropFirst())
            .filter { $1.time.timeIntervalSince($0.time) > .minutes(every) }
            .map(\.1.time)
    }

    /// One entered session per run, each from its first reading (its inferred sensor start) to the next one's, the
    /// last to just after its last reading: what the old rule's answer made of a Libre with jumps after dropouts.
    private func fragments(_ points: [GlucosePoint], _ cgmId: String = "libre3") -> [CGMSessionRecord] {
        let firsts = runFirsts(points)
        return firsts.indices.map { index in
            entered(
                cgmId,
                start: firsts[index],
                end: index + 1 < firsts.count ? firsts[index + 1] : points.last!.time.addingTimeInterval(1),
                sensorStart: firsts[index]
            )
        }
    }

    private func topic(_ points: [GlucosePoint], _ sessions: [CGMSessionRecord], now: Date) -> Stat.CGMResult {
        Stat.Provider.cgmResult(
            readings: points,
            sessions: sessions,
            period: .days30,
            window: DateInterval(start: at(0), end: now),
            generation: 0,
            now: now,
            calendar: StatsFixtures.berlin
        )
    }

    /// A Libre the old rule split in four at its jumps, entered so: read as one sensor, one session from the first
    /// one's start (its id and sensor start) to the last one's end; one Sensors row, not ended early, one sensor day
    /// 1. The readings fetched for it: the three boundaries, the two close ones in one window. Unjoined, the
    /// fragments' rows and sensor days, the last one alone ended early (no reading after it).
    @MainActor func testTouchingEnteredSessionsOfOneSensorAreJoined() {
        let points = readings([
            libre(4.5),
            Run(length: 240, every: 1, gapBefore: 3, offset: 30),
            Run(length: 480, every: 1, gapBefore: 5, offset: -10),
            libre(9, gapBefore: 8, offset: 30)
        ])
        let sessions = fragments(points)
        XCTAssertEqual(sessions.count, 4)
        let windows = CGMUnknownInference.joinWindows(sessions)
        XCTAssertEqual(windows.count, 2)
        for session in sessions.dropFirst() {
            XCTAssertTrue(windows.contains { $0.contains(session.start) })
        }

        let joined = CGMUnknownInference.joinedEntered(sessions, readings: points)
        XCTAssertEqual(joined.map(\.id), [sessions[0].id])
        XCTAssertEqual(joined.first?.start, sessions[0].start)
        XCTAssertEqual(joined.first?.end, sessions[3].end)
        XCTAssertEqual(joined.first?.sensorStart, sessions[0].sensorStart)

        let now = points.last!.time.addingTimeInterval(.days(1))
        let result = topic(points, joined, now: now)
        let libre = result.picks[.cgm("libre3")]
        XCTAssertEqual(libre?.sensors.count, 1)
        XCTAssertEqual(libre?.sensorsBySensorDay[1], 1)
        XCTAssertNil(libre?.sensors.first.map { Stat.CGMReport.sensorRow($0, now: now, units: .mgdL) }?.earlyText)

        let fragmented = topic(points, sessions, now: now).picks[.cgm("libre3")]
        XCTAssertEqual(fragmented?.sensorsBySensorDay[1], 4)
        XCTAssertEqual(
            fragmented?.sensors.map { Stat.CGMReport.sensorRow($0, now: now, units: .mgdL).earlyText },
            ["Ended early", nil, nil, nil]
        )
    }

    /// Never joined: across a recorded session, into a session whose start is a recorded sensor's, across a change of
    /// CGM; nor two that together are longer than a sensor lasts.
    func testEnteredSessionsJoinedOnlyWithinOneSensor() {
        let points = readings([libre(4), libre(4, gapBefore: 3, offset: 30), libre(4, gapBefore: 3, offset: -20)])
        let parts = fragments(points)
        XCTAssertEqual(parts.count, 3)

        var withRecorded = parts
        withRecorded[1].source = .recorded
        XCTAssertEqual(CGMUnknownInference.joinedEntered(withRecorded, readings: points).count, 3)

        let recordedSensor = recorded("libre3", start: at(20 * Self.day), sensorStart: parts[1].sensorStart)
        XCTAssertEqual(
            CGMUnknownInference.joinedEntered(parts + [recordedSensor], readings: points).map(\.id),
            [parts[0].id, parts[1].id, recordedSensor.id]
        )

        let switched = [parts[0], fragments(points, "libreTransmitter")[1], parts[2]]
        XCTAssertEqual(CGMUnknownInference.joinedEntered(switched, readings: points).count, 3)

        let long = readings([libre(10), libre(10, gapBefore: 3, offset: 30)])
        XCTAssertEqual(CGMUnknownInference.joinedEntered(fragments(long), readings: long).count, 2)
    }

    /// Ended early when something ended it: a short entered sensor, then a 60-minute gap before the next one (as the
    /// sheet makes it, from the warm-up before its first reading); not when the next one goes straight on from it,
    /// its start inferred (too long together to be joined).
    @MainActor func testEndedEarlyOnlyWhenSomethingEndedIt() {
        let afterGap = readings([libre(3), libre(gapBefore: 60)])
        let firsts = runFirsts(afterGap)
        let warmupStart = firsts[1].addingTimeInterval(-.minutes(60) + 1)
        let gapSessions = [
            entered("libre3", start: firsts[0], end: warmupStart, sensorStart: firsts[0]),
            entered("libre3", start: warmupStart, end: afterGap.last!.time.addingTimeInterval(1), sensorStart: warmupStart)
        ]
        let gapNow = afterGap.last!.time.addingTimeInterval(.hours(1))
        let gapRows = topic(afterGap, gapSessions, now: gapNow).picks[.cgm("libre3")]?.sensors ?? []
        XCTAssertEqual(gapRows.count, 2)
        XCTAssertEqual(gapRows.last.map { Stat.CGMReport.sensorRow($0, now: gapNow, units: .mgdL).earlyText }, "Ended early")
        XCTAssertEqual(gapRows.last?.hasEndCause, true)

        let straightOn = readings([libre(3), libre(gapBefore: 3, offset: 40)])
        let straightSessions = fragments(straightOn)
        XCTAssertEqual(CGMUnknownInference.joinedEntered(straightSessions, readings: straightOn).count, 2)
        let straightNow = straightOn.last!.time.addingTimeInterval(.hours(1))
        let straightRows = topic(straightOn, straightSessions, now: straightNow).picks[.cgm("libre3")]?.sensors ?? []
        XCTAssertEqual(straightRows.count, 2)
        XCTAssertEqual(straightRows.last?.hasEndCause, false)
        XCTAssertNil(straightRows.last.map { Stat.CGMReport.sensorRow($0, now: straightNow, units: .mgdL) }?.earlyText)
    }

    /// A sensor whose readings all fall before the period, the next one going straight on from it inside the period:
    /// its last reading is taken from before the period, so it isn't "no reading after" and not ended early.
    @MainActor func testASensorEndingJustBeforeThePeriodIsNotEndedEarly() {
        let points = readings([libre(3), libre(gapBefore: 3, offset: 40)])
        let sessions = fragments(points)
        let second = sessions[1].start
        let now = points.last!.time.addingTimeInterval(.hours(1))
        // the first sensor's last reading 3 minutes before the second's first, the period from 2 minutes before it
        let window = DateInterval(start: second.addingTimeInterval(-.minutes(2)), end: now)
        XCTAssertLessThan(points.last { $0.time < second }!.time, window.start)
        let result = Stat.Provider.cgmResult(
            readings: points,
            sessions: sessions,
            period: .days30,
            window: window,
            generation: 0,
            now: now,
            calendar: StatsFixtures.berlin
        )
        let rows = result.picks[.cgm("libre3")]?.sensors ?? []
        XCTAssertEqual(rows.map(\.id), [sessions[1].id, sessions[0].id])
        XCTAssertEqual(rows.last?.hasEndCause, false)
        XCTAssertNil(rows.last.map { Stat.CGMReport.sensorRow($0, now: now, units: .mgdL) }?.earlyText)
        // the readings before the period count nowhere else
        XCTAssertEqual(result.picks[.cgm("libre3")]?.stats.span?.start, second)
    }

    /// Entered sessions older than the sheet's 90 days: not counted, no Change; Clear stays.
    @MainActor func testEnteredSessionsOlderThanTheSheetsDaysOnlyClear() {
        let now = at(7 * Self.day)
        let window = DateInterval(start: at(0), end: now)
        var old = recorded("libre3", start: at(-200 * Self.day), end: at(-190 * Self.day), sensorStart: at(-200 * Self.day))
        old.source = .entered
        let result = Stat.Provider.cgmResult(
            readings: readings([dexcom(7)]),
            sessions: [old],
            period: .days7,
            window: window,
            generation: 0,
            now: now,
            calendar: StatsFixtures.berlin
        )
        XCTAssertEqual(result.enteredSessions, 0)
        XCTAssertTrue(result.hasEnteredSessions)
        let report = Stat.CGMReport(result, pick: .unknown, units: .mgdL, smoothing: .none, editor: CGMUnknownEditor())
        XCTAssertEqual(report.unknown?.entered?.canChange, false)
        XCTAssertEqual(report.unknown?.entered?.text, "What you entered is older than 90 days.")
    }

    /// The Unknown card has the editor (its "Which CGM was this?"), and what was entered when some is.
    @MainActor func testTheUnknownCardCarriesTheEditor() {
        let now = at(7 * Self.day)
        let window = DateInterval(start: at(0), end: now)
        let points = readings([dexcom(7)])
        let result = Stat.Provider.cgmResult(
            readings: points,
            sessions: [],
            period: .days7,
            window: window,
            generation: 0,
            now: now,
            calendar: StatsFixtures.berlin
        )
        let editor = CGMUnknownEditor()
        let report = Stat.CGMReport(result, pick: .unknown, units: .mgdL, smoothing: .none, editor: editor)
        XCTAssertTrue(report.unknown?.editor === editor)
        XCTAssertNil(report.unknown?.entered)
        XCTAssertNil(report.entered)
    }
}
