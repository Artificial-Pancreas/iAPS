@testable import FreeAPS
import XCTest

final class GlucoseSmoothingTests: XCTestCase {
    // MARK: - fixtures

    /// Realistic magnitude: timestamps in the app are seconds since 2001, around this.
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Every algorithm with every option.
    private var smoothers: [(name: String, smoother: GlucoseSmoother)] {
        var result: [(name: String, smoother: GlucoseSmoother)] = []
        for passes in SavitzkyGolayPasses.allCases {
            result.append((name: "Savitzky-Golay \(passes.rawValue)", smoother: SavitzkyGolayFilter(passes: passes.rawValue)))
        }
        for responsiveness in KalmanResponsiveness.allCases {
            result.append((
                name: "Kalman \(responsiveness.rawValue)",
                smoother: KalmanFilter(responsiveness: responsiveness.processNoiseScale)
            ))
        }
        result.append((name: "Exponential", smoother: ExponentialFilter()))
        return result
    }

    private func reading(
        _ value: Int,
        at minutes: Double,
        type: GlucoseType = .sgv,
        session: Date? = nil
    ) -> BloodGlucose {
        let date = Self.start.addingTimeInterval(.minutes(minutes))
        return BloodGlucose(
            glucose: value,
            date: Decimal(date.timeIntervalSince1970 * 1000),
            dateString: date,
            type: type.rawValue,
            sessionStartDate: session
        )
    }

    /// - Parameter values: oldest -> newest
    private func readings(_ values: [Int], every minutes: Double) -> [BloodGlucose] {
        values.enumerated().map { reading($0.element, at: Double($0.offset) * minutes) }
    }

    /// Runs the driver the way the storage does (newest -> oldest), but takes and returns oldest -> newest.
    private func smooth(_ readings: [BloodGlucose], with smoother: GlucoseSmoother) -> [BloodGlucose] {
        Array(GlucoseSmoothing.smooth(Array(readings.reversed()), using: smoother).reversed())
    }

    /// - Parameter values: oldest -> newest
    private func samples(
        _ values: [Double],
        every minutes: Double,
        jitter: [TimeInterval]? = nil,
        session: Date? = nil
    ) -> [GlucoseSample] {
        values.enumerated().map { index, value in
            let offset = TimeInterval.minutes(Double(index) * minutes) + (jitter?[index] ?? 0)
            return GlucoseSample(date: Self.start.addingTimeInterval(offset), value: value, sessionStart: session)
        }
    }

    private func samples(at minutes: [Double], sessions: [Date?]) -> [GlucoseSample] {
        zip(minutes, sessions).map {
            GlucoseSample(date: Self.start.addingTimeInterval(.minutes($0)), value: 120, sessionStart: $1)
        }
    }

    /// SplitMix64, so the noisy fixtures are the same on every run.
    private struct SeededGenerator: RandomNumberGenerator {
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
    }

    /// Box-Muller
    private func gaussian(sd: Double, _ generator: inout SeededGenerator) -> Double {
        let u1 = Double.random(in: Double.ulpOfOne ..< 1, using: &generator)
        let u2 = Double.random(in: 0 ..< 1, using: &generator)
        return sd * (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }

    /// A smooth curve with sensor noise, oldest -> newest.
    private func noisyCurve(count: Int, every minutes: Double, seed: UInt64, sd: Double = 5) -> [Double] {
        var generator = SeededGenerator(seed: seed)
        return (0 ..< count).map { index in
            let t = Double(index) * minutes
            return 130 + 40 * sin(t / 50) + gaussian(sd: sd, &generator)
        }
    }

    // MARK: - the floor oref needs

    /// A fall onto the bottom of the range overshoots in every algorithm. No value may come out as anything
    /// oref reads as an error code (`<= 10`, `== 38`) or drops from its deltas (`<= 39`).
    func testFallOntoPlateauNeverGoesBelowFloor() {
        for cadence in [1.0, 5.0] {
            var values = [Int](repeating: 150, count: Int(30 / cadence))
            var value = 150.0
            while value > 40 {
                values.append(Int(value))
                value -= 3 * cadence
            }
            values += [Int](repeating: 40, count: max(2, Int(10 / cadence)))

            for (name, smoother) in smoothers {
                let smoothed = smooth(readings(values, every: cadence), with: smoother)
                XCTAssertEqual(smoothed.count, values.count)
                for glucose in smoothed {
                    XCTAssertGreaterThanOrEqual(glucose.glucose, 40, "\(name) at \(cadence) min")
                }
            }
        }
    }

    func testValidLowReadingsNeverBecomeErrorCodes() {
        for cadence in [1.0, 5.0] {
            var generator = SeededGenerator(seed: 7)
            let values = (0 ..< Int(180 / cadence)).map { _ in Int.random(in: 39 ... 60, using: &generator) }

            for (name, smoother) in smoothers {
                let smoothed = smooth(readings(values, every: cadence), with: smoother)
                for (raw, glucose) in zip(values, smoothed) {
                    if raw == 39 {
                        // the LOW sentinel is not glucose: it passes through, as with smoothing off
                        XCTAssertEqual(glucose.glucose, 39, "\(name) at \(cadence) min")
                    } else {
                        XCTAssertGreaterThanOrEqual(glucose.glucose, 40, "\(name) at \(cadence) min")
                    }
                }
            }
        }
    }

    // MARK: - what is not smoothed

    /// A 38 (error) or 39 (LOW) must come out unchanged, and everything else exactly as if it had never been there.
    func testErrorCodePassesThroughAndDoesNotDistortNeighbours() {
        for cadence in [1.0, 5.0] {
            let values = noisyCurve(count: Int(120 / cadence), every: cadence, seed: 11).map { Int($0.rounded()) }

            for errorIndex in [0, values.count / 2, values.count - 1] {
                for errorValue in [38, 39] {
                    var withError = readings(values, every: cadence)
                    withError[errorIndex].glucose = errorValue
                    var withoutError = readings(values, every: cadence)
                    withoutError.remove(at: errorIndex)

                    for (name, smoother) in smoothers {
                        var smoothed = smooth(withError, with: smoother)
                        XCTAssertEqual(smoothed[errorIndex].glucose, errorValue, "\(name) at \(cadence) min")
                        smoothed.remove(at: errorIndex)

                        let reference = smooth(withoutError, with: smoother)
                        XCTAssertEqual(smoothed.map(\.glucose), reference.map(\.glucose), "\(name) at \(cadence) min")
                    }
                }
            }
        }
    }

    // MARK: - a misbehaving smoother

    private struct FixedOutput: GlucoseSmoother {
        let output: [Double]
        let maximumGap: TimeInterval = .minutes(60)

        func smooth(_: [GlucoseSample]) -> [Double] {
            output
        }
    }

    /// Values no filter should produce leave their reading raw rather than trapping in `Int(...)`.
    func testUnusableValuesFallBackToRaw() {
        let values = [120, 125, 130, 135, 140]
        let smoother = FixedOutput(output: [.nan, .infinity, 5000, -50, 141.4])
        let smoothed = smooth(readings(values, every: 5), with: smoother)
        XCTAssertEqual(smoothed.map(\.glucose), [120, 125, 130, 135, 141])
    }

    /// A smoother that breaks the one-value-per-sample contract leaves the whole segment raw.
    func testWrongCountLeavesSegmentRaw() {
        let values = [120, 125, 130, 135, 140]
        for output in [[Double](), [100, 100, 100, 100], [100, 100, 100, 100, 100, 100]] {
            let smoothed = smooth(readings(values, every: 5), with: FixedOutput(output: output))
            XCTAssertEqual(smoothed.map(\.glucose), values, "\(output.count) values")
        }
    }

    func testManualAndCalibrationEntriesPassThroughRaw() {
        let values = noisyCurve(count: 30, every: 5, seed: 3).map { Int($0.rounded()) }
        let sensor = readings(values, every: 5)
        let manual = reading(250, at: 52, type: .manual)
        let calibration = reading(60, at: 101, type: .cal)

        var mixed = sensor + [manual, calibration]
        mixed.sort { $0.dateString < $1.dateString }

        for (name, smoother) in smoothers {
            let smoothed = smooth(mixed, with: smoother)
            XCTAssertEqual(smoothed.map(\.id), mixed.map(\.id), name)
            XCTAssertEqual(smoothed.first(where: { $0.id == manual.id })?.glucose, 250, name)
            XCTAssertEqual(smoothed.first(where: { $0.id == calibration.id })?.glucose, 60, name)

            let sensorOnly = smoothed.filter { $0.type == GlucoseType.sgv.rawValue }
            XCTAssertEqual(sensorOnly.map(\.glucose), smooth(sensor, with: smoother).map(\.glucose), name)
        }
    }

    // MARK: - degenerate input

    func testEmptyAndTinyInput() {
        for (name, smoother) in smoothers {
            XCTAssertTrue(GlucoseSmoothing.smooth([], using: smoother).isEmpty, name)

            for count in 1 ... 3 {
                let values = [Int](repeating: 110, count: count)
                let smoothed = smooth(readings(values, every: 5), with: smoother)
                XCTAssertEqual(smoothed.map(\.glucose), values, "\(name), \(count) readings")

                let noisy = Array([100, 130, 90].prefix(count))
                let smoothedNoisy = smooth(readings(noisy, every: 5), with: smoother)
                XCTAssertEqual(smoothedNoisy.count, count, "\(name), \(count) readings")
                XCTAssertTrue(smoothedNoisy.allSatisfy { $0.glucose >= 40 && $0.glucose <= 1000 }, name)
            }
        }
    }

    func testBelowMinimumSegmentSizeIsLeftRaw() {
        let noisy = [100.0, 130, 90, 125, 95]

        // Savitzky-Golay and Exponential need 4 readings, Kalman 3.
        let cases: [(name: String, smoother: GlucoseSmoother, minimum: Int)] = [
            (name: "Savitzky-Golay", smoother: SavitzkyGolayFilter(), minimum: 4),
            (name: "Kalman", smoother: KalmanFilter(), minimum: 3),
            (name: "Exponential", smoother: ExponentialFilter(), minimum: 4)
        ]

        for (name, smoother, minimum) in cases {
            let tooFew = Array(noisy.prefix(minimum - 1))
            XCTAssertEqual(smoother.smooth(samples(tooFew, every: 5)), tooFew, name)

            let enough = Array(noisy.prefix(minimum))
            let smoothed = smoother.smooth(samples(enough, every: 5))
            XCTAssertEqual(smoothed.count, minimum, name)
            XCTAssertTrue(smoothed.allSatisfy(\.isFinite), name)
            XCTAssertNotEqual(smoothed, enough, "\(name) should smooth \(minimum) readings")
        }
    }

    func testDuplicateAndOutOfOrderTimestampsStayFinite() {
        let values = noisyCurve(count: 40, every: 5, seed: 5)

        var duplicated = samples(values, every: 5)
        for index in stride(from: 1, to: duplicated.count, by: 3) {
            duplicated[index] = GlucoseSample(date: duplicated[index - 1].date, value: values[index], sessionStart: nil)
        }

        var shuffled = samples(values, every: 5)
        var generator = SeededGenerator(seed: 9)
        shuffled.shuffle(using: &generator)

        let allSame = samples([120, 140, 100, 130, 110], every: 0)

        for (name, smoother) in smoothers {
            for input in [duplicated, shuffled, allSame] {
                let smoothed = smoother.smooth(input)
                XCTAssertEqual(smoothed.count, input.count, name)
                XCTAssertTrue(smoothed.allSatisfy(\.isFinite), name)
            }

            // the driver keeps the caller's order, whatever order the timestamps are in
            var readings = self.readings(values.map { Int($0.rounded()) }, every: 5)
            readings.shuffle(using: &generator)
            readings[3] = reading(readings[3].glucose, at: 0)
            let smoothed = GlucoseSmoothing.smooth(readings, using: smoother)
            XCTAssertEqual(smoothed.map(\.id), readings.map(\.id), name)
            XCTAssertTrue(smoothed.allSatisfy { $0.glucose >= 40 && $0.glucose <= 1000 }, name)
        }
    }

    // MARK: - segmentation

    func testSegmentsSplitOnlyBeyondMaximumGap() {
        for (name, smoother) in smoothers {
            let gap = smoother.maximumGap
            let within = [
                GlucoseSample(date: Self.start, value: 120, sessionStart: nil),
                GlucoseSample(date: Self.start.addingTimeInterval(gap), value: 120, sessionStart: nil)
            ]
            XCTAssertEqual(GlucoseSmoothing.segments(of: within, maximumGap: gap), [0 ..< 2], name)

            let beyond = [
                GlucoseSample(date: Self.start, value: 120, sessionStart: nil),
                GlucoseSample(date: Self.start.addingTimeInterval(gap + 1), value: 120, sessionStart: nil)
            ]
            XCTAssertEqual(GlucoseSmoothing.segments(of: beyond, maximumGap: gap), [0 ..< 1, 1 ..< 2], name)
        }
    }

    func testSegmentsSplitOnSessionChange() {
        let sensorA = Self.start.addingTimeInterval(-TimeInterval.days(5))
        let sensorB = Self.start.addingTimeInterval(.minutes(9))
        let gap = TimeInterval.minutes(60)

        // a new sensor
        XCTAssertEqual(
            GlucoseSmoothing.segments(of: samples(at: [0, 5, 10], sessions: [sensorA, sensorA, sensorB]), maximumGap: gap),
            [0 ..< 2, 2 ..< 3]
        )
        // readings without a session do not bridge two sensors
        XCTAssertEqual(
            GlucoseSmoothing.segments(of: samples(at: [0, 5, 10, 15], sessions: [sensorA, nil, nil, sensorB]), maximumGap: gap),
            [0 ..< 3, 3 ..< 4]
        )
        // ...but do not split one
        XCTAssertEqual(
            GlucoseSmoothing.segments(of: samples(at: [0, 5, 10], sessions: [sensorA, nil, sensorA]), maximumGap: gap),
            [0 ..< 3]
        )
        XCTAssertEqual(
            GlucoseSmoothing.segments(of: samples(at: [0, 5, 10], sessions: [nil, nil, nil]), maximumGap: gap),
            [0 ..< 3]
        )
        // a session stamp that jitters within the tolerance is one session
        XCTAssertEqual(
            GlucoseSmoothing.segments(
                of: samples(at: [0, 5, 10], sessions: [sensorA, sensorA.addingTimeInterval(.minutes(20)), sensorA]),
                maximumGap: gap
            ),
            [0 ..< 3]
        )
    }

    // MARK: - response

    func testConstantInputStaysConstant() {
        for cadence in [1.0, 5.0] {
            let values = [Double](repeating: 120, count: Int(120 / cadence))
            for (name, smoother) in smoothers {
                let smoothed = smoother.smooth(samples(values, every: cadence))
                for value in smoothed {
                    XCTAssertEqual(value, 120, accuracy: 1E-6, "\(name) at \(cadence) min")
                }
            }
        }
    }

    func testLinearRamp() {
        let slope = 2.0 // mg/dL/min

        func ramp(every minutes: Double) -> [Double] {
            (0 ... Int(120 / minutes)).map { 100 + slope * Double($0) * minutes }
        }

        // Savitzky-Golay fits a quadratic, so a straight line comes back exactly, whatever the spacing.
        var generator = SeededGenerator(seed: 13)
        for cadence in [1.0, 5.0] {
            let values = ramp(every: cadence)
            let jitter = values.map { _ in Double.random(in: -20 ... 20, using: &generator) }
            let jittered = samples(values, every: cadence, jitter: jitter)
            let exact = jittered.map { 100 + slope * $0.date.timeIntervalSince(Self.start) / 60 }
            for passes in SavitzkyGolayPasses.allCases {
                let smoothed = SavitzkyGolayFilter(passes: passes.rawValue).smooth(
                    jittered.enumerated().map { GlucoseSample(date: $1.date, value: exact[$0], sessionStart: nil) }
                )
                for (value, expected) in zip(smoothed, exact) {
                    XCTAssertEqual(value, expected, accuracy: 1E-6, "Savitzky-Golay \(passes.rawValue) at \(cadence) min")
                }
            }
        }

        // The other two lag the newest reading, by a bounded amount, and by about as much on either cadence.
        let bounds: [(name: String, smoother: GlucoseSmoother, maximumLag: Double, cadenceDifference: Double)] = [
            (name: "Kalman", smoother: KalmanFilter(), maximumLag: 3, cadenceDifference: 1.5),
            (name: "Exponential", smoother: ExponentialFilter(), maximumLag: 8, cadenceDifference: 2)
        ]
        for (name, smoother, maximumLag, cadenceDifference) in bounds {
            var lags: [Double] = []
            for cadence in [1.0, 5.0] {
                let values = ramp(every: cadence)
                let smoothed = smoother.smooth(samples(values, every: cadence))
                let lag = values.last! - smoothed.last!
                XCTAssertGreaterThanOrEqual(lag, 0, "\(name) at \(cadence) min")
                XCTAssertLessThan(lag, maximumLag, "\(name) at \(cadence) min")
                lags.append(lag)
            }
            XCTAssertLessThan(abs(lags[0] - lags[1]), cadenceDifference, "\(name): 1-minute vs 5-minute lag")
        }
    }

    // MARK: - Savitzky-Golay

    /// Away from the ends, one pass at a 5-minute cadence is the classic 7-point quadratic filter the old
    /// implementation used.
    func testSavitzkyGolayInteriorMatchesLegacyCoefficients() {
        let coefficients = [-2.0, 3, 6, 7, 6, 3, -2]
        let values = noisyCurve(count: 30, every: 5, seed: 17, sd: 10)
        let smoothed = SavitzkyGolayFilter(passes: 1).smooth(samples(values, every: 5))

        for index in 3 ..< (values.count - 3) {
            let expected = coefficients.enumerated()
                .map { $1 * values[index - 3 + $0] }
                .reduce(0, +) / 21
            XCTAssertEqual(smoothed[index], expected, accuracy: 1E-9, "index \(index)")
        }
    }

    /// Timestamps a few seconds off the 5-minute grid must not change which readings each window holds.
    /// With the window edges on the readings, one such jitter moved a value by several mg/dL.
    func testSavitzkyGolayIgnoresTimestampJitter() {
        let values = noisyCurve(count: 40, every: 5, seed: 19)
        var generator = SeededGenerator(seed: 23)
        let jitter = values.map { _ in Double.random(in: -10 ... 10, using: &generator) }

        for passes in SavitzkyGolayPasses.allCases {
            let filter = SavitzkyGolayFilter(passes: passes.rawValue)
            let regular = filter.smooth(samples(values, every: 5))
            let jittered = filter.smooth(samples(values, every: 5, jitter: jitter))
            for (a, b) in zip(regular, jittered) {
                XCTAssertEqual(a, b, accuracy: 1, "\(passes.rawValue) passes")
            }
        }
    }

    // MARK: - Exponential

    /// `ExponentialSmoothingPlugin.smooth` from AndroidAPS, transcribed. `data` is newest -> oldest, as there,
    /// and so is the result: the unrounded smoothed values of the window it smooths. The fixture has no
    /// gaps and no error codes, so the window checks for those are left out.
    private func androidAPSExponential(_ data: [Double]) -> [Double] {
        let sizeRecords = data.count
        var windowSize = data.count
        if sizeRecords <= windowSize {
            windowSize = max(sizeRecords - 1, 0)
        }
        let o1Weight = 0.4
        let o1A = 0.5
        let o2A = 0.4
        let o2B = 1.0

        var o1: [Double] = [data[windowSize - 1]]
        for i in 0 ..< windowSize {
            o1.insert(o1[0] + o1A * (data[windowSize - 1 - i] - o1[0]), at: 0)
        }

        var o2: [Double] = [data[windowSize - 1]]
        var o2D: [Double] = [data[windowSize - 2] - data[windowSize - 1]]
        for i in 0 ..< (windowSize - 1) {
            o2.insert(o2A * data[windowSize - 2 - i] + (1 - o2A) * (o2[0] + o2D[0]), at: 0)
            o2D.insert(o2B * (o2[0] - o2[1]) + (1 - o2B) * o2D[0], at: 0)
        }

        return o2.indices.map { o1Weight * o1[$0] + (1 - o1Weight) * o2[$0] }
    }

    func testExponentialMatchesAndroidAPSAtFiveMinutes() {
        // AndroidAPS keeps the oldest reading back as a buffer, so it smooths all but that one.
        let values = noisyCurve(count: 30, every: 5, seed: 29).map { $0.rounded() }
        let expected = androidAPSExponential(Array(values.reversed()))
        XCTAssertEqual(expected.count, values.count - 1)

        let window = Array(values.dropFirst())
        let smoothed = ExponentialFilter().smooth(samples(window, every: 5))

        for (value, reference) in zip(smoothed, expected.reversed()) {
            XCTAssertEqual(value, reference, accuracy: 1E-9)
        }
    }

    // MARK: - Kalman

    /// Right after a segment starts a filter has little to go on. On noisy 1-minute data the newest value
    /// must still be no noisier than the reading itself. Seeding the trend from the first interval made
    /// Kalman's up to a quarter noisier than raw, and Exponential's (scaled to 5 minutes) over three times.
    func testSegmentStartIsNotNoisierThanRaw() {
        var generator = SeededGenerator(seed: 42)
        let filters: [(name: String, smoother: GlucoseSmoother)] = [
            (name: "Kalman", smoother: KalmanFilter()),
            (name: "Exponential", smoother: ExponentialFilter())
        ]

        for (name, filter) in filters {
            for count in [4, 5, 6, 8, 10, 12, 15, 20] {
                var smoothedErrors: [Double] = []
                var rawErrors: [Double] = []
                for _ in 0 ..< 2000 {
                    let values = (0 ..< count).map { _ in 120 + gaussian(sd: 4, &generator) }
                    let smoothed = filter.smooth(samples(values, every: 1))
                    smoothedErrors.append(smoothed.last! - 120)
                    rawErrors.append(values.last! - 120)
                }
                XCTAssertLessThan(
                    standardDeviation(smoothedErrors),
                    0.9 * standardDeviation(rawErrors),
                    "\(name), \(count) readings"
                )
            }
        }
    }

    func testKalmanDoesNotStartFromAnErrorCode() {
        let values = noisyCurve(count: 20, every: 5, seed: 31)
        let tail = KalmanFilter().smooth(samples(Array(values.dropFirst(2)), every: 5))

        var withLeadingErrors = samples(values, every: 5)
        for index in 0 ..< 2 {
            withLeadingErrors[index] = GlucoseSample(date: withLeadingErrors[index].date, value: 38, sessionStart: nil)
        }
        let smoothed = KalmanFilter().smooth(withLeadingErrors)

        XCTAssertEqual(Array(smoothed.prefix(2)), [38, 38])
        XCTAssertEqual(Array(smoothed.dropFirst(2)), tail)
    }

    // MARK: - settings

    func testMissingSmoothingSettingsDefaultToOff() throws {
        let neither = try FreeAPSSettings.decodeFrom(json: "{}")
        XCTAssertEqual(neither.glucoseSmoothing, GlucoseSmoothingSettings())
        XCTAssertEqual(neither.glucoseSmoothing.algorithm, .off)

        let notAnObject = try FreeAPSSettings.decodeFrom(json: #"{"glucoseSmoothing": "kalman"}"#)
        XCTAssertEqual(notAnObject.glucoseSmoothing, GlucoseSmoothingSettings())
    }

    /// Decoding, saving and decoding again changes nothing, and the saved form carries no old `smoothGlucose` key.
    func testSettingsRoundTrip() throws {
        let original = try FreeAPSSettings.decodeFrom(
            json: #"{"smoothGlucose": true, "glucoseSmoothing": {"algorithm": "kalman", "kalman": {"responsiveness": "calm"}, "savitzkyGolay": {"passes": 2}}}"#
        )
        XCTAssertEqual(original.glucoseSmoothing.algorithm, .kalman)
        XCTAssertEqual(original.glucoseSmoothing.kalman.responsiveness, .calm)
        XCTAssertEqual(original.glucoseSmoothing.savitzkyGolay.passes, .two)

        let saved = original.rawJSON()
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(saved.utf8)) as? [String: Any]
        )
        XCTAssertNotNil(object["glucoseSmoothing"])
        XCTAssertNil(object["smoothGlucose"])

        let reloaded = try FreeAPSSettings.decodeFrom(json: saved)
        XCTAssertEqual(reloaded.glucoseSmoothing, original.glucoseSmoothing)
        XCTAssertEqual(try FreeAPSSettings.decodeFrom(json: reloaded.rawJSON()).glucoseSmoothing, original.glucoseSmoothing)
    }

    func testUnknownSettingValuesDefaultOnlyThatField() throws {
        func decode(_ json: String) throws -> GlucoseSmoothingSettings {
            try GlucoseSmoothingSettings.decodeFrom(json: json)
        }

        let unknownAlgorithm = try decode(
            #"{"algorithm": "wavelet", "savitzkyGolay": {"passes": 2}, "kalman": {"responsiveness": "calm"}}"#
        )
        XCTAssertEqual(unknownAlgorithm.algorithm, .off)
        XCTAssertEqual(unknownAlgorithm.savitzkyGolay.passes, .two)
        XCTAssertEqual(unknownAlgorithm.kalman.responsiveness, .calm)

        let passesOutOfRange = try decode(#"{"algorithm": "savitzkyGolay", "savitzkyGolay": {"passes": 4}}"#)
        XCTAssertEqual(passesOutOfRange.algorithm, .savitzkyGolay)
        XCTAssertEqual(passesOutOfRange.savitzkyGolay.passes, .three)

        let unknownResponsiveness = try decode(#"{"algorithm": "kalman", "kalman": {"responsiveness": "frantic"}}"#)
        XCTAssertEqual(unknownResponsiveness.algorithm, .kalman)
        XCTAssertEqual(unknownResponsiveness.kalman.responsiveness, .balanced)

        let missingNested = try decode(#"{"algorithm": "kalman", "kalman": {}, "savitzkyGolay": {}}"#)
        XCTAssertEqual(missingNested.algorithm, .kalman)
        XCTAssertEqual(missingNested.kalman, KalmanSettings())
        XCTAssertEqual(missingNested.savitzkyGolay, SavitzkyGolaySettings())

        // and inside the whole settings file
        let settings = try FreeAPSSettings.decodeFrom(
            json: #"{"glucoseSmoothing": {"algorithm": "exponential", "savitzkyGolay": {"passes": 9}}}"#
        )
        XCTAssertEqual(settings.glucoseSmoothing.algorithm, .exponential)
        XCTAssertEqual(settings.glucoseSmoothing.savitzkyGolay.passes, .three)
    }
}
