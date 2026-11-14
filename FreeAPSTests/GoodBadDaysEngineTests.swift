@testable import FreeAPS
import XCTest

private typealias Engine = GoodBadDaysEngine
private typealias GlucoseEngine = GlucoseStatsEngine

final class GoodBadDaysEngineTests: XCTestCase {
    // MARK: - fixtures

    private let calendar = StatsFixtures.berlin
    private let bands = StatsBands(low: 70, high: 180, units: .mgdL)

    /// 2026-09-01 00:00 Europe/Berlin: 54 days of 24 hours follow (to the change to CET on 25 Oct)
    private var start: Date { calendar.date(byAdding: .day, value: -49, to: StatsFixtures.day0)! }

    /// The whole calendar day `offset` days after `start`.
    private func interval(_ offset: Int, from start: Date? = nil) -> DateInterval {
        let dayStart = calendar.date(byAdding: .day, value: offset, to: start ?? self.start)!
        return DateInterval(start: dayStart, end: StatsClock.endOfDay(dayStart, calendar: calendar))
    }

    /// A day's aggregate: `percent` of the day at each value, the rest without data.
    private func aggregate(_ offset: Int, _ entries: [(mgdl: Int16, percent: Double)]) -> DayAggregate {
        let day = interval(offset)
        var histogram = GlucoseHistogram()
        for entry in entries {
            let seconds = entry.percent * day.duration / 100
            histogram.add(WeightedPoint(time: day.start, mgdl: entry.mgdl, span: seconds), seconds: seconds, startsInside: true)
        }
        return DayAggregate(day: day, histogram: histogram)
    }

    /// A good day: all of it at `mgdl`.
    private func good(_ offset: Int, _ mgdl: Int16 = 120) -> DayAggregate {
        aggregate(offset, [(mgdl, 100)])
    }

    /// A day 10 % at 60 (GRI 24).
    private func low(_ offset: Int) -> DayAggregate {
        aggregate(offset, [(60, 10), (120, 90)])
    }

    /// A day 60 % at 220 (GRI 48).
    private func high(_ offset: Int) -> DayAggregate {
        aggregate(offset, [(220, 60), (120, 40)])
    }

    private func result(
        _ days: [DayAggregate],
        readings w: [WeightedPoint] = [],
        bands: StatsBands? = nil
    ) -> GoodBadDaysResult {
        Engine.result(period: .days30, days: days, readings: w, bands: bands ?? self.bands, calendar: calendar)
    }

    private func score(_ day: DayAggregate, bands: StatsBands? = nil) -> GoodBadDaysResult.ScoredDay? {
        Engine.score(day, nightTIR: nil, bands: bands ?? self.bands, calendar: calendar)
    }

    private func starts(_ group: GoodBadDaysResult.Group) -> [Date] {
        group.days.map(\.day.start)
    }

    /// Readings every 5 minutes over the days, oldest -> newest, weighed.
    private func readings(_ days: [DateInterval], value: (DateInterval, TimeInterval) -> Int16) -> [WeightedPoint] {
        let points = days.flatMap { day in
            stride(from: 0, to: day.duration, by: 300).map { offset in
                GlucosePoint(time: day.start.addingTimeInterval(offset), mgdl: value(day, offset))
            }
        }
        return GlucoseEngine.weigh(GlucoseEngine.clean(points))
    }

    /// 96 AGP bins with the median a function of the bin; the IQR ±10 around it.
    private func bins(_ p50: (Int) -> Double?) -> [AGPBin?] {
        (0 ..< 96).map { index in
            p50(index).map {
                AGPBin(startMinute: index * 15, p5: $0 - 30, p25: $0 - 10, p50: $0, p75: $0 + 10, p95: $0 + 30, seconds: 900)
            }
        }
    }

    /// The compared group's bins: the reference's 120 plus Δ by clock hour.
    private func highlights(_ delta: (Int) -> Double?) -> [GoodBadDaysResult.Highlight] {
        Engine.highlights(reference: bins { _ in 120 }, compared: bins { index in delta(index / 4).map { 120 + $0 } })
    }

    // MARK: - Scores

    /// 1 % very low, 3 % low, 20 % high, 5 % very high: GRI 34.2 (zone B), the shares of the covered time, the mean.
    func testADaysScore() {
        guard let day = score(aggregate(0, [(50, 1), (60, 3), (120, 71), (200, 20), (300, 5)])) else {
            return XCTFail("scored")
        }
        XCTAssertEqual(day.key, StatsDayKey(start, calendar))
        XCTAssertEqual(day.key.month, 9)
        XCTAssertEqual(day.day, interval(0))
        XCTAssertEqual(day.gri.hypo, 3.4, accuracy: 1E-9)
        XCTAssertEqual(day.gri.hyper, 15, accuracy: 1E-9)
        XCTAssertEqual(day.gri.value, 34.2, accuracy: 1E-9)
        XCTAssertEqual(day.gri.zone, .b)
        XCTAssertEqual(day.tir, 0.71, accuracy: 1E-9)
        XCTAssertEqual(day.below70, 0.04, accuracy: 1E-12)
        XCTAssertEqual(day.mean, 142.5, accuracy: 1E-9)
        XCTAssertEqual(day.coverage, 1, accuracy: 1E-9)
        XCTAssertEqual(day.shares.percents, [1, 3, 71, 20, 5])
        XCTAssertNil(day.nightTIR)
    }

    /// A day is scored with a coverage of 70 % as shown (rounded, `GlucoseSummary.isLimited`'s rule); the days left
    /// out are counted.
    func testNoDaysAndNoScoredDays() {
        let empty = result([])
        XCTAssertEqual(empty.scored, 0)
        XCTAssertEqual(empty.unscored, 0)
        XCTAssertEqual(empty.window.duration, 0)
        XCTAssertEqual(empty.axis, GlucoseEngine.agpAxis([]))
        XCTAssertEqual(empty.lowTreatmentTimes, [])

        // two days with too little CGM data, readings at night on both
        let days = [good(0).withCoverage(40), aggregate(1, [])]
        let w = readings([interval(0), interval(1)].map { DateInterval(start: $0.start, duration: .hours(2)) }) { _, _ in 60 }
        let unscored = result(days, readings: w)
        XCTAssertEqual(unscored.scored, 0)
        XCTAssertEqual(unscored.unscored, 2)
        XCTAssertEqual(unscored.window, DateInterval(start: interval(0).start, end: interval(1).end))
        XCTAssertEqual(unscored.lowTreatmentTimes.count, 2)

        for result in [empty, unscored] {
            let split = result.thirds
            XCTAssertTrue(split.reference.days.isEmpty)
            XCTAssertTrue(split.compared.days.isEmpty)
            XCTAssertEqual(split.reference.bins, [])
            XCTAssertEqual(split.leftOut, 0)
            XCTAssertEqual(split.highlights, [])
            XCTAssertFalse(split.isComparable)
            XCTAssertTrue(split.glucoseRows.allSatisfy { !$0.isShown })
        }
    }

    func testDaysWithTooLittleCGMDataAreLeftOut() {
        XCTAssertNil(score(good(0).withCoverage(69.4)))
        XCTAssertNotNil(score(good(0).withCoverage(69.6)))
        XCTAssertNotNil(score(good(0).withCoverage(70)))
        XCTAssertNil(score(aggregate(0, [])))

        let days = (0 ..< 14).map { $0 == 3 ? good($0).withCoverage(50) : good($0) }
        let result = result(days + [aggregate(14, [])])
        XCTAssertEqual(result.scored, 13)
        XCTAssertEqual(result.unscored, 2)
        XCTAssertEqual(result.window, DateInterval(start: start, end: interval(14).end))
        XCTAssertFalse((result.thirds.reference.days + result.thirds.compared.days).contains { $0.day == interval(3) })
    }

    /// The Statistics low/high settings change the days' band bars, never their scores or groups.
    func testTheSettingsNeverMoveADayBetweenGroups() {
        let days = (0 ..< 30).map { offset -> DayAggregate in
            switch offset % 4 {
            case 0: return good(offset, Int16(90 + offset))
            case 1: return low(offset)
            case 2: return high(offset)
            default: return aggregate(offset, [(150, 60), (190, 40)])
            }
        }
        let standard = result(days)
        let narrow = result(days, bands: StatsBands(low: 90, high: 140, units: .mgdL))
        let a = standard.thirds
        let b = narrow.thirds
        XCTAssertEqual(a.reference.days.map(\.key), b.reference.days.map(\.key))
        XCTAssertEqual(a.compared.days.map(\.key), b.compared.days.map(\.key))
        XCTAssertEqual(a.reference.days.map(\.gri), b.reference.days.map(\.gri))
        XCTAssertEqual(a.glucoseRows, b.glucoseRows)
        // the worst third has the days at 150 / 190: in range and high, or high only
        XCTAssertNotEqual(standard.thirds.compared.days.map(\.shares), narrow.thirds.compared.days.map(\.shares))
    }

    /// mmol users' `tirRange` ends at 181 (10.0 mmol/L): 181 is in range for them, high for mg/dL users.
    func testTheMmolTIRTopIs181() {
        let day = aggregate(0, [(181, 55), (120, 45)])
        let mmol = StatsBands(low: Decimal(string: "3.9")!.asMgdL, high: Decimal(string: "10.0")!.asMgdL, units: .mmolL)
        guard let mgdl = score(day), let mmolDay = score(day, bands: mmol) else { return XCTFail("scored") }
        XCTAssertEqual(mgdl.tir, 0.45, accuracy: 1E-12)
        XCTAssertEqual(mgdl.gri.value, 0.8 * 55, accuracy: 1E-9)
        XCTAssertEqual(mmolDay.tir, 1, accuracy: 1E-12)
        XCTAssertEqual(mmolDay.gri.value, 0)
    }

    // MARK: - The thirds

    func testThirdSizes() {
        XCTAssertEqual(Engine.thirdSize(0), 0)
        XCTAssertEqual(Engine.thirdSize(2), 1)
        XCTAssertEqual(Engine.thirdSize(13), 4)
        XCTAssertEqual(Engine.thirdSize(14), 5)
        XCTAssertEqual(Engine.thirdSize(30), 10)
        XCTAssertEqual(Engine.thirdSize(90), 30)
    }

    /// The best k and the worst k by GRI, each oldest -> newest, the days between left out: 14 days give 5 / 4 / 5,
    /// 30 give 10 / 10 / 10, 90 give 30 / 30 / 30 (a 25-hour day among them).
    func testTheThirdsAreTheBestAndWorstByGRI() {
        for (count, k) in [(14, 5), (30, 10), (90, 30)] {
            // the share high grows day by day: the newest days the worst
            let days = (0 ..< count).map { offset -> DayAggregate in
                let high = Double(offset) * 100 / Double(count)
                return aggregate(offset, [(200, high), (120, 100 - high)])
            }
            let result = result(days)
            XCTAssertEqual(result.thirds.reference.days.count, k)
            XCTAssertEqual(starts(result.thirds.reference), (0 ..< k).map { interval($0).start }, "\(count)")
            XCTAssertEqual(starts(result.thirds.compared), (count - k ..< count).map { interval($0).start }, "\(count)")
            XCTAssertEqual(result.thirds.leftOut, count - 2 * k)
            XCTAssertTrue(result.thirds.isComparable)
        }
    }

    /// Equal GRIs rank by the lower time below 70, then the lower mean, then the newer day.
    func testThirdsTies() {
        let days = [
            good(0, 120),
            good(1, 100),
            good(2, 100), // as day 1, newer: before it
            aggregate(3, [(40, 40), (120, 60)]), // GRI 100 (capped), 40 % below 70
            aggregate(4, [(300, 100)]), // GRI 100 (capped), none below 70: before day 3
            aggregate(5, [(300, 100)]) // as day 4, newer: before it
        ]
        let ranked = days.compactMap { score($0) }.sorted(by: Engine.ranksBefore).map(\.day.start)
        XCTAssertEqual(ranked, [2, 1, 0, 5, 4, 3].map { interval($0).start })

        let result = result(days)
        // k = 2: the best two and the worst two, oldest -> newest
        XCTAssertEqual(starts(result.thirds.reference), [1, 2].map { interval($0).start })
        XCTAssertEqual(starts(result.thirds.compared), [3, 4].map { interval($0).start })
        XCTAssertEqual(result.thirds.leftOut, 2)
    }

    /// 14 days with one left out: thirds of 4, too few to show: no band, no highlights, no rows. With all 14 scored,
    /// thirds of 5, shown and marked as limited (under 10).
    func testFourteenDaysWithAnUnscoredDayGiveThirdsOfFour() {
        var days = (0 ..< 14).map { good($0, Int16(90 + $0)) }
        let all = result(days)
        XCTAssertEqual(all.thirds.reference.days.count, 5)
        XCTAssertTrue(all.thirds.isComparable)
        XCTAssertTrue(all.thirds.compared.isShown)
        XCTAssertTrue(all.thirds.compared.isLimited)

        days[6] = aggregate(6, [(120, 40)])
        let oneLeftOut = result(days)
        XCTAssertEqual(oneLeftOut.unscored, 1)
        XCTAssertEqual(oneLeftOut.thirds.reference.days.count, 4)
        XCTAssertEqual(oneLeftOut.thirds.compared.days.count, 4)
        XCTAssertEqual(oneLeftOut.thirds.leftOut, 5)
        XCTAssertFalse(oneLeftOut.thirds.reference.isShown)
        XCTAssertFalse(oneLeftOut.thirds.isComparable)
        XCTAssertEqual(oneLeftOut.thirds.reference.bins, [])
        XCTAssertEqual(oneLeftOut.thirds.compared.points, [])
        XCTAssertEqual(oneLeftOut.thirds.highlights, [])
        XCTAssertTrue(oneLeftOut.thirds.glucoseRows.allSatisfy { !$0.isShown })
    }

    // MARK: - The profiles

    /// The thirds' profiles are the AGP of their days (readings across each midnight, the lookback before the first
    /// day); the points are on the result's axis.
    func testAGroupsProfileIsTheAGPOfItsDays() {
        let intervals = (0 ..< 14).map { interval($0) }
        let window = DateInterval(start: intervals[0].start, end: intervals[13].end)
        let first = intervals[0].start.addingTimeInterval(-.hours(1) + .minutes(2))
        let points = (0 ..< 15 * 288).map { index -> GlucosePoint in
            let mgdl = 90 + (index * 7) % 80
            return GlucosePoint(time: first.addingTimeInterval(Double(index) * 300), mgdl: Int16(mgdl))
        }
        let w = GlucoseEngine.weigh(GlucoseEngine.clean(points))
        let result = result(GlucoseEngine.dayAggregates(w, days: intervals), readings: w)
        XCTAssertEqual(result.window, window)

        let groups = [result.thirds.reference, result.thirds.compared]
        for group in groups {
            XCTAssertEqual(group.days.count, 5)
            XCTAssertEqual(group.bins, GlucoseEngine.agp(w, calendar: calendar, days: group.days.map(\.day)))
            XCTAssertEqual(group.points, GlucoseEngine.agpPlotPoints(group.bins, axis: result.axis))
            // the night TIRs, from the same pass: all in range
            XCTAssertTrue(group.days.allSatisfy { $0.nightTIR == 1 })
        }
        XCTAssertEqual(result.axis, GlucoseEngine.agpAxis(groups.flatMap(\.bins)))
    }

    /// A reading across midnight into a day of another group gives that day its part, at the reading's clock time;
    /// the night TIR counts it by its clock time too (23:55 isn't night).
    func testAGroupsProfileSplitsAReadingAcrossMidnight() {
        let days = [interval(0), interval(1)]
        let w = [
            // 23:55 to 00:05
            WeightedPoint(time: days[1].start.addingTimeInterval(-.minutes(5)), mgdl: 150, span: .minutes(10)),
            WeightedPoint(time: days[1].start.addingTimeInterval(.minutes(5)), mgdl: 100, span: .minutes(5))
        ]
        let profiles = Engine.profiles(
            w,
            days: days,
            groups: [[0], [1]],
            groupCount: 3,
            nightRange: 70 ... 180,
            calendar: calendar
        )
        XCTAssertEqual(profiles.bins.count, 3)
        // pooled with its neighbours: group 0 has 23:55-24:00 only, group 1 the 23:55 reading's 5 minutes after midnight
        // (in bin 95, its clock time) and the 00:05 one (bin 0)
        XCTAssertEqual(profiles.bins[0][95]?.seconds ?? 0, 300, accuracy: 1E-9)
        XCTAssertEqual(profiles.bins[0][95]?.p50 ?? 0, 150, accuracy: 1E-9)
        XCTAssertEqual(profiles.bins[1][95]?.seconds ?? 0, 600, accuracy: 1E-9)
        XCTAssertEqual(profiles.bins[1][1]?.seconds ?? 0, 300, accuracy: 1E-9)
        XCTAssertNil(profiles.bins[1][2])
        XCTAssertEqual(profiles.bins[2], Array(repeating: nil, count: 96))
        XCTAssertEqual(profiles.nightTIR.count, 2)
        XCTAssertNil(profiles.nightTIR[0])
        XCTAssertEqual(profiles.nightTIR[1] ?? 0, 1, accuracy: 1E-12)
    }

    /// DST days: a 25-hour day is scored on its 25 hours and its night 00:00–06:00 has 7 hours (02:00–03:00 twice), a
    /// 23-hour day's has 5.
    func testDSTDays() {
        let fallBack = StatsClock.wholeDay(of: StatsFixtures.fallBack, calendar: calendar)
        let spring = StatsClock.wholeDay(of: StatsFixtures.springForward, calendar: calendar)
        XCTAssertEqual(fallBack.duration, .hours(25))
        XCTAssertEqual(spring.duration, .hours(23))
        // 200 in the 4th hour of the day: 02:00–03:00 CET (the repeated hour) on the 25-hour day, 04:00-05:00 on the
        // 23-hour one
        let w = readings([spring, fallBack]) { _, offset in offset >= .hours(3) && offset < .hours(4) ? 200 : 120 }
        let profiles = Engine.profiles(
            w,
            days: [spring, fallBack],
            groups: [[], []],
            groupCount: 0,
            nightRange: 70 ... 180,
            calendar: calendar
        )
        XCTAssertEqual(profiles.nightTIR[0] ?? 0, 4.0 / 5, accuracy: 1E-9)
        XCTAssertEqual(profiles.nightTIR[1] ?? 0, 6.0 / 7, accuracy: 1E-9)

        let aggregates = GlucoseEngine.dayAggregates(w, days: [spring, fallBack])
        let scored = aggregates.compactMap { score($0) }
        XCTAssertEqual(scored.map(\.coverage), [1, 1])
        XCTAssertEqual(scored[1].tir, 24.0 / 25, accuracy: 1E-9)
        // 24 of the 25 hours: 96 %
        let partial = GlucoseEngine.dayAggregates(
            w.filter { $0.time < fallBack.end.addingTimeInterval(-.hours(1)) },
            days: [fallBack]
        )
        XCTAssertEqual(score(partial[0])?.coverage ?? 0, 0.96, accuracy: 1E-9)
    }

    // MARK: - Highlights

    func testHighlightsNeedAtLeast20() {
        XCTAssertEqual(highlights { _ in 15 }, [])
        XCTAssertEqual(highlights { $0 == 5 ? 19.99 : 0 }, [])
        let stretch = highlights { [3, 4].contains($0) ? 25 : 10 }
        XCTAssertEqual(stretch.map(\.minutes), [180 ..< 300])
        XCTAssertEqual(stretch.first?.reference ?? 0, 120, accuracy: 1E-9)
        XCTAssertEqual(stretch.first?.compared ?? 0, 145, accuracy: 1E-9)
        XCTAssertEqual(stretch.first?.weight ?? 0, 50, accuracy: 1E-9)
        XCTAssertEqual(stretch.first?.isHigher, true)
        // no hour where both groups have data
        XCTAssertEqual(Engine.highlights(reference: bins { _ in 120 }, compared: bins { _ in nil }), [])
        XCTAssertEqual(Engine.highlights(reference: [], compared: []), [])
    }

    /// At least half the largest |Δ|: an hour between two larger ones splits them.
    func testHighlightsNeedHalfTheLargest() {
        let deltas: [Int: Double] = [15: 100, 16: 45, 17: 60]
        let stretches = highlights { deltas[$0] ?? 0 }
        XCTAssertEqual(stretches.map(\.minutes), [900 ..< 960, 1020 ..< 1080])
    }

    /// Adjacent hours of opposite signs are two stretches; a lower compared median is `isHigher` false.
    func testHighlightsKeepTheSign() {
        let deltas: [Int: Double] = [8: 30, 9: 30, 10: -30]
        let stretches = highlights { deltas[$0] ?? 0 }
        XCTAssertEqual(stretches.map(\.minutes), [480 ..< 600, 600 ..< 660])
        XCTAssertEqual(stretches.map(\.isHigher), [true, false])
        XCTAssertEqual(stretches.last?.compared ?? 0, 90, accuracy: 1E-9)
        // across midnight too
        let acrossMidnight: [Int: Double] = [23: 40, 0: -40]
        XCTAssertEqual(highlights { acrossMidnight[$0] ?? 0 }.map(\.minutes), [0 ..< 60, 1380 ..< 1440])
    }

    /// A stretch across midnight is one: 22:00–02:00 is 1320..<1560.
    func testHighlightsWrapAtMidnight() {
        let stretches = highlights { [22, 23, 0, 1].contains($0) ? 40 : 0 }
        XCTAssertEqual(stretches.map(\.minutes), [1320 ..< 1560])
        XCTAssertEqual(stretches.first?.weight ?? 0, 160, accuracy: 1E-9)
        XCTAssertEqual(stretches.first?.compared ?? 0, 160, accuracy: 1E-9)
        // every hour: the whole day, once
        XCTAssertEqual(highlights { _ in 30 }.map(\.minutes), [0 ..< 1440])
    }

    /// At most two stretches, the largest Σ|Δ| first; equal ones the longer first, then the earlier start in the
    /// drawn day (a stretch across midnight starts at its evening hour).
    func testHighlightsAreAtMostTwo() {
        let three: [Int: Double] = [2: 50, 6: 60, 12: 70]
        XCTAssertEqual(highlights { three[$0] ?? 0 }.map(\.minutes), [720 ..< 780, 360 ..< 420])
        XCTAssertEqual(highlights { $0 % 2 == 0 ? 30 : -30 }.map(\.minutes), [0 ..< 60, 60 ..< 120])
        // Σ|Δ| 60 each: two hours of 30 before one of 60
        let longer: [Int: Double] = [3: 60, 8: 30, 9: 30]
        XCTAssertEqual(highlights { longer[$0] ?? 0 }.map(\.minutes), [480 ..< 600, 180 ..< 240])
        // equal and as long: 05:00 before 23:00-01:00
        let wrapped: [Int: Double] = [23: 40, 0: 40, 5: 40, 6: 40]
        XCTAssertEqual(highlights { wrapped[$0] ?? 0 }.map(\.minutes), [300 ..< 420, 1380 ..< 1500])
    }

    /// Δ is over the bins where both groups have data only.
    func testHighlightsUseTheBinsBothGroupsHave() {
        let reference = bins { _ in 120 }
        let compared = bins { index -> Double? in index == 20 ? 160 : (index / 4 == 5 ? nil : 120) }
        XCTAssertEqual(Engine.hourDeltas(reference: reference, compared: compared)[5] ?? 0, 40, accuracy: 1E-9)
        XCTAssertEqual(Engine.highlights(reference: reference, compared: compared).map(\.minutes), [300 ..< 360])
    }

    /// From the readings: the worst third 70 above the best, 210 from 15:00 to 19:00; only those hours are highlighted.
    /// 8 days at 120 and 7 high ones in turn: the best third the 5 newest at 120 (the newer day first on a tie), the
    /// worst the 5 oldest high ones.
    func testHighlightsOfAResult() {
        let highDays = (0 ..< 7).map { interval(2 * $0 + 1) }
        let all = (0 ..< 15).map { interval($0) }
        let w = readings(all) { day, offset in
            guard highDays.contains(day) else { return 120 }
            return offset >= .hours(15) && offset < .hours(19) ? 330 : 190
        }
        let result = result(GlucoseEngine.dayAggregates(w, days: all), readings: w)
        XCTAssertEqual(starts(result.thirds.reference), [6, 8, 10, 12, 14].map { interval($0).start })
        XCTAssertEqual(starts(result.thirds.compared), [1, 3, 5, 7, 9].map { interval($0).start })
        XCTAssertEqual(result.thirds.highlights.map(\.minutes), [900 ..< 1140])
        XCTAssertEqual(result.thirds.highlights.first?.reference ?? 0, 120, accuracy: 1E-9)
        XCTAssertGreaterThan(result.thirds.highlights.first?.compared ?? 0, 300)
        XCTAssertEqual(result.thirds.highlights.first?.isHigher, true)
        XCTAssertEqual(result.axis, GlucoseEngine.agpAxis(result.thirds.reference.bins + result.thirds.compared.bins))
    }

    // MARK: - Glucose rows

    /// The median and the IQR with linear interpolation; at least 5 values.
    func testValuesAndQuantiles() {
        XCTAssertEqual(Engine.values([5, 1, 4, 2, 3]), GoodBadDaysResult.Values(median: 3, p25: 2, p75: 4, n: 5))
        XCTAssertEqual(
            Engine.values([6, 1, 4, 2, 3, 5]),
            GoodBadDaysResult.Values(median: 3.5, p25: 2.25, p75: 4.75, n: 6)
        )
        XCTAssertNil(Engine.values([1, 2, 3, 4]))
        XCTAssertEqual(Engine.quantile([7], 0.25), 7)
        XCTAssertEqual(Engine.quantile([], 0.5), 0)
    }

    /// The rows in their fixed order, each group's values over its days with a value: a row is hidden with 4 (the night
    /// TIR, read for 4 of the best third's days only). 15 days: the best third the 5 days at 100–140, the worst 5 of
    /// the high days (the older ones on a tie), the days at 150 / 190 in between.
    func testGlucoseRows() {
        let days = (0 ..< 6).map { good($0, Int16(100 + 10 * $0)) } + (6 ..< 12).map(high)
            + (12 ..< 15).map { aggregate($0, [(150, 60), (190, 40)]) }
        let nights = (Array(0 ..< 4) + Array(6 ..< 12)).map { DateInterval(start: interval($0).start, duration: .hours(6)) }
        let w = readings(nights) { _, _ in 120 }
        let thirds = result(days, readings: w).thirds
        XCTAssertEqual(starts(thirds.reference), (0 ..< 5).map { interval($0).start })
        XCTAssertEqual(starts(thirds.compared), (6 ..< 11).map { interval($0).start })
        let rows = thirds.glucoseRows
        XCTAssertEqual(rows.map(\.id), GoodBadDaysResult.GlucoseRowID.allCases)
        guard let mean = rows.first(where: { $0.id == .mean }), let night = rows.first(where: { $0.id == .nightTIR }) else {
            return XCTFail("rows")
        }
        XCTAssertTrue(mean.isShown)
        XCTAssertEqual(mean.reference, GoodBadDaysResult.Values(median: 120, p25: 110, p75: 130, n: 5))
        XCTAssertEqual(mean.compared?.median ?? 0, 0.6 * 220 + 0.4 * 120, accuracy: 1E-9)
        XCTAssertNil(night.reference)
        XCTAssertEqual(night.compared, GoodBadDaysResult.Values(median: 1, p25: 1, p75: 1, n: 5))
        XCTAssertFalse(night.isShown)
    }

    // MARK: - Low treatments

    /// During a low (touching readings below 70 one low) or up to 30 minutes after it ends; both ends included,
    /// overlapping times one.
    func testLowTreatmentTimes() {
        let day = interval(0).start
        func at(_ hours: Double, _ minutes: Double = 0) -> Date {
            day.addingTimeInterval(.hours(hours) + .minutes(minutes))
        }
        let w = [
            WeightedPoint(time: at(9, 50), mgdl: 100, span: 600),
            // a 10-minute low
            WeightedPoint(time: at(10), mgdl: 65, span: 300),
            WeightedPoint(time: at(10, 5), mgdl: 60, span: 300),
            WeightedPoint(time: at(10, 10), mgdl: 80, span: .minutes(110))
        ] + (0 ..< 12).map {
            // an hour's low
            WeightedPoint(time: at(12, Double($0) * 5), mgdl: 60, span: 300)
        } + [
            WeightedPoint(time: at(13), mgdl: 90, span: .hours(1)),
            // two lows 20 minutes apart: one time
            WeightedPoint(time: at(14), mgdl: 65, span: 300),
            WeightedPoint(time: at(14, 5), mgdl: 100, span: 900),
            WeightedPoint(time: at(14, 20), mgdl: 65, span: 300),
            WeightedPoint(time: at(14, 25), mgdl: 100, span: 300)
        ]
        let times = Engine.lowTreatmentTimes(w)
        XCTAssertEqual(times, [
            // 10:00-10:10, then 30 minutes
            DateInterval(start: at(10), end: at(10, 40)),
            DateInterval(start: at(12), end: at(13, 30)),
            // 14:00-14:05 and 14:20-14:25, each then 30 minutes
            DateInterval(start: at(14), end: at(14, 55))
        ])
        let expected: [(Date, Bool)] = [
            (at(9, 59), false), (at(10), true), (at(10, 31), true), (at(10, 40), true), (at(10, 41), false),
            (at(12, 59), true), (at(13, 30), true), (at(13, 31), false), (at(14, 50), true), (at(14, 55), true),
            (at(14, 56), false)
        ]
        for (date, isTreatment) in expected {
            XCTAssertEqual(Engine.isLowTreatment(date, in: times), isTreatment, "\(date)")
        }
        XCTAssertFalse(Engine.isLowTreatment(at(10), in: []))
        XCTAssertEqual(result([good(0)], readings: w).lowTreatmentTimes, times)
    }

    // MARK: - Late or no bolus

    /// A meal's first bolus (not an SMB) in [start − 30 min, start + 60 min]: on time up to 15 min after the start, late
    /// after it; none in the window counts as late too. A pre-bolus within 30 min is on time.
    func testTheBolusWindowEdges() {
        let read = interval(0)
        let meal = read.start.addingTimeInterval(.hours(12))
        func share(_ minutes: [Double], meals: [Date]? = nil) -> Double? {
            Engine.lateBolusShare(meals ?? [meal], boluses: minutes.map { meal.addingTimeInterval(.minutes($0)) }, read: read)
        }
        // on time: from 30 min before to 15 min after the start, both ends included
        XCTAssertEqual(share([0]), 0)
        XCTAssertEqual(share([-30]), 0)
        XCTAssertEqual(share([-10]), 0)
        XCTAssertEqual(share([15]), 0)
        // late: more than 15 min after, to the window's end and after it alike
        XCTAssertEqual(share([16]), 1)
        XCTAssertEqual(share([60]), 1)
        XCTAssertEqual(share([61]), 1)
        // none: nothing, or only a bolus more than 30 min before
        XCTAssertEqual(share([]), 1)
        XCTAssertEqual(share([-31]), 1)
        // the first in the window counts
        XCTAssertEqual(share([-31, 5, 40]), 0)
        XCTAssertEqual(share([20, 40]), 1)
        // a share of the meals; no meal: no value
        XCTAssertEqual(share([0], meals: [meal, meal.addingTimeInterval(.hours(3))]), 0.5)
        XCTAssertNil(share([0], meals: []))

        // a meal whose window runs out of the days read counts only with a bolus in time: the one it lacks could be
        // outside them
        let lateMeal = read.end.addingTimeInterval(-.minutes(10))
        XCTAssertNil(Engine.lateBolusShare([lateMeal], boluses: [], read: read))
        XCTAssertEqual(Engine.lateBolusShare([lateMeal], boluses: [lateMeal.addingTimeInterval(.minutes(5))], read: read), 0)
        let earlyMeal = read.start.addingTimeInterval(.minutes(10))
        XCTAssertNil(Engine.lateBolusShare([earlyMeal], boluses: [], read: read))
        XCTAssertEqual(Engine.lateBolusShare([earlyMeal], boluses: [earlyMeal], read: read), 0)
        let inside = read.end.addingTimeInterval(-.minutes(16))
        XCTAssertEqual(Engine.lateBolusShare([inside], boluses: [], read: read), 1)
    }

    /// The meals counted for the bolus: entries within 30 min of a meal's first are one meal, 10 g or more.
    func testTheMealsCountedForTheBolus() {
        let day = interval(0)
        func at(_ hours: Double) -> Date {
            day.start.addingTimeInterval(.hours(hours))
        }
        let entries = [
            MealPoint(id: "a", actualDate: at(8), carbs: 6),
            MealPoint(id: "b", actualDate: at(8.25), carbs: 4),
            MealPoint(id: "c", actualDate: at(12), carbs: 9),
            MealPoint(id: "d", actualDate: at(19), carbs: 10)
        ]
        let facts = Engine.mealFacts(entries, in: day, calendar: calendar)
        XCTAssertEqual(facts?.bolusMealStarts, [at(8), at(19)])
        // a day without a meal of 10 g: no value
        let small = Engine.mealFacts([entries[2]], in: day, calendar: calendar)
        XCTAssertEqual(small?.bolusMealStarts, [])
        XCTAssertNil(Engine.lateBolusShare(small?.bolusMealStarts ?? [], boluses: [], read: day))
    }

    // MARK: - Performance

    /// Reports, never fails on the time: the result for 90 days of 1-minute readings (about 130k) from the day
    /// aggregates the cache holds, as `GlucoseStatistics` would run it. Printed as "Good vs bad days performance: ...";
    /// the test target is usually built unoptimized (Debug), so read the numbers as an upper bound.
    func testPerformanceOver90DaysOfOneMinuteReadings() {
        let intervals = (0 ..< 90).map { interval($0) }
        let first = intervals[0].start.addingTimeInterval(-.days(1))
        let count = Int(intervals[89].end.timeIntervalSince(first) / 60)
        let points = (0 ..< count).map { index -> GlucosePoint in
            let wave: Double = 70 * sin(Double(index) / 180)
            let noise = Double((index * 7919) % 41) - 20
            return GlucosePoint(time: first.addingTimeInterval(Double(index) * 60), mgdl: Int16(150 + wave + noise))
        }
        let w = GlucoseEngine.weigh(GlucoseEngine.clean(points))
        let days = GlucoseEngine.dayAggregates(w, days: intervals)

        let clock = ContinuousClock()
        var best = Double.infinity
        for run in 1 ... 3 {
            var result: GoodBadDaysResult?
            let duration = clock.measure { result = self.result(days, readings: w) }
            let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1E15
            best = Swift.min(best, milliseconds)
            XCTAssertEqual(result?.scored, 90)
            XCTAssertEqual(result?.thirds.reference.days.count, 30)
            print(String(format: "Good vs bad days performance: %d readings, run %d: %.1f ms", w.count, run, milliseconds))
        }
        print(String(format: "Good vs bad days performance: best %.1f ms", best))
    }
}

private extension DayAggregate {
    /// The day with its histogram scaled to the coverage, in percent.
    func withCoverage(_ percent: Double) -> DayAggregate {
        var histogram = GlucoseHistogram()
        let seconds = percent * day.duration / 100
        histogram.add(WeightedPoint(time: day.start, mgdl: 120, span: seconds), seconds: seconds, startsInside: true)
        return DayAggregate(day: day, histogram: histogram)
    }
}
