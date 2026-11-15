@testable import FreeAPS
import JavaScriptCore
import XCTest

private typealias Replay = SmoothingReplay

/// The smoothing replay: the `glucose-get-last` port against the bundled JS, the replay against the live pipeline's own
/// functions (what the loop saw, never the revised history), the trimmed windows against the full 24 h, the scores on
/// synthetic signals, cancellation and progress, short inputs and the sensor-change split. Seeded noise throughout.
final class SmoothingReplayTests: XCTestCase {
    // MARK: - Fixtures

    /// 2026-10-20 00:00 Europe/Berlin (CEST)
    private static let day0 = StatsFixtures.day0

    private func at(_ minutes: Double) -> Date {
        Self.day0.addingTimeInterval(.minutes(minutes))
    }

    /// SplitMix64, with normal deviates by Box-Muller: the same noise on every run.
    private struct SeededRandom {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// [0, 1)
        mutating func uniform() -> Double {
            Double(next() >> 11) / Double(UInt64(1) << 53)
        }

        mutating func gaussian() -> Double {
            let u1 = Swift.max(uniform(), .leastNonzeroMagnitude)
            let u2 = uniform()
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    /// Readings every `step` minutes for `minutes`, the value a function of the minutes from `day0`, rounded.
    private func series(every step: Double, for minutes: Double, from start: Double = 0, _ value: (Double) -> Double)
        -> [GlucosePoint]
    {
        stride(from: start, to: start + minutes, by: step).map { minute in
            GlucosePoint(time: at(minute), mgdl: Int16(value(minute).rounded()))
        }
    }

    /// Real-shaped readings from `day0`: three meal rises a day (fast up, slow down), a night dip below 70 every other
    /// day, autocorrelated sensor noise plus white noise, jittered timestamps, gaps of 10, 14, 16 and 70 min, a few
    /// error codes (39), and the level stepping +20 at `sensorChange` (minutes), the new sensor's offset. Without
    /// `gaps`, a segment can be longer than the 24 h window.
    private func realShaped(
        days: Double,
        every step: Double,
        seed: UInt64 = 7,
        sensorChange: Double? = nil,
        gaps hasGaps: Bool = true
    ) -> [GlucosePoint] {
        var random = SeededRandom(seed: seed)
        var noise = 0.0
        let gaps: [ClosedRange<Double>] = hasGaps
            ? [300 ... 310, 1000 ... 1014, 1700 ... 1716, 2500 ... 2570, 3300 ... 3316]
            : []
        var points: [GlucosePoint] = []
        for minute in stride(from: 0, to: days * 1440, by: step) {
            noise = 0.8 * noise + 2.5 * random.gaussian()
            let jitter = (random.uniform() - 0.5) * (step >= 5 ? 40 : 10) // s
            guard !gaps.contains(where: { $0.contains(minute.truncatingRemainder(dividingBy: 4000)) }) else { continue }
            let clock = minute.truncatingRemainder(dividingBy: 1440)
            var value = 115.0
            for meal in [450.0, 760, 1150] {
                let since = clock - meal
                if since > 0 {
                    value += 90 * (1 - exp(-since / 25)) * exp(-since / 90)
                }
            }
            let day = Int(minute / 1440)
            if day.isMultiple(of: 2) {
                let fromDip = clock - 200
                value -= 60 * exp(-(fromDip * fromDip) / (2 * 18 * 18))
            }
            if let sensorChange, minute >= sensorChange {
                value += 20
            }
            let reading = random.uniform() < 0.002 ? 39 : min(max(value + noise + random.gaussian(), 40), 400)
            points.append(GlucosePoint(
                time: at(minute).addingTimeInterval(jitter),
                mgdl: Int16(reading.rounded())
            ))
        }
        return points
    }

    /// A session from `start` (minutes); its sensor starts then, unless `withSensorStart` is false (a CGM that reports
    /// none).
    private func session(from start: Double, until end: Double?, withSensorStart: Bool = true) -> CGMSessionRecord {
        CGMSessionRecord(
            id: UUID(),
            start: at(start),
            end: end.map { at($0) },
            CGMSnapshot(
                plugin: "test",
                cgmId: "test",
                name: "Test",
                sensorStart: withSensorStart ? at(start) : nil,
                expectedLife: .days(10),
                oneMinute: false,
                sensorId: nil
            )
        )
    }

    private func period(from start: Double, to end: Double) -> DateInterval {
        DateInterval(start: at(start), end: at(end))
    }

    /// The readings as the live pipeline holds them: `BloodGlucose`, newest -> oldest, stamped with the session's
    /// sensor start as the CGM stamps them (nil from a CGM without one).
    private func liveGlucose(_ readings: [GlucosePoint], sessions: [CGMSessionRecord]) -> [BloodGlucose] {
        readings
            .sorted { $0.time > $1.time }
            .map { point in
                BloodGlucose(
                    glucose: Int(point.mgdl),
                    date: Decimal(Int(point.time.timeIntervalSince1970 * 1000)),
                    dateString: point.time,
                    type: GlucoseType.sgv.rawValue,
                    sessionStartDate: sessions.last { $0.contains(point.time) }?.sensorStart
                )
            }
    }

    /// The live pipeline at `time`, with its own functions: the readings of the 24 h before (`liveGlucose`),
    /// `GlucoseSmoothing.smooth`, `FrequentGlucoseFiltering`, then the entries oref gets.
    private func liveEntries(_ glucose: [BloodGlucose], candidate: SmoothingCandidate, at time: Date) -> [OrefGlucoseEntry] {
        let window = glucose.filter { $0.dateString > time.addingTimeInterval(-.hours(24)) && $0.dateString <= time }
        let smoothed = candidate.smoother.map { GlucoseSmoothing.smooth(window, using: $0) } ?? window
        return FrequentGlucoseFiltering.filterFrequentGlucose(smoothed, interval: FrequentGlucoseFiltering.fiveMinuteInterval)
            .map { OrefGlucoseEntry(date: Int($0.dateString.timeIntervalSince1970 * 1000), glucose: $0.glucose) }
    }

    /// Thread-safe values for the `@Sendable` callbacks.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Double] = []
        private var _calls = 0

        var values: [Double] {
            lock.lock()
            defer { lock.unlock() }
            return _values
        }

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return _calls
        }

        func record(_ value: Double) {
            lock.lock()
            _values.append(value)
            lock.unlock()
        }

        /// counts a call; true from the `limit`th on
        func call(limit: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            _calls += 1
            return _calls >= limit
        }
    }

    // MARK: - glucose-get-last against the bundled JS

    /// The bundle's `glucose-get-last` module: its webpack module table (`var iaps;(()=>{var <name>={`, whatever the
    /// minifier named it) is exposed by a patch of the bundle's opening, and the module whose source builds the status
    /// object (not autoISF's) is instantiated.
    private func bundledGlucoseGetLast() throws -> (JSContext, JSValue) {
        let source = Script(name: OpenAPS.Bundle.oref0).body
        let opening = try NSRegularExpression(pattern: #"^var iaps;\(\(\)=>\{var (\w+)=\{"#)
        let whole = NSRange(source.startIndex..., in: source)
        guard let match = opening.firstMatch(in: source, range: whole),
              let range = Range(match.range, in: source), let name = Range(match.range(at: 1), in: source)
        else {
            XCTFail("the bundle doesn't open with its webpack module table: the patch below needs updating")
            throw CocoaError(.featureUnsupported)
        }
        let patched = "var __orefModules;var iaps;(()=>{var \(source[name])=__orefModules={" + source[range.upperBound...]
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(patched)
        // only the module table is needed: whatever the bundle's entry made of this context is left behind
        context.exception = nil
        let found = context.evaluateScript("""
        (function () {
          var found = [];
          for (var key in __orefModules) {
            var text = String(__orefModules[key]);
            if (text.indexOf('last_cal:') >= 0 && text.indexOf('long_avgdelta:Math.round') >= 0
                && text.indexOf('dura_ISF') < 0) { found.push(key); }
          }
          if (found.length !== 1) { return 'modules found: ' + found.length; }
          var module = { exports: {} };
          __orefModules[found[0]](module, module.exports, function () { throw new Error('require'); });
          globalThis.__glucoseGetLast = module.exports;
          return 'ok';
        })()
        """)?.toString()
        XCTAssertEqual(found, "ok")
        return try (context, XCTUnwrap(context.objectForKeyedSubscript("__glucoseGetLast")))
    }

    private func jsStatus(_ function: JSValue, _ context: JSContext, _ entries: [OrefGlucoseEntry]) -> OrefGlucoseStatus? {
        let input: [[String: Any]] = entries.map { entry in
            var object: [String: Any] = [
                "date": entry.date,
                "dateString": Date(timeIntervalSince1970: Double(entry.date) / 1000).ISO8601Format(),
                "sgv": entry.glucose,
                "glucose": entry.glucose
            ]
            object["type"] = entry.type
            object["device"] = entry.device
            return object
        }
        context.exception = nil
        guard let result = function.call(withArguments: [JSValue(object: input, in: context) as Any]),
              result.isObject, context.exception == nil
        else { return nil }
        return OrefGlucoseStatus(
            glucose: result.forProperty("glucose").toDouble(),
            delta: result.forProperty("delta").toDouble(),
            shortAvgDelta: result.forProperty("short_avgdelta").toDouble(),
            longAvgDelta: result.forProperty("long_avgdelta").toDouble(),
            date: Int(result.forProperty("date").toDouble()),
            lastCal: Int(result.forProperty("last_cal").toInt32())
        )
    }

    func testPortEqualsTheBundledJS() throws {
        let (context, function) = try bundledGlucoseGetLast()
        let base = Int(Self.day0.timeIntervalSince1970 * 1000)
        func entry(_ minutesAgo: Double, _ glucose: Int, type: String? = "sgv", device: String? = nil) -> OrefGlucoseEntry {
            OrefGlucoseEntry(date: base - Int(minutesAgo * 60000), glucose: glucose, type: type, device: device)
        }

        var fixtures: [[OrefGlucoseEntry]] = [
            // one entry; 5-minute; 1-minute
            [entry(0, 120)],
            stride(from: 0.0, to: 60, by: 5).map { entry($0, 120 - Int($0)) },
            stride(from: 0.0, to: 60, by: 1).map { entry($0, 100 + Int($0 * 1.7) % 23) },
            // the bounds themselves (2.5, 7.5, 17.5, 42.5 exclusive), and past 42.5 the walk stops
            [entry(0, 100), entry(2.5, 98), entry(7.5, 93), entry(17.5, 90), entry(42.5, 80), entry(43, 70), entry(50, 1)],
            // error codes skipped (39, 38), a falsy glucose dropped, the newest an error code
            [entry(0, 110), entry(5, 39), entry(10, 38), entry(12, 0), entry(15, 104), entry(30, 99)],
            [entry(0, 38), entry(5, 120), entry(10, 125)],
            // a calibration ends the walk; another device is skipped
            [entry(0, 140), entry(5, 135), entry(7, 140, type: "cal"), entry(10, 130)],
            [entry(0, 140, device: "a"), entry(5, 100, device: "b"), entry(6, 130, device: "a"), entry(20, 120)],
            // duplicate time (0 minutes: infinite delta, not pushed); rounding halves (±x.xx5)
            [entry(0, 100), entry(0, 98), entry(4, 99), entry(8, 97)],
            [entry(0, 101), entry(8 / 3.0, 100), entry(16 / 3.0, 100), entry(20, 97), entry(40, 96)],
            // no 2.5-7.5 entry: delta is short_avgdelta
            [entry(0, 150), entry(10, 140), entry(15, 135), entry(25, 120)]
        ]
        var random = SeededRandom(seed: 3)
        for _ in 0 ..< 300 {
            var minutes = 0.0
            var list: [OrefGlucoseEntry] = []
            let step = random.uniform() < 0.5 ? 1.0 : 5.0
            while minutes < 60 {
                let glucose = random.uniform() < 0.05 ? 39 : 60 + Int(random.uniform() * 200)
                list.append(entry(minutes, glucose, type: random.uniform() < 0.01 ? "cal" : "sgv"))
                minutes += step * (0.5 + random.uniform()) + (random.uniform() < 0.05 ? 15 : 0)
            }
            fixtures.append(list)
        }
        // what the live pipeline gives oref, real-shaped
        let glucose = liveGlucose(realShaped(days: 1.2, every: 1), sessions: [])
        for candidate in SmoothingCandidate.all {
            for minute in stride(from: 1450.0, to: 1720, by: 37) {
                fixtures.append(liveEntries(glucose, candidate: candidate, at: at(minute)))
            }
        }

        for (index, fixture) in fixtures.enumerated() {
            XCTAssertEqual(GlucoseGetLast.status(fixture), jsStatus(function, context, fixture), "fixture \(index)")
        }
        XCTAssertNil(GlucoseGetLast.status([]))
    }

    func testJSRoundingHalvesGoUp() {
        XCTAssertEqual(GlucoseGetLast.jsRound(2.5), 3)
        XCTAssertEqual(GlucoseGetLast.jsRound(-2.5), -2)
        XCTAssertEqual(GlucoseGetLast.jsRound(0.49999999999999994), 0)
        XCTAssertEqual(GlucoseGetLast.jsRound(-0.6), -1)
    }

    // MARK: - What the loop saw

    /// The replay's status at a loop time is the live pipeline's on the 24 h before it: no revised history.
    func testReplayEqualsTheLivePipeline() {
        for step in [1.0, 5.0] {
            let readings = realShaped(days: 2, every: step, seed: UInt64(step), sensorChange: 2000)
            let sessions = [session(from: -2000, until: 2000), session(from: 2000, until: nil)]
            let candidates: [SmoothingCandidate] = [
                .none, .savitzkyGolay(.one), .savitzkyGolay(.three), .kalman(.balanced), .kalman(.responsive), .exponential
            ]
            let replayPeriod = period(from: 1500, to: 2880)
            guard let snapshots = Replay.loopStatuses(
                readings: readings,
                sessions: sessions,
                period: replayPeriod,
                candidates: candidates,
                now: at(2880)
            ) else { return XCTFail("cancelled") }
            XCTAssertGreaterThan(snapshots.loopTimes.count, 200)

            let glucose = liveGlucose(readings, sessions: sessions)
            // every 23rd loop time, and every one in the 20 min after the sensor change
            let afterChange = at(2000) ... at(2020)
            let sampled = Set(stride(from: 0, to: snapshots.loopTimes.count, by: 23))
                .union(snapshots.loopTimes.indices.filter { afterChange.contains(snapshots.loopTimes[$0]) })
            XCTAssertGreaterThanOrEqual(sampled.count - Set(stride(from: 0, to: snapshots.loopTimes.count, by: 23)).count, 3)
            for position in snapshots.loopTimes.indices {
                let time = snapshots.loopTimes[position]
                for (index, candidate) in candidates.enumerated() {
                    // every loop time for one Savitzky-Golay and one Kalman candidate
                    guard sampled.contains(position) || candidate == .savitzkyGolay(.three) || candidate == .kalman(.balanced)
                    else { continue }
                    let live = GlucoseGetLast.status(liveEntries(glucose, candidate: candidate, at: time))
                    XCTAssertEqual(snapshots.statuses[index][position], live, "\(candidate.id) at \(time), step \(step)")
                }
            }
        }
    }

    /// The trimmed Savitzky-Golay windows and the one exponential pass give what the full 24 h window gives, also
    /// where a segment is longer than 24 h, across gaps, error codes and a sensor change.
    func testTrimmedWindowsEqualTheFullWindow() {
        let candidates: [SmoothingCandidate] = [.savitzkyGolay(.one), .savitzkyGolay(.two), .savitzkyGolay(.three), .exponential]
        // with gaps, and without: then the segments in the window are longer than it
        for (step, minutes, gaps) in [(1.0, 600.0, true), (5.0, 1440.0, true), (1.0, 300.0, false), (5.0, 1440.0, false)] {
            let readings = realShaped(days: 3, every: step, seed: 11, sensorChange: 1440 * 1.5 + 200, gaps: gaps)
            let sessions = [session(from: -100, until: 1440 * 1.5 + 200), session(from: 1440 * 1.5 + 200, until: nil)]
            // from 26 h on: the first segments are then longer than the 24 h window
            let replayPeriod = period(from: 1560, to: 1560 + minutes)
            let trimmed = Replay.loopStatuses(
                readings: readings, sessions: sessions, period: replayPeriod, candidates: candidates, now: at(4320)
            )
            let full = Replay.loopStatuses(
                readings: readings, sessions: sessions, period: replayPeriod, candidates: candidates, now: at(4320),
                trimWindows: false
            )
            XCTAssertNotNil(trimmed)
            XCTAssertEqual(trimmed, full, "step \(step), gaps \(gaps)")
            XCTAssertGreaterThan(trimmed?.loopTimes.count ?? 0, 50)
        }
        XCTAssertEqual(Replay.savitzkyGolayReach(SavitzkyGolayFilter(passes: 3)), .minutes(123.5))
    }

    // MARK: - Scores

    func testNoneOnACleanSineTurnsLikeTheReference() throws {
        // 40 mg/dL, 3-hour period: 2 turns per period, 16 a day
        let readings = series(every: 5, for: 4 * 1440) { 140 + 40 * sin(2 * .pi * $0 / 180) }
        let result = try XCTUnwrap(Replay.replay(
            readings: readings, sessions: [], period: period(from: 1440, to: 4 * 1440), candidates: [.none], now: at(4 * 1440)
        ))
        let none = result.results[0].scores
        XCTAssertEqual(try XCTUnwrap(none[.reversals].value), 16, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(result.referenceReversals.value), 16, accuracy: 0.6)
        XCTAssertEqual(none[.wrongWay].value ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(none.loopTimes, result.loopTimes)
        // none against itself
        XCTAssertEqual(result.results[0].changes[.deltaError]?.difference, 0)
        XCTAssertEqual(result.results[0].changes[.reversals]?.relative, 0)
    }

    func testNoneJitterOfWhiteNoiseIsSqrtSixSigma() throws {
        var random = SeededRandom(seed: 5)
        let sigma = 4.0
        let readings = series(every: 5, for: 6 * 1440) { _ in 120 + sigma * random.gaussian() }
        let result = try XCTUnwrap(Replay.replay(
            readings: readings, sessions: [], period: period(from: 1440, to: 6 * 1440),
            candidates: [.none, .savitzkyGolay(.three), .kalman(.balanced)], now: at(6 * 1440)
        ))
        // the change in a 5-minute delta of independent readings: n − 2n' + n'', each rounded to whole mg/dL
        let expected = (6 * (sigma * sigma + 1.0 / 12)).squareRoot()
        let none = result.results[0].scores
        XCTAssertEqual(try XCTUnwrap(none[.deltaJitter].value), expected, accuracy: expected * 0.06)
        XCTAssertGreaterThan(none[.deltaJitter].count, 1000)
        // noise-driven turns: far more than the flat reference's
        XCTAssertGreaterThan(try XCTUnwrap(none[.reversals].value), 3 * (result.referenceReversals.value ?? 0))
        // Kalman takes much of it away (Savitzky-Golay's newest values are end-of-window fits: only logged)
        XCTAssertLessThan(try XCTUnwrap(result.results[2].changes[.deltaJitter]?.relative), -0.2)
        print(
            "SmoothingReplay: white-noise jitter vs none, SG 3: \(result.results[1].changes[.deltaJitter]?.relative ?? .nan), Kalman: \(result.results[2].changes[.deltaJitter]?.relative ?? .nan)"
        )
    }

    /// A loop that sees the reference 10 minutes late has a lag of 10; one that sees it as it is, 0.
    func testAPureDelayIsThatLag() throws {
        // up to 2.6 mg/dL/min: fast rises and falls
        let readings = series(every: 1, for: 2 * 1440) { 150 + 100 * sin(2 * .pi * $0 / 240) }
        let segments = CGMStatsEngine.segments(CGMStatsEngine.weighed(readings), sensorStarts: [])
        let reference = SmoothingReference(readings: readings, segments: segments, halfWidth: .minutes(20))
        let loopSeconds = stride(from: 120.0, to: 2 * 1440 - 120, by: 5).map { at($0).timeIntervalSinceReferenceDate }
        let context = Replay.ScoringContext(loopSeconds: loopSeconds, reference: reference)
        func statuses(delay: Double) -> [OrefGlucoseStatus?] {
            loopSeconds.map { seconds in
                let minute = (seconds - Self.day0.timeIntervalSinceReferenceDate) / 60 - delay
                let value = 150 + 100 * sin(2 * .pi * minute / 240)
                let before = 150 + 100 * sin(2 * .pi * (minute - 5) / 240)
                return OrefGlucoseStatus(
                    glucose: value, delta: value - before, shortAvgDelta: 0, longAvgDelta: 0, date: 0, lastCal: 0
                )
            }
        }
        let late = Replay.score(loopSeconds: loopSeconds, statuses: statuses(delay: 10), context: context)
        let onTime = Replay.score(loopSeconds: loopSeconds, statuses: statuses(delay: 0), context: context)
        XCTAssertEqual(try XCTUnwrap(late[.lag].value), 10, accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(onTime[.lag].value), 0, accuracy: 0.3)
        XCTAssertGreaterThan(late[.lag].count, 500)
        // seen late, a rise reads low and a fall high
        XCTAssertLessThan(try XCTUnwrap(late[.riseError].value), -5)
        XCTAssertGreaterThan(try XCTUnwrap(late[.fallError].value), 5)
    }

    /// Savitzky-Golay's newest value undershoots the bottom of a fast V-shaped dip (as the smoothing PR found): its
    /// nadir miss is below no smoothing's, whose lowest value is the raw bottom.
    func testSavitzkyGolayUndershootsAVDip() throws {
        // falling and rising at 3 mg/dL/min, rounded off over the last few minutes to a bottom of 45
        let readings = series(every: 1, for: 1440) { minute in
            let fromTip = minute - 1000
            return min(150, 30 + 3 * (fromTip * fromTip + 25).squareRoot())
        }
        let result = try XCTUnwrap(Replay.replay(
            readings: readings, sessions: [], period: period(from: 600, to: 1440),
            candidates: [.none, .savitzkyGolay(.three)], now: at(1440)
        ))
        let none = result.results[0].scores
        let sg = result.results[1].scores
        XCTAssertEqual(none[.nadirMiss].count, 1)
        XCTAssertEqual(none[.lowCrossingDelay].count, 1)
        XCTAssertLessThan(try XCTUnwrap(sg[.nadirMiss].value), try XCTUnwrap(none[.nadirMiss].value) - 2)
    }

    // MARK: - Cancellation, progress, edges

    func testCancellationStopsEarly() {
        let readings = realShaped(days: 3, every: 1)
        let recorder = Recorder()
        let result = Replay.replay(
            readings: readings, sessions: [], period: period(from: 1440, to: 4320), now: at(4320),
            isCancelled: { recorder.call(limit: 10) }
        )
        XCTAssertNil(result)
        // each parallel chunk stops at its next check
        XCTAssertLessThan(recorder.calls, 10 + ProcessInfo.processInfo.activeProcessorCount * 4 + 5)
    }

    func testProgressIncreasesToOne() {
        let readings = realShaped(days: 2, every: 5)
        let recorder = Recorder()
        let result = Replay.replay(
            readings: readings, sessions: [], period: period(from: 1440, to: 2880), now: at(2880),
            progress: { recorder.record($0) }
        )
        XCTAssertNotNil(result)
        let values = recorder.values
        XCTAssertGreaterThan(values.count, 10)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(values.allSatisfy { (0 ... 1).contains($0) })
    }

    func testEmptyAndShortInputs() throws {
        let empty = try XCTUnwrap(Replay.replay(readings: [], sessions: [], period: period(from: 0, to: 1440), now: at(1440)))
        XCTAssertEqual(empty.loopTimes, 0)
        XCTAssertEqual(empty.results.count, SmoothingCandidate.all.count)
        for result in empty.results {
            XCTAssertNil(result.scores[.deltaError].value)
            XCTAssertEqual(result.scores[.reversals].count, 0)
        }

        // two readings: too few for any smoother (Kalman needs 3), so every candidate sees them raw
        let short = series(every: 5, for: 10) { 100 + $0 }
        let snapshots = try XCTUnwrap(Replay.loopStatuses(
            readings: short, sessions: [], period: period(from: 0, to: 60), candidates: SmoothingCandidate.all, now: at(60)
        ))
        XCTAssertEqual(snapshots.loopTimes.count, 2)
        XCTAssertEqual(snapshots.statuses[0].last??.delta, 5)
        for statuses in snapshots.statuses {
            XCTAssertEqual(statuses, snapshots.statuses[0])
        }
        XCTAssertNotNil(Replay.replay(readings: short, sessions: [], period: period(from: 0, to: 60), now: at(60)))
    }

    /// A sensor start splits the smoothing segment: the new sensor's first reading is seen raw, not pulled towards the
    /// old sensor's level.
    func testASensorStartSplitsTheSegment() throws {
        let readings = series(every: 5, for: 360) { $0 < 180 ? 100 : 125 }
        let candidates: [SmoothingCandidate] = [.none, .savitzkyGolay(.three), .kalman(.balanced), .exponential]
        let split = try XCTUnwrap(Replay.loopStatuses(
            readings: readings, sessions: [session(from: -60, until: 180), session(from: 180, until: nil)],
            period: period(from: 0, to: 360), candidates: candidates, now: at(360)
        ))
        let joined = try XCTUnwrap(Replay.loopStatuses(
            readings: readings, sessions: [], period: period(from: 0, to: 360), candidates: candidates, now: at(360)
        ))
        let first = try XCTUnwrap(split.loopTimes.firstIndex(of: at(180)))
        for index in candidates.indices.dropFirst() {
            XCTAssertEqual(split.statuses[index][first]?.glucose, 125, candidates[index].id)
            XCTAssertNotEqual(joined.statuses[index][first]?.glucose, 125, candidates[index].id)
        }
        // oref's deltas still compare across the change (glucose-get-last only filters on device)
        XCTAssertEqual(split.statuses[0][first]?.delta, 25)

        // a CGM that reports no sensor start stamps none, and never splits
        let unstamped = try XCTUnwrap(Replay.loopStatuses(
            readings: readings,
            sessions: [
                session(from: -60, until: 180, withSensorStart: false),
                session(from: 180, until: nil, withSensorStart: false)
            ],
            period: period(from: 0, to: 360), candidates: candidates, now: at(360)
        ))
        XCTAssertEqual(unstamped, joined)
    }

    /// A double dip (68 → 76 → 68): a loop already below the limit when the second dip's search starts gets a delay
    /// (earlier than the reference's crossing), not a miss; one that follows the reference crosses at once.
    func testALoopAlreadyBelowTheLimitIsNotAMissedLow() throws {
        let readings = series(every: 5, for: 1440) { minute in
            if minute < 300 {
                return 100 - 24 * minute / 300
            }
            if minute <= 780 {
                return 72 + 4 * cos(2 * .pi * (minute - 300) / 240)
            }
            return 76 + 0.08 * (minute - 780)
        }
        let segments = CGMStatsEngine.segments(CGMStatsEngine.weighed(readings), sensorStarts: [])
        let reference = SmoothingReference(readings: readings, segments: segments, halfWidth: .minutes(20))
        let loopSeconds = stride(from: 100.0, to: 1300, by: 5).map { at($0).timeIntervalSinceReferenceDate }
        let context = Replay.ScoringContext(loopSeconds: loopSeconds, reference: reference)
        XCTAssertEqual(context.dips.count, 2)
        XCTAssertTrue(context.dips.allSatisfy { $0.crossing != nil })

        func status(_ glucose: Double) -> OrefGlucoseStatus {
            OrefGlucoseStatus(glucose: glucose, delta: 0, shortAvgDelta: 0, longAvgDelta: 0, date: 0, lastCal: 0)
        }
        let below = Replay.score(loopSeconds: loopSeconds, statuses: loopSeconds.map { _ in status(65) }, context: context)
        XCTAssertEqual(below.lowsNotCrossed, 0)
        XCTAssertEqual(below[.lowCrossingDelay].count, 2)
        XCTAssertEqual(try XCTUnwrap(below[.lowCrossingDelay].value), -27.5, accuracy: 2.6)

        let following = Replay.score(
            loopSeconds: loopSeconds,
            statuses: loopSeconds.map { status(reference.value(at: $0) ?? 100) },
            context: context
        )
        XCTAssertEqual(following.lowsNotCrossed, 0)
        let delay = try XCTUnwrap(following[.lowCrossingDelay].value)
        XCTAssertTrue((0 ... 5).contains(delay), "\(delay)")
        XCTAssertEqual(try XCTUnwrap(following[.nadirMiss].value), 0, accuracy: 0.5)
    }

    /// Dips at the edges of the replayed loop times aren't scored: the reference spans more than the period.
    func testDipsOutsideTheLoopTimesAreLeftOut() {
        let readings = series(every: 5, for: 1440) { minute in
            min(150, 30 + 3 * ((minute - 1000) * (minute - 1000) + 25).squareRoot()) }
        let segments = CGMStatsEngine.segments(CGMStatsEngine.weighed(readings), sensorStarts: [])
        let reference = SmoothingReference(readings: readings, segments: segments, halfWidth: .minutes(20))
        XCTAssertEqual(Replay.dips(reference).count, 1)
        // loop times ending 10 min after the lowest point: its windows aren't covered
        let short = stride(from: 600.0, to: 1010, by: 5).map { at($0).timeIntervalSinceReferenceDate }
        XCTAssertTrue(Replay.ScoringContext(loopSeconds: short, reference: reference).dips.isEmpty)
        let covering = stride(from: 600.0, to: 1100, by: 5).map { at($0).timeIntervalSinceReferenceDate }
        XCTAssertEqual(Replay.ScoringContext(loopSeconds: covering, reference: reference).dips.count, 1)
    }

    // MARK: - Performance

    /// 30 days of 1-minute readings, every candidate: logs the time (no tight bound).
    func testThirtyDaysOfOneMinuteReadings() throws {
        let readings = realShaped(days: 31, every: 1, seed: 13)
        let started = Date()
        let result = try XCTUnwrap(Replay.replay(
            readings: readings, sessions: [], period: period(from: 1440, to: 31 * 1440), now: at(31 * 1440)
        ))
        let seconds = Date().timeIntervalSince(started)
        print(
            "SmoothingReplay: 30 days of 1-minute readings, \(result.loopTimes) loop times, \(result.results.count) candidates: \(seconds) s"
        )
        XCTAssertGreaterThan(result.loopTimes, 8000)
        XCTAssertEqual(result.sensitivity.deltaErrorOrder.count, 3)
        XCTAssertTrue(result.sensitivity.lagOrder.allSatisfy { Set($0) == Set(SmoothingCandidate.all) })
        for candidate in result.results {
            print(
                "  \(candidate.id): delta error \(candidate.scores[.deltaError].value ?? .nan), lag \(candidate.scores[.lag].value ?? .nan), reversals/day \(candidate.scores[.reversals].value ?? .nan), nadir miss \(candidate.scores[.nadirMiss].value ?? .nan) (\(candidate.scores[.nadirMiss].count)), crossing delay \(candidate.scores[.lowCrossingDelay].value ?? .nan)"
            )
        }
        print(
            "  ranking changes: delta error \(result.sensitivity.deltaErrorRankingChanges), lag \(result.sensitivity.lagRankingChanges)"
        )
    }
}
