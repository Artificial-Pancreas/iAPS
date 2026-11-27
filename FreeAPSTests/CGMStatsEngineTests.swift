@testable import FreeAPS
import XCTest

private typealias Engine = CGMStatsEngine

/// The CGM statistics from synthetic readings (seeded noise, so every run is the same): segments, coverage and gaps,
/// the reference fit, noise, jitter, reversals and rate of change.
final class CGMStatsEngineTests: XCTestCase {
    // MARK: - Fixtures

    /// 2026-10-20 00:00 Europe/Berlin (CEST)
    private static let day0 = StatsFixtures.day0

    private func at(_ minutes: Double, from start: Date = CGMStatsEngineTests.day0) -> Date {
        start.addingTimeInterval(.minutes(minutes))
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

    /// Readings every `step` for `duration` (the end excluded unless `throughEnd`), the value a function of the minutes
    /// from the start, rounded to whole mg/dL.
    private func series(
        from start: Date = CGMStatsEngineTests.day0,
        every step: TimeInterval,
        for duration: TimeInterval,
        throughEnd: Bool = false,
        _ value: (Double) -> Double
    ) -> [GlucosePoint] {
        let count = Int((duration / step).rounded(.down)) + (throughEnd ? 1 : 0)
        return (0 ..< count).map { index in
            let minutes = Double(index) * step / 60
            return GlucosePoint(time: start.addingTimeInterval(.minutes(minutes)), mgdl: Int16(value(minutes).rounded()))
        }
    }

    /// A sine around `level` with the amplitude and period (minutes), plus normal noise of the SD.
    private func noisySine(
        every step: TimeInterval,
        for duration: TimeInterval,
        level: Double = 140,
        amplitude: Double,
        period: Double,
        noise: Double,
        seed: UInt64 = 1,
        throughEnd: Bool = false
    ) -> [GlucosePoint] {
        var random = SeededRandom(seed: seed)
        return series(every: step, for: duration, throughEnd: throughEnd) { minutes in
            level + amplitude * sin(2 * .pi * minutes / period) + noise * random.gaussian()
        }
    }

    private func stats(
        _ readings: [GlucosePoint],
        sensorStarts: [Date] = [],
        period: DateInterval = DateInterval(start: .distantPast, end: .distantFuture),
        now: Date = .distantFuture
    ) -> CGMStats {
        Engine.stats(
            readings: readings,
            sensorStarts: sensorStarts,
            period: period,
            now: now
        )
    }

    private func dropping(_ readings: [GlucosePoint], from: Date, to: Date) -> [GlucosePoint] {
        readings.filter { $0.time < from || $0.time > to }
    }

    /// The same readings, every one later by the seconds.
    private func shifted(_ readings: [GlucosePoint], by seconds: TimeInterval) -> [GlucosePoint] {
        readings.map { GlucosePoint(time: $0.time.addingTimeInterval(seconds), mgdl: $0.mgdl) }
    }

    // MARK: - Flat line

    func testFlatLineScoresNoNoiseNoReversalsNoJitter() {
        let result = stats(series(every: .minutes(1), for: .hours(24)) { _ in 120 })

        XCTAssertEqual(result.readings, 1440)
        XCTAssertEqual(result.cadence, .minutes(1))
        XCTAssertEqual(result.noise?.mgdl ?? -1, 0, accuracy: 1E-9)
        XCTAssertEqual(result.noise?.fraction ?? -1, 0, accuracy: 1E-9)
        XCTAssertEqual(result.deltaJitter ?? -1, 0, accuracy: 1E-9)
        XCTAssertEqual(result.reversals.raw, 0)
        XCTAssertEqual(result.reversals.reference, 0)
        XCTAssertEqual(result.coverage.fraction, 1)
        XCTAssertTrue(result.gaps.isEmpty)
        XCTAssertEqual(result.rateOfChange?.share(.slow) ?? 0, 1, accuracy: 1E-9)
        XCTAssertNil(result.rateOfChange?.fastestRise)
        XCTAssertNil(result.rateOfChange?.fastestFall)
    }

    // MARK: - Noise and jitter

    func testNoiseOfKnownSDIsRecoveredAtOneMinute() {
        let result = stats(noisySine(every: .minutes(1), for: .days(3), amplitude: 30, period: 180, noise: 5))

        XCTAssertEqual(result.cadence, .minutes(1))
        XCTAssertEqual(result.noise?.mgdl ?? 0, 5, accuracy: 0.4)
        // 5 mg/dL around 110...170
        XCTAssertEqual(result.noise?.fraction ?? 0, 5.0 / 140, accuracy: 0.006)
        // the change in the 5-min delta is a second difference: √6 × the noise
        XCTAssertEqual(result.deltaJitter ?? 0, 5 * 6.0.squareRoot(), accuracy: 1.2)
    }

    func testNoiseOfKnownSDIsRecoveredAtFiveMinutes() {
        // two weeks: the robust SD of 4000 residuals is within about 0.15 mg/dL of the noise's
        let result = stats(noisySine(every: .minutes(5), for: .days(14), amplitude: 30, period: 180, noise: 5, seed: 2))

        XCTAssertEqual(result.cadence, .minutes(5))
        XCTAssertEqual(result.noise?.mgdl ?? 0, 5, accuracy: 0.4)
        XCTAssertEqual(result.deltaJitter ?? 0, 5 * 6.0.squareRoot(), accuracy: 1.5)
    }

    /// A sensor's noise alone is the whole statistics' noise without sensor starts.
    func testNoiseAloneIsTheStatisticsNoise() {
        let readings = noisySine(every: .minutes(1), for: .days(1), amplitude: 30, period: 180, noise: 3, seed: 4)
        let period = DateInterval(start: Self.day0, duration: .hours(20))
        XCTAssertEqual(
            Engine.noise(readings: readings, period: period, now: at(18 * 60)),
            stats(readings, period: period, now: at(18 * 60)).noise
        )
        XCTAssertNil(Engine.noise(readings: [], period: period, now: at(18 * 60)))
    }

    /// A sensor's noise from its CGM's segments is its own: the segments it shares taken from them (after a sensor
    /// start), the others (a part cut inside one) fitted on their own.
    func testNoiseFromTheCGMsSegmentsIsTheSensorsOwn() {
        let readings = noisySine(every: .minutes(1), for: .days(2), amplitude: 30, period: 180, noise: 3, seed: 6)
        let period = DateInterval(start: Self.day0, duration: .days(2))
        let start = at(20 * 60)
        let kept = Engine.analysed(readings: readings, sensorStarts: [start], period: period, now: .distantFuture)
        XCTAssertEqual(kept.stats, stats(readings, sensorStarts: [start], period: period))
        XCTAssertEqual(kept.residuals.ranges.count, 2)
        for part in [
            readings.filter { $0.time >= start },
            readings.filter { $0.time < start },
            readings.filter { $0.time >= at(30 * 60) },
            dropping(readings, from: at(10 * 60), to: at(11 * 60))
        ] {
            XCTAssertEqual(
                Engine.noise(readings: part, period: period, now: .distantFuture, reusing: kept.residuals),
                Engine.noise(readings: part, period: period, now: .distantFuture)
            )
        }
    }

    func testWhereTheTimestampsFallDoesNotChangeJitterOrReversals() {
        // 5-min readings half a step off the clock's 5 minutes, 1-min ones 37 s off it
        let cases: [(step: TimeInterval, shift: TimeInterval, seed: UInt64)] = [(.minutes(5), 150, 2), (.minutes(1), 37, 1)]
        for (step, shift, seed) in cases {
            let readings = noisySine(every: step, for: .days(3), amplitude: 30, period: 180, noise: 5, seed: seed)

            let onTheClock = stats(readings)
            let off = stats(shifted(readings, by: shift))

            XCTAssertEqual(off.deltaJitter ?? 0, onTheClock.deltaJitter ?? -1, accuracy: 1E-9, "\(step)")
            XCTAssertEqual(off.reversals.raw, onTheClock.reversals.raw, "\(step)")
            XCTAssertEqual(off.reversals.reference, onTheClock.reversals.reference, "\(step)")
            XCTAssertEqual(off.noise?.mgdl ?? 0, onTheClock.noise?.mgdl ?? -1, accuracy: 1E-9, "\(step)")
            // the readings themselves, not averages of two: √6 × the noise
            XCTAssertEqual(off.deltaJitter ?? 0, 5 * 6.0.squareRoot(), accuracy: 1.5, "\(step)")
        }
    }

    func testOneAndFiveMinuteSensorsWithTheSameNoiseTurnAlike() {
        // a week of the same sine and noise SD; the 5-min sensor's readings half a step off the clock
        let oneMinute = noisySine(every: .minutes(1), for: .days(7), amplitude: 40, period: 120, noise: 4, seed: 20)
        let fiveMinute = shifted(
            noisySine(every: .minutes(5), for: .days(7), amplitude: 40, period: 120, noise: 4, seed: 21),
            by: 150
        )

        let one = stats(oneMinute).reversals.rawPerDay ?? 0
        let five = stats(fiveMinute).reversals.rawPerDay ?? 0

        // about 50 a day: 24 real turns and about as many from the noise. The two are of different noise, so they differ
        // by chance (~380 turns a week each: within 7 % over a dozen seed pairs); 15 % allows that, and is far inside
        // the halving that averaging neighbours (the 5-min readings off the clock) used to cause.
        XCTAssertGreaterThan(one, 40)
        XCTAssertEqual(five / one, 1, accuracy: 0.15)
    }

    func testFiveMinuteSeriesTakesTheNearestReadingAndInterpolatesOnlyWithoutOne() {
        // seconds off the clock; 7 min 21 s between the third and fourth reading
        let base = Self.day0.timeIntervalSinceReferenceDate + 7
        let times = [0.0, 230, 440, 881, 1190, 1500].map { base + $0 }
        let values: [Double?] = [100, 110, 120, 140, 150, 160]
        let segment = [0 ..< times.count]

        let raw = Engine.fiveMinuteRuns(times: times, values: values, segments: segment, nearest: true)
        let reference = Engine.fiveMinuteRuns(times: times, values: values, segments: segment, nearest: false)

        // grid at +0, 5, ..., 25 min from the first reading; at +10 min no reading is within 2.5 min
        XCTAssertEqual(raw.count, 1)
        let expectedRaw: [Double] = [100, 110, 120 + 20 * 160 / 441, 140, 150, 160]
        for (value, expected) in zip(raw.first ?? [], expectedRaw) {
            XCTAssertEqual(value, expected, accuracy: 1E-9)
        }
        XCTAssertEqual(raw.first?.count, 6)
        let expectedReference: [Double] = [
            100,
            110 + 10 * 70 / 210,
            120 + 20 * 160 / 441,
            140 + 10 * 19 / 309,
            150 + 10 * 10 / 310,
            160
        ]
        for (value, expected) in zip(reference.first ?? [], expectedReference) {
            XCTAssertEqual(value, expected, accuracy: 1E-9)
        }
        XCTAssertEqual(reference.first?.count, 6)
    }

    func testNoiseBySensorDayStartsAtTheFirstSensorStart() {
        var random = SeededRandom(seed: 3)
        let start = at(6 * 60)
        // 6 h before the sensor start, then day 1 with SD 3, day 2 with SD 6
        let readings = series(every: .minutes(1), for: .hours(54)) { minutes in
            let sd: Double = minutes < 30 * 60 ? 3 : 6
            return 130 + 20 * sin(2 * .pi * minutes / 240) + sd * random.gaussian()
        }

        let result = stats(readings, sensorStarts: [start])

        XCTAssertEqual(Set(result.noiseBySensorDay.keys), [1, 2])
        XCTAssertEqual(result.noiseBySensorDay[1]?.mgdl ?? 0, 3, accuracy: 0.3)
        XCTAssertEqual(result.noiseBySensorDay[2]?.mgdl ?? 0, 6, accuracy: 0.6)
    }

    func testResidualAtASensorStartIsTheNewSensorsFirstDay() {
        var random = SeededRandom(seed: 6)
        // 1-min readings 00:00...03:00, the sensor started at the 01:00 reading
        let readings = series(every: .minutes(1), for: .hours(3), throughEnd: true) { minutes in
            (minutes < 60 ? 100 : 150) + 3 * random.gaussian()
        }

        let result = stats(readings, sensorStarts: [at(60)])

        XCTAssertEqual(Set(result.noiseBySensorDay.keys), [1])
        // 01:00...03:00: the start reading's leave-one-out fit is of the new sensor's readings after it
        XCTAssertEqual(result.noiseBySensorDay[1]?.count, 121)
    }

    // MARK: - Reference fit

    func testReferenceFitIsNotBentByASpike() {
        var readings = series(every: .minutes(5), for: .hours(2)) { _ in 120 }
        readings[12] = GlucosePoint(time: readings[12].time, mgdl: 180)
        let w = GlucoseStatsEngine.weigh(readings)

        let fits = Engine.referenceFit(readings, segments: Engine.segments(w, sensorStarts: []))

        XCTAssertEqual(fits.count, readings.count)
        for index in 9 ... 15 {
            XCTAssertEqual(fits[index]?.value ?? 0, 120, accuracy: 0.01, "reading \(index)")
            XCTAssertEqual(fits[index]?.slope ?? 1, 0, accuracy: 0.01, "reading \(index)")
        }
    }

    func testReferenceFitFollowsAQuadraticAndSkipsTooFewReadings() {
        let readings = series(every: .minutes(5), for: .hours(2)) { minutes in 100 + 0.01 * minutes * minutes }
        let lone = GlucosePoint(time: at(600), mgdl: 100)
        let all = readings + [lone]
        let w = GlucoseStatsEngine.weigh(all)
        let segments = Engine.segments(w, sensorStarts: [])

        let fits = Engine.referenceFit(all, segments: segments)

        XCTAssertEqual(segments.count, 2)
        // the readings are rounded: the fit is within half a mg/dL
        XCTAssertEqual(fits[12]?.value ?? 0, 100 + 0.01 * 3600, accuracy: 0.5)
        XCTAssertEqual(fits[12]?.slope ?? 0, 0.02 * 60, accuracy: 0.05)
        XCTAssertNil(fits.last ?? nil, "a reading alone in its segment has no fit")
        XCTAssertEqual(fits[0]?.isCentred, false)
        XCTAssertEqual(fits[12]?.isCentred, true)
        XCTAssertNil(fits[12]?.variance ?? nil, "only the leave-one-out fits carry the variance")
    }

    // MARK: - Reversals

    func testReversalsOnACleanSineAreItsTurns() {
        // 12 h of a 2-hour sine: extremes at 0:30, 1:30, ..., 11:30
        let readings = noisySine(every: .minutes(1), for: .hours(12), amplitude: 40, period: 120, noise: 0, throughEnd: true)

        let result = stats(readings)

        XCTAssertEqual(result.reversals.raw, 12)
        XCTAssertEqual(result.reversals.reference, 12)
        XCTAssertEqual(result.reversals.rawPerDay ?? 0, 24, accuracy: 1E-9)
        // the reference leaves out the first and last reading (one-sided fits): 00:05...11:55
        XCTAssertEqual(result.reversals.referenceSeconds, .minutes(710))
        XCTAssertEqual(result.reversals.referencePerDay ?? 0, 12 * 1440 / 710, accuracy: 1E-9)
    }

    func testNoiseRaisesTheRawReversalsButNotTheReference() {
        let readings = noisySine(
            every: .minutes(1),
            for: .hours(12),
            amplitude: 40,
            period: 120,
            noise: 4,
            seed: 4,
            throughEnd: true
        )

        let result = stats(readings)

        XCTAssertEqual(Double(result.reversals.reference), 12, accuracy: 1)
        XCTAssertGreaterThan(result.reversals.raw, result.reversals.reference + 12)
    }

    func testTurnsNeedTheThreshold() {
        XCTAssertEqual(Engine.turns([100, 102, 100, 102, 100]), 0)
        XCTAssertEqual(Engine.turns([100, 103, 100, 103, 100]), 3)
        XCTAssertEqual(Engine.turns([100, 110, 108, 120]), 0)
        XCTAssertEqual(Engine.turns([]), 0)
    }

    // MARK: - Gaps and coverage

    func testGapIsCounted() {
        // 5-min readings for the day, 02:05...02:25 missing
        let readings = dropping(
            series(every: .minutes(5), for: .hours(24)) { _ in 120 },
            from: at(125),
            to: at(145)
        )

        let result = stats(readings)

        XCTAssertEqual(result.gaps.count, 1)
        XCTAssertEqual(result.gaps.first?.start, at(120))
        XCTAssertEqual(result.gaps.first?.end, at(150))
        XCTAssertEqual(result.gaps.first?.missing, 5)
        XCTAssertEqual(result.longestGap, .minutes(25))
        XCTAssertEqual(result.gaps.first?.elapsed, .minutes(30))
        XCTAssertEqual(result.coverage, CGMCoverage(received: 283, missing: 5, gaps: 1, gapSeconds: .minutes(25)))
        XCTAssertEqual(result.span, DateInterval(start: at(0), end: at(24 * 60 - 5)))
    }

    func testOneMinuteGapMissesItsMinutes() {
        let readings = dropping(series(every: .minutes(1), for: .hours(2)) { _ in 120 }, from: at(31), to: at(39))

        let result = stats(readings)

        XCTAssertEqual(result.cadence, .minutes(1))
        XCTAssertEqual(result.gaps.map(\.missing), [9])
        XCTAssertEqual(result.coverage.expected, 120)
    }

    func testGapRightAfterAnOutageOrTheFirstReadingIsWeighedAtTheSensorsCadence() {
        // 1-min readings over 4 h: 00:01 and 00:02 missing, nothing 01:01...02:59, then 03:01...03:03 missing
        let minutes = Set([0] + Array(3 ... 60) + [180] + Array(184 ... 240))
        let readings = series(every: .minutes(1), for: .hours(4), throughEnd: true) { _ in 120 }
            .enumerated().filter { minutes.contains($0.offset) }.map(\.element)

        let result = stats(readings)

        XCTAssertEqual(Engine.dropouts(Engine.weighed(readings)).map(\.missing), [2, 119, 3])
        XCTAssertEqual(Engine.dropouts(Engine.weighed(readings)).map(\.cadence), [.minutes(1), .minutes(1), .minutes(1)])
        // the 3- and 4-minute distances miss readings but aren't gaps
        XCTAssertEqual(result.gaps.map(\.missing), [119])
        XCTAssertEqual(result.coverage.missing, 124)
        XCTAssertEqual(result.coverage.expected, 241)
    }

    func testOneMinuteDropoutsAreGapsOnlyOverFiveMinutes() {
        // 1-min readings over 2 h: 2, 4 and 6 minutes from the reading before to the next at 00:20, 00:40 and 01:00
        let readings = series(every: .minutes(1), for: .hours(2)) { _ in 120 }
            .filter { reading in
                ![21.0, 41, 42, 43, 61, 62, 63, 64, 65].contains { reading.time == at($0) }
            }

        let result = stats(readings)

        XCTAssertEqual(result.cadence, .minutes(1))
        XCTAssertEqual(result.gaps, [CGMGap(start: at(60), end: at(66), cadence: .minutes(1), missing: 5)])
        XCTAssertEqual(result.longestGap, .minutes(5))
        // every skipped reading still counts against the coverage
        XCTAssertEqual(result.coverage, CGMCoverage(received: 111, missing: 9, gaps: 1, gapSeconds: .minutes(5)))
        // the segments still split at every dropout (1.5 cadences)
        XCTAssertEqual(Engine.segments(Engine.weighed(readings), sensorStarts: []).count, 4)
    }

    func testFiveMinuteDropoutIsAGapAsBefore() {
        // 5-min readings over 2 h: one missed at 00:30 (10 min between two)
        let readings = dropping(series(every: .minutes(5), for: .hours(2)) { _ in 120 }, from: at(30), to: at(30))

        let result = stats(readings)

        XCTAssertEqual(result.gaps, [CGMGap(start: at(25), end: at(35), cadence: .minutes(5), missing: 1)])
        XCTAssertEqual(result.coverage, CGMCoverage(received: 23, missing: 1, gaps: 1, gapSeconds: .minutes(5)))
    }

    func testGapAcrossMidnight() {
        // 5-min readings from 12:00 for a day, 23:45...00:15 missing
        let readings = dropping(
            series(from: at(12 * 60), every: .minutes(5), for: .hours(24)) { _ in 120 },
            from: at(23 * 60 + 45),
            to: at(24 * 60 + 15)
        )

        let result = stats(readings)

        XCTAssertEqual(result.gaps.map(\.missing), [7])
        XCTAssertEqual(result.gaps.first?.elapsed, .minutes(40))
        XCTAssertEqual(result.coverage, CGMCoverage(received: 281, missing: 7, gaps: 1, gapSeconds: .minutes(35)))
    }

    func testFiveMinuteWeekThenOneMinuteWeek() {
        let start = StatsFixtures.week
        let day: TimeInterval = .days(1)
        // a gap in each: 10:05...10:25 on day 2 (5 readings), 10:31...10:39 on day 9 (9 readings)
        var readings = series(from: start, every: .minutes(5), for: .days(7)) { _ in 120 }
            + series(from: start.addingTimeInterval(7 * day), every: .minutes(1), for: .days(7)) { _ in 120 }
        readings = dropping(readings, from: at(10 * 60 + 5, from: start + 2 * day), to: at(10 * 60 + 25, from: start + 2 * day))
        readings = dropping(readings, from: at(10 * 60 + 31, from: start + 9 * day), to: at(10 * 60 + 39, from: start + 9 * day))

        let result = stats(readings)

        XCTAssertEqual(result.gaps, [
            CGMGap(start: at(600, from: start + 2 * day), end: at(630, from: start + 2 * day), cadence: .minutes(5), missing: 5),
            CGMGap(start: at(630, from: start + 9 * day), end: at(640, from: start + 9 * day), cadence: .minutes(1), missing: 9)
        ])
        // 12 an hour, then 60
        XCTAssertEqual(result.coverage.expected, 7 * 288 + 7 * 1440)
        XCTAssertEqual(result.coverage.missing, 14)
        // one cadence for the set: the median distance, the 1-min week's (it has 5 times the readings)
        XCTAssertEqual(result.cadence, .minutes(1))
    }

    // MARK: - Sensor changes

    func testSensorStartSplitsTheSegments() {
        let start = at(6 * 60)
        let readings = series(every: .minutes(5), for: .hours(12)) { minutes in minutes < 6 * 60 ? 100 : 125 }
        let w = GlucoseStatsEngine.weigh(readings)

        let result = stats(readings, sensorStarts: [start])

        XCTAssertEqual(Engine.segments(w, sensorStarts: [start]), [0 ..< 72, 72 ..< 144])
        // nothing fitted across the start: each sensor's flat line is flat
        XCTAssertEqual(result.noise?.mgdl ?? -1, 0, accuracy: 1E-9)
        XCTAssertTrue(result.gaps.isEmpty)
    }

    // MARK: - Rate of change

    func testFastRealRise() {
        // 3 mg/dL/min for an hour, at both cadences
        for step in [TimeInterval.minutes(1), .minutes(5)] {
            let readings = series(every: step, for: .hours(3)) { minutes in
                minutes < 60 ? 100 : minutes < 120 ? 100 + 3 * (minutes - 60) : 280
            }

            let result = stats(readings)

            XCTAssertEqual(result.rateOfChange?.fastestRise?.rate ?? 0, 3, accuracy: 1E-6, "\(step)")
        }
    }

    func testRateOfChangeBands() {
        // an hour at each of 0.5, 1.5, 2.5 and 3.5 mg/dL/min
        let rates = [0.5, 1.5, 2.5, 3.5]
        let readings = series(every: .minutes(1), for: .hours(4)) { minutes in
            let hour = Int(minutes / 60)
            let before = rates.prefix(hour).reduce(0) { $0 + $1 * 60 }
            return 50 + before + rates[hour] * (minutes - Double(hour) * 60)
        }

        let result = stats(readings)

        for band in CGMRateBand.allCases {
            XCTAssertEqual(result.rateOfChange?.share(band) ?? 0, 0.25, accuracy: 0.03, "\(band)")
        }
        // the readings are rounded to whole mg/dL
        XCTAssertEqual(result.rateOfChange?.fastestRise?.rate ?? 0, 3.5, accuracy: 0.05)
        XCTAssertNil(result.rateOfChange?.fastestFall)
    }

    // MARK: - Empty and tiny

    func testEmptyInput() {
        let result = stats([])

        XCTAssertEqual(result.readings, 0)
        XCTAssertNil(result.cadence)
        XCTAssertNil(result.span)
        XCTAssertEqual(result.coverage, .zero)
        XCTAssertNil(result.coverage.fraction)
        XCTAssertNil(result.noise)
        XCTAssertNil(result.deltaJitter)
        XCTAssertEqual(result.reversals, CGMReversals())
        XCTAssertNil(result.reversals.rawPerDay)
        XCTAssertNil(result.rateOfChange)
        XCTAssertNil(result.longestGap)
    }

    func testTinyInputs() {
        let one = stats([GlucosePoint(time: Self.day0, mgdl: 120)])
        XCTAssertEqual(one.readings, 1)
        XCTAssertNil(one.cadence)
        XCTAssertEqual(one.coverage, CGMCoverage(received: 1))
        XCTAssertNil(one.noise)
        XCTAssertNil(one.rateOfChange)

        let two = stats([GlucosePoint(time: Self.day0, mgdl: 120), GlucosePoint(time: at(5), mgdl: 125)])
        XCTAssertEqual(two.cadence, .minutes(5))
        XCTAssertNil(two.noise)
        XCTAssertEqual(two.reversals.raw, 0)

        // error codes, readings outside the period or after now, and duplicates are left out
        let mixed = [
            GlucosePoint(time: at(0), mgdl: 120),
            GlucosePoint(time: at(0), mgdl: 121),
            GlucosePoint(time: at(5), mgdl: 39),
            GlucosePoint(time: at(-5), mgdl: 120),
            GlucosePoint(time: at(10), mgdl: 120),
            GlucosePoint(time: at(15), mgdl: 120)
        ]
        let result = stats(mixed, period: DateInterval(start: Self.day0, duration: .days(1)), now: at(12))
        XCTAssertEqual(result.readings, 2)
    }

    // MARK: - Performance

    func testNinetyDaysOfOneMinuteReadingsComputes() {
        let start = Self.day0.addingTimeInterval(-.days(90))
        var random = SeededRandom(seed: 5)
        var readings = series(from: start, every: .minutes(1), for: .days(90)) { minutes in
            140 + 40 * sin(2 * .pi * minutes / 300) + 4 * random.gaussian()
        }
        // an hour's gap every 3 days
        readings = readings.enumerated().filter { !(2000 ..< 2060).contains($0.offset % 4320) }.map(\.element)
        let sensorStarts = (0 ..< 9).map { start.addingTimeInterval(.days(Double($0) * 10)) }

        let result = stats(readings, sensorStarts: sensorStarts)

        XCTAssertEqual(result.readings, readings.count)
        XCTAssertEqual(result.gaps.count, 30)
        XCTAssertEqual(result.noise?.mgdl ?? 0, 4, accuracy: 0.4)
        XCTAssertEqual(result.noiseBySensorDay.keys.sorted(), Array(1 ... 10))
    }
}
