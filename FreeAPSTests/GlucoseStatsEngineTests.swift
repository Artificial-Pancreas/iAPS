@testable import FreeAPS
import SwiftUI
import XCTest

private typealias Engine = GlucoseStatsEngine

final class GlucoseStatsEngineTests: XCTestCase {
    // MARK: - fixtures

    private static let calendar = StatsFixtures.berlin

    private var calendar: Calendar { Self.calendar }

    /// 2026-10-20
    private static let day0 = StatsFixtures.day0
    /// 2026-03-29, a 23-hour day
    private static let springForward = StatsFixtures.springForward
    /// 2026-10-25, a 25-hour day
    private static let fallBack = StatsFixtures.fallBack

    private let bands = StatsBands(low: 70, high: 145, units: .mgdL)

    private func day(_ offset: Int, from start: Date = GlucoseStatsEngineTests.day0) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    /// oldest -> newest
    private func points(
        from start: Date,
        every step: TimeInterval,
        count: Int,
        value: (Int) -> Int16 = { _ in 120 }
    ) -> [GlucosePoint] {
        (0 ..< count).map { GlucosePoint(time: start.addingTimeInterval(Double($0) * step), mgdl: value($0)) }
    }

    private func weighed(_ points: [GlucosePoint]) -> [WeightedPoint] {
        Engine.weigh(Engine.clean(points))
    }

    private struct Computed {
        let w: [WeightedPoint]
        let window: DateInterval
        let days: [DayAggregate]
        let summary: GlucoseSummary
    }

    /// The whole computation of a period, the way the service runs it, from raw readings.
    private func compute(
        _ period: StatsPeriod,
        _ points: [GlucosePoint],
        now: Date,
        bands: StatsBands? = nil
    ) -> Computed {
        let w = weighed(points)
        let (end, endRule) = Engine.effectiveEndRule(w, now: now, calendar: calendar)
        let window = Engine.window(for: period, now: now, end: end, calendar: calendar)
        let dayIntervals = Engine.days(for: period, window: window, calendar: calendar)
        let days = Engine.dayAggregates(w, days: dayIntervals)
        let counts = Engine.dayCounts(period, days: days)
        let summary = Engine.summary(
            Engine.histogram(w, clippedTo: window),
            window: window,
            endRule: endRule,
            calendarDays: counts.calendarDays,
            daysWithData: counts.daysWithData,
            bands: bands ?? self.bands
        )
        return Computed(w: w, window: window, days: days, summary: summary)
    }

    private func summary(_ period: StatsPeriod, _ points: [GlucosePoint], now: Date) -> GlucoseSummary {
        compute(period, points, now: now).summary
    }

    /// A histogram of single values, each for the given seconds.
    private func histogram(
        _ entries: [(mgdl: Int16, seconds: Double)],
        at time: Date = GlucoseStatsEngineTests.day0
    ) -> GlucoseHistogram {
        var histogram = GlucoseHistogram()
        for entry in entries {
            histogram.add(
                WeightedPoint(time: time, mgdl: entry.mgdl, span: entry.seconds),
                seconds: entry.seconds,
                startsInside: true
            )
        }
        return histogram
    }

    private func summary(
        of histogram: GlucoseHistogram,
        duration: TimeInterval? = nil,
        calendarDays: Int = 1,
        daysWithData: Int = 1
    ) -> GlucoseSummary {
        Engine.summary(
            histogram,
            window: DateInterval(start: Self.day0, duration: duration ?? histogram.totalSeconds),
            endRule: .stalled,
            calendarDays: calendarDays,
            daysWithData: daysWithData,
            bands: bands
        )
    }

    // MARK: - Coverage and weighting

    func testSteadyFiveMinutesCoverTheDay() {
        let s = compute(.today, points(from: Self.day0, every: .minutes(5), count: 288), now: day(1).addingTimeInterval(-1))
        XCTAssertTrue(s.w.allSatisfy { $0.span == .minutes(5) })
        XCTAssertEqual(s.window, DateInterval(start: Self.day0, end: day(1)))
        XCTAssertEqual(s.summary.coverage, 1, accuracy: 1E-12)
        XCTAssertEqual(s.summary.coveragePercent, 100)
        XCTAssertFalse(s.summary.isLimited)
    }

    func testJitteredFiveMinutesCoverTheDay() {
        let jitter: [TimeInterval] = [0, 5, -5, 3, -3]
        let jittered = points(from: Self.day0, every: .minutes(5), count: 288).enumerated().map {
            GlucosePoint(time: $0.element.time.addingTimeInterval(jitter[$0.offset % jitter.count]), mgdl: $0.element.mgdl)
        }
        let s = summary(.today, jittered, now: day(1).addingTimeInterval(-1))
        XCTAssertEqual(s.coverage, 1, accuracy: 1E-12)
        XCTAssertEqual(s.coveragePercent, 100)
    }

    func testSteadyOneMinuteCoversTheDay() {
        let s = compute(.today, points(from: Self.day0, every: .minutes(1), count: 1440), now: day(1).addingTimeInterval(-1))
        XCTAssertTrue(s.w.allSatisfy { $0.span == .minutes(1) })
        XCTAssertEqual(s.summary.coverage, 1, accuracy: 1E-12)
    }

    func testOneMissingOneMinuteReading() {
        var series = points(from: Self.day0, every: .minutes(1), count: 1440)
        series.remove(at: 700)
        let s = summary(.today, series, now: day(1).addingTimeInterval(-1))
        XCTAssertEqual(s.coverage, 1439.0 / 1440.0, accuracy: 1E-12)
    }

    func testOneMissingFiveMinuteReading() {
        var series = points(from: Self.day0, every: .minutes(5), count: 288)
        series.remove(at: 100)
        let s = summary(.today, series, now: day(1).addingTimeInterval(-1))
        XCTAssertEqual(s.coverage, 287.0 / 288.0, accuracy: 1E-12)
    }

    func testTwoHourGapIsNotCovered() {
        // 10:00 ..< 12:00 missing
        let series = points(from: Self.day0, every: .minutes(5), count: 288).enumerated()
            .filter { !(120 ..< 144).contains($0.offset) }
            .map(\.element)
        let s = compute(.today, series, now: day(1).addingTimeInterval(-1))
        XCTAssertEqual(s.summary.histogram.totalSeconds, 264 * 300, accuracy: 1E-9)
        // the reading before the gap covers its own 5 minutes, nothing of the gap
        XCTAssertEqual(s.w[119].span, .minutes(5))
        XCTAssertEqual(s.summary.coverage, 264.0 / 288.0, accuracy: 1E-12)
    }

    func testInterleavedFiveMinuteStreamsKeepAFiveMinuteCadence() {
        // Δ alternates 120 / 180 s
        let a = points(from: Self.day0, every: .minutes(5), count: 288)
        let b = points(from: Self.day0.addingTimeInterval(120), every: .minutes(5), count: 288)
        let s = compute(.today, a + b, now: day(1).addingTimeInterval(-1))
        XCTAssertEqual(s.w.last?.span, .minutes(5))
        XCTAssertEqual(s.summary.coverage, 1, accuracy: 1E-12)
        XCTAssertEqual(s.summary.coveragePercent, 100)
    }

    func testCadenceForgetsTheReadingsBeforeAGap() {
        // a 1-minute sensor up to 21:00, nothing for 2.5 hours, a 5-minute one from 23:30
        let oneMinute = points(from: day(-2), every: .minutes(1), count: 45 * 60 + 1)
        let fiveMinute = points(from: Self.day0.addingTimeInterval(-TimeInterval.minutes(30)), every: .minutes(5), count: 294)
        XCTAssertEqual(oneMinute.last?.time, day(-1).addingTimeInterval(.hours(21)))
        let series = oneMinute + fiveMinute
        let today = DateInterval(start: Self.day0, end: day(1))

        // read from 2 days before, or from mid-gap (the service's 1 h before the day)
        let fromEarlier = weighed(series)
        let fromMidGap = weighed(series.filter { $0.time >= Self.day0.addingTimeInterval(-TimeInterval.hours(1)) })

        // the 1-minute readings are too long ago to set the cadence: every 5-minute reading covers its 5 minutes
        let afterGap = Array(fromEarlier.suffix(fiveMinute.count))
        XCTAssertEqual(afterGap, fromMidGap)
        XCTAssertTrue(afterGap.allSatisfy { $0.span == .minutes(5) })
        XCTAssertEqual(Engine.dayAggregates(fromEarlier, days: [today]), Engine.dayAggregates(fromMidGap, days: [today]))

        // the lookback the service reads before every window holds the horizon and a span running into the window
        XCTAssertLessThanOrEqual(
            Engine.cadenceHorizon + .minutes(5) * GapDetection.Config.tolerance,
            GlucoseStatistics.Config.lookback
        )
    }

    func testCadenceThreshold() {
        XCTAssertEqual(Engine.cadence(previousDeltas: []), .minutes(5))
        XCTAssertEqual(Engine.cadence(previousDeltas: [90]), .minutes(1))
        XCTAssertEqual(Engine.cadence(previousDeltas: [91]), .minutes(5))
        XCTAssertEqual(Engine.cadence(previousDeltas: [60, 120]), .minutes(1)) // median 90
        XCTAssertEqual(Engine.cadence(previousDeltas: [120, 180, 120, 180]), .minutes(5))

        let at90 = weighed(points(from: Self.day0, every: 90, count: 20))
        XCTAssertEqual(at90.last?.span, .minutes(1))
        XCTAssertEqual(at90[10].span, 90) // 90 s is within 1.5 × 1 minute

        let at91 = weighed(points(from: Self.day0, every: 91, count: 20))
        XCTAssertEqual(at91.last?.span, .minutes(5))
        XCTAssertEqual(at91[10].span, 91)
    }

    func testWeighMatchesTheSortingCadence() {
        // the cadence as first written, sorting the last distances at every reading: `weigh` keeps them sorted as it
        // goes, with the same spans
        func reference(_ sorted: [GlucosePoint]) -> [TimeInterval] {
            var spans: [TimeInterval] = []
            var recent: [(from: Date, delta: TimeInterval)] = []
            for (index, point) in sorted.enumerated() {
                let horizon = point.time.addingTimeInterval(-Engine.cadenceHorizon)
                while let first = recent.first, first.from < horizon {
                    recent.removeFirst()
                }
                let expected = Engine.cadence(previousDeltas: recent.map(\.delta))
                guard index + 1 < sorted.count else {
                    spans.append(expected)
                    continue
                }
                let delta = sorted[index + 1].time.timeIntervalSince(point.time)
                spans.append(delta <= expected * GapDetection.Config.tolerance ? Swift.max(delta, 0) : expected)
                if delta > 0 {
                    recent.append((from: point.time, delta: delta))
                    if recent.count > Engine.cadenceWindow {
                        recent.removeFirst()
                    }
                }
            }
            return spans
        }

        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        for trial in 0 ..< 20 {
            var time = Self.day0
            var series: [GlucosePoint] = []
            for _ in 0 ..< 2000 {
                let step: TimeInterval
                switch next() % 100 {
                case 0 ..< 40: step = 60 + Double(next() % 30) // 1-minute, jittered
                case 40 ..< 70: step = 290 + Double(next() % 20) // 5-minute, jittered
                case 70 ..< 80: step = Double(next() % 200) // interleaved
                case 80 ..< 85: step = 0 // same timestamp
                case 85 ..< 90: step = Double(next() % 7200) // gaps
                default: step = [60, 90, 91, 120, 150, 180][Int(next() % 6)] // around the thresholds
                }
                time = time.addingTimeInterval(step)
                series.append(GlucosePoint(time: time, mgdl: 120))
            }
            // with the same-timestamp readings (zero distances) and cleaned
            XCTAssertEqual(Engine.weigh(series).map(\.span), reference(series), "trial \(trial)")
            let cleaned = Engine.clean(series)
            XCTAssertEqual(Engine.weigh(cleaned).map(\.span), reference(cleaned), "trial \(trial), cleaned")
        }
    }

    func testMixedSensorsWeighByTime() {
        // 00:00-12:00 every 5 minutes in range, 12:00-24:00 every minute high:
        // counted 144 vs 720 readings, timed 12 h vs 12 h
        let fiveMinute = points(from: Self.day0, every: .minutes(5), count: 144) { _ in 100 }
        let oneMinute = points(from: Self.day0.addingTimeInterval(.hours(12)), every: .minutes(1), count: 720) { _ in 200 }
        let s = summary(.today, fiveMinute + oneMinute, now: day(1).addingTimeInterval(-1))
        XCTAssertEqual(s.fraction(.inRange), 0.5, accuracy: 1E-12)
        XCTAssertEqual(s.fraction(.high), 0.5, accuracy: 1E-12)
        XCTAssertEqual(s.percent(.inRange), 50)
        XCTAssertEqual(s.mean ?? 0, 150, accuracy: 1E-9)
        XCTAssertEqual(s.coverage, 1, accuracy: 1E-12)
    }

    func testExactDuplicatesKeepTheLowest() {
        let series = points(from: Self.day0, every: .minutes(5), count: 100) { Int16(80 + $0) }
        // the concurrent Nightscout-import saves: same timestamps, higher values
        let duplicates = series.enumerated().filter { $0.offset.isMultiple(of: 7) }
            .map { GlucosePoint(time: $0.element.time, mgdl: $0.element.mgdl + 50) }
        let withDuplicates = (duplicates + series).reversed()

        XCTAssertEqual(Engine.clean(Array(withDuplicates)), series)
        let now = Self.day0.addingTimeInterval(.hours(12))
        XCTAssertEqual(summary(.today, Array(withDuplicates), now: now), summary(.today, series, now: now))

        // whatever the fetch order
        let high = GlucosePoint(time: Self.day0, mgdl: 150)
        let low = GlucosePoint(time: Self.day0, mgdl: 90)
        XCTAssertEqual(Engine.clean([high, low]), [low])
        XCTAssertEqual(Engine.clean([low, high]), [low])
    }

    func testCleanDropsNonPositiveValues() {
        let series = [
            GlucosePoint(time: Self.day0, mgdl: 0),
            GlucosePoint(time: Self.day0.addingTimeInterval(300), mgdl: 100)
        ]
        XCTAssertEqual(Engine.clean(series), [series[1]])
    }

    // MARK: - Bands

    func testBandEdges() {
        XCTAssertEqual(bands.band(53), .veryLow)
        XCTAssertEqual(bands.band(54), .low)
        XCTAssertEqual(bands.band(69), .low)
        XCTAssertEqual(bands.band(70), .inRange)
        XCTAssertEqual(bands.band(145), .inRange)
        XCTAssertEqual(bands.band(146), .high)
        XCTAssertEqual(bands.band(250), .high)
        XCTAssertEqual(bands.band(251), .veryHigh)

        // the band seconds use the same edges
        let edges: [(mgdl: Int16, band: GlucoseBand)] = [
            (53, .veryLow), (54, .low), (69, .low), (70, .inRange), (145, .inRange), (146, .high), (250, .high), (251, .veryHigh)
        ]
        for edge in edges {
            XCTAssertEqual(summary(of: histogram([(edge.mgdl, 300)])).fraction(edge.band), 1, "\(edge.mgdl)")
        }
    }

    func testTIRAndTITREdges() {
        func tir(_ value: Int16) -> Double { summary(of: histogram([(value, 300)])).tirFraction }
        func titr(_ value: Int16) -> Double { summary(of: histogram([(value, 300)])).titrFraction }
        XCTAssertEqual(bands.tirRange, 70 ... 180)
        XCTAssertEqual(bands.titrRange, 70 ... 140)
        XCTAssertEqual(tir(69), 0)
        XCTAssertEqual(tir(70), 1)
        XCTAssertEqual(tir(180), 1)
        XCTAssertEqual(tir(181), 0)
        XCTAssertEqual(titr(140), 1)
        XCTAssertEqual(titr(141), 0)
    }

    func testMmolTIRAndTITRUseTheDisplayedEdges() {
        // high 10.0 mmol/L: 181 is displayed as 10.0, 182 as 10.1; 70 as 3.9, 69 as 3.8
        XCTAssertEqual(StatsBands.mmolDisplay(181), Decimal(string: "10.0"))
        XCTAssertEqual(StatsBands.mmolDisplay(182), Decimal(string: "10.1"))
        XCTAssertEqual(StatsBands.mmolDisplay(70), Decimal(string: "3.9"))
        XCTAssertEqual(StatsBands.mmolDisplay(69), Decimal(string: "3.8"))
        XCTAssertEqual(StatsBands.mmolDisplay(141), Decimal(string: "7.8"))
        XCTAssertEqual(StatsBands.mmolDisplay(142), Decimal(string: "7.9"))

        let mmol = StatsBands(low: Decimal(string: "3.9")!.asMgdL, high: Decimal(string: "10.0")!.asMgdL, units: .mmolL)
        XCTAssertEqual(mmol.low, 70)
        XCTAssertEqual(mmol.high, 181)
        XCTAssertEqual(mmol.tirRange, 70 ... 181)
        XCTAssertEqual(mmol.titrRange, 70 ... 141)
        // the fixed edges stay
        XCTAssertEqual(mmol.band(53), .veryLow)
        XCTAssertEqual(mmol.band(250), .high)
        XCTAssertEqual(mmol.band(251), .veryHigh)

        let titrHigh = StatsBands(low: Decimal(string: "3.9")!.asMgdL, high: Decimal(string: "7.8")!.asMgdL, units: .mmolL)
        XCTAssertEqual(titrHigh.high, 141)
        XCTAssertEqual(titrHigh.titrRange, 70 ... 141)

        // the readings counted follow the edges: "3.9-10.0" counts the same readings in both rows
        func s(_ value: Int16) -> GlucoseSummary {
            Engine.summary(
                histogram([(value, 300)]),
                window: DateInterval(start: Self.day0, duration: 300),
                endRule: .stalled,
                calendarDays: 1,
                daysWithData: 1,
                bands: mmol
            )
        }
        for value: Int16 in [69, 70, 181, 182] {
            XCTAssertEqual(s(value).tirFraction, s(value).fraction(.inRange), "\(value)")
        }
        XCTAssertEqual(s(181).tirFraction, 1)
        XCTAssertEqual(s(182).tirFraction, 0)
        XCTAssertEqual(s(141).titrFraction, 1)
        XCTAssertEqual(s(142).titrFraction, 0)
        XCTAssertEqual(s(69).tirFraction, 0)
    }

    func testTIRShowsTheInRangePercentForTheSameRange() {
        // 1.3 / 3.3 / 71.4 / 18.0 / 6.0 %: largest remainder gives in range 72, plain rounding of TIR 71
        let h = histogram([(50, 13), (60, 33), (120, 714), (200, 180), (300, 60)])
        let window = DateInterval(start: Self.day0, duration: 1000)
        let sameRange = StatsBands(low: 70, high: 180, units: .mgdL)
        let s = Engine.summary(h, window: window, endRule: .stalled, calendarDays: 1, daysWithData: 1, bands: sameRange)
        XCTAssertEqual(s.bandShares.percents, [1, 3, 72, 18, 6])
        XCTAssertEqual(Int((s.tirFraction * 100).rounded()), 71)
        XCTAssertEqual(s.tirPercent, 72)
        XCTAssertEqual(s.tirPercent, s.percent(.inRange))
        // TITR is a different range: rounded plainly
        XCTAssertEqual(s.titrPercent, 71)

        // a different in-range band: TIR is rounded plainly
        let other = Engine.summary(h, window: window, endRule: .stalled, calendarDays: 1, daysWithData: 1, bands: bands)
        XCTAssertEqual(other.tirPercent, 71)

        // in range = TITR range
        let titrRange = StatsBands(low: 70, high: 140, units: .mgdL)
        let titr = Engine.summary(h, window: window, endRule: .stalled, calendarDays: 1, daysWithData: 1, bands: titrRange)
        XCTAssertEqual(titr.titrPercent, 72)
        XCTAssertEqual(titr.tirPercent, 71)
    }

    func testMgdlSettingsRoundHalfUp() {
        XCTAssertEqual(StatsBands(low: Decimal(string: "70.27")!, high: 145, units: .mgdL).low, 70)
        XCTAssertEqual(StatsBands(low: Decimal(string: "70.5")!, high: 145, units: .mgdL).low, 71)
        XCTAssertEqual(StatsBands(low: 70, high: Decimal(string: "145.49")!, units: .mgdL).high, 145)
    }

    func testMmolSettingsUseTheDisplayedEdges() {
        // 8.0 mmol/L is stored as 144.14 mg/dL; 145 is still displayed as 8.0
        XCTAssertEqual(StatsBands(low: 70, high: Decimal(string: "144.14")!, units: .mmolL).high, 145)
        XCTAssertEqual(StatsBands(low: 70, high: Decimal(string: "8.0")!.asMgdL, units: .mmolL).high, 145)
        // 3.9 mmol/L is stored as 70.27 mg/dL; 69 is displayed as 3.8, 70 as 3.9
        XCTAssertEqual(StatsBands(low: Decimal(string: "70.27")!, high: 145, units: .mmolL).low, 70)
        XCTAssertEqual(StatsBands(low: Decimal(string: "3.9")!.asMgdL, high: 145, units: .mmolL).low, 70)
    }

    func testOutOfRangeSettingsAreClampedAndEmptyBandsHidden() {
        let clamped = StatsBands(low: 40, high: 270, units: .mgdL)
        XCTAssertEqual(clamped.low, 54)
        XCTAssertEqual(clamped.high, 250)
        XCTAssertEqual(clamped.visibleBands, [.veryLow, .inRange, .veryHigh])
        XCTAssertNil(clamped.range(of: .low))
        XCTAssertNil(clamped.range(of: .high))
        XCTAssertEqual(clamped.band(54), .inRange)
        XCTAssertEqual(clamped.band(250), .inRange)

        // hidden bands stay in the arrays, with 0
        let s = Engine.summary(
            histogram([(60, 300)]),
            window: DateInterval(start: Self.day0, duration: 300),
            endRule: .stalled,
            calendarDays: 1,
            daysWithData: 1,
            bands: clamped
        )
        XCTAssertEqual(s.bandShares.fractions.count, GlucoseBand.allCases.count)
        XCTAssertEqual(s.fraction(.low), 0)
        XCTAssertEqual(s.fraction(.inRange), 1)

        XCTAssertEqual(bands.visibleBands, GlucoseBand.allCases)

        let inverted = StatsBands(low: 100, high: 90, units: .mgdL)
        XCTAssertEqual(inverted.low, 100)
        XCTAssertEqual(inverted.high, 100)
    }

    func testMmolDisplayMatchesTheGlucoseFormatter() {
        // configured like CurrentGlucoseView.mmolLFormatter
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp

        for value in 40 ... 400 {
            let text = formatter.string(from: NSNumber(value: Double(Decimal(value).asMmolL)))
            XCTAssertNotNil(text)
            XCTAssertEqual(StatsBands.mmolDisplay(value), text.flatMap { Decimal(string: $0) }, "\(value) mg/dL")
        }
    }

    // MARK: - Statistics and A1c

    func testWeightedMeanSDAndCV() {
        // 100 for 10 minutes, 200 for 5 minutes
        let series = [
            GlucosePoint(time: Self.day0, mgdl: 100),
            GlucosePoint(time: Self.day0.addingTimeInterval(.minutes(5)), mgdl: 100),
            GlucosePoint(time: Self.day0.addingTimeInterval(.minutes(10)), mgdl: 200)
        ]
        let w = weighed(series)
        let h = Engine.histogram(w, clippedTo: DateInterval(start: Self.day0, duration: .minutes(15)))
        let s = summary(of: h)

        let mean = (100.0 * 600 + 200.0 * 300) / 900
        let sd = ((100.0 * 100 * 600 + 200.0 * 200 * 300) / 900 - mean * mean).squareRoot()
        XCTAssertEqual(s.mean ?? 0, mean, accuracy: 1E-9)
        XCTAssertEqual(s.sd ?? 0, sd, accuracy: 1E-9)
        XCTAssertEqual(s.cv ?? 0, sd / mean * 100, accuracy: 1E-9)
        XCTAssertEqual(s.minMax, 100 ... 200)
        XCTAssertEqual(s.histogram.readingCount, 3)
    }

    func testA1cEstimates() {
        let gmi154 = Engine.gmiPercent(meanMgdl: 154)
        let eA1c154 = Engine.eA1cPercent(meanMgdl: 154)
        XCTAssertEqual(gmi154, 6.99, accuracy: 0.005)
        XCTAssertEqual(Int(Engine.ifcc(fromPercent: gmi154).rounded()), 53)
        XCTAssertEqual(eA1c154, 6.99, accuracy: 0.005)
        XCTAssertEqual(Int(Engine.ifcc(fromPercent: eA1c154).rounded()), 53)

        let gmi150 = Engine.gmiPercent(meanMgdl: 150)
        let eA1c150 = Engine.eA1cPercent(meanMgdl: 150)
        XCTAssertEqual(gmi150, 6.90, accuracy: 0.005)
        XCTAssertEqual(Int(Engine.ifcc(fromPercent: gmi150).rounded()), 52)
        XCTAssertEqual(eA1c150, 6.85, accuracy: 0.005)
        XCTAssertEqual(Int(Engine.ifcc(fromPercent: eA1c150).rounded()), 51)

        let s = summary(of: histogram([(154, 300)]))
        XCTAssertEqual(s.gmiPercent ?? 0, gmi154, accuracy: 1E-12)
        XCTAssertEqual(s.eA1cPercent ?? 0, eA1c154, accuracy: 1E-12)
    }

    func testHbA1cUnit() {
        XCTAssertEqual(HbA1cUnit.resolve(units: .mgdL, override: false), .percent)
        XCTAssertEqual(HbA1cUnit.resolve(units: .mgdL, override: true), .mmolPerMol)
        XCTAssertEqual(HbA1cUnit.resolve(units: .mmolL, override: false), .mmolPerMol)
        XCTAssertEqual(HbA1cUnit.resolve(units: .mmolL, override: true), .percent)
    }

    func testLargestRemainder() {
        let thirds = Engine.largestRemainder([1.0 / 3, 1.0 / 3, 1.0 / 3, 0, 0])
        XCTAssertEqual(thirds.reduce(0, +), 100)
        XCTAssertEqual(thirds, [34, 33, 33, 0, 0])
        XCTAssertEqual(Engine.largestRemainder([0, 0, 0, 0, 0]), [0, 0, 0, 0, 0])
        XCTAssertEqual(Engine.largestRemainder([0.004, 0.006, 0.5, 0.49, 0]).reduce(0, +), 100)
    }

    func testBelowOnePercent() {
        let s = summary(of: histogram([(60, 1), (100, 9999)]))
        XCTAssertEqual(s.percent(.low), 0)
        XCTAssertTrue(s.isBelowOnePercent(.low))
        XCTAssertFalse(s.isBelowOnePercent(.high))
        XCTAssertFalse(s.isBelowOnePercent(.inRange))
        XCTAssertEqual(s.bandShares.percents.reduce(0, +), 100)
    }

    // MARK: - Time handling

    func testSpanIsSplitAtMidnight() {
        let w = [WeightedPoint(time: day(1).addingTimeInterval(-TimeInterval.minutes(2)), mgdl: 120, span: .minutes(5))]
        let days = Engine.dayAggregates(w, days: [
            DateInterval(start: Self.day0, end: day(1)),
            DateInterval(start: day(1), end: day(2))
        ])
        XCTAssertEqual(days[0].histogram.totalSeconds, .minutes(2), accuracy: 1E-9)
        XCTAssertEqual(days[1].histogram.totalSeconds, .minutes(3), accuracy: 1E-9)
        // counted once, on the day it starts
        XCTAssertEqual(days[0].histogram.readingCount, 1)
        XCTAssertEqual(days[1].histogram.readingCount, 0)
    }

    func testDSTDays() {
        let short = StatsClock.calendarDays(in: DateInterval(start: Self.springForward, duration: 1), calendar: calendar)
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short[0].duration, .hours(23))
        let long = StatsClock.calendarDays(in: DateInterval(start: Self.fallBack, duration: 1), calendar: calendar)
        XCTAssertEqual(long.count, 1)
        XCTAssertEqual(long[0].duration, .hours(25))

        // complete days have full coverage, whatever their length
        let shortDay = summary(
            .today,
            points(from: Self.springForward, every: .minutes(5), count: 23 * 12),
            now: day(1, from: Self.springForward).addingTimeInterval(-1)
        )
        XCTAssertEqual(shortDay.window.duration, .hours(23))
        XCTAssertEqual(shortDay.coverage, 1, accuracy: 1E-12)

        let longDay = compute(
            .today,
            points(from: Self.fallBack, every: .minutes(5), count: 25 * 12),
            now: day(1, from: Self.fallBack).addingTimeInterval(-1)
        )
        XCTAssertEqual(longDay.window.duration, .hours(25))
        XCTAssertEqual(longDay.summary.coverage, 1, accuracy: 1E-12)

        // 02:00-03:00 happens twice
        let hours = Engine.hourOfDay(longDay.w, calendar: calendar, clippedTo: longDay.window)
        XCTAssertEqual(hours[2].histogram.totalSeconds, .hours(2), accuracy: 1E-9)
        XCTAssertEqual(hours[3].histogram.totalSeconds, .hours(1), accuracy: 1E-9)

        // an N-day window across the change starts at local midnight
        let now = day(6).addingTimeInterval(.hours(12)) // 2026-10-26 12:00 CET
        let week = Engine.window(for: .days7, now: now, end: now, calendar: calendar)
        XCTAssertEqual(week.start, Self.day0)
    }

    func testClockHistogramsFollowTheLocalClockAcrossDSTChanges() {
        // every 5 minutes over three days around each change: every span goes to its reading's local clock hour (the
        // zone's offset is looked up once per transition, not per reading)
        for change in [Self.springForward, Self.fallBack] {
            let w = weighed(points(from: day(-1, from: change), every: .minutes(5), count: 3 * 288))
            guard let first = w.first, let last = w.last else { return XCTFail("no readings") }
            let hours = Engine.hourOfDay(w, calendar: calendar, clippedTo: DateInterval(start: first.time, end: last.end))
            var expected = [Double](repeating: 0, count: 24)
            for point in w {
                expected[calendar.component(.hour, from: point.time)] += point.span
            }
            for hour in 0 ..< 24 {
                XCTAssertEqual(hours[hour].histogram.totalSeconds, expected[hour], accuracy: 1E-9, "\(change) \(hour)")
            }
        }
    }

    func testCurrentDataDoesNotDependOnNow() {
        // 00:00 ... 12:00 every 5 minutes
        let series = points(from: Self.day0, every: .minutes(5), count: 145)
        let last = series.last!.time
        let soon = summary(.today, series, now: last.addingTimeInterval(10))
        let later = summary(.today, series, now: last.addingTimeInterval(.minutes(4)))
        XCTAssertEqual(soon, later)
        XCTAssertEqual(soon.window.end, last.addingTimeInterval(.minutes(5)))
        XCTAssertEqual(soon.coverage, 1, accuracy: 1E-12)
    }

    func testStallLowersCoverage() {
        let series = points(from: Self.day0, every: .minutes(5), count: 145)
        let last = series.last!.time
        let stalled = summary(.today, series, now: last.addingTimeInterval(.minutes(30)))
        XCTAssertEqual(stalled.window.end, last.addingTimeInterval(.minutes(30)))
        XCTAssertEqual(stalled.coverage, 145.0 * 300 / (12.5 * 3600), accuracy: 1E-12)
    }

    func testStallChangesOnlyOnceAMinute() {
        let series = points(from: Self.day0, every: .minutes(5), count: 145)
        let minute = series.last!.time.addingTimeInterval(.minutes(30))
        let early = summary(.today, series, now: minute.addingTimeInterval(5))
        let late = summary(.today, series, now: minute.addingTimeInterval(55))
        XCTAssertEqual(early, late)
        XCTAssertEqual(early.window.end, minute)
        XCTAssertNotEqual(early, summary(.today, series, now: minute.addingTimeInterval(65)))
    }

    func testEffectiveEndNeverPassesTheEndOfToday() {
        let w = [WeightedPoint(time: day(1).addingTimeInterval(-TimeInterval.minutes(2)), mgdl: 120, span: .minutes(5))]
        XCTAssertEqual(Engine.effectiveEnd(w, now: day(1).addingTimeInterval(-60), calendar: calendar), day(1))
    }

    func testStalledOneMinuteEndNeverMovesBackwards() {
        // every minute, the last at 12:00:10: it covers up to 12:01:10 and turns stalled after 12:01:40
        let last = Self.day0.addingTimeInterval(TimeInterval.hours(12) + 10)
        let w = weighed(points(from: last.addingTimeInterval(-TimeInterval.hours(1)), every: .minutes(1), count: 61))
        XCTAssertEqual(w.last?.time, last)
        XCTAssertEqual(w.last?.span, .minutes(1))
        XCTAssertEqual(Engine.effectiveEnd(w, now: last.addingTimeInterval(90), calendar: calendar), last.addingTimeInterval(60))
        // 12:01:41, stalled: the floored minute 12:01:00 is before the reading's end
        XCTAssertEqual(Engine.effectiveEnd(w, now: last.addingTimeInterval(91), calendar: calendar), last.addingTimeInterval(60))

        var previous = Date.distantPast
        for second in 0 ... 300 {
            let end = Engine.effectiveEnd(w, now: last.addingTimeInterval(Double(second)), calendar: calendar)
            XCTAssertGreaterThanOrEqual(end, previous, "now = last + \(second) s")
            previous = end
        }
        // 12:05:10 -> 12:05:00
        XCTAssertEqual(previous, Self.day0.addingTimeInterval(TimeInterval.hours(12) + .minutes(5)))
    }

    func testJustAfterMidnightTodayIsAnEmptyDayOfThePeriod() {
        // every 5 minutes, the last at 23:54:30, still current at 00:01:00: E = 23:59:30, before the start of today
        let today = day(1)
        let series = points(from: day(-6).addingTimeInterval(270), every: .minutes(5), count: 2015)
        XCTAssertEqual(series.last?.time, today.addingTimeInterval(-330))
        let now = today.addingTimeInterval(60)
        let end = today.addingTimeInterval(-30)

        let week = compute(.days7, series, now: now)
        XCTAssertEqual(week.window, DateInterval(start: day(-5), end: end))
        XCTAssertEqual(week.days.map(\.day.start), (-5 ... 1).map { day($0) })
        XCTAssertEqual(week.days[5].day, DateInterval(start: day(0), end: end))
        XCTAssertEqual(week.days[6].day, DateInterval(start: today, duration: 0))
        XCTAssertTrue(week.days[6].histogram.isEmpty)
        XCTAssertEqual(week.summary.calendarDays, 7)
        XCTAssertEqual(week.summary.daysWithData, 6)
        XCTAssertEqual(week.summary.coverage, 1, accuracy: 1E-12)

        let todayOnly = compute(.today, series, now: now)
        XCTAssertEqual(todayOnly.window, DateInterval(start: today, duration: 0))
        XCTAssertEqual(todayOnly.days.map(\.day), [DateInterval(start: today, duration: 0)])
        XCTAssertTrue(todayOnly.summary.isEmpty)
        XCTAssertEqual(todayOnly.summary.calendarDays, 1)
        XCTAssertEqual(todayOnly.summary.daysWithData, 0)
        XCTAssertEqual(todayOnly.summary.coverage, 0)

        // the weeks follow the same days: the last one ends with the empty today
        let fiveWeeks = compute(.weeks5, series, now: now)
        XCTAssertEqual(fiveWeeks.days.count, 35)
        let weeks = Engine.weeks(fiveWeeks.days, count: 5)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.map(\.includesToday), [false, false, false, false, true])
        XCTAssertEqual(weeks.last?.days, DateInterval(start: day(-5), end: today))
        XCTAssertEqual(weeks.last?.lastDay, today)
        XCTAssertEqual(weeks.last?.dayCount, 7)
        XCTAssertEqual(weeks.last?.histogram.totalSeconds ?? 0, end.timeIntervalSince(day(-5)), accuracy: 1E-6)
    }

    // MARK: - The end rule

    func testTheEndStaysUpToTheStall() {
        // every 5 minutes up to 12:00: current up to 12:07:30
        let series = points(from: Self.day0, every: .minutes(5), count: 145)
        let last = series.last!.time
        let stallsAt = last.addingTimeInterval(.minutes(5) * GapDetection.Config.tolerance)
        let requestedAt = last.addingTimeInterval(10)
        for period in [StatsPeriod.today, .last24h, .days7] {
            let s = summary(period, series, now: requestedAt)
            XCTAssertEqual(s.endRule, .current(stallsAt: stallsAt), "\(period)")
            XCTAssertFalse(s.endRule == .stalled, "\(period)")
            // nothing changes up to it (nor the 24 h window: it starts from E), and E moves right after it
            XCTAssertEqual(summary(period, series, now: stallsAt), s, "\(period)")
            let after = summary(period, series, now: stallsAt.addingTimeInterval(1))
            XCTAssertTrue(after.endRule == .stalled, "\(period)")
            XCTAssertNotEqual(after.window, s.window, "\(period)")
        }
    }

    func testTheEndOfAOneMinuteSensor() {
        // every minute, the last at 12:00:10: current up to 12:01:40; then E stays at its end (12:01:10) up to 12:02:00
        let last = Self.day0.addingTimeInterval(TimeInterval.hours(12) + 10)
        let series = points(from: last.addingTimeInterval(-TimeInterval.hours(1)), every: .minutes(1), count: 61)
        let requestedAt = last.addingTimeInterval(5)
        let current = summary(.today, series, now: requestedAt)
        XCTAssertEqual(current.endRule, .current(stallsAt: last.addingTimeInterval(90)))
        XCTAssertFalse(current.endRule == .stalled)

        // just stalled, 12:01:41: E moves on at the next whole minute
        let justStalledAt = last.addingTimeInterval(91)
        let justStalled = summary(.today, series, now: justStalledAt)
        XCTAssertTrue(justStalled.endRule == .stalled)
        XCTAssertEqual(justStalled.window, current.window)
        let twelveTwo = Self.day0.addingTimeInterval(TimeInterval.hours(12) + .minutes(2))
        XCTAssertEqual(summary(.today, series, now: twelveTwo.addingTimeInterval(-1)), justStalled)
        XCTAssertNotEqual(summary(.today, series, now: twelveTwo).window, justStalled.window)
    }

    func testTheEndWhileStalledIsTheFlooredMinute() {
        let series = points(from: Self.day0, every: .minutes(5), count: 145)
        let last = series.last!.time

        // just stalled, 12:07:31: E is 12:07
        let justStalledAt = last.addingTimeInterval(451)
        let justStalled = summary(.today, series, now: justStalledAt)
        XCTAssertEqual(justStalled.endRule, .stalled)
        XCTAssertTrue(justStalled.endRule == .stalled)
        XCTAssertEqual(justStalled.window.end, last.addingTimeInterval(.minutes(7)))

        // half an hour on: on the whole minute and within it, E is that minute
        let minute = last.addingTimeInterval(.minutes(30))
        for requestedAt in [minute, minute.addingTimeInterval(5), minute.addingTimeInterval(59.9)] {
            for period in [StatsPeriod.today, .last24h] {
                let stalled = summary(period, series, now: requestedAt)
                XCTAssertTrue(stalled.endRule == .stalled, "\(period) \(requestedAt)")
                XCTAssertEqual(stalled.window.end, minute, "\(period) \(requestedAt)")
            }
        }
    }

    func testTheEndIsClippedAtMidnight() {
        // the last reading at 23:59: its end (00:04 for 5 minutes, 00:00 for 1 minute) is clipped at midnight,
        // and it stalls after midnight
        let midnight = day(1)
        let last = midnight.addingTimeInterval(-60)
        let requestedAt = midnight.addingTimeInterval(-30)
        for step: TimeInterval in [.minutes(5), .minutes(1)] {
            let series = points(from: last.addingTimeInterval(-step * 60), every: step, count: 61)
            let s = summary(.today, series, now: requestedAt)
            XCTAssertEqual(s.window.end, midnight, "\(step)")
            XCTAssertEqual(
                s.endRule,
                .current(stallsAt: last.addingTimeInterval(step * GapDetection.Config.tolerance)),
                "\(step)"
            )
            // at midnight Today is a new day
            XCTAssertNotEqual(summary(.today, series, now: midnight).window, s.window, "\(step)")
        }

        // stalled at 23:59:30: E is the floored minute
        let stalled = summary(.today, points(from: Self.day0, every: .minutes(5), count: 145), now: requestedAt)
        XCTAssertTrue(stalled.endRule == .stalled)
        XCTAssertEqual(stalled.window.end, midnight.addingTimeInterval(-60))
    }

    func testAnEmptyWindowIsStalled() {
        let now = Self.day0.addingTimeInterval(.hours(10))
        let none = summary(.today, [], now: now)
        XCTAssertTrue(none.isEmpty)
        XCTAssertTrue(none.endRule == .stalled)

        // the readings are days before: the window is empty
        for period in [StatsPeriod.today, .last24h] {
            let old = summary(period, points(from: day(-3), every: .minutes(5), count: 100), now: now)
            XCTAssertTrue(old.isEmpty, "\(period)")
        }
    }

    func testTheEndJustAfterMidnight() {
        let today = day(1)
        let now = today.addingTimeInterval(60)

        // the last reading at 23:54:30, current up to 00:02:00: E = 23:59:30, so Today is empty and the week isn't
        let before = points(from: day(-6).addingTimeInterval(270), every: .minutes(5), count: 2015)
        let emptyToday = summary(.today, before, now: now)
        XCTAssertTrue(emptyToday.isEmpty)
        XCTAssertFalse(emptyToday.endRule == .stalled)
        XCTAssertEqual(summary(.days7, before, now: now).endRule, .current(stallsAt: today.addingTimeInterval(120)))

        // the carry-over: the last reading at 23:58 runs 3 minutes into Today, and none starts in it
        let carry = points(from: today.addingTimeInterval(-120 - 100 * 300), every: .minutes(5), count: 101)
        XCTAssertEqual(carry.last?.time, today.addingTimeInterval(-120))
        let current = summary(.today, carry, now: now)
        XCTAssertFalse(current.isEmpty)
        XCTAssertEqual(current.histogram.readingCount, 0)
        XCTAssertEqual(current.window, DateInterval(start: today, end: today.addingTimeInterval(180)))
        // current up to 00:05:30, unchanged up to it
        XCTAssertEqual(current.endRule, .current(stallsAt: today.addingTimeInterval(330)))
        XCTAssertEqual(summary(.today, carry, now: today.addingTimeInterval(330)), current)

        // stalled, 00:06
        let stalledAt = today.addingTimeInterval(.minutes(6))
        let stalled = summary(.today, carry, now: stalledAt)
        XCTAssertTrue(stalled.endRule == .stalled)
        XCTAssertFalse(stalled.isEmpty)
        XCTAssertEqual(stalled.histogram.readingCount, 0)
    }

    func testTheEndStallsJustAfterTheStall() {
        let series = points(from: Self.day0, every: .minutes(5), count: 145)
        let last = series.last!.time
        let stallsAt = last.addingTimeInterval(450)

        // at the moment itself still current; just after it, stalled
        let atStall = summary(.today, series, now: stallsAt)
        XCTAssertFalse(atStall.endRule == .stalled)
        let after = summary(.today, series, now: stallsAt.addingTimeInterval(0.001))
        XCTAssertTrue(after.endRule == .stalled)
        XCTAssertEqual(after.window.end, last.addingTimeInterval(.minutes(7)))
    }

    // MARK: - Additivity

    func testDaysAddUpToTheWindow() {
        // 14 days, readings at hh:m2 / hh:m7 (spans cross midnight), one from before the window, a gap, across the DST change
        let lastDay = day(13)
        let now = lastDay.addingTimeInterval(TimeInterval.hours(20) + .minutes(1))
        let start = Self.day0.addingTimeInterval(-TimeInterval.minutes(3))
        let count = Int(lastDay.addingTimeInterval(.hours(20)).timeIntervalSince(start) / 300) + 1
        let series = points(from: start, every: .minutes(5), count: count) { Int16(40 + ($0 * 37) % 300) }
            .enumerated()
            .filter { !(1000 ..< 1030).contains($0.offset) }
            .map(\.element)

        let raw = compute(.days14, series, now: now)
        XCTAssertEqual(raw.window.start, Self.day0)
        XCTAssertEqual(raw.days.count, 14)
        XCTAssertEqual(raw.summary.daysWithData, 14)

        let sum = raw.days.reduce(GlucoseHistogram()) { $0 + $1.histogram }
        let fromDays = Engine.summary(
            sum,
            window: raw.window,
            endRule: raw.summary.endRule,
            calendarDays: raw.summary.calendarDays,
            daysWithData: raw.summary.daysWithData,
            bands: bands
        )

        func assertClose(_ a: Double?, _ b: Double?, _ name: String) {
            guard let a, let b else { return XCTFail(name) }
            XCTAssertEqual(a, b, accuracy: Swift.max(abs(a), abs(b)) * 1E-9, name)
        }
        assertClose(fromDays.histogram.totalSeconds, raw.summary.histogram.totalSeconds, "seconds")
        assertClose(fromDays.mean, raw.summary.mean, "mean")
        assertClose(fromDays.sd, raw.summary.sd, "sd")
        assertClose(fromDays.coverage, raw.summary.coverage, "coverage")
        for band in GlucoseBand.allCases {
            XCTAssertEqual(fromDays.fraction(band), raw.summary.fraction(band), accuracy: 1E-9, "\(band)")
        }
        XCTAssertEqual(fromDays.bandShares.percents, raw.summary.bandShares.percents)
        XCTAssertEqual(fromDays.coveragePercent, raw.summary.coveragePercent)
        XCTAssertEqual(fromDays.histogram.readingCount, raw.summary.histogram.readingCount)
        XCTAssertEqual(fromDays.minMax, raw.summary.minMax)

        // the service's (and the Daily view's) summary of the days is that sum
        XCTAssertEqual(
            Engine.summary(days: raw.days, window: raw.window, endRule: raw.summary.endRule, period: .days14, bands: bands),
            fromDays
        )
    }

    // MARK: - Edge cases

    func testEmptyInput() {
        let s = summary(.today, [], now: Self.day0.addingTimeInterval(.hours(10)))
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.mean)
        XCTAssertNil(s.sd)
        XCTAssertNil(s.cv)
        XCTAssertNil(s.gmiPercent)
        XCTAssertNil(s.eA1cPercent)
        XCTAssertNil(s.minMax)
        XCTAssertNil(s.histogram.quantile(0.5))
        XCTAssertEqual(s.bandShares.percents, [0, 0, 0, 0, 0])
        XCTAssertFalse(s.bandShares.fractions.contains { $0.isNaN })
        XCTAssertFalse(s.coverage.isNaN || s.tirFraction.isNaN || s.titrFraction.isNaN)
        XCTAssertEqual(s.tirPercent, 0)
        XCTAssertEqual(s.titrPercent, 0)
        XCTAssertEqual(s.coveragePercent, 0)
        XCTAssertEqual(s.calendarDays, 1)
        XCTAssertEqual(s.daysWithData, 0)

        let none = Engine.summary(
            GlucoseHistogram(),
            window: DateInterval(start: Self.day0, duration: 0),
            endRule: .stalled,
            calendarDays: 0,
            daysWithData: 0,
            bands: bands
        )
        XCTAssertFalse(none.coverage.isNaN)
        XCTAssertTrue(
            Engine.agp([], calendar: calendar, clippedTo: DateInterval(start: Self.day0, duration: 0))
                .allSatisfy { $0 == nil }
        )
    }

    func testLimitedUsesTheRoundedCoverage() {
        let limited = summary(of: histogram([(120, 6949)]), duration: 10000)
        XCTAssertEqual(limited.coveragePercent, 69)
        XCTAssertTrue(limited.isLimited)

        let enough = summary(of: histogram([(120, 6951)]), duration: 10000)
        XCTAssertEqual(enough.coveragePercent, 70)
        XCTAssertFalse(enough.isLimited)
    }

    func testA1cNeedsFourteenDays() {
        let h = histogram([(120, 300)])
        let window = DateInterval(start: Self.day0, duration: 300)
        XCTAssertTrue(
            Engine.summary(h, window: window, endRule: .stalled, calendarDays: 14, daysWithData: 13, bands: bands)
                .a1cNeedsMoreDays
        )
        XCTAssertFalse(
            Engine.summary(h, window: window, endRule: .stalled, calendarDays: 14, daysWithData: 14, bands: bands)
                .a1cNeedsMoreDays
        )
    }

    func testTodayAndLast24hCountAsOneDay() {
        let series = points(from: Self.day0, every: .minutes(5), count: 2 * 288)
        let now = day(1).addingTimeInterval(.hours(12))
        let twoDays = Array(series.prefix(288 + 144))

        let last24h = compute(.last24h, twoDays, now: now)
        XCTAssertEqual(last24h.days.count, 2) // across two calendar dates
        XCTAssertEqual(last24h.summary.calendarDays, 1)
        XCTAssertEqual(last24h.summary.daysWithData, 1)
        XCTAssertEqual(last24h.window.duration, .hours(24))

        let today = summary(.today, twoDays, now: now)
        XCTAssertEqual(today.calendarDays, 1)
        XCTAssertEqual(today.daysWithData, 1)

        let week = summary(.days7, twoDays, now: now)
        XCTAssertEqual(week.calendarDays, 7)
        XCTAssertEqual(week.daysWithData, 2)
    }

    func testSpilloverAloneIsNotADayWithData() {
        // day 0 every 5 minutes, 00:03 ... 23:58: the last span runs 3 minutes into day 1, which has no readings
        let series = points(from: Self.day0.addingTimeInterval(.minutes(3)), every: .minutes(5), count: 288)
        XCTAssertEqual(series.last?.time, day(1).addingTimeInterval(-TimeInterval.minutes(2)))
        let s = compute(.days7, series, now: day(2).addingTimeInterval(.hours(12)))
        XCTAssertEqual(s.days.count, 7)
        XCTAssertEqual(s.days[5].day.start, day(1))
        XCTAssertEqual(s.days[5].histogram.totalSeconds, .minutes(3), accuracy: 1E-9)
        XCTAssertEqual(s.days[5].histogram.readingCount, 0)
        XCTAssertEqual(s.summary.calendarDays, 7)
        XCTAssertEqual(s.summary.daysWithData, 1)
    }

    // MARK: - AGP

    func testAGPPoolingWrapsAtMidnight() {
        // data only in 00:00-00:15
        let w = weighed(points(from: Self.day0, every: .minutes(5), count: 3))
        let bins = Engine.agp(w, calendar: calendar, clippedTo: DateInterval(start: Self.day0, end: day(1)))
        XCTAssertEqual(bins.count, 96)
        XCTAssertNotNil(bins[95])
        XCTAssertNotNil(bins[0])
        XCTAssertNotNil(bins[1])
        XCTAssertNil(bins[2])
        XCTAssertNil(bins[94])
        XCTAssertEqual(bins[1]?.startMinute, 15)
        XCTAssertEqual(bins[0]?.seconds ?? 0, 900, accuracy: 1E-9)
        XCTAssertNotNil(Engine.agpMidnightEdge(bins))
    }

    func testAGPEdgePointNeedsBothEndBins() {
        // 00:15-00:30: bin 0 has data (pooled), bin 95 doesn't
        let early = Engine.agp(
            weighed(points(from: Self.day0.addingTimeInterval(.minutes(15)), every: .minutes(5), count: 3)),
            calendar: calendar,
            clippedTo: DateInterval(start: Self.day0, end: day(1))
        )
        XCTAssertNotNil(early[0])
        XCTAssertNil(early[95])
        XCTAssertNil(Engine.agpMidnightEdge(early))

        // 06:00
        let morning = Engine.agp(
            weighed(points(from: Self.day0.addingTimeInterval(.hours(6)), every: .minutes(5), count: 3)),
            calendar: calendar,
            clippedTo: DateInterval(start: Self.day0, end: day(1))
        )
        XCTAssertNil(morning[0])
        XCTAssertNil(morning[95])
        XCTAssertNil(Engine.agpMidnightEdge(morning))
    }

    func testAGPPercentilesWithEqualWeights() {
        // 100, 110, ... 190, 5 minutes each, all in 06:00-06:15 (bin 24): Hazen positions 0.05, 0.15, ... 0.95
        let start = Self.day0.addingTimeInterval(.hours(6))
        let w = (0 ..< 10).map {
            WeightedPoint(time: start.addingTimeInterval(Double($0) * 60), mgdl: Int16(100 + 10 * $0), span: 300)
        }
        let bins = Engine.agp(w, calendar: calendar, clippedTo: DateInterval(start: Self.day0, end: day(1)), poolNeighbours: 0)
        guard let bin = bins[24] else { return XCTFail("bin 24") }
        XCTAssertEqual(bin.startMinute, 360)
        XCTAssertEqual(bin.p5, 100, accuracy: 1E-9)
        XCTAssertEqual(bin.p25, 120, accuracy: 1E-9)
        XCTAssertEqual(bin.p50, 145, accuracy: 1E-9)
        XCTAssertEqual(bin.p75, 170, accuracy: 1E-9)
        XCTAssertEqual(bin.p95, 190, accuracy: 1E-9)
    }

    func testAGPOneMinuteDayDoesNotOutweighFiveMinuteDay() {
        // 06:00-06:15 on two days: 100 every 5 minutes, then 200 every minute; 15 minutes each
        let fiveMinute = points(from: Self.day0.addingTimeInterval(.hours(6)), every: .minutes(5), count: 3) { _ in 100 }
        let oneMinute = points(from: day(1).addingTimeInterval(.hours(6)), every: .minutes(1), count: 15) { _ in 200 }
        let bins = Engine.agp(
            weighed(fiveMinute + oneMinute),
            calendar: calendar,
            clippedTo: DateInterval(start: Self.day0, end: day(2))
        )
        guard let bin = bins[24] else { return XCTFail("bin 24") }
        XCTAssertEqual(bin.seconds, 1800, accuracy: 1E-9)
        XCTAssertEqual(bin.p50, 150, accuracy: 1E-9) // counting readings would give 200
        XCTAssertEqual(bin.p5, 100, accuracy: 1E-9)
        XCTAssertEqual(bin.p95, 200, accuracy: 1E-9)
    }

    func testQuantilesMergeEqualValues() {
        // 100 for 900 s, 200 for 300 s: one position per value, 100 at (900 - 450) / 1200 = 0.375, 200 at
        // (1200 - 150) / 1200 = 0.875 (per reading, the three 100s would sit at 0.125 / 0.375 / 0.625: median 100)
        let threeReadings = histogram([(100, 300), (100, 300), (100, 300), (200, 300)])
        let oneReading = histogram([(100, 900), (200, 300)])
        for h in [threeReadings, oneReading] {
            XCTAssertEqual(h.quantile(0.5) ?? 0, 125, accuracy: 1E-9)
            XCTAssertEqual(h.quantile(0.375) ?? 0, 100, accuracy: 1E-9)
            XCTAssertEqual(h.quantile(0.75) ?? 0, 175, accuracy: 1E-9)
            XCTAssertEqual(h.quantile(0.875) ?? 0, 200, accuracy: 1E-9)
            // clamped at the ends
            XCTAssertEqual(h.quantile(0.05) ?? 0, 100, accuracy: 1E-9)
            XCTAssertEqual(h.quantile(0.95) ?? 0, 200, accuracy: 1E-9)
        }
        XCTAssertEqual(threeReadings.readingCount, 4)
    }

    func testAGPAndHourOfDayLeaveOutTheLookback() {
        // 23:00 the day before ... 00:55, every 5 minutes; the window is the day
        let w = weighed(points(from: Self.day0.addingTimeInterval(-TimeInterval.hours(1)), every: .minutes(5), count: 24))
        let window = DateInterval(start: Self.day0, end: day(1))

        let hours = Engine.hourOfDay(w, calendar: calendar, clippedTo: window)
        XCTAssertEqual(hours[23].histogram.totalSeconds, 0)
        XCTAssertEqual(hours[0].histogram.totalSeconds, .hours(1), accuracy: 1E-9)
        XCTAssertEqual(hours[0].histogram.readingCount, 12)

        let bins = Engine.agp(w, calendar: calendar, clippedTo: window)
        XCTAssertNil(bins[92])
        XCTAssertNil(bins[93])
        XCTAssertNil(bins[94])
        XCTAssertNotNil(bins[95]) // pooled with bin 0
        XCTAssertEqual(bins[0]?.seconds ?? 0, 1800, accuracy: 1E-9) // bins 95 (empty), 0 and 1
    }

    func testAGPChangesWithTheTimeAloneOnlyAtMidnight() {
        // every 5 minutes from 6 days before today up to 10:00 today; current up to 10:07:30, stalled after
        let today = day(0)
        let series = points(from: day(-6), every: .minutes(5), count: 6 * 288 + 121) { Int16(80 + ($0 * 7) % 150) }
        let w = weighed(series)
        func profile(at now: Date) -> [AGPBin?] {
            let end = Engine.effectiveEnd(w, now: now, calendar: calendar)
            let window = Engine.window(for: .days7, now: now, end: end, calendar: calendar)
            return Engine.agp(w, calendar: calendar, clippedTo: window)
        }
        let current = profile(at: today.addingTimeInterval(TimeInterval.hours(10) + 10))
        XCTAssertTrue(current.allSatisfy { $0 != nil })
        // still current, stalled, stalled late in the day: E never clips a span, the window's start stays
        for hours: Double in [10.1, 12, 23.99] {
            XCTAssertEqual(profile(at: today.addingTimeInterval(.hours(hours))), current, "\(hours)")
        }
        // midnight: the first day leaves the window
        XCTAssertNotEqual(profile(at: day(1).addingTimeInterval(60)), current)
    }

    // MARK: - AGP over a list of days

    /// The days of a window, listed, give the window's AGP: across a 25-hour day, with readings across each midnight
    /// (at :02, :07, …) and a lookback reading before the first day.
    func testAGPOfAWindowsDaysIsTheWindowsAGP() {
        let window = DateInterval(start: day(3), end: day(8))
        let start = day(3).addingTimeInterval(-.hours(1) + .minutes(2))
        let w = weighed(points(from: start, every: .minutes(5), count: 6 * 300) { Int16(80 + ($0 * 7) % 150) })
        let days = StatsClock.calendarDays(in: window, calendar: calendar)
        XCTAssertEqual(days.count, 5)
        XCTAssertTrue(days.contains { $0.duration == .hours(25) })
        XCTAssertEqual(Engine.agp(w, calendar: calendar, days: days), Engine.agp(w, calendar: calendar, clippedTo: window))
        XCTAssertEqual(
            Engine.agp(w, calendar: calendar, days: days, poolNeighbours: 0),
            Engine.agp(w, calendar: calendar, clippedTo: window, poolNeighbours: 0)
        )
        XCTAssertEqual(Engine.agp(w, calendar: calendar, days: []), Array(repeating: nil, count: 96))
    }

    /// A reading across midnight gives each listed day its part, at the reading's own clock time; a day that isn't
    /// listed gives nothing.
    func testAGPOfAListOfDaysSplitsAReadingAcrossMidnight() {
        let day0 = DateInterval(start: day(0), end: day(1))
        let day1 = DateInterval(start: day(1), end: day(2))
        let day2 = DateInterval(start: day(2), end: day(3))
        let w = [
            // 23:55 to 00:05
            WeightedPoint(time: day(1).addingTimeInterval(-.minutes(5)), mgdl: 150, span: .minutes(10)),
            WeightedPoint(time: day(1).addingTimeInterval(.minutes(5)), mgdl: 100, span: .minutes(5)),
            WeightedPoint(time: day(2).addingTimeInterval(.hours(6)), mgdl: 200, span: .minutes(5))
        ]
        let first = Engine.agp(w, calendar: calendar, days: [day0], poolNeighbours: 0)
        XCTAssertEqual(first[95]?.seconds ?? 0, 300, accuracy: 1E-9)
        XCTAssertNil(first[0])

        let second = Engine.agp(w, calendar: calendar, days: [day1], poolNeighbours: 0)
        XCTAssertEqual(second[95]?.seconds ?? 0, 300, accuracy: 1E-9) // the 23:55 reading's minutes after midnight
        XCTAssertEqual(second[95]?.p50 ?? 0, 150, accuracy: 1E-9)
        XCTAssertEqual(second[0]?.seconds ?? 0, 300, accuracy: 1E-9)
        XCTAssertNil(second[24])

        // day 1 left out: its readings and its part of the 23:55 one aren't counted
        let apart = Engine.agp(w, calendar: calendar, days: [day0, day2], poolNeighbours: 0)
        XCTAssertEqual(apart[95]?.seconds ?? 0, 300, accuracy: 1E-9)
        XCTAssertNil(apart[0])
        XCTAssertEqual(apart[24]?.p50 ?? 0, 200, accuracy: 1E-9)
        XCTAssertEqual(
            Engine.agp(w, calendar: calendar, days: [day0, day1, day2]),
            Engine.agp(w, calendar: calendar, clippedTo: DateInterval(start: day(0), end: day(3)))
        )
    }

    /// A 25-hour day by its clock: the repeated hour 02:00–03:00 is in its bins twice, as in `agp` of the day.
    func testAGPOfAListOfDaysOnA25HourDay() {
        let day = DateInterval(start: Self.fallBack, end: StatsClock.endOfDay(Self.fallBack, calendar: calendar))
        XCTAssertEqual(day.duration, .hours(25))
        let w = (0 ..< 300).map { WeightedPoint(time: day.start.addingTimeInterval(Double($0) * 300), mgdl: 120, span: 300) }
        let bins = Engine.agp(w, calendar: calendar, days: [day], poolNeighbours: 0)
        XCTAssertEqual(bins[7]?.seconds ?? 0, 900, accuracy: 1E-9)
        for bin in 8 ... 11 {
            XCTAssertEqual(bins[bin]?.seconds ?? 0, 1800, accuracy: 1E-9, "\(bin)")
        }
        XCTAssertEqual(bins[12]?.seconds ?? 0, 900, accuracy: 1E-9)
        XCTAssertEqual(bins, Engine.agp(w, calendar: calendar, clippedTo: day, poolNeighbours: 0))
    }

    // MARK: - Glycemia Risk Index

    /// 1 % very low, 3 % low, 20 % high, 5 % very high: hypo 3.4, hyper 15, GRI 3.0 × 3.4 + 1.6 × 15 = 34.2, zone B.
    func testGRIOfAFixture() {
        let h = histogram([(50, 100), (60, 300), (120, 7100), (200, 2000), (300, 500)])
        guard let gri = Engine.gri(h, bands: bands) else { return XCTFail("gri") }
        XCTAssertEqual(gri.veryLow, 1, accuracy: 1E-9)
        XCTAssertEqual(gri.low, 3, accuracy: 1E-9)
        XCTAssertEqual(gri.high, 20, accuracy: 1E-9)
        XCTAssertEqual(gri.veryHigh, 5, accuracy: 1E-9)
        XCTAssertEqual(gri.hypo, 3.4, accuracy: 1E-9)
        XCTAssertEqual(gri.hyper, 15, accuracy: 1E-9)
        XCTAssertEqual(gri.value, 34.2, accuracy: 1E-9)
        XCTAssertEqual(gri.zone, .b)
        XCTAssertNil(Engine.gri(GlucoseHistogram(), bands: bands))
    }

    /// The standard edges, whatever the low/high settings: 53 very low, 54 and 69 low, 70 and 180 in range, 181 and 250
    /// high, 251 very high; for mmol users 181 is in range (`tirRange` 70...181). Each value 5 % of the time.
    func testGRIUsesTheStandardRangesNotTheSettings() {
        let h = histogram([
            (53, 100), (54, 100), (69, 100), (70, 100), (180, 100), (181, 100), (250, 100), (251, 100), (120, 1200)
        ])
        let settings = [
            bands,
            StatsBands(low: 80, high: 160, units: .mgdL),
            StatsBands(low: 54, high: 250, units: .mgdL)
        ]
        for bands in settings {
            guard let gri = Engine.gri(h, bands: bands) else { return XCTFail("gri") }
            XCTAssertEqual(gri.veryLow, 5, accuracy: 1E-9)
            XCTAssertEqual(gri.low, 10, accuracy: 1E-9)
            XCTAssertEqual(gri.high, 10, accuracy: 1E-9)
            XCTAssertEqual(gri.veryHigh, 5, accuracy: 1E-9)
            XCTAssertEqual(gri.value, 3.0 * (5 + 0.8 * 10) + 1.6 * (5 + 0.5 * 10), accuracy: 1E-9)
        }

        let mmol = StatsBands(low: Decimal(string: "4.4")!.asMgdL, high: Decimal(string: "8.0")!.asMgdL, units: .mmolL)
        XCTAssertEqual(mmol.tirRange, 70 ... 181)
        guard let gri = Engine.gri(h, bands: mmol) else { return XCTFail("gri") }
        XCTAssertEqual(gri.low, 10, accuracy: 1E-9)
        XCTAssertEqual(gri.high, 5, accuracy: 1E-9) // 250 only
        XCTAssertEqual(gri.veryHigh, 5, accuracy: 1E-9)
    }

    func testGRIIsCappedAndItsZoneEdges() {
        guard let worst = Engine.gri(histogram([(40, 3600)]), bands: bands) else { return XCTFail("gri") }
        XCTAssertEqual(worst.hypo, 100, accuracy: 1E-9)
        XCTAssertEqual(worst.value, 100)
        XCTAssertEqual(worst.zone, .e)
        XCTAssertEqual(Engine.gri(histogram([(120, 3600)]), bands: bands)?.value, 0)

        // on the whole-number GRI: A 0–20, B 21–40, C 41–60, D 61–80, E 81–100
        let zones: [(Double, GlycemiaRiskIndex.Zone)] = [
            (0, .a), (20, .a), (20.4, .a), (20.5, .b), (21, .b), (40, .b), (40.5, .c), (60, .c), (60.5, .d), (80, .d),
            (80.5, .e), (81, .e), (100, .e)
        ]
        for (value, zone) in zones {
            XCTAssertEqual(Engine.griZone(value), zone, "\(value)")
        }
    }

    // MARK: - AGP chart

    private func agpBin(_ index: Int, median: Double, p5: Double? = nil, p95: Double? = nil) -> AGPBin {
        AGPBin(
            startMinute: index * 15,
            p5: p5 ?? median - 40,
            p25: median - 20,
            p50: median,
            p75: median + 20,
            p95: p95 ?? median + 40,
            seconds: 2700
        )
    }

    func testAGPPlotPointsAndTheMidnightEdge() {
        // data in bins 0-2 and 94-95, a gap between: two segments, joined across midnight by the edge
        var bins = [AGPBin?](repeating: nil, count: 96)
        for index in [0, 1, 2, 94, 95] {
            bins[index] = agpBin(index, median: 100 + Double(index))
        }
        let points = Engine.agpPlotPoints(bins, axis: 40 ... 300)
        XCTAssertEqual(points.map(\.minute), [0, 7, 22, 37, 1417, 1432, 1440])
        XCTAssertEqual(points.map(\.segment), [0, 0, 0, 0, 1, 1, 1])
        // the edge, at both ends: the average of bins 95 and 0
        XCTAssertEqual(points[0].p50, (195 + 100) / 2, accuracy: 1E-9)
        XCTAssertEqual(points[0].p5, (155 + 60) / 2, accuracy: 1E-9)
        XCTAssertEqual(points[6].p50, points[0].p50, accuracy: 1E-9)
        XCTAssertEqual(points[1].p25, 80, accuracy: 1E-9)
        XCTAssertEqual(points[1].p75, 120, accuracy: 1E-9)

        // without bin 95 no edge; a gap at the start makes no empty segment, every gap ends one
        var gappy = [AGPBin?](repeating: nil, count: 96)
        for index in [10, 12, 13] {
            gappy[index] = agpBin(index, median: 120)
        }
        let gapped = Engine.agpPlotPoints(gappy, axis: 40 ... 300)
        XCTAssertEqual(gapped.map(\.minute), [157, 187, 202])
        XCTAssertEqual(gapped.map(\.segment), [0, 1, 1])

        XCTAssertEqual(Engine.agpPlotPoints([], axis: 40 ... 300), [])
        XCTAssertEqual(Engine.agpPlotPoints([AGPBin?](repeating: nil, count: 96), axis: 40 ... 300), [])
    }

    func testAGPPlotPointsAreKeptInsideTheAxis() {
        var bins = [AGPBin?](repeating: nil, count: 96)
        bins[40] = agpBin(40, median: 120, p5: 20, p95: 450)
        let axis = Engine.agpAxis(bins)
        XCTAssertEqual(axis, 40 ... 400)
        let point = Engine.agpPlotPoints(bins, axis: axis)[0]
        XCTAssertEqual(point.p5, 40)
        XCTAssertEqual(point.p50, 120)
        XCTAssertEqual(point.p95, 400)

        // the axis: raised by a p95 above 300 only
        bins[40] = agpBin(40, median: 120, p95: 300)
        XCTAssertEqual(Engine.agpAxis(bins), 40 ... 300)
        bins[41] = agpBin(41, median: 120, p95: 300.5)
        XCTAssertEqual(Engine.agpAxis(bins), 40 ... 400)
        XCTAssertEqual(Engine.agpAxis([AGPBin?](repeating: nil, count: 96)), 40 ... 300)
    }

    func testAGPBinSelection() {
        // snapping
        XCTAssertEqual(Engine.agpBin(atMinute: 0, binCount: 96), 0)
        XCTAssertEqual(Engine.agpBin(atMinute: 14, binCount: 96), 0)
        XCTAssertEqual(Engine.agpBin(atMinute: 15, binCount: 96), 1)
        XCTAssertEqual(Engine.agpBin(atMinute: 1439, binCount: 96), 95)
        // outside the day: kept inside it
        XCTAssertEqual(Engine.agpBin(atMinute: 1440, binCount: 96), 95)
        XCTAssertEqual(Engine.agpBin(atMinute: -5, binCount: 96), 0)

        // drawn at its middle, which is in it
        XCTAssertEqual(Engine.agpMiddleMinute(ofBin: 0, binCount: 96), 7)
        XCTAssertEqual(Engine.agpMiddleMinute(ofBin: 95, binCount: 96), 1432)
        for bin in 0 ..< 96 {
            XCTAssertEqual(Engine.agpBin(atMinute: Engine.agpMiddleMinute(ofBin: bin, binCount: 96), binCount: 96), bin)
        }

        // the stepper wraps around midnight
        XCTAssertEqual(Engine.agpStep(40, by: 2, binCount: 96), 42)
        XCTAssertEqual(Engine.agpStep(95, by: 2, binCount: 96), 1)
        XCTAssertEqual(Engine.agpStep(0, by: -2, binCount: 96), 94)
        XCTAssertEqual(Engine.agpStep(1, by: -1, binCount: 96), 0)

        // the current clock time's bin, by the local clock
        func bin(_ date: Date) -> Int { Engine.agpBin(of: date, calendar: calendar, binCount: 96) }
        XCTAssertEqual(bin(Self.day0.addingTimeInterval(TimeInterval.hours(8) + .minutes(35))), 34)
        XCTAssertEqual(bin(Self.day0.addingTimeInterval(TimeInterval.hours(24) - 1)), 95)
        // the repeated hour of the 25-hour day is 02:30 twice; the 23-hour day's 02:00 is 03:00
        XCTAssertEqual(bin(Self.fallBack.addingTimeInterval(.hours(2.5))), 10)
        XCTAssertEqual(bin(Self.fallBack.addingTimeInterval(.hours(3.5))), 10)
        XCTAssertEqual(bin(Self.springForward.addingTimeInterval(.hours(2))), 12)
    }

    func testAGPSegmentsAreNeverOnePoint() {
        // readings in one 15-minute bin only, for every bin of the day: pooled, its segment has three points or more,
        // and the part a split at midnight leaves on the other side keeps the edge point
        let window = DateInterval(start: Self.day0, end: day(1))
        for bin in 0 ..< 96 {
            let start = Self.day0.addingTimeInterval(.minutes(bin * 15))
            let bins = Engine.agp(
                weighed(points(from: start, every: .minutes(5), count: 3)),
                calendar: calendar,
                clippedTo: window
            )
            let plotted = Engine.agpPlotPoints(bins, axis: 40 ... 300)
            let middle = Engine.agpMiddleMinute(ofBin: bin, binCount: 96)
            guard let own = plotted.first(where: { $0.minute == middle })?.segment else { return XCTFail("bin \(bin)") }
            XCTAssertGreaterThanOrEqual(plotted.filter { $0.segment == own }.count, 3, "bin \(bin)")
            for segment in Set(plotted.map(\.segment)) {
                XCTAssertGreaterThanOrEqual(plotted.filter { $0.segment == segment }.count, 2, "bin \(bin), segment \(segment)")
            }
        }
    }

    func testAGPReadoutTimesAreOneInterval() {
        // the day's last bin ends at the next day's 00:00, which the interval format would show with both dates
        // (of the 2001 reference day)
        for (start, end) in [(0, 15), (510, 525), (705, 720), (1425, 1440)] {
            let time = Stat.AGP.clockInterval(from: start, to: end)
            XCTAssertFalse(time.isEmpty)
            XCTAssertFalse(time.contains("2001"), time)
        }
    }

    func testAGPIsLimited() {
        // full coverage
        func full(days: Int, withData: Int) -> GlucoseSummary {
            summary(of: histogram([(120, 3600)]), duration: 3600, calendarDays: days, daysWithData: withData)
        }
        XCTAssertFalse(full(days: 14, withData: 14).isLimited)
        // fewer than 14 days with data: a shorter period, or days without readings
        XCTAssertTrue(Engine.agpIsLimited(full(days: 7, withData: 7)))
        XCTAssertTrue(Engine.agpIsLimited(full(days: 13, withData: 13)))
        XCTAssertTrue(Engine.agpIsLimited(full(days: 14, withData: 13)))
        XCTAssertTrue(Engine.agpIsLimited(full(days: 90, withData: 13)))
        XCTAssertFalse(Engine.agpIsLimited(full(days: 14, withData: 14)))
        XCTAssertFalse(Engine.agpIsLimited(full(days: 90, withData: 14)))

        // 69% coverage
        let sparse = summary(of: histogram([(120, 3600)]), duration: 3600 / 0.69, calendarDays: 90, daysWithData: 90)
        XCTAssertTrue(sparse.isLimited)
        XCTAssertTrue(Engine.agpIsLimited(sparse))
    }

    func testAGPResultIsEmptyOnlyWithoutData() {
        let none = summary(.days7, [], now: day(1))
        let noBins = [AGPBin?](repeating: nil, count: 96)
        XCTAssertTrue(Stat.AGPResult(bins: noBins, points: [], axis: 40 ... 300, summary: none).isEmpty)

        var bins = noBins
        bins[3] = agpBin(3, median: 120)
        XCTAssertFalse(Stat.AGPResult(bins: bins, points: [], axis: 40 ... 300, summary: none).isEmpty)

        let some = summary(.days7, points(from: day(0), every: .minutes(5), count: 3), now: day(0).addingTimeInterval(600))
        XCTAssertFalse(some.isEmpty)
        XCTAssertFalse(Stat.AGPResult(bins: noBins, points: [], axis: 40 ... 300, summary: some).isEmpty)
    }

    @MainActor func testAGPKeyNumbersAreTheOverviews() {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        freeAPSSettings.low = 70
        freeAPSSettings.high = 145
        let settings = Stat.StatsSettings(freeAPSSettings)
        let now = day(13).addingTimeInterval(.hours(12))

        func makeAGP(_ period: StatsPeriod, _ series: [GlucosePoint]) -> (agp: Stat.AGP, summary: GlucoseSummary) {
            let c = compute(period, series, now: now, bands: settings.bands)
            let bins = Engine.agp(c.w, calendar: calendar, clippedTo: c.window)
            let axis = Engine.agpAxis(bins)
            let result = Stat.AGPResult(
                bins: bins,
                points: Engine.agpPlotPoints(bins, axis: axis),
                axis: axis,
                summary: c.summary
            )
            return (Stat.AGP(result, period: period, settings: settings), c.summary)
        }

        let fewDays = "A glucose profile is meant for 14 or more days with readings; this period has fewer."
        let lowCoverage = "CGM readings cover less than 70% of this period, so these numbers may not represent it."

        // every 5 minutes up to about now (the 25-hour day takes an hour off the end): full coverage
        let full = points(from: day(0), every: .minutes(5), count: 13 * 288 + 144) { $0 % 4 == 0 ? 200 : 120 }
        for period in [StatsPeriod.days7, .days14] {
            let (agp, periodSummary) = makeAGP(period, full)
            XCTAssertFalse(periodSummary.isLimited)
            let overview = Stat.Overview(periodSummary, period: period, settings: settings)
            let limited = period == .days7
            XCTAssertEqual(agp.dateRange, overview.dateRange)
            XCTAssertEqual(agp.tiles.map(\.value), [
                StatsFormatting.percent(.inRange, of: periodSummary),
                overview.tir,
                overview.titr,
                overview.mean + " / " + overview.cv,
                overview.gmi,
                overview.eA1c
            ])
            XCTAssertEqual(agp.tiles.map(\.title)[1 ... 2], [overview.tirTitle, overview.titrTitle])
            XCTAssertEqual(agp.tiles[4].unit, overview.a1cUnit)
            // 7 days: fewer than 14 days with data only, the coverage is full; the A1c estimates marked as the
            // Overview marks them, nothing else
            XCTAssertEqual(agp.profileNote, limited ? fewDays : nil)
            XCTAssertNil(agp.coverageNote)
            XCTAssertEqual(agp.tiles.map(\.limitedNote), [nil, nil, nil, nil, overview.a1cNote, overview.a1cNote])
            XCTAssertEqual(overview.a1cNote != nil, limited)
            XCTAssertEqual(agp.daysWithData, "Days with data " + overview.daysWithData)
            XCTAssertEqual(agp.tiles[0].note, overview.inRangeRange)

            // every bin has data, read out as the percentiles
            XCTAssertEqual(agp.plot.readouts.count, 96)
            XCTAssertTrue(agp.plot.readouts.allSatisfy { $0.values?.count == 5 && $0.plottedMedian != nil })
        }

        // 14 days without one of them: 13 days with data, the coverage isn't limited
        let missingDay = full.filter { $0.time < day(6) || $0.time >= day(7) }
        let (gap, gapSummary) = makeAGP(.days14, missingDay)
        XCTAssertFalse(gapSummary.isLimited)
        XCTAssertEqual(gapSummary.daysWithData, 13)
        XCTAssertEqual(gap.profileNote, fewDays)
        XCTAssertNil(gap.coverageNote)
        // the count the note leaves out, in the header
        XCTAssertEqual(gap.daysWithData, "Days with data " + StatsFormatting.days(13, of: 14))
        XCTAssertNotNil(gap.tiles[4].limitedNote)

        // 14 days, readings only from day 5: 9 days with data, and the coverage, with the Overview's text
        let late = points(from: day(5), every: .minutes(5), count: 8 * 288 + 144)
        let (sparse, sparseSummary) = makeAGP(.days14, late)
        XCTAssertTrue(sparseSummary.isLimited)
        XCTAssertEqual(sparseSummary.daysWithData, 9)
        XCTAssertEqual(sparse.profileNote, fewDays + " " + lowCoverage)
        XCTAssertEqual(sparse.coverageNote, lowCoverage)
        XCTAssertEqual(sparse.tiles[0].limitedNote, lowCoverage)
        XCTAssertNotNil(sparse.tiles[4].limitedNote)

        // 7 days with 69% coverage: both, the days with data first
        let short = points(from: day(9), every: .minutes(5), count: 4 * 288 + 144)
        let (both, bothSummary) = makeAGP(.days7, short)
        XCTAssertEqual(bothSummary.coveragePercent, 69)
        XCTAssertEqual(both.profileNote, fewDays + " " + lowCoverage)
        // a readout has the percentiles exactly when it has a median to draw
        XCTAssertTrue(both.plot.readouts.allSatisfy { ($0.values == nil) == ($0.plottedMedian == nil) })
    }

    // MARK: - Hour of day and weeks

    func testHourOfDayAddsUpToTheCoveredTime() {
        var series = points(from: Self.day0.addingTimeInterval(.minutes(2)), every: .minutes(5), count: 3 * 288) {
            Int16(60 + ($0 * 13) % 200)
        }
        series.removeSubrange(400 ..< 460)
        let s = compute(.days7, series, now: day(2).addingTimeInterval(TimeInterval.hours(23) + .minutes(59)))
        let hours = Engine.hourOfDay(s.w, calendar: calendar, clippedTo: s.window)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours.map(\.hour), Array(0 ..< 24))
        XCTAssertEqual(hours.reduce(0) { $0 + $1.histogram.totalSeconds }, s.summary.histogram.totalSeconds, accuracy: 1E-6)
    }

    func testPeakHours() {
        func bucket(_ hour: Int, _ entries: [(mgdl: Int16, seconds: Double)]) -> HourBucket {
            HourBucket(hour: hour, histogram: histogram(entries))
        }
        let buckets = [
            bucket(5, [(60, 1800), (100, 1800)]),
            bucket(3, [(60, 1800), (100, 1800)]),
            bucket(4, [(100, 3600)]),
            bucket(6, [])
        ]
        let peaks = Engine.peakHours(buckets, bands: bands)
        // below ties between 3 and 5 -> 3; in range peaks at 4; nothing above -> no row
        XCTAssertEqual(peaks.map(\.group), [.below, .inRange])
        XCTAssertEqual(peaks.first { $0.group == .below }?.hour, 3)
        XCTAssertEqual(peaks.first { $0.group == .below }?.share ?? 0, 0.5, accuracy: 1E-12)
        XCTAssertEqual(peaks.first { $0.group == .inRange }?.hour, 4)
    }

    /// The peak is the hour whose percent shown is the highest (the sum of its rows' largest-remainder percents), not the
    /// one with the highest share: 2.5 + 2.5 % shown as 3 + 3 = 6 % beats 5.1 % shown as 5 %.
    func testPeakHoursRankByThePercentShown() {
        func bucket(_ hour: Int, _ entries: [(mgdl: Int16, seconds: Double)]) -> HourBucket {
            HourBucket(hour: hour, histogram: histogram(entries))
        }
        // very low 2.5, low 2.5, in range 47.5, high 47.5 % -> 3 / 3 / 47 / 47 (ties to the earlier band)
        let split = bucket(9, [(50, 90), (60, 90), (100, 1710), (200, 1710)])
        // low 5.1, in range 94.9 % -> 0 / 5 / 95
        let single = bucket(4, [(60, 183.6), (100, 3416.4)])
        XCTAssertEqual(Engine.hourOfDayHour(split, bands: bands).bandShares.percents, [3, 3, 47, 47, 0])
        XCTAssertEqual(Engine.hourOfDayHour(single, bands: bands).bandShares.percents, [0, 5, 95, 0, 0])
        let peaks = Engine.peakHours([single, split], bands: bands)
        let below = peaks.first { $0.group == .below }
        XCTAssertEqual(below?.hour, 9)
        XCTAssertEqual(below?.share ?? 0, 0.05, accuracy: 1E-12)
        XCTAssertEqual(below.map { Engine.peakPercent($0, of: Engine.hourOfDayHour(split, bands: bands)).percent }, 6)
        // the same with a split that doesn't hinge on remainder ties: 2.6 + 2.6 % (3 + 3) over 5.3 % (5)
        let robust = bucket(9, [(50, 93.6), (60, 93.6), (100, 1706.4), (200, 1706.4)])
        let higherShare = bucket(4, [(60, 190.8), (100, 3409.2)])
        XCTAssertEqual(Engine.peakHours([higherShare, robust], bands: bands).first { $0.group == .below }?.hour, 9)

        // the same percent shown: the higher share
        let five = bucket(2, [(60, 180), (100, 3420)])
        let fiveAndABit = bucket(7, [(60, 190), (100, 3410)])
        XCTAssertEqual(Engine.hourOfDayHour(five, bands: bands).percent(.low), 5)
        XCTAssertEqual(Engine.hourOfDayHour(fiveAndABit, bands: bands).percent(.low), 5)
        XCTAssertEqual(Engine.peakHours([five, fiveAndABit], bands: bands).first { $0.group == .below }?.hour, 7)
        // the same percent and share: the earliest hour, in any order given
        XCTAssertEqual(
            Engine.peakHours([fiveAndABit, bucket(3, [(60, 190), (100, 3410)])], bands: bands)
                .first { $0.group == .below }?.hour,
            3
        )
    }

    /// Summation noise doesn't decide a tie: an hour all in range whose share comes out a hair above 1 (its band's time
    /// and its total summed in different orders) doesn't beat an earlier hour at exactly 1.
    func testPeakHoursIgnoreSummationNoise() {
        // added 0.3, 0.2, 0.1: the total is 0.6, the in-range time (summed by value) 0.6000000000000001
        let noisy = HourBucket(hour: 7, histogram: histogram([(120, 0.3), (110, 0.2), (100, 0.1)]))
        let exact = HourBucket(hour: 3, histogram: histogram([(100, 3600)]))
        let noisyShare = noisy.histogram.seconds(in: bands.low ... bands.high) / noisy.histogram.totalSeconds
        XCTAssertNotEqual(noisyShare, 1)
        XCTAssertEqual(noisyShare, 1, accuracy: Engine.peakShareTolerance)
        for buckets in [[noisy, exact], [exact, noisy]] {
            let inRange = Engine.peakHours(buckets, bands: bands).first { $0.group == .inRange }
            XCTAssertEqual(inRange?.hour, 3)
        }
    }

    /// An hour's column and its percents: the nonzero visible bands stacked from very low up, largest remainder with
    /// "<1%"; an hour without data has neither.
    func testHourOfDayHour() {
        // 1.3 / 3.3 / 71.4 / 18.0 / 6.0 % of an hour
        let bucket = HourBucket(hour: 8, histogram: histogram([
            (50, 0.013 * 3600), (60, 0.033 * 3600), (100, 0.714 * 3600), (200, 0.18 * 3600), (300, 0.06 * 3600)
        ]))
        let hour = Engine.hourOfDayHour(bucket, bands: bands)
        XCTAssertEqual(hour.hour, 8)
        XCTAssertTrue(hour.hasData)
        XCTAssertEqual(hour.hoursOfData, 1, accuracy: 1E-9)
        XCTAssertEqual(hour.bandShares.percents, [1, 3, 72, 18, 6])
        XCTAssertEqual(GlucoseBand.allCases.map { hour.isBelowOnePercent($0) }, [false, false, false, false, false])
        XCTAssertEqual(hour.segments.map(\.band), GlucoseBand.allCases)
        XCTAssertEqual(hour.segments.first?.lower ?? -1, 0, accuracy: 1E-12)
        XCTAssertEqual(hour.segments[2].lower, 0.046, accuracy: 1E-9)
        XCTAssertEqual(hour.segments[2].upper, 0.76, accuracy: 1E-9)
        XCTAssertEqual(hour.segments.last?.upper ?? 0, 1, accuracy: 1E-9)
        for (lower, upper) in zip(hour.segments.dropLast(), hour.segments.dropFirst()) {
            XCTAssertEqual(lower.upper, upper.lower, accuracy: 1E-12)
        }

        // a nonzero band rounded to 0 is "<1%"; the zero bands have no part of the column
        let sliver = Engine.hourOfDayHour(HourBucket(hour: 3, histogram: histogram([(50, 10), (100, 3590)])), bands: bands)
        XCTAssertEqual(sliver.bandShares.percents, [0, 0, 100, 0, 0])
        XCTAssertEqual(GlucoseBand.allCases.map { sliver.isBelowOnePercent($0) }, [true, false, false, false, false])
        XCTAssertEqual(sliver.segments.map(\.band), [.veryLow, .inRange])

        // without data
        let none = Engine.hourOfDayHour(HourBucket(hour: 12, histogram: GlucoseHistogram()), bands: bands)
        XCTAssertFalse(none.hasData)
        XCTAssertEqual(none.hoursOfData, 0)
        XCTAssertEqual(none.segments, [])
        XCTAssertEqual(none.bandShares.percents, [0, 0, 0, 0, 0])
        XCTAssertEqual(GlucoseBand.allCases.map { none.isBelowOnePercent($0) }, [false, false, false, false, false])

        // a hidden band (low at 54) has no part: 60 is in range then
        let noLowBand = StatsBands(low: 40, high: 145, units: .mgdL)
        let hidden = Engine.hourOfDayHour(HourBucket(hour: 1, histogram: histogram([(50, 600), (60, 3000)])), bands: noLowBand)
        XCTAssertEqual(hidden.segments.map(\.band), [.veryLow, .inRange])
        XCTAssertEqual(hidden.percent(.low), 0)
    }

    /// "When it happens" shows the peak's share as the sum of its hour's band percents: the number the hour's rows add
    /// up to when it is selected, not the share rounded on its own.
    func testPeakPercentIsTheSelectedHoursRows() {
        let bucket = HourBucket(hour: 8, histogram: histogram([
            (50, 0.013 * 3600), (60, 0.033 * 3600), (100, 0.714 * 3600), (200, 0.18 * 3600), (300, 0.06 * 3600)
        ]))
        let hour = Engine.hourOfDayHour(bucket, bands: bands)
        let peaks = Engine.peakHours([bucket], bands: bands)
        func shown(_ group: PeakHour.Group) -> (percent: Int, belowOne: Bool)? {
            peaks.first { $0.group == group }.map { Engine.peakPercent($0, of: hour) }
        }
        XCTAssertEqual(peaks.first { $0.group == .below }?.share ?? 0, 0.046, accuracy: 1E-9)
        // 1 + 3 (4.6 rounded alone would be 5), 18 + 6, and the in-range row's 72 (71.4 rounded alone: 71)
        XCTAssertEqual(shown(.below)?.percent, 4)
        XCTAssertEqual(shown(.above)?.percent, 24)
        XCTAssertEqual(shown(.inRange)?.percent, 72)
        XCTAssertEqual(shown(.inRange)?.percent, hour.percent(.inRange))
        XCTAssertEqual(shown(.below)?.belowOne, false)

        // nonzero, but 0 in the rows: "<1%"
        let sliverBucket = HourBucket(hour: 3, histogram: histogram([(50, 10), (100, 3590)]))
        let sliver = Engine.hourOfDayHour(sliverBucket, bands: bands)
        let below = Engine.peakHours([sliverBucket], bands: bands).first { $0.group == .below }
        XCTAssertNotNil(below)
        XCTAssertEqual(below.map { Engine.peakPercent($0, of: sliver).percent }, 0)
        XCTAssertEqual(below.map { Engine.peakPercent($0, of: sliver).belowOne }, true)
    }

    /// The local clock hour of a moment (By hour opens at the current one) and the stepper around midnight.
    func testClockHourAndHourStep() {
        XCTAssertEqual(
            Engine.clockHour(of: Self.day0.addingTimeInterval(TimeInterval.hours(8) + .minutes(59)), calendar: calendar),
            8
        )
        XCTAssertEqual(Engine.clockHour(of: Self.day0.addingTimeInterval(TimeInterval.hours(24) - 1), calendar: calendar), 23)
        // the repeated hour of the 25-hour day is 02 twice; the 23-hour day's 02:00 is 03:00
        XCTAssertEqual(Engine.clockHour(of: Self.fallBack.addingTimeInterval(.hours(2.5)), calendar: calendar), 2)
        XCTAssertEqual(Engine.clockHour(of: Self.fallBack.addingTimeInterval(.hours(3.5)), calendar: calendar), 2)
        XCTAssertEqual(Engine.clockHour(of: Self.springForward.addingTimeInterval(.hours(2)), calendar: calendar), 3)

        XCTAssertEqual(Engine.hourStep(8, by: 1), 9)
        XCTAssertEqual(Engine.hourStep(23, by: 1), 0)
        XCTAssertEqual(Engine.hourStep(0, by: -1), 23)
    }

    /// By hour's numbers are the engine's for the period: every hour from `hourOfDay` over the period's window, adding up
    /// to the period summary's covered time; the peaks are `peakHours`'.
    func testHourOfDayResultIsTheEngines() {
        var series = points(from: Self.day0.addingTimeInterval(-TimeInterval.hours(1) + 40), every: .minutes(5), count: 4 * 288) {
            Int16(50 + ($0 * 17) % 260)
        }
        series.removeSubrange(500 ..< 540)
        let c = compute(.days7, series, now: series.last!.time.addingTimeInterval(60))
        let buckets = Engine.hourOfDay(c.w, calendar: calendar, clippedTo: c.window)
        let result = Stat.HourOfDayResult(buckets: buckets, summary: c.summary, bands: bands)

        XCTAssertEqual(result.hours, buckets.map { Engine.hourOfDayHour($0, bands: bands) })
        XCTAssertEqual(result.hours.map(\.hour), Array(0 ..< 24))
        XCTAssertEqual(result.peaks, Engine.peakHours(buckets, bands: bands))
        XCTAssertEqual(result.hours.reduce(0) { $0 + $1.seconds }, c.summary.histogram.totalSeconds, accuracy: 1E-6)
        XCTAssertEqual(result.summary, c.summary)
        XCTAssertFalse(result.isEmpty)
        // every hour's interval, on one day (the last one ends at the next 00:00)
        XCTAssertEqual(result.labels.count, 24)
        XCTAssertEqual(result.labels[23], Stat.AGP.clockInterval(from: 23 * 60, to: 24 * 60))
        XCTAssertTrue(result.labels.allSatisfy { !$0.isEmpty && !$0.contains("2001") })
        // a column per hour with data adds up to 100%
        for hour in result.hours where hour.hasData {
            XCTAssertEqual(hour.segments.last?.upper ?? 0, 1, accuracy: 1E-9, "\(hour.hour)")
            XCTAssertEqual(hour.bandShares.percents.reduce(0, +), 100, "\(hour.hour)")
        }

        // nothing in the period
        let none = compute(.days7, [], now: day(1))
        let empty = Stat.HourOfDayResult(
            buckets: Engine.hourOfDay(none.w, calendar: calendar, clippedTo: none.window),
            summary: none.summary,
            bands: bands
        )
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.hours.count, 24)
        XCTAssertEqual(empty.peaks, [])
    }

    /// The hours follow the local clock on the DST days of a week of complete data: the 25-hour day gives hour 02 an
    /// hour more, the 23-hour day none; every other hour has one hour a day.
    func testHourOfDayOnTheDSTDays() {
        for (change, hourTwo) in [(Self.fallBack, 8.0), (Self.springForward, 6.0)] {
            let first = day(-3, from: change)
            let today = day(3, from: change)
            let start = first.addingTimeInterval(-TimeInterval.hours(1))
            let series = points(from: start, every: .minutes(5), count: Int(day(1, from: today).timeIntervalSince(start) / 300))
            let c = compute(.days7, series, now: series.last!.time.addingTimeInterval(120))
            XCTAssertEqual(c.window.start, first)
            XCTAssertEqual(c.summary.coverage, 1, accuracy: 1E-9)
            let result = Stat.HourOfDayResult(
                buckets: Engine.hourOfDay(c.w, calendar: calendar, clippedTo: c.window),
                summary: c.summary,
                bands: bands
            )
            for hour in result.hours {
                XCTAssertEqual(hour.hoursOfData, hour.hour == 2 ? hourTwo : 7, accuracy: 1E-9, "\(change) \(hour.hour)")
            }
            XCTAssertEqual(result.hours.reduce(0) { $0 + $1.seconds }, c.window.duration, accuracy: 1E-6)
        }
    }

    /// By hour, formatted: each hour's rows are its percents, "When it happens" lists lows, highs and the best hour
    /// (none for a group whose share is 0), each with its hour's interval and the share its rows add up to.
    @MainActor func testHourOfDayFormatting() {
        // 7 days to the end of today (the 25-hour day among them), every 5 minutes: low at 03, high at 18, in range
        // otherwise, nothing between 12:00 and 13:00
        let now = day(6).addingTimeInterval(TimeInterval.hours(23) + .minutes(57))
        let series = points(from: day(0), every: .minutes(5), count: Int(day(7).timeIntervalSince(day(0)) / 300)) { _ in 0 }
            .compactMap { point -> GlucosePoint? in
                switch calendar.component(.hour, from: point.time) {
                case 3: return GlucosePoint(time: point.time, mgdl: 60)
                case 12: return nil
                case 18: return GlucosePoint(time: point.time, mgdl: 200)
                default: return GlucosePoint(time: point.time, mgdl: 120)
                }
            }
        for units in [GlucoseUnits.mgdL, .mmolL] {
            var freeAPSSettings = FreeAPSSettings()
            freeAPSSettings.units = units
            freeAPSSettings.low = 70
            freeAPSSettings.high = 145
            let settings = Stat.StatsSettings(freeAPSSettings)
            let c = compute(.days7, series, now: now, bands: settings.bands)
            let result = Stat.HourOfDayResult(
                buckets: Engine.hourOfDay(c.w, calendar: calendar, clippedTo: c.window),
                summary: c.summary,
                bands: settings.bands
            )
            let view = Stat.HourOfDay(result, period: .days7, settings: settings)
            let overview = Stat.Overview(c.summary, period: .days7, settings: settings)
            XCTAssertEqual(view.dateRange, overview.dateRange)
            XCTAssertEqual(view.legendBands, settings.bands.visibleBands)
            XCTAssertEqual(view.plot.xTicks.map(\.hour), [0, 6, 12, 18])
            XCTAssertEqual(view.plot.yDomain, 0 ... 1)
            XCTAssertEqual(view.plot.parts.map(\.series), result.hours.flatMap { $0.segments.map(\.band.rawValue) })

            // the rows are the hour's percents, the Overview's band names and labels
            XCTAssertEqual(view.readouts.count, 24)
            for (hour, readout) in zip(result.hours, view.readouts) {
                XCTAssertEqual(readout.time, result.labels[hour.hour])
                XCTAssertEqual(readout.hasData, hour.hasData, "\(hour.hour)")
                // also without data (hidden there, keeping the card's height)
                let rows = readout.rows
                XCTAssertEqual(rows.map(\.band), settings.bands.visibleBands)
                XCTAssertEqual(rows.map(\.name), overview.rows.map(\.name))
                XCTAssertEqual(rows.map(\.range), overview.rows.map(\.range))
                guard readout.hasData else {
                    XCTAssertEqual(rows.map(\.percent), rows.map { _ in "–" })
                    continue
                }
                XCTAssertEqual(
                    rows.map(\.percent),
                    rows.map { StatsFormatting.percent(hour.percent($0.band), belowOne: hour.isBelowOnePercent($0.band)) }
                )
            }
            XCTAssertFalse(view.readouts[12].hasData)
            XCTAssertEqual(view.readouts[3].rows.first { $0.band == .low }?.percent, "100%")
            // the 25-hour day's repeated hour
            XCTAssertEqual(view.readouts[2].subtitle, StatsFormatting.hourDataNote(hours: 8, days: 7))
            XCTAssertEqual(view.readouts[4].subtitle, StatsFormatting.hourDataNote(hours: 7, days: 7))
            XCTAssertEqual(view.readouts[12].subtitle, String(format: NSLocalizedString("%d days", comment: ""), 7))

            // lows, highs, the best hour (the earliest of the hours all in range)
            XCTAssertEqual(view.peaks.map(\.group), [.below, .above, .inRange])
            XCTAssertEqual(view.peaks.map(\.hour), [3, 18, 0])
            XCTAssertEqual(view.peaks.map(\.band), [.low, .high, .inRange])
            XCTAssertEqual(view.peaks.map(\.time), [result.labels[3], result.labels[18], result.labels[0]])
            let low = StatsFormatting.glucose(settings.bands.low, units: units)
            let high = StatsFormatting.glucose(settings.bands.high, units: units)
            XCTAssertEqual(
                view.peaks[0].subtitle,
                String(format: NSLocalizedString("below %1$@ · %2$@ of that hour", comment: ""), low, "100%")
            )
            XCTAssertEqual(
                view.peaks[1].subtitle,
                String(format: NSLocalizedString("above %1$@ · %2$@ of that hour", comment: ""), high, "100%")
            )
            XCTAssertEqual(
                view.peaks[2].subtitle,
                String(format: NSLocalizedString("%@ of that hour in your range", comment: ""), "100%")
            )
        }

        // no highs: no row for them
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.low = 70
        freeAPSSettings.high = 145
        let settings = Stat.StatsSettings(freeAPSSettings)
        let noHighs = series.map { GlucosePoint(time: $0.time, mgdl: Swift.min($0.mgdl, 120)) }
        let c = compute(.days7, noHighs, now: now, bands: settings.bands)
        let result = Stat.HourOfDayResult(
            buckets: Engine.hourOfDay(c.w, calendar: calendar, clippedTo: c.window),
            summary: c.summary,
            bands: settings.bands
        )
        XCTAssertEqual(Stat.HourOfDay(result, period: .days7, settings: settings).peaks.map(\.group), [.below, .inRange])
    }

    /// "{N} days · {h} hours of data": the hours rounded, one hour and less than one in their own words.
    func testHourOfDayDataNote() {
        func note(_ format: String, _ args: CVarArg...) -> String {
            String(format: NSLocalizedString(format, comment: ""), arguments: args)
        }
        XCTAssertEqual(StatsFormatting.hourDataNote(hours: 12.4, days: 30), note("%1$d days · %2$d hours of data", 30, 12))
        XCTAssertEqual(StatsFormatting.hourDataNote(hours: 12.5, days: 30), note("%1$d days · %2$d hours of data", 30, 13))
        XCTAssertEqual(StatsFormatting.hourDataNote(hours: 1.2, days: 7), note("%d days · 1 hour of data", 7))
        XCTAssertEqual(StatsFormatting.hourDataNote(hours: 0.3, days: 7), note("%d days · less than 1 hour of data", 7))
        XCTAssertEqual(StatsFormatting.hourDataNote(hours: 0, days: 7), note("%1$d days · %2$d hours of data", 7, 0))
    }

    /// A pick on the chart snaps to its hour, kept inside the day; the stepper wraps around midnight.
    @MainActor func testHourSelection() {
        XCTAssertEqual(StatsHourBars.hour(at: 0), 0)
        XCTAssertEqual(StatsHourBars.hour(at: 8.99), 8)
        XCTAssertEqual(StatsHourBars.hour(at: 24), 23)
        XCTAssertEqual(StatsHourBars.hour(at: -1), 0)
        XCTAssertEqual(StatsHourBars.hour(at: .nan), 0)

        let selection = HourSelection()
        selection.select(x: 17.4)
        XCTAssertEqual(selection.hour, 17)
        selection.select(23)
        selection.step(by: 1)
        XCTAssertEqual(selection.hour, 0)
        selection.step(by: -1)
        XCTAssertEqual(selection.hour, 23)
        selection.select(40)
        XCTAssertEqual(selection.hour, 23)
    }

    func testWeeks() {
        for weekCount in [5, 13] {
            let period: StatsPeriod = weekCount == 5 ? .weeks5 : .weeks13
            let dayCount = 7 * weekCount
            let first = day(0)
            let now = day(dayCount - 1).addingTimeInterval(.hours(12))
            // every 5 minutes, except the whole of week 2
            let series = points(from: first, every: .minutes(5), count: Int(now.timeIntervalSince(first) / 300)).filter {
                !($0.time >= day(14) && $0.time < day(21))
            }
            let s = compute(period, series, now: now)
            XCTAssertEqual(s.window.start, first)
            XCTAssertEqual(s.days.count, dayCount)

            let weeks = Engine.weeks(s.days, count: period.weekCount!)
            XCTAssertEqual(weeks.count, weekCount)
            XCTAssertEqual(weeks.map(\.includesToday), Array(repeating: false, count: weekCount - 1) + [true])
            XCTAssertEqual(weeks[0].days.start, first)
            XCTAssertEqual(weeks[1].days.start, day(7))
            XCTAssertEqual(weeks.last?.days.end, s.window.end)
            XCTAssertEqual(weeks.map(\.lastDay), (0 ..< weekCount).map { day(7 * $0 + 6) })
            XCTAssertEqual(weeks.map(\.dayCount), Array(repeating: 7, count: weekCount))
            XCTAssertTrue(weeks[2].isEmpty)
            XCTAssertFalse(weeks[1].isEmpty)

            let total = weeks.reduce(0) { $0 + $1.histogram.totalSeconds }
            XCTAssertEqual(total, s.summary.histogram.totalSeconds, accuracy: 1E-6)
        }
    }

    func testWeeksWithADayCountThatIsNotAMultipleOfSeven() {
        // 10 days, 5 minutes of data each
        let days = (0 ..< 10).map { offset in
            DayAggregate(
                day: DateInterval(start: day(offset), end: day(offset + 1)),
                histogram: histogram([(120, 300)], at: day(offset))
            )
        }
        let weeks = Engine.weeks(days, count: 2)
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].days, DateInterval(start: day(0), end: day(7)))
        XCTAssertEqual(weeks[1].days, DateInterval(start: day(7), end: day(10)))
        XCTAssertEqual(weeks.map(\.includesToday), [false, true])
        XCTAssertEqual(weeks.map(\.lastDay), [day(6), day(9)])
        XCTAssertEqual(weeks.map(\.dayCount), [7, 3])
        XCTAssertEqual(weeks[0].histogram.totalSeconds, 7 * 300, accuracy: 1E-9)
        XCTAssertEqual(weeks[1].histogram.totalSeconds, 3 * 300, accuracy: 1E-9)
        // more weeks than days: only the weeks with days
        XCTAssertEqual(Engine.weeks(days, count: 3), weeks)
        // fewer: the newest days are left out
        XCTAssertEqual(Engine.weeks(days, count: 1).map(\.includesToday), [false])
        // the input order doesn't matter
        XCTAssertEqual(Engine.weeks(Array(days.reversed()), count: 2), weeks)
    }

    // MARK: - Weekly

    /// A week of 7 days from day 0.
    private func weekAggregate(_ histogram: GlucoseHistogram, includesToday: Bool = false) -> WeekAggregate {
        WeekAggregate(
            days: DateInterval(start: day(0), end: day(7)),
            lastDay: day(6),
            dayCount: 7,
            histogram: histogram,
            includesToday: includesToday
        )
    }

    /// Weeks follow the calendar days: the week with the change to summer or winter time is 167 or 169 hours long,
    /// every week starts at a local midnight, its last day is its seventh, and complete data covers each week exactly.
    func testWeeksAcrossTheDSTChanges() {
        for (change, hours) in [(Self.springForward, 167.0), (Self.fallBack, 169.0)] {
            // 5 weeks to 12:00 today, the change in the fourth
            let today = day(10, from: change)
            let first = day(-24, from: change)
            let now = today.addingTimeInterval(.hours(12))
            let start = first.addingTimeInterval(-TimeInterval.hours(1))
            let series = points(from: start, every: .minutes(5), count: Int(now.timeIntervalSince(start) / 300))
            let c = compute(.weeks5, series, now: now)
            XCTAssertEqual(c.window, DateInterval(start: first, end: now))

            let weeks = Engine.weeks(c.days, count: 5)
            XCTAssertEqual(weeks.map(\.days.start), (0 ..< 5).map { day(7 * $0, from: first) }, "\(change)")
            XCTAssertEqual(weeks.map(\.lastDay), (0 ..< 5).map { day(7 * $0 + 6, from: first) }, "\(change)")
            XCTAssertEqual(weeks.map(\.includesToday), [false, false, false, false, true])
            XCTAssertEqual(weeks[3].days.duration, .hours(hours), "\(change)")
            for week in weeks.prefix(3) {
                XCTAssertEqual(week.days.duration, .hours(168), "\(change)")
            }
            XCTAssertEqual(weeks[4].days, DateInterval(start: day(28, from: first), end: now))
            for week in weeks {
                XCTAssertEqual(week.histogram.totalSeconds, week.days.duration, accuracy: 1E-6, "\(change) \(week.days)")
            }
            let result = Stat.WeeklyResult(summary: c.summary, weeks: weeks, units: .mgdL)
            XCTAssertTrue(result.weeks.allSatisfy(\.hasData))
            XCTAssertEqual(result.weeks.map(\.inRangeDelta), Array(repeating: 0, count: 5))
        }
    }

    /// A week against the period: Δ = the week as shown − the period as shown. In range by largest remainder, the mean
    /// rounded as shown (in mmol/L the difference of the two displayed values); a Δ of 0 is neither better nor worse; a
    /// week no reading starts in has no data.
    func testWeeklyWeekAgainstThePeriod() {
        // the period: 70% in range, mean 130
        let period = summary(of: histogram([(100, 700), (200, 300)]))
        XCTAssertEqual(period.percent(.inRange), 70)

        // 1.3 / 3.3 / 71.4 / 18.0 / 6.0 %: in range 72 by largest remainder (71 rounded alone); mean 128.03 -> 128
        let week = Engine.weeklyWeek(
            weekAggregate(histogram([(50, 13), (60, 33), (100, 714), (200, 180), (300, 60)])),
            average: period,
            units: .mgdL
        )
        XCTAssertTrue(week.hasData)
        XCTAssertEqual(week.days, DateInterval(start: day(0), end: day(7)))
        XCTAssertEqual(week.lastDay, day(6))
        XCTAssertEqual(week.dayCount, 7)
        XCTAssertFalse(week.includesToday)
        XCTAssertEqual(week.inRangePercent, 72)
        XCTAssertFalse(week.inRangeBelowOnePercent)
        XCTAssertEqual(week.inRangeDelta, 2)
        XCTAssertEqual(week.inRangeComparison, .better)
        XCTAssertEqual(week.mean, 128)
        XCTAssertEqual(week.meanDelta, -2)
        XCTAssertEqual(week.meanComparison, .better)

        // the same as the period: ±0 both, neither better nor worse
        let same = Engine.weeklyWeek(weekAggregate(histogram([(100, 1400), (200, 600)])), average: period, units: .mgdL)
        XCTAssertEqual(same.inRangeDelta, 0)
        XCTAssertEqual(same.meanDelta, 0)
        XCTAssertEqual(same.inRangeComparison, .same)
        XCTAssertEqual(same.meanComparison, .same)

        // the means as shown: 152.5 -> 153 against 151.4 -> 151 is +2 (the raw 1.1 rounds to 1), worse
        let rounding = Engine.weeklyWeek(
            weekAggregate(histogram([(152, 500), (153, 500)])),
            average: summary(of: histogram([(151, 600), (152, 400)])),
            units: .mgdL
        )
        XCTAssertEqual(rounding.mean, 153)
        XCTAssertEqual(rounding.meanDelta, 2)
        XCTAssertEqual(rounding.meanComparison, .worse)
        XCTAssertEqual(rounding.inRangeDelta, 0)

        // mmol/L: 145 (8.0) − 140 (7.8) is 0.2, not the 0.3 of 5 mg/dL; 144 (8.0) against 145 (8.0) is ±0, though
        // 1 mg/dL lower
        let mmol = Engine.weeklyWeek(
            weekAggregate(histogram([(145, 600)])),
            average: summary(of: histogram([(140, 600)])),
            units: .mmolL
        )
        XCTAssertEqual(mmol.mean, Decimal(string: "8.0"))
        XCTAssertEqual(mmol.meanDelta, Decimal(string: "0.2"))
        XCTAssertEqual(mmol.meanComparison, .worse)
        let lower = weekAggregate(histogram([(144, 600)]))
        let lowerPeriod = summary(of: histogram([(145, 600)]))
        XCTAssertEqual(Engine.weeklyWeek(lower, average: lowerPeriod, units: .mmolL).meanDelta, 0)
        XCTAssertEqual(Engine.weeklyWeek(lower, average: lowerPeriod, units: .mmolL).meanComparison, .same)
        XCTAssertEqual(Engine.weeklyWeek(lower, average: lowerPeriod, units: .mgdL).meanDelta, -1)
        XCTAssertEqual(Engine.weeklyWeek(lower, average: lowerPeriod, units: .mgdL).meanComparison, .better)
        XCTAssertEqual(Engine.shownMean(152.5, units: .mgdL), 153)
        XCTAssertEqual(Engine.shownMean(144, units: .mmolL), Decimal(string: "8.0"))

        // a sliver in range: "<1%", its Δ from 0
        let sliver = Engine.weeklyWeek(weekAggregate(histogram([(100, 4), (300, 996)])), average: period, units: .mgdL)
        XCTAssertEqual(sliver.inRangePercent, 0)
        XCTAssertTrue(sliver.inRangeBelowOnePercent)
        XCTAssertEqual(sliver.inRangeDelta, -70)
        XCTAssertEqual(sliver.inRangeComparison, .worse)

        // no reading starts in it: no data, also with the previous week's last span running in
        var spillover = GlucoseHistogram()
        spillover.add(
            WeightedPoint(time: day(0).addingTimeInterval(-60), mgdl: 120, span: 300),
            seconds: 240,
            startsInside: false
        )
        XCTAssertTrue(weekAggregate(spillover).isEmpty)
        for empty in [weekAggregate(GlucoseHistogram()), weekAggregate(spillover, includesToday: true)] {
            let none = Engine.weeklyWeek(empty, average: period, units: .mgdL)
            XCTAssertFalse(none.hasData)
            XCTAssertEqual(none.includesToday, empty.includesToday)
            XCTAssertNil(none.inRangePercent)
            XCTAssertNil(none.mean)
            XCTAssertNil(none.inRangeDelta)
            XCTAssertNil(none.meanDelta)
            XCTAssertNil(none.inRangeComparison)
            XCTAssertNil(none.meanComparison)
        }
    }

    /// Better: a higher in range, a lower mean; a Δ of 0 is neither.
    func testWeeklyComparison() {
        typealias Comparison = WeeklyWeek.Comparison
        XCTAssertEqual(Comparison(delta: 2, higherIsBetter: true), .better)
        XCTAssertEqual(Comparison(delta: -2, higherIsBetter: true), .worse)
        XCTAssertEqual(Comparison(delta: 0, higherIsBetter: true), .same)
        XCTAssertEqual(Comparison(delta: Decimal(string: "0.1")!, higherIsBetter: false), .worse)
        XCTAssertEqual(Comparison(delta: Decimal(string: "-0.1")!, higherIsBetter: false), .better)
        XCTAssertEqual(Comparison(delta: 0, higherIsBetter: false), .same)
    }

    /// The charts' scale: the average in the middle, the farthest week inside, in whole steps, at least one; the weeks
    /// without data left out. A bar is never thinner than its minimum, a week at the average gets it across the line.
    func testWeeklyScaleAndBars() {
        XCTAssertEqual(Engine.weeklyHalfRange([nil, 72, 80, 60], average: 70, step: 5), 10)
        XCTAssertEqual(Engine.weeklyHalfRange([nil, 72, 81], average: 70, step: 5), 15)
        XCTAssertEqual(Engine.weeklyHalfRange([70], average: 70, step: 5), 5)
        XCTAssertEqual(Engine.weeklyHalfRange([75], average: 70, step: 5), 5)
        XCTAssertEqual(Engine.weeklyHalfRange([nil, nil], average: 70, step: 5), 5)
        XCTAssertEqual(Engine.weeklyHalfRange([], average: 130, step: 10), 10)
        XCTAssertEqual(Engine.weeklyHalfRange([95, 170], average: 130, step: 10), 40)
        // mmol/L values as Doubles: a hair over a whole step is that step
        func double(_ text: String) -> Double {
            NSDecimalNumber(decimal: Decimal(string: text)!).doubleValue
        }
        XCTAssertEqual(Engine.weeklyHalfRange([double("8.7")], average: double("7.7"), step: 0.5), 1, accuracy: 1E-12)
        XCTAssertEqual(Engine.weeklyHalfRange([double("6.6")], average: double("7.1"), step: 0.5), 0.5, accuracy: 1E-12)
        XCTAssertEqual(Engine.weeklyHalfRange([double("8.4")], average: double("7.7"), step: 0.5), 1, accuracy: 1E-12)
        XCTAssertEqual(Engine.weeklyMeanStep(units: .mgdL), 10)
        XCTAssertEqual(Engine.weeklyMeanStep(units: .mmolL), 0.5)
        XCTAssertEqual(Engine.weeklyInRangeStep, 5)

        func bar(_ value: Double) -> [Double] {
            let bar = Engine.weeklyBar(value, average: 70, halfRange: 10)
            return [bar.lower, bar.upper]
        }
        XCTAssertEqual(bar(80), [70, 80])
        XCTAssertEqual(bar(60), [60, 70])
        XCTAssertEqual(bar(70.1)[0], 70)
        XCTAssertEqual(bar(70.1)[1], 70.4, accuracy: 1E-12)
        XCTAssertEqual(bar(69.9)[0], 69.6, accuracy: 1E-12)
        XCTAssertEqual(bar(69.9)[1], 70)
        XCTAssertEqual(bar(70)[0], 69.8, accuracy: 1E-12)
        XCTAssertEqual(bar(70)[1], 70.2, accuracy: 1E-12)

        XCTAssertEqual(Engine.weeklyTickWeeks(count: 13), [0, 3, 6, 9, 12])
        XCTAssertEqual(Engine.weeklyTickWeeks(count: 5), [0, 1, 2, 3, 4])
        XCTAssertEqual(Engine.weeklyTickWeeks(count: 0), [])
    }

    /// Every 5 minutes over 5 weeks to 12:00 today (the 25-hour day in the first): 100 the first week, 160 the second
    /// with every 400th reading 120 (a sliver in range: "<1%"), none the third, 130 with every fourth reading 180 the
    /// fourth, 120 this week.
    private var weeklySeries: (points: [GlucosePoint], now: Date) {
        let now = day(34).addingTimeInterval(.hours(12))
        let start = day(0).addingTimeInterval(-TimeInterval.hours(1))
        let series = points(from: start, every: .minutes(5), count: Int(now.timeIntervalSince(start) / 300))
            .enumerated()
            .compactMap { index, point -> GlucosePoint? in
                let days = calendar.dateComponents([.day], from: day(0), to: point.time).day ?? 0
                switch Swift.min(Swift.max(days, 0) / 7, 4) {
                case 0: return GlucosePoint(time: point.time, mgdl: 100)
                case 1: return GlucosePoint(time: point.time, mgdl: index % 400 == 0 ? 120 : 160)
                case 2: return nil
                case 3: return GlucosePoint(time: point.time, mgdl: index % 4 == 0 ? 180 : 130)
                default: return GlucosePoint(time: point.time, mgdl: 120)
                }
            }
        return (series, now)
    }

    /// The provider's assembly: the period's summary is the Overview's, each week `weeklyWeek` of `weeks` against it,
    /// the labels the weeks' days.
    func testWeeklyResultIsTheEngines() {
        let (series, now) = weeklySeries
        let c = compute(.weeks5, series, now: now)
        let summary = Engine.summary(days: c.days, window: c.window, endRule: c.summary.endRule, period: .weeks5, bands: bands)
        XCTAssertEqual(summary.bandShares.percents, c.summary.bandShares.percents)
        XCTAssertEqual(summary.coveragePercent, c.summary.coveragePercent)
        XCTAssertEqual(summary.mean ?? 0, c.summary.mean ?? 0, accuracy: 1E-9)

        let weeks = Engine.weeks(c.days, count: 5)
        let result = Stat.WeeklyResult(summary: summary, weeks: weeks, units: .mgdL)
        XCTAssertEqual(result.summary, summary)
        XCTAssertEqual(result.weeks, weeks.map { Engine.weeklyWeek($0, average: summary, units: .mgdL) })
        XCTAssertEqual(result.averageMean, summary.mean.map { Engine.shownMean($0, units: .mgdL) })
        XCTAssertEqual(result.weeks.map(\.hasData), [true, true, false, true, true])
        XCTAssertEqual(result.weeks.map(\.includesToday), [false, false, false, false, true])
        XCTAssertEqual(result.weeks.map(\.inRangePercent), [100, 0, nil, 75, 100])
        XCTAssertEqual(result.weeks.map(\.inRangeComparison), [.better, .worse, nil, .better, .better])
        XCTAssertEqual(result.weeks.map(\.meanComparison), [.better, .worse, nil, .worse, .better])
        XCTAssertFalse(result.isEmpty)

        // the labels: the week's days, its first day on the axis
        XCTAssertEqual(result.labels.map(\.start), (0 ..< 5).map { day(7 * $0).formatted(.dateTime.day().month(.abbreviated)) })
        for (week, label) in zip(0 ..< 5, result.labels) {
            XCTAssertEqual(label.title, (day(7 * week) ..< day(7 * week + 6)).formatted(.interval.day().month(.abbreviated)))
        }

        // nothing in the period
        let none = compute(.weeks5, [], now: now)
        let empty = Stat.WeeklyResult(summary: none.summary, weeks: Engine.weeks(none.days, count: 5), units: .mgdL)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.weeks.count, 5)
        XCTAssertNil(empty.averageMean)
    }

    /// Weekly, formatted: the averages as the Overview shows them, the table newest first with the Δ signed (a minus
    /// sign, "±0"), the week without readings "no data"; the charts' bars for the weeks with data, coloured as the table.
    @MainActor func testWeeklyFormatting() {
        func text(_ format: String, _ args: CVarArg...) -> String {
            String(format: NSLocalizedString(format, comment: ""), arguments: args)
        }
        func signed(_ delta: Decimal, _ magnitude: String) -> String {
            delta == 0 ? "±0" : (delta > 0 ? "+" : "−") + magnitude
        }
        let (series, now) = weeklySeries
        for units in [GlucoseUnits.mgdL, .mmolL] {
            var freeAPSSettings = FreeAPSSettings()
            freeAPSSettings.units = units
            // as stored: mg/dL, fractional for mmol/L users (3.9 and 8.0 mmol/L: the edges 70 and 145)
            freeAPSSettings.low = units == .mmolL ? Decimal(string: "70.27")! : 70
            freeAPSSettings.high = units == .mmolL ? Decimal(string: "144.14")! : 145
            let settings = Stat.StatsSettings(freeAPSSettings)
            XCTAssertEqual([settings.bands.low, settings.bands.high], [70, 145], "\(units)")
            let c = compute(.weeks5, series, now: now, bands: settings.bands)
            let summary = Engine.summary(
                days: c.days,
                window: c.window,
                endRule: c.summary.endRule,
                period: .weeks5,
                bands: settings.bands
            )
            let aggregates = Engine.weeks(c.days, count: 5)
            let result = Stat.WeeklyResult(summary: summary, weeks: aggregates, units: units)
            let weekly = Stat.Weekly(result, period: .weeks5)
            let overview = Stat.Overview(summary, period: .weeks5, settings: settings)

            XCTAssertEqual(weekly.subtitle, text("%1$d weeks · %2$@", 5, overview.dateRange))
            XCTAssertEqual(weekly.inRangeTitle, text("In your range %@", overview.inRangeRange))
            XCTAssertEqual(weekly.inRangeAverage, text("average %@", overview.inRangePercent + "%"))
            XCTAssertEqual(weekly.meanTitle, text("Mean glucose · %@", overview.unit))
            // the period's mean as the Overview shows it
            XCTAssertEqual(weekly.meanAverage, text("average %@", overview.mean))

            // the table: newest first; this week "includes today", the week without readings "no data"
            XCTAssertEqual(weekly.rows.map(\.id), result.weeks.reversed().map(\.days.start))
            XCTAssertEqual(weekly.rows.map(\.title), result.labels.reversed().map(\.title))
            XCTAssertEqual(weekly.rows.map(\.subtitle), [text("includes today")] + Array(repeating: text("%d days", 7), count: 4))
            XCTAssertNil(weekly.rows[2].values)
            for (row, (week, aggregate)) in zip(weekly.rows, zip(result.weeks, aggregates).reversed()) where week.hasData {
                guard let values = row.values,
                      let inRange = week.inRangePercent,
                      let inRangeDelta = week.inRangeDelta,
                      let mean = week.mean,
                      let meanDelta = week.meanDelta,
                      let rawMean = aggregate.histogram.mean,
                      let averageMean = result.averageMean
                else {
                    XCTFail("\(row.title)")
                    continue
                }
                XCTAssertEqual(values.inRange, StatsFormatting.percent(inRange, belowOne: week.inRangeBelowOnePercent))
                XCTAssertEqual(values.inRangeDelta, signed(Decimal(inRangeDelta), "\(abs(inRangeDelta))"))
                XCTAssertEqual(inRangeDelta, inRange - summary.percent(.inRange))
                // the mean as every view shows a mean, its Δ the difference of the two shown
                XCTAssertEqual(values.mean, StatsFormatting.glucose(rawMean, units: units))
                XCTAssertEqual(meanDelta, mean - averageMean)
                let magnitude = StatsFormatting.glucose(shown: abs(meanDelta), units: units)
                XCTAssertEqual(values.meanDelta, signed(meanDelta, magnitude))
                XCTAssertEqual(values.inRangeComparison, week.inRangeComparison)
                XCTAssertEqual(values.meanComparison, week.meanComparison)
            }

            // the sliver in range of the second week: "<1%", its Δ from 0
            XCTAssertEqual(weekly.rows[3].values?.inRange, "<1%")
            XCTAssertEqual(weekly.rows[3].values?.inRangeDelta, "−\(summary.percent(.inRange))")
            XCTAssertEqual(weekly.rows[3].values?.inRangeComparison, .worse)

            // the charts: a slot for every week, a bar for those with data, coloured as the table
            let inRangeValues = result.weeks.compactMap(\.inRangePercent).map { Double($0) }
            let meanValues = result.weeks.compactMap(\.mean).map { NSDecimalNumber(decimal: $0).doubleValue }
            for (plot, values, step) in [
                (weekly.inRangePlot, inRangeValues, Engine.weeklyInRangeStep),
                (weekly.meanPlot, meanValues, Engine.weeklyMeanStep(units: units))
            ] {
                XCTAssertEqual(plot.slots, ["00", "01", "02", "03", "04"])
                XCTAssertEqual(plot.slots, plot.slots.sorted())
                XCTAssertEqual(plot.bars.map(\.slot), ["00", "01", "03", "04"])
                // the scale: whole steps, the farthest week inside, less than a step to spare
                let half = plot.domain.upperBound - plot.average
                let farthest = values.map { abs($0 - plot.average) }.max() ?? 0
                XCTAssertEqual((half / step).rounded(), half / step, accuracy: 1E-9, "\(units)")
                XCTAssertGreaterThanOrEqual(half, farthest - 1E-9, "\(units)")
                XCTAssertLessThan(half, farthest + step, "\(units)")
                XCTAssertFalse(plot.isNarrow)
                XCTAssertEqual(plot.ticks.map(\.label), result.labels.map(\.start))
                XCTAssertEqual(plot.domain.upperBound - plot.average, plot.average - plot.domain.lowerBound, accuracy: 1E-9)
                for bar in plot.bars {
                    XCTAssertTrue(plot.domain.contains(bar.lower) && plot.domain.contains(bar.upper), "\(units) \(bar)")
                    XCTAssertTrue(bar.lower == plot.average || bar.upper == plot.average, "\(units) \(bar)")
                }
            }
            XCTAssertEqual(weekly.inRangePlot.bars.map(\.comparison), [0, 1, 3, 4].map { result.weeks[$0].inRangeComparison })
            XCTAssertEqual(weekly.meanPlot.bars.map(\.comparison), [0, 1, 3, 4].map { result.weeks[$0].meanComparison })
            XCTAssertEqual(weekly.inRangePlot.average, Double(summary.percent(.inRange)))
            // the average's level reads as the average above the chart; none above 100% or below 0%
            XCTAssertEqual(weekly.inRangePlot.levels.first(where: \.isAverage)?.label, overview.inRangePercent + "%")
            XCTAssertTrue(weekly.inRangePlot.levels.allSatisfy { (0 ... 100).contains($0.value) })
            XCTAssertEqual(weekly.meanPlot.levels.first(where: \.isAverage)?.label, overview.mean)
            XCTAssertEqual(weekly.meanPlot.levels.count, 3)
            XCTAssertEqual(weekly.meanPlot.gridLevels.count, 2)
            let meanHalf = weekly.meanPlot.domain.upperBound - weekly.meanPlot.average
            XCTAssertEqual(
                [weekly.meanPlot.levels.first?.label, weekly.meanPlot.levels.last?.label],
                [weekly.meanPlot.average - meanHalf, weekly.meanPlot.average + meanHalf]
                    .map { Optional(StatsFormatting.glucose(shown: Decimal($0), units: units)) }
            )
        }

        // 13 weeks, all like the period: narrow bars, every third week labelled (this week too), ±0 everywhere, neither
        // colour, the scale one step either way
        let thirteen = (0 ..< 13).map { weekAggregate(histogram([(120, 600)]), includesToday: $0 == 12) }
        let flat = Stat.Weekly(
            Stat.WeeklyResult(summary: summary(of: histogram([(120, 13 * 600)])), weeks: thirteen, units: .mgdL),
            period: .weeks13
        )
        XCTAssertTrue(flat.inRangePlot.isNarrow)
        XCTAssertEqual(flat.inRangePlot.ticks.map(\.slot), ["00", "03", "06", "09", "12"])
        XCTAssertEqual(flat.inRangePlot.slots, flat.inRangePlot.slots.sorted())
        XCTAssertEqual(flat.rows.count, 13)
        XCTAssertEqual(flat.rows.first?.subtitle, text("includes today"))
        XCTAssertTrue(flat.rows.allSatisfy { $0.values?.inRangeDelta == "±0" && $0.values?.meanDelta == "±0" })
        XCTAssertTrue(flat.rows.allSatisfy { $0.values?.inRangeComparison == .same && $0.values?.meanComparison == .same })
        XCTAssertTrue(flat.meanPlot.bars.allSatisfy { $0.comparison == .same })
        XCTAssertEqual(flat.meanPlot.domain, 110 ... 130)
        XCTAssertEqual(flat.inRangePlot.domain, 95 ... 105)
        XCTAssertEqual(flat.inRangePlot.levels.map(\.label), ["95%", "100%"])
    }

    /// The average's level reads as the header: "<1%" for a sliver in range, not "0%".
    @MainActor func testWeeklyAverageLevelReadsAsTheHeader() {
        let sliver = histogram([(100, 4), (300, 996)])
        let period = summary(of: sliver)
        XCTAssertTrue(period.isBelowOnePercent(.inRange))
        let weekly = Stat.Weekly(
            Stat.WeeklyResult(summary: period, weeks: [weekAggregate(sliver)], units: .mgdL),
            period: .weeks5
        )
        XCTAssertEqual(weekly.inRangeAverage, String(format: NSLocalizedString("average %@", comment: ""), "<1%"))
        XCTAssertEqual(weekly.inRangePlot.levels.first(where: \.isAverage)?.label, "<1%")
        XCTAssertEqual(weekly.rows.first?.values?.inRange, "<1%")
        XCTAssertEqual(weekly.rows.first?.values?.inRangeDelta, "±0")
    }

    /// A period covered only by the previous evening's last span running into its first day: not empty (the Overview
    /// shows its numbers), every week "no data", no bar, only the average's rule; midnight its only time change.
    @MainActor func testWeeklyPeriodCoveredOnlyByTheSpanRunningIn() {
        let now = day(34).addingTimeInterval(.hours(12))
        let carry = points(from: day(0).addingTimeInterval(-120 - 100 * 300), every: .minutes(5), count: 101)
        let c = compute(.weeks5, carry, now: now)
        XCTAssertFalse(c.summary.isEmpty)
        XCTAssertEqual(c.summary.histogram.readingCount, 0)

        let result = Stat.WeeklyResult(summary: c.summary, weeks: Engine.weeks(c.days, count: 5), units: .mgdL)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.weeks.count, 5)
        XCTAssertTrue(result.weeks.allSatisfy { !$0.hasData })

        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        freeAPSSettings.low = 70
        freeAPSSettings.high = 145
        let overview = Stat.Overview(c.summary, period: .weeks5, settings: Stat.StatsSettings(freeAPSSettings))
        let weekly = Stat.Weekly(result, period: .weeks5)
        XCTAssertTrue(weekly.rows.allSatisfy { $0.values == nil })
        for plot in [weekly.inRangePlot, weekly.meanPlot] {
            XCTAssertEqual(plot.bars, [])
            XCTAssertEqual(plot.slots.count, 5)
        }
        XCTAssertEqual(weekly.inRangePlot.levels.first(where: \.isAverage)?.label, overview.inRangePercent + "%")
        XCTAssertEqual(weekly.meanPlot.levels.first(where: \.isAverage)?.label, overview.mean)
    }

    /// Nothing Weekly shows changes with the time alone within a day, current or stalled (E clips no span): only at
    /// midnight, when the period's days move on.
    @MainActor func testWeeklyChangesWithTheTimeAloneOnlyAtMidnight() {
        let (series, now) = weeklySeries
        func weekly(at now: Date) -> (view: Stat.Weekly, summary: GlucoseSummary) {
            let c = compute(.weeks5, series, now: now)
            let summary = Engine.summary(
                days: c.days,
                window: c.window,
                endRule: c.summary.endRule,
                period: .weeks5,
                bands: bands
            )
            let result = Stat.WeeklyResult(summary: summary, weeks: Engine.weeks(c.days, count: 5), units: .mgdL)
            return (Stat.Weekly(result, period: .weeks5), summary)
        }
        let current = weekly(at: now)
        XCTAssertFalse(current.summary.endRule == .stalled)
        for later in [now.addingTimeInterval(.minutes(20)), now.addingTimeInterval(TimeInterval.hours(11) + 59)] {
            let stalled = weekly(at: later)
            XCTAssertTrue(stalled.summary.endRule == .stalled)
            // the window's end moved on (every minute), what is shown didn't
            XCTAssertNotEqual(stalled.summary.window, current.summary.window)
            XCTAssertEqual(stalled.view, current.view)
        }
        // the next day: the period's first day moved on
        XCTAssertNotEqual(weekly(at: day(35).addingTimeInterval(60)).view, current.view)
    }

    /// The Δ signed.
    func testWeeklyDeltaStrings() {
        typealias Weekly = Stat.Weekly
        XCTAssertEqual(Weekly.signed(2, magnitude: "2"), "+2")
        XCTAssertEqual(Weekly.signed(Decimal(string: "-0.3")!, magnitude: "0.3"), "−0.3")
        XCTAssertEqual(Weekly.signed(0, magnitude: "0"), "±0")
    }

    /// The view's title and its periods' labels.
    @MainActor func testWeeklyTabAndPeriodLabels() {
        XCTAssertEqual(StatsViewMenu.title(.weekly), NSLocalizedString("Weekly", comment: ""))
        XCTAssertEqual(StatsFormatting.label(.weeks5), NSLocalizedString("1 mo", comment: ""))
        XCTAssertEqual(StatsFormatting.label(.weeks13), NSLocalizedString("3 mo", comment: ""))
    }

    // MARK: - Charts

    func testGlucoseAxis() {
        XCTAssertEqual(Engine.glucoseAxis(highest: nil), 40 ... 300)
        XCTAssertEqual(Engine.glucoseAxis(highest: 120), 40 ... 300)
        XCTAssertEqual(Engine.glucoseAxis(highest: 300), 40 ... 300)
        XCTAssertEqual(Engine.glucoseAxis(highest: 300.5), 40 ... 400)
        XCTAssertEqual(Engine.glucoseAxis(highest: 401), 40 ... 400)
    }

    func testChartLevels() {
        let axis = 40 ... 300
        // 54, 180, 250 dashed; low, high, the top, 180 and 250 labelled
        XCTAssertEqual(Engine.dashedLevels(bands: bands, axis: axis), [54, 180, 250])
        XCTAssertEqual(Engine.labelledLevels(bands: bands, axis: axis), [70, 145, 180, 250, 300])

        // a range edge is solid, not dashed: high 180, low clamped to 54
        let edges = StatsBands(low: 40, high: 180, units: .mgdL)
        XCTAssertEqual(edges.low, 54)
        XCTAssertEqual(Engine.dashedLevels(bands: edges, axis: axis), [250])

        // a level closer than 7% of the axis (18.2 mg/dL here) to one labelled before it is left out: high 170 hides 180
        let close = StatsBands(low: 70, high: 170, units: .mgdL)
        XCTAssertEqual(Engine.labelledLevels(bands: close, axis: axis), [70, 170, 250, 300])
        XCTAssertEqual(Engine.dashedLevels(bands: close, axis: axis), [54, 180, 250])

        // mmol: the TIR edge is 181, here also the high edge (10.0), so solid
        let mmol = StatsBands(low: Decimal(string: "70.27")!, high: Decimal(string: "180.18")!, units: .mmolL)
        XCTAssertEqual(mmol.tirRange.upperBound, 181)
        XCTAssertEqual(mmol.high, 181)
        XCTAssertEqual(Engine.dashedLevels(bands: mmol, axis: axis), [54, 250])
        let mmolLower = StatsBands(low: Decimal(string: "70.27")!, high: Decimal(string: "144.14")!, units: .mmolL)
        XCTAssertEqual(Engine.dashedLevels(bands: mmolLower, axis: axis), [54, 181, 250])

        // the raised axis: 400 on top, 25.2 mg/dL apart
        XCTAssertEqual(Engine.labelledLevels(bands: bands, axis: 40 ... 400), [70, 145, 180, 250, 400])
        // only inside the axis
        XCTAssertEqual(Engine.dashedLevels(bands: bands, axis: 60 ... 200), [180])
    }

    func testClockTicks() {
        // a day: 00, 06, 12, 18
        XCTAssertEqual(
            Engine.clockTicks(in: DateInterval(start: day(0), end: day(1)), calendar: calendar),
            [0, 6, 12, 18].map { day(0).addingTimeInterval(.hours($0)) }
        )

        // the 24 hours across midnight: real dates of both days, in order
        let start = day(0).addingTimeInterval(TimeInterval.hours(14) + .minutes(40))
        XCTAssertEqual(
            Engine.clockTicks(in: DateInterval(start: start, duration: .hours(24)), calendar: calendar),
            [
                day(0).addingTimeInterval(.hours(18)),
                day(1),
                day(1).addingTimeInterval(.hours(6)),
                day(1).addingTimeInterval(.hours(12))
            ]
        )

        // the start is inside, the end isn't
        let morning = DateInterval(start: day(0).addingTimeInterval(.hours(6)), end: day(0).addingTimeInterval(.hours(12)))
        XCTAssertEqual(Engine.clockTicks(in: morning, calendar: calendar), [morning.start])

        // DST days keep their clock times: 5 and 7 hours from 00:00 to 06:00
        let hour = { (date: Date) in Self.calendar.component(.hour, from: date) }
        for (dayStart, firstStep) in [(Self.springForward, TimeInterval.hours(5)), (Self.fallBack, TimeInterval.hours(7))] {
            let whole = StatsClock.calendarDays(in: DateInterval(start: dayStart, duration: 1), calendar: calendar)[0]
            let ticks = Engine.clockTicks(in: whole, calendar: calendar)
            XCTAssertEqual(ticks.map(hour), [0, 6, 12, 18])
            XCTAssertEqual(ticks[1].timeIntervalSince(ticks[0]), firstStep)
        }
    }

    func testNearestIndex() {
        let times = [0, 300, 600].map { Self.day0.addingTimeInterval(.seconds($0)) }
        func nearest(_ offset: Double) -> Int? {
            Engine.nearestIndex(to: Self.day0.addingTimeInterval(offset), in: times) { $0 }
        }
        XCTAssertEqual(nearest(-100), 0)
        XCTAssertEqual(nearest(0), 0)
        XCTAssertEqual(nearest(100), 0)
        // a tie goes to the earlier one
        XCTAssertEqual(nearest(150), 0)
        XCTAssertEqual(nearest(151), 1)
        XCTAssertEqual(nearest(300), 1)
        XCTAssertEqual(nearest(500), 2)
        XCTAssertEqual(nearest(600), 2)
        XCTAssertEqual(nearest(10000), 2)
        XCTAssertNil(Engine.nearestIndex(to: Self.day0, in: [Date]()) { $0 })
    }

    // MARK: - Trace

    func testTracePointsAreClampedIntoTheAxis() {
        let w = [30, 40, 120, 300, 350].enumerated().map { index, mgdl in
            WeightedPoint(time: Self.day0.addingTimeInterval(.minutes(5 * index)), mgdl: Int16(mgdl), span: .minutes(5))
        }
        let points = Engine.tracePoints(w, axis: 40 ... 300, bands: bands)
        XCTAssertEqual(points.map(\.time), w.map(\.time))
        XCTAssertEqual(points.map(\.mgdl), [30, 40, 120, 300, 350])
        XCTAssertEqual(points.map(\.plotted), [40, 40, 120, 300, 300])
        // the band of the reading, not of the value drawn
        XCTAssertEqual(points.map(\.band), [.veryLow, .veryLow, .inRange, .veryHigh, .veryHigh])

        // the raised axis draws 350 where it is
        XCTAssertEqual(Engine.tracePoints(w, axis: Engine.glucoseAxis(highest: 350), bands: bands).last?.plotted, 350)
        XCTAssertEqual(Engine.tracePoints([], axis: 40 ... 300, bands: bands), [])
    }

    func testTraceTicksLeaveRoomForNow() {
        // a day: the clock ticks, none dropped
        let wholeDay = DateInterval(start: day(0), end: day(1))
        XCTAssertEqual(
            Engine.traceTicks(in: wholeDay, endsNow: false, calendar: calendar),
            Engine.clockTicks(in: wholeDay, calendar: calendar)
        )

        // the 24 hours: none within 90 minutes before "now"
        func ticks(endingAt hours: Double) -> [Date] {
            let end = day(1).addingTimeInterval(.hours(hours))
            return Engine.traceTicks(
                in: DateInterval(start: end.addingTimeInterval(-TimeInterval.hours(24)), end: end),
                endsNow: true,
                calendar: calendar
            )
        }
        let previous18 = day(0).addingTimeInterval(.hours(18))
        let at = { (hours: Double) in self.day(1).addingTimeInterval(.hours(hours)) }
        XCTAssertEqual(ticks(endingAt: 17.5), [previous18, at(0), at(6), at(12)])
        XCTAssertEqual(ticks(endingAt: 13), [previous18, at(0), at(6)])
        // exactly 90 minutes stays
        XCTAssertEqual(ticks(endingAt: 13.5), [previous18, at(0), at(6), at(12)])
        XCTAssertEqual(ticks(endingAt: 13.49), [previous18, at(0), at(6)])
    }

    func testTraceStripDays() {
        // day 0 every 5 minutes, 00:03 ... 23:58, in range only the first and the last (its span runs 3 minutes into
        // day 1): 7 of 1437 minutes in range, the rest high
        let series = points(from: Self.day0.addingTimeInterval(.minutes(3)), every: .minutes(5), count: 288) {
            $0 == 0 || $0 == 287 ? 120 : 200
        }
        let s = compute(.days7, series, now: day(1).addingTimeInterval(.hours(12)))
        let strip = s.days.map { Engine.traceStripDay($0, endRule: s.summary.endRule, bands: bands) }
        XCTAssertEqual(strip.map(\.start), (-5 ... 1).map { day($0) })

        // the days before: nothing
        for stripDay in strip[0 ..< 5] {
            XCTAssertFalse(stripDay.hasReadings)
            XCTAssertEqual(stripDay.inRangeFraction, 0)
        }

        // day 0: 7 of 1437 minutes in range
        XCTAssertTrue(strip[5].hasReadings)
        XCTAssertEqual(strip[5].inRangeFraction, 7.0 / 1437, accuracy: 1E-12)

        // today: only the span running past midnight, in range: covered, but no reading
        XCTAssertFalse(strip[6].hasReadings)
        XCTAssertEqual(strip[6].inRangeFraction, 1)
    }

    func testTraceStripTodayDoesNotChangeWithTheTimeAlone() {
        // today every 5 minutes up to 12:00, current at 12:00:10, stalled after 12:07:30
        let today = day(1)
        let series = points(from: day(-1), every: .minutes(5), count: 2 * 288 + 145) { $0 % 3 == 0 ? 200 : 120 }
        func todayOnTheStrip(at now: Date) -> TraceStripDay {
            let s = compute(.days7, series, now: now)
            return Engine.traceStripDay(s.days.last!, endRule: s.summary.endRule, bands: bands)
        }
        let current = todayOnTheStrip(at: today.addingTimeInterval(TimeInterval.hours(12) + 10))
        XCTAssertTrue(current.hasReadings)
        for hours: Double in [12.2, 15, 23.9] {
            XCTAssertEqual(todayOnTheStrip(at: today.addingTimeInterval(.hours(hours))), current, "\(hours)")
        }
    }

    /// The Day tab shows "no data" only when its selector is in and none of its days has a reading: a day without
    /// readings among others (today just after midnight, covered only by the previous evening's span) shows the chart.
    func testDayTabHasNothingToShowOnlyWithoutAReadingOnAnyDay() {
        let strip = { (offset: Int, hasReadings: Bool) in
            TraceStripDay(
                start: self.day(offset),
                hasReadings: hasReadings,
                inRangeFraction: hasReadings ? 1 : 0
            )
        }
        typealias Item = Stat.TraceSelectorItem
        // not in yet: the trace is shown
        XCTAssertFalse(Item.nothingToShow([]))
        XCTAssertTrue(Item.nothingToShow(Item.items([strip(0, false), strip(1, false)])))
        // a reading on the day before today, none on today: the chart of today with "No readings"
        XCTAssertFalse(Item.nothingToShow(Item.items([strip(0, true), strip(1, false)])))
        // the 24 hours never counts as a day with readings
        XCTAssertEqual(Item.items([strip(0, true)]).map(\.hasReadings), [true, false])
    }

    // MARK: - Picking a day

    func testShownDayKeepsThePickInsideThePeriod() {
        let today = day(6)
        func shown(_ picked: Date?, _ period: StatsPeriod) -> Date? {
            Engine.shownDay(picked, period: period, today: today, calendar: calendar)
        }
        // nothing picked, or a period of one day: today
        XCTAssertNil(shown(nil, .days7))
        XCTAssertNil(shown(day(3), .today))
        XCTAssertNil(shown(day(3), .last24h))
        // a day of the period: that day, from its start
        XCTAssertEqual(shown(day(3), .days7), day(3))
        XCTAssertEqual(shown(day(3).addingTimeInterval(.hours(5)), .days7), day(3))
        // the 25-hour day
        XCTAssertEqual(shown(day(5), .days7), day(5))
        // before the period: its first day (7 d: day 0 ... today)
        XCTAssertEqual(shown(day(-10), .days7), day(0))
        XCTAssertEqual(shown(day(-10), .days14), day(-7))
        XCTAssertEqual(shown(day(-10), .days30), day(-10))
        XCTAssertEqual(shown(day(-40), .weeks5), day(-28))
        // today, or after it: today
        XCTAssertNil(shown(today, .days7))
        XCTAssertNil(shown(day(8), .days7))
    }

    func testDayIndexOfADate() {
        let days = (0 ..< 7).map { DateInterval(start: day($0), end: day($0 + 1)) }
        XCTAssertNil(Engine.dayIndex(containing: day(0), in: []))
        XCTAssertEqual(Engine.dayIndex(containing: day(-1), in: days), 0)
        XCTAssertEqual(Engine.dayIndex(containing: day(0), in: days), 0)
        XCTAssertEqual(Engine.dayIndex(containing: day(3).addingTimeInterval(-1), in: days), 2)
        XCTAssertEqual(Engine.dayIndex(containing: day(3), in: days), 3)
        XCTAssertEqual(Engine.dayIndex(containing: day(3).addingTimeInterval(.hours(12)), in: days), 3)
        // the 25-hour day: its last hour is still in it
        XCTAssertEqual(days[5].duration, .hours(25))
        XCTAssertEqual(Engine.dayIndex(containing: day(5).addingTimeInterval(.hours(24.5)), in: days), 5)
        // after the last day: the last one
        XCTAssertEqual(Engine.dayIndex(containing: day(7), in: days), 6)
        XCTAssertEqual(Engine.dayIndex(containing: day(9), in: days), 6)
    }

    // MARK: - Daily

    /// Every 5 minutes from the day before day 0 to 12:00 on day 6, through every band, none on day 2: the Daily
    /// view's 7 days (day 0 ... day 6, day 5 is 25 hours long).
    private var dailySeries: (points: [GlucosePoint], now: Date) {
        let now = day(6).addingTimeInterval(.hours(12))
        let start = day(-1)
        let values: [Int16] = [45, 60, 70, 100, 145, 146, 200, 251, 300]
        let count = Int(now.timeIntervalSince(start) / 300)
        let series = points(from: start, every: .minutes(5), count: count) { values[($0 * 7) % values.count] }
            .filter { $0.time < day(2) || $0.time >= day(3) }
        return (series, now)
    }

    private func dailyDays(_ c: Computed, bands: StatsBands? = nil) -> [DailyDay] {
        c.days.map { Engine.dailyDay($0, endRule: c.summary.endRule, bands: bands ?? self.bands, calendar: calendar) }
    }

    /// The Trace's summary of a day: the whole day up to E, its readings weighed from all of them.
    private func traceSummary(of wholeDay: DateInterval, _ c: Computed, bands: StatsBands? = nil) -> GlucoseSummary {
        let window = DateInterval(
            start: wholeDay.start,
            end: Swift.max(wholeDay.start, Swift.min(wholeDay.end, c.window.end))
        )
        let histogram = Engine.histogram(c.w, clippedTo: window)
        let counts = Engine.dayCounts(.today, days: [DayAggregate(day: window, histogram: histogram)])
        return Engine.summary(
            histogram,
            window: window,
            endRule: c.summary.endRule,
            calendarDays: counts.calendarDays,
            daysWithData: counts.daysWithData,
            bands: bands ?? self.bands
        )
    }

    func testDailyDayIsTheTracesDay() {
        let (series, now) = dailySeries
        let c = compute(.days7, series, now: now)
        let days = dailyDays(c)
        XCTAssertEqual(days.map(\.day.start), (0 ... 6).map { day($0) })
        // the whole calendar days, also today's (computed up to E) and the 25-hour one
        XCTAssertEqual(days.map(\.day), (0 ... 6).map { DateInterval(start: day($0), end: day($0 + 1)) })
        XCTAssertEqual(days[5].day.duration, .hours(25))
        XCTAssertEqual(days.map(\.hasReadings), [true, true, false, true, true, true, true])

        for (aggregate, daily) in zip(c.days, days) {
            let trace = traceSummary(of: daily.day, c)
            let name = "\(daily.day.start)"
            XCTAssertEqual(Engine.daySummary(aggregate, endRule: c.summary.endRule, bands: bands), trace, name)
            XCTAssertEqual(daily.hasReadings, trace.histogram.readingCount > 0, name)
            XCTAssertEqual(daily.bandShares, trace.bandShares, name)
            XCTAssertEqual(daily.tirPercent, trace.tirPercent, name)
            XCTAssertEqual(daily.titrPercent, trace.titrPercent, name)
            XCTAssertEqual(daily.mean, trace.mean, name)
            XCTAssertEqual(daily.cv, trace.cv, name)
            XCTAssertEqual(daily.coveragePercent, trace.coveragePercent, name)
            XCTAssertEqual(daily.secondsBelowLow, trace.histogram.seconds(in: 0 ... bands.low - 1), accuracy: 1E-6, name)
        }
        // every band is there, and below the low end some time
        XCTAssertTrue(days[3].bandShares.percents.allSatisfy { $0 > 0 })
        XCTAssertGreaterThan(days[3].secondsBelowLow, 0)
    }

    func testDailyBarsStackTheBands() {
        let (series, now) = dailySeries
        let c = compute(.days7, series, now: now)
        for (aggregate, daily) in zip(c.days, dailyDays(c)) {
            guard daily.hasReadings else {
                XCTAssertEqual(daily.segments, [])
                continue
            }
            let oneDay = Engine.daySummary(aggregate, endRule: c.summary.endRule, bands: bands)
            // the nonzero bands, very low at the bottom, back to back up to the whole day's covered time
            XCTAssertEqual(daily.segments.map(\.band), GlucoseBand.allCases.filter { oneDay.fraction($0) > 0 })
            XCTAssertEqual(daily.segments.first?.lower, 0)
            for (below, above) in zip(daily.segments, daily.segments.dropFirst()) {
                XCTAssertEqual(below.upper, above.lower)
            }
            XCTAssertEqual(daily.segments.last?.upper ?? 0, 1, accuracy: 1E-12)
            for segment in daily.segments {
                XCTAssertEqual(segment.upper - segment.lower, oneDay.fraction(segment.band), accuracy: 1E-12)
            }
        }

        // a zero-width band (low 40 is clamped to 54: no low band) is never drawn
        let noLow = StatsBands(low: 40, high: 145, units: .mgdL)
        XCTAssertFalse(dailyDays(c, bands: noLow).contains { day in day.segments.contains { $0.band == .low } })
    }

    func testDailyDaysWithoutReadingsHaveNoBar() {
        // just after midnight, the last reading at 23:58: its span runs 3 minutes into today, and none starts in it
        let today = day(1)
        let carry = compute(
            .days7,
            points(from: today.addingTimeInterval(-120 - 287 * 300), every: .minutes(5), count: 288),
            now: today.addingTimeInterval(60)
        )
        let days = dailyDays(carry)
        XCTAssertEqual(days.last?.day, DateInterval(start: today, end: day(2)))
        XCTAssertFalse(days.last?.hasReadings ?? true)
        XCTAssertEqual(days.last?.segments, [])
        XCTAssertTrue(days[5].hasReadings)

        // and the zero-length today while E is still yesterday's: the whole day too
        let early = compute(
            .days7,
            points(from: today.addingTimeInterval(-330 - 287 * 300), every: .minutes(5), count: 288),
            now: today.addingTimeInterval(60)
        )
        XCTAssertEqual(early.days.last?.day, DateInterval(start: today, duration: 0))
        let earlyToday = dailyDays(early).last
        XCTAssertEqual(earlyToday?.day, DateInterval(start: today, end: day(2)))
        XCTAssertEqual(earlyToday?.segments, [])
        XCTAssertEqual(earlyToday?.coveragePercent, 0)
    }

    func testDailyLeadingDayShowsTheSelectedDay() {
        func leading(_ selected: Int, from leading: Int?, days: Int = 90) -> Int {
            Engine.dailyLeadingDay(showing: selected, from: leading, dayCount: days, visibleDays: Engine.dailyVisibleDays)
        }
        // opening: the selected day at the trailing end
        XCTAssertEqual(leading(89, from: nil), 78)
        XCTAssertEqual(leading(40, from: nil), 29)
        XCTAssertEqual(leading(5, from: nil), 0)
        // shown already: no scrolling
        XCTAssertEqual(leading(80, from: 78), 78)
        XCTAssertEqual(leading(41, from: 30), 30)
        // before the days shown: it becomes the first; after: the last
        XCTAssertEqual(leading(60, from: 78), 60)
        XCTAssertEqual(leading(89, from: 30), 78)
        XCTAssertEqual(leading(42, from: 30), 31)
        // a position past the period's last full screen is kept inside it
        XCTAssertEqual(leading(89, from: 85), 78)
        // a period that fits: always its first day
        XCTAssertEqual(leading(6, from: nil, days: 7), 0)
        XCTAssertEqual(leading(0, from: 3, days: 7), 0)
        XCTAssertEqual(leading(11, from: nil, days: 12), 0)
        XCTAssertEqual(leading(13, from: nil, days: 14), 2)
    }

    func testDailyResultIsEmptyOnlyWithoutData() {
        let now = day(6).addingTimeInterval(60)
        func result(_ c: Computed) -> Stat.DailyResult {
            Stat.DailyResult(summary: c.summary, days: dailyDays(c))
        }
        XCTAssertTrue(result(compute(.days7, [], now: now)).isEmpty)

        // covered only by a span running in from before the period (its first day, day 0): the Overview shows numbers,
        // the chart has no bar
        let carry = result(compute(
            .days7,
            points(from: day(0).addingTimeInterval(-120 - 100 * 300), every: .minutes(5), count: 101),
            now: now
        ))
        XCTAssertFalse(carry.summary.isEmpty)
        XCTAssertTrue(carry.days.allSatisfy { !$0.hasReadings && $0.segments.isEmpty })
        XCTAssertFalse(carry.isEmpty)

        XCTAssertFalse(result(compute(.days7, points(from: day(3), every: .minutes(5), count: 3), now: now)).isEmpty)
    }

    func testDailyChangesWithTheTimeAloneOnlyInTodaysCoverage() {
        // every 5 minutes up to 10:00 today: current up to 10:07:30, stalled after
        let today = day(6)
        let lastReading = today.addingTimeInterval(.hours(10))
        let series = points(
            from: day(-1),
            every: .minutes(5),
            count: Int(lastReading.timeIntervalSince(day(-1)) / 300) + 1
        ) { $0 % 5 == 0 ? 200 : 120 }
        func daily(at now: Date) -> Stat.DailyResult {
            let c = compute(.days7, series, now: now)
            return Stat.DailyResult(
                summary: Engine.summary(days: c.days, window: c.window, endRule: c.summary.endRule, period: .days7, bands: bands),
                days: dailyDays(c)
            )
        }
        let requestedAt = lastReading.addingTimeInterval(10)
        let current = daily(at: requestedAt)
        let stalled = daily(at: today.addingTimeInterval(.hours(14)))
        let later = daily(at: today.addingTimeInterval(.hours(20)))

        // the bars, and the days before today, stay
        for result in [stalled, later] {
            XCTAssertEqual(result.days.map(\.segments), current.days.map(\.segments))
            XCTAssertEqual(Array(result.days.dropLast()), Array(current.days.dropLast()))
        }
        // today's coverage moves on while stalled (10 h 05 m of 10 h 05 m, 14 h, 20 h)
        XCTAssertEqual(current.days.last?.coveragePercent, 100)
        XCTAssertEqual(stalled.days.last?.coveragePercent, 72)
        XCTAssertEqual(later.days.last?.coveragePercent, 50)

        // the period summary is the Overview's
        let overview = summary(.days7, series, now: requestedAt)
        XCTAssertEqual(current.summary.endRule, overview.endRule)
        XCTAssertEqual(current.summary.bandShares.percents, overview.bandShares.percents)
        XCTAssertEqual(current.summary.coveragePercent, overview.coveragePercent)
    }

    /// 30 days ending in the week of the change to summer time (2026-03-29, a 23-hour day: index 24), so the last
    /// 12 days include it.
    private func springForwardPlot() -> StatsDayBars.Plot {
        let first = day(-24, from: Self.springForward)
        let days = (0 ..< 30).map { offset in
            DateInterval(start: day(offset, from: first), end: day(offset + 1, from: first))
        }
        return StatsDayBars.Plot(days: days, labels: [], parts: [], levels: [], levelLabels: [])
    }

    func testDailyScrollPositionIsReadAsTheNearestDayStart() {
        let plot = springForwardPlot()
        XCTAssertEqual(
            plot.domain,
            DateInterval(start: day(-24, from: Self.springForward), end: day(6, from: Self.springForward))
        )
        XCTAssertEqual(plot.days[24].day.duration, .hours(23))
        let start = { (index: Int) in plot.days[index].day.start }
        func leading(_ selected: Int, from position: Date?, visibleDays: Int = 12) -> Date {
            plot.leadingEdge(showing: selected, from: position, visibleDays: visibleDays)
        }

        // opening: the selected day at the trailing end (the last full screen starts at day 18, or 22 with 8 days)
        XCTAssertEqual(leading(29, from: nil), start(18))
        XCTAssertEqual(leading(29, from: nil, visibleDays: 8), start(22))
        XCTAssertEqual(leading(10, from: nil), start(0))
        // a position written back a hair before a midnight is that midnight's day: a tap on the first day shown, or a
        // step back onto it, doesn't scroll a day back
        XCTAssertEqual(leading(5, from: start(5).addingTimeInterval(-1)), start(5))
        XCTAssertEqual(leading(4, from: start(5).addingTimeInterval(-1)), start(4))
        XCTAssertEqual(leading(16, from: start(5).addingTimeInterval(-1)), start(5))
        // past the middle of a day: the next one
        XCTAssertEqual(leading(10, from: start(5).addingTimeInterval(.hours(13))), start(6))
        // the end of the period, 12 × 24 h before its end: an hour before a midnight in this week (its 23-hour day),
        // still that midnight's day, so nothing scrolls
        let end = plot.domain.end.addingTimeInterval(-plot.visibleLength(days: 12))
        XCTAssertEqual(end, start(18).addingTimeInterval(-TimeInterval.hours(1)))
        XCTAssertEqual(leading(18, from: end), start(18))
        XCTAssertEqual(leading(29, from: end), start(18))
        XCTAssertEqual(leading(24, from: end), start(18))
        // a position past the last full screen is kept at it
        XCTAssertEqual(leading(29, from: start(25)), start(18))
        XCTAssertEqual(leading(20, from: start(25)), start(18))
        // a tap's day is still the day it falls in
        XCTAssertEqual(plot.index(containing: start(5).addingTimeInterval(-1)), 4)
    }

    // MARK: - By weekday

    /// A gregorian calendar in Berlin with a locale (its weekend, its first weekday).
    private func weekdayCalendar(_ locale: String, firstWeekday: Int? = nil) -> Calendar {
        var calendar = Self.calendar
        calendar.locale = Locale(identifier: locale)
        if let firstWeekday {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }

    /// By weekday's pooling of the readings, the way the service runs it.
    /// - Parameter calendar: the days', the hours' and the columns' order's (Berlin, without a locale by default)
    private func weekdayPooled(
        _ points: [GlucosePoint],
        weeks: Int,
        today: Date,
        calendar: Calendar? = nil
    ) -> WeekdayHours {
        let calendar = calendar ?? self.calendar
        return Engine.weekdayHours(
            weighed(points),
            days: Engine.weekdayDays(weeks: weeks, today: today, calendar: calendar),
            bands: bands,
            calendar: calendar
        )
    }

    /// 4 weeks to `day(28)`, every 5 minutes from the lookback on, 120 mg/dL, but `skipped` days
    private func weekdaySeries(skipping skipped: [Date] = []) -> [GlucosePoint] {
        let start = day(0).addingTimeInterval(-.hours(1))
        return points(from: start, every: .minutes(5), count: Int(day(28).timeIntervalSince(start) / 300))
            .filter { point in !skipped.contains { calendar.isDate(point.time, inSameDayAs: $0) } }
    }

    /// A pool of the shown numbers (`weekdayStep` reads only them).
    private func weekdayPool(inRange: Int = 0, low: Int = 0, lowBelowOne: Bool = false, mean: Double? = 120) -> WeekdayPool {
        var percents = [0, low, inRange, 0, 0]
        percents[3] = Swift.max(100 - inRange - low, 0)
        return WeekdayPool(
            seconds: 3600,
            readingCount: 12,
            days: 1,
            bandShares: BandShares(fractions: percents.map { Double($0) / 100 }, percents: percents),
            lowPercent: low,
            lowBelowOnePercent: lowBelowOne,
            highPercent: percents[3],
            highBelowOnePercent: false,
            mean: mean,
            isFew: false
        )
    }

    /// The period is whole weeks to yesterday: 7 × weeks whole calendar days (a 25-hour one among them), each weekday as
    /// often, ending at the start of today, the same all day long (it moves on at midnight only).
    func testWeekdayDaysAreWholeWeeksToYesterday() {
        // Tue 17 Nov 2026, 14:00: 8 weeks back to Tue 22 Sep, Sun 25 Oct (25 h) among them
        let today = day(28)
        for weeks in [4, 8, 13] {
            let days = Engine.weekdayDays(weeks: weeks, today: today.addingTimeInterval(.hours(14)), calendar: calendar)
            XCTAssertEqual(days.count, weeks * 7)
            XCTAssertEqual(days.last?.end, today)
            XCTAssertEqual(days.first?.start, calendar.date(byAdding: .day, value: -weeks * 7, to: today))
            for (day, next) in zip(days, days.dropFirst()) {
                XCTAssertEqual(day.end, next.start)
            }
            let weekdays = Dictionary(grouping: days) { calendar.component(.weekday, from: $0.start) }
            XCTAssertEqual(weekdays.count, 7)
            XCTAssertTrue(weekdays.values.allSatisfy { $0.count == weeks }, "\(weeks)")
            XCTAssertEqual(days.filter { $0.duration == .hours(25) }.map(\.start), [Self.fallBack])
            // the same just after midnight and just before the next one
            XCTAssertEqual(Engine.weekdayDays(weeks: weeks, today: today.addingTimeInterval(1), calendar: calendar), days)
            XCTAssertEqual(
                Engine.weekdayDays(weeks: weeks, today: day(29).addingTimeInterval(-1), calendar: calendar),
                days
            )
        }
        XCTAssertEqual(Engine.weekdayDays(weeks: 0, today: today, calendar: calendar), [])
        // a period ending today is the same days moved on by one
        let tomorrow = Engine.weekdayDays(weeks: 4, today: day(29), calendar: calendar)
        XCTAssertEqual(tomorrow.last?.start, today)
    }

    /// The N whole days to yesterday (the 25-hour one among them), the same all day long; By weekday's are N = 7 × weeks.
    func testCompleteDaysEndYesterday() {
        // Fri 30 Oct 2026
        let today = day(10)
        for count in [14, 30, 90] {
            let days = Engine.completeDays(count: count, today: today.addingTimeInterval(.hours(14)), calendar: calendar)
            XCTAssertEqual(days.count, count)
            XCTAssertEqual(days.last?.end, today)
            XCTAssertEqual(days.first?.start, calendar.date(byAdding: .day, value: -count, to: today))
            for (day, next) in zip(days, days.dropFirst()) {
                XCTAssertEqual(day.end, next.start)
            }
            XCTAssertEqual(days.filter { $0.duration == .hours(25) }.map(\.start), [Self.fallBack])
            XCTAssertEqual(Engine.completeDays(count: count, today: today, calendar: calendar), days)
            XCTAssertEqual(Engine.completeDays(count: count, today: day(11).addingTimeInterval(-1), calendar: calendar), days)
        }
        XCTAssertEqual(Engine.completeDays(count: 0, today: today, calendar: calendar), [])
        XCTAssertEqual(Engine.completeDays(count: -1, today: today, calendar: calendar), [])
        XCTAssertEqual(
            Engine.completeDays(count: 28, today: today, calendar: calendar),
            Engine.weekdayDays(weeks: 4, today: today, calendar: calendar)
        )
    }

    /// Every weekday pools its days of the period, each hour by the local clock: complete data gives each weekday its
    /// weeks' days, 4 h in each hour (the 25-hour day's repeated 02:00 an hour more), the whole period covered; today's
    /// readings and the lookback's aren't counted.
    func testWeekdayHoursPoolEveryWeekdayEqually() {
        let today = day(28)
        let start = day(0).addingTimeInterval(-.hours(1))
        // every 5 minutes, up to today 12:00: high on Saturdays, in range otherwise
        let series = points(
            from: start,
            every: .minutes(5),
            count: Int(today.addingTimeInterval(.hours(12)).timeIntervalSince(start) / 300)
        ) {
            _ in 0
        }.map { point in
            GlucosePoint(time: point.time, mgdl: calendar.component(.weekday, from: point.time) == 7 ? 200 : 120)
        }
        let pooled = weekdayPooled(series, weeks: 4, today: today)
        XCTAssertEqual(pooled.window, DateInterval(start: day(0), end: today))
        XCTAssertEqual(pooled.dayCounts, Array(repeating: 4, count: 7))
        XCTAssertEqual(pooled.daysWithData, Array(repeating: 4, count: 7))
        XCTAssertEqual(pooled.firstReading, day(0))

        let total = pooled.hours.joined().reduce(0) { $0 + $1.tally.seconds }
        XCTAssertEqual(total, today.timeIntervalSince(day(0)), accuracy: 1E-6)
        XCTAssertEqual(pooled.blocks.joined().reduce(0) { $0 + $1.tally.seconds }, total, accuracy: 1E-6)
        let readings = pooled.hours.joined().reduce(0) { $0 + $1.tally.readingCount }
        XCTAssertEqual(readings, series.filter { $0.time >= day(0) && $0.time < today }.count)

        for weekday in 0 ..< 7 {
            for hour in 0 ..< 24 {
                let cell = pooled.hours[weekday][hour]
                // Sunday 02:00 twice on 25 Oct
                let hours = weekday == 0 && hour == 2 ? 5.0 : 4.0
                XCTAssertEqual(cell.tally.seconds, .hours(hours), accuracy: 1E-6, "\(weekday) \(hour)")
                XCTAssertEqual(cell.days, 4, "\(weekday) \(hour)")
                let band: GlucoseBand = weekday == 6 ? .high : .inRange
                XCTAssertEqual(cell.tally.bandSeconds[band.rawValue], cell.tally.seconds, accuracy: 1E-6)
                XCTAssertEqual(cell.tally.mean ?? 0, weekday == 6 ? 200 : 120, accuracy: 1E-9)
            }
            for block in 0 ..< 8 {
                XCTAssertEqual(pooled.blocks[weekday][block].days, 4)
                let hours = weekday == 0 && block == 0 ? 13.0 : 12.0
                XCTAssertEqual(pooled.blocks[weekday][block].tally.seconds, .hours(hours), accuracy: 1E-6)
            }
        }
    }

    /// The DST days by the local clock, as By hour has them: the 23-hour Sunday has no 02:00 (no data, no day), the
    /// 25-hour one 02:00 twice (one day).
    func testWeekdayHoursOnTheDSTDays() {
        for (change, hourTwo) in [(Self.fallBack, 2.0), (Self.springForward, 0.0)] {
            let today = day(4, from: change)
            let start = day(-3, from: change).addingTimeInterval(-.hours(1))
            let series = points(from: start, every: .minutes(5), count: Int(today.timeIntervalSince(start) / 300))
            let pooled = weekdayPooled(series, weeks: 1, today: today)
            let sunday = pooled.hours[0]
            XCTAssertEqual(sunday.reduce(0) { $0 + $1.tally.seconds }, calendar.dateInterval(of: .day, for: change)!.duration)
            for (hour, cell) in sunday.enumerated() {
                let hours: Double = hour == 2 ? hourTwo : 1
                XCTAssertEqual(cell.tally.seconds, TimeInterval.hours(hours), accuracy: 1E-6, "\(change) \(hour)")
                XCTAssertEqual(cell.days, hour == 2 && hourTwo == 0 ? 0 : 1, "\(change) \(hour)")
            }
            XCTAssertEqual(pooled.daysWithData, Array(repeating: 1, count: 7))
        }
    }

    /// The columns: the workdays in their order, then the weekend, whatever the first weekday: Mon … Sun for a
    /// Monday-first and a Sunday-first locale (Saturday–Sunday weekend), Sun … Thu, Fri, Sat for a Friday–Saturday one.
    func testWeekdayOrderKeepsTheWeekendLast() {
        let germany = weekdayCalendar("de_DE")
        let us = weekdayCalendar("en_US")
        let israel = weekdayCalendar("he_IL")
        XCTAssertEqual(germany.firstWeekday, 2)
        XCTAssertEqual(us.firstWeekday, 1)
        let mondayFirst = [2, 3, 4, 5, 6, 7, 1]
        let saturdayFirst = weekdayCalendar("de_DE", firstWeekday: 7)
        let calendars = [(germany, "de_DE"), (us, "en_US"), (saturdayFirst, "Saturday first")]
        for (calendar, name) in calendars {
            for offset in 0 ..< 7 {
                let shown = Engine.weekdayOrder(calendar: calendar, around: day(offset))
                XCTAssertEqual(shown.order, mondayFirst, "\(name) \(offset)")
                XCTAssertEqual(shown.weekend, [7, 1], "\(name) \(offset)")
            }
        }
        let iran = weekdayCalendar("fa_IR")
        let afghanistan = weekdayCalendar("ps_AF")
        let india = weekdayCalendar("en_IN")
        for offset in 0 ..< 7 {
            // India: Sunday alone, Mon … Sat, Sun
            let sunday = Engine.weekdayOrder(calendar: india, around: day(offset))
            XCTAssertEqual(sunday.order, [2, 3, 4, 5, 6, 7, 1], "\(offset)")
            XCTAssertEqual(sunday.weekend, [1], "\(offset)")
            let shown = Engine.weekdayOrder(calendar: israel, around: day(offset))
            XCTAssertEqual(shown.order, [1, 2, 3, 4, 5, 6, 7], "\(offset)")
            XCTAssertEqual(shown.weekend, [6, 7], "\(offset)")
            // Iran: Friday alone, Sat … Thu, Fri
            let friday = Engine.weekdayOrder(calendar: iran, around: day(offset))
            XCTAssertEqual(friday.order, [7, 1, 2, 3, 4, 5, 6], "\(offset)")
            XCTAssertEqual(friday.weekend, [6], "\(offset)")
            // Afghanistan: Thursday–Friday, Sat … Wed, Thu, Fri
            let thursday = Engine.weekdayOrder(calendar: afghanistan, around: day(offset))
            XCTAssertEqual(thursday.order, [7, 1, 2, 3, 4, 5, 6], "\(offset)")
            XCTAssertEqual(thursday.weekend, [5, 6], "\(offset)")
        }
        // a weekend given: the week that ends with it, whatever the first weekday
        XCTAssertEqual(Engine.weekdayOrder(weekend: [5, 6], firstWeekday: 2).order, [7, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(Engine.weekdayOrder(weekend: [7, 1], firstWeekday: 1).order, [2, 3, 4, 5, 6, 7, 1])
    }

    /// The result in the columns' order: each weekday's pool, its usual (the same hours on the other six), the
    /// workdays against the weekend by the locale.
    func testWeekdayResultIsInTheColumnsOrder() {
        // one week, every 5 minutes, a value per weekday: Sunday 100, Monday 110 … Saturday 160
        let today = day(28)
        let start = day(21).addingTimeInterval(-.hours(1))
        let series = points(from: start, every: .minutes(5), count: Int(today.timeIntervalSince(start) / 300)) { _ in 0 }
            .map { GlucosePoint(time: $0.time, mgdl: Int16(90 + 10 * calendar.component(.weekday, from: $0.time))) }
        let pooled = weekdayPooled(series, weeks: 1, today: today)

        let monday = Stat.WeekdayResult(
            weekdayPooled(series, weeks: 1, today: today, calendar: weekdayCalendar("de_DE")),
            period: .weeks8
        )
        XCTAssertEqual(monday.order, [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(monday.weekendCount, 2)
        XCTAssertEqual(monday.weeks, 8)
        XCTAssertEqual(monday.window, pooled.window)
        XCTAssertEqual(monday.lastDay, day(27))
        XCTAssertEqual(monday.weekdays.map { Int($0.mean!.rounded()) }, [110, 120, 130, 140, 150, 160, 100])
        XCTAssertEqual(monday.daysWithData, Array(repeating: 1, count: 7))
        // the period holds 8 of each, there is one: limited (at most half)
        XCTAssertTrue(monday.isLimited)
        XCTAssertNil(monday.recordedSince)
        XCTAssertFalse(monday.isEmpty)
        XCTAssertEqual(monday.hours.count, 7)
        XCTAssertEqual(monday.hours[0].count, 24)
        XCTAssertEqual(monday.blocks[0].count, 8)
        // the usual: the other six at the same hour (equal time each)
        let others = [100.0, 120, 130, 140, 150, 160]
        XCTAssertEqual(monday.usualHours[0][10].mean ?? 0, others.reduce(0, +) / 6, accuracy: 1E-9)
        XCTAssertEqual(monday.usualHours[0][10].seconds, .hours(6), accuracy: 1E-6)
        XCTAssertEqual(monday.usualBlocks[6][3].seconds, .hours(18), accuracy: 1E-6)
        XCTAssertEqual(monday.workdays.seconds, .hours(5 * 24), accuracy: 1E-6)
        XCTAssertEqual(monday.workdays.mean ?? 0, 130, accuracy: 1E-9)
        XCTAssertEqual(monday.workdays.days, 5)
        XCTAssertEqual(monday.weekend?.mean ?? 0, 130, accuracy: 1E-9)
        XCTAssertEqual(monday.weekend?.days, 2)
        // the 145 high edge: Saturday (160) and Friday (150) are high
        XCTAssertEqual(monday.weekdays[5].highPercent, 100)
        XCTAssertEqual(monday.weekdays[4].highPercent, 100)
        XCTAssertEqual(monday.weekdays[3].percent(.inRange), 100)

        let friday = Stat.WeekdayResult(
            weekdayPooled(series, weeks: 1, today: today, calendar: weekdayCalendar("he_IL")),
            period: .weeks8
        )
        XCTAssertEqual(friday.order, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(friday.weekend?.mean ?? 0, 155, accuracy: 1E-9)
        XCTAssertEqual(friday.workdays.mean ?? 0, 120, accuracy: 1E-9)

        // nothing in the period
        let none = Stat.WeekdayResult(weekdayPooled([], weeks: 4, today: today), period: .weeks4)
        XCTAssertTrue(none.isEmpty)
        XCTAssertFalse(none.isLimited)
        XCTAssertEqual(none.daysWithData, Array(repeating: 0, count: 7))

        // only today's readings: the weeks end yesterday, nothing to show (`.empty`, "they end yesterday")
        let todayOnly = points(from: today, every: .minutes(5), count: 100)
        let onlyToday = Stat.WeekdayResult(weekdayPooled(todayOnly, weeks: 4, today: today), period: .weeks4)
        XCTAssertTrue(onlyToday.isEmpty)
        XCTAssertNil(onlyToday.firstReading)
    }

    /// A calendar without a weekend: the week from its first weekday, no weekend pool, no comparison card.
    @MainActor func testWeekdayWithoutAWeekend() {
        XCTAssertEqual(Engine.weekdayOrder(weekend: [], firstWeekday: 2).order, [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(Engine.weekdayOrder(weekend: [], firstWeekday: 1).order, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(Engine.weekdayOrder(weekend: [], firstWeekday: 2).weekend, [])
        // a week all weekend is no weekend
        XCTAssertEqual(Engine.weekdayOrder(weekend: [1, 2, 3, 4, 5, 6, 7], firstWeekday: 1).weekend, [])

        let pooled = weekdayPooled(weekdaySeries(), weeks: 4, today: day(28))
        let shown = Engine.weekdayOrder(weekend: [], firstWeekday: 2)
        let noWeekend = WeekdayHours(
            days: pooled.days,
            hours: pooled.hours,
            blocks: pooled.blocks,
            dayCounts: pooled.dayCounts,
            daysWithData: pooled.daysWithData,
            firstReading: pooled.firstReading,
            firstDayWithData: pooled.firstDayWithData,
            order: shown.order,
            weekend: shown.weekend
        )
        let result = Stat.WeekdayResult(noWeekend, period: .weeks4)
        XCTAssertNil(result.weekend)
        XCTAssertEqual(result.weekendCount, 0)
        XCTAssertEqual(result.workdays.days, 28)
        let view = Stat.Weekday(result, settings: Stat.StatsSettings(FreeAPSSettings()), calendar: weekdayCalendar("en_US"))
        XCTAssertNil(view.workdays)
        XCTAssertNil(view.weekend)
        XCTAssertEqual(view.summaryRows, [])
        XCTAssertEqual(view.weekendStart, 7)
        XCTAssertEqual(view.heatmap(.inRange, hoursPerRow: 1)?.weekendStart, 7)
    }

    /// Limited when the recording began inside the period, or some weekday has readings on at most half the period's
    /// weeks; a day without readings here and there isn't.
    func testWeekdayLimitedCounts() {
        let today = day(28)
        let germany = weekdayCalendar("de_DE")
        // recorded since Fri 30 Oct (the 11th day): 2 or 3 of each weekday
        let since = day(10)
        let series = points(from: since, every: .minutes(5), count: Int(today.timeIntervalSince(since) / 300))
        let recorded = Stat.WeekdayResult(weekdayPooled(series, weeks: 4, today: today, calendar: germany), period: .weeks4)
        XCTAssertTrue(recorded.isLimited)
        XCTAssertEqual(recorded.recordedSince, since)
        // Fri … Mon three times (the last day, Mon 16 Nov), Tue … Thu twice
        XCTAssertEqual(recorded.daysWithData, [3, 2, 2, 2, 3, 3, 3])
        XCTAssertEqual(recorded.firstReading, since)
        // recorded since the next day, every weekday but one still 4 times: limited all the same
        let nextDay = points(from: day(1), every: .minutes(5), count: Int(today.timeIntervalSince(day(1)) / 300))
        let lateByADay = Stat.WeekdayResult(weekdayPooled(nextDay, weeks: 4, today: today, calendar: germany), period: .weeks4)
        XCTAssertEqual(lateByADay.recordedSince, day(1))
        XCTAssertTrue(lateByADay.isLimited)

        // a day without readings in the middle of complete weeks: Wed 4 Nov, 3 Wednesdays: not limited
        let missing = Stat.WeekdayResult(
            weekdayPooled(weekdaySeries(skipping: [day(15)]), weeks: 4, today: today, calendar: germany),
            period: .weeks4
        )
        XCTAssertEqual(missing.daysWithData, [4, 4, 3, 4, 4, 4, 4])
        XCTAssertNil(missing.recordedSince)
        XCTAssertFalse(missing.isLimited)
        // two of the four Wednesdays: half, limited
        let half = Stat.WeekdayResult(
            weekdayPooled(weekdaySeries(skipping: [day(15), day(22)]), weeks: 4, today: today, calendar: germany),
            period: .weeks4
        )
        XCTAssertEqual(half.daysWithData, [4, 4, 2, 4, 4, 4, 4])
        XCTAssertNil(half.recordedSince)
        XCTAssertTrue(half.isLimited)
        // a first day with readings from its noon on: recorded from the period's start
        let fromNoon = weekdaySeries().filter { $0.time >= day(0).addingTimeInterval(.hours(12)) }
        let noon = Stat.WeekdayResult(weekdayPooled(fromNoon, weeks: 4, today: today, calendar: germany), period: .weeks4)
        XCTAssertNil(noon.recordedSince)
        XCTAssertFalse(noon.isLimited)

        let whole = Stat.WeekdayResult(weekdayPooled(weekdaySeries(), weeks: 4, today: today, calendar: germany), period: .weeks4)
        XCTAssertFalse(whole.isLimited)
        // a reading of yesterday's spilling past midnight is no reading of today; today's aren't counted
        XCTAssertEqual(whole.daysWithData, Array(repeating: 4, count: 7))
    }

    /// The date range of By weekday's periods, as the siblings show theirs: its first day to its last, yesterday; also
    /// for a period across a DST change (in the zone the app formats in, `Calendar.current`).
    @MainActor func testWeekdayDateRange() {
        let current = Calendar.current
        for components in [DateComponents(year: 2026, month: 11, day: 17), DateComponents(year: 2026, month: 4, day: 2)] {
            let today = current.startOfDay(for: current.date(from: components)!)
            let yesterday = current.date(byAdding: .day, value: -1, to: today)!
            for period in StatsPeriod.weekdayPeriods {
                let weeks = period.weekCount!
                let days = Engine.weekdayDays(weeks: weeks, today: today, calendar: current)
                let window = DateInterval(start: days.first!.start, end: days.last!.end)
                XCTAssertEqual(days.last?.start, yesterday)
                XCTAssertEqual(window.end, today)
                XCTAssertEqual(window.start, current.date(byAdding: .day, value: -7 * weeks, to: today))
                let expected = String(
                    format: NSLocalizedString("%@ – %@", comment: "Statistics date range, first and last day"),
                    window.start.formatted(.dateTime.day().month(.abbreviated)),
                    yesterday.formatted(.dateTime.day().month(.abbreviated))
                )
                XCTAssertEqual(StatsFormatting.dateRange(window, period: period), expected, "\(components) \(period)")
            }
        }
        // 4 weeks to Tue 17 Nov 2026: 20 Oct – 16 Nov
        let november = current.startOfDay(for: current.date(from: DateComponents(year: 2026, month: 11, day: 17))!)
        let days = Engine.weekdayDays(weeks: 4, today: november, calendar: current)
        let first = current.dateComponents([.month, .day], from: days.first!.start)
        let last = current.dateComponents([.month, .day], from: days.last!.start)
        XCTAssertEqual([first.month, first.day, last.month, last.day], [10, 20, 11, 16])
    }

    /// A 1-minute sensor across the DST days: the 25-hour Sunday's 02:00 has 120 readings and 2 h, the 23-hour one's
    /// none, the other hours 60 and one.
    func testWeekdayHoursOfAOneMinuteSensorOnTheDSTDays() {
        for (change, hourTwo) in [(Self.fallBack, 2), (Self.springForward, 0)] {
            let today = day(4, from: change)
            let start = day(-3, from: change).addingTimeInterval(-.hours(1))
            let series = points(from: start, every: .minutes(1), count: Int(today.timeIntervalSince(start) / 60))
            let pooled = weekdayPooled(series, weeks: 1, today: today)
            let sunday = pooled.hours[0]
            for (hour, cell) in sunday.enumerated() {
                let hours = hour == 2 ? hourTwo : 1
                XCTAssertEqual(cell.tally.seconds, TimeInterval.hours(hours), accuracy: 1E-6, "\(change) \(hour)")
                XCTAssertEqual(cell.tally.readingCount, 60 * hours, "\(change) \(hour)")
                XCTAssertEqual(cell.days, hours > 0 ? 1 : 0, "\(change) \(hour)")
            }
            XCTAssertEqual(sunday.reduce(0) { $0 + $1.tally.readingCount }, hourTwo == 2 ? 25 * 60 : 23 * 60)
            // the 3-hour block of 00–03 the same
            XCTAssertEqual(pooled.blocks[0][0].tally.seconds, TimeInterval.hours(2 + hourTwo), accuracy: 1E-6)
        }
    }

    /// The lookback reading before the period's first midnight: its minutes after it go to its own clock hour (23:00)
    /// of the first day, as By hour gives them; no reading, no day there. By weekday's cells summed by hour are
    /// `hourOfDay` of the period, the lookback reading's minutes too.
    func testWeekdayHoursMatchByHour() {
        let today = day(7)
        // every 5 minutes from 23:58 the evening before, values going round the bands, a gap of 40 minutes on day 2
        let count = Int(today.timeIntervalSince(day(0)) / 300)
        var series = points(from: day(0).addingTimeInterval(-120), every: .minutes(5), count: count) {
            Int16(50 + ($0 * 23) % 240)
        }
        series.removeSubrange(600 ..< 608)
        let pooled = weekdayPooled(series, weeks: 1, today: today)
        // Tue 20 Oct 23:00: its own hour, and the 3 minutes of the evening before's 23:58 after the first midnight
        let tuesday = calendar.component(.weekday, from: day(0)) - 1
        let lookback = pooled.hours[tuesday][23]
        XCTAssertEqual(lookback.tally.seconds, TimeInterval.hours(1) + 180, accuracy: 1E-6)
        XCTAssertEqual(lookback.days, 1)
        XCTAssertEqual(pooled.firstReading, day(0).addingTimeInterval(180))
        XCTAssertEqual(pooled.firstDayWithData, day(0))

        let byHour = Engine.hourOfDay(weighed(series), calendar: calendar, clippedTo: pooled.window!)
        for bucket in byHour {
            let cells = pooled.hours.map { $0[bucket.hour] }
            let seconds = cells.reduce(0) { $0 + $1.tally.seconds }
            XCTAssertEqual(seconds, bucket.histogram.totalSeconds, accuracy: 1E-6, "\(bucket.hour)")
            XCTAssertEqual(cells.reduce(0) { $0 + $1.tally.readingCount }, bucket.histogram.readingCount, "\(bucket.hour)")
            let inRange = cells.reduce(0) { $0 + $1.tally.bandSeconds[GlucoseBand.inRange.rawValue] }
            XCTAssertEqual(inRange, Engine.seconds(bucket.histogram, in: GlucoseBand.inRange, bands: bands), accuracy: 1E-6)
        }
    }

    /// The hatching: under 3 h of covered time per hour of the cell, whatever the cadence (180 readings of a 1-minute
    /// sensor are 3 h, so are 36 of a 5-minute one); a 3-hour block needs 9 h. A pool that isn't a cell is never few.
    func testWeekdayFewReadingsThreshold() {
        let today = day(28)
        let saturdays = Engine.weekdayDays(weeks: 4, today: today, calendar: calendar)
            .filter { calendar.component(.weekday, from: $0.start) == 7 }
            .prefix(3)
        let cadences: [(step: TimeInterval, perDay: Int)] = [(TimeInterval.minutes(1), 60), (TimeInterval.minutes(5), 12)]
        for (step, perDay) in cadences {
            let readings = saturdays.flatMap { saturday in
                points(from: saturday.start.addingTimeInterval(.hours(10)), every: step, count: perDay)
            }
            XCTAssertEqual(readings.count, perDay * 3)
            let enough = weekdayPooled(readings, weeks: 4, today: today)
            let cell = enough.hours[6][10]
            XCTAssertEqual(cell.tally.seconds, .hours(3), accuracy: 1E-6)
            XCTAssertEqual(cell.days, 3)
            XCTAssertFalse(Engine.weekdayPool(cell.tally, days: cell.days, hoursPerCell: 1).isFew, "\(step)")
            // the block of 09–12 with the same 3 h: few for a block
            let block = enough.blocks[6][3]
            XCTAssertTrue(Engine.weekdayPool(block.tally, days: block.days, hoursPerCell: 3).isFew)
            XCTAssertFalse(Engine.weekdayPool(block.tally, days: block.days, hoursPerCell: nil).isFew)

            let fewer = weekdayPooled(Array(readings.dropLast()), weeks: 4, today: today).hours[6][10]
            XCTAssertEqual(fewer.tally.seconds, TimeInterval.hours(3) - step, accuracy: 1E-6)
            XCTAssertTrue(Engine.weekdayPool(fewer.tally, days: fewer.days, hoursPerCell: 1).isFew, "\(step)")
            // the hours without readings: no data, not few
            let empty = enough.hours[6][11]
            XCTAssertFalse(Engine.weekdayPool(empty.tally, days: empty.days, hoursPerCell: 1).hasData)
            XCTAssertFalse(Engine.weekdayPool(empty.tally, days: empty.days, hoursPerCell: 1).isFew)
        }
    }

    /// A pool shown: the band percents by largest remainder, low and high the sums of their two bands' percents, "<1%"
    /// for a nonzero sum rounded to 0.
    func testWeekdayPoolLowAndHigh() {
        var tally = WeekdayTally()
        func add(_ mgdl: Int16, _ seconds: TimeInterval) {
            tally.add(WeightedPoint(time: day(0), mgdl: mgdl, span: seconds), seconds: seconds, startsInside: true, bands: bands)
        }
        // 0.3% very low, 0.1% low, 89.6% in range, 10% high
        add(50, 3)
        add(60, 1)
        add(100, 896)
        add(200, 100)
        let pool = Engine.weekdayPool(tally, days: 2, hoursPerCell: nil)
        XCTAssertEqual(pool.bandShares.percents.reduce(0, +), 100)
        XCTAssertEqual(pool.lowPercent, pool.percent(.veryLow) + pool.percent(.low))
        XCTAssertEqual(pool.lowPercent, 0)
        XCTAssertTrue(pool.lowBelowOnePercent)
        XCTAssertEqual(pool.highPercent, 10)
        XCTAssertFalse(pool.highBelowOnePercent)
        XCTAssertEqual(pool.readingCount, 4)
        XCTAssertEqual(pool.days, 2)
        let weighted: Double = 50 * 3 + 60 + 100 * 896 + 200 * 100
        XCTAssertEqual(pool.mean ?? 0, weighted / 1000, accuracy: 1E-9)
        // the same tally twice is the same shares
        XCTAssertEqual(
            Engine.weekdayPool(tally + tally, days: 4, hoursPerCell: nil).bandShares.percents,
            pool.bandShares.percents
        )
    }

    /// The heatmap's five steps of each metric, by the value shown: in range and low by their percents, the mean as
    /// shown in the units (mmol/L 6/7/8/9, mg/dL 110/130/150/170); nothing without data.
    func testWeekdayMetricSteps() {
        let inRange: [(Int, Int)] = [(0, 0), (49, 0), (50, 1), (69, 1), (70, 2), (79, 2), (80, 3), (89, 3), (90, 4), (100, 4)]
        for (percent, step) in inRange {
            XCTAssertEqual(Engine.weekdayStep(weekdayPool(inRange: percent), metric: .inRange, units: .mgdL), step, "\(percent)")
        }
        let low: [(Int, Int)] = [(0, 0), (1, 1), (2, 2), (3, 2), (4, 3), (7, 3), (8, 4), (30, 4)]
        for (percent, step) in low {
            XCTAssertEqual(Engine.weekdayStep(weekdayPool(low: percent), metric: .low, units: .mgdL), step, "\(percent)")
        }
        // the first step is no low at all: "<1%" is the second ("<2"), as 1%
        XCTAssertEqual(Engine.weekdayStep(weekdayPool(low: 0, lowBelowOne: true), metric: .low, units: .mgdL), 1)
        // mmol/L as shown: 107 mg/dL is 5.9, 108 is 6.0; 161 is 8.9, 162 is 9.0
        let mmol: [(Double, Int)] = [(107, 0), (108, 1), (126, 2), (144, 3), (161, 3), (162, 4)]
        for (mgdl, step) in mmol {
            XCTAssertEqual(Engine.weekdayStep(weekdayPool(mean: mgdl), metric: .mean, units: .mmolL), step, "\(mgdl)")
        }
        let mgdl: [(Double, Int)] = [(109.4, 0), (109.5, 1), (129, 1), (130, 2), (150, 3), (169, 3), (170, 4), (300, 4)]
        for (mean, step) in mgdl {
            XCTAssertEqual(Engine.weekdayStep(weekdayPool(mean: mean), metric: .mean, units: .mgdL), step, "\(mean)")
        }
        XCTAssertEqual(Engine.weekdayStepEdges(.inRange, units: .mmolL), [50, 70, 80, 90])
        XCTAssertEqual(Engine.weekdayStepEdges(.low, units: .mgdL), [1, 2, 4, 8])
        // without data
        let none = Engine.weekdayPool(WeekdayTally(), days: 0, hoursPerCell: 1)
        for metric in WeekdayMetric.allCases {
            XCTAssertNil(Engine.weekdayStep(none, metric: metric, units: .mmolL))
        }
    }

    /// The readout's stepper: the next or previous row around midnight, a 3-hour block's first hour.
    func testWeekdayRowStep() {
        XCTAssertEqual(Engine.weekdayRowStep(23, by: 1, hoursPerRow: 1), 0)
        XCTAssertEqual(Engine.weekdayRowStep(0, by: -1, hoursPerRow: 1), 23)
        XCTAssertEqual(Engine.weekdayRowStep(10, by: 1, hoursPerRow: 3), 12)
        XCTAssertEqual(Engine.weekdayRowStep(10, by: 0, hoursPerRow: 3), 9)
        XCTAssertEqual(Engine.weekdayRowStep(1, by: -1, hoursPerRow: 3), 21)
        XCTAssertEqual(Engine.weekdayRowStep(22, by: 1, hoursPerRow: 3), 0)
    }

    /// By weekday, formatted: the counts, the table (a Days row with limited data), the heatmap's steps and keys, the
    /// picked cell's readout against the usual, the workdays against the weekend.
    @MainActor func testWeekdayFormatting() {
        let today = day(28)
        let start = day(0).addingTimeInterval(-.hours(1))
        // 4 complete weeks, every 5 minutes: low at 03 on Saturdays, in range otherwise; nothing on Sundays 12:00–13:00,
        // 10 minutes of Mondays 08:00
        let series = points(from: start, every: .minutes(5), count: Int(today.timeIntervalSince(start) / 300)) { _ in 0 }
            .compactMap { point -> GlucosePoint? in
                let weekday = calendar.component(.weekday, from: point.time)
                let hour = calendar.component(.hour, from: point.time)
                let minute = calendar.component(.minute, from: point.time)
                if weekday == 1, hour == 12 { return nil }
                if weekday == 2, hour == 8, minute >= 10 { return nil }
                return GlucosePoint(time: point.time, mgdl: weekday == 7 && hour == 3 ? 60 : 120)
            }
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        freeAPSSettings.low = 70
        freeAPSSettings.high = 145
        let settings = Stat.StatsSettings(freeAPSSettings)
        let names = weekdayCalendar("en_US")
        let result = Stat.WeekdayResult(
            Engine.weekdayHours(
                weighed(series),
                days: Engine.weekdayDays(weeks: 4, today: today, calendar: names),
                bands: settings.bands,
                calendar: names
            ),
            period: .weeks4
        )
        let view = Stat.Weekday(result, settings: settings, calendar: names)

        XCTAssertEqual(view.columns.map(\.weekday), [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(view.columns.map(\.short), [2, 3, 4, 5, 6, 7, 1].map { names.shortWeekdaySymbols[$0 - 1] })
        XCTAssertEqual(view.weekendStart, 5)
        XCTAssertNil(view.limitedNote)
        XCTAssertEqual(view.countNote, String(format: NSLocalizedString("%@ of each weekday", comment: ""), "4"))
        // the weekdays, In range, Mean, Low, High; no Days row
        XCTAssertEqual(view.tableRows.count, 5)
        XCTAssertEqual(view.tableRows[0].values, view.columns.map(\.short))
        XCTAssertEqual(view.tableRows[1].values, ["100%", "100%", "100%", "100%", "100%", "96%", "100%"])
        XCTAssertEqual(view.tableRows[3].values[5], "4%")
        XCTAssertEqual(view.bars.parts[5].map(\.band), [.low, .inRange])
        XCTAssertEqual(view.bars.parts[5].last?.upper ?? 0, 1, accuracy: 1E-9)
        XCTAssertEqual(view.weekdayRows.map(\.inRange), view.tableRows[1].values)

        // the heatmap: Saturday 03:00 all low, the empty Sunday hour without a step, Monday 08:00 few
        let lowMap = view.heatmap(.low, hoursPerRow: 1)!
        XCTAssertEqual(lowMap.weekendStart, 5)
        XCTAssertEqual(lowMap.rowCount, 24)
        XCTAssertEqual(lowMap.cells[5][3], .init(step: 4, isFew: false))
        XCTAssertEqual(lowMap.cells[5][4], .init(step: 0, isFew: false))
        XCTAssertEqual(lowMap.cells[6][12], .init(step: nil, isFew: false))
        XCTAssertEqual(lowMap.cells[0][8], .init(step: 0, isFew: true))
        let blocks = view.heatmap(.inRange, hoursPerRow: 3)!
        XCTAssertEqual(blocks.rowCount, 8)
        // Saturday 03–06: 2 of its 3 hours in range (67%); Sunday 12–15: 2 hours a day, all in range, under 9 h
        XCTAssertEqual(blocks.cells[5][1], .init(step: 1, isFew: false))
        XCTAssertEqual(blocks.cells[6][4], .init(step: 4, isFew: true))
        XCTAssertEqual(view.legends[.inRange]?.steps, ["<50", "50–70", "70–80", "80–90", "≥90"])
        XCTAssertEqual(view.legends[.low]?.steps, ["0", "<2", "2–4", "4–8", "≥8"])
        XCTAssertEqual(view.legends[.mean]?.steps, ["<110", "110–130", "130–150", "150–170", "≥170"])
        XCTAssertEqual(view.legends[.mean]?.title, "mg/dL")
        XCTAssertEqual(view.hourLabels.compactMap { $0 }.count, 8)
        XCTAssertEqual(view.blockLabels.count, 8)

        // the picked cell: Saturday 03:00, against the same hour on the other six days
        let saturday = view.readout(weekday: 7, hour: 3, hoursPerRow: 1, metric: .low)!
        XCTAssertTrue(saturday.hasData)
        XCTAssertEqual(saturday.value, "100%")
        XCTAssertEqual(saturday.usual, String(format: NSLocalizedString("usual %@", comment: ""), "0%"))
        XCTAssertFalse(saturday.isFew)
        XCTAssertEqual(saturday.rows.map(\.band), settings.bands.visibleBands.reversed())
        XCTAssertTrue(saturday.title.hasPrefix(names.weekdaySymbols[6]))
        XCTAssertTrue(saturday.subtitle.hasPrefix("4 "))
        XCTAssertEqual(view.readout(weekday: 7, hour: 3, hoursPerRow: 1, metric: .mean)?.value, "60")
        // its block, 03:00–06:00
        XCTAssertEqual(view.readout(weekday: 7, hour: 4, hoursPerRow: 3, metric: .low)?.value, "33%")
        let empty = view.readout(weekday: 1, hour: 12, hoursPerRow: 1, metric: .inRange)!
        XCTAssertFalse(empty.hasData)
        XCTAssertEqual(empty.value, "–")
        let few = view.readout(weekday: 2, hour: 8, hoursPerRow: 1, metric: .inRange)!
        XCTAssertTrue(few.isFew)
        XCTAssertNil(view.readout(weekday: 8, hour: 0, hoursPerRow: 1, metric: .inRange))

        // workdays vs weekends: Mon–Fri, Sat–Sun
        XCTAssertEqual(view.workdays?.name, names.shortWeekdaySymbols[1] + "–" + names.shortWeekdaySymbols[5])
        XCTAssertEqual(view.weekend?.name, names.shortWeekdaySymbols[6] + "–" + names.shortWeekdaySymbols[0])
        XCTAssertEqual(view.summaryRows.count, 3)
        XCTAssertEqual(view.summaryRows[1].workdays, "0%")
        XCTAssertEqual(view.summaryRows[1].weekend, "2%")

        // limited: recorded since the middle of the period, a Days row and the mark
        let since = day(10)
        let late = series.filter { $0.time >= since }
        let limited = Stat.Weekday(
            Stat.WeekdayResult(
                Engine.weekdayHours(
                    weighed(late),
                    days: Engine.weekdayDays(weeks: 4, today: today, calendar: names),
                    bands: settings.bands,
                    calendar: names
                ),
                period: .weeks4
            ),
            settings: settings,
            calendar: names
        )
        XCTAssertNotNil(limited.limitedNote)
        XCTAssertEqual(limited.tableRows.count, 6)
        XCTAssertEqual(limited.tableRows.last?.values, ["3", "2", "2", "2", "3", "3", "3"])
        XCTAssertEqual(
            limited.countNote,
            String(format: NSLocalizedString("%@ of each weekday", comment: ""), Stat.Weekday.countRange(2, 3))
        )
        XCTAssertTrue(limited.barsFootnote.contains(Stat.Trace.dayTitle(since)))
        XCTAssertEqual(view.legends[.inRange]?.title, "% in range")
        XCTAssertEqual(view.legends[.mean]?.title, StatsFormatting.unit(.mgdL))
    }

    /// A weekday without readings in the period (every Wednesday missing): dashes, no bar, no readout; limited, and the
    /// footnote without a recording start (it began with the period).
    @MainActor func testWeekdayWithoutDaysAndTheLimitedFootnote() {
        let wednesdays = [day(1), day(8), day(15), day(22)]
        let names = weekdayCalendar("en_US")
        let result = Stat.WeekdayResult(
            weekdayPooled(weekdaySeries(skipping: wednesdays), weeks: 4, today: day(28), calendar: names),
            period: .weeks4
        )
        XCTAssertEqual(result.daysWithData, [4, 4, 0, 4, 4, 4, 4])
        XCTAssertTrue(result.isLimited)
        XCTAssertNil(result.recordedSince)
        XCTAssertFalse(result.weekdays[2].hasData)
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        let view = Stat.Weekday(result, settings: Stat.StatsSettings(freeAPSSettings), calendar: names)
        XCTAssertEqual(view.tableRows[1].values[2], "–")
        XCTAssertEqual(view.tableRows.last?.values[2], "0")
        XCTAssertEqual(view.bars.parts[2], [])
        XCTAssertEqual(view.heatmap(.inRange, hoursPerRow: 1)?.cells[2].allSatisfy { $0.step == nil }, true)
        XCTAssertEqual(view.readout(weekday: 4, hour: 10, hoursPerRow: 1, metric: .inRange)?.hasData, false)
        let expected = String(
            format: NSLocalizedString(
                "Readings on %1$@ of each weekday, not the %2$d the period holds, so one day weighs a lot.",
                comment: ""
            ),
            Stat.Weekday.countRange(0, 4),
            4
        )
        XCTAssertEqual(view.barsFootnote, expected)
    }

    /// The heatmap's geometry: the weekend's wider gap, the columns' targets covering the grid without a gap, the row
    /// under a point (a gap between rows is the row above it).
    func testWeekdayGridLayout() {
        let layout = WeekdayGridLayout(width: 280, columns: 7, rows: 24, rowHeight: 15, weekendStart: 5)
        let cell = layout.cellWidth
        XCTAssertEqual(cell, (280 - 12 - 6) / 7, accuracy: 1E-9)
        XCTAssertEqual(layout.x(0), 0)
        XCTAssertEqual(layout.x(4), 4 * (cell + 2), accuracy: 1E-9)
        XCTAssertEqual(layout.x(5), 5 * (cell + 2) + 6, accuracy: 1E-9)
        XCTAssertEqual(layout.x(6) + cell, 280, accuracy: 1E-9)
        XCTAssertEqual(layout.height, 24 * 15 + 23)
        XCTAssertEqual(layout.target(0).minX, 0)
        for column in 0 ..< 6 {
            let target = layout.target(column)
            XCTAssertEqual(target.minX + target.width, layout.target(column + 1).minX, accuracy: 1E-9, "\(column)")
        }
        let last = layout.target(6)
        XCTAssertEqual(last.minX + last.width, 280, accuracy: 1E-9)
        // the weekend's gap (8 pt) split between its neighbours: each 3 pt wider than across a 2 pt gap; the last
        // column has nothing on its right
        XCTAssertEqual(layout.target(3).width, cell + 2, accuracy: 1E-9)
        XCTAssertEqual(layout.target(4).width, cell + 5, accuracy: 1E-9)
        XCTAssertEqual(layout.target(5).width, cell + 5, accuracy: 1E-9)
        XCTAssertEqual(layout.target(6).width, cell + 1, accuracy: 1E-9)
        XCTAssertEqual(layout.row(at: 0), 0)
        XCTAssertEqual(layout.row(at: 15.5), 0)
        XCTAssertEqual(layout.row(at: 16), 1)
        XCTAssertEqual(layout.row(at: -3), 0)
        XCTAssertEqual(layout.row(at: 10000), 23)
        XCTAssertEqual(layout.row(at: .nan), 0)
        let blocks = WeekdayGridLayout(width: 280, columns: 7, rows: 8, rowHeight: 44, weekendStart: 7)
        XCTAssertEqual(blocks.cellWidth, (280 - 12) / 7, accuracy: 1E-9)
        XCTAssertEqual(blocks.x(5), 5 * (blocks.cellWidth + 2), accuracy: 1E-9)
        XCTAssertEqual(blocks.row(at: 45 * 3 + 44.5), 3)
        XCTAssertEqual(blocks.row(at: 45 * 7), 7)
    }

    /// The selection across the switch of the rows (an hour, a 3-hour block): a block steps from its first hour, the
    /// hours go on from it.
    @MainActor func testWeekdaySelectionAcrossHoursAndBlocks() {
        let selection = WeekdaySelection()
        selection.select(weekday: 2, hour: 11)
        // blocks: 09–12, the next is 12–15, the previous 06–09 from there
        selection.step(by: 1, hoursPerRow: 3)
        XCTAssertEqual(selection.hour, 12)
        selection.step(by: -1, hoursPerRow: 3)
        XCTAssertEqual(selection.hour, 9)
        // hours again: on from 09:00
        selection.step(by: -1, hoursPerRow: 1)
        XCTAssertEqual(selection.hour, 8)
        selection.select(weekday: 2, hour: 23)
        selection.step(by: 1, hoursPerRow: 3)
        XCTAssertEqual(selection.hour, 0)
        selection.step(by: -1, hoursPerRow: 3)
        XCTAssertEqual(selection.hour, 21)
        XCTAssertEqual(selection.weekday, 2)
    }

    // MARK: - Tabs

    /// The views, in order (no Loop tab: the Loops screen replaces it); the Day tab has no period (its day selector
    /// replaces it), Weekly its 13 weeks only (no control), the others theirs.
    func testTabsAndTheirPeriods() {
        XCTAssertEqual(
            StatsTab.allCases,
            [
                .overview, .trace, .agp, .goodBadDays, .daily, .hourOfDay, .weekday, .weekly, .insulin, .patches,
                .meals, .cgmOverview, .cgmSensors, .cgmSmoothing
            ]
        )
        XCTAssertEqual(
            StatsTab.allCases.filter(\.isGlucose),
            [.overview, .trace, .agp, .goodBadDays, .daily, .hourOfDay, .weekday, .weekly]
        )
        XCTAssertEqual(StatsTab.overview.validPeriods, StatsPeriod.homeRanges)
        XCTAssertEqual(StatsTab.trace.validPeriods, [])
        XCTAssertEqual(StatsTab.agp.validPeriods, [.days7, .days14, .days30, .days90])
        XCTAssertEqual(StatsTab.daily.validPeriods, [.days90])
        XCTAssertEqual(StatsTab.hourOfDay.validPeriods, [.days7, .days14, .days30, .days90])
        XCTAssertEqual(StatsTab.weekly.validPeriods, [.weeks13])
        XCTAssertEqual(StatsTab.weekday.validPeriods, [.weeks4, .weeks8, .weeks13])
        XCTAssertEqual(StatsTab.allCases.filter(\.isCGM), [.cgmOverview, .cgmSensors, .cgmSmoothing])
        for tab in StatsTab.allCases.filter(\.isCGM) {
            XCTAssertEqual(tab.validPeriods, [.days7, .days14, .days30, .days90], "\(tab)")
        }
        XCTAssertEqual(StatsTab.allCases.filter { !$0.hasPeriodControl }, [.trace, .daily, .weekly])
    }

    /// Weekly is the last 13 weeks whatever the period picked elsewhere: the preferred period maps to 13 weeks there
    /// (and stays as it is: the other views show it again).
    func testWeeklyIsThirteenWeeks() {
        for preferred in StatsPeriod.allCases {
            XCTAssertEqual(Stat.StateModel.nearest(preferred, in: StatsTab.weekly.validPeriods), .weeks13, "\(preferred)")
        }
        XCTAssertEqual(StatsPeriod.weeks13.weekCount, 13)
        XCTAssertFalse(StatsTab.weekly.hasPeriodControl)
    }

    /// By weekday (after By hour, `square.grid.3x3`) has whole weeks, 4, 8 and 13, a period of its own: it shows its own
    /// whatever the preferred one, a pick there leaves the preferred one (the other views') as it is, and a pick
    /// elsewhere leaves its own.
    @MainActor func testByWeekdayHasAPeriodOfItsOwn() {
        typealias Model = Stat.StateModel
        XCTAssertEqual(
            StatsTopic.glucose.views.firstIndex(of: .weekday),
            StatsTopic.glucose.views.firstIndex(of: .hourOfDay)! + 1
        )
        XCTAssertEqual(StatsTab.weekday.topic, .glucose)
        XCTAssertTrue(StatsTab.weekday.usesBands)
        XCTAssertTrue(StatsTab.weekday.hasPeriodControl)
        XCTAssertEqual(StatsTab.weekday.validPeriods, StatsPeriod.weekdayPeriods)
        XCTAssertEqual(StatsPeriod.weekdayPeriods.map(\.weekCount), [4, 8, 13])
        XCTAssertEqual(StatsPeriod.weekdayPeriods.map(\.calendarDayCount), [28, 56, 91])
        XCTAssertEqual(
            StatsPeriod.weekdayPeriods.map { StatsFormatting.weeksLabel($0) },
            ["4", "8", "13"].map { String(format: NSLocalizedString("%d wk", comment: ""), Int($0)!) }
        )
        XCTAssertEqual(StatsViewMenu.systemImage(.weekday), "square.grid.3x3")
        XCTAssertNotNil(UIImage(systemName: StatsViewMenu.systemImage(.weekday)))
        XCTAssertEqual(StatsViewMenu.title(.weekday), NSLocalizedString("By weekday", comment: ""))

        // its own period, whatever the preferred one (8 weeks when Statistics opens)
        for preferred in StatsPeriod.allCases {
            for own in StatsPeriod.weekdayPeriods {
                XCTAssertEqual(Model.shownPeriod(on: .weekday, preferred: preferred, weekday: own), own, "\(preferred)")
            }
        }
        // a pick on By weekday: the preferred one stays, so every other view shows what it showed
        let picked = Model.picking(.weeks4, on: .weekday, preferred: .days14, weekday: .weeks8)
        XCTAssertEqual(picked.preferred, .days14)
        XCTAssertEqual(picked.weekday, .weeks4)
        // Good & bad days has a period of its own too (`GoodBadDaysTabsTests`)
        for tab in StatsTab.allCases where tab != .weekday && tab != .goodBadDays {
            XCTAssertEqual(
                Model.shownPeriod(on: tab, preferred: picked.preferred, weekday: picked.weekday),
                Model.shownPeriod(on: tab, preferred: .days14, weekday: .weeks8),
                "\(tab)"
            )
            XCTAssertEqual(
                Model.shownPeriod(on: tab, preferred: .days14, weekday: .weeks4),
                Model.nearest(.days14, in: tab.validPeriods)
            )
        }
        XCTAssertEqual(Model.picking(.weeks13, on: .weekday, preferred: .today, weekday: .weeks8).preferred, .today)
        // a period it doesn't offer changes nothing
        XCTAssertEqual(Model.picking(.days7, on: .weekday, preferred: .days14, weekday: .weeks8).weekday, .weeks8)
        // a pick elsewhere: By weekday's stays
        let elsewhere = Model.picking(.days30, on: .agp, preferred: .days14, weekday: .weeks4)
        XCTAssertEqual(elsewhere.preferred, .days30)
        XCTAssertEqual(elsewhere.weekday, .weeks4)
        // the week periods are never another view's: none of them offers one but Weekly its 13 weeks
        for tab in StatsTab.allCases where tab != .weekday && tab != .weekly {
            XCTAssertFalse(tab.validPeriods.contains { StatsPeriod.weekdayPeriods.contains($0) }, "\(tab)")
        }
    }

    /// The nearest valid period of each tab with a period; the Day tab keeps the preferred one as it is (it ignores
    /// it), so coming back to a tab with a period shows the same one as before.
    @MainActor func testTheNearestPeriodOfEachTab() {
        typealias Model = Stat.StateModel
        for preferred in StatsPeriod.allCases {
            XCTAssertEqual(Model.nearest(preferred, in: StatsTab.trace.validPeriods), preferred, "\(preferred)")
            for tab in StatsTab.allCases where tab != .trace {
                XCTAssertTrue(tab.validPeriods.contains(Model.nearest(preferred, in: tab.validPeriods)), "\(tab) \(preferred)")
            }
        }
        // Home's ranges open the Overview as they are
        for range in StatsPeriod.homeRanges {
            XCTAssertEqual(Model.nearest(range, in: StatsTab.overview.validPeriods), range)
        }
        // Today and 24 h count as one day: 7 d on the AGP and the Days tab; 1 mo as 35 days: 30 d
        XCTAssertEqual(Model.nearest(.today, in: StatsTab.agp.validPeriods), .days7)
        for preferred in StatsPeriod.allCases {
            XCTAssertEqual(Model.nearest(preferred, in: StatsTab.daily.validPeriods), .days90, "\(preferred)")
        }
        XCTAssertFalse(StatsTab.daily.hasPeriodControl)
        XCTAssertEqual(Model.nearest(.weeks13, in: StatsTab.agp.validPeriods), .days90)
        XCTAssertEqual(Model.nearest(.last24h, in: StatsTab.hourOfDay.validPeriods), .days7)
        XCTAssertEqual(Model.nearest(.weeks13, in: StatsTab.hourOfDay.validPeriods), .days90)
        // Weekly: 13 weeks for every period (`testWeeklyIsThirteenWeeks`); and back: 90 d (a 5 weeks one, 30 d)
        XCTAssertEqual(Model.nearest(.days14, in: StatsTab.weekly.validPeriods), .weeks13)
        XCTAssertEqual(Model.nearest(.weeks5, in: StatsTab.overview.validPeriods), .days30)
        XCTAssertEqual(Model.nearest(.weeks13, in: StatsTab.overview.validPeriods), .days90)
    }

    // MARK: - Day selector

    /// The selector's items: its days oldest -> newest, the last one today, then the 24 hours at the trailing end.
    func testDaySelectorItems() {
        typealias TraceDay = Stat.TraceDay
        XCTAssertEqual(TraceDay.selectorPeriod, .days90)
        XCTAssertEqual(TraceDay.items(days: []), [.last24h])
        XCTAssertEqual(TraceDay.items(days: [day(6)]), [.today, .last24h])
        XCTAssertEqual(
            TraceDay.items(days: (0 ... 6).map { day($0) }),
            (0 ... 5).map { TraceDay.day(day($0)) } + [.today, .last24h]
        )
    }

    /// A day picked (the selector, the stepper): today as `.today` (it follows midnight), a past day from its start, kept
    /// inside the selector's 90 days as midnight moves them on.
    func testDaySelectorSelection() {
        typealias TraceDay = Stat.TraceDay
        let today = day(6)
        func of(_ date: Date) -> TraceDay {
            TraceDay.of(date, today: today, calendar: calendar)
        }
        XCTAssertEqual(of(today), .today)
        XCTAssertEqual(of(today.addingTimeInterval(.hours(13))), .today)
        XCTAssertEqual(of(day(8)), .today)
        XCTAssertEqual(of(day(3)), .day(day(3)))
        XCTAssertEqual(of(day(3).addingTimeInterval(.hours(5))), .day(day(3)))
        // the 25-hour day
        XCTAssertEqual(of(day(5).addingTimeInterval(.hours(24.5))), .day(day(5)))

        func shown(_ pick: TraceDay, today: Date) -> TraceDay {
            pick.shown(today: today, calendar: calendar)
        }
        XCTAssertEqual(shown(.today, today: today), .today)
        XCTAssertEqual(shown(.last24h, today: today), .last24h)
        XCTAssertEqual(shown(.day(day(3)), today: today), .day(day(3)))
        // the oldest of the 90 days stays; one day older is kept at the oldest (midnight moved it out)
        let oldest = calendar.date(byAdding: .day, value: -89, to: today)!
        XCTAssertEqual(shown(.day(oldest), today: today), .day(oldest))
        let older = calendar.date(byAdding: .day, value: -1, to: oldest)!
        XCTAssertEqual(shown(.day(older), today: today), .day(oldest))
        // a picked day that has become today (the clock set back over midnight, then on again) is today
        XCTAssertEqual(shown(.day(today), today: today), .today)

        // every day of a Days period opens as itself on the Day tab: the Days periods are inside the selector's
        for period in StatsTab.agp.validPeriods {
            let count = period.calendarDayCount ?? 1
            for back in 0 ..< count {
                let date = calendar.date(byAdding: .day, value: -back, to: today)!
                let pick = of(date)
                XCTAssertEqual(pick, back == 0 ? .today : .day(date), "\(period) \(back)")
                XCTAssertEqual(shown(pick, today: today), pick, "\(period) \(back)")
            }
        }

        // the range computed: today is the day of the request, a past day itself, the 24 hours
        let requestedAt = today.addingTimeInterval(.hours(10))
        XCTAssertEqual(TraceDay.today.range(requestedAt: requestedAt, calendar: calendar), .day(today))
        XCTAssertEqual(TraceDay.day(day(3)).range(requestedAt: requestedAt, calendar: calendar), .day(day(3)))
        XCTAssertEqual(TraceDay.last24h.range(requestedAt: requestedAt, calendar: calendar), .last24h)
    }

    /// The selector's items (formatted off the main actor): its days with their in-range bars (today labelled so),
    /// then the 24 hours without a bar.
    func testTraceSelectorItems() {
        let strip = (0 ... 6).map { index in
            TraceStripDay(
                start: day(index),
                hasReadings: index != 2,
                inRangeFraction: index == 2 ? 0.3 : 0.5
            )
        }
        let items = Stat.TraceSelectorItem.items(strip)
        XCTAssertEqual(Stat.TraceSelectorItem.items([]), [])
        XCTAssertEqual(items.map(\.pick), Stat.TraceDay.items(days: strip.map(\.start)))
        // the day without readings: an empty bar; the 24 hours: none
        XCTAssertEqual(items.map(\.inRangeFraction), [0.5, 0.5, 0, 0.5, 0.5, 0.5, 0.5, nil])
        XCTAssertEqual(items.map(\.hasReadings), [true, true, false, true, true, true, true, false])
        let todayTitle = NSLocalizedString("Today", comment: "")
        XCTAssertEqual(items[6].title, todayTitle)
        XCTAssertEqual(items[6].caption, todayTitle)
        XCTAssertEqual(items[3].title, Stat.Trace.dayTitle(day(3)))
        XCTAssertEqual(items[3].caption, day(3).formatted(.dateTime.weekday(.abbreviated)))
        XCTAssertEqual(items[3].number, day(3).formatted(.dateTime.day()))
        XCTAssertEqual(items[7].title, NSLocalizedString("Last 24 hours", comment: ""))
        XCTAssertNil(items[7].caption)
    }

    /// The Trace's own pick from its range against now: just after midnight, today's trace computed before it is that
    /// day's, not today's.
    @MainActor func testTracePickFollowsItsOwnDay() {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.low = 70
        freeAPSSettings.high = 145
        let settings = Stat.StatsSettings(freeAPSSettings)
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        func trace(_ range: TraceRange, domain: DateInterval, at now: Date) -> Stat.Trace {
            Stat.Trace(
                Stat.TraceResult(
                    range: range,
                    domain: domain,
                    window: domain,
                    points: [],
                    axis: 40 ... 300,
                    ticks: [],
                    summary: summary(.today, [], now: now)
                ),
                settings: settings,
                now: now
            )
        }
        let todayDomain = DateInterval(start: today, end: Calendar.current.date(byAdding: .day, value: 1, to: today)!)
        let current = trace(.day(today), domain: todayDomain, at: now)
        XCTAssertEqual(current.pick, .today)
        XCTAssertEqual(current.title, NSLocalizedString("Today", comment: ""))
        XCTAssertNotNil(current.windowSubtitle)

        let yesterdayDomain = DateInterval(start: yesterday, end: today)
        let past = trace(.day(yesterday), domain: yesterdayDomain, at: now)
        XCTAssertEqual(past.pick, .day(yesterday))
        XCTAssertEqual(past.title, Stat.Trace.dayTitle(yesterday))
        XCTAssertNil(past.windowSubtitle)

        // yesterday's "today", shown a second after midnight: that day
        let late = trace(.day(yesterday), domain: yesterdayDomain, at: today.addingTimeInterval(1))
        XCTAssertEqual(late.pick, .day(yesterday))

        let last24h = trace(
            .last24h,
            domain: DateInterval(start: now.addingTimeInterval(-TimeInterval.hours(24)), end: now),
            at: now
        )
        XCTAssertEqual(last24h.pick, .last24h)
        XCTAssertEqual(last24h.title, NSLocalizedString("Last 24 hours", comment: ""))
        XCTAssertNotNil(last24h.windowSubtitle)
    }

    @MainActor func testDailyCardIsTheTracesDay() {
        let (series, now) = dailySeries
        for units in [GlucoseUnits.mgdL, .mmolL] {
            var freeAPSSettings = FreeAPSSettings()
            freeAPSSettings.units = units
            freeAPSSettings.low = 70
            freeAPSSettings.high = 145
            let settings = Stat.StatsSettings(freeAPSSettings)
            let c = compute(.days7, series, now: now, bands: settings.bands)
            let result = Stat.DailyResult(
                summary: Engine.summary(
                    days: c.days,
                    window: c.window,
                    endRule: c.summary.endRule,
                    period: .days7,
                    bands: settings.bands
                ),
                days: dailyDays(c, bands: settings.bands)
            )
            let daily = Stat.Daily(result, period: .days7, settings: settings)
            let overview = Stat.Overview(result.summary, period: .days7, settings: settings)
            XCTAssertEqual(daily.dateRange, overview.dateRange)

            for (index, shown) in result.days.enumerated() {
                let window = traceSummary(of: shown.day, c, bands: settings.bands).window
                let inside = c.w.filter { $0.time >= window.start && $0.time < window.end }
                let axis = Engine.glucoseAxis(highest: nil)
                let trace = Stat.Trace(
                    Stat.TraceResult(
                        range: .day(shown.day.start),
                        domain: shown.day,
                        window: window,
                        points: Engine.tracePoints(inside, axis: axis, bands: settings.bands),
                        axis: axis,
                        ticks: [],
                        summary: traceSummary(of: shown.day, c, bands: settings.bands)
                    ),
                    settings: settings
                )
                // the Trace's in-range note has the unit, as the Overview's
                XCTAssertEqual(trace.inRangeRange, overview.inRangeRange)

                let card = daily.card(at: index)
                XCTAssertEqual(card.title, Stat.Trace.dayTitle(shown.day.start))
                guard let numbers = card.numbers else {
                    XCTAssertTrue(inside.isEmpty)
                    XCTAssertEqual(trace.inRange, "–")
                    continue
                }
                XCTAssertEqual(numbers.inRange + "%", trace.inRange)
                XCTAssertEqual(numbers.inRangeRange, trace.inRangeRange)
                XCTAssertEqual(
                    [numbers.tirTitle, numbers.tir, numbers.titrTitle, numbers.titr, numbers.unit, numbers.mean, numbers.cv],
                    [trace.tirTitle, trace.tir, trace.titrTitle, trace.titr, trace.unit, trace.mean, trace.cv]
                )
                XCTAssertEqual(
                    String(format: NSLocalizedString("CGM coverage %@", comment: ""), numbers.coverage),
                    trace.coverage
                )
                XCTAssertEqual(numbers.below, StatsFormatting.duration(minutes: shown.secondsBelowLow / 60))
            }
            XCTAssertNil(daily.card(at: 2).numbers)

            // the chart: a slot for every day, bars only for the days with readings, the whole week at once
            let plot = daily.plot
            XCTAssertEqual(plot.days.map(\.day), result.days.map(\.day))
            XCTAssertEqual(plot.domain, DateInterval(start: day(0), end: day(7)))
            XCTAssertEqual(Set(plot.parts.map(\.day)), Set(result.days.filter(\.hasReadings).map(\.day.start)))
            XCTAssertEqual(plot.visibleDays(largeText: false), 7)
            // never more than the period's days (8 at large text, 7 here)
            XCTAssertEqual(plot.visibleDays(largeText: true), 7)
            XCTAssertEqual(plot.visibleLength(days: 7), plot.domain.duration)
            XCTAssertEqual(plot.leadingEdge(showing: 6, from: nil, visibleDays: 7), day(0))
            // the day strings come with the result
            XCTAssertEqual(result.labels.map(\.title), result.days.map { Stat.Trace.dayTitle($0.day.start) })
            XCTAssertEqual(plot.days.map(\.number), result.labels.map(\.number))
            XCTAssertEqual(plot.index(containing: day(5).addingTimeInterval(.hours(24.5))), 5)
            XCTAssertEqual(plot.levelLabels, ["0%", "50%", "100%"])
            // no room above the 100% (no dots), no card's colour under the opaque bands
            XCTAssertEqual(plot.yDomain, 0 ... 1)
            XCTAssertEqual(plot.days.map(\.top), result.days.map { $0.segments.last?.upper ?? 0 })
            XCTAssertEqual(plot.days.map(\.isMarked), result.days.map { _ in false })
            XCTAssertTrue(plot.opaqueFills)

            // the day shown: today without a pick, a picked day kept inside the period (today is kept as nil)
            let selection = DailySelection()
            let days = plot.dayIntervals
            XCTAssertEqual(selection.index(in: days), 6)
            selection.pick(3, in: days)
            XCTAssertEqual(selection.day, day(3))
            XCTAssertEqual(selection.index(in: days), 3)
            selection.pick(6, in: days)
            XCTAssertNil(selection.day)
            selection.select(day(-20))
            XCTAssertEqual(selection.index(in: days), 0)
            selection.select(day(9))
            XCTAssertEqual(selection.index(in: days), 6)
        }
    }

    // MARK: - Performance

    /// Reports, never fails on the time: how long the AGP view's computation takes for 90 days of 1-minute readings
    /// (about 130k), the way the service runs it per refresh: clean, weigh, the clock histograms with their pooled
    /// percentiles (`agp`), and the summary (the days, cold: computed from the readings, as without the day cache;
    /// warm: summed from the day aggregates, as with it). Printed as "AGP performance: ..."; the test target is usually
    /// built unoptimized (Debug), so read the numbers as an upper bound.
    func testAGPPerformanceOver90DaysOfOneMinuteReadings() {
        // a 90-day window across the change to CET, from the start of its first day, an hour of lookback before it
        let now = day(30).addingTimeInterval(.hours(12))
        let firstDay = day(-59)
        let start = firstDay.addingTimeInterval(-GlucoseStatistics.Config.lookback)
        let count = Int(now.timeIntervalSince(start) / 60)
        let series = points(from: start, every: .minutes(1), count: count) { index -> Int16 in
            let wave: Double = 60 * sin(Double(index) / 180)
            let noise = Double((index * 7919) % 41) - 20
            return Int16(140 + wave + noise)
        }

        let clock = ContinuousClock()
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1E15
        }

        var totals: [Double] = []
        for run in 1 ... 3 {
            var times: [(String, Double)] = []
            func timed<T>(_ name: String, _ work: () -> T) -> T {
                var result: T?
                times.append((name, milliseconds(clock.measure { result = work() })))
                return result!
            }

            let cleaned = timed("clean") { Engine.clean(series) }
            let w = timed("weigh") { Engine.weigh(cleaned) }
            let (end, endRule) = Engine.effectiveEndRule(w, now: now, calendar: calendar)
            let window = Engine.window(for: .days90, now: now, end: end, calendar: calendar)
            let bins = timed("agp") { Engine.agp(w, calendar: calendar, clippedTo: window) }
            let dayIntervals = Engine.days(for: .days90, window: window, calendar: calendar)
            let days = timed("days (cold)") { Engine.dayAggregates(w, days: dayIntervals) }
            let summary = timed("summary (warm)") { () -> GlucoseSummary in
                let counts = Engine.dayCounts(.days90, days: days)
                return Engine.summary(
                    days.reduce(GlucoseHistogram()) { $0 + $1.histogram },
                    window: window,
                    endRule: endRule,
                    calendarDays: counts.calendarDays,
                    daysWithData: counts.daysWithData,
                    bands: bands
                )
            }

            XCTAssertEqual(bins.count, 96)
            XCTAssertTrue(bins.allSatisfy { $0 != nil })
            XCTAssertEqual(summary.daysWithData, 90)
            XCTAssertEqual(summary.coveragePercent, 100)

            let total = times.reduce(0) { $0 + $1.1 }
            totals.append(total)
            let stages = times.map { String(format: "%@ %.1f ms", $0.0, $0.1) }.joined(separator: ", ")
            print(String(format: "AGP performance: %d readings, run %d: %@; total %.1f ms", w.count, run, stages, total))
        }
        print(String(format: "AGP performance: best total %.1f ms", totals.min() ?? 0))
    }

    // MARK: - Band edges everywhere (header, Live Activity, calendar)

    private func bandSettings(units: GlucoseUnits, low: Decimal, high: Decimal) -> FreeAPSSettings {
        var settings = FreeAPSSettings()
        settings.units = units
        settings.low = low
        settings.high = high
        return settings
    }

    /// mmol/L as the settings screen stores it (mg/dL)
    private func storedMmol(_ value: String) -> Decimal {
        Decimal(string: value)!.asMgdL
    }

    func testSettingsBandsRoundMgdlHalfUp() {
        XCTAssertEqual(StatsBands(settings: bandSettings(units: .mgdL, low: 70, high: Decimal(string: "180.4")!)).high, 180)
        XCTAssertEqual(StatsBands(settings: bandSettings(units: .mgdL, low: 70, high: Decimal(string: "180.5")!)).high, 181)
        XCTAssertEqual(StatsBands(settings: bandSettings(units: .mgdL, low: Decimal(string: "69.5")!, high: 180)).low, 70)
        XCTAssertEqual(StatsBands(settings: bandSettings(units: .mgdL, low: Decimal(string: "70.4")!, high: 180)).low, 70)
    }

    func testSettingsBandsGiveTheMmolEdges() {
        let bands = StatsBands(settings: bandSettings(units: .mmolL, low: storedMmol("3.9"), high: storedMmol("8.0")))
        XCTAssertEqual(bands.low, 70)
        XCTAssertEqual(bands.high, 145)
        XCTAssertEqual(bands, StatsBands(low: storedMmol("3.9"), high: storedMmol("8.0"), units: .mmolL))
        // 8.0 mmol/L stored as 144.14 mg/dL: the truncated and the rounded setting were 144, the edge is 145
        let stored = StatsBands(settings: bandSettings(units: .mmolL, low: 70, high: Decimal(string: "144.14")!))
        XCTAssertEqual(stored.high, 145)
    }

    @MainActor func testHeaderGlucoseColourFollowsTheBands() {
        let mgdl = StatsBands(settings: bandSettings(units: .mgdL, low: 70, high: Decimal(string: "180.4")!))
        let mgdlCases: [(Int, Color)] = [
            (0, .loopRed), (53, .loopRed), (69, .loopRed), (70, .loopGreen), (180, .loopGreen), (181, .loopYellow),
            (251, .loopYellow)
        ]
        for (value, colour) in mgdlCases {
            XCTAssertEqual(CurrentGlucoseView.glucoseColour(value, bands: mgdl), colour, "\(value) mg/dL")
        }
        let roundedUp = StatsBands(settings: bandSettings(units: .mgdL, low: 70, high: Decimal(string: "180.5")!))
        XCTAssertEqual(CurrentGlucoseView.glucoseColour(181, bands: roundedUp), .loopGreen)
        XCTAssertEqual(CurrentGlucoseView.glucoseColour(182, bands: roundedUp), .loopYellow)

        let mmol = StatsBands(settings: bandSettings(units: .mmolL, low: storedMmol("3.9"), high: storedMmol("8.0")))
        let mmolCases: [(Int, Color)] = [
            (69, .loopRed),
            (70, .loopGreen),
            (144, .loopGreen),
            (145, .loopGreen),
            (146, .loopYellow)
        ]
        for (value, colour) in mmolCases {
            XCTAssertEqual(CurrentGlucoseView.glucoseColour(value, bands: mmol), colour, "\(value) mg/dL")
        }
    }

    func testCalendarEmojiFollowsTheBands() {
        let mgdl = StatsBands(settings: bandSettings(units: .mgdL, low: 70, high: Decimal(string: "180.4")!))
        // before: `<= low` red, `>= high` orange; now the edges are in range
        let mgdlCases: [(Int, String)] = [(53, "🔴"), (69, "🔴"), (70, "🟢"), (180, "🟢"), (181, "🟠"), (251, "🟠")]
        for (value, emoji) in mgdlCases {
            XCTAssertEqual(BaseCalendarManager.glucoseEmoji(value, bands: mgdl), emoji, "\(value) mg/dL")
        }

        let mmol = StatsBands(settings: bandSettings(units: .mmolL, low: storedMmol("3.9"), high: storedMmol("8.0")))
        let mmolCases: [(Int, String)] = [(69, "🔴"), (70, "🟢"), (145, "🟢"), (146, "🟠")]
        for (value, emoji) in mmolCases {
            XCTAssertEqual(BaseCalendarManager.glucoseEmoji(value, bands: mmol), emoji, "\(value) mg/dL")
        }
    }

    func testLiveActivityReadingRangeIsInclusiveOfTheEdges() {
        typealias State = LiveActivityAttributes.ContentState
        // the edges as the bridge sends them
        let bands = StatsBands(settings: bandSettings(units: .mmolL, low: storedMmol("3.9"), high: storedMmol("8.0")))
        let low = Int16(clamping: bands.low)
        let high = Int16(clamping: bands.high)
        XCTAssertEqual(low, 70)
        XCTAssertEqual(high, 145)
        let cases: [(Int16, State.ReadingRange)] = [(39, .below), (69, .below), (70, .inRange), (145, .inRange), (146, .above)]
        for (value, range) in cases {
            XCTAssertEqual(State.readingRange(value, low: low, high: high), range, "\(value) mg/dL")
        }

        let mgdl = StatsBands(settings: bandSettings(units: .mgdL, low: 70, high: Decimal(string: "180.5")!))
        XCTAssertEqual(State.readingRange(181, low: Int16(clamping: mgdl.low), high: Int16(clamping: mgdl.high)), .inRange)
        XCTAssertEqual(State.readingRange(182, low: Int16(clamping: mgdl.low), high: Int16(clamping: mgdl.high)), .above)
    }

    func testLiveActivityStateOfAnOlderAppStillDecodes() throws {
        typealias State = LiveActivityAttributes.ContentState
        // a running activity's state from before: the same keys (no field was added), no readings or predictions,
        // and the truncated high setting (8.0 mmol/L -> 144) in place of the edge
        let json = """
        {"bg":"8.0","direction":"→","change":"+0.1","date":0,"iob":"1.2","cob":"20","loopDate":0,"eventual":"8.2",
        "mmol":true,"showChart":true,"watchChart":false,"watchPredictions":false,"watchDelta":true,"watchEventual":true,
        "chartLowThreshold":70,"chartHighThreshold":144}
        """
        let state = try JSONDecoder().decode(State.self, from: Data(json.utf8))
        XCTAssertNil(state.readings)
        XCTAssertNil(state.predictions)
        XCTAssertEqual(state.chartLowThreshold, 70)
        XCTAssertEqual(state.chartHighThreshold, 144)
        // read as edges until the next update replaces it
        XCTAssertEqual(state.readingRange(144), .inRange)
        XCTAssertEqual(state.readingRange(145), .above)

        let roundTripped = try JSONDecoder().decode(State.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(roundTripped, state)
    }

    // MARK: - Home Loops card

    private func loopRecord(_ start: Date, success: Bool = true) -> HomeLoopStats.Record {
        HomeLoopStats.Record(start: start, success: success)
    }

    private func homeLoops(
        _ period: StatsPeriod = .today,
        records: [HomeLoopStats.Record] = [],
        previousStart: Date? = nil,
        readings: [Date] = [],
        allowOneMinuteLoop: Bool = false,
        now: Date
    ) -> HomeLoopStats {
        HomeLoopStats.make(
            period: period,
            records: records,
            previousStart: previousStart,
            readings: readings,
            allowOneMinuteLoop: allowOneMinuteLoop,
            now: now,
            calendar: calendar
        )
    }

    /// `count` times `step` apart from `start`
    private func homeLoopTimes(from start: Date, every step: TimeInterval, count: Int) -> [Date] {
        (0 ..< count).map { start.addingTimeInterval(Double($0) * step) }
    }

    /// The card's counts: every "Success" record in the window (two in one slot both, a failed one not; the share per
    /// slot unchanged), and the CGM readings in it as read, not thinned (a 1-minute CGM's every one), exact duplicates
    /// once; an N-day range's summed over its days (`HomeLoopStats.make`, the raw read; the store's cached days are
    /// `assertHomeLoopsStore`'s).
    @MainActor func testHomeLoopsCardCountsLoopsAndReadings() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        // a 1-minute CGM: 60 readings, every one twice (a Nightscout import's saves), and one before the window
        let minutely = homeLoopTimes(from: Self.day0, every: .minutes(1), count: 60)
        let readings = minutely + minutely + [Self.day0.addingTimeInterval(-60)]
        // a loop on every slot's reading (thinned from the newest, 00:59, back: 00:04, 00:09 … 00:59): the 2nd slot's
        // failed, the 4th's ran again after its success
        var records = (0 ..< 12).map { loopRecord(minutely[4 + $0 * 5].addingTimeInterval(30), success: $0 != 1) }
        records.append(loopRecord(minutely[19].addingTimeInterval(90)))
        let stats = homeLoops(records: records, readings: readings, now: now)
        XCTAssertEqual(stats.readings, 60)
        XCTAssertEqual(stats.successfulLoops, 12)
        XCTAssertEqual(stats.records, 13)
        // the share per slot: 11 of 12
        XCTAssertEqual(stats.slots.count, 12)
        XCTAssertEqual(stats.slots.successes, 11)
        let content = HomeLoopsCard.Content(stats)
        XCTAssertEqual(content.counts, "12 loops · 60 readings")
        // the 1-minute loop: the same counts (only the slots change)
        let oneMinute = homeLoops(records: records, readings: readings, allowOneMinuteLoop: true, now: now)
        XCTAssertEqual(oneMinute.readings, 60)
        XCTAssertEqual(oneMinute.successfulLoops, 12)
        XCTAssertEqual(oneMinute.slots.count, 60)

        // an N-day range sums its days
        let history = homeLoopsHistory(from: day(-3), to: now)
        let days = homeLoops(.days7, records: history.records, readings: history.readings, now: now)
        let window = days.window
        let inWindow = history.readings.filter { HomeLoopStats.contains(window, $0, throughEnd: false) }
        XCTAssertEqual(days.readings, Set(inWindow).count)
        XCTAssertEqual(
            days.successfulLoops,
            history.records.filter { $0.success && HomeLoopStats.contains(window, $0.start, throughEnd: true) }.count
        )
        XCTAssertGreaterThan(days.successfulLoops, 0)
    }

    /// The card's range, 24 h: the counts over both days' parts, each record and reading once: a loop just after
    /// midnight (in the last slot of yesterday's part, its lookahead) is today's only; the readings either side of
    /// midnight each once, their duplicates too.
    @MainActor func testHomeLoopsCardCountsOver24Hours() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        // every 5 min from 23:00 yesterday to 00:55: 12 before midnight, 12 after; every one twice; one before the
        // window
        let fiveMinutes = homeLoopTimes(from: Self.day0.addingTimeInterval(-.hours(1)), every: .minutes(5), count: 24)
        let dayAgo = now.addingTimeInterval(-.hours(24))
        let readings = fiveMinutes + fiveMinutes + [dayAgo.addingTimeInterval(-60)]
        // a loop 30 s after each reading; 23:55's failed and ran again at 00:02 (yesterday's last slot's lookahead)
        var records = fiveMinutes.enumerated().map { index, reading in
            loopRecord(reading.addingTimeInterval(30), success: index != 11)
        }
        records.append(loopRecord(Self.day0.addingTimeInterval(.minutes(2))))
        // before the window: not counted
        records.append(loopRecord(dayAgo.addingTimeInterval(-30)))
        let stats = homeLoops(.last24h, records: records, readings: readings, now: now)
        XCTAssertEqual(stats.window, DateInterval(start: dayAgo, end: now))
        XCTAssertLessThan(stats.window.start, Self.day0)
        XCTAssertEqual(stats.todayStart, Self.day0)
        XCTAssertEqual(stats.readings, 24)
        // 23 of the 24 after the readings, and the one at 00:02
        XCTAssertEqual(stats.successfulLoops, 24)
        XCTAssertEqual(stats.records, 25)
        let content = HomeLoopsCard.Content(stats)
        XCTAssertEqual(content.counts, "24 loops · 24 readings")
        // today's part alone: Today's counts
        let today = homeLoops(.today, records: records, readings: readings, now: now)
        XCTAssertEqual(today.readings, 12)
        XCTAssertEqual(today.successfulLoops, 13)
    }

    func testHomeLoopsPercentIsSuccessesOverReadings() {
        let now = Self.day0.addingTimeInterval(.hours(2))
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 24)
        // a loop 30 s after every reading, two of them failed
        let records = readings.enumerated().map { index, reading in
            loopRecord(reading.addingTimeInterval(30), success: index != 7 && index != 15)
        }
        let stats = homeLoops(records: records, readings: readings, now: now)
        XCTAssertEqual(stats.window, DateInterval(start: Self.day0, end: now))
        XCTAssertEqual(stats.slots, HomeLoopStats.Slots(count: 24, successes: 22, failed: 2, missed: 0))
        XCTAssertEqual(stats.records, 24)
        XCTAssertEqual(stats.percent!, 22.0 / 24 * 100, accuracy: 1E-9)
        XCTAssertFalse(stats.isEmpty)
        // every 5 minutes, the newest 4.5 min ago: no gap
        XCTAssertNil(stats.longestGap)
        XCTAssertEqual(stats.markedGaps, [])
        XCTAssertNil(stats.ongoingGap)
    }

    /// Two loops in a slot are one success: the share is of the readings, never above 100 %.
    func testHomeLoopsLoopsInASlotCountOnce() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 12)
        // twice as many loops as readings
        let records = homeLoopTimes(from: Self.day0.addingTimeInterval(30), every: .minutes(2.5), count: 24)
            .map { loopRecord($0) }
        let stats = homeLoops(records: records, readings: readings, now: now)
        XCTAssertEqual(stats.slots, HomeLoopStats.Slots(count: 12, successes: 12, failed: 0, missed: 0))
        XCTAssertEqual(stats.records, 24)
        XCTAssertEqual(stats.percent, 100)
        XCTAssertEqual(stats.buckets.map(\.fraction), [1, 1])
    }

    func testHomeLoopsCountOnlyTheWindow() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        // records in [start, now]: at the window's start and at now inside, before it not;
        // readings in [start, now): at the window's start inside, at now not. The one slot, from the reading at the
        // start to now, takes both loops
        let stats = homeLoops(
            records: [loopRecord(Self.day0), loopRecord(Self.day0.addingTimeInterval(-60)), loopRecord(now)],
            readings: [Self.day0, now, now.addingTimeInterval(60), Self.day0.addingTimeInterval(-60)],
            now: now
        )
        XCTAssertEqual(stats.records, 2)
        XCTAssertEqual(stats.slots, HomeLoopStats.Slots(count: 1, successes: 1, failed: 0, missed: 0))
        XCTAssertEqual(stats.buckets.map(\.successes), [1, 0])
        XCTAssertEqual(stats.buckets.map(\.slots), [1, 0])
    }

    func testHomeLoopsReadingsALoopCanRunOn() {
        // 1-minute readings for an hour, one saved twice
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(1), count: 60) +
            [Self.day0.addingTimeInterval(.minutes(10))]
        // the 5-minute loop runs on oref's readings: at least 4.5 min apart, from the newest one on
        let thinned = HomeLoopStats.expectedReadings(readings, allowOneMinuteLoop: false)
        XCTAssertEqual(thinned, stride(from: 59, through: 4, by: -5).map { Self.day0.addingTimeInterval(.minutes(Double($0))) })
        XCTAssertEqual(thinned.count, 12)
        // the 1-minute loop on every reading, the duplicate once
        XCTAssertEqual(HomeLoopStats.expectedReadings(readings, allowOneMinuteLoop: true).count, 60)
        // 5-minute readings are all kept
        let fiveMinute = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 12)
        XCTAssertEqual(HomeLoopStats.expectedReadings(fiveMinute, allowOneMinuteLoop: false).count, 12)

        let now = Self.day0.addingTimeInterval(.hours(1))
        XCTAssertEqual(homeLoops(readings: readings, now: now).slots.count, 12)
        XCTAssertEqual(homeLoops(readings: readings, allowOneMinuteLoop: true, now: now).slots.count, 60)

        // each day thinned from its own newest reading: 23:00-00:59 in the 24 h range, 12 + 12
        let acrossMidnight = homeLoopTimes(
            from: Self.day0.addingTimeInterval(-TimeInterval.hours(1)),
            every: .minutes(1),
            count: 120
        )
        let twoDays = homeLoops(.last24h, readings: acrossMidnight, now: now)
        XCTAssertEqual(twoDays.slots.count, 24)
        XCTAssertEqual(twoDays.buckets.map(\.slots).reduce(0, +), 24)
    }

    func testHomeLoopsEmpty() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        let stats = homeLoops(now: now)
        XCTAssertTrue(stats.isEmpty)
        XCTAssertNil(stats.percent)
        XCTAssertEqual(stats.slots.count, 0)
        XCTAssertEqual(stats.buckets.count, 2)
        XCTAssertEqual(stats.buckets.map(\.fraction), [nil, nil])
        XCTAssertNil(stats.longestGap)
        XCTAssertEqual(stats.markedGaps, [])
        XCTAssertNil(stats.ongoingGap)

        // readings but no loop: 0 %
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 12)
        XCTAssertEqual(homeLoops(readings: readings, now: now).percent, 0)
        XCTAssertTrue(homeLoops(readings: readings, now: now).isEmpty)

        // just after midnight, a range without readings
        XCTAssertEqual(homeLoops(now: Self.day0).buckets, [])
    }

    func testHomeLoopsOngoingGapWithoutALoopInTheWindow() {
        // Today at 00:20, the last loop yesterday at 23:50
        let now = Self.day0.addingTimeInterval(.minutes(20))
        let last = Self.day0.addingTimeInterval(-TimeInterval.minutes(10))
        let stats = homeLoops(previousStart: last, now: now)
        let gap = LoopGap(start: last, end: now, loopInterval: .minutes(5), ongoing: true)
        XCTAssertTrue(stats.isEmpty)
        XCTAssertEqual(stats.ongoingGap, gap)
        XCTAssertEqual(stats.longestGap, gap)
        XCTAssertEqual(stats.markedGaps, [gap])

        // 12 minutes: not yet (the header's ring covers it); from 15 minutes on
        let early = homeLoops(previousStart: last, now: Self.day0.addingTimeInterval(.minutes(2)))
        XCTAssertNil(early.ongoingGap)
        XCTAssertNil(early.longestGap)
        XCTAssertEqual(
            homeLoops(previousStart: last, now: last.addingTimeInterval(.minutes(15))).ongoingGap?.duration,
            TimeInterval.minutes(15)
        )
    }

    func testHomeLoopsGaps() {
        let now = Self.day0.addingTimeInterval(.hours(2))
        // every 5 minutes from 00:01, but 00:26 (a 10-minute gap), 00:51-01:01 (20 minutes), and none after 01:46
        let starts = (0 ... 21).filter { ![5, 10, 11, 12].contains($0) }
            .map { Self.day0.addingTimeInterval(.minutes(1 + 5 * Double($0))) }
        let start = { (k: Double) in Self.day0.addingTimeInterval(.minutes(1 + 5 * k)) }
        let stats = homeLoops(records: starts.map { loopRecord($0) }, now: now)

        XCTAssertEqual(stats.longestGap, LoopGap(start: start(9), end: start(13), loopInterval: .minutes(5), ongoing: false))
        // 15 minutes or more
        XCTAssertEqual(stats.markedGaps.map(\.start), [start(9)])
        // 14 minutes since the last loop: not ongoing yet
        XCTAssertNil(stats.ongoingGap)

        // from 15 minutes on it is ongoing (up to the read's now), and counts for the longest
        let fifteen = homeLoops(records: starts.map { loopRecord($0) }, now: start(21).addingTimeInterval(.minutes(15)))
        XCTAssertEqual(fifteen.ongoingGap?.duration, TimeInterval.minutes(15))
        XCTAssertEqual(fifteen.ongoingGap?.end, fifteen.window.end)
        XCTAssertEqual(fifteen.longestGap?.start, start(9))
        let later = homeLoops(records: starts.map { loopRecord($0) }, now: start(21).addingTimeInterval(.minutes(25)))
        XCTAssertEqual(later.longestGap?.start, start(21))
        XCTAssertTrue(later.longestGap?.ongoing ?? false)
        XCTAssertEqual(later.markedGaps.map(\.start), [start(9), start(21)])
    }

    func testHomeLoopsGapsByDay() {
        // the 1-minute loop: the cadence comes from the day's own starts, a 3-minute gap counts
        let starts = homeLoopTimes(from: Self.day0.addingTimeInterval(30), every: .minutes(1), count: 60)
            .filter { $0 != Self.day0.addingTimeInterval(.minutes(30.5)) && $0 != Self.day0.addingTimeInterval(.minutes(31.5)) }
        let oneMinute = homeLoops(
            records: starts.map { loopRecord($0) },
            allowOneMinuteLoop: true,
            now: Self.day0.addingTimeInterval(.hours(1))
        )
        XCTAssertEqual(oneMinute.longestGap?.start, Self.day0.addingTimeInterval(.minutes(29.5)))
        XCTAssertEqual(oneMinute.longestGap?.duration, TimeInterval.minutes(3))
        // the 5-minute loop doesn't count it
        XCTAssertNil(homeLoops(records: starts.map { loopRecord($0) }, now: Self.day0.addingTimeInterval(.hours(1))).longestGap)

        // across midnight (7 d): yesterday's last loop at 23:50, today's first at 00:20
        let yesterday = homeLoopTimes(from: day(-1), every: .minutes(5), count: 287).map { loopRecord($0) }
        let today = homeLoopTimes(from: Self.day0.addingTimeInterval(.minutes(20)), every: .minutes(5), count: 12)
            .map { loopRecord($0) }
        let stats = homeLoops(.days7, records: yesterday + today, now: Self.day0.addingTimeInterval(.hours(1) + .minutes(16)))
        XCTAssertEqual(yesterday.last?.start, Self.day0.addingTimeInterval(-TimeInterval.minutes(10)))
        XCTAssertEqual(
            stats.longestGap,
            LoopGap(
                start: Self.day0.addingTimeInterval(-TimeInterval.minutes(10)),
                end: today[0].start,
                loopInterval: .minutes(5),
                ongoing: false
            )
        )
        XCTAssertEqual(stats.markedGaps.count, 1)
    }

    func testHomeLoopsGapIntoTheWindow() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        let first = Self.day0.addingTimeInterval(.minutes(1))
        let starts = homeLoopTimes(from: first, every: .minutes(5), count: 12)
        // the gap from the last loop before the window runs into it, whole
        let gap = LoopGap(
            start: Self.day0.addingTimeInterval(-TimeInterval.minutes(30)),
            end: first,
            loopInterval: .minutes(5),
            ongoing: false
        )
        let stats = homeLoops(records: starts.map { loopRecord($0) }, previousStart: gap.start, now: now)
        XCTAssertEqual(stats.longestGap, gap)
        XCTAssertEqual(stats.markedGaps, [gap])
        XCTAssertNil(stats.ongoingGap)
        // the start before the window only links up: no gap when it is a loop's distance away
        let close = homeLoops(
            records: starts.map { loopRecord($0) },
            previousStart: Self.day0.addingTimeInterval(-TimeInterval.minutes(4)),
            now: now
        )
        XCTAssertNil(close.longestGap)
    }

    func testHomeLoopsSingleStart() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        let stale = homeLoops(records: [loopRecord(now.addingTimeInterval(-TimeInterval.minutes(20)))], now: now)
        XCTAssertEqual(stale.ongoingGap?.start, now.addingTimeInterval(-TimeInterval.minutes(20)))
        XCTAssertEqual(stale.ongoingGap?.duration, TimeInterval.minutes(20))
        XCTAssertEqual(stale.markedGaps.count, 1)

        let recent = homeLoops(records: [loopRecord(now.addingTimeInterval(-TimeInterval.minutes(5)))], now: now)
        XCTAssertNil(recent.longestGap)
        XCTAssertNil(recent.ongoingGap)
    }

    /// A slot with only failed records is failed, not a loop; the card says nothing more of them (the header shows the
    /// loop status), and an ongoing gap counts from the newest record, failed or not.
    func testHomeLoopsFailedRecords() {
        let starts = homeLoopTimes(from: Self.day0.addingTimeInterval(.minutes(1)), every: .minutes(5), count: 7)
        let readings = starts.map { $0.addingTimeInterval(-30) }
        let now = starts.last!.addingTimeInterval(.minutes(1))
        let failing = homeLoops(
            records: starts.enumerated().map { loopRecord($1, success: $0 < 4) },
            readings: readings,
            now: now
        )
        XCTAssertEqual(failing.slots, HomeLoopStats.Slots(count: 7, successes: 4, failed: 3, missed: 0))
        XCTAssertEqual(failing.records, 7)
        XCTAssertNil(failing.ongoingGap)

        let all = homeLoops(records: starts.map { loopRecord($0, success: false) }, readings: readings, now: now)
        XCTAssertEqual(all.slots.successes, 0)
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all.percent, 0)
        // records without readings: no slots, no share
        XCTAssertNil(homeLoops(records: starts.map { loopRecord($0, success: false) }, now: now).percent)

        let stopped = homeLoops(
            records: starts.enumerated().map { loopRecord($1, success: $0 < 4) },
            now: starts.last!.addingTimeInterval(.minutes(20))
        )
        XCTAssertEqual(stopped.ongoingGap?.start, starts.last)
    }

    /// Today and 24 h: half hours of the clock, cut at the window's start and at now (midnight an edge); the N-day ranges
    /// have no strip.
    func testHomeLoopsBucketsPerRange() {
        // 14:36
        let now = Self.day0.addingTimeInterval(TimeInterval.hours(14) + .minutes(36))
        for (period, count) in [(StatsPeriod.today, 30), (.last24h, 49)] {
            let window = Engine.window(for: period, now: now, end: now, calendar: calendar)
            let buckets = HomeLoopStats.bucketIntervals(of: window, calendar: calendar)
            XCTAssertEqual(buckets.count, count, "\(period)")
            // they cover the window, one after the other, the last one cut at now
            XCTAssertEqual(buckets.first?.start, window.start, "\(period)")
            XCTAssertEqual(buckets.last?.end, now, "\(period)")
            XCTAssertTrue(zip(buckets, buckets.dropFirst()).allSatisfy { $0.end == $1.start }, "\(period)")
            XCTAssertTrue(buckets.dropFirst().dropLast().allSatisfy { $0.duration == .minutes(30) }, "\(period)")
            XCTAssertEqual(homeLoops(period, now: now).buckets.map(\.interval), buckets, "\(period)")
        }
        // 24 h: yesterday 14:36-15:00 first, midnight an edge, 14:30-14:36 last
        let day = HomeLoopStats.bucketIntervals(
            of: Engine.window(for: .last24h, now: now, end: now, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(day.first?.duration, TimeInterval.minutes(24))
        XCTAssertTrue(day.contains { $0.start == Self.day0 })
        XCTAssertEqual(day.last?.duration, TimeInterval.minutes(6))
        for period in [StatsPeriod.days7, .days14, .days30, .days90] {
            XCTAssertEqual(homeLoops(period, now: now).buckets, [], "\(period)")
        }
    }

    func testHomeLoopsBucketCounts() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 12)
        // the first half hour a loop after every reading; the second: loops after 00:30 and 00:35, a failed one after
        // 00:45, none after 00:40 and 00:50, and one at now in the slot of 00:55
        let records = readings.prefix(6).map { loopRecord($0.addingTimeInterval(30)) } + [
            loopRecord(Self.day0.addingTimeInterval(.minutes(30.5))),
            loopRecord(Self.day0.addingTimeInterval(.minutes(35.5))),
            loopRecord(Self.day0.addingTimeInterval(.minutes(45.5)), success: false),
            loopRecord(now)
        ]
        let stats = homeLoops(records: records, readings: readings, now: now)
        XCTAssertEqual(stats.buckets.map(\.interval), [
            DateInterval(start: Self.day0, duration: .minutes(30)),
            DateInterval(start: Self.day0.addingTimeInterval(.minutes(30)), end: now)
        ])
        XCTAssertEqual(stats.buckets.map(\.successes), [6, 3])
        XCTAssertEqual(stats.buckets.map(\.slots), [6, 6])
        XCTAssertEqual(stats.buckets.map(\.fraction), [1, 0.5])
        XCTAssertEqual(stats.slots, HomeLoopStats.Slots(count: 12, successes: 9, failed: 1, missed: 2))
        XCTAssertEqual(stats.records, 10)
    }

    /// A day's slots are kept in 48 equal parts by their reading (half hours, 31 min 15 s on the 25-hour day), the
    /// Loops screen's strip.
    func testHomeLoopsDayParts() {
        for (start, hours) in [(Self.day0, 24.0), (Self.fallBack, 25.0)] {
            let day = DateInterval(start: start, duration: .hours(hours))
            let readings = homeLoopTimes(from: start, every: .minutes(5), count: Int(hours * 12))
            // a loop after every reading but those of the first part
            let partLength = day.duration / Double(HomeLoopStats.Config.dayParts)
            let records = readings.filter { $0.timeIntervalSince(start) >= partLength }
                .map { loopRecord($0.addingTimeInterval(30)) }
            let result = HomeLoopStats.day(
                day,
                interval: day,
                windowEnd: day.end.addingTimeInterval(.hours(1)),
                records: records,
                readings: readings,
                allowOneMinuteLoop: false
            )
            XCTAssertEqual(result.partSlots.count, 48)
            XCTAssertEqual(result.partSlots.reduce(0, +), readings.count, "\(hours) h")
            for part in 0 ..< 48 {
                let inside = readings.filter { HomeLoopStats.dayPart(of: $0, in: day) == part }.count
                XCTAssertEqual(result.partSlots[part], inside, "\(hours) h, part \(part)")
            }
            XCTAssertEqual(result.partSuccesses[0], 0)
            XCTAssertEqual(result.partSuccesses.dropFirst().reduce(0, +), records.count)
            XCTAssertEqual(HomeLoopStats.dayPart(of: start.addingTimeInterval(partLength - 1), in: day), 0)
            XCTAssertEqual(HomeLoopStats.dayPart(of: start.addingTimeInterval(partLength), in: day), 1)
            XCTAssertEqual(HomeLoopStats.dayPart(of: day.end.addingTimeInterval(-1), in: day), 47)
        }
    }

    func testHomeLoopsBucketsOnADSTDay() {
        // Today on the 23- and the 25-hour day, at 23:59: 46 and 50 half hours, the last one cut at now
        for (start, hours, count) in [(Self.springForward, 23.0, 46), (Self.fallBack, 25.0, 50)] {
            let now = start.addingTimeInterval(.hours(hours) - .minutes(1))
            let buckets = HomeLoopStats.bucketIntervals(of: DateInterval(start: start, end: now), calendar: calendar)
            XCTAssertEqual(buckets.count, count)
            XCTAssertTrue(buckets.dropLast().allSatisfy { $0.duration == .minutes(30) })
            XCTAssertEqual(buckets.last?.duration, TimeInterval.minutes(29))
        }

        // 24 h over the 25-hour night: half hours of the clock
        let night = Self.fallBack.addingTimeInterval(.hours(13))
        let buckets = HomeLoopStats.bucketIntervals(
            of: Engine.window(for: .last24h, now: night, end: night, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.duration }, TimeInterval.hours(24))
        XCTAssertTrue(buckets.allSatisfy { $0.duration <= .minutes(30) })
        XCTAssertTrue(buckets.contains { $0.start == Self.fallBack })
    }

    @MainActor func testHomeLoopsCardContent() {
        typealias Card = HomeLoopsCard
        XCTAssertEqual(Card.duration(.minutes(25)), "25 min")
        XCTAssertEqual(Card.duration(.minutes(59.6)), "1 h")
        XCTAssertEqual(Card.duration(.minutes(125)), "2 h 5 min")
        XCTAssertEqual(Card.duration(.minutes(7.4)), "7 min")

        let now = Self.day0.addingTimeInterval(.hours(2))
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 24)
        let records = readings.enumerated().map { index, reading in
            loopRecord(reading.addingTimeInterval(30), success: index != 7 && index != 15)
        }
        let content = Card.Content(homeLoops(records: records, readings: readings, now: now))
        XCTAssertEqual(content.range, StatsFormatting.label(.today))
        XCTAssertFalse(content.isEmpty)
        XCTAssertTrue(content.hasPercent)
        // the loops that ran and the readings, plain counts
        XCTAssertEqual(content.counts, "22 loops · 24 readings")
        XCTAssertEqual(Card.Content.loops(1, of: 1), "1 of 1 loop")
        XCTAssertEqual(Card.Content.counts(loops: 1, readings: 1), "1 loop · 1 reading")
        XCTAssertEqual(Card.Content.counts(loops: 0, readings: 1234), "0 loops · \(1234.formatted()) readings")
        XCTAssertNil(content.maxGap)
        // a column per bucket with readings, in fractions of the strip; the failed loops at 00:35 and 01:15
        XCTAssertEqual(content.columns.count, 4)
        let expectedColumns: [(x: Double, height: Double)] = [(0, 1), (0.25, 5.0 / 6), (0.5, 5.0 / 6), (0.75, 1)]
        for (column, expected) in zip(content.columns, expectedColumns) {
            XCTAssertEqual(column.x, expected.x, accuracy: 1E-9)
            XCTAssertEqual(column.width, 0.25, accuracy: 1E-9)
            XCTAssertEqual(column.height, expected.height, accuracy: 1E-3)
        }
        XCTAssertEqual(content.gapMarks, [])
        // the same result displays the same
        XCTAssertEqual(content, Card.Content(homeLoops(records: records, readings: readings, now: now)))

        // "100" from 99.95 on: 3999 of 4000
        let many = homeLoopTimes(from: day(-13), every: .minutes(5), count: 4000)
        let all = homeLoops(
            .days14,
            records: many.dropFirst().map { loopRecord($0.addingTimeInterval(30)) },
            readings: many,
            now: Self.day0.addingTimeInterval(.hours(23))
        )
        XCTAssertEqual(all.slots.successes, 3999)
        XCTAssertEqual(all.slots.count, 4000)
        XCTAssertEqual(Card.Content(all).percent, "100")

        // empty: no percent, no strip
        let empty = Card.Content(homeLoops(now: now))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.hasPercent)
        XCTAssertEqual(empty.percent, "–")
        XCTAssertEqual(empty.columns, [])

        // no loop for 25 minutes at the read: the longest gap, marked up to the strip's end (the read's now); no
        // warning, the header shows the loop status
        let starts = homeLoopTimes(from: Self.day0.addingTimeInterval(.minutes(1)), every: .minutes(5), count: 12)
        let stopped = Card
            .Content(homeLoops(records: starts.map { loopRecord($0) }, now: starts.last!.addingTimeInterval(.minutes(25))))
        XCTAssertEqual(stopped.maxGap, "25 min")
        XCTAssertEqual(stopped.gapMarks.count, 1)
        XCTAssertEqual(stopped.gapMarks.first?.end, 1)

        // failed loops: their readings got no loop, nothing more
        let failing = Card.Content(homeLoops(
            records: starts.enumerated().map { loopRecord($1, success: $0 < 9) },
            readings: starts.map { $0.addingTimeInterval(-30) },
            now: starts.last!.addingTimeInterval(.minutes(1))
        ))
        XCTAssertEqual(failing.counts, "9 loops · 12 readings")

        // a gap running into the window is marked from the window's start
        let into = Card.Content(homeLoops(
            records: starts.map { loopRecord($0) },
            previousStart: Self.day0.addingTimeInterval(-TimeInterval.minutes(30)),
            now: starts.last!.addingTimeInterval(.minutes(1))
        ))
        XCTAssertEqual(into.gapMarks.first?.start, 0)
        XCTAssertEqual(into.maxGap, "31 min")

        // no loop for 20 minutes after a 31-minute gap: the longest isn't the ongoing one, both marked
        let stoppedAfterLonger = Card.Content(homeLoops(
            records: starts.map { loopRecord($0) },
            previousStart: Self.day0.addingTimeInterval(-TimeInterval.minutes(30)),
            now: starts.last!.addingTimeInterval(.minutes(20))
        ))
        XCTAssertEqual(stoppedAfterLonger.maxGap, "31 min")
        XCTAssertEqual(stoppedAfterLonger.gapMarks.count, 2)
    }

    /// "Max gap" is shown from `minGapShown` (10 min) on: not without a gap, not below it.
    @MainActor func testHomeLoopsCardHidesShortGaps() {
        typealias Card = HomeLoopsCard
        XCTAssertEqual(Card.Content.minGapShown, TimeInterval.minutes(10))
        let first = Self.day0.addingTimeInterval(.minutes(1))
        let steady = homeLoopTimes(from: first, every: .minutes(5), count: 4)
        // loops every 5 min, then one `gap` after the last
        func card(gap: TimeInterval, nowAfter: TimeInterval = .minutes(1)) -> Card.Content {
            let last = steady.last!.addingTimeInterval(gap)
            return Card
                .Content(homeLoops(records: (steady + [last]).map { loopRecord($0) }, now: last.addingTimeInterval(nowAfter)))
        }

        // no gap above the cadence
        let none = card(gap: .minutes(5))
        XCTAssertNil(none.maxGap)

        // 9 min 59 s: hidden
        let short = card(gap: .minutes(9) + 59)
        XCTAssertNil(short.maxGap)

        // exactly 10 min: shown
        let ten = card(gap: .minutes(10))
        XCTAssertEqual(ten.maxGap, "10 min")

        // no loop for 9 min: no gap at all (an ongoing one counts only from `HomeLoopStats.Config.longGap`, 15 min,
        // so `minGapShown` isn't what hides it), unmarked
        let ongoing = Card.Content(homeLoops(
            records: steady.map { loopRecord($0) },
            now: steady.last!.addingTimeInterval(.minutes(9))
        ))
        XCTAssertNil(ongoing.maxGap)
        XCTAssertEqual(ongoing.gapMarks, [])
    }

    /// A reading reads the card again before the next loop only once the newest loop start is `minGapShown` back (the
    /// ongoing gap can show from there on); never without a loop start. The newest start is also one before the window.
    func testHomeLoopsReadingChangesTheCardOnlyThroughTheOngoingGap() {
        typealias Content = HomeLoopsCard.Content
        let starts = homeLoopTimes(from: Self.day0.addingTimeInterval(.minutes(1)), every: .minutes(5), count: 4)
        let last = starts.last!
        let previous = Self.day0.addingTimeInterval(-TimeInterval.minutes(10))
        XCTAssertEqual(
            homeLoops(records: starts.map { loopRecord($0) }, previousStart: previous, now: last.addingTimeInterval(60))
                .newestStart,
            last
        )
        // a failed record is a start too
        XCTAssertEqual(
            homeLoops(records: [loopRecord(last, success: false)], now: last.addingTimeInterval(60)).newestStart,
            last
        )
        XCTAssertEqual(homeLoops(previousStart: previous, now: Self.day0.addingTimeInterval(60)).newestStart, previous)
        XCTAssertNil(homeLoops(now: Self.day0.addingTimeInterval(60)).newestStart)

        XCTAssertFalse(Content.readingMayChange(newestStart: nil, now: last))
        XCTAssertFalse(Content.readingMayChange(newestStart: last, now: last))
        XCTAssertFalse(Content.readingMayChange(newestStart: last, now: last.addingTimeInterval(.minutes(9) + 59)))
        XCTAssertTrue(Content.readingMayChange(newestStart: last, now: last.addingTimeInterval(.minutes(10))))
        XCTAssertTrue(Content.readingMayChange(newestStart: last, now: last.addingTimeInterval(.hours(3))))
        // no gap the card shows before it
        XCTAssertNil(
            homeLoops(records: starts.map { loopRecord($0) }, now: last.addingTimeInterval(.minutes(9) + 59))
                .ongoingGap
        )
    }

    // MARK: Home Loops card: the day cache

    /// Records and readings in memory, the reads counted.
    private final class HomeLoopsFakeSource: HomeLoopsSource, @unchecked Sendable {
        private let lock = NSLock()
        private var storedRecords: [HomeLoopStats.Record]
        private var storedReadings: [Date]
        private var reads: [DateInterval] = []
        private var hold: Hold?

        /// a read of readings held until the test lets it go
        private struct Hold {
            let matches: @Sendable(DateInterval) -> Bool
            let arrived: AsyncStream<Void>.Continuation
            let release: AsyncStream<Void>
        }

        init(records: [HomeLoopStats.Record], readings: [Date]) {
            storedRecords = records
            storedReadings = readings
        }

        var records: [HomeLoopStats.Record] { lock.withLock { storedRecords } }
        var readings: [Date] { lock.withLock { storedReadings } }
        /// the ranges the readings were read for
        var readingReads: [DateInterval] { lock.withLock { reads } }

        func update(records: [HomeLoopStats.Record]? = nil, readings: [Date]? = nil) {
            lock.withLock {
                if let records { storedRecords = records }
                if let readings { storedReadings = readings }
            }
        }

        func loopRecords(in range: DateInterval, throughEnd: Bool) async throws -> [HomeLoopStats.Record] {
            records.filter { HomeLoopStats.contains(range, $0.start, throughEnd: throughEnd) }
        }

        func loopRecordCount(in range: DateInterval) async throws -> Int {
            records.filter { HomeLoopStats.contains(range, $0.start, throughEnd: false) }.count
        }

        func lastLoopStart(before date: Date) async throws -> Date? {
            records.map(\.start).filter { $0 < date }.max()
        }

        /// The next read of readings matching the predicate returns what was stored when it started, but only once
        /// `release` finishes; `arrived` finishes when it is held.
        func holdNextRead(
            _ matches: @escaping @Sendable(DateInterval) -> Bool
        ) -> (arrived: AsyncStream<Void>, release: AsyncStream<Void>.Continuation) {
            let (arrived, arrivedContinuation) = AsyncStream<Void>.makeStream()
            let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
            lock.withLock { hold = Hold(matches: matches, arrived: arrivedContinuation, release: release) }
            return (arrived, releaseContinuation)
        }

        func readingTimes(in range: DateInterval) async throws -> [Date] {
            let (result, held) = lock.withLock { () -> ([Date], Hold?) in
                reads.append(range)
                let result = storedReadings.filter { HomeLoopStats.contains(range, $0, throughEnd: false) }
                guard let current = hold, current.matches(range) else { return (result, nil) }
                hold = nil
                return (result, current)
            }
            if let held {
                held.arrived.finish()
                for await _ in held.release {}
            }
            return result
        }
    }

    /// 5-minute readings from `start` to `end`, a loop 30 s after each, every 50th failed, none 08:20-09:00 every day.
    private func homeLoopsHistory(from start: Date, to end: Date) -> (records: [HomeLoopStats.Record], readings: [Date]) {
        let readings = homeLoopTimes(from: start, every: .minutes(5), count: Int(end.timeIntervalSince(start) / 300))
        let records = readings.enumerated().compactMap { index, reading -> HomeLoopStats.Record? in
            let minute = calendar.component(.hour, from: reading) * 60 + calendar.component(.minute, from: reading)
            guard !(500 ..< 540).contains(minute) else { return nil }
            return loopRecord(reading.addingTimeInterval(30), success: index % 50 != 7)
        }
        return (records, readings)
    }

    /// The store's result against every day computed from the source's data.
    private func assertHomeLoopsStore(
        _ store: HomeLoopsStore,
        _ source: HomeLoopsFakeSource,
        _ period: StatsPeriod,
        now: Date,
        allowOneMinuteLoop: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let cached = await store.stats(period, allowOneMinuteLoop: allowOneMinuteLoop, now: now, calendar: calendar)
        let window = Engine.window(for: period, now: now, end: now, calendar: calendar)
        let uncached = homeLoops(
            period,
            records: source.records,
            previousStart: source.records.map(\.start).filter { $0 < window.start }.max(),
            readings: source.readings,
            allowOneMinuteLoop: allowOneMinuteLoop,
            now: now
        )
        XCTAssertEqual(cached, uncached, file: file, line: line)
    }

    func testHomeLoopsStoreReadsTodayOnceTheDaysAreCached() async {
        let now = Self.day0.addingTimeInterval(TimeInterval.hours(14) + .minutes(36))
        let history = homeLoopsHistory(from: day(-20), to: now)
        let source = HomeLoopsFakeSource(records: history.records, readings: history.readings)
        let store = HomeLoopsStore(source: source)

        // the first time: one read of the whole window, the 13 complete days stored
        await assertHomeLoopsStore(store, source, .days14, now: now)
        XCTAssertEqual(source.readingReads, [DateInterval(start: day(-13), end: now)])
        let cachedDays = await store.cachedDayCount
        XCTAssertEqual(cachedDays, 13)

        // then today only, with the same result as everything read
        let later = now.addingTimeInterval(.minutes(5))
        source.update(records: source.records + [loopRecord(later.addingTimeInterval(-60))])
        await assertHomeLoopsStore(store, source, .days14, now: later)
        XCTAssertEqual(source.readingReads.last, DateInterval(start: Self.day0, end: later))
        XCTAssertEqual(source.readingReads.count, 2)

        // 7 d reads today only too (its days are cached); the 1-minute loop is its own entry: read once
        await assertHomeLoopsStore(store, source, .days7, now: later)
        XCTAssertEqual(source.readingReads.last, DateInterval(start: Self.day0, end: later))
        await assertHomeLoopsStore(store, source, .days7, now: later, allowOneMinuteLoop: true)
        XCTAssertEqual(source.readingReads.last, DateInterval(start: day(-6), end: later))
        // Today and 24 h: read raw
        await assertHomeLoopsStore(store, source, .today, now: later)
        await assertHomeLoopsStore(store, source, .last24h, now: later)
    }

    func testHomeLoopsStoreReadsAChangedDayAgain() async {
        let now = Self.day0.addingTimeInterval(.hours(10))
        let history = homeLoopsHistory(from: day(-7), to: now)
        let source = HomeLoopsFakeSource(records: history.records, readings: history.readings)
        let store = HomeLoopsStore(source: source)
        await assertHomeLoopsStore(store, source, .days7, now: now)

        // readings of 3 days ago deleted: that day and today are read
        let changed = DateInterval(start: day(-3).addingTimeInterval(.hours(6)), end: day(-3).addingTimeInterval(.hours(8)))
        source.update(readings: source.readings.filter { !changed.contains($0) })
        await store.readingsChanged(.interval(changed, newest: false))
        await assertHomeLoopsStore(store, source, .days7, now: now)
        // with the lookahead after it (its last slot)
        let lookahead = HomeLoopStats.Config.slotLookahead
        XCTAssertEqual(Array(source.readingReads.suffix(2)), [
            DateInterval(start: day(-3), end: day(-2).addingTimeInterval(lookahead)),
            DateInterval(start: Self.day0, end: now)
        ])

        // a change ending exactly at midnight: also the day it ends at (a reading there is that day's)
        await store
            .readingsChanged(.interval(DateInterval(start: day(-3).addingTimeInterval(.hours(23)), end: day(-2)), newest: false))
        await assertHomeLoopsStore(store, source, .days7, now: now)
        XCTAssertEqual(Array(source.readingReads.suffix(2)), [
            DateInterval(start: day(-3), end: day(-1).addingTimeInterval(lookahead)),
            DateInterval(start: Self.day0, end: now)
        ])

        // a change in a day's first minutes: the day before too (its last slot reaches into them)
        await store
            .readingsChanged(.interval(DateInterval(start: day(-5).addingTimeInterval(.minutes(5)), duration: 60), newest: false))
        await assertHomeLoopsStore(store, source, .days7, now: now)
        XCTAssertEqual(Array(source.readingReads.suffix(2)), [
            DateInterval(start: day(-6), end: day(-4).addingTimeInterval(lookahead)),
            DateInterval(start: Self.day0, end: now)
        ])

        // the readings wiped: everything is read
        await store.readingsChanged(.all)
        await assertHomeLoopsStore(store, source, .days7, now: now)
        XCTAssertEqual(source.readingReads.last, DateInterval(start: day(-6), end: now))
    }

    func testHomeLoopsStoreSeesUnannouncedRecordChanges() async {
        // 00:30: yesterday is past its settle time, cached
        let now = Self.day0.addingTimeInterval(.minutes(30))
        let history = homeLoopsHistory(from: day(-7), to: Self.day0)
        let source = HomeLoopsFakeSource(records: history.records, readings: history.readings)
        let store = HomeLoopsStore(source: source)
        await assertHomeLoopsStore(store, source, .days7, now: now)
        let stored = await store.cachedDayCount
        XCTAssertEqual(stored, 6)

        // a loop that started before midnight saved after yesterday was stored: the count shows it, yesterday (with
        // today) is read again, the days before it stay
        source.update(records: source.records + [loopRecord(Self.day0.addingTimeInterval(-2), success: false)])
        await assertHomeLoopsStore(store, source, .days7, now: now.addingTimeInterval(60))
        XCTAssertEqual(source.readingReads.last, DateInterval(start: day(-1), end: now.addingTimeInterval(60)))
        let cached = await store.cachedDayCount
        XCTAssertEqual(cached, 6)

        // the loop records wiped (the Settings, unannounced): the days before yesterday differ too, all is read again
        source.update(records: [])
        await assertHomeLoopsStore(store, source, .days7, now: now.addingTimeInterval(120))
        XCTAssertEqual(source.readingReads.last, DateInterval(start: day(-6), end: now.addingTimeInterval(120)))
        let empty = await store.stats(.days7, allowOneMinuteLoop: false, now: now.addingTimeInterval(120), calendar: calendar)
        XCTAssertEqual(empty?.records, 0)
    }

    /// A loop of yesterday's last slot that started after midnight and was saved after yesterday was stored: the count
    /// of its lookahead shows it, yesterday is read again.
    func testHomeLoopsStoreSeesALateLoopInTheLastSlot() async {
        // 00:30: yesterday cached; its last slot (23:55) without a loop
        let now = Self.day0.addingTimeInterval(.minutes(30))
        let history = homeLoopsHistory(from: day(-7), to: Self.day0)
        let records = history.records.filter { $0.start < Self.day0.addingTimeInterval(-TimeInterval.minutes(5)) }
        let source = HomeLoopsFakeSource(records: records, readings: history.readings)
        let store = HomeLoopsStore(source: source)
        await assertHomeLoopsStore(store, source, .days7, now: now)
        let first = await store.stats(.days7, allowOneMinuteLoop: false, now: now, calendar: calendar)
        let stored = await store.cachedDayCount
        XCTAssertEqual(stored, 6)

        // its loop, started at 00:02, saved late: yesterday's last slot succeeded
        source.update(records: records + [loopRecord(Self.day0.addingTimeInterval(.minutes(2)))])
        let later = now.addingTimeInterval(60)
        await assertHomeLoopsStore(store, source, .days7, now: later)
        XCTAssertEqual(source.readingReads.last, DateInterval(start: day(-1), end: later))
        let second = await store.stats(.days7, allowOneMinuteLoop: false, now: later, calendar: calendar)
        XCTAssertEqual(second?.slots.successes, first.map { $0.slots.successes + 1 })
        let cached = await store.cachedDayCount
        XCTAssertEqual(cached, 6)
    }

    func testHomeLoopsStoreDoesNotStoreADayChangedWhileItIsRead() async {
        let now = Self.day0.addingTimeInterval(.hours(10))
        let history = homeLoopsHistory(from: day(-7), to: now)
        let source = HomeLoopsFakeSource(records: history.records, readings: history.readings)
        let store = HomeLoopsStore(source: source)
        // the first read (the whole window) is held
        let noon = day(-3).addingTimeInterval(.hours(12))
        let held = source.holdNextRead { $0.contains(noon) }
        let calendar = self.calendar
        let computing = Task { await store.stats(.days7, allowOneMinuteLoop: false, now: now, calendar: calendar) }
        for await _ in held.arrived {}

        // the day's readings change while it is read
        let changed = DateInterval(start: noon, duration: .hours(1))
        source.update(readings: source.readings.filter { !changed.contains($0) })
        await store.readingsChanged(.interval(changed, newest: false))
        held.release.finish()
        let raced = await computing.value
        XCTAssertNotNil(raced)

        // the other complete days stored, not that one: the next refresh reads it again, with the change
        let cached = await store.cachedDayCount
        XCTAssertEqual(cached, 5)
        await assertHomeLoopsStore(store, source, .days7, now: now)
        XCTAssertEqual(Array(source.readingReads.suffix(2)), [
            DateInterval(start: day(-3), end: day(-2).addingTimeInterval(HomeLoopStats.Config.slotLookahead)),
            DateInterval(start: Self.day0, end: now)
        ])
        let after = await store.cachedDayCount
        XCTAssertEqual(after, 6)
    }

    /// The ongoing gap is as of the read: a later read (a reading, a loop, the foreground) moves it on, nothing else
    /// does.
    func testHomeLoopsOngoingGapIsAsOfTheRead() {
        let starts = homeLoopTimes(from: Self.day0.addingTimeInterval(.minutes(1)), every: .minutes(5), count: 12)
        let records = starts.map { loopRecord($0) }
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 12)
        let stats = homeLoops(records: records, readings: readings, now: starts.last!.addingTimeInterval(.minutes(20)))
        XCTAssertEqual(
            stats.ongoingGap,
            LoopGap(start: starts.last!, end: stats.window.end, loopInterval: .minutes(5), ongoing: true)
        )
        let later = starts.last!.addingTimeInterval(.minutes(27))
        let read = homeLoops(records: records, readings: readings, now: later)
        XCTAssertEqual(read.ongoingGap, LoopGap(start: starts.last!, end: later, loopInterval: .minutes(5), ongoing: true))
        XCTAssertEqual(read.longestGap, read.ongoingGap)
        XCTAssertEqual(read.markedGaps, [read.ongoingGap!])
        XCTAssertEqual(read.slots, stats.slots)
        // a gap that began to count between two reads
        let early = homeLoops(records: records, readings: readings, now: starts.last!.addingTimeInterval(.minutes(5)))
        XCTAssertNil(early.ongoingGap)
        XCTAssertEqual(
            homeLoops(records: records, readings: readings, now: starts.last!.addingTimeInterval(.minutes(15)))
                .ongoingGap?.duration,
            TimeInterval.minutes(15)
        )
    }

    func testHomeLoopsStoreAtMidnight() async {
        // 23:50: six complete days cached, today read
        let evening = Self.day0.addingTimeInterval(TimeInterval.hours(23) + .minutes(50))
        let history = homeLoopsHistory(from: day(-7), to: day(1).addingTimeInterval(.minutes(40)))
        let source = HomeLoopsFakeSource(
            records: history.records.filter { $0.start <= evening },
            readings: history.readings.filter { $0 < evening }
        )
        let store = HomeLoopsStore(source: source)
        await assertHomeLoopsStore(store, source, .days7, now: evening)
        let before = await store.cachedDayCount
        XCTAssertEqual(before, 6)

        // 00:05: yesterday is complete but its last slot's loops may still come: read with today, not stored
        let night = day(1).addingTimeInterval(.minutes(5))
        source.update(records: history.records.filter { $0.start <= night }, readings: history.readings.filter { $0 < night })
        await assertHomeLoopsStore(store, source, .days7, now: night)
        XCTAssertEqual(source.readingReads.last, DateInterval(start: Self.day0, end: night))
        let unsettled = await store.cachedDayCount
        XCTAssertEqual(unsettled, 6)

        // 00:25, past the settle time: read once more, then stored
        let settled = day(1).addingTimeInterval(.minutes(25))
        source.update(records: history.records.filter { $0.start <= settled }, readings: history.readings.filter { $0 < settled })
        await assertHomeLoopsStore(store, source, .days7, now: settled)
        XCTAssertEqual(source.readingReads.last, DateInterval(start: Self.day0, end: settled))
        let after = await store.cachedDayCount
        XCTAssertEqual(after, 7)

        // then today only
        await assertHomeLoopsStore(store, source, .days7, now: settled.addingTimeInterval(60))
        XCTAssertEqual(source.readingReads.last, DateInterval(start: day(1), end: settled.addingTimeInterval(60)))
    }

    func testHomeLoopsStoreDropsTheDaysOfAnotherTimeZone() async {
        let now = Self.day0.addingTimeInterval(.hours(10))
        let history = homeLoopsHistory(from: day(-7), to: now)
        let source = HomeLoopsFakeSource(records: history.records, readings: history.readings)
        let store = HomeLoopsStore(source: source)
        await assertHomeLoopsStore(store, source, .days7, now: now)

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        _ = await store.stats(.days7, allowOneMinuteLoop: false, now: now, calendar: tokyo)
        // the whole window, in Tokyo's days
        let window = Engine.window(for: .days7, now: now, end: now, calendar: tokyo)
        XCTAssertEqual(source.readingReads.last, window)
        let cached = await store.cachedDayCount
        XCTAssertEqual(cached, 6)
    }

    // MARK: - Loop slots

    /// A failed record as `APSManager` stores it: the error in its status and its error, the duration in minutes.
    private func failedRecord(_ start: Date, _ error: String, seconds: Double = 3) -> HomeLoopStats.Record {
        HomeLoopStats.Record(start: start, status: error, error: error, durationMinutes: seconds / 60)
    }

    /// A slot counts once, whatever its attempts: a failing loop tried again every minute (no throttle after a failure,
    /// `APSManager.loop`) is one failed slot, its cause the last attempt's; failures and then a success, one success; a
    /// slot without a record, missed.
    func testLoopSlotsRetryStormCountsOnce() {
        let now = Self.day0.addingTimeInterval(.minutes(20))
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(5), count: 4)
        let stale = "Error: Invalid glucose: Glucose data is stale"
        let pump = "Pump error: Communication Failure"
        // 00:05: five failures a minute apart, the last one the pump's
        let storm = homeLoopTimes(from: Self.day0.addingTimeInterval(.minutes(5) + 10), every: .minutes(1), count: 5)
            .enumerated().map { index, start in failedRecord(start, index < 4 ? stale : pump) }
        // 00:10: four failures, then a loop
        let recovered = homeLoopTimes(from: Self.day0.addingTimeInterval(.minutes(10) + 5), every: .minutes(1), count: 4)
            .map { failedRecord($0, stale) } + [loopRecord(Self.day0.addingTimeInterval(.minutes(14) + 30))]
        // 00:00 a loop, 00:15 none
        let records = [loopRecord(Self.day0.addingTimeInterval(10))] + storm + recovered
        let stats = homeLoops(records: records, readings: readings, now: now)
        XCTAssertEqual(stats.slots, HomeLoopStats.Slots(count: 4, successes: 2, failed: 1, missed: 1))
        XCTAssertEqual(stats.records, 11)
        XCTAssertEqual(stats.percent, 50)

        let result = HomeLoopStats.day(
            DateInterval(start: Self.day0, end: day(1)),
            interval: stats.window,
            windowEnd: now,
            records: records,
            readings: readings,
            allowOneMinuteLoop: false
        )
        XCTAssertEqual(result.causes, [LoopFailureCause.of(error: pump, status: pump): 1])
        XCTAssertEqual(result.causes.keys.first?.type, .pumpCommunication)
        // every attempt's duration: the 9 failures', 3 s each (the loops' are unknown)
        XCTAssertEqual(result.durations, [30: 9])
        XCTAssertEqual(HomeLoopStats.medianDuration(result.durations), 3)
        XCTAssertNil(HomeLoopStats.medianDuration([:]))
        XCTAssertEqual(HomeLoopStats.medianDuration([20: 1, 30: 1, 40: 2]), 3)
    }

    /// A day's last slot runs into the next day, up to its first reading (`slotLookahead` at most): the loop of the
    /// reading at 23:59:50, started at 00:00:20, is yesterday's; today's slots start at its first reading.
    func testLoopSlotSpanningMidnight() {
        let yesterday = day(-1)
        // yesterday 00:04:50 to 23:59:50, today 00:04:50 to 00:54:50
        let readings = homeLoopTimes(from: yesterday.addingTimeInterval(.minutes(4) + 50), every: .minutes(5), count: 288 + 11)
        let records = readings.map { loopRecord($0.addingTimeInterval(30)) }
        XCTAssertEqual(readings[287], Self.day0.addingTimeInterval(-10))
        let now = Self.day0.addingTimeInterval(.hours(1))

        let stats = homeLoops(.days7, records: records, readings: readings, now: now)
        XCTAssertEqual(stats.slots, HomeLoopStats.Slots(count: 299, successes: 299, failed: 0, missed: 0))
        XCTAssertEqual(stats.todaySlots, HomeLoopStats.Slots(count: 11, successes: 11, failed: 0, missed: 0))

        let window = Engine.window(for: .days7, now: now, end: now, calendar: calendar)
        let days = HomeLoopStats.days(
            HomeLoopStats.segments(of: window, calendar: calendar),
            windowEnd: now,
            records: records,
            readings: readings,
            allowOneMinuteLoop: false
        )
        let previous = days.first { $0.day.start == yesterday }
        XCTAssertEqual(previous?.slots, HomeLoopStats.Slots(count: 288, successes: 288, failed: 0, missed: 0))
        // its own records: the loop at 00:00:20 started today
        XCTAssertEqual(previous?.records, 287)
        XCTAssertEqual(days.last?.records, 12)

        // the 24 h range across that midnight (from yesterday 01:00: 276 + 11 readings): every one a loop
        XCTAssertEqual(
            homeLoops(.last24h, records: records, readings: readings, now: now).slots,
            HomeLoopStats.Slots(count: 287, successes: 287, failed: 0, missed: 0)
        )

        // where the last slot ends: the next day's first reading a loop could run on after the slot's (4.5 min after it
        // with the 5-minute loop, any with the 1-minute one), `slotLookahead` after midnight at most, now at most
        let yesterdayPart = DateInterval(start: yesterday, end: Self.day0)
        let last = Self.day0.addingTimeInterval(-10)
        let first = Self.day0.addingTimeInterval(.minutes(4) + 50)
        let slotsEnd = { (part: DateInterval, windowEnd: Date, readings: [Date], oneMinute: Bool) in
            HomeLoopStats.slotsEnd(
                of: part,
                windowEnd: windowEnd,
                lastSlotStart: last,
                readings: readings,
                allowOneMinuteLoop: oneMinute
            )
        }
        XCTAssertEqual(slotsEnd(yesterdayPart, now, [first], false), first)
        XCTAssertEqual(slotsEnd(yesterdayPart, now, [], false), Self.day0.addingTimeInterval(HomeLoopStats.Config.slotLookahead))
        let early = Self.day0.addingTimeInterval(.minutes(2))
        XCTAssertEqual(slotsEnd(yesterdayPart, early, [first], false), early)
        XCTAssertEqual(slotsEnd(DateInterval(start: Self.day0, end: now), now, [], false), now)
        // a reading seconds after midnight: past it with the 5-minute loop, the end with the 1-minute one
        let close = Self.day0.addingTimeInterval(20)
        XCTAssertEqual(slotsEnd(yesterdayPart, now, [close, first], false), first)
        XCTAssertEqual(slotsEnd(yesterdayPart, now, [close, first], true), close)

        // without a reading after midnight: a loop at 00:00:20 is still the last slot's, one at 00:16 nobody's
        let alone = HomeLoopStats.day(
            DateInterval(start: yesterday, end: Self.day0),
            interval: yesterdayPart,
            windowEnd: now,
            records: [loopRecord(Self.day0.addingTimeInterval(-100)), loopRecord(Self.day0.addingTimeInterval(20))],
            readings: [Self.day0.addingTimeInterval(-120), Self.day0.addingTimeInterval(-90)],
            allowOneMinuteLoop: true
        )
        XCTAssertEqual(alone.slots, HomeLoopStats.Slots(count: 2, successes: 2, failed: 0, missed: 0))
        let late = HomeLoopStats.day(
            DateInterval(start: yesterday, end: Self.day0),
            interval: yesterdayPart,
            windowEnd: now,
            records: [loopRecord(Self.day0.addingTimeInterval(.minutes(16)))],
            readings: [Self.day0.addingTimeInterval(-120)],
            allowOneMinuteLoop: false
        )
        XCTAssertEqual(late.slots, HomeLoopStats.Slots(count: 1, successes: 0, failed: 0, missed: 1))
    }

    /// The window's last slot runs up to now, a loop at now included.
    func testLoopLastSlotRunsToNow() {
        let reading = Self.day0.addingTimeInterval(.hours(10))
        let now = reading.addingTimeInterval(.minutes(3))
        XCTAssertEqual(
            homeLoops(records: [loopRecord(now)], readings: [reading], now: now).slots,
            HomeLoopStats.Slots(count: 1, successes: 1, failed: 0, missed: 0)
        )
        // none yet: missed, until its loop (a reading reads with the loop, `readingMayChange`)
        XCTAssertEqual(
            homeLoops(readings: [reading], now: now).slots,
            HomeLoopStats.Slots(count: 1, successes: 0, failed: 0, missed: 1)
        )
        // a loop before the first reading belongs to the slot before (yesterday's): none of today's
        XCTAssertEqual(
            homeLoops(records: [loopRecord(reading.addingTimeInterval(-60))], readings: [reading], now: now).slots,
            HomeLoopStats.Slots(count: 1, successes: 0, failed: 0, missed: 1)
        )
    }

    /// 1-minute readings on the 5-minute loop, the loops at any offset from the day's thinning: a day's last slot (its
    /// newest reading, 23:59:30) runs to the next day's first reading 4.5 min after it, not to the one at 00:00:30, so it
    /// holds the loop that ran for it. Every slot of the day a loop.
    func testLoopDaysLastSlotOnOneMinuteReadings() {
        let yesterday = day(-1)
        let yesterdayPart = DateInterval(start: yesterday, end: Self.day0)
        // 22:00:30 yesterday to 01:57:30 today
        let readings = homeLoopTimes(from: yesterday.addingTimeInterval(.hours(22) + 30), every: .minutes(1), count: 238)
        let now = Self.day0.addingTimeInterval(.hours(2))
        for offset in stride(from: 0.0, to: 300, by: 20) {
            // a loop every 5 minutes from 22:00 plus the offset
            let records = homeLoopTimes(from: yesterday.addingTimeInterval(.hours(22) + offset), every: .minutes(5), count: 48)
                .map { loopRecord($0) }
            let result = HomeLoopStats.day(
                yesterdayPart,
                interval: yesterdayPart,
                windowEnd: now,
                records: records,
                readings: readings,
                allowOneMinuteLoop: false
            )
            // 22:04:30 to 23:59:30, the last one to 00:04:30
            XCTAssertEqual(result.slots, HomeLoopStats.Slots(count: 24, successes: 24, failed: 0, missed: 0), "\(offset)")
            XCTAssertEqual(result.lookaheadEnd, Self.day0.addingTimeInterval(.minutes(4) + 30), "\(offset)")
            XCTAssertEqual(result.lookaheadRecords, offset < 270 ? 1 : 0, "\(offset)")
            // today: from 00:02:30 (thinned from 01:57:30), every slot but the last one (to now) a loop
            let today = homeLoops(records: records, readings: readings, now: now).slots
            XCTAssertEqual(today.count, 24, "\(offset)")
            XCTAssertGreaterThanOrEqual(today.successes, 23, "\(offset)")
        }
    }

    /// A 5-minute sensor, a reading 20 s after the day's last one (a second source): the loop of the last one, started
    /// 30 s after it, after midnight, is still its slot's (the loop throttle skips the close reading).
    func testLoopDaysLastSlotWithAReadingJustAfterIt() {
        let yesterday = day(-1)
        let yesterdayPart = DateInterval(start: yesterday, end: Self.day0)
        // 22:04:50 to 23:59:50 yesterday, 00:00:10, 00:04:50 and 00:09:50 today; each loop 30 s after its reading, none
        // for 00:00:10
        let last = Self.day0.addingTimeInterval(-10)
        let yesterdays = homeLoopTimes(
            from: yesterday.addingTimeInterval(.hours(22) + .minutes(4) + 50),
            every: .minutes(5),
            count: 24
        )
        XCTAssertEqual(yesterdays.last, last)
        let todays = [Self.day0.addingTimeInterval(.minutes(4) + 50), Self.day0.addingTimeInterval(.minutes(9) + 50)]
        let readings = yesterdays + [Self.day0.addingTimeInterval(10)] + todays
        let records = (yesterdays + todays).map { loopRecord($0.addingTimeInterval(30)) }
        let now = Self.day0.addingTimeInterval(.minutes(12))
        let result = HomeLoopStats.day(
            yesterdayPart,
            interval: yesterdayPart,
            windowEnd: now,
            records: records,
            readings: readings,
            allowOneMinuteLoop: false
        )
        XCTAssertEqual(result.slots, HomeLoopStats.Slots(count: 24, successes: 24, failed: 0, missed: 0))
        XCTAssertEqual(result.lookaheadEnd, todays[0])
        XCTAssertEqual(result.lookaheadRecords, 1)
        // today's own slots from 00:00:10: the loop at 00:00:20 is due for both
        XCTAssertEqual(
            homeLoops(records: records, readings: readings, now: now).slots,
            HomeLoopStats.Slots(count: 3, successes: 3, failed: 0, missed: 0)
        )
    }

    /// The 1-minute loop: every reading a slot; the 5-minute loop on 1-minute readings: oref's readings (4.5 min).
    func testLoopSlotsOneMinuteLoop() {
        let now = Self.day0.addingTimeInterval(.hours(1))
        let readings = homeLoopTimes(from: Self.day0, every: .minutes(1), count: 60)
        let everyMinute = homeLoops(
            records: readings.map { loopRecord($0.addingTimeInterval(5)) },
            readings: readings,
            allowOneMinuteLoop: true,
            now: now
        )
        XCTAssertEqual(everyMinute.slots, HomeLoopStats.Slots(count: 60, successes: 60, failed: 0, missed: 0))
        // a loop every 5 minutes on the 1-minute loop: the minutes between them missed
        let sparse = homeLoops(
            records: stride(from: 4, to: 60, by: 5).map { loopRecord(readings[$0].addingTimeInterval(5)) },
            readings: readings,
            allowOneMinuteLoop: true,
            now: now
        )
        XCTAssertEqual(sparse.slots, HomeLoopStats.Slots(count: 60, successes: 12, failed: 0, missed: 48))
        let fiveMinute = homeLoops(
            records: stride(from: 4, to: 60, by: 5).map { loopRecord(readings[$0].addingTimeInterval(5)) },
            readings: readings,
            now: now
        )
        XCTAssertEqual(fiveMinute.slots, HomeLoopStats.Slots(count: 12, successes: 12, failed: 0, missed: 0))
    }

    /// A day's share is its successes over its slots; over days pooled, not the mean of the days' shares.
    func testLoopPooledShare() {
        let good = HomeLoopStats.Slots(count: 100, successes: 99, failed: 1, missed: 0)
        let poor = HomeLoopStats.Slots(count: 10, successes: 5, failed: 0, missed: 5)
        XCTAssertEqual(good.percent, 99)
        XCTAssertEqual(poor.percent, 50)
        XCTAssertEqual((good + poor).percent!, 104.0 / 110 * 100, accuracy: 1E-9)
        XCTAssertEqual(good + poor, HomeLoopStats.Slots(count: 110, successes: 104, failed: 1, missed: 5))
        XCTAssertNil(HomeLoopStats.Slots().percent)

        // the N-day stats are their days pooled
        let now = Self.day0.addingTimeInterval(.hours(14))
        let history = homeLoopsHistory(from: day(-29), to: now)
        let window = Engine.window(for: .days30, now: now, end: now, calendar: calendar)
        let days = HomeLoopStats.days(
            HomeLoopStats.segments(of: window, calendar: calendar),
            windowEnd: now,
            records: history.records,
            readings: history.readings,
            allowOneMinuteLoop: false
        )
        let stats = homeLoops(.days30, records: history.records, readings: history.readings, now: now)
        XCTAssertEqual(stats.slots, days.reduce(HomeLoopStats.Slots()) { $0 + $1.slots })
        // 08:20-09:00 no loop every day, every 50th failed
        XCTAssertEqual(stats.slots.missed, 8 * 30)
        XCTAssertGreaterThan(stats.slots.failed, 0)
    }

    func testLoopHistoryBins() {
        typealias Bin = LoopHistory.Bin
        let cases: [(Double, Bin)] = [
            (100, .best), (95, .best), (94.99, .good), (90, .good), (89.9, .fair), (75, .fair), (74.9, .poor), (0, .poor)
        ]
        for (percent, bin) in cases {
            XCTAssertEqual(Bin.of(percent), bin, "\(percent)")
        }
        // by the value shown: 94.96 is "95.0", the best
        let shown: [(Double, String, Bin)] = [
            (94.96, "95.0", .best), (94.94, "94.9", .good), (89.95, "90.0", .good), (74.95, "75.0", .fair),
            (99.95, "100", .best), (99.94, "99.9", .best)
        ]
        for (percent, text, bin) in shown {
            let expected = text == "100" ? text : Double(text)!.formatted(.number.precision(.fractionLength(1)))
            XCTAssertEqual(HomeLoopsCard.Content.percent(percent), expected, "\(percent)")
            XCTAssertEqual(Bin.of(shown: percent), bin, "\(percent)")
        }
    }

    /// The stored texts, cleaned (numbers, ids, dates and times stripped) and grouped by the loop event types; an
    /// unknown text is its own cause; case doesn't make another one.
    func testLoopFailureCauses() {
        let cases: [(String, LoopEventType, String)] = [
            ("Pump error: Communication Failure", .pumpCommunication, "Pump error: Communication Failure"),
            ("Pump error: No response from pod", .pumpCommunication, "Pump error: No response from pod"),
            ("Pump error: Uncertain Delivery", .deliveryUncertain, "Pump error: Uncertain Delivery"),
            // a pump error by the pump manager's words, as the chart names it (`LoopEventType(failure:)`, the command
            // failures): `.deviceState` the pump's state, an error it can't tell apart its communication
            ("Pump error: Pod fault 049 at 12:34", .pumpDeviceState, "Pump error: Pod fault at"),
            ("Pump error: Device Refused", .pumpDeviceState, "Pump error: Device Refused"),
            ("Pump error: Pod is suspended", .pumpDeviceState, "Pump error: Pod is suspended"),
            (
                "Pump error: Action has been canceled, because the pump is busy",
                .pumpDeviceState,
                "Pump error: Action has been canceled, because the pump is busy"
            ),
            ("Pump error: Bolus of 2.5 U failed, retry in 30 s", .pumpCommunication, "Pump error: Bolus of U failed, retry in s"),
            ("Pump error: Invalid Configuration", .pumpConfiguration, "Pump error: Invalid Configuration"),
            ("Error: Invalid glucose: Glucose data is stale", .glucoseData, "Error: Invalid glucose: Glucose data is stale"),
            ("Error: Invalid glucose: Not enough glucose data", .glucoseData, "Error: Invalid glucose: Not enough glucose data"),
            (
                "Pump is Busy. Can't enact the new loop cycle recommendation, because a Bolus is in progress. Wait for next loop cycle",
                .pumpBusy,
                "Pump is Busy. Can't enact the new loop cycle recommendation, because a Bolus is in progress. Wait for next loop cycle"
            ),
            ("Suggested SMB not enacted while in Bolus View", .bolusView, "Suggested SMB not enacted while in Bolus View"),
            (
                "Suggested Temp Basal (when > 0) and SMB not enacted while in Bolus View",
                .bolusView,
                "Suggested Temp Basal (when >) and SMB not enacted while in Bolus View"
            ),
            ("APS error: Determine basal failed", .algorithm, "APS error: Determine basal failed"),
            ("APS error: Suggestion expired", .algorithm, "APS error: Suggestion expired"),
            // an `APSError.apsError`, as the chart names it
            (
                "APS error: failed to resume delivery: Pump error: Connection Failure",
                .algorithm,
                "APS error: failed to resume delivery: Pump error: Connection Failure"
            ),
            (
                "Manual Basal Temp : Loop not possible during the manual basal temp",
                .manualTempBasal,
                "Manual Basal Temp: Loop not possible during the manual basal temp"
            ),
            ("Error: Invalid Pump State: Pump suspended", .pumpSuspended, "Error: Invalid Pump State: Pump suspended"),
            ("Error: Invalid Pump State: Pump not set", .pumpNotConfigured, "Error: Invalid Pump State: Pump not set"),
            ("Pump not configured", .pumpNotConfigured, "Pump not configured"),
            ("Sync error: Pump history sync failed", .pumpCommunication, "Sync error: Pump history sync failed"),
            (
                "The operation couldn’t be completed. (OmniBLE.PodCommsError error 5.)",
                .pumpCommunication,
                "The operation couldn’t be completed. (OmniBLE.PodCommsError error.)"
            ),
            (
                "JS: TypeError: undefined is not an object (evaluating 'glucose_status.delta')",
                .loopFailed,
                "JS: TypeError: undefined is not an object (evaluating 'glucose_status.delta')"
            )
        ]
        for (text, type, message) in cases {
            let cause = LoopFailureCause.of(error: text, status: text)
            XCTAssertEqual(cause.type, type, text)
            XCTAssertEqual(cause.message, message, text)
        }

        // a long state dump: its dates, ids and amounts stripped, cut
        let dump = "Error: Invalid Pump State: Invalid basal delivery state: tempBasal(LoopKit.DoseEntry(type: LoopKit.DoseType"
            + ".tempBasal, startDate: 2026-11-03 10:15:30 +0000, endDate: 2026-11-03 10:45:30 +0000, value: 1.25, "
            + "syncIdentifier: Optional(\"6a1b2c3d4e5f6a7b8c9d\"), id: 5F2A4B6C-1D2E-4F3A-8B9C-0D1E2F3A4B5C))"
        let cleaned = LoopFailureCause.of(error: dump, status: nil)
        XCTAssertEqual(cleaned.type, .pumpNotConfigured)
        XCTAssertFalse(cleaned.message.contains("2026"))
        XCTAssertFalse(cleaned.message.contains("10:15"))
        XCTAssertFalse(cleaned.message.contains("1.25"))
        XCTAssertFalse(cleaned.message.contains("5F2A4B6C"))
        XCTAssertLessThanOrEqual(cleaned.message.count, LoopFailureCause.Config.maxLength)
        // the same failure at another time, of another amount: one cause
        XCTAssertEqual(
            LoopFailureCause.of(error: "Pump error: Pod fault 049 at 12:34", status: nil),
            LoopFailureCause.of(error: "Pump error: Pod fault 051 at 18:02", status: nil)
        )
        // case: one cause, shown as met first
        XCTAssertEqual(
            LoopFailureCause.of(error: "Pump error: Timeout", status: nil),
            LoopFailureCause.of(error: "pump error: TIMEOUT", status: nil)
        )
        // the status when there is no error; neither: "Loop failed"
        XCTAssertEqual(LoopFailureCause.of(error: nil, status: "APS error: Suggestion expired").type, .algorithm)
        let none = LoopFailureCause.of(error: nil, status: nil)
        XCTAssertEqual(none.type, .loopFailed)
        XCTAssertEqual(none.title, LoopEventType.loopFailed.title)
        // a known kind is titled by its type, an unknown text by itself
        XCTAssertEqual(
            LoopFailureCause.of(error: "APS error: Determine basal failed", status: nil).title,
            LoopEventType.algorithm.title
        )
        XCTAssertEqual(LoopFailureCause.of(error: "Something odd 42", status: nil).title, "Something odd")
        // digits inside a word stay
        XCTAssertEqual(LoopFailureCause.clean("Dexcom G7 sensor: no data for 12 min"), "Dexcom G7 sensor: no data for min")
        XCTAssertEqual(LoopFailureCause.clean("G12 failed 3 times (#4)"), "G12 failed times")
        // the memo: the same causes, each text once, bounded
        let memo = LoopFailureCause.Memo()
        for (text, _, _) in cases + cases {
            XCTAssertEqual(memo.cause(error: text, status: text), LoopFailureCause.of(error: text, status: text), text)
        }
        XCTAssertEqual(memo.count, cases.count)
        for index in 0 ..< LoopFailureCause.Config.memoSize + 5 {
            _ = memo.cause(error: "Odd failure \(index)", status: nil)
        }
        XCTAssertLessThanOrEqual(memo.count, LoopFailureCause.Config.memoSize)
        let memoised = HomeLoopStats.Record(
            start: Self.day0,
            status: "Pump error: Timeout",
            error: "Pump error: Timeout",
            durationMinutes: nil,
            cause: memo.cause(error:status:)
        )
        XCTAssertEqual(memoised.cause, LoopFailureCause.of(error: "Pump error: Timeout", status: "Pump error: Timeout"))
        // a stored record: "Success" ran, any other status failed
        XCTAssertTrue(HomeLoopStats.Record(start: Self.day0, status: "Success", error: nil, durationMinutes: 0.05).success)
        let failed = HomeLoopStats.Record(start: Self.day0, status: "Pump error: Timeout", error: nil, durationMinutes: 0.05)
        XCTAssertFalse(failed.success)
        XCTAssertEqual(failed.cause?.type, .pumpCommunication)
        XCTAssertEqual(failed.duration!, 3, accuracy: 1E-9)
        // not "contains": a status that only mentions it failed
        XCTAssertFalse(HomeLoopStats.Record(start: Self.day0, status: "No Success", error: nil, durationMinutes: nil).success)
    }

    // MARK: Loops screen

    /// en_GB, the week from Monday, 24 hours
    private var britishCalendar: Calendar {
        var calendar = self.calendar
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }

    /// 35 days up to 14:35 today, a reading every 5 minutes and a loop 20 s after it; 12 days ago no loop 10:00-12:59;
    /// 9 days ago no readings (and no loops) 02:00-03:59; 6 days ago the pump busy 15:00-15:59; 4 days ago no readings;
    /// 3 days ago readings without a loop; every day at 08:00 one failed loop of the pump.
    private func loopScreenHistory(calendar: Calendar)
        -> (history: HomeLoopsStore.History, records: [HomeLoopStats.Record], readings: [Date])
    {
        let now = Self.day0.addingTimeInterval(TimeInterval.hours(14) + .minutes(35))
        let start = day(-34)
        var readings: [Date] = []
        var records: [HomeLoopStats.Record] = []
        var time = start
        while time < now {
            let dayIndex = calendar.dateComponents([.day], from: calendar.startOfDay(for: time), to: Self.day0).day ?? 0
            let hour = calendar.component(.hour, from: time)
            let minute = calendar.component(.minute, from: time)
            defer { time = time.addingTimeInterval(.minutes(5)) }
            if dayIndex == 4 || (dayIndex == 9 && (2 ..< 4).contains(hour)) { continue }
            readings.append(time)
            if dayIndex == 3 || (dayIndex == 12 && (10 ..< 13).contains(hour)) { continue }
            let start = time.addingTimeInterval(20)
            if dayIndex == 6, hour == 15 {
                records.append(failedRecord(
                    start,
                    "Pump is Busy. Can't enact the new loop cycle recommendation, because a Bolus is in progress. Wait for next loop cycle"
                ))
            } else if hour == 8, minute == 0 {
                records.append(failedRecord(start, "Pump error: Communication Failure"))
            } else {
                records.append(HomeLoopStats.Record(start: start, success: true, duration: 4))
            }
        }
        let window = DateInterval(start: start, end: now)
        let days = HomeLoopStats.days(
            HomeLoopStats.segments(of: window, calendar: calendar),
            windowEnd: now,
            records: records,
            readings: readings,
            allowOneMinuteLoop: false
        )
        return (HomeLoopsStore.History(window: window, days: days, previousStart: nil), records, readings)
    }

    func testLoopHistoryCalendar() {
        let calendar = britishCalendar
        let (history, _, _) = loopScreenHistory(calendar: calendar)
        let content = LoopHistory.Content.make(history, selection: .lastDays, calendar: calendar)
        // five weeks from a Monday, this week last; Tuesday 20 October today
        XCTAssertEqual(content.weekdays, ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(content.weeks.count, 5)
        XCTAssertTrue(content.weeks.allSatisfy { $0.count == 7 })
        let cells = content.weeks.flatMap { $0 }
        XCTAssertEqual(cells.first?.id, day(-29))
        XCTAssertEqual(calendar.component(.weekday, from: cells[0].id), 2)
        XCTAssertEqual(content.calendarDates, "21 Sep – 20 Oct")
        let today = cells.first { $0.isToday }
        XCTAssertEqual(today?.id, Self.day0)
        XCTAssertEqual(today?.caption, "Today")
        XCTAssertEqual(cells.filter(\.isFuture).count, 5)
        XCTAssertEqual(cells.first?.caption, "Sep")
        XCTAssertEqual(cells.first { $0.number == "1" }?.caption, "Oct")
        // the bins; no readings: no bin; readings without a loop: the lowest
        let cell = { (offset: Int) in cells.first { $0.id == self.day(offset) }! }
        XCTAssertEqual(cell(-1).bin, .best)
        XCTAssertNil(cell(-4).bin)
        XCTAssertEqual(cell(-3).bin, .poor)
        // 12 days ago: 36 of 288 readings without a loop (87.5 %)
        XCTAssertEqual(cell(-12).bin, .fair)
        XCTAssertNil(content.weeks.flatMap { $0 }.first(where: \.isSelected))

        // the week from Sunday elsewhere
        var american = calendar
        american.locale = Locale(identifier: "en_US")
        american.firstWeekday = 1
        let us = LoopHistory.Content.make(history, selection: .lastDays, calendar: american)
        XCTAssertEqual(us.weekdays, ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(american.component(.weekday, from: us.weeks[0][0].id), 1)
        // the 12-hour clock (its narrow space as a space)
        XCTAssertEqual(us.detail.axis.first?.replacingOccurrences(of: "\u{202F}", with: " "), "12 AM")
        XCTAssertEqual(
            LoopHistory.Content.make(history, selection: .lastDays, calendar: calendar).detail.axis,
            ["00", "06", "12", "18", "00"]
        )
    }

    /// The detail: the 30 days are a 30 d range's numbers (pooled), today the card's Today; a day picked; gaps and why;
    /// the causes.
    func testLoopHistoryDetail() {
        let calendar = britishCalendar
        let (history, records, readings) = loopScreenHistory(calendar: calendar)
        let now = history.window.end
        let make = { (selection: LoopHistory.Selection) in
            LoopHistory.Content.make(history, selection: selection, calendar: calendar)
        }

        // the 30 days: the same numbers as the 30 d range
        let lastDays = make(.lastDays)
        let thirty = HomeLoopStats.make(
            period: .days30,
            records: records,
            previousStart: nil,
            readings: readings,
            allowOneMinuteLoop: false,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(lastDays.selection, .lastDays)
        XCTAssertEqual(lastDays.detail.title, "Last 30 days")
        XCTAssertEqual(lastDays.detail.subtitle, "21 Sep – 20 Oct, today so far")
        XCTAssertEqual(lastDays.detail.percent, HomeLoopsCard.Content.percent(thirty.percent!))
        XCTAssertEqual(lastDays.detail.failed, thirty.slots.failed.formatted())
        XCTAssertEqual(lastDays.detail.missed, thirty.slots.missed.formatted())
        XCTAssertEqual(lastDays.detail.medianDuration, 4.0.formatted(.number.precision(.fractionLength(1)).grouping(.never)))
        XCTAssertFalse(lastDays.detail.isDay)
        XCTAssertEqual(lastDays.detail.columns.count, 48)
        XCTAssertEqual(lastDays.detail.gapMarks, [])
        XCTAssertEqual(lastDays.detail.failed, "40")
        // the longest gaps, the longest first, with their day: 2 days from the last loop before the day without readings
        // (as many readings as missed loops: no CGM), 3 h without a loop, 2 h without readings
        XCTAssertEqual(lastDays.detail.gaps.map(\.day), ["Thu 15 Oct", "Thu 8 Oct", "Sun 11 Oct"])
        // a day or longer: its days too
        XCTAssertEqual(lastDays.detail.gaps.map(\.times), [
            "Thu 23:55 – Sun 00:00 · no CGM readings",
            "09:55–13:00 · no loop ran",
            "01:55–04:00 · no CGM readings"
        ])
        XCTAssertEqual(lastDays.detail.gaps[1].dayStart, day(-12))
        // the causes: no loop (12 days ago, 3 days ago), the pump's every day at 08:00, the busy pump; their shares of
        // the readings without a loop
        let causes = lastDays.detail.causes
        XCTAssertEqual(causes.map(\.kind), [.missed, .failure(.pumpCommunication), .failure(.pumpBusy)])
        XCTAssertEqual(causes.map(\.count), ["324", "28", "12"])
        XCTAssertEqual(causes.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1E-9)
        XCTAssertEqual(causes.first { $0.kind == .failure(.pumpBusy) }?.title, LoopEventType.pumpBusy.title)
        XCTAssertEqual(lastDays.detail.causesLine, "364 loops missed or failed")
        XCTAssertTrue(lastDays.detail.counts.hasPrefix(
            HomeLoopsCard.Content.loops(thirty.slots.successes, of: thirty.slots.count) + " · "
        ))
        XCTAssertTrue(lastDays.detail.counts.hasSuffix(" a day"))

        // today: the card's Today
        let today = make(.day(Self.day0))
        let card = homeLoops(.today, records: records, readings: readings, now: now)
        XCTAssertEqual(today.detail.title, "Today")
        XCTAssertEqual(today.detail.subtitle, "So far, until 14:35")
        XCTAssertEqual(today.detail.percent, HomeLoopsCard.Content.percent(card.percent!))
        XCTAssertEqual(today.selection, .day(Self.day0))
        XCTAssertTrue(today.weeks.flatMap { $0 }.first { $0.isToday }!.isSelected)

        // 12 days ago: its gap on the strip, its row with no day
        let gapDay = make(.day(day(-12)))
        XCTAssertEqual(gapDay.detail.title, "Thursday 8 October")
        XCTAssertEqual(gapDay.detail.subtitle, "The whole day")
        XCTAssertTrue(gapDay.detail.isDay)
        XCTAssertEqual(gapDay.detail.gaps.map(\.times), ["09:55–13:00 · no loop ran"])
        XCTAssertNil(gapDay.detail.gaps.first?.day)
        XCTAssertEqual(gapDay.detail.gapMarks.count, 1)
        XCTAssertEqual(gapDay.detail.gapMarks.first!.start, (9 * 60 + 60.0) / 1440, accuracy: 1E-3)
        XCTAssertEqual(gapDay.detail.gapMarks.first!.end, 780.0 / 1440, accuracy: 1E-3)
        XCTAssertEqual(gapDay.detail.causes.first?.kind, .missed)
        XCTAssertEqual(gapDay.detail.causes.first?.count, "36")

        // a day without readings: no share; a day outside the calendar: the 30 days
        XCTAssertEqual(make(.day(day(-4))).detail.percent, "–")
        XCTAssertFalse(make(.day(day(-4))).detail.hasPercent)
        XCTAssertEqual(make(.day(day(-40))).selection, .lastDays)
        XCTAssertEqual(make(.day(day(1))).selection, .lastDays)
        // every reading got a loop: no causes
        let clean = make(.day(day(-1)))
        XCTAssertEqual(clean.detail.causes.map(\.kind), [.failure(.pumpCommunication)])
    }

    /// The strip's times are of the day's equal parts: on the 25-hour day its quarters aren't 06, 12, 18; the 30 days on
    /// that day are a day of 24 hours (yesterday's).
    func testLoopHistoryStripTimesOnADSTDay() {
        let calendar = britishCalendar
        // today the 25-hour day, to 13:00; from two days before, a reading every 5 minutes and a loop 20 s after it, but
        // none 10:00-10:29 on those two days
        let start = day(-2, from: Self.fallBack)
        let now = Self.fallBack.addingTimeInterval(.hours(14))
        let readings = homeLoopTimes(from: start, every: .minutes(5), count: Int(now.timeIntervalSince(start) / 300))
        let records = readings.compactMap { reading -> HomeLoopStats.Record? in
            let late = calendar.component(.hour, from: reading) == 10 && calendar.component(.minute, from: reading) < 30
            guard !late || reading >= Self.fallBack else { return nil }
            return loopRecord(reading.addingTimeInterval(20))
        }
        let window = DateInterval(start: start, end: now)
        let days = HomeLoopStats.days(
            HomeLoopStats.segments(of: window, calendar: calendar),
            windowEnd: now,
            records: records,
            readings: readings,
            allowOneMinuteLoop: false
        )
        let history = HomeLoopsStore.History(window: window, days: days, previousStart: nil)
        let make = { (selection: LoopHistory.Selection) in
            LoopHistory.Content.make(history, selection: selection, calendar: calendar).detail
        }
        // the 25-hour day: its quarters 6 h 15 min long, the clock going back at 03:00
        XCTAssertEqual(make(.day(Self.fallBack)).axis, ["00", "05", "11", "17", "00"])
        // a day of 24 hours, also while today is the long one
        XCTAssertEqual(make(.day(day(-1, from: Self.fallBack))).axis, ["00", "06", "12", "18", "00"])
        let lastDays = make(.lastDays)
        XCTAssertEqual(lastDays.axis, ["00", "06", "12", "18", "00"])
    }

    /// More than five kinds: the five with the most, then "Other"; "No loop ran" in its place by its count.
    func testLoopHistoryCauseRows() {
        let types: [(String, Int)] = [
            ("Pump error: Communication Failure", 30),
            ("Error: Invalid glucose: Glucose data is stale", 20),
            ("Error: Invalid glucose: Not enough glucose data", 5),
            ("Suggested SMB not enacted while in Bolus View", 12),
            ("APS error: Determine basal failed", 6),
            ("Manual Basal Temp : Loop not possible during the manual basal temp", 3),
            ("Error: Invalid Pump State: Pump suspended", 2),
            ("Something odd", 1)
        ]
        var causes: [LoopFailureCause: Int] = [:]
        for (text, count) in types {
            causes[LoopFailureCause.of(error: text, status: nil), default: 0] += count
        }
        let rows = LoopHistory.Content.causeRows(causes, missed: 10, total: 89)
        XCTAssertEqual(rows.map(\.kind), [
            .failure(.pumpCommunication),
            .failure(.glucoseData),
            .failure(.bolusView),
            .missed,
            .failure(.algorithm),
            .failure(.manualTempBasal),
            .other
        ])
        XCTAssertEqual(rows.map(\.count), ["30", "25", "12", "10", "6", "3", "3"])
        // a kind of several texts: the most frequent and how many more
        XCTAssertEqual(rows[1].message, "Error: Invalid glucose: Glucose data is stale (and 1 more)")
        XCTAssertEqual(rows.last?.message, LoopEventType.pumpSuspended.title + ", Something odd")
        XCTAssertEqual(rows.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1E-9)
        XCTAssertEqual(LoopHistory.Content.causeRows([:], missed: 0, total: 0), [])
    }

    /// The store's days for the Loops screen are the days computed from everything; a second read reads today only.
    func testLoopHistoryStore() async {
        let now = Self.day0.addingTimeInterval(TimeInterval.hours(14) + .minutes(36))
        let raw = homeLoopsHistory(from: day(-40), to: now)
        let source = HomeLoopsFakeSource(records: raw.records, readings: raw.readings)
        let store = HomeLoopsStore(source: source)
        let read = await store.history(allowOneMinuteLoop: false, now: now, calendar: calendar)
        let window = DateInterval(start: day(-34), end: now)
        XCTAssertEqual(read?.window, window)
        XCTAssertEqual(read?.previousStart, raw.records.map(\.start).filter { $0 < window.start }.max())
        let days = HomeLoopStats.days(
            HomeLoopStats.segments(of: window, calendar: calendar),
            windowEnd: now,
            records: raw.records.filter { HomeLoopStats.contains(window, $0.start, throughEnd: true) },
            readings: raw.readings.filter { HomeLoopStats.contains(window, $0, throughEnd: false) },
            allowOneMinuteLoop: false
        )
        XCTAssertEqual(read?.days, days)
        XCTAssertEqual(source.readingReads, [window])
        let again = await store.history(allowOneMinuteLoop: false, now: now.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(again?.days.dropLast(), days.dropLast())
        XCTAssertEqual(source.readingReads.last, DateInterval(start: Self.day0, end: now.addingTimeInterval(60)))
        // a 30 d range's numbers from the same days
        let thirty = await store.stats(.days30, allowOneMinuteLoop: false, now: now, calendar: calendar)
        XCTAssertEqual(thirty?.slots, days.suffix(30).reduce(HomeLoopStats.Slots()) { $0 + $1.slots })
    }

    /// The 24 h card: yesterday's columns dimmed, a tick at midnight with today's share under it; Today has neither.
    @MainActor func testHomeLoopsCardMarksToday() {
        let now = Self.day0.addingTimeInterval(TimeInterval.hours(14) + .minutes(36))
        let raw = homeLoopsHistory(from: day(-2), to: now)
        let stats = homeLoops(.last24h, records: raw.records, readings: raw.readings, now: now)
        let content = HomeLoopsCard.Content(stats)
        let midnight = (TimeInterval.hours(24) - (TimeInterval.hours(14) + .minutes(36))) / .hours(24)
        XCTAssertEqual(content.todayMark!, midnight, accuracy: 1E-3)
        XCTAssertTrue(content.pastColumns.allSatisfy { $0.x < content.todayMark! })
        XCTAssertTrue(content.columns.allSatisfy { $0.x >= content.todayMark! })
        XCTAssertEqual(content.pastColumns.count + content.columns.count, 49)
        XCTAssertEqual(content.todayPercent, HomeLoopsCard.Content.percent(stats.todaySlots.percent!) + "%")
        // the same today as Today's
        XCTAssertEqual(stats.todaySlots, homeLoops(.today, records: raw.records, readings: raw.readings, now: now).slots)

        let today = HomeLoopsCard.Content(homeLoops(.today, records: raw.records, readings: raw.readings, now: now))
        XCTAssertNil(today.todayMark)
        XCTAssertEqual(today.todayPercent, HomeLoopsCard.Content.percent(stats.todaySlots.percent!) + "%")
        XCTAssertEqual(today.pastColumns, [])
    }

    /// "Today 97.3%" beside the midnight tick: starting `gap` after it; near the strip's end (just after midnight), ending
    /// `gap` before it, not slid under it; a label wider than both sides kept inside the strip.
    func testHomeLoopsTodayLabelBesideTheTick() {
        func x(_ position: Double, label: CGFloat = 60, width: CGFloat = 300) -> CGFloat {
            MarkLabelLayout.labelX(position: position, gap: 4, labelWidth: label, in: width)
        }
        // left, middle: after the tick
        XCTAssertEqual(x(0), 4)
        XCTAssertEqual(x(0.1), 34, accuracy: 1E-9)
        XCTAssertEqual(x(0.5), 154)
        // just fits after it
        XCTAssertEqual(x(0.5, label: 196, width: 400), 204)
        // at the right end: before it, its trailing edge `gap` left of the tick
        XCTAssertEqual(x(0.9), 270 - 4 - 60, accuracy: 1E-9)
        XCTAssertEqual(x(1), 236)
        XCTAssertEqual(x(0.6, label: 150), 180 - 4 - 150, accuracy: 1E-9)
        // neither side has the room: inside the strip
        XCTAssertEqual(x(0.5, label: 90, width: 100), 10)
        // never over the tick, wherever midnight is
        for step in 0 ... 100 {
            let position = Double(step) / 100
            let mark = 300 * CGFloat(position)
            let start = x(position)
            XCTAssertTrue(start >= mark + 4 || start + 60 <= mark - 4, "\(position)")
            XCTAssertGreaterThanOrEqual(start, 0)
            XCTAssertLessThanOrEqual(start + 60, 300)
        }
        XCTAssertEqual(LoopStripTick.width / 2 + 3, 4)
    }

    // MARK: - Usual day overlay

    /// Every bin with data, the median 100 + its index (`agpBin`: 25–75% at ±20).
    private func usualDayBins() -> [AGPBin?] {
        (0 ..< 96).map { agpBin($0, median: 100 + Double($0)) }
    }

    func testUsualDayOnANormalDay() {
        let bins = usualDayBins()
        let plotted = Engine.agpPlotPoints(bins, axis: 40 ... 300)
        let domain = DateInterval(start: Self.day0, end: day(1))
        let points = Engine.usualDayPoints(plotted, domain: domain, calendar: calendar)
        // every point at its clock minute of the day, the midnight edge at 00:00 and 24:00: one segment
        XCTAssertEqual(points.count, 98)
        XCTAssertEqual(points.map(\.time), plotted.map { Self.day0.addingTimeInterval(.minutes($0.minute)) })
        XCTAssertEqual(points.map(\.p25), plotted.map(\.p25))
        XCTAssertEqual(points.map(\.p50), plotted.map(\.p50))
        XCTAssertEqual(points.map(\.p75), plotted.map(\.p75))
        XCTAssertEqual(Set(points.map(\.segment)), [0])
        XCTAssertEqual(points.first?.time, domain.start)
        XCTAssertEqual(points.last?.time, domain.end)

        // a gap in the profile stays a gap: bin 40 (10:00–10:15) without data
        var gappy = bins
        gappy[40] = nil
        let gapped = Engine.usualDayPoints(Engine.agpPlotPoints(gappy, axis: 40 ... 300), domain: domain, calendar: calendar)
        XCTAssertEqual(gapped.count, 97)
        XCTAssertEqual(Set(gapped.map(\.segment)), [0, 1])
        XCTAssertEqual(gapped.last { $0.segment == 0 }?.time, Self.day0.addingTimeInterval(.minutes(592)))
        XCTAssertEqual(gapped.first { $0.segment == 1 }?.time, Self.day0.addingTimeInterval(.minutes(622)))

        // values kept inside the Trace's axis, as given
        var high = bins
        high[50] = agpBin(50, median: 290)
        let clamped = Engine.usualDayPoints(Engine.agpPlotPoints(high, axis: 40 ... 300), domain: domain, calendar: calendar)
        XCTAssertEqual(clamped.first { $0.time == Self.day0.addingTimeInterval(.minutes(757)) }?.p75, 300)

        // nothing to place
        XCTAssertEqual(Engine.usualDayPoints([], domain: domain, calendar: calendar), [])
        XCTAssertEqual(
            Engine.usualDayPoints(plotted, domain: DateInterval(start: Self.day0, duration: 0), calendar: calendar),
            []
        )
    }

    func testUsualDayAcrossMidnightInTheLast24Hours() {
        let plotted = Engine.agpPlotPoints(usualDayBins(), axis: 40 ... 300)
        // 14:40 to 14:40 the next day
        let start = Self.day0.addingTimeInterval(TimeInterval.hours(14) + .minutes(40))
        let domain = DateInterval(start: start, end: start.addingTimeInterval(.hours(24)))
        let points = Engine.usualDayPoints(plotted, domain: domain, calendar: calendar)
        // one segment, oldest -> newest, from edge to edge
        XCTAssertEqual(Set(points.map(\.segment)), [0])
        XCTAssertEqual(points.map(\.time), points.map(\.time).sorted())
        XCTAssertEqual(points.first?.time, domain.start)
        XCTAssertEqual(points.last?.time, domain.end)
        // the edges interpolated between 14:37 (bin 58, median 158) and 14:52 (bin 59, 159): 3 of the 15 minutes
        XCTAssertEqual(points.first?.p50 ?? 0, 158.2, accuracy: 1E-9)
        XCTAssertEqual(points.first?.p25 ?? 0, 138.2, accuracy: 1E-9)
        XCTAssertEqual(points.first?.p75 ?? 0, 178.2, accuracy: 1E-9)
        XCTAssertEqual(points.last?.p50 ?? 0, 158.2, accuracy: 1E-9)
        // the first day's evening (14:52 ... 23:52), midnight once (the edge of bins 95 and 0), the next morning
        // (00:07 ... 14:37), the two edges
        XCTAssertEqual(points.count, 1 + 37 + 1 + 59 + 1)
        XCTAssertEqual(points[1].time, Self.day0.addingTimeInterval(.minutes(892)))
        let midnight = day(1)
        XCTAssertEqual(points.filter { $0.time == midnight }.count, 1)
        XCTAssertEqual(points.first { $0.time == midnight }?.p50 ?? 0, (195 + 100) / 2, accuracy: 1E-9)
        XCTAssertEqual(points[points.count - 2].time, midnight.addingTimeInterval(.minutes(877)))
        XCTAssertEqual(points[points.count - 2].p50, 158)
    }

    func testUsualDayOnTheDSTDays() {
        let plotted = Engine.agpPlotPoints(usualDayBins(), axis: 40 ... 300)
        func times(_ points: [UsualDayPoint], median: Double) -> [Date] {
            points.filter { $0.p50 == median }.map(\.time)
        }

        // the 25-hour day: 02:00–03:00 is twice (summer time, then winter time), so are its four points
        let long = DateInterval(start: Self.fallBack, end: day(1, from: Self.fallBack))
        XCTAssertEqual(long.duration, .hours(25))
        let fallBack = Engine.usualDayPoints(plotted, domain: long, calendar: calendar)
        XCTAssertEqual(fallBack.count, plotted.count + 4)
        XCTAssertEqual(Set(fallBack.map(\.segment)), [0])
        XCTAssertEqual(fallBack.map(\.time), fallBack.map(\.time).sorted())
        XCTAssertEqual(fallBack.first?.time, long.start)
        XCTAssertEqual(fallBack.last?.time, long.end)
        // 02:07 (bin 8) an hour apart; 01:52 (bin 7) and 03:07 (bin 12) once
        XCTAssertEqual(
            times(fallBack, median: 108),
            [Self.fallBack.addingTimeInterval(.minutes(127)), Self.fallBack.addingTimeInterval(.minutes(187))]
        )
        XCTAssertEqual(times(fallBack, median: 107), [Self.fallBack.addingTimeInterval(.minutes(112))])
        XCTAssertEqual(times(fallBack, median: 112), [Self.fallBack.addingTimeInterval(.minutes(247))])

        // the 23-hour day: 02:00–03:00 is skipped, its four points with it; 01:52 and 03:07 a quarter of an hour apart
        let short = DateInterval(start: Self.springForward, end: day(1, from: Self.springForward))
        XCTAssertEqual(short.duration, .hours(23))
        let springForward = Engine.usualDayPoints(plotted, domain: short, calendar: calendar)
        XCTAssertEqual(springForward.count, plotted.count - 4)
        XCTAssertEqual(Set(springForward.map(\.segment)), [0])
        XCTAssertTrue(springForward.allSatisfy { !(108 ... 111).contains($0.p50) })
        XCTAssertEqual(times(springForward, median: 107), [Self.springForward.addingTimeInterval(.minutes(112))])
        XCTAssertEqual(times(springForward, median: 112), [Self.springForward.addingTimeInterval(.minutes(127))])
        XCTAssertEqual(springForward.first?.time, short.start)
        XCTAssertEqual(springForward.last?.time, short.end)
    }

    func testUsualDayReloadsOnlyWhenAChangeReachesIt() {
        let today = Self.day0
        func reached(_ seq: Int, _ interval: DateInterval?, seen: Int = 4) -> Bool {
            Engine.usualDayIsReached(by: StatsChange(seq: seq, interval: interval), seenSeq: seen, today: today)
        }
        // a reading of today: kept (1/N of the baseline)
        let reading = DateInterval(start: today.addingTimeInterval(.hours(14)), end: today.addingTimeInterval(.hours(14.1)))
        XCTAssertFalse(reached(5, reading))
        // a day before today: a backfill, a delete; the previous reading's span just after midnight
        XCTAssertTrue(reached(5, DateInterval(start: day(-3), end: day(-2))))
        XCTAssertTrue(reached(5, DateInterval(start: today.addingTimeInterval(-TimeInterval.minutes(10)), end: today)))
        // everything (a wipe, a time zone change)
        XCTAssertTrue(reached(5, nil))
        // a change missed in between (only the newest delivered after the background): it may have reached it
        XCTAssertTrue(reached(7, reading))
        // already accounted for (read by its load)
        XCTAssertFalse(reached(4, nil))
        XCTAssertFalse(reached(3, DateInterval(start: day(-3), end: day(-2))))
    }

    @MainActor func testUsualDayIsDrawnFromAFewDaysAndMarkedAsTheAGPMarksIt() {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        freeAPSSettings.low = 70
        freeAPSSettings.high = 145
        let settings = Stat.StatsSettings(freeAPSSettings)
        let now = Self.day0.addingTimeInterval(.hours(12))
        /// 06:00–06:15 on each of the last `days` days
        func readings(days: Int) -> [GlucosePoint] {
            (0 ..< days).reversed().flatMap { points(from: day(-$0).addingTimeInterval(.hours(6)), every: .minutes(5), count: 3) }
        }
        func usualDay(_ series: [GlucosePoint]) -> (usual: Stat.UsualDay, summary: GlucoseSummary) {
            let c = compute(.days14, series, now: now, bands: settings.bands)
            let bins = Engine.agp(c.w, calendar: calendar, clippedTo: c.window)
            return (
                Stat.UsualDay(Stat.UsualDayResult(period: .days14, bins: bins, summary: c.summary)),
                c.summary
            )
        }

        // two days with readings: not drawn, one line says why
        let two = usualDay(readings(days: 2))
        XCTAssertEqual(two.summary.daysWithData, 2)
        XCTAssertFalse(Engine.usualDayIsDrawn(two.summary))
        XCTAssertFalse(two.usual.isDrawn)
        XCTAssertEqual(two.usual.tooFewText, "Too few days with readings for a usual day: 2 of the last 14.")
        XCTAssertNil(two.usual.profileNote)

        // three: drawn, limited as the AGP is (fewer than 14 days with data): the AGP's mark, its note
        let three = usualDay(readings(days: 3))
        XCTAssertEqual(three.summary.daysWithData, 3)
        XCTAssertTrue(three.usual.isDrawn)
        XCTAssertTrue(Engine.agpIsLimited(three.summary))
        XCTAssertNil(three.usual.tooFewText)
        XCTAssertEqual(three.usual.label, "Usual · last 14 days")
        XCTAssertEqual(three.usual.profileNote, StatsFormatting.profileNote(three.summary))
        XCTAssertNotNil(three.usual.profileNote)

        // 14 complete days: not limited
        let full = usualDay(points(from: day(-13), every: .minutes(5), count: 13 * 288 + 144))
        XCTAssertEqual(full.summary.daysWithData, 14)
        XCTAssertFalse(Engine.agpIsLimited(full.summary))
        XCTAssertEqual(full.usual.label, "Usual · last 14 days")
        XCTAssertNil(full.usual.profileNote)
    }

    @MainActor func testUsualDayLabel() {
        let now = Self.day0.addingTimeInterval(.hours(12))
        let summary = compute(.days30, points(from: day(-13), every: .minutes(5), count: 13 * 288 + 144), now: now).summary
        // 14 of 30 days with readings: limited
        let usual = Stat.UsualDay(Stat.UsualDayResult(period: .days30, bins: usualDayBins(), summary: summary))
        XCTAssertEqual(usual.label, "Usual · last 30 days")
    }

    // MARK: - Limited-data marks

    /// The marks' notes (`StatsFormatting.coverageNote`, `.a1cNote`, `.profileNote`) say the rule, never the counts:
    /// the same text for 1 day with readings as for 13, for 10% coverage as for 69%.
    @MainActor func testLimitedDataNotesSayTheRuleNotTheCounts() {
        func days(_ calendarDays: Int, withData daysWithData: Int) -> GlucoseSummary {
            summary(of: histogram([(120, 3600)]), duration: 3600, calendarDays: calendarDays, daysWithData: daysWithData)
        }
        func covered(_ fraction: Double, days: Int) -> GlucoseSummary {
            summary(of: histogram([(120, 3600)]), duration: 3600 / fraction, calendarDays: days, daysWithData: days)
        }
        let fewDaysA1c = "GMI and eA1c are meant for 14 or more days with readings; this period has fewer."
        let fewDaysProfile = "A glucose profile is meant for 14 or more days with readings; this period has fewer."
        let lowCoverage = "CGM readings cover less than 70% of this period, so these numbers may not represent it."

        // A1c: fewer than 14 days with readings
        XCTAssertEqual(StatsFormatting.a1cNote(days(1, withData: 1)), fewDaysA1c)
        XCTAssertEqual(StatsFormatting.a1cNote(days(13, withData: 9)), fewDaysA1c)
        XCTAssertNil(StatsFormatting.a1cNote(days(14, withData: 14)))
        // without readings the estimates are dashes: nothing to mark
        let none = summary(of: GlucoseHistogram(), duration: 3600, calendarDays: 1, daysWithData: 0)
        XCTAssertTrue(none.a1cNeedsMoreDays)
        XCTAssertNil(none.mean)
        XCTAssertNil(StatsFormatting.a1cNote(none))

        // coverage: the rounded percent below 70
        let sparse = covered(0.55, days: 14)
        XCTAssertEqual(sparse.coveragePercent, 55)
        XCTAssertEqual(StatsFormatting.coverageNote(sparse), lowCoverage)
        XCTAssertEqual(StatsFormatting.coverageNote(covered(0.1, days: 14)), lowCoverage)
        XCTAssertNil(StatsFormatting.coverageNote(covered(0.7, days: 14)))

        // the profile: the days, the coverage, or both (the days first)
        XCTAssertNil(StatsFormatting.profileNote(days(14, withData: 14)))
        XCTAssertNil(StatsFormatting.profileNote(days(90, withData: 14)))
        XCTAssertEqual(StatsFormatting.profileNote(days(7, withData: 7)), fewDaysProfile)
        XCTAssertEqual(StatsFormatting.profileNote(days(14, withData: 13)), fewDaysProfile)
        XCTAssertEqual(StatsFormatting.profileNote(sparse), lowCoverage)
        XCTAssertEqual(StatsFormatting.profileNote(covered(0.55, days: 7)), fewDaysProfile + " " + lowCoverage)

        // no count in any of them
        let notes = [fewDaysA1c, fewDaysProfile, lowCoverage]
        for count in ["1 day", "9", "13", "55"] {
            XCTAssertTrue(notes.allSatisfy { !$0.contains(count) }, count)
        }
    }

    /// The Overview, the AGP and the Home card mark the same values by the same rules.
    @MainActor func testLimitedDataMarksAgreeAcrossTheViews() {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        let settings = Stat.StatsSettings(freeAPSSettings)
        let summaries = [
            summary(of: histogram([(120, 3600)]), duration: 3600, calendarDays: 1, daysWithData: 1),
            summary(of: histogram([(120, 3600)]), duration: 3600, calendarDays: 14, daysWithData: 14),
            summary(of: histogram([(120, 3600)]), duration: 3600 / 0.5, calendarDays: 14, daysWithData: 14),
            summary(of: histogram([(120, 3600)]), duration: 3600 / 0.5, calendarDays: 7, daysWithData: 7)
        ]
        for (index, summary) in summaries.enumerated() {
            let overview = Stat.Overview(summary, period: .days14, settings: settings)
            XCTAssertEqual(overview.coverageNote, StatsFormatting.coverageNote(summary), "\(index)")
            XCTAssertEqual(overview.isLimited, summary.isLimited, "\(index)")
            XCTAssertEqual(overview.a1cNote, StatsFormatting.a1cNote(summary), "\(index)")

            let agp = Stat.AGP(
                Stat.AGPResult(bins: [], points: [], axis: 40 ... 300, summary: summary),
                period: .days14,
                settings: settings
            )
            XCTAssertEqual(agp.coverageNote, overview.coverageNote, "\(index)")
            XCTAssertEqual(agp.profileNote, StatsFormatting.profileNote(summary), "\(index)")
            // In range as the Overview's headline, the A1c estimates as its tiles
            XCTAssertEqual(
                agp.tiles.map(\.limitedNote),
                [overview.coverageNote, nil, nil, nil, overview.a1cNote, overview.a1cNote],
                "\(index)"
            )
            // the values themselves are never marked in the text ("6.9*" before)
            XCTAssertEqual(agp.tiles[4].value, overview.gmi, "\(index)")

            let home = HomeStatsBar.Content(summary, period: .days14, settings: settings)
            XCTAssertEqual(home.isLimited, overview.coverageNote != nil, "\(index)")
            // the GMI line by the Overview's A1c rule: hidden where the Overview marks its GMI as limited
            let gmi = HomeStatsBar.Content(summary, gmi: summary, period: .today, settings: settings).gmi
            XCTAssertEqual(gmi == nil, overview.a1cNote != nil, "\(index)")
            if let gmi {
                XCTAssertEqual(gmi.value, overview.gmi, "\(index)")
            }
        }
    }

    /// The Home card shows no coverage percent any more: two limited results that differ only in it are equal (no
    /// re-render of Home).
    @MainActor func testHomeCardLimitedMarkDoesNotChangeWithTheCoverage() {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        let settings = Stat.StatsSettings(freeAPSSettings)
        func covered(_ fraction: Double) -> HomeStatsBar.Content {
            HomeStatsBar.Content(
                summary(of: histogram([(120, 3600)]), duration: 3600 / fraction, calendarDays: 1, daysWithData: 1),
                period: .today,
                settings: settings
            )
        }
        XCTAssertTrue(covered(0.4).isLimited)
        XCTAssertEqual(covered(0.4), covered(0.6))
        XCTAssertNotEqual(covered(0.6), covered(0.9))
    }

    /// The header's glucose range: the Overview's, and without its unit where that doesn't fit.
    @MainActor func testHomeStatsBarGlucoseRange() {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        let settings = Stat.StatsSettings(freeAPSSettings)
        let bar = summary(of: histogram([(120, 3600)]), duration: 3600)
        let card = HomeStatsBar.Content(bar, period: .last24h, settings: settings)
        XCTAssertEqual(card.inRangeRange, Stat.Overview(bar, period: .last24h, settings: settings).inRangeRange)
        XCTAssertFalse(card.inRangeBounds.isEmpty)
        XCTAssertEqual(card.inRangeRange, card.inRangeBounds + " " + StatsFormatting.unit(.mgdL))

        let none = summary(of: GlucoseHistogram(), duration: 3600, calendarDays: 1, daysWithData: 0)
        let empty = HomeStatsBar.Content(none, period: .today, settings: settings)
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - Home stats bar: TITR

    /// The stats bar's TITR split: the tight part drawn in the in-range segment is the time inside both the in-range
    /// band and 70–140; the figure is the standard 70–140 share. They agree for a band containing 70–140 and part at
    /// its edges otherwise: by the time in 70 up to the low edge, and in the high edge up to 140.
    @MainActor func testHomeStatsBarTITRSplit() throws {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        let settings = Stat.StatsSettings(freeAPSSettings)
        // an hour at each, 6 h
        let hours = histogram([(60, 3600), (75, 3600), (100, 3600), (130, 3600), (150, 3600), (200, 3600)])
        func summary(_ bands: StatsBands) -> GlucoseSummary {
            Engine.summary(
                hours,
                window: DateInterval(start: Self.day0, duration: hours.totalSeconds),
                endRule: .stalled,
                calendarDays: 1,
                daysWithData: 1,
                bands: bands
            )
        }

        // 70–180 contains 70–140: drawn and figure the same, 75, 100 and 130 (3 of the 4 in-range hours)
        let wide = summary(StatsBands(low: 70, high: 180, units: .mgdL))
        XCTAssertEqual(wide.titrFraction, 3.0 / 6, accuracy: 1E-9)
        XCTAssertEqual(wide.tightInRangeFraction, wide.titrFraction, accuracy: 1E-9)
        XCTAssertEqual(HomeStatsBar.Content.tightShare(wide), 0.75)

        // 80–180: the hour at 75 is TITR but not in range: drawn 2 h, the figure 3 h
        let higher = summary(StatsBands(low: 80, high: 180, units: .mgdL))
        XCTAssertEqual(higher.tightInRangeFraction, 2.0 / 6, accuracy: 1E-9)
        XCTAssertEqual(higher.titrFraction, 3.0 / 6, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(HomeStatsBar.Content.tightShare(higher)), 0.667, accuracy: 1E-9)

        // 70–120: the hour at 130 is TITR but above the range: drawn 2 h, all of the in-range segment
        let lower = summary(StatsBands(low: 70, high: 120, units: .mgdL))
        XCTAssertEqual(lower.tightInRangeFraction, 2.0 / 6, accuracy: 1E-9)
        XCTAssertEqual(lower.titrFraction, 3.0 / 6, accuracy: 1E-9)
        XCTAssertEqual(HomeStatsBar.Content.tightShare(lower), 1)

        // 150–180 misses 70–140: no tight part, the figure as ever
        let apart = summary(StatsBands(low: 150, high: 180, units: .mgdL))
        XCTAssertEqual(apart.tightInRangeFraction, 0)
        XCTAssertEqual(HomeStatsBar.Content.tightShare(apart), 0)
        XCTAssertEqual(apart.titrFraction, 3.0 / 6, accuracy: 1E-9)

        // mmol 3.9–10.0 (70...181) contains 3.9–7.8 (70...141): the same
        let mmol = summary(StatsBands(low: 70, high: 180, units: .mmolL))
        XCTAssertEqual(mmol.tightInRangeFraction, mmol.titrFraction, accuracy: 1E-9)

        // no readings, no in-range time: none
        let none = Engine.summary(
            GlucoseHistogram(),
            window: DateInterval(start: Self.day0, duration: 3600),
            endRule: .stalled,
            calendarDays: 1,
            daysWithData: 0,
            bands: bands
        )
        XCTAssertEqual(none.tightInRangeFraction, 0)
        XCTAssertNil(HomeStatsBar.Content.tightShare(none))
        XCTAssertNil(HomeStatsBar.Content.tightShare(summary(StatsBands(low: 210, high: 250, units: .mgdL))))

        // on the card: the figure is the Overview's TITR; the segments and the main number are the Overview's, TITR
        // shown or not (it is drawn over the bar)
        let card = HomeStatsBar.Content(higher, period: .last24h, settings: settings)
        let overview = Stat.Overview(higher, period: .last24h, settings: settings)
        XCTAssertEqual(card.titr, overview.titr)
        XCTAssertEqual(card.titr, StatsFormatting.percent(50))
        XCTAssertEqual(card.inRangePercent, overview.inRangePercent)
        XCTAssertEqual(card.segments.map(\.band), overview.segments.map(\.band))
        XCTAssertEqual(try XCTUnwrap(card.tightShare), 0.667, accuracy: 1E-9)
        XCTAssertNil(HomeStatsBar.Content(none, period: .today, settings: settings).tightShare)
    }

    /// Where the tight part is drawn: after the segments before the in-range one (the bar's widths; the overlay's HStack
    /// has the bar's 2 pt gaps), its share of the segment's width.
    @MainActor func testHomeStatsBarTightPart() throws {
        let segments = [
            BandSegment(band: .low, fraction: 0.25),
            BandSegment(band: .inRange, fraction: 0.5),
            BandSegment(band: .high, fraction: 0.25)
        ]
        // 202 pt: 198 for the segments, 49.5, 99, 49.5
        let part = try XCTUnwrap(HomeStatsBar.Content.tightPart(segments, share: 0.75, width: 202))
        XCTAssertEqual(part.before.count, 1)
        XCTAssertEqual(part.before[0], 49.5, accuracy: 1E-9)
        XCTAssertEqual(part.width, 74.25, accuracy: 1E-9)
        // laid out with the gaps: from 51.5 pt, the in-range segment's start
        XCTAssertEqual(part.before.reduce(0, +) + StatsSplitBar.gap * CGFloat(part.before.count), 51.5, accuracy: 1E-9)
        // the segment first: from the bar's start
        let first = try XCTUnwrap(HomeStatsBar.Content.tightPart(
            [BandSegment(band: .inRange, fraction: 1)],
            share: 0.5,
            width: 100
        ))
        XCTAssertEqual(first.before, [])
        XCTAssertEqual(first.width, 50, accuracy: 1E-9)
        // none
        XCTAssertNil(HomeStatsBar.Content.tightPart(segments, share: nil, width: 202))
        XCTAssertNil(HomeStatsBar.Content.tightPart(segments, share: 0, width: 202))
        XCTAssertNil(HomeStatsBar.Content.tightPart(
            [BandSegment(band: .high, fraction: 1)],
            share: 0.5,
            width: 100
        ))
    }

    // MARK: - Home stats bar: the GMI line

    /// The last 90 days' summary: `daysWithData` of its 90, the mean 120 mg/dL.
    private func ninetyDays(withData days: Int) -> GlucoseSummary {
        summary(of: histogram([(120, 3600)]), duration: 3600, calendarDays: 90, daysWithData: days)
    }

    /// The GMI line: shown from 14 days with readings on (the Overview's A1c rule), with the days in its title, 90 at
    /// most; hidden below 14, without readings, and without a 90-day summary. The value and the unit are the
    /// Overview's.
    @MainActor func testHomeStatsBarGMILine() throws {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        let settings = Stat.StatsSettings(freeAPSSettings)
        XCTAssertEqual(settings.hbA1cUnit, .percent)
        let bar = summary(of: histogram([(120, 3600)]), duration: 3600)

        let line = try XCTUnwrap(HomeStatsBar.Content.gmiLine(ninetyDays(withData: 37), settings: settings))
        XCTAssertEqual(line.title, "37-day GMI")
        XCTAssertEqual(line.value, StatsFormatting.a1c(GlucoseStatsEngine.gmiPercent(meanMgdl: 120), unit: .percent))
        XCTAssertEqual(line.unit, "%")
        // as the Overview of the same 90 days shows it
        let overview = Stat.Overview(ninetyDays(withData: 37), period: .days90, settings: settings)
        XCTAssertEqual(line.value, overview.gmi)
        XCTAssertEqual(line.unit, overview.a1cUnit)

        // on the card, beside its own range
        let card = HomeStatsBar.Content(bar, gmi: ninetyDays(withData: 37), period: .today, settings: settings)
        XCTAssertEqual(card.gmi, line)
        XCTAssertNil(HomeStatsBar.Content(bar, period: .today, settings: settings).gmi)

        // 14 days: shown; 13: hidden (the Overview marks its GMI there); no readings: hidden
        XCTAssertEqual(HomeStatsBar.Content.gmiLine(ninetyDays(withData: 14), settings: settings)?.title, "14-day GMI")
        XCTAssertNil(HomeStatsBar.Content.gmiLine(ninetyDays(withData: 13), settings: settings))
        XCTAssertNotNil(StatsFormatting.a1cNote(ninetyDays(withData: 13)))
        XCTAssertNil(HomeStatsBar.Content.gmiLine(
            summary(of: GlucoseHistogram(), duration: 3600, calendarDays: 90, daysWithData: 90),
            settings: settings
        ))
        XCTAssertNil(HomeStatsBar.Content.gmiLine(nil, settings: settings))
        XCTAssertNil(HomeStatsBar.Content(bar, gmi: ninetyDays(withData: 13), period: .last24h, settings: settings).gmi)

        // every day of the 90: "90-day", never more
        XCTAssertEqual(HomeStatsBar.Content.gmiLine(ninetyDays(withData: 90), settings: settings)?.title, "90-day GMI")
        XCTAssertEqual(HomeStatsBar.Content.gmiLine(ninetyDays(withData: 95), settings: settings)?.title, "90-day GMI")

        // the HbA1c unit setting: mmol/mol, as the Overview's
        freeAPSSettings.overrideHbA1cUnit = true
        let ifcc = Stat.StatsSettings(freeAPSSettings)
        XCTAssertEqual(ifcc.hbA1cUnit, .mmolPerMol)
        let mmol = try XCTUnwrap(HomeStatsBar.Content.gmiLine(ninetyDays(withData: 37), settings: ifcc))
        XCTAssertEqual(mmol.unit, "mmol/mol")
        XCTAssertEqual(mmol.value, Stat.Overview(ninetyDays(withData: 37), period: .days90, settings: ifcc).gmi)
    }

    /// The days of the GMI line are the Overview's days with data: a day counts when a reading starts in it, of the
    /// 90 calendar days of `Home.gmiPeriod` (`GlucoseStatsEngine.dayCounts`).
    func testHomeStatsBarGMIDaysAreTheDaysWithReadings() {
        XCTAssertEqual(Home.gmiPeriod, .days90)
        XCTAssertEqual(Home.gmiPeriod.calendarDayCount, 90)
        let empty = DayAggregate(day: DateInterval(start: Self.day0, duration: 86400), histogram: GlucoseHistogram())
        let withReading = DayAggregate(
            day: DateInterval(start: day(1), duration: 86400),
            histogram: histogram([(120, 300)], at: day(1))
        )
        let counts = Engine.dayCounts(.days90, days: [empty, withReading, withReading])
        XCTAssertEqual(counts.calendarDays, 90)
        XCTAssertEqual(counts.daysWithData, 2)
    }
}
