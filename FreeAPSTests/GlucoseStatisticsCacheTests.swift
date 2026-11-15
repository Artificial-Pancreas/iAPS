import CoreData
@testable import FreeAPS
import XCTest

private typealias Engine = GlucoseStatsEngine

/// The stored readings, with every fetch recorded. A fetch matching a closed gate waits there until it opens; it
/// returns what was stored when it started. A fetch matching a failure throws instead (once).
private actor FakeGlucoseSource: GlucosePointSource {
    struct Failure: Error {}

    private var points: [GlucosePoint] = []
    private(set) var fetches: [DateInterval] = []
    private var gates = TestGates<DateInterval>()
    private var failures: [@Sendable(DateInterval) -> Bool] = []

    func set(_ points: [GlucosePoint]) {
        self.points = points
    }

    func append(_ new: [GlucosePoint]) {
        points += new
    }

    func update(_ transform: @Sendable(GlucosePoint) -> GlucosePoint) {
        points = points.map(transform)
    }

    func clearFetches() {
        fetches = []
    }

    /// Holds the fetches matching the predicate until `open`.
    func gate(_ matches: @escaping @Sendable(DateInterval) -> Bool) -> Int {
        gates.add(matches)
    }

    func open(_ gate: Int) {
        gates.open(gate)
    }

    /// Returns once a fetch is held at the gate (at once when one was).
    func arrival(at gate: Int) async {
        guard let arrival = gates.arrival(at: gate) else { return }
        for await _ in arrival {}
    }

    /// The next fetch matching the predicate throws.
    func failOnce(_ matches: @escaping @Sendable(DateInterval) -> Bool) {
        failures.append(matches)
    }

    func fetchGlucosePoints(from: Date, to: Date) async throws -> [GlucosePoint] {
        let range = DateInterval(start: from, end: to)
        fetches.append(range)
        if let index = failures.firstIndex(where: { $0(range) }) {
            failures.remove(at: index)
            throw Failure()
        }
        let result = points.filter { $0.time >= from && $0.time < to && $0.mgdl > 0 }.sorted { $0.time < $1.time }
        if let held = gates.hold(range) {
            for await _ in held {}
        }
        return result
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var currentNow: Date
    private var currentCalendar: Calendar

    init(now: Date, calendar: Calendar) {
        currentNow = now
        currentCalendar = calendar
    }

    var now: Date {
        get { lock.withLock { currentNow } }
        set { lock.withLock { currentNow = newValue } }
    }

    var calendar: Calendar {
        get { lock.withLock { currentCalendar } }
        set { lock.withLock { currentCalendar = newValue } }
    }
}

final class GlucoseStatisticsCacheTests: XCTestCase {
    // MARK: - fixtures

    private static let berlin = StatsFixtures.berlin

    /// 2026-10-20, today in every test (no DST change in the two weeks before)
    private static let day0 = StatsFixtures.day0

    private let bands = StatsBands(low: 70, high: 145, units: .mgdL)

    /// noon past 12:01 on day0
    private let noonish = GlucoseStatisticsCacheTests.at(0, hours: 12, minutes: 1)

    private struct Fixture {
        let statistics: GlucoseStatistics
        let source: FakeGlucoseSource
        let clock: TestClock
        let coordinator: AppCoordinator
    }

    private func fixture(now: Date, points: [GlucosePoint]) async -> Fixture {
        let clock = TestClock(now: now, calendar: Self.berlin)
        let source = FakeGlucoseSource()
        await source.set(points)
        let coordinator = AppCoordinator()
        let statistics = GlucoseStatistics(
            appCoordinator: coordinator,
            source: source,
            calendar: { clock.calendar },
            now: { clock.now }
        )
        return Fixture(statistics: statistics, source: source, clock: clock, coordinator: coordinator)
    }

    /// The day `offset` days from day0 (Berlin), at the time of day.
    private static func at(_ offset: Int, hours: Double = 0, minutes: Double = 0) -> Date {
        berlin.date(byAdding: .day, value: offset, to: day0)!.addingTimeInterval(TimeInterval.hours(hours) + .minutes(minutes))
    }

    private func day(_ offset: Int) -> Date {
        Self.at(offset)
    }

    /// what every request reads first: today, with the hour before it
    private var tail: DateInterval {
        DateInterval(start: day(0).addingTimeInterval(-TimeInterval.hours(1)), end: day(1))
    }

    /// every 5 minutes, oldest -> newest, values over all the bands
    private func points(
        from start: Date,
        every step: TimeInterval = .minutes(5),
        through end: Date,
        value: (Int) -> Int16 = { Int16(40 + ($0 * 37) % 300) }
    ) -> [GlucosePoint] {
        let count = Int(end.timeIntervalSince(start) / step) + 1
        return (0 ..< count).map { GlucosePoint(time: start.addingTimeInterval(Double($0) * step), mgdl: value($0)) }
    }

    /// two weeks up to 12:00 today
    private func twoWeeks() -> [GlucosePoint] {
        points(from: day(-14), through: Self.at(0, hours: 12))
    }

    private struct Expected {
        let w: [WeightedPoint]
        let window: DateInterval
        let days: [DayAggregate]
        let summary: GlucoseSummary
    }

    /// The whole computation from raw readings, with the engine alone.
    private func expected(
        _ period: StatsPeriod,
        _ points: [GlucosePoint],
        now: Date,
        calendar: Calendar = GlucoseStatisticsCacheTests.berlin,
        bands: StatsBands? = nil
    ) -> Expected {
        let w = Engine.weigh(Engine.clean(points))
        let (end, endRule) = Engine.effectiveEndRule(w, now: now, calendar: calendar)
        let window = Engine.window(for: period, now: now, end: end, calendar: calendar)
        let days = Engine.dayAggregates(w, days: Engine.days(for: period, window: window, calendar: calendar))
        let counts = Engine.dayCounts(period, days: days)
        let summary = Engine.summary(
            Engine.histogram(w, clippedTo: window),
            window: window,
            endRule: endRule,
            calendarDays: counts.calendarDays,
            daysWithData: counts.daysWithData,
            bands: bands ?? self.bands
        )
        return Expected(w: w, window: window, days: days, summary: summary)
    }

    private func assertEqual(
        _ a: GlucoseSummary,
        _ b: GlucoseSummary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        func close(_ x: Double?, _ y: Double?, _ name: String) {
            guard let x, let y else { return XCTAssertTrue(x == nil && y == nil, name, file: file, line: line) }
            XCTAssertEqual(x, y, accuracy: Swift.max(abs(x), abs(y), 1) * 1E-9, name, file: file, line: line)
        }
        XCTAssertEqual(a.window, b.window, "window", file: file, line: line)
        XCTAssertEqual(a.endRule, b.endRule, "endRule", file: file, line: line)
        XCTAssertEqual(a.calendarDays, b.calendarDays, "calendarDays", file: file, line: line)
        XCTAssertEqual(a.daysWithData, b.daysWithData, "daysWithData", file: file, line: line)
        close(a.histogram.totalSeconds, b.histogram.totalSeconds, "seconds")
        close(a.mean, b.mean, "mean")
        close(a.sd, b.sd, "sd")
        close(a.cv, b.cv, "cv")
        close(a.coverage, b.coverage, "coverage")
        close(a.tirFraction, b.tirFraction, "tir")
        close(a.titrFraction, b.titrFraction, "titr")
        for band in GlucoseBand.allCases {
            close(a.fraction(band), b.fraction(band), "\(band)")
        }
        XCTAssertEqual(a.bandShares.percents, b.bandShares.percents, "bandPercents", file: file, line: line)
        XCTAssertEqual(a.coveragePercent, b.coveragePercent, "coveragePercent", file: file, line: line)
        XCTAssertEqual(a.tirPercent, b.tirPercent, "tirPercent", file: file, line: line)
        XCTAssertEqual(a.titrPercent, b.titrPercent, "titrPercent", file: file, line: line)
        XCTAssertEqual(a.histogram.readingCount, b.histogram.readingCount, "readingCount", file: file, line: line)
        XCTAssertEqual(a.minMax, b.minMax, "minMax", file: file, line: line)
        XCTAssertEqual(a.firstReading, b.firstReading, "firstReading", file: file, line: line)
        XCTAssertEqual(a.lastReading, b.lastReading, "lastReading", file: file, line: line)
    }

    private func assertEqual(_ a: [AGPBin?], _ b: [AGPBin?], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (x, y) in zip(a, b) {
            guard let x, let y else {
                XCTAssertTrue(x == nil && y == nil, file: file, line: line)
                continue
            }
            XCTAssertEqual(x.startMinute, y.startMinute, file: file, line: line)
            for (u, v) in [(x.p5, y.p5), (x.p25, y.p25), (x.p50, y.p50), (x.p75, y.p75), (x.p95, y.p95)] {
                XCTAssertEqual(u, v, accuracy: 1E-9, file: file, line: line)
            }
            XCTAssertEqual(x.seconds, y.seconds, accuracy: 1E-6, file: file, line: line)
        }
    }

    private func expectedAGP(_ period: StatsPeriod, _ points: [GlucosePoint], now: Date) -> [AGPBin?] {
        let all = expected(period, points, now: now)
        return Engine.agp(all.w, calendar: Self.berlin, clippedTo: all.window)
    }

    /// The rolling window's summary from raw readings, with the engine alone.
    private func expectedRolling(_ duration: TimeInterval, _ points: [GlucosePoint], now: Date) -> GlucoseSummary {
        let w = Engine.weigh(Engine.clean(points))
        let (end, endRule) = Engine.effectiveEndRule(w, now: now, calendar: Self.berlin)
        let window = DateInterval(start: end.addingTimeInterval(-duration), end: end)
        let days = Engine.dayAggregates(w, days: Engine.days(in: window, calendar: Self.berlin))
        let counts = Engine.dayCounts(nil, days: days)
        return Engine.summary(
            Engine.histogram(w, clippedTo: window),
            window: window,
            endRule: endRule,
            calendarDays: counts.calendarDays,
            daysWithData: counts.daysWithData,
            bands: bands
        )
    }

    /// the 6 days before today, read after the tail
    private var weekRun: DateInterval {
        DateInterval(start: day(-6).addingTimeInterval(-TimeInterval.hours(1)), end: tail.start)
    }

    /// What a 7-day summary reads in New York days: the tail, then the 6 days before it.
    private func newYorkReads(_ newYork: Calendar) -> (tail: DateInterval, run: DateInterval) {
        let today = newYork.startOfDay(for: noonish)
        let tail = DateInterval(
            start: today.addingTimeInterval(-TimeInterval.hours(1)),
            end: newYork.date(byAdding: .day, value: 1, to: today)!
        )
        let run = DateInterval(
            start: newYork.date(byAdding: .day, value: -6, to: today)!.addingTimeInterval(-TimeInterval.hours(1)),
            end: tail.start
        )
        return (tail, run)
    }

    /// thirty days and more, up to 12:00 today
    private func month() -> [GlucosePoint] {
        points(from: day(-31), through: Self.at(0, hours: 12))
    }

    /// what extending the held 7 days to 30 reads
    private var extension30: DateInterval {
        DateInterval(
            start: day(-29).addingTimeInterval(-TimeInterval.hours(1)),
            end: day(-6).addingTimeInterval(-TimeInterval.hours(1))
        )
    }

    /// Waits (at most 10 s) until a fetch is held at the gate.
    private func arrival(
        at gate: Int,
        _ source: FakeGlucoseSource,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let arrived = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await source.arrival(at: gate)
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        XCTAssertTrue(arrived, "no fetch reached the gate", file: file, line: line)
    }

    // MARK: - Cache

    func testTodayIsNeverCached() async {
        let f = await fixture(now: noonish, points: twoWeeks())

        _ = await f.statistics.summary(.days7, bands: bands)
        let first = await f.source.fetches
        // today with its lookback, then the 6 days before it
        XCTAssertEqual(first, [tail, DateInterval(start: day(-6).addingTimeInterval(-TimeInterval.hours(1)), end: tail.start)])

        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        // the complete days come from the cache, today is read again
        let second = await f.source.fetches
        XCTAssertEqual(second, [tail])

        await f.source.clearFetches()
        _ = await f.statistics.summary(.today, bands: bands)
        _ = await f.statistics.summary(.today, bands: bands)
        let today = await f.source.fetches
        XCTAssertEqual(today, [tail, tail])
    }

    func testReadingComingInDropsOnlyToday() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        _ = await f.statistics.summary(.days7, bands: bands)

        let t = Self.at(0, hours: 12, minutes: 5)
        f.clock.now = t.addingTimeInterval(30)
        await f.source.append([GlucosePoint(time: t, mgdl: 120)])
        await f.source.clearFetches()
        await f.statistics.readingsChanged(ReadingsChange.readings(at: [t], newest: true)!)

        XCTAssertEqual(
            f.coordinator.glucoseStatsChanged.value,
            StatsChange(seq: 1, interval: DateInterval(start: t.addingTimeInterval(-TimeInterval.minutes(10)), end: t))
        )

        let summary = await f.statistics.summary(.days7, bands: bands)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail])
        XCTAssertEqual(summary.lastReading, t)
    }

    func testReadingJustAfterMidnightAlsoDropsYesterday() async {
        // the last reading at 00:02, current at 00:03: yesterday is complete (E = 00:07)
        let data = points(from: day(-14).addingTimeInterval(.minutes(2)), through: Self.at(0, minutes: 2))
        XCTAssertEqual(data.last?.time, Self.at(0, minutes: 2))
        let f = await fixture(now: Self.at(0, minutes: 3), points: data)
        _ = await f.statistics.summary(.days7, bands: bands)

        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        let cached = await f.source.fetches
        XCTAssertEqual(cached, [tail])

        // 00:07: the 23:57 reading before midnight is within 10 minutes of it
        let t = Self.at(0, minutes: 7)
        f.clock.now = Self.at(0, minutes: 8)
        await f.source.append([GlucosePoint(time: t, mgdl: 120)])
        await f.statistics.readingsChanged(ReadingsChange.readings(at: [t], newest: true)!)

        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, DateInterval(start: day(-1).addingTimeInterval(-TimeInterval.hours(1)), end: tail.start)])
    }

    func testBackfillDropsTheDaysAroundIt() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        _ = await f.statistics.summary(.days7, bands: bands)

        // 10:00-11:00 three days ago: the days touching 09:00-12:00
        let backfill = DateInterval(start: Self.at(-3, hours: 10), end: Self.at(-3, hours: 11))
        await f.statistics.readingsChanged(.interval(backfill, newest: false))
        XCTAssertEqual(
            f.coordinator.glucoseStatsChanged.value.interval,
            DateInterval(start: Self.at(-3, hours: 9), end: Self.at(-3, hours: 12))
        )

        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [
            tail,
            DateInterval(start: day(-3).addingTimeInterval(-TimeInterval.hours(1)), end: day(-2).addingTimeInterval(.minutes(10)))
        ])

        // a reading deleted at 23:30: the hour after it is the next day
        let delete = Self.at(-5, hours: 23, minutes: 30)
        await f.statistics.readingsChanged(ReadingsChange.readings(at: [delete], newest: false)!)

        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [
            tail,
            DateInterval(start: day(-5).addingTimeInterval(-TimeInterval.hours(1)), end: day(-3).addingTimeInterval(.minutes(10)))
        ])
    }

    func testDayInvalidatedDuringItsComputationIsReturnedButNotStored() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        _ = await f.statistics.days(.days7)

        // a backfill three days ago: the next request recomputes that day
        let noon = Self.at(-3, hours: 12)
        await f.statistics.readingsChanged(.interval(DateInterval(start: noon, duration: 0), newest: false))

        let gate = await f.source.gate { $0.contains(noon) }
        let statistics = f.statistics
        let computing = Task { await statistics.days(.days7) }
        await arrival(at: gate, f.source)

        // the day changes again while it is being computed
        let changed = DateInterval(
            start: noon.addingTimeInterval(-TimeInterval.minutes(30)),
            end: noon.addingTimeInterval(.minutes(30))
        )
        let raise: @Sendable(GlucosePoint) -> GlucosePoint = { point in
            changed.contains(point.time) ? GlucosePoint(time: point.time, mgdl: 300) : point
        }
        await f.source.update(raise)
        await f.statistics.readingsChanged(.interval(changed, newest: false))
        await f.source.open(gate)

        // returned, computed from what was read
        let raced = await computing.value
        let before = expected(.days7, data, now: noonish).days
        XCTAssertEqual(raced.count, 7)
        XCTAssertEqual(raced[3].day, DateInterval(start: day(-3), end: day(-2)))
        XCTAssertEqual(raced[3].histogram.mean ?? 0, before[3].histogram.mean ?? -1, accuracy: 1E-9)

        // not stored: read again, now with the change
        await f.source.clearFetches()
        let after = await f.statistics.days(.days7)
        let fetches = await f.source.fetches
        XCTAssertTrue(fetches.contains { $0.contains(noon) })
        let now = expected(.days7, data.map(raise), now: noonish).days
        XCTAssertEqual(after[3].histogram.mean ?? 0, now[3].histogram.mean ?? -1, accuracy: 1E-9)
        XCTAssertNotEqual(after[3].histogram.mean ?? 0, before[3].histogram.mean ?? 0, accuracy: 1)

        // and stored this time
        await f.source.clearFetches()
        _ = await f.statistics.days(.days7)
        let cached = await f.source.fetches
        XCTAssertEqual(cached, [tail])
    }

    func testTimeZoneChangeDropsTheCache() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        _ = await f.statistics.summary(.days7, bands: bands)
        XCTAssertEqual(f.coordinator.glucoseStatsChanged.value.seq, 0)

        let newYork = StatsFixtures.calendar("America/New_York")
        f.clock.calendar = newYork
        await f.source.clearFetches()
        let summary = await f.statistics.summary(.days7, bands: bands)

        XCTAssertEqual(f.coordinator.glucoseStatsChanged.value, StatsChange(seq: 1, interval: nil))
        // every day read again, in New York days
        let today = newYork.startOfDay(for: noonish)
        let newYorkTail = DateInterval(
            start: today.addingTimeInterval(-TimeInterval.hours(1)),
            end: newYork.date(byAdding: .day, value: 1, to: today)!
        )
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [
            newYorkTail,
            DateInterval(
                start: newYork.date(byAdding: .day, value: -6, to: today)!.addingTimeInterval(-TimeInterval.hours(1)),
                end: newYorkTail.start
            )
        ])
        assertEqual(summary, expected(.days7, data, now: noonish, calendar: newYork).summary)

        // and cached again
        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        let cached = await f.source.fetches
        XCTAssertEqual(cached, [newYorkTail])
    }

    func testBandsChangeNeedsNoRefetch() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        let primed = await f.statistics.summary(.days7, bands: bands)

        await f.source.clearFetches()
        let other = StatsBands(low: 80, high: 180, units: .mgdL)
        let summary = await f.statistics.summary(.days7, bands: other)

        // the same reads as with unchanged bands: today only
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail])
        assertEqual(summary, expected(.days7, data, now: noonish, bands: other).summary)
        XCTAssertNotEqual(summary.bandShares.percents, primed.bandShares.percents)
    }

    func testWipeDropsEverything() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        _ = await f.statistics.summary(.days7, bands: bands)

        await f.source.set([])
        await f.statistics.readingsChanged(.all)
        XCTAssertEqual(f.coordinator.glucoseStatsChanged.value, StatsChange(seq: 1, interval: nil))

        let summary = await f.statistics.summary(.days7, bands: bands)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.daysWithData, 0)
    }

    func testOneMinuteReadings() async {
        let data = points(from: day(-8), every: .minutes(1), through: Self.at(0, hours: 12))
        let f = await fixture(now: noonish, points: data)
        let all = expected(.days7, data, now: noonish)
        XCTAssertTrue(all.w.allSatisfy { $0.span == .minutes(1) })

        let fromRaw = await f.statistics.summary(.days7, bands: bands)
        let fromCache = await f.statistics.summary(.days7, bands: bands)
        XCTAssertEqual(fromCache, fromRaw)
        assertEqual(fromCache, all.summary)
        XCTAssertEqual(fromCache.window.end, Self.at(0, hours: 12, minutes: 1))
        XCTAssertEqual(fromCache.coveragePercent, 100)

        await f.statistics.beginSession()
        let agp = await f.statistics.agp(.days7)
        assertEqual(agp, Engine.agp(all.w, calendar: Self.berlin, clippedTo: all.window))
        let trace = await f.statistics.trace(.day(day(0)), bands: bands)
        XCTAssertEqual(trace.points.count, 12 * 60 + 1)
    }

    func testDSTDayFromTheCacheAndFromTheReadings() async {
        // 2026-10-25 (day 5) has 25 hours; now is the 27th, 20:01 CET
        let now = Self.at(7, hours: 20, minutes: 1)
        let data = points(from: day(-8).addingTimeInterval(-TimeInterval.minutes(3)), through: Self.at(7, hours: 20))
        let f = await fixture(now: now, points: data)

        let fromRaw = await f.statistics.days(.days14)
        XCTAssertEqual(fromRaw.first { $0.day.start == day(5) }?.day.duration, .hours(25))

        // the complete days (the 25-hour one among them) from the cache
        await f.source.clearFetches()
        let summary = await f.statistics.summary(.days14, bands: bands)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [DateInterval(start: day(7).addingTimeInterval(-TimeInterval.hours(1)), end: day(8))])
        assertEqual(summary, expected(.days14, data, now: now).summary)

        // rolling 7 x 24 h across the change: a partial first day, the 25-hour day from the cache
        let rolling = await f.statistics.summary(rolling: .days(7), bands: bands)
        assertEqual(rolling, expectedRolling(.days(7), data, now: now))
    }

    func testWipeDuringAReadIsNotStored() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        let run = weekRun
        let gate = await f.source.gate { $0 == run }
        let statistics = f.statistics
        let computing = Task { await statistics.days(.days7) }
        await arrival(at: gate, f.source)

        // wiped, and other readings stored, while the days are read
        await f.source.set(points(from: day(-14), through: Self.at(0, hours: 12)) { _ in 200 })
        await f.statistics.readingsChanged(.all)
        await f.source.open(gate)
        _ = await computing.value

        // not stored: read again, the new readings
        await f.source.clearFetches()
        let days = await f.statistics.days(.days7)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run])
        XCTAssertEqual(days[0].histogram.mean ?? 0, 200, accuracy: 1E-9)
    }

    func testTimeZoneChangeDuringAReadIsNotStored() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        let run = weekRun
        let gate = await f.source.gate { $0 == run }
        let statistics = f.statistics
        let computing = Task { await statistics.days(.days7) }
        await arrival(at: gate, f.source)

        // New York, noticed by another request while the Berlin days are read
        let newYork = StatsFixtures.calendar("America/New_York")
        f.clock.calendar = newYork
        _ = await f.statistics.summary(.today, bands: bands)
        await f.source.open(gate)
        _ = await computing.value

        // the Berlin days weren't stored as dates of New York: all read again
        await f.source.clearFetches()
        let summary = await f.statistics.summary(.days7, bands: bands)
        let fetches = await f.source.fetches
        let reads = newYorkReads(newYork)
        XCTAssertEqual(fetches, [reads.tail, reads.run])
        assertEqual(summary, expected(.days7, data, now: noonish, calendar: newYork).summary)
    }

    func testCalendarChangeDropsTheCache() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        _ = await f.statistics.summary(.days7, bands: bands)

        // the same time zone, another calendar
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = Self.berlin.timeZone
        f.clock.calendar = iso
        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)

        XCTAssertEqual(f.coordinator.glucoseStatsChanged.value, StatsChange(seq: 1, interval: nil))
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, weekRun])
    }

    func testCacheKeepsTheNewestDays() async {
        XCTAssertEqual(GlucoseStatistics.Config.maxCachedDays, 100)
        let data = points(from: day(-122), through: Self.at(0, hours: 12))
        let f = await fixture(now: noonish, points: data)

        // 119 complete days: the oldest 19 are evicted
        _ = await f.statistics.summary(rolling: .days(120), bands: bands)

        // the 89 days before today are among the newest 100
        await f.source.clearFetches()
        _ = await f.statistics.summary(.days90, bands: bands)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail])

        // the evicted ones are read again, with the partial first day before them
        await f.source.clearFetches()
        _ = await f.statistics.summary(rolling: .days(120), bands: bands)
        fetches = await f.source.fetches
        let start = Self.at(0, hours: 12, minutes: 5).addingTimeInterval(-TimeInterval.days(120))
        XCTAssertEqual(fetches, [
            tail,
            DateInterval(start: start.addingTimeInterval(-TimeInterval.hours(1)), end: day(-100).addingTimeInterval(.minutes(10)))
        ])
    }

    // MARK: - Failed reads

    func testFailedReadIsNeitherCachedNorHeld() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        let run = weekRun
        await f.source.failOnce { $0 == run }

        // returned, without what couldn't be read
        let failed = await f.statistics.days(.days7)
        XCTAssertEqual(failed.count, 7)
        XCTAssertTrue(failed[0].histogram.isEmpty)

        // not cached: read again, with the readings
        await f.source.clearFetches()
        let days = await f.statistics.days(.days7)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run])
        let all = expected(.days7, data, now: noonish).days
        XCTAssertEqual(days.count, all.count)
        for (a, b) in zip(days, all) {
            XCTAssertEqual(a.day, b.day)
            XCTAssertEqual(a.histogram.totalSeconds, b.histogram.totalSeconds, accuracy: 1E-6)
            XCTAssertEqual(a.histogram.readingCount, b.histogram.readingCount)
        }

        // and cached now
        await f.source.clearFetches()
        _ = await f.statistics.days(.days7)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail])

        // nor held
        await f.statistics.beginSession()
        await f.source.failOnce { $0 == run }
        _ = await f.statistics.agp(.days7)
        await f.source.clearFetches()
        let agp = await f.statistics.agp(.days7)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run])
        assertEqual(agp, expectedAGP(.days7, data, now: noonish))
    }

    func testFailedSpliceDropsTheHeldReadings() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        await f.statistics.beginSession()
        _ = await f.statistics.agp(.days7)

        let t = Self.at(0, hours: 12, minutes: 5)
        f.clock.now = t.addingTimeInterval(30)
        await f.source.append([GlucosePoint(time: t, mgdl: 250)])
        let spliceRange = DateInterval(start: t.addingTimeInterval(-TimeInterval.hours(1)), end: t.addingTimeInterval(.hours(1)))
        await f.source.failOnce { $0 == spliceRange }
        await f.statistics.readingsChanged(ReadingsChange.readings(at: [t], newest: true)!)
        XCTAssertEqual(f.coordinator.glucoseStatsChanged.value.seq, 1)

        // they'd miss the reading: read again (the tail has the day with its lookback hour)
        await f.source.clearFetches()
        let trace = await f.statistics.trace(.day(day(0)), bands: bands)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail])
        XCTAssertEqual(trace.points.last?.time, t)
    }

    // MARK: - Good & bad days

    /// The 14 complete days to yesterday, scored from the day cache and profiled from the readings, held from the day
    /// before them (one read, the tail apart): the days the cache misses come from the held readings. Again, nothing is
    /// read: the tail and the days are held or cached.
    func testGoodBadDaysReadsOnlyTheMissingDaysAndReusesTheHeldReadings() async {
        let data = points(from: day(-16), through: Self.at(0, hours: 12))
        let f = await fixture(now: noonish, points: data)
        await f.statistics.beginSession()
        let glucose = await f.statistics.goodBadDays(count: 14, bands: bands)
        let result = glucose.result
        let head = DateInterval(start: day(-15).addingTimeInterval(-TimeInterval.hours(1)), end: tail.start)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, head])

        // the engine's, of the readings read: from the day before's lookback hour to its lookahead after yesterday
        let readEnd = day(0).addingTimeInterval(GlucoseStatistics.Config.lookahead)
        let w = Engine.weigh(Engine.clean(data.filter { $0.time >= head.start && $0.time < readEnd }))
        let days = Engine.completeDays(count: 14, today: noonish, calendar: Self.berlin)
        XCTAssertEqual(days.first?.start, day(-14))
        XCTAssertEqual(days.last?.end, day(0))
        let expected = GoodBadDaysEngine.result(
            period: .days14,
            days: Engine.dayAggregates(w, days: days),
            readings: w,
            bands: bands,
            calendar: Self.berlin
        )
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.scored, 14)
        // the GRI of the day before too, for the first day's previous day
        let before = Engine.dayAggregates(w, days: [DateInterval(start: day(-15), end: day(-14))])[0]
        XCTAssertEqual(glucose.gri.count, 15)
        XCTAssertEqual(
            glucose.gri[StatsDayKey(day(-15), Self.berlin)],
            GoodBadDaysEngine.score(before, nightTIR: nil, bands: bands, calendar: Self.berlin)?.gri.value
        )

        await f.source.clearFetches()
        let again = await f.statistics.goodBadDays(count: 14, bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [])
        XCTAssertEqual(again, glucose)
    }

    // MARK: - Session

    func testLiveUpdateIsSplicedIntoTheHeldReadings() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        await f.statistics.beginSession()
        _ = await f.statistics.agp(.days7)
        let first = await f.source.fetches
        XCTAssertEqual(first, [tail, DateInterval(start: day(-6).addingTimeInterval(-TimeInterval.hours(1)), end: tail.start)])

        // a reading comes in: only the hours around it are read again
        let t = Self.at(0, hours: 12, minutes: 5)
        f.clock.now = t.addingTimeInterval(30)
        let reading = GlucosePoint(time: t, mgdl: 250)
        await f.source.append([reading])
        await f.source.clearFetches()
        await f.statistics.readingsChanged(ReadingsChange.readings(at: [t], newest: true)!)
        let splice = await f.source.fetches
        XCTAssertEqual(
            splice,
            [DateInterval(start: t.addingTimeInterval(-TimeInterval.hours(1)), end: t.addingTimeInterval(.hours(1)))]
        )

        // everything else comes from the held readings
        await f.source.clearFetches()
        let agp = await f.statistics.agp(.days7)
        let hours = await f.statistics.hourOfDay(.days7)
        let summary = await f.statistics.summary(.days7, bands: bands)
        let trace = await f.statistics.trace(.day(day(0)), bands: bands)
        let none = await f.source.fetches
        XCTAssertEqual(none, [])

        let all = expected(.days7, data + [reading], now: f.clock.now)
        assertEqual(agp, Engine.agp(all.w, calendar: Self.berlin, clippedTo: all.window))
        let expectedHours = Engine.hourOfDay(all.w, calendar: Self.berlin, clippedTo: all.window)
        XCTAssertEqual(hours.count, expectedHours.count)
        for (a, b) in zip(hours, expectedHours) {
            XCTAssertEqual(a.histogram.totalSeconds, b.histogram.totalSeconds, accuracy: 1E-6)
        }
        assertEqual(summary, all.summary)
        XCTAssertEqual(summary.lastReading, t)
        XCTAssertEqual(trace.window, DateInterval(start: day(0), end: t.addingTimeInterval(.minutes(5))))
        XCTAssertEqual(trace.points.last, WeightedPoint(time: t, mgdl: 250, span: .minutes(5)))
        XCTAssertEqual(trace.summary.histogram.readingCount, all.days[6].histogram.readingCount)

        // closing Statistics drops them
        await f.statistics.endSession()
        await f.source.clearFetches()
        _ = await f.statistics.agp(.days7)
        let after = await f.source.fetches
        XCTAssertEqual(after.count, 2)
    }

    func testSpliceLandingDuringAnExtensionIsNotOverwritten() async {
        let data = month()
        let f = await fixture(now: noonish, points: data)
        await f.statistics.beginSession()
        _ = await f.statistics.agp(.days7)

        // a reading comes in; its splice waits in its read
        let t = Self.at(0, hours: 12, minutes: 5)
        f.clock.now = t.addingTimeInterval(30)
        let reading = GlucosePoint(time: t, mgdl: 250)
        await f.source.append([reading])
        let spliceRange = DateInterval(start: t.addingTimeInterval(-TimeInterval.hours(1)), end: t.addingTimeInterval(.hours(1)))
        let spliceGate = await f.source.gate { $0 == spliceRange }
        let statistics = f.statistics
        let change = Task { await statistics.readingsChanged(ReadingsChange.readings(at: [t], newest: true)!) }
        await arrival(at: spliceGate, f.source)

        // meanwhile 30 days extend the held readings from before the splice
        let extension30 = self.extension30
        let extensionGate = await f.source.gate { $0 == extension30 }
        let extending = Task { await statistics.agp(.days30) }
        await arrival(at: extensionGate, f.source)

        // the splice lands first, then the extension
        await f.source.open(spliceGate)
        await change.value
        await f.source.open(extensionGate)
        let raced = await extending.value
        // computed from what it read: the readings from before the reading
        assertEqual(raced, expectedAGP(.days30, data, now: f.clock.now))

        // the splice is still held: the day needs no read, and has the reading
        await f.source.clearFetches()
        let trace = await f.statistics.trace(.day(day(0)), bands: bands)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [])
        XCTAssertEqual(trace.points.last, WeightedPoint(time: t, mgdl: 250, span: .minutes(5)))

        // the extension wasn't kept: read again, and kept this time
        let agp = await f.statistics.agp(.days30)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [extension30])
        assertEqual(agp, expectedAGP(.days30, data + [reading], now: f.clock.now))

        await f.source.clearFetches()
        _ = await f.statistics.agp(.days30)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [])
    }

    func testExtensionReadDuringAChangeIsUsedButNotKept() async {
        let data = month()
        let f = await fixture(now: noonish, points: data)
        await f.statistics.beginSession()
        _ = await f.statistics.agp(.days7)

        let extension30 = self.extension30
        let gate = await f.source.gate { $0 == extension30 }
        let statistics = f.statistics
        let extending = Task { await statistics.agp(.days30) }
        await arrival(at: gate, f.source)

        // a reading comes in (and is spliced in) while the extension is read
        let t = Self.at(0, hours: 12, minutes: 5)
        f.clock.now = t.addingTimeInterval(30)
        let reading = GlucosePoint(time: t, mgdl: 250)
        await f.source.append([reading])
        await f.statistics.readingsChanged(ReadingsChange.readings(at: [t], newest: true)!)
        await f.source.open(gate)

        // this request gets the 30 days, as they were when it started
        let raced = await extending.value
        assertEqual(raced, expectedAGP(.days30, data, now: noonish))

        // not kept: the next one reads the extension again, now with the reading
        await f.source.clearFetches()
        let agp = await f.statistics.agp(.days30)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [extension30])
        assertEqual(agp, expectedAGP(.days30, data + [reading], now: f.clock.now))

        await f.source.clearFetches()
        _ = await f.statistics.agp(.days30)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [])
    }

    func testExtensionInFlightWhenStatisticsClosesIsNotKept() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        await f.statistics.beginSession()
        let head = weekRun
        let gate = await f.source.gate { $0 == head }
        let statistics = f.statistics
        let holding = Task { await statistics.agp(.days7) }
        await arrival(at: gate, f.source)

        // closed, and opened again, while it reads
        await f.statistics.endSession()
        await f.statistics.beginSession()
        await f.source.open(gate)
        _ = await holding.value

        // nothing held: read again
        await f.source.clearFetches()
        _ = await f.statistics.agp(.days7)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, head])
    }

    func testExtensionOnBothSidesAfterMidnight() async {
        // the held 7 days end at midnight; after it, 14 days need the days before them and the new today
        let data = points(from: day(-14), through: Self.at(0, hours: 23, minutes: 45))
        let f = await fixture(now: Self.at(0, hours: 23, minutes: 50), points: data)
        await f.statistics.beginSession()
        _ = await f.statistics.agp(.days7)

        // readings on to 00:15, spliced in up to midnight
        let new = points(from: Self.at(0, hours: 23, minutes: 50), through: Self.at(1, minutes: 15))
        await f.source.append(new)
        f.clock.now = Self.at(1, minutes: 16)
        await f.statistics.readingsChanged(ReadingsChange.readings(at: new.map(\.time), newest: true)!)

        // the new tail (not held yet), and the days before the held ones; the new today comes from the tail
        await f.source.clearFetches()
        let agp = await f.statistics.agp(.days14)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [
            DateInterval(start: day(1).addingTimeInterval(-TimeInterval.hours(1)), end: day(2)),
            DateInterval(
                start: day(-12).addingTimeInterval(-TimeInterval.hours(1)),
                end: day(-6).addingTimeInterval(-TimeInterval.hours(1))
            )
        ])
        let all = data + new
        assertEqual(agp, expectedAGP(.days14, all, now: f.clock.now))

        // held on both sides now
        await f.source.clearFetches()
        let summary = await f.statistics.summary(.days14, bands: bands)
        let trace = await f.statistics.trace(.day(day(1)), bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [])
        assertEqual(summary, expected(.days14, all, now: f.clock.now).summary)
        XCTAssertEqual(trace.points.map(\.time), new.filter { $0.time >= day(1) }.map(\.time))
    }

    func testTimeZoneChangeKeepsTheHeldReadingsCurrent() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        await f.statistics.beginSession()
        _ = await f.statistics.agp(.days7)

        // the complete New York days come from the held readings (they end at the Berlin end of today)
        let newYork = StatsFixtures.calendar("America/New_York")
        f.clock.calendar = newYork
        let reads = newYorkReads(newYork)
        await f.source.clearFetches()
        let summary = await f.statistics.summary(.days7, bands: bands)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [reads.tail])
        assertEqual(summary, expected(.days7, data, now: noonish, calendar: newYork).summary)

        // and were stored: closing Statistics doesn't lose them
        await f.statistics.endSession()
        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [reads.tail])
    }

    // MARK: - Windows

    func testJustAfterMidnightSevenDaysHaveAnEmptyToday() async {
        // every 5 minutes, the last at 23:54:30, still current at 00:01: E = 23:59:30, before the start of today
        let data = points(from: day(-7).addingTimeInterval(270), through: day(0).addingTimeInterval(-330))
        XCTAssertEqual(data.last?.time, day(0).addingTimeInterval(-330))
        let now = day(0).addingTimeInterval(60)
        let end = day(0).addingTimeInterval(-30)
        let f = await fixture(now: now, points: data)

        let days = await f.statistics.days(.days7)
        XCTAssertEqual(days.map(\.day.start), (-6 ... 0).map { day($0) })
        XCTAssertEqual(days[5].day, DateInterval(start: day(-1), end: end))
        XCTAssertEqual(days[6].day, DateInterval(start: day(0), duration: 0))
        XCTAssertTrue(days[6].histogram.isEmpty)

        let summary = await f.statistics.summary(.days7, bands: bands)
        XCTAssertEqual(summary.calendarDays, 7)
        XCTAssertEqual(summary.daysWithData, 6)
        assertEqual(summary, expected(.days7, data, now: now).summary)

        // yesterday ends at E, so it isn't complete: it is read again, the days before it are cached
        await f.source.clearFetches()
        _ = await f.statistics.summary(.days7, bands: bands)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, DateInterval(start: day(-1).addingTimeInterval(-TimeInterval.hours(1)), end: tail.start)])
    }

    func testCachedAndPartialDaysAddUpToTheRawSummary() async {
        // 14 days and more, readings at hh:m2 / hh:m7 (spans cross midnight), with a gap
        let now = Self.at(0, hours: 20, minutes: 1)
        let data = points(from: day(-15).addingTimeInterval(-TimeInterval.minutes(3)), through: Self.at(0, hours: 20))
            .enumerated()
            .filter { !(1000 ..< 1030).contains($0.offset) }
            .map(\.element)
        let f = await fixture(now: now, points: data)

        let fromRaw = await f.statistics.summary(.days14, bands: bands)
        let fromCache = await f.statistics.summary(.days14, bands: bands)
        XCTAssertEqual(fromCache, fromRaw)
        assertEqual(fromCache, expected(.days14, data, now: now).summary)

        // rolling 7 x 24 h: a partial first day from the readings, the complete days from the cache
        let rolling = await f.statistics.summary(rolling: .days(7), bands: bands)
        let w = Engine.weigh(Engine.clean(data))
        let (end, endRule) = Engine.effectiveEndRule(w, now: now, calendar: Self.berlin)
        let window = DateInterval(start: end.addingTimeInterval(-TimeInterval.days(7)), end: end)
        let days = Engine.dayAggregates(w, days: Engine.days(in: window, calendar: Self.berlin))
        XCTAssertEqual(days.count, 8)
        let counts = Engine.dayCounts(nil, days: days)
        assertEqual(
            rolling,
            Engine.summary(
                Engine.histogram(w, clippedTo: window),
                window: window,
                endRule: endRule,
                calendarDays: counts.calendarDays,
                daysWithData: counts.daysWithData,
                bands: bands
            )
        )
    }

    // MARK: - Core Data

    func testFetchGlucosePointsReadsOnlyTheCGMReadings() async throws {
        let container = StatsFixtures.inMemoryContainer()

        // 10 days: two chunks, the second from `boundary`
        let from = day(-10)
        let to = day(0)
        let boundary = from.addingTimeInterval(.days(7))
        struct Row: Sendable {
            let date: Date
            let glucose: Int16
            let type: String?
        }
        let rows = [
            Row(date: from.addingTimeInterval(-1), glucose: 99, type: "sgv"),
            Row(date: from, glucose: 100, type: "sgv"),
            Row(date: from.addingTimeInterval(.hours(1)), glucose: 101, type: nil),
            Row(date: from.addingTimeInterval(.hours(2)), glucose: 102, type: "Manual"),
            Row(date: from.addingTimeInterval(.hours(3)), glucose: 103, type: "mbg"),
            Row(date: from.addingTimeInterval(.hours(4)), glucose: 0, type: "sgv"),
            Row(date: from.addingTimeInterval(.hours(5)), glucose: 0, type: nil),
            Row(date: boundary.addingTimeInterval(-60), glucose: 104, type: "sgv"),
            Row(date: boundary, glucose: 105, type: nil),
            Row(date: boundary.addingTimeInterval(60), glucose: 106, type: "sgv"),
            Row(date: boundary.addingTimeInterval(120), glucose: 107, type: "Manual"),
            Row(date: to.addingTimeInterval(-60), glucose: 108, type: "sgv"),
            Row(date: to, glucose: 109, type: "sgv")
        ]
        // stored newest first, so the order comes from the fetch
        try await container.performBackgroundTask { context in
            for row in rows.reversed() {
                let reading = NSEntityDescription.insertNewObject(forEntityName: "Readings", into: context)
                reading.setValue(row.date, forKey: "date")
                reading.setValue(row.glucose, forKey: "glucose")
                reading.setValue(row.type, forKey: "type")
            }
            try context.save()
        }

        let points = try await CoreDataStorage(container: container).fetchGlucosePoints(from: from, to: to)
        XCTAssertEqual(points, [
            GlucosePoint(time: from, mgdl: 100),
            GlucosePoint(time: from.addingTimeInterval(.hours(1)), mgdl: 101),
            GlucosePoint(time: boundary.addingTimeInterval(-60), mgdl: 104),
            GlucosePoint(time: boundary, mgdl: 105),
            GlucosePoint(time: boundary.addingTimeInterval(60), mgdl: 106),
            GlucosePoint(time: to.addingTimeInterval(-60), mgdl: 108)
        ])
    }

    // MARK: - Backfill duplicates

    private typealias Row = (date: Date, type: String?)

    /// The duplicate check `CoreDataManager.storeGlucose` had before `nonDuplicates`: the reference.
    private static func referenceNonDuplicates(_ readings: [Row], existing: [Row]) -> [Int] {
        func isCGM(_ type: String?) -> Bool {
            type == nil || type == GlucoseType.sgv.rawValue
        }
        var existingRows = existing
        var result: [Int] = []
        for (index, bg) in readings.enumerated() {
            let cgm = isCGM(bg.type)
            guard !existingRows.contains(where: {
                (cgm ? isCGM($0.type) : $0.type == bg.type) && abs($0.date.timeIntervalSince(bg.date)) <= 45
            })
            else {
                continue
            }
            existingRows.append((date: bg.date, type: bg.type))
            result.append(index)
        }
        return result
    }

    /// SplitMix64, so the random cases are the same on every run.
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

    func testNonDuplicatesKeepTheFirstOfNewReadingsWithin45s() {
        let t = Self.day0
        // the second is within 45 s of the first; the third only of the second, which is not kept
        XCTAssertEqual(
            CoreDataManager.nonDuplicates(
                [(t, "sgv"), (t.addingTimeInterval(30), "sgv"), (t.addingTimeInterval(60), "sgv")],
                existing: []
            ),
            [0, 2]
        )
        // in input order, not in time order
        XCTAssertEqual(
            CoreDataManager.nonDuplicates(
                [(t.addingTimeInterval(30), "sgv"), (t, "sgv"), (t.addingTimeInterval(60), "sgv")],
                existing: []
            ),
            [0]
        )
        // 45 s is a duplicate, just over it is not
        XCTAssertEqual(
            CoreDataManager.nonDuplicates(
                [(t.addingTimeInterval(45), "sgv"), (t.addingTimeInterval(-45.001), "sgv")],
                existing: [(t, "sgv")]
            ),
            [1]
        )
    }

    func testNonDuplicatesCompareOnlyTheSameClass() {
        let t = Self.day0
        let readings: [Row] = [
            (t, nil), // a CGM reading: duplicate of the stored sgv
            (t, "Manual"), // kept next to the CGM reading
            (t.addingTimeInterval(10), "Manual"), // duplicate of the manual one just kept
            (t.addingTimeInterval(10), "mbg"), // another type, 50 s from the stored mbg: kept
            (t.addingTimeInterval(20), "mbg"), // duplicate of the mbg just kept (and of the stored one)
            (t.addingTimeInterval(100), nil), // kept
            (t.addingTimeInterval(110), "sgv") // duplicate of the nil-type one just kept
        ]
        let existing: [Row] = [(t.addingTimeInterval(5), "sgv"), (t.addingTimeInterval(60), "mbg")]
        XCTAssertEqual(CoreDataManager.nonDuplicates(readings, existing: existing), [1, 3, 5])
        XCTAssertEqual(Self.referenceNonDuplicates(readings, existing: existing), [1, 3, 5])
    }

    func testNonDuplicatesMatchTheReferenceOnRandomReadings() {
        var generator = SeededGenerator(seed: 42)
        let types: [String?] = [nil, "sgv", "Manual", "mbg", "cal"]
        let odd: [Date] = [
            .distantPast,
            .distantFuture,
            Date(timeIntervalSinceReferenceDate: 1E20),
            Date(timeIntervalSinceReferenceDate: -1E20),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: .nan)
        ]
        for round in 0 ..< 2000 {
            // a grid of 15 s steps (so equal dates and exactly 45 s apart are common), sometimes off the grid
            let slots = Int.random(in: 1 ... 400, using: &generator)
            func row() -> Row {
                var date = Self.day0.addingTimeInterval(Double(Int.random(in: 0 ..< slots, using: &generator)) * 15)
                if Int.random(in: 0 ..< 4, using: &generator) == 0 {
                    date = date.addingTimeInterval(Double.random(in: -20 ... 20, using: &generator))
                }
                if Int.random(in: 0 ..< 200, using: &generator) == 0 {
                    date = odd.randomElement(using: &generator)!
                }
                return (date: date, type: types.randomElement(using: &generator)!)
            }
            let readings = (0 ..< Int.random(in: 0 ... 80, using: &generator)).map { _ in row() }
            let existing = (0 ..< Int.random(in: 0 ... 40, using: &generator)).map { _ in row() }
            XCTAssertEqual(
                CoreDataManager.nonDuplicates(readings, existing: existing),
                Self.referenceNonDuplicates(readings, existing: existing),
                "round \(round)"
            )
        }
    }

    func testNonDuplicatesOf100kReadings() {
        // as Nightscout returns them, newest first: 60 days of 1-minute readings, then 30 days of 5-minute ones,
        // and a manual BG every 26 minutes
        let now = Self.day0
        let oneMinute = (0 ..< 86400).map { (date: now.addingTimeInterval(-Double($0) * 60), type: "sgv" as String?) }
        let fiveMinutes = (1 ... 8640).map {
            (date: now.addingTimeInterval(-TimeInterval.days(60) - Double($0) * 300), type: "sgv" as String?)
        }
        let manual = (0 ..< 4960).map {
            (date: now.addingTimeInterval(-13 - Double($0) * 1560), type: "Manual" as String?)
        }
        let readings: [Row] = oneMinute + fiveMinutes + manual
        XCTAssertEqual(readings.count, 100_000)
        // the last 7 days already stored, 5-minute, 10 s after a 1-minute reading: each a duplicate of that one
        let existing: [Row] = (0 ..< 2016).map { (date: now.addingTimeInterval(10 - Double($0) * 300), type: nil) }

        let start = Date()
        let kept = CoreDataManager.nonDuplicates(readings, existing: existing)
        print("nonDuplicates of \(readings.count) readings (\(existing.count) stored): \(Date().timeIntervalSince(start)) s")

        XCTAssertEqual(kept.count, 100_000 - 2016)
        XCTAssertEqual(kept, kept.sorted())
    }

    // MARK: - Backfill batches

    func testBatchesAreContiguousNewestFirstAndKeepTheInputOrder() {
        XCTAssertEqual(CoreDataManager.batches(of: [], size: 3), [])
        let t = Self.day0
        // up to the size: one batch, in the input order
        XCTAssertEqual(
            CoreDataManager.batches(of: [t, t.addingTimeInterval(60), t.addingTimeInterval(-60)], size: 3),
            [[0, 1, 2]]
        )

        var generator = SeededGenerator(seed: 7)
        // unsorted, with equal dates
        let dates = (0 ..< 10000).map { _ in t.addingTimeInterval(Double(Int.random(in: 0 ..< 5000, using: &generator)) * 60) }
        let batches = CoreDataManager.batches(of: dates, size: 3000)
        XCTAssertEqual(batches.map(\.count), [3000, 3000, 3000, 1000])
        XCTAssertEqual(batches.flatMap { $0 }.sorted(), Array(dates.indices))
        for batch in batches {
            XCTAssertEqual(batch, batch.sorted())
        }
        for (newer, older) in zip(batches, batches.dropFirst()) {
            XCTAssertGreaterThanOrEqual(newer.map { dates[$0] }.min()!, older.map { dates[$0] }.max()!)
        }
        XCTAssertEqual(batches[0].map { dates[$0] }.max(), dates.max())

        // equal dates across a boundary: the earlier input goes to the newer batch
        XCTAssertEqual(
            CoreDataManager.batches(
                of: [t, t, t, t.addingTimeInterval(60), t.addingTimeInterval(-60)],
                size: 2
            ),
            [[0, 3], [1, 2], [4]]
        )
    }

    private func reading(_ date: Date, _ type: String? = "sgv") -> BloodGlucose {
        BloodGlucose(
            glucose: 100,
            date: Decimal(date.timeIntervalSince1970 * 1000),
            dateString: date,
            type: type
        )
    }

    func testInsertBatchChecksTheStoredRowsAroundIt() async throws {
        let container = StatsFixtures.inMemoryContainer()

        let t = Self.day0
        // stored: a CGM reading at t, a manual BG an hour later
        let stored = [reading(t), reading(t.addingTimeInterval(.hours(1)), "Manual")]
        _ = try await container.performBackgroundTask { try CoreDataManager.insertBatch(stored, into: $0) }

        // the newer batch, as the backfill stores it first
        let newer = [
            reading(t.addingTimeInterval(10)), // duplicate of the stored one
            reading(t.addingTimeInterval(.hours(1)), nil), // a CGM reading next to the manual BG: kept
            reading(t.addingTimeInterval(TimeInterval.hours(1) + 20), "Manual"), // duplicate of the stored manual BG
            reading(t.addingTimeInterval(.hours(2)))
        ]
        let first = try await container.performBackgroundTask { try CoreDataManager.insertBatch(newer, into: $0) }
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(
            first.change,
            .interval(DateInterval(start: t.addingTimeInterval(.hours(1)), end: t.addingTimeInterval(.hours(2))), newest: true)
        )

        // the older batch: its newest reading is a duplicate of the stored one just after it
        let older = [
            reading(t.addingTimeInterval(-30)),
            reading(t.addingTimeInterval(-300)),
            reading(t.addingTimeInterval(-600), "Manual")
        ]
        let second = try await container.performBackgroundTask { try CoreDataManager.insertBatch(older, into: $0) }
        XCTAssertEqual(second.count, 2)
        // the manual BG is not a statistics change; older than the stored readings
        XCTAssertEqual(
            second.change,
            .interval(DateInterval(start: t.addingTimeInterval(-300), end: t.addingTimeInterval(-300)), newest: false)
        )

        let count = try await container.performBackgroundTask { context in
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Readings"))
        }
        XCTAssertEqual(count, 6)
    }

    // MARK: - Backfill paging

    private struct PageFailure: Error {}

    /// A Nightscout serving `dates` newest first, at most `limit` per page, both ends of the interval included.
    private static func page(_ dates: [Date], limit: Int) -> @Sendable(DateInterval) -> [Date] {
        let newestFirst = dates.sorted(by: >)
        return { interval in
            Array(newestFirst.filter { interval.contains($0) }.prefix(limit))
        }
    }

    func testFetchPagesGoesBackToSince() async {
        let since = Self.day0
        // a minute apart from an hour before `since`, and a second reading on one date
        let dates = (0 ..< 300).map { since.addingTimeInterval(Double($0 - 60) * 60) } + [since.addingTimeInterval(120 * 60)]
        let page = Self.page(dates, limit: 50)
        let result = await BaseNightscoutManager.fetchPages(
            since: since,
            until: since.addingTimeInterval(.hours(10)),
            date: { $0 },
            page: { page($0) },
            reached: { _ in }
        )
        XCTAssertNil(result.error)
        let expected = dates.filter { $0 > since }
        XCTAssertEqual(Set(result.entries), Set(expected))
        XCTAssertEqual(result.entries.count, expected.count) // both readings on the one date (on one page)
    }

    func testFetchPagesStopsAtAFailedPageWithWhatItHas() async {
        let since = Self.day0
        let dates = (0 ..< 300).map { since.addingTimeInterval(Double($0) * 60 + 30) }
        let page = Self.page(dates, limit: 100)
        // the third page fails
        let failBefore = dates[100]
        let result = await BaseNightscoutManager.fetchPages(
            since: since,
            until: since.addingTimeInterval(.hours(10)),
            date: { $0 },
            page: { interval in
                if interval.end < failBefore { throw PageFailure() }
                return page(interval)
            },
            reached: { _ in }
        )
        XCTAssertTrue(result.error is PageFailure)
        XCTAssertEqual(result.entries, Array(dates[100...].reversed()))
        XCTAssertEqual(result.oldest, dates[100])

        // the first page fails
        let none = await BaseNightscoutManager.fetchPages(
            since: since,
            until: since.addingTimeInterval(.hours(10)),
            date: { $0 },
            page: { _ -> [Date] in throw PageFailure() },
            reached: { _ in }
        )
        XCTAssertTrue(none.error is PageFailure)
        XCTAssertEqual(none.entries, [])
        XCTAssertNil(none.oldest)
    }

    func testFetchPagesEnds() async {
        let since = Self.day0
        let until = since.addingTimeInterval(.hours(10))
        // nothing there
        let empty = await BaseNightscoutManager.fetchPages(
            since: since, until: until, date: { $0 }, page: { _ in [Date]() }, reached: { _ in }
        )
        XCTAssertEqual(empty.entries, [])
        XCTAssertNil(empty.error)
        // a server ignoring the end returns the same page again: taken once, and a failure
        let same = [since.addingTimeInterval(.hours(2)), since.addingTimeInterval(.hours(1))]
        let stuck = await BaseNightscoutManager.fetchPages(
            since: since, until: until, date: { $0 }, page: { _ in same }, reached: { _ in }
        )
        XCTAssertEqual(stuck.entries, same)
        XCTAssertEqual(stuck.error as? FetchPagesError, .notPagingBack)
        XCTAssertEqual(stuck.oldest, since.addingTimeInterval(.hours(1)))
    }

    func testFetchPagesWithWholeSecondEnds() async {
        let since = Self.day0
        // half a second past the minute, from 10 minutes before `since`
        let dates = (0 ..< 300).map { since.addingTimeInterval(Double($0 - 10) * 60 + 0.5) }
        let newestFirst = dates.sorted(by: >)
        let result = await BaseNightscoutManager.fetchPages(
            since: since,
            until: since.addingTimeInterval(.hours(10)),
            date: { $0 },
            page: { interval in
                // like Nightscout: the end compared as a whole-second string, so the entries of its second are in
                // (the oldest entry of the page before, again)
                let endSecond = interval.end.timeIntervalSinceReferenceDate.rounded(.down)
                let inInterval = newestFirst
                    .filter { $0 >= interval.start }
                    .filter { endSecond >= $0.timeIntervalSinceReferenceDate.rounded(.down) }
                return Array(inInterval.prefix(50))
            },
            reached: { _ in }
        )
        // ends at the page with only the repeated entry, each entry taken once
        XCTAssertNil(result.error)
        XCTAssertEqual(result.entries, newestFirst.filter { $0 > since })
    }

    // MARK: - Storing in batches

    private final class Recorder<Item>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Item] = []

        func append(_ item: Item) {
            lock.withLock { items.append(item) }
        }

        var all: [Item] {
            lock.withLock { items }
        }
    }

    private struct SaveFailure: Error {}

    func testStoreGlucoseStoresBatchesNewestFirstWithACallInBetween() async throws {
        let container = StatsFixtures.inMemoryContainer()
        let batches = Recorder<[Date]>()
        let manager = CoreDataManager(
            appCoordinator: AppCoordinator(),
            container: container,
            batchSize: 100,
            insert: { readings, context in
                batches.append(readings.map(\.dateString))
                return try CoreDataManager.insertBatch(readings, into: context)
            }
        )
        let t = Self.day0
        var generator = SeededGenerator(seed: 3)
        let readings = (0 ..< 250).map { reading(t.addingTimeInterval(Double($0) * 60)) }.shuffled(using: &generator)
        let live = reading(t.addingTimeInterval(.days(1)))

        let progress = Recorder<Double>()
        let outcome = await manager.storeGlucose(readings) { value in
            progress.append(value)
            // after the first batch: a CGM reading coming in is stored before the next batch
            if progress.all.count == 1 {
                await manager.storeGlucose([live])
            }
        }

        XCTAssertEqual(outcome, CoreDataManager.GlucoseStoreOutcome(inserted: 250))
        XCTAssertEqual(progress.all, [1.0 / 3, 2.0 / 3, 1])
        let calls = batches.all
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(calls[1], [live.dateString])
        let imported = [calls[0], calls[2], calls[3]]
        XCTAssertEqual(imported.map(\.count), [100, 100, 50])
        for (newer, older) in zip(imported, imported.dropFirst()) {
            XCTAssertGreaterThan(newer.min()!, older.max()!)
        }
        let count = try await container.performBackgroundTask { context in
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Readings"))
        }
        XCTAssertEqual(count, 251)
    }

    func testStoreGlucoseFailureKeepsTheBatchesBefore() async throws {
        let container = StatsFixtures.inMemoryContainer()
        let manager = CoreDataManager(
            appCoordinator: AppCoordinator(),
            container: container,
            batchSize: 100,
            insert: { readings, context in
                if readings.contains(where: { $0.glucose == 999 }) { throw SaveFailure() }
                return try CoreDataManager.insertBatch(readings, into: context)
            }
        )
        let t = Self.day0
        // three batches: 249 ... 150, 149 ... 50 (failing), 49 ... 0 minutes
        var readings = (0 ..< 250).map { reading(t.addingTimeInterval(Double($0) * 60)) }
        readings[120].glucose = 999

        let progress = Recorder<Double>()
        let outcome = await manager.storeGlucose(readings) { progress.append($0) }

        XCTAssertEqual(outcome.inserted, 100)
        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.reached, t.addingTimeInterval(149 * 60))
        XCTAssertEqual(progress.all, [1.0 / 3])
        let count = try await container.performBackgroundTask { context in
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Readings"))
        }
        XCTAssertEqual(count, 100)
    }

    // MARK: - Upload

    /// A summary of readings back to back from day0, each covering its seconds, over the 70-145 bands.
    private func uploadSummary(_ readings: [(mgdl: Int16, seconds: Double)]) -> GlucoseSummary {
        var histogram = GlucoseHistogram()
        var time = Self.day0
        for reading in readings {
            histogram.add(
                WeightedPoint(time: time, mgdl: reading.mgdl, span: reading.seconds),
                seconds: reading.seconds,
                startsInside: true
            )
            time = time.addingTimeInterval(reading.seconds)
        }
        return Engine.summary(
            histogram,
            window: DateInterval(start: Self.day0, end: time),
            endRule: .stalled,
            calendarDays: 1,
            daysWithData: histogram.readingCount > 0 ? 1 : 0,
            bands: bands
        )
    }

    private var emptySummary: GlucoseSummary { uploadSummary([]) }

    /// day, week, month, total
    private func assertDurations(
        _ durations: Durations,
        _ expected: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let values = [durations.day, durations.week, durations.month, durations.total]
            .map { NSDecimalNumber(decimal: $0).doubleValue }
        XCTAssertEqual(values.count, expected.count, file: file, line: line)
        for (value, expected) in zip(values, expected) {
            XCTAssertEqual(value, expected, accuracy: 1E-9, file: file, line: line)
        }
    }

    private func uploadNumbers(
        day: GlucoseSummary,
        week: GlucoseSummary,
        month: GlucoseSummary,
        total: GlucoseSummary,
        units: GlucoseUnits = .mgdL,
        override: Bool = false
    ) -> DatabaseStatisticsFactory.GlucoseNumbers {
        DatabaseStatisticsFactory.glucoseNumbers(
            day: day,
            week: week,
            month: month,
            total: total,
            units: units,
            hbA1cUnit: HbA1cUnit.resolve(units: units, override: override)
        )
    }

    /// TIR = in range (L...H inclusive), Hypos < L, Hypers > H, Euglycemic = TITR 70...140; 1 decimal; each window in
    /// its own slot.
    func testUploadDistribution() {
        // L = 70, H = 145: 70 and 145 are in range, 69 low, 146 high, 141 in range but not TITR
        let edges = uploadSummary([
            (53, 1000), (54, 1000), (69, 1000), (70, 1000), (100, 1000),
            (141, 1000), (145, 1000), (146, 1000), (250, 1000), (251, 1000)
        ])
        let allInRange = uploadSummary([(100, 3000)])
        let thirds = uploadSummary([(50, 1000), (100, 2000)])

        let numbers = uploadNumbers(day: edges, week: allInRange, month: thirds, total: emptySummary)

        assertDurations(numbers.tir, [40, 100, 66.7, 0])
        assertDurations(numbers.hypos, [30, 0, 33.3, 0])
        assertDurations(numbers.hypers, [30, 0, 0, 0])
        assertDurations(numbers.euglycemic, [20, 100, 66.7, 0])
    }

    /// Time-weighted mean, the weighted histogram median, population SD, CV; mean, median and SD in mmol/L for mmol
    /// users, CV unchanged.
    func testUploadMedianMeanSDAndCV() {
        // 100 for 900 s, 200 for 300 s: mean 125, median 125 (per distinct value), SD sqrt(1875) = 43.30, CV 34.64
        let summary = uploadSummary([(100, 300), (100, 300), (100, 300), (200, 300)])

        let mgdl = uploadNumbers(day: summary, week: summary, month: summary, total: emptySummary)
        assertDurations(mgdl.averages.Average, [125, 125, 125, 0])
        assertDurations(mgdl.averages.Median, [125, 125, 125, 0])
        assertDurations(mgdl.variance.SD, [43.3, 43.3, 43.3, 0])
        assertDurations(mgdl.variance.CV, [34.6, 34.6, 34.6, 0])

        // 125 x 0.0555 = 6.94, 43.30 x 0.0555 = 2.40
        let mmol = uploadNumbers(day: summary, week: summary, month: summary, total: emptySummary, units: .mmolL)
        assertDurations(mmol.averages.Average, [6.9, 6.9, 6.9, 0])
        assertDurations(mmol.averages.Median, [6.9, 6.9, 6.9, 0])
        assertDurations(mmol.variance.SD, [2.4, 2.4, 2.4, 0])
        assertDurations(mmol.variance.CV, [34.6, 34.6, 34.6, 0])
    }

    /// HbA1c stays the ADAG eA1c, GMI is new; both in % or mmol/mol by the units / override XOR, 1 decimal.
    func testUploadHbA1cAndGMI() {
        let mean200 = uploadSummary([(200, 3000)])
        let mean150 = uploadSummary([(150, 3000)])

        let cases: [(units: GlucoseUnits, override: Bool, unit: String)] = [
            (.mgdL, false, "%"),
            (.mgdL, true, "mmol/mol"),
            (.mmolL, false, "mmol/mol"),
            (.mmolL, true, "%")
        ]
        for (units, override, unit) in cases {
            let numbers = uploadNumbers(
                day: mean200,
                week: mean150,
                month: mean200,
                total: emptySummary,
                units: units,
                override: override
            )
            XCTAssertEqual(numbers.a1cUnit, unit, "\(units) override \(override)")
            if unit == "%" {
                // eA1c (200 + 46.7) / 28.7 = 8.60, (150 + 46.7) / 28.7 = 6.85; GMI 3.31 + 0.02392 x 200 = 8.09, x 150 = 6.90
                assertDurations(numbers.hbA1c, [8.6, 6.9, 8.6, 0])
                assertDurations(numbers.gmi, [8.1, 6.9, 8.1, 0])
            } else {
                // 10.929 x (% - 2.152): eA1c 70.42 / 51.38, GMI 64.94 / 51.87
                assertDurations(numbers.hbA1c, [70.4, 51.4, 70.4, 0])
                assertDurations(numbers.gmi, [64.9, 51.9, 64.9, 0])
            }
        }
    }

    /// LoopCycles.readings = the readings starting in the 24 h window; GlucoseStorage_Days = the 90 days' first to last
    /// reading, in days.
    func testUploadReadingsAndStorageDays() {
        let day = uploadSummary([(120, 300), (120, 300), (120, 300)])
        let week = uploadSummary(Array(repeating: (mgdl: Int16(120), seconds: 300.0), count: 10))

        let first = Self.day0
        let last = first.addingTimeInterval(TimeInterval.days(2) + .hours(12))
        var histogram = GlucoseHistogram()
        for time in [first, first.addingTimeInterval(.hours(30)), last] {
            histogram.add(WeightedPoint(time: time, mgdl: 120, span: 300), seconds: 300, startsInside: true)
        }
        let total = Engine.summary(
            histogram,
            window: DateInterval(start: first, end: last.addingTimeInterval(300)),
            endRule: .stalled,
            calendarDays: 3,
            daysWithData: 3,
            bands: bands
        )

        let numbers = uploadNumbers(day: day, week: week, month: week, total: total)

        XCTAssertEqual(numbers.readings, 3)
        XCTAssertEqual(NSDecimalNumber(decimal: numbers.storageDays).doubleValue, 2.5, accuracy: 1E-9)
    }

    /// No readings: every number 0 (never NaN), the units still set.
    func testUploadEmptyWindows() {
        let numbers = uploadNumbers(
            day: emptySummary,
            week: emptySummary,
            month: emptySummary,
            total: emptySummary,
            units: .mmolL
        )

        for durations in [
            numbers.tir, numbers.hypos, numbers.hypers, numbers.euglycemic,
            numbers.averages.Average, numbers.averages.Median,
            numbers.hbA1c, numbers.gmi,
            numbers.variance.SD, numbers.variance.CV
        ] {
            assertDurations(durations, [0, 0, 0, 0])
        }
        XCTAssertEqual(numbers.a1cUnit, "mmol/mol")
        XCTAssertEqual(numbers.readings, 0)
        XCTAssertEqual(numbers.storageDays, 0)
    }

    // MARK: - Uploading the stored readings

    private func storedReading(
        _ type: String?,
        id: String? = UUID().uuidString,
        date: Date? = GlucoseStatisticsCacheTests.day0
    ) -> ReadingsSnapshot {
        ReadingsSnapshot(id: id, date: date, direction: "↔︎", glucose: 123, type: type)
    }

    /// The Nightscout entry type ("sgv", "mbg") a stored reading is uploaded as; nil: not uploaded.
    private func uploadedEntryType(_ reading: ReadingsSnapshot) -> String? {
        NightscoutConfig.StateModel.glucoseUpload(reading)?.toNightscoutEntry?.dictionaryRepresentation["type"] as? String
    }

    /// A CGM reading (sgv, or no type: stored before the type was) is an sgv entry, as before.
    func testUploadStoredCGMReadingsAsSGV() throws {
        for type in [nil, GlucoseType.sgv.rawValue] {
            let reading = storedReading(type)
            let glucose = try XCTUnwrap(NightscoutConfig.StateModel.glucoseUpload(reading))
            XCTAssertEqual(glucose.type, GlucoseType.sgv.rawValue)
            XCTAssertEqual(glucose._id, reading.id)
            XCTAssertEqual(glucose.glucose, 123)
            XCTAssertEqual(glucose.dateString, Self.day0)
            XCTAssertEqual(glucose.date, Decimal(Int(Self.day0.timeIntervalSince1970 * 1000)))
            XCTAssertEqual(uploadedEntryType(reading), "sgv")
        }
    }

    /// A manual BG is an mbg entry, as the live upload sends it.
    func testUploadStoredManualReadingAsMBG() throws {
        let reading = storedReading(GlucoseType.manual.rawValue)
        let glucose = try XCTUnwrap(NightscoutConfig.StateModel.glucoseUpload(reading))
        XCTAssertEqual(glucose.type, GlucoseType.manual.rawValue)
        XCTAssertEqual(uploadedEntryType(reading), "mbg")
        XCTAssertEqual(glucose.toNightscoutEntry?.isCalibration, false)
    }

    /// A meter reading from Nightscout, a type the live upload doesn't send, a reading without an id or a date: not
    /// uploaded.
    func testUploadSkipsOtherStoredReadings() {
        for reading in [
            storedReading("mbg"),
            storedReading("unknown"),
            storedReading(nil, id: nil),
            storedReading(nil, date: nil)
        ] {
            XCTAssertNil(NightscoutConfig.StateModel.glucoseUpload(reading))
        }
    }

    // MARK: - By weekday

    /// The service's calendar is frozen with the locale: By weekday's columns keep its weekend (Israel: Friday and
    /// Saturday, the week from Sunday).
    func testWeekdayKeepsTheLocalesWeekend() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        var israel = Self.berlin
        israel.locale = Locale(identifier: "he_IL")
        f.clock.calendar = israel
        let pooled = await f.statistics.weekdayHours(weeks: 1, bands: bands)
        XCTAssertEqual(pooled.order, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(pooled.weekend, [6, 7])
        XCTAssertEqual(pooled.days.last?.end, day(0))

        var germany = Self.berlin
        germany.locale = Locale(identifier: "de_DE")
        f.clock.calendar = germany
        let monday = await f.statistics.weekdayHours(weeks: 1, bands: bands)
        XCTAssertEqual(monday.order, [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(monday.weekend, [7, 1])
    }

    /// A first day of the period without readings is a recording start only when the store has none before the
    /// period (one row asks): readings before it, and the missing day is a day without readings, not limited on that
    /// alone; none before it, and the recording began inside the period, limited.
    func testWeekdayRecordingStartNeedsNoReadingBefore() async {
        // 4 weeks: day(-28) … day(-1); nothing on day(-28)
        let before = points(from: day(-35), through: day(-30))
        let after = points(from: day(-27), through: Self.at(0, hours: 12))
        let gap = await fixture(now: noonish, points: before + after)
        let pooled = await gap.statistics.weekdayHours(weeks: 4, bands: bands)
        XCTAssertEqual(pooled.firstDayWithData, day(-27))
        XCTAssertTrue(pooled.hasReadingsBefore)
        let missingDay = Stat.WeekdayResult(pooled, period: .weeks4)
        XCTAssertNil(missingDay.recordedSince)
        XCTAssertEqual(missingDay.daysWithData.sorted(), [3, 4, 4, 4, 4, 4, 4])
        XCTAssertFalse(missingDay.isLimited)
        // the one-row fetch, before the period
        let fetches = await gap.source.fetches
        XCTAssertTrue(fetches.contains(DateInterval(start: .distantPast, end: day(-28))))

        let started = await fixture(now: noonish, points: after)
        let recorded = Stat.WeekdayResult(await started.statistics.weekdayHours(weeks: 4, bands: bands), period: .weeks4)
        XCTAssertEqual(recorded.recordedSince, day(-27))
        XCTAssertTrue(recorded.isLimited)

        // a first day with readings asks nothing
        let whole = await fixture(now: noonish, points: points(from: day(-29), through: Self.at(0, hours: 12)))
        let complete = await whole.statistics.weekdayHours(weeks: 4, bands: bands)
        XCTAssertFalse(complete.hasReadingsBefore)
        let wholeFetches = await whole.source.fetches
        XCTAssertFalse(wholeFetches.contains { $0.start == .distantPast })
        XCTAssertFalse(Stat.WeekdayResult(complete, period: .weeks4).isLimited)
    }

    // MARK: - One tail per refresh

    private func assertEqual(_ a: [HourBucket], _ b: [HourBucket], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.map(\.hour), b.map(\.hour), file: file, line: line)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.histogram.totalSeconds, y.histogram.totalSeconds, accuracy: 1E-6, file: file, line: line)
            XCTAssertEqual(x.histogram.readingCount, y.histogram.readingCount, file: file, line: line)
        }
    }

    /// The AGP and By hour refreshes (`agp(_:bands:)`, `hourOfDay(_:bands:)`) read the tail once for both requests;
    /// separate calls read it twice.
    func testRefreshReadsTheTailOnce() async {
        let f = await fixture(now: noonish, points: twoWeeks())
        let run = weekRun

        // outside a session: the summary reads the days the profile read (it caches none), not the tail
        _ = await f.statistics.agp(.days7, bands: bands)
        var fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run, run])

        // the days are cached now: the hours read theirs, the summary nothing
        await f.source.clearFetches()
        _ = await f.statistics.hourOfDay(.days7, bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run])

        // separate calls: the tail twice
        await f.source.clearFetches()
        _ = await f.statistics.hourOfDay(.days7)
        _ = await f.statistics.summary(.days7, bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run, tail])

        // in a session: the profile holds the readings; the next refresh reads nothing
        await f.statistics.beginSession()
        await f.source.clearFetches()
        _ = await f.statistics.agp(.days7, bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run])
        await f.source.clearFetches()
        _ = await f.statistics.hourOfDay(.days7, bands: bands)
        fetches = await f.source.fetches
        XCTAssertEqual(fetches, [])
    }

    func testRefreshEqualsSeparateCalls() async {
        let data = twoWeeks()
        for session in [false, true] {
            let batched = await fixture(now: noonish, points: data)
            let separate = await fixture(now: noonish, points: data)
            if session {
                await batched.statistics.beginSession()
                await separate.statistics.beginSession()
            }

            let agp = await batched.statistics.agp(.days7, bands: bands)
            let bins = await separate.statistics.agp(.days7)
            let agpSummary = await separate.statistics.summary(.days7, bands: bands)
            assertEqual(agp.bins, bins)
            assertEqual(agp.summary, agpSummary)
            assertEqual(agp.summary, expected(.days7, data, now: noonish).summary)

            let hours = await batched.statistics.hourOfDay(.days14, bands: bands)
            let buckets = await separate.statistics.hourOfDay(.days14)
            let hoursSummary = await separate.statistics.summary(.days14, bands: bands)
            assertEqual(hours.buckets, buckets)
            assertEqual(hours.summary, hoursSummary)
            assertEqual(hours.summary, expected(.days14, data, now: noonish).summary)
        }
    }

    /// A reading saved during the refresh, its change not delivered yet: the summary keeps the profile's E (and now),
    /// from the one tail read; a separate call would see the reading.
    func testRefreshHasOneEnd() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        let run = weekRun
        let gate = await f.source.gate { $0 == run }
        let statistics = f.statistics
        let bands = self.bands
        let refreshing = Task { await statistics.agp(.days7, bands: bands) }
        await arrival(at: gate, f.source)

        let t = Self.at(0, hours: 12, minutes: 5)
        f.clock.now = t.addingTimeInterval(30)
        await f.source.append([GlucosePoint(time: t, mgdl: 250)])
        await f.source.open(gate)
        let result = await refreshing.value

        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run, run])
        let before = expected(.days7, data, now: noonish)
        assertEqual(result.bins, Engine.agp(before.w, calendar: Self.berlin, clippedTo: before.window))
        assertEqual(result.summary, before.summary)
        XCTAssertEqual(result.summary.window, before.window)

        let separate = await f.statistics.summary(.days7, bands: bands)
        XCTAssertEqual(separate.lastReading, t)
        XCTAssertNotEqual(separate.window.end, result.summary.window.end)
    }

    /// A change delivered between the tail read and the summary: the summary reads the tail again (and with it its
    /// own E), as a request of its own; the profile is computed from what it read.
    func testInvalidationDuringARefreshReadsTheTailAgain() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        let run = weekRun
        let gate = await f.source.gate { $0 == run }
        let statistics = f.statistics
        let bands = self.bands
        let refreshing = Task { await statistics.agp(.days7, bands: bands) }
        await arrival(at: gate, f.source)

        let t = Self.at(0, hours: 12, minutes: 5)
        f.clock.now = t.addingTimeInterval(30)
        let reading = GlucosePoint(time: t, mgdl: 250)
        await f.source.append([reading])
        await f.statistics.readingsChanged(ReadingsChange.readings(at: [t], newest: true)!)
        await f.source.open(gate)
        let result = await refreshing.value

        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run, tail, run])
        assertEqual(result.bins, expectedAGP(.days7, data, now: noonish))
        XCTAssertEqual(result.summary.lastReading, t)
        assertEqual(result.summary, expected(.days7, data + [reading], now: f.clock.now).summary)
    }

    /// A time zone change noticed between the requests is an invalidation too: the summary reads the New York tail.
    func testTimeZoneChangeDuringARefreshReadsTheTailAgain() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        let run = weekRun
        let gate = await f.source.gate { $0 == run }
        let statistics = f.statistics
        let bands = self.bands
        let refreshing = Task { await statistics.hourOfDay(.days7, bands: bands) }
        await arrival(at: gate, f.source)

        let newYork = StatsFixtures.calendar("America/New_York")
        f.clock.calendar = newYork
        await f.source.open(gate)
        let result = await refreshing.value

        let reads = newYorkReads(newYork)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run, reads.tail, reads.run])
        XCTAssertEqual(f.coordinator.glucoseStatsChanged.value, StatsChange(seq: 1, interval: nil))
        assertEqual(result.summary, expected(.days7, data, now: noonish, calendar: newYork).summary)
    }

    /// A failed tail read serves only the request it was read for: the summary reads it again.
    func testFailedTailIsNotShared() async {
        let data = twoWeeks()
        let f = await fixture(now: noonish, points: data)
        let run = weekRun
        let tail = self.tail
        await f.source.failOnce { $0 == tail }

        let result = await f.statistics.hourOfDay(.days7, bands: bands)
        let fetches = await f.source.fetches
        XCTAssertEqual(fetches, [tail, run, tail, run])
        let all = expected(.days7, data, now: noonish)
        // the hours without today (and E from no readings); the summary complete
        let expectedHours = Engine.hourOfDay(all.w, calendar: Self.berlin, clippedTo: all.window)
        XCTAssertLessThan(
            result.buckets.map(\.histogram.totalSeconds).reduce(0, +),
            expectedHours.map(\.histogram.totalSeconds).reduce(0, +)
        )
        assertEqual(result.summary, all.summary)
    }

    // MARK: - Meals rows

    private func mealsRowEntry(_ id: String?, isFPU: Bool?) -> CarbsEntry {
        CarbsEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            actualDate: nil,
            carbs: 10,
            fat: nil,
            protein: nil,
            fiber: nil,
            note: nil,
            enteredBy: CarbsEntry.manual,
            isFPU: isFPU
        )
    }

    /// A deleted meal takes its own row: its FPU entries (same created-at, own ids) have none.
    func testDeletedMealRowIsTheMealsOwn() {
        let deleted = [
            mealsRowEntry("fpu-1", isFPU: true),
            mealsRowEntry("meal", isFPU: false),
            mealsRowEntry("fpu-2", isFPU: true)
        ]
        XCTAssertEqual(BaseCarbsStorage.mealRowIDs(of: deleted), ["meal"])
    }

    /// A Nightscout entry (no isFPU) has a row; an entry without an id matches none; an id is deleted once.
    func testDeletedMealRowIDs() {
        let deleted = [
            mealsRowEntry("ns", isFPU: nil),
            mealsRowEntry(nil, isFPU: false),
            mealsRowEntry("", isFPU: false),
            mealsRowEntry("ns", isFPU: false)
        ]
        XCTAssertEqual(BaseCarbsStorage.mealRowIDs(of: deleted), ["ns"])
    }

    /// Each id keeps its row with the earliest actual date; rows without an id are left alone.
    func testDuplicateMealRows() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let rows: [(id: String, actualDate: Date?)] = [
            (id: "ns", actualDate: t.addingTimeInterval(.minutes(2))),
            (id: "ns", actualDate: t),
            (id: "local", actualDate: t),
            (id: "", actualDate: t),
            (id: "", actualDate: t),
            (id: "ns", actualDate: nil),
            (id: "ns", actualDate: t.addingTimeInterval(.minutes(1)))
        ]
        // no date sorts first in the store: that row stays
        XCTAssertEqual(CoreDataStorage.duplicateMealRows(rows), [0, 1, 6])
    }

    /// The deduplication deletes in chunks: all items, in order, none longer than the size.
    func testChunked() {
        XCTAssertEqual(CoreDataStorage.chunked(Array(0 ..< 7), size: 3), [[0, 1, 2], [3, 4, 5], [6]])
        XCTAssertEqual(CoreDataStorage.chunked(Array(0 ..< 6), size: 3), [[0, 1, 2], [3, 4, 5]])
        XCTAssertEqual(CoreDataStorage.chunked([Int](), size: 3), [])
        XCTAssertEqual(CoreDataStorage.chunked(Array(0 ..< 2), size: 1000), [[0, 1]])
    }

    /// An "end with new carbs" override ends on any meal dated after its start (the latest), of any source, from the
    /// published carbs; not on carb equivalents or empty entries, nor on meals from before it.
    func testOverrideEndsOnAMealAfterItsStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func entry(
            _ id: String,
            minutes: Int,
            carbs: Decimal = 20,
            isFPU: Bool = false,
            enteredBy: String = "Mom"
        ) -> CarbsEntry {
            let date = start.addingTimeInterval(.minutes(minutes))
            return CarbsEntry(
                id: id, createdAt: date, actualDate: date,
                carbs: carbs, fat: nil, protein: nil, fiber: nil, note: nil,
                enteredBy: enteredBy, isFPU: isFPU
            )
        }
        XCTAssertNil(BaseOverrideManager.meal(after: start, in: [entry("before", minutes: -5)]))
        XCTAssertNil(BaseOverrideManager.meal(after: start, in: [entry("fpu", minutes: 30, isFPU: true)]))
        XCTAssertNil(BaseOverrideManager.meal(after: start, in: [entry("empty", minutes: 30, carbs: 0)]))
        // a caregiver's meal dated later than one entered here afterwards (back-dated) still counts
        let carbs = [
            entry("backdated", minutes: -10, enteredBy: CarbsEntry.manual),
            entry("caregiver", minutes: 20),
            entry("watch", minutes: 10, enteredBy: CarbsEntry.watch)
        ]
        XCTAssertEqual(BaseOverrideManager.meal(after: start, in: carbs)?.id, "caregiver")
    }

    /// Records the row writes. A row delete is held until `open` (the first one to arrive is announced).
    private actor GatedMealRows: MealRowStore {
        private(set) var events: [String] = []
        private var isOpen = false
        private var held: [AsyncStream<Void>.Continuation] = []
        private var watchers: [AsyncStream<Void>.Continuation] = []
        private var deletes = 0

        private var holdingSaves = false
        private var saves = 0
        private var saveWatchers: [AsyncStream<Void>.Continuation] = []

        private var eventHandler: (@Sendable(String) -> Void)?

        /// Called with every row event, as it is recorded (nil: no more).
        func onEvent(_ handler: (@Sendable(String) -> Void)?) {
            eventHandler = handler
        }

        private func record(_ event: String) {
            events.append(event)
            eventHandler?(event)
        }

        func saveMeals(_ entries: [CarbsEntry]) async {
            record("save " + entries.compactMap(\.id).joined(separator: ","))
            guard holdingSaves else { return }
            saves += 1
            saveWatchers.forEach { $0.finish() }
            saveWatchers = []
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            held.append(continuation)
            for await _ in stream {}
        }

        /// From now: the row saves are held (not the deletes) until `open`.
        func holdSaves() {
            isOpen = true
            holdingSaves = true
        }

        /// Returns once a row save is held (at once when one was).
        func saveArrived() async {
            guard saves == 0 else { return }
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            saveWatchers.append(continuation)
            for await _ in stream {}
        }

        func deleteMeals(ids: [String]) async {
            record("delete " + ids.joined(separator: ","))
            deletes += 1
            watchers.forEach { $0.finish() }
            watchers = []
            guard !isOpen else { return }
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            held.append(continuation)
            for await _ in stream {}
        }

        func deduplicateMealsOnce() async {}

        /// Returns once a row delete is held (at once when one was).
        func deleteArrived() async {
            guard deletes == 0 else { return }
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            watchers.append(continuation)
            for await _ in stream {}
        }

        func open() {
            isOpen = true
            holdingSaves = false
            held.forEach { $0.finish() }
            held = []
        }
    }

    private struct MealsFixture: Sendable {
        let carbs: BaseCarbsStorage
        let rows: GatedMealRows
        let files: BaseFileStorage
        let coordinator: AppCoordinator
        let file: String

        func stored() async -> [CarbsEntry] {
            await files.retrieve(file, as: [CarbsEntry].self) ?? []
        }
    }

    private func mealsFixture() -> MealsFixture {
        let files = BaseFileStorage()
        let coordinator = AppCoordinator()
        let rows = GatedMealRows()
        let file = "test-carbs-\(UUID().uuidString).json"
        let carbs = BaseCarbsStorage(
            storage: files,
            settingsManager: BaseSettingsManager(storage: files, appCoordinator: coordinator),
            appCoordinator: coordinator,
            mealRows: rows,
            carbsFile: file
        )
        return MealsFixture(carbs: carbs, rows: rows, files: files, coordinator: coordinator, file: file)
    }

    private func mealsEntry(_ id: String, at date: Date, carbs: Decimal = 20) -> CarbsEntry {
        CarbsEntry(
            id: id, createdAt: date, actualDate: date,
            carbs: carbs, fat: 0, protein: 0, fiber: nil, note: nil,
            enteredBy: CarbsEntry.manual, isFPU: false
        )
    }

    /// Starts `operation` in a task, and returns once that task runs (the operation is being called).
    private func startMealsCall(_ operation: @escaping @Sendable() async -> Void) async -> Task<Void, Never> {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task {
            signal.finish()
            await operation()
        }
        for await _ in started {}
        return task
    }

    /// Starts `operation` while another change is held in the row store, and checks it waits: its row `event` doesn't
    /// come within 0.3 s (without the one-at-a-time changes it comes at once: the actor is free while the other waits).
    private func startWaitingMealsCall(
        _ operation: @escaping @Sendable() async -> Void,
        event: String,
        rows: GatedMealRows
    ) async -> Task<Void, Never> {
        let reached = expectation(description: "\(event) reached the row store")
        reached.isInverted = true
        await rows.onEvent { if $0 == event { reached.fulfill() } }
        // only the events from here: the same event can be an earlier change's (a stored download's row)
        let earlier = await rows.events.count
        let task = await startMealsCall(operation)
        await fulfillment(of: [reached], timeout: 0.3)
        // no fulfilling after the wait
        await rows.onEvent(nil)
        let events = await rows.events.dropFirst(earlier)
        XCTAssertFalse(events.contains(event), "\(event) ran while the other change was held")
        return task
    }

    /// A meal stored while a delete waits on its Meals row: it waits, and the published carbs end as the file's.
    func testConcurrentCarbsChangesPublishTheFile() async {
        let f = mealsFixture()
        let now = Date().truncatedToSecond
        let a = mealsEntry("A", at: now.addingTimeInterval(.minutes(-30)))
        let b = mealsEntry("B", at: now.addingTimeInterval(.minutes(-10)))
        await f.carbs.storeMeal(a)

        let deleting = Task { await f.carbs.deleteCarbsAndFPUs(at: a.createdAt) }
        await f.rows.deleteArrived()
        let storing = await startWaitingMealsCall({ await f.carbs.storeMeal(b) }, event: "save B", rows: f.rows)
        // nothing published in between
        XCTAssertEqual(f.coordinator.carbHistory.value.compactMap(\.id), ["A"])
        await f.rows.open()
        await deleting.value
        await storing.value

        let stored = await f.stored()
        XCTAssertEqual(stored.compactMap(\.id), ["B"])
        XCTAssertEqual(f.coordinator.carbHistory.value.compactMap(\.id), stored.compactMap(\.id))
        let events = await f.rows.events
        XCTAssertEqual(events, ["save A", "delete A", "save B"])
        await f.files.remove(f.file)
    }

    /// An edit is one step: a download arriving while the edit waits on the Meals row lands after it.
    func testMealEditIsOneStep() async {
        let f = mealsFixture()
        let at = Date().truncatedToSecond.addingTimeInterval(.minutes(-30))
        await f.carbs.storeMeal(mealsEntry("A", at: at))

        let edited = mealsEntry("A", at: at, carbs: 35)
        let editing = Task { await f.carbs.replaceMeal(createdAt: at, with: edited) }
        await f.rows.deleteArrived()
        let downloaded = CarbsEntry(
            id: "N", createdAt: at.addingTimeInterval(.minutes(5)), actualDate: nil,
            carbs: 10, fat: nil, protein: nil, fiber: nil, note: nil,
            enteredBy: "Mom", isFPU: nil
        )
        let polling = await startWaitingMealsCall(
            { await f.carbs.storeDownloadedCarbs([downloaded]) },
            event: "save N",
            rows: f.rows
        )
        XCTAssertEqual(f.coordinator.carbHistory.value.compactMap(\.id), ["A"])
        await f.rows.open()
        await editing.value
        await polling.value

        let events = await f.rows.events
        XCTAssertEqual(events, ["save A", "delete A", "save A", "save N"])
        let stored = await f.stored()
        XCTAssertEqual(Set(stored.compactMap(\.id)), ["A", "N"])
        XCTAssertEqual(stored.first { $0.id == "A" }?.carbs, 35)
        XCTAssertEqual(f.coordinator.carbHistory.value.compactMap(\.id), stored.compactMap(\.id))
        await f.files.remove(f.file)
    }

    /// An edit publishes once, with the new meal: while it saves the new meal's row, the published carbs still have
    /// the old one (never neither).
    func testMealEditPublishesOnce() async {
        let f = mealsFixture()
        let at = Date().truncatedToSecond.addingTimeInterval(.minutes(-30))
        await f.rows.open()
        await f.carbs.storeMeal(mealsEntry("A", at: at))
        await f.rows.holdSaves()

        let edited = mealsEntry("A", at: at, carbs: 35)
        let editing = Task { await f.carbs.replaceMeal(createdAt: at, with: edited) }
        await f.rows.saveArrived()
        XCTAssertEqual(f.coordinator.carbHistory.value.filter { $0.isFPU != true }.map(\.carbs), [20])
        await f.rows.open()
        await editing.value

        XCTAssertEqual(f.coordinator.carbHistory.value.filter { $0.isFPU != true }.map(\.carbs), [35])
        let stored = await f.stored()
        XCTAssertEqual(f.coordinator.carbHistory.value.compactMap(\.id), stored.compactMap(\.id))
        await f.files.remove(f.file)
    }

    // MARK: - Nightscout carbs fetch

    private var nsFPU: FPUSettings { FPUSettings(interval: 30, timeCap: 8, adjustment: 0.5, delay: 60) }
    /// a whole second
    private var nsMealTime: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private var nsNow: Date { nsMealTime.addingTimeInterval(.hours(1)) }

    private func nsEntry(
        _ id: String?,
        carbs: Decimal = 20,
        fat: Decimal? = nil,
        protein: Decimal? = nil,
        enteredBy: String? = "Careportal",
        at date: Date? = nil,
        uploadedID: String? = nil
    ) -> CarbsEntry {
        var entry = CarbsEntry(
            id: id, createdAt: date ?? nsMealTime, actualDate: nil,
            carbs: carbs, fat: fat, protein: protein, fiber: nil, note: nil,
            enteredBy: enteredBy, isFPU: nil
        )
        entry.uploadedID = uploadedID
        return entry
    }

    private func nsMerge(
        _ fetched: [CarbsEntry],
        into stored: [CarbsEntry],
        conversion: Bool = true,
        now: Date? = nil
    ) -> DownloadedCarbsMerge {
        BaseCarbsStorage.mergeDownloaded(
            fetched,
            into: stored,
            fpu: nsFPU,
            fatProteinConversion: conversion,
            now: now ?? nsNow
        )
    }

    private func nsFPUs(_ carbs: [CarbsEntry]?, of id: String) -> [CarbsEntry] {
        (carbs ?? [])
            .filter { $0.isFPU == true && ($0.id ?? "").hasPrefix(BaseCarbsStorage.downloadedFPUPrefix(id)) }
            .sorted { ($0.actualDate ?? .distantPast) < ($1.actualDate ?? .distantPast) }
    }

    /// Every poll downloads the last 24 h again: the meal and its carb equivalents are stored once.
    func testRepolledDownloadIsSplitOnce() {
        let fetched = [nsEntry("A", fat: 20, protein: 20)]
        guard let stored = nsMerge(fetched, into: []).carbs else { return XCTFail("the first download is stored") }
        XCTAssertEqual(stored.filter { $0.isFPU == true }.count, 6)
        XCTAssertEqual(stored.filter { $0.isFPU != true }.map(\.id), ["A"])

        for poll in 1 ... 5 {
            let later = nsNow.addingTimeInterval(.minutes(poll))
            XCTAssertNil(nsMerge(fetched, into: stored, now: later).carbs, "poll \(poll) changed the carbs")
        }
    }

    /// The carb equivalents start from the meal's own time (+ the delay), not from the download.
    func testDownloadedCarbEquivalentsStartAtTheMealsTime() {
        let carbs = nsMerge([nsEntry("A", fat: 20, protein: 20)], into: []).carbs
        let fpus = nsFPUs(carbs, of: "A")

        let minutes = [60, 90, 120, 150, 180, 210]
        XCTAssertEqual(fpus.compactMap(\.actualDate), minutes.map { nsMealTime.addingTimeInterval(.minutes($0)) })
        XCTAssertEqual(fpus.compactMap(\.id), (0 ..< 6).map { "A.fpu.\($0)" })
        XCTAssertEqual(Set(fpus.map(\.createdAt)), [nsMealTime])
        for fpu in fpus {
            XCTAssertEqual(Double(fpu.carbs), 2.2, accuracy: 0.001)
        }
        let meal = carbs?.first { $0.id == "A" }
        XCTAssertEqual(meal?.actualDate, nsMealTime)
        XCTAssertEqual(meal?.isFPU, false)
    }

    /// Each downloaded meal is split by its own fat and protein (not the oldest one's).
    func testTwoDownloadsAreSplitByTheirOwnFatAndProtein() {
        let later = nsMealTime.addingTimeInterval(.minutes(30))
        let carbs = nsMerge(
            [nsEntry("B", protein: 50, at: later), nsEntry("A", fat: 20, protein: 20)],
            into: []
        ).carbs

        let a = nsFPUs(carbs, of: "A")
        let b = nsFPUs(carbs, of: "B")
        XCTAssertEqual(a.count, 6)
        XCTAssertEqual(b.count, 6)
        for fpu in a {
            XCTAssertEqual(Double(fpu.carbs), 2.2, accuracy: 0.001)
        }
        for fpu in b {
            XCTAssertEqual(Double(fpu.carbs), 1.7, accuracy: 0.001)
        }
        XCTAssertEqual(b.first?.actualDate, later.addingTimeInterval(.minutes(60)))
        XCTAssertEqual(Set(b.map(\.createdAt)), [later])
        XCTAssertEqual(carbs?.filter { $0.isFPU == true }.count, 12)
    }

    /// A remote meal comes back from Nightscout with its own `_id`: it is not imported again (one poll, one meal).
    func testRemoteMealRoundTripAloneIsNotImported() {
        let local = CarbsEntry(
            id: "U", createdAt: nsMealTime, actualDate: nsMealTime,
            carbs: 20, fat: 0, protein: 0, fiber: nil, note: "Remote",
            enteredBy: CarbsEntry.remote, isFPU: false
        )
        let back = nsEntry("X", enteredBy: CarbsEntry.remote, uploadedID: "U")

        let merge = nsMerge([back], into: [local])
        XCTAssertNil(merge.carbs)
        XCTAssertTrue(merge.meals.isEmpty)

        // edited in Nightscout: still iAPS's, by the id it was uploaded with
        let edited = nsEntry("X", enteredBy: "Edited", uploadedID: "U")
        XCTAssertNil(nsMerge([edited], into: [local]).carbs)
    }

    /// The same in a download of several meals: the caregiver's arrives, the remote meal stays one entry.
    func testRemoteMealRoundTripWithOthersIsNotImported() {
        let local = CarbsEntry(
            id: "U", createdAt: nsMealTime, actualDate: nsMealTime,
            carbs: 20, fat: 0, protein: 0, fiber: nil, note: "Remote",
            enteredBy: CarbsEntry.remote, isFPU: false
        )
        let back = nsEntry("X", enteredBy: CarbsEntry.remote, uploadedID: "U")
        let caregiver = nsEntry("C", carbs: 30, enteredBy: "Mom", at: nsMealTime.addingTimeInterval(.minutes(10)))

        let merge = nsMerge([caregiver, back], into: [local])
        let carbs = merge.carbs ?? []
        XCTAssertEqual(Set(carbs.compactMap(\.id)), ["U", "C"])
        XCTAssertEqual(carbs.filter { $0.createdAt == nsMealTime }.count, 1)
        XCTAssertEqual(merge.meals.map(\.id), ["C"])
    }

    /// A caregiver's entry (and another app's, with its own `id` field) arrives; one edited on this phone stays local.
    func testCaregiverDownloadArrives() {
        let localMeal = CarbsEntry(
            id: "L", createdAt: nsMealTime.addingTimeInterval(.minutes(-20)), actualDate: nil,
            carbs: 40, fat: 0, protein: 0, fiber: nil, note: nil,
            enteredBy: CarbsEntry.manual, isFPU: false
        )
        let merge = nsMerge(
            [nsEntry("C", carbs: 30, enteredBy: "Mom"), nsEntry("D", carbs: 5, enteredBy: nil, uploadedID: "foreign")],
            into: [localMeal]
        )
        let caregiver = merge.carbs?.first { $0.id == "C" }
        XCTAssertEqual(caregiver?.carbs, 30)
        XCTAssertEqual(caregiver?.actualDate, nsMealTime)
        XCTAssertEqual(caregiver?.isFPU, false)
        XCTAssertNotNil(merge.carbs?.first { $0.id == "D" })
        XCTAssertNotNil(merge.carbs?.first { $0.id == "L" })
        XCTAssertEqual(merge.meals.map(\.id), ["C", "D"])

        let editedHere = CarbsEntry(
            id: "C", createdAt: nsMealTime, actualDate: nsMealTime,
            carbs: 45, fat: 0, protein: 0, fiber: nil, note: nil,
            enteredBy: CarbsEntry.manual, isFPU: false
        )
        XCTAssertNil(nsMerge([nsEntry("C", carbs: 30, enteredBy: "Mom")], into: [editedHere]).carbs)
    }

    /// The careportal posts fat and protein as strings: a number, a numeric string or garbage spoils only that field;
    /// an entry that cannot be read at all is left out, not the download.
    func testDownloadedFatAndProteinDecodeLeniently() throws {
        let json = """
        [
          {"_id": "a", "created_at": "2026-11-01T12:00:00.000Z", "carbs": 10, "fat": "15", "protein": 12, "id": "U"},
          {"_id": "b", "created_at": "2026-11-01T12:05:00.000Z", "carbs": 20, "fat": "lots", "protein": {"g": 3}},
          {"_id": "c", "created_at": "2026-11-01T12:10:00.000Z", "carbs": "garbage"},
          {"_id": "d", "created_at": "2026-11-01T12:15:00.000Z", "carbs": 5, "fat": " 7.5 "}
        ]
        """
        let entries = try JSONCoding.decoder.decode([LossyCarbsEntry].self, from: Data(json.utf8)).compactMap(\.entry)
        XCTAssertEqual(entries.map(\.id), ["a", "b", "d"])
        guard entries.count == 3 else { return }
        XCTAssertEqual(entries[0].fat, 15)
        XCTAssertEqual(entries[0].protein, 12)
        XCTAssertEqual(entries[0].uploadedID, "U")
        XCTAssertEqual(entries[1].carbs, 20)
        XCTAssertNil(entries[1].fat)
        XCTAssertNil(entries[1].protein)
        XCTAssertEqual(entries[2].fat, 7.5)
        XCTAssertNil(entries[2].uploadedID)
    }

    private func nsLocal(
        _ id: String,
        at date: Date? = nil,
        fat: Decimal = 0,
        protein: Decimal = 0,
        enteredBy: String = CarbsEntry.manual
    ) -> CarbsEntry {
        let date = date ?? nsMealTime
        return CarbsEntry(
            id: id, createdAt: date, actualDate: date,
            carbs: 20, fat: fat, protein: protein, fiber: nil, note: nil,
            enteredBy: enteredBy, isFPU: false
        )
    }

    /// The carb equivalents split here: ids `<prefix><n>`
    private func nsSplit(of meal: CarbsEntry, start: Date? = nil, prefix: String) -> [CarbsEntry] {
        BaseCarbsStorage.carbEquivalents(
            fat: meal.fat ?? 0,
            protein: meal.protein ?? 0,
            start: start ?? meal.actualDate ?? meal.createdAt,
            createdAt: meal.createdAt,
            fpu: nsFPU
        ) { prefix + String($0) }
    }

    private let nsObjectID = "5f8d0d55b54764421b7156c9"

    /// Two downloads of one created-at second keep their own carb equivalents, in either order, poll after poll.
    func testSameSecondDownloadsKeepTheirOwnSplits() {
        let withFat = nsEntry("A", fat: 20, protein: 20)
        let without = nsEntry("B")
        for fetched in [[withFat, without], [without, withFat]] {
            guard let stored = nsMerge(fetched, into: []).carbs else { return XCTFail("stored") }
            XCTAssertEqual(nsFPUs(stored, of: "A").count, 6)
            XCTAssertEqual(stored.filter { $0.isFPU == true }.count, 6)
            XCTAssertNil(nsMerge(fetched, into: stored).carbs)
            XCTAssertNil(nsMerge(fetched.reversed(), into: stored).carbs)
        }
    }

    /// A meal entered here of a download's created-at keeps its carb equivalents.
    func testLocalMealSharingADownloadsTimeKeepsItsSplit() {
        let local = nsLocal("L", fat: 20, protein: 20)
        let localSplit = nsSplit(of: local, prefix: "local-")
        let fetched = [nsEntry("N", fat: 0, protein: 50)]
        guard let stored = nsMerge(fetched, into: [local] + localSplit).carbs else { return XCTFail("stored") }
        XCTAssertEqual(
            Set(stored.filter { ($0.id ?? "").hasPrefix("local-") }.compactMap(\.id)),
            Set(localSplit.compactMap(\.id))
        )
        XCTAssertEqual(nsFPUs(stored, of: "N").count, 6)
        XCTAssertNil(nsMerge(fetched, into: stored).carbs)
    }

    /// A download edited here: the local version wins, and the download's own carb equivalents go.
    func testLocalEditDropsTheDownloadsSplit() {
        let edited = nsLocal("C", fat: 10)
        let editSplit = nsSplit(of: edited, prefix: "edit-")
        let downloadSplit = nsSplit(
            of: BaseCarbsStorage.storedDownload(nsEntry("C", fat: 20, protein: 20), id: "C"),
            prefix: BaseCarbsStorage.downloadedFPUPrefix("C")
        )
        let fetched = [nsEntry("C", fat: 20, protein: 20)]
        guard let stored = nsMerge(fetched, into: [edited] + editSplit + downloadSplit).carbs else {
            return XCTFail("the download's split goes")
        }
        XCTAssertTrue(nsFPUs(stored, of: "C").isEmpty)
        XCTAssertEqual(Set(stored.filter { $0.isFPU == true }.compactMap(\.id)), Set(editSplit.compactMap(\.id)))
        XCTAssertEqual(stored.first { $0.id == "C" }?.enteredBy, CarbsEntry.manual)
        XCTAssertNil(nsMerge(fetched, into: stored).carbs)
    }

    /// Copies of one download (an older version's created-at merge) collapse into one.
    func testCopiesOfADownloadCollapse() {
        let copy = BaseCarbsStorage.storedDownload(nsEntry("C", at: nsMealTime.addingTimeInterval(.minutes(-5))), id: "C")
        let current = BaseCarbsStorage.storedDownload(nsEntry("C"), id: "C")
        let merge = nsMerge([nsEntry("C")], into: [current, copy])
        XCTAssertEqual(merge.carbs?.filter { $0.id == "C" }.count, 1)
        XCTAssertEqual(merge.carbs?.first { $0.id == "C" }?.createdAt, nsMealTime)
        XCTAssertEqual(merge.meals.map(\.id), ["C"])
    }

    /// Only added or changed meals get their Meals rows written.
    func testUnchangedDownloadWritesNoRow() {
        let fetched = [nsEntry("C", carbs: 30, enteredBy: "Mom")]
        let first = nsMerge(fetched, into: [])
        XCTAssertEqual(first.meals.map(\.id), ["C"])
        let again = nsMerge(fetched, into: first.carbs ?? [])
        XCTAssertNil(again.carbs)
        XCTAssertTrue(again.meals.isEmpty)
        let changed = nsMerge([nsEntry("C", carbs: 35, enteredBy: "Mom")], into: first.carbs ?? [])
        XCTAssertEqual(changed.meals.map(\.carbs), [35])
    }

    /// The fat and protein conversion off: a new download is stored with its fat and protein, and no carb equivalents.
    func testConversionOffNewDownloadGetsNoSplit() {
        let merge = nsMerge([nsEntry("A", fat: 20, protein: 20)], into: [], conversion: false)
        guard let stored = merge.carbs else { return XCTFail("the download is stored") }
        XCTAssertTrue(stored.filter { $0.isFPU == true }.isEmpty)
        let meal = stored.first { $0.id == "A" }
        XCTAssertEqual(meal?.fat, 20)
        XCTAssertEqual(meal?.protein, 20)
        XCTAssertEqual(merge.meals.map(\.id), ["A"])
        XCTAssertNil(nsMerge([nsEntry("A", fat: 20, protein: 20)], into: stored, conversion: false).carbs)
    }

    /// The conversion turned off: an unchanged download keeps the carb equivalents split before (as a meal entered
    /// here does), copies collapsed or not.
    func testConversionOffUnchangedDownloadKeepsItsSplit() {
        let fetched = [nsEntry("A", fat: 20, protein: 20)]
        guard let stored = nsMerge(fetched, into: []).carbs else { return XCTFail("stored") }
        XCTAssertEqual(nsFPUs(stored, of: "A").count, 6)
        XCTAssertNil(nsMerge(fetched, into: stored, conversion: false).carbs)

        let copy = BaseCarbsStorage.storedDownload(nsEntry("A", fat: 20, protein: 20), id: "A")
        let collapsed = nsMerge(fetched, into: stored + [copy], conversion: false).carbs
        XCTAssertEqual(collapsed?.filter { $0.id == "A" }.count, 1)
        XCTAssertEqual(nsFPUs(collapsed, of: "A").compactMap(\.id), nsFPUs(stored, of: "A").compactMap(\.id))
    }

    /// The conversion off: a download whose fat, protein or time changed loses its old carb equivalents and gets none
    /// (as a meal edited here: replaced, not split again).
    func testConversionOffChangedDownloadDropsItsSplit() {
        guard let stored = nsMerge([nsEntry("A", fat: 20, protein: 20)], into: []).carbs else { return XCTFail("stored") }
        let later = nsMealTime.addingTimeInterval(.minutes(10))
        for edited in [nsEntry("A", fat: 30, protein: 20), nsEntry("A", fat: 20, protein: 20, at: later)] {
            let merge = nsMerge([edited], into: stored, conversion: false)
            guard let carbs = merge.carbs else { return XCTFail("the change is stored") }
            XCTAssertTrue(carbs.filter { $0.isFPU == true }.isEmpty)
            XCTAssertEqual(merge.meals.map(\.id), ["A"])
            XCTAssertNil(nsMerge([edited], into: carbs, conversion: false).carbs)
        }
    }

    /// The conversion on: a changed download is split again from its new fat and protein, an unchanged one is left.
    func testConversionOnChangedDownloadIsSplitAgain() {
        guard let stored = nsMerge([nsEntry("A", fat: 20, protein: 20)], into: [], conversion: true).carbs else {
            return XCTFail("stored")
        }
        XCTAssertEqual(nsFPUs(stored, of: "A").count, 6)
        XCTAssertNil(nsMerge([nsEntry("A", fat: 20, protein: 20)], into: stored, conversion: true).carbs)

        let edited = nsEntry("A", fat: 40, protein: 20)
        let carbs = nsMerge([edited], into: stored, conversion: true).carbs
        let expected = nsSplit(
            of: BaseCarbsStorage.storedDownload(edited, id: "A"),
            prefix: BaseCarbsStorage.downloadedFPUPrefix("A")
        )
        XCTAssertEqual(nsFPUs(carbs, of: "A").map(\.carbs), expected.map(\.carbs))
        XCTAssertEqual(carbs?.filter { $0.isFPU == true }.count, expected.count)
    }

    /// Once: a remote meal imported back on every poll loses its copies and the splits from "now", and is split once
    /// from its own time. A second run changes nothing.
    func testMigrationClearsTheRemoteMealPile() {
        let original = nsLocal("U", fat: 20, protein: 20, enteredBy: CarbsEntry.remote)
        let copy = CarbsEntry(
            id: nsObjectID, createdAt: nsMealTime, actualDate: nsMealTime,
            carbs: 20, fat: 20, protein: 20, fiber: nil, note: nil,
            enteredBy: CarbsEntry.remote, isFPU: false
        )
        let pile = nsSplit(of: original, start: nsMealTime.addingTimeInterval(.hours(1)), prefix: "old1-")
            + nsSplit(of: original, start: nsMealTime.addingTimeInterval(.hours(2)), prefix: "old2-")

        var next = 0
        guard let migrated = BaseCarbsStorage.migrateOldSplits([original, copy] + pile, fpu: nsFPU, newID: {
            next += 1
            return "new-\(next)"
        }) else { return XCTFail("migrated") }

        XCTAssertEqual(migrated.filter { $0.isFPU != true }.compactMap(\.id), ["U"])
        let fpus = migrated.filter { $0.isFPU == true }
            .sorted { ($0.actualDate ?? .distantPast) < ($1.actualDate ?? .distantPast) }
        XCTAssertEqual(fpus.compactMap(\.id), (1 ... 6).map { "new-\($0)" })
        XCTAssertEqual(fpus.first?.actualDate, nsMealTime.addingTimeInterval(.minutes(60)))
        XCTAssertNil(BaseCarbsStorage.migrateOldSplits(migrated, fpu: nsFPU, newID: { "again" }))
    }

    /// Once: a download carrying the old per-poll splits gets one of its own; another download of the second keeps
    /// none (it has no fat); a meal entered here keeps its split, and its created-at is left alone.
    func testMigrationReplacesTheOldDownloadSplits() {
        let a = BaseCarbsStorage.storedDownload(nsEntry("A", fat: 20, protein: 20), id: "A")
        let b = BaseCarbsStorage.storedDownload(nsEntry("B"), id: "B")
        let old = nsSplit(of: a, start: nsMealTime.addingTimeInterval(.hours(1)), prefix: "old1-")
            + nsSplit(of: a, start: nsMealTime.addingTimeInterval(.hours(2)), prefix: "old2-")
        let localTime = nsMealTime.addingTimeInterval(.minutes(-30))
        let local = nsLocal("L", at: localTime, fat: 20, protein: 20)
        let localSplit = nsSplit(of: local, prefix: "local-")
        let sharing = BaseCarbsStorage.storedDownload(nsEntry("S", fat: 20, at: localTime), id: "S")

        guard let migrated = BaseCarbsStorage.migrateOldSplits(
            [a, b, local, sharing] + old + localSplit,
            fpu: nsFPU,
            newID: { "unused" }
        ) else { return XCTFail("migrated") }

        XCTAssertEqual(nsFPUs(migrated, of: "A").count, 6)
        XCTAssertTrue(nsFPUs(migrated, of: "B").isEmpty)
        XCTAssertFalse(migrated.contains { ($0.id ?? "").hasPrefix("old") })
        XCTAssertEqual(
            Set(migrated.filter { $0.isFPU == true && $0.createdAt == localTime }.compactMap(\.id)),
            Set(localSplit.compactMap(\.id))
        )
        XCTAssertNil(BaseCarbsStorage.migrateOldSplits(migrated, fpu: nsFPU, newID: { "again" }))
    }

    /// A meal entered here with exactly its one split: the migration leaves the file alone.
    func testMigrationLeavesASplitMealAlone() {
        let local = nsLocal("L", fat: 20, protein: 20)
        XCTAssertNil(BaseCarbsStorage.migrateOldSplits([local] + nsSplit(of: local, prefix: "L-"), fpu: nsFPU, newID: { "x" }))
    }

    /// A meal entered here split under other settings than today's (other count and sizes, one set): no duplication,
    /// so the migration leaves it as it is.
    func testMigrationLeavesAMealSplitUnderOtherSettingsAlone() {
        let local = nsLocal("L", fat: 20, protein: 20)
        let otherSettings = FPUSettings(interval: 60, timeCap: 8, adjustment: 1, delay: 30)
        let split = BaseCarbsStorage.carbEquivalents(
            fat: 20, protein: 20, start: nsMealTime, createdAt: nsMealTime, fpu: otherSettings
        ) { "L-\($0)" }
        XCTAssertNotEqual(split.count, nsSplit(of: local, prefix: "x").count)
        XCTAssertNil(BaseCarbsStorage.migrateOldSplits([local] + split, fpu: nsFPU, newID: { "x" }))
    }

    /// One old split of the one download with fat at its created-at is kept as it is (only renamed as its own).
    func testMigrationAdoptsASingleOldDownloadSplit() {
        let a = BaseCarbsStorage.storedDownload(nsEntry("A", fat: 20, protein: 20), id: "A")
        let b = BaseCarbsStorage.storedDownload(nsEntry("B"), id: "B")
        let old = nsSplit(of: a, start: nsMealTime.addingTimeInterval(.minutes(1)), prefix: "old-")
        guard let migrated = BaseCarbsStorage.migrateOldSplits([a, b] + old, fpu: nsFPU, newID: { "unused" }) else {
            return XCTFail("adopted")
        }
        let own = nsFPUs(migrated, of: "A")
        XCTAssertEqual(own.compactMap(\.actualDate), old.compactMap(\.actualDate))
        XCTAssertEqual(own.map(\.carbs), old.map(\.carbs))
        XCTAssertEqual(migrated.filter { $0.isFPU == true }.count, old.count)
        XCTAssertNil(nsMerge([nsEntry("A", fat: 20, protein: 20), nsEntry("B")], into: migrated).carbs)
    }

    /// Piles are not one split; one split under any settings is.
    func testOneSplitShape() {
        let local = nsLocal("L", fat: 20, protein: 20)
        let one = nsSplit(of: local, prefix: "a-")
        let other = BaseCarbsStorage.carbEquivalents(
            fat: 20, protein: 20, start: nsMealTime, createdAt: nsMealTime,
            fpu: FPUSettings(interval: 60, timeCap: 8, adjustment: 1, delay: 30)
        ) { "b-\($0)" }
        let later = nsSplit(of: local, start: nsMealTime.addingTimeInterval(.minutes(1)), prefix: "c-")
        XCTAssertTrue(BaseCarbsStorage.isOneSplitShape(one))
        XCTAssertTrue(BaseCarbsStorage.isOneSplitShape(other))
        XCTAssertTrue(BaseCarbsStorage.isOneSplitShape([]))
        XCTAssertFalse(BaseCarbsStorage.isOneSplitShape(one + one))
        XCTAssertFalse(BaseCarbsStorage.isOneSplitShape(one + later))
    }

    /// After the migration: every download's row in its stored shape (the meal's own time, not the first poll's; the
    /// file's amounts), none for the meals entered here, and the rows of the removed copies deleted.
    func testMigratedMealRows() {
        let raw = CarbsEntry(
            id: "A", createdAt: nsMealTime, actualDate: nil,
            carbs: 25, fat: nil, protein: nil, fiber: nil, note: nil,
            enteredBy: "Mom", isFPU: nil
        )
        let local = nsLocal("U", enteredBy: CarbsEntry.remote)
        let copy = CarbsEntry(
            id: nsObjectID, createdAt: nsMealTime, actualDate: nsMealTime,
            carbs: 20, fat: 0, protein: 0, fiber: nil, note: nil,
            enteredBy: CarbsEntry.remote, isFPU: false
        )
        let fpu = nsSplit(of: nsLocal("U", fat: 20), prefix: "f-")
        let rows = BaseCarbsStorage.migratedMealRows(before: [raw, local, copy] + fpu, after: [raw, local] + fpu)
        XCTAssertEqual(rows.save.map(\.id), ["A"])
        XCTAssertEqual(rows.save.first?.actualDate, nsMealTime)
        XCTAssertEqual(rows.save.first?.carbs, 25)
        XCTAssertEqual(rows.delete, [nsObjectID])
    }

    /// A remote meal edited here (now "iAPS", new carbs) loses its copy imported back ("Nightscout operator", a
    /// Nightscout id, the old carbs).
    func testMigrationDropsAnEditedRemoteMealsCopy() {
        var edited = nsLocal("U")
        edited.carbs = 30
        let copy = CarbsEntry(
            id: nsObjectID, createdAt: nsMealTime, actualDate: nsMealTime,
            carbs: 20, fat: 0, protein: 0, fiber: nil, note: "Remote",
            enteredBy: CarbsEntry.remote, isFPU: false
        )
        guard let migrated = BaseCarbsStorage.migrateOldSplits([edited, copy], fpu: nsFPU, newID: { "x" }) else {
            return XCTFail("the copy goes")
        }
        XCTAssertEqual(migrated.compactMap(\.id), ["U"])
        XCTAssertEqual(migrated.first?.carbs, 30)
    }

    /// An edit of a download with fat, with a poll waiting behind it: one split (the edit's), and the published carbs
    /// are the file's.
    func testDownloadEditWithAConcurrentPollKeepsOneSplit() async {
        let f = mealsFixture()
        let at = Date().truncatedToSecond.addingTimeInterval(.minutes(-30))
        let downloaded = CarbsEntry(
            id: nsObjectID, createdAt: at, actualDate: nil,
            carbs: 20, fat: 20, protein: 20, fiber: nil, note: nil,
            enteredBy: "Mom", isFPU: nil
        )
        await f.carbs.storeDownloadedCarbs([downloaded])
        let edited = CarbsEntry(
            id: nsObjectID, createdAt: at, actualDate: at,
            carbs: 25, fat: 20, protein: 20, fiber: nil, note: nil,
            enteredBy: CarbsEntry.manual, isFPU: false
        )

        let editing = Task { await f.carbs.replaceMeal(createdAt: at, with: edited) }
        await f.rows.deleteArrived()
        let polling = await startWaitingMealsCall(
            { await f.carbs.storeDownloadedCarbs([downloaded]) },
            event: "save \(nsObjectID)",
            rows: f.rows
        )
        await f.rows.open()
        await editing.value
        await polling.value

        let fpu = await FPUSettings(BaseSettingsManager(storage: f.files, appCoordinator: f.coordinator).settings)
        let expected = BaseCarbsStorage.carbEquivalents(
            fat: 20, protein: 20, start: at, createdAt: at, fpu: fpu
        ) { String($0) }
        let stored = await f.stored()
        XCTAssertEqual(stored.filter { $0.isFPU == true }.count, expected.count)
        XCTAssertTrue(nsFPUs(stored, of: nsObjectID).isEmpty)
        XCTAssertEqual(stored.first { $0.id == nsObjectID }?.carbs, 25)
        XCTAssertEqual(f.coordinator.carbHistory.value.compactMap(\.id), stored.compactMap(\.id))
        await f.files.remove(f.file)
    }
}
