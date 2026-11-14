@testable import FreeAPS
import XCTest

private typealias Engine = InsulinStatsEngine

final class InsulinStatsEngineTests: XCTestCase, PumpEventRecordBuilders {
    // MARK: - Fixtures

    private static let calendar = StatsFixtures.berlin

    private var calendar: Calendar { Self.calendar }

    /// 2026-10-20
    private static let day0 = StatsFixtures.day0
    /// 2026-03-29, a 23-hour day
    private static let springForward = StatsFixtures.springForward
    /// 2026-10-25, a 25-hour day
    private static let fallBack = StatsFixtures.fallBack
    /// 2026-10-10: a week without a DST change
    private static let week = StatsFixtures.week

    private let accuracy = 1E-9

    /// The start of the day `offset` days after `start`.
    private func day(_ offset: Int, from start: Date = InsulinStatsEngineTests.day0) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    /// The start of the day `offset` days after `week`.
    private func weekDay(_ offset: Int) -> Date {
        day(offset, from: Self.week)
    }

    /// The whole calendar day starting at `start`.
    private func wholeDay(_ start: Date) -> DateInterval {
        DateInterval(start: start, end: day(1, from: start))
    }

    /// The local clock time `hh:mm` of the day starting at `start` (the first pass of a repeated hour).
    private func clock(_ hour: Int, _ minute: Int = 0, on start: Date = InsulinStatsEngineTests.day0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
    }

    private func coverage(_ start: Date, _ end: Date, source: PumpEventSource = .pump) -> CoveredInterval {
        CoveredInterval(interval: DateInterval(start: start, end: end), source: source)
    }

    /// A schedule record: (start "HH:mm", U/h) entries.
    private func schedule(_ date: Date, _ entries: [(String, Double)], source: BasalScheduleSource = .local)
        -> BasalScheduleRecordValue
    {
        BasalScheduleRecordValue(
            date: date,
            source: source,
            entries: entries.map { start, rate in
                let parts = start.split(separator: ":").compactMap { Int($0) }
                return BasalProfileEntry(start: start + ":00", minutes: parts[0] * 60 + parts[1], rate: Decimal(rate))
            }
        )
    }

    /// A flat schedule of `rate` U/h, from long before the tests' days.
    private func flat(_ rate: Double, from date: Date = InsulinStatsEngineTests.day0.addingTimeInterval(-.days(400)))
        -> BasalScheduleRecordValue
    {
        schedule(date, [("00:00", rate)])
    }

    /// One day of the engine, computed at `now` (by default long after it).
    private func dayInsulin(
        _ start: Date,
        events: [PumpEventRecord] = [],
        coverage: [CoveredInterval] = [],
        schedules: [BasalScheduleRecordValue]? = nil,
        iob: [IOBPoint] = [],
        now: Date? = nil
    ) -> DayInsulin {
        let input = InsulinInput(events: events, coverage: coverage, schedules: schedules ?? [flat(1)], iob: iob)
        return Engine.days([wholeDay(start)], input: input, now: now ?? day(10, from: start), calendar: calendar)[0]
    }

    private func segments(
        _ window: DateInterval,
        events: [PumpEventRecord] = [],
        coverage: [CoveredInterval] = [],
        schedules: [BasalScheduleRecordValue]? = nil,
        now: Date? = nil
    ) -> [DeliverySegment] {
        Engine.timeline(
            events: events,
            coverage: coverage,
            schedules: schedules ?? [flat(1)],
            window: window,
            now: now ?? window.end.addingTimeInterval(.days(1)),
            calendar: calendar
        )
    }

    private func sum(_ segments: [DeliverySegment], _ cause: DeliverySegment.Cause? = nil) -> Double {
        segments.filter { cause == nil || $0.cause == cause }.reduce(0) { $0 + $1.amount }
    }

    private func seconds(_ segments: [DeliverySegment], _ cause: DeliverySegment.Cause) -> Double {
        segments.filter { $0.cause == cause }.reduce(0) { $0 + $1.interval.duration }
    }

    // MARK: - Timeline: coverage

    func testScheduledFillOnlyInsideCoverage() {
        let day = dayInsulin(Self.day0, coverage: [coverage(clock(10), clock(14))])
        XCTAssertEqual(day.basal, 4, accuracy: accuracy)
        XCTAssertEqual(day.scheduled, 4, accuracy: accuracy)
        XCTAssertEqual(day.coveredSeconds, .hours(4), accuracy: accuracy)
        XCTAssertEqual(day.hours[9].basal, 0, accuracy: accuracy)
        XCTAssertEqual(day.hours[10].basal, 1, accuracy: accuracy)
        XCTAssertEqual(day.hours[14].basal, 0, accuracy: accuracy)
        XCTAssertEqual(day.coveredUntil, clock(14))
        XCTAssertTrue(day.hasData)
        XCTAssertFalse(day.hasDeliveries)

        let timeline = segments(wholeDay(Self.day0), coverage: [coverage(clock(10), clock(14))])
        XCTAssertEqual(timeline.first?.interval.start, clock(10))
        XCTAssertEqual(timeline.last?.interval.end, clock(14))
        XCTAssertTrue(timeline.allSatisfy { $0.cause == .scheduled && $0.isCovered })
    }

    func testTempsAndBolusesOutsideCoverageStillCount() {
        let day = dayInsulin(
            Self.day0,
            events: [temp(clock(16), rate: 2, minutes: 30.1), bolus(clock(18), 3), bolus(clock(19), 0.4, smb: true)],
            coverage: [coverage(clock(10), clock(14))]
        )
        // 4 U of schedule in coverage, 2 U/h for 30 min outside it
        XCTAssertEqual(day.basal, 5, accuracy: accuracy)
        XCTAssertEqual(day.bolus, 3, accuracy: accuracy)
        XCTAssertEqual(day.smb, 0.4, accuracy: accuracy)
        XCTAssertEqual(day.scheduled, 4, accuracy: accuracy)
        XCTAssertEqual(day.coveredSeconds, .hours(4), accuracy: accuracy)
        XCTAssertEqual(day.hours[16].basal, 1, accuracy: accuracy)
        XCTAssertEqual(day.hours[16].coveredSeconds, 0, accuracy: accuracy)
        XCTAssertEqual(day.hours[18].bolus, 3, accuracy: accuracy)
        XCTAssertTrue(day.hasDeliveries)
    }

    func testNoCoverageAndNoDeliveriesIsNoData() {
        let day = dayInsulin(Self.day0)
        XCTAssertFalse(day.hasData)
        XCTAssertEqual(day.basal, 0)
        XCTAssertNil(day.coveredUntil)
        // External Insulin alone: boluses, no basal
        let pen = dayInsulin(Self.day0, events: [bolus(clock(8), 6, external: true)])
        XCTAssertTrue(pen.hasData)
        XCTAssertEqual(pen.bolus, 6, accuracy: accuracy)
        XCTAssertEqual(pen.basal, 0)
        XCTAssertEqual(pen.coveredSeconds, 0)
    }

    /// A past day keeps its boluses that aren't SMBs (External Insulin too), oldest -> newest, for Good & bad days; its
    /// SMBs only in its hours and totals, as before. Today keeps all of them.
    func testAPastDayKeepsItsBolusesButNotItsSMBs() {
        let events = [
            bolus(clock(7, 40), 4),
            bolus(clock(8), 0.3, smb: true),
            bolus(clock(8, 5), 0.2, smb: true),
            bolus(clock(12), 2, external: true),
            bolus(clock(19), 0.4, smb: true)
        ]
        let past = dayInsulin(Self.day0, events: events, coverage: [coverage(clock(0), day(1))])
        XCTAssertFalse(past.isToday)
        XCTAssertEqual(past.boluses.map(\.date), [clock(7, 40), clock(12)])
        XCTAssertEqual(past.boluses.map(\.units), [4, 2])
        XCTAssertEqual(past.boluses.map(\.isExternal), [false, true])
        XCTAssertFalse(past.boluses.contains(where: \.isSMB))
        XCTAssertEqual(past.smb, 0.9, accuracy: accuracy)
        XCTAssertEqual(past.bolus, 6, accuracy: accuracy)
        XCTAssertEqual(past.hours[8].smb, 0.5, accuracy: accuracy)
        XCTAssertEqual(past.hours[7].bolus, 4, accuracy: accuracy)

        let today = dayInsulin(Self.day0, events: events, coverage: [coverage(clock(0), clock(20))], now: clock(20))
        XCTAssertTrue(today.isToday)
        XCTAssertEqual(today.boluses.map(\.isSMB), [false, true, true, false, true])
    }

    func testCoverageEdges() {
        // the fill starts and ends exactly at the coverage edges; touching rows are one
        let rows = [coverage(clock(10), clock(11)), coverage(clock(11), clock(12)), coverage(clock(13), clock(13, 30))]
        let timeline = segments(wholeDay(Self.day0), coverage: rows)
        XCTAssertEqual(timeline.first?.interval.start, clock(10))
        XCTAssertEqual(seconds(timeline, .scheduled), .hours(2.5), accuracy: accuracy)
        XCTAssertFalse(timeline.contains { $0.interval.start < clock(13) && clock(12) < $0.interval.end })
        // Nightscout coverage fills too
        let ns = dayInsulin(Self.day0, coverage: [coverage(clock(0), clock(6), source: .nightscout)])
        XCTAssertEqual(ns.basal, 6, accuracy: accuracy)
        // a coverage end at now: nothing after it, and today's coverage is never stretched to now
        let today = dayInsulin(Self.day0, coverage: [coverage(clock(0), clock(9))], now: clock(9, 30))
        XCTAssertEqual(today.coveredSeconds, .hours(9), accuracy: accuracy)
        XCTAssertEqual(today.coveredUntil, clock(9))
        XCTAssertTrue(today.isToday)
        // coverage past now is cut at now
        let running = dayInsulin(Self.day0, coverage: [coverage(clock(0), clock(12))], now: clock(9, 30))
        XCTAssertEqual(running.coveredSeconds, .hours(9.5), accuracy: accuracy)
    }

    func testWithoutAScheduleNothingIsCovered() {
        let day = dayInsulin(
            Self.day0,
            events: [temp(clock(10), rate: 2, minutes: 60.1)],
            coverage: [coverage(clock(0), clock(23))],
            schedules: []
        )
        XCTAssertEqual(day.coveredSeconds, 0)
        XCTAssertEqual(day.basal, 2, accuracy: accuracy)
    }

    // MARK: - Timeline: sources

    func testNightscoutEventsWithAPumpTwinOrInsidePumpCoverageAreIgnored() {
        let pumpCoverage = coverage(clock(10), clock(12))
        let events = [
            bolus(clock(10, 30), 3),
            // the twin of the pump bolus
            bolus(clock(10, 30), 3, source: .nightscout),
            // inside the pump coverage
            bolus(clock(11), 2, source: .nightscout),
            // at the coverage start: inside
            bolus(clock(10), 1.5, source: .nightscout),
            // at its end: inside too (the local time is closed: `PumpSessionRules.isLocal`)
            bolus(clock(12), 0.7, source: .nightscout),
            // after it: counted
            bolus(clock(12, 1), 0.4, source: .nightscout),
            // a Nightscout temp outside the pump coverage: its duration as stored (no 0.1)
            temp(clock(20), rate: 1.2, minutes: 30, source: .nightscout),
            // a Nightscout temp inside it: dropped
            temp(clock(11, 30), rate: 5, minutes: 30, source: .nightscout)
        ]
        let usable = Engine.usableEvents(events, coverage: [pumpCoverage])
        XCTAssertEqual(usable.map(\.date), [clock(10, 30), clock(12, 1), clock(20)])
        XCTAssertEqual(usable.first?.source, .pump)

        let day = dayInsulin(Self.day0, events: events, coverage: [pumpCoverage])
        XCTAssertEqual(day.bolus, 3.4, accuracy: accuracy)
        // 2 U of schedule, 1.2 U/h for 30 min
        XCTAssertEqual(day.basal, 2.6, accuracy: accuracy)
        XCTAssertEqual(day.hours[20].basal, 0.6, accuracy: accuracy)
    }

    func testNightscoutTwinOfAPumpEventOutsideCoverageIsIgnored() {
        // a pump catch-up bolus outside any coverage and its Nightscout upload
        let events = [bolus(clock(22), 2), bolus(clock(22), 2, source: .nightscout)]
        let day = dayInsulin(Self.day0, events: events)
        XCTAssertEqual(day.bolus, 2, accuracy: accuracy)
        XCTAssertEqual(Engine.usableEvents(events, coverage: []).map(\.source), [.pump])
    }

    func testNightscoutCoverageDoesNotHideNightscoutEvents() {
        let events = [bolus(clock(8), 4, source: .nightscout)]
        let usable = Engine.usableEvents(events, coverage: [coverage(clock(0), clock(23), source: .nightscout)])
        XCTAssertEqual(usable.count, 1)
    }

    // MARK: - Timeline: temps

    func testTempClippedByTheNextTemp() {
        let events = [temp(clock(10), rate: 2, minutes: 30.1), temp(clock(10, 10), rate: 0, minutes: 30.1)]
        let timeline = segments(wholeDay(Self.day0), events: events, coverage: [coverage(clock(10), clock(11))])
        XCTAssertEqual(sum(timeline, .temp), 2.0 / 6, accuracy: accuracy)
        XCTAssertEqual(seconds(timeline, .temp), .minutes(40), accuracy: accuracy)
        XCTAssertEqual(sum(timeline, .scheduled), 1.0 / 3, accuracy: accuracy)
        XCTAssertEqual(timeline.filter { $0.cause == .scheduled }.first?.interval.start, clock(10, 40))

        let day = dayInsulin(Self.day0, events: events, coverage: [coverage(clock(10), clock(11))])
        XCTAssertEqual(day.basal, 2.0 / 3, accuracy: accuracy)
        // a zero temp is zero basal
        XCTAssertEqual(day.zeroBasalSeconds, .minutes(30), accuracy: accuracy)
        XCTAssertEqual(day.scheduled, 1, accuracy: accuracy)
    }

    func testFinalDeliveredUnitsCountInFullWhenTheNextTempStartsAtItsActualEnd() {
        // a final of 20 min (stored 20.1), 1.5 U/h nominal, the pump reported 0.45 U; the next starts 20.1 min later
        let first = temp(clock(10), rate: 1.5, minutes: 20.1, units: 0.45)
        let next = temp(clock(10).addingTimeInterval(.minutes(20.1)), rate: 1, minutes: 30.1)
        let timeline = segments(wholeDay(Self.day0), events: [first, next], coverage: [coverage(clock(10), clock(10, 30))])
        let firstSegments = timeline.filter { $0.cause == .temp && $0.interval.start < clock(10, 20) }
        XCTAssertEqual(sum(firstSegments), 0.45, accuracy: accuracy)
        XCTAssertEqual(firstSegments.last?.interval.end, clock(10, 20))
        // the 6 s between its nominal end and the next temp: the schedule
        XCTAssertEqual(seconds(timeline, .scheduled), 6, accuracy: 1E-6)
    }

    func testFinalClippedByTheNextTempStillCountsInFull() {
        let first = temp(clock(10), rate: 1.5, minutes: 30.1, units: 0.7)
        let next = temp(clock(10, 10), rate: 1, minutes: 30.1)
        let timeline = segments(wholeDay(Self.day0), events: [first, next], coverage: [coverage(clock(10), clock(11))])
        XCTAssertEqual(sum(timeline.filter { $0.interval.start < clock(10, 10) }), 0.7, accuracy: accuracy)
    }

    func testSuspensionClipsAFinalTempAndScalesItsUnits() {
        let events = [temp(clock(10), rate: 1.2, minutes: 30.1, units: 0.6), suspend(clock(10, 15)), resume(clock(10, 45))]
        let timeline = segments(wholeDay(Self.day0), events: events, coverage: [coverage(clock(10), clock(11))])
        XCTAssertEqual(sum(timeline, .temp), 0.3, accuracy: accuracy)
        XCTAssertEqual(seconds(timeline, .suspended), .minutes(30), accuracy: accuracy)
        XCTAssertEqual(sum(timeline, .scheduled), 0.25, accuracy: accuracy)

        let day = dayInsulin(Self.day0, events: events, coverage: [coverage(clock(10), clock(11))])
        XCTAssertEqual(day.basal, 0.55, accuracy: accuracy)
        XCTAssertEqual(day.zeroBasalSeconds, .minutes(30), accuracy: accuracy)
    }

    func testMutableTempCountsItsRateUpToNow() {
        let now = clock(10, 12)
        let timeline = segments(
            wholeDay(Self.day0),
            events: [temp(clock(10), rate: 3, minutes: 30.1)],
            coverage: [coverage(clock(9), now)],
            now: now
        )
        XCTAssertEqual(sum(timeline, .temp), 3.0 * 12 / 60, accuracy: accuracy)
        XCTAssertEqual(timeline.last?.interval.end, now)
    }

    // MARK: - Timeline: suspensions

    func testSuspensionWinsOverATempRunningThroughIt() {
        let events = [temp(clock(10), rate: 3, minutes: 60.1), suspend(clock(10, 20)), resume(clock(10, 30))]
        let timeline = segments(wholeDay(Self.day0), events: events, coverage: [coverage(clock(10), clock(11))])
        XCTAssertEqual(sum(timeline, .temp), 1, accuracy: accuracy)
        XCTAssertEqual(seconds(timeline, .suspended), .minutes(10), accuracy: accuracy)
        // the temp doesn't come back after the resume
        XCTAssertEqual(sum(timeline, .scheduled), 0.5, accuracy: accuracy)
        XCTAssertEqual(seconds(timeline, .temp), .minutes(20), accuracy: accuracy)
    }

    func testSuspensionEndsAtTheResumeOrTheNextPumpDelivery() {
        let rows = [coverage(clock(9), clock(15))]
        let events = [
            // ended by an SMB
            suspend(clock(9, 10)), bolus(clock(9, 30), 0.3, smb: true),
            // ended by a temp start
            suspend(clock(10)), temp(clock(10, 20), rate: 1, minutes: 10.1),
            // ended by the resume
            suspend(clock(11)), resume(clock(11, 5)),
            // no resume: up to the end of the coverage (and on)
            suspend(clock(14, 30))
        ]
        let timeline = segments(wholeDay(Self.day0), events: events, coverage: rows)
        let suspended = timeline.filter { $0.cause == .suspended && $0.isCovered }.map(\.interval)
        XCTAssertEqual(suspended.map(\.start), [clock(9, 10), clock(10), clock(11), clock(14, 30)])
        XCTAssertEqual(suspended.map(\.end), [clock(9, 30), clock(10, 20), clock(11, 5), clock(15)])
    }

    func testSuspensionRunsOnThroughACoverageGap() {
        // suspended at 10:00, the app dead 10:05-10:40, resumed at 11:00: still suspended after the gap
        let rows = [coverage(clock(9), clock(10, 5)), coverage(clock(10, 40), clock(12))]
        let events = [suspend(clock(10)), resume(clock(11))]
        let timeline = segments(wholeDay(Self.day0), events: events, coverage: rows)
        let suspended = timeline.filter { $0.cause == .suspended }
        XCTAssertEqual(suspended.first?.interval.start, clock(10))
        XCTAssertEqual(suspended.last?.interval.end, clock(11))
        XCTAssertFalse(
            timeline
                .contains { $0.cause == .scheduled && $0.interval.start < clock(11) && clock(10) < $0.interval.end }
        )

        let day = dayInsulin(Self.day0, events: events, coverage: rows)
        // zero basal only where covered: 10:00-10:05 and 10:40-11:00
        XCTAssertEqual(day.zeroBasalSeconds, .minutes(25), accuracy: accuracy)
        // 09:00-10:00 and 11:00-12:00 at 1 U/h
        XCTAssertEqual(day.basal, 2, accuracy: accuracy)
        XCTAssertEqual(day.coveredSeconds, .minutes(65 + 80), accuracy: accuracy)

        // a pod change in the gap: the new pod's first temp ends it
        let pod = dayInsulin(
            Self.day0,
            events: [suspend(clock(10)), temp(clock(10, 45), rate: 2, minutes: 30.1)],
            coverage: rows
        )
        XCTAssertEqual(pod.zeroBasalSeconds, .minutes(10), accuracy: accuracy)
        XCTAssertEqual(pod.basal, 1 + 1 + 0.75, accuracy: accuracy)
    }

    func testSuspensionOutsideCoverageIsNotZeroBasal() {
        let events = [suspend(clock(7)), temp(clock(8, 10), rate: 2, minutes: 60.1)]
        let rows = [coverage(clock(7, 30), clock(9))]
        let timeline = segments(wholeDay(Self.day0), events: events, coverage: rows)
        XCTAssertEqual(timeline.first?.interval, DateInterval(start: clock(7), end: clock(7, 30)))
        XCTAssertEqual(timeline.first?.cause, .suspended)
        XCTAssertFalse(timeline.first?.isCovered ?? true)
        // covered from 07:30 on, still suspended until the temp at 08:10
        let day = dayInsulin(Self.day0, events: events, coverage: rows)
        XCTAssertEqual(day.zeroBasalSeconds, .minutes(40), accuracy: accuracy)
    }

    func testExternalInsulinDoesNotEndASuspension() {
        let events = [suspend(clock(10)), bolus(clock(10, 10), 2, external: true), resume(clock(10, 40))]
        let day = dayInsulin(Self.day0, events: events, coverage: [coverage(clock(10), clock(11))])
        XCTAssertEqual(day.zeroBasalSeconds, .minutes(40), accuracy: accuracy)
        XCTAssertEqual(day.bolus, 2, accuracy: accuracy)
        XCTAssertEqual(day.basal, 20.0 / 60, accuracy: accuracy)
        // a pump bolus does
        let pump = dayInsulin(
            Self.day0,
            events: [suspend(clock(10)), bolus(clock(10, 10), 2), resume(clock(10, 40))],
            coverage: [coverage(clock(10), clock(11))]
        )
        XCTAssertEqual(pump.zeroBasalSeconds, .minutes(10), accuracy: accuracy)
    }

    func testScheduleEntriesOffTheHourChangeTheRateAtTheirClockTime() {
        let schedules = [schedule(Self.day0.addingTimeInterval(-.days(10)), [("00:00", 1), ("03:30", 0), ("04:15", 1)])]
        let day = dayInsulin(Self.day0, coverage: [coverage(clock(0), clock(6))], schedules: schedules)
        XCTAssertEqual(day.zeroBasalSeconds, .minutes(45), accuracy: accuracy)
        XCTAssertEqual(day.hours[3].zeroBasalSeconds, .minutes(30), accuracy: accuracy)
        XCTAssertEqual(day.hours[4].zeroBasalSeconds, .minutes(15), accuracy: accuracy)
        XCTAssertEqual(day.basal, 6 - 0.75, accuracy: accuracy)
    }

    func testZeroScheduleEntryIsZeroBasal() {
        let schedules = [schedule(Self.day0.addingTimeInterval(-.days(10)), [("00:00", 1), ("03:00", 0), ("04:00", 1)])]
        let day = dayInsulin(Self.day0, coverage: [coverage(clock(0), clock(6))], schedules: schedules)
        XCTAssertEqual(day.zeroBasalSeconds, .hours(1), accuracy: accuracy)
        XCTAssertEqual(day.basal, 5, accuracy: accuracy)
        XCTAssertEqual(day.hours[3].zeroBasalSeconds, .hours(1), accuracy: accuracy)
    }

    // MARK: - Timeline: running into the window

    func testRunningInStateFromThirtyHoursBefore() {
        let start = Self.day0
        // a suspension 30 h before the window, resumed at 03:00 of its first day
        let suspended = dayInsulin(
            start,
            events: [suspend(start.addingTimeInterval(-.hours(30))), resume(clock(3))],
            coverage: [coverage(start.addingTimeInterval(-.hours(31)), clock(12))]
        )
        XCTAssertEqual(suspended.zeroBasalSeconds, .hours(3), accuracy: accuracy)
        XCTAssertEqual(suspended.basal, 9, accuracy: accuracy)

        // a 32-hour temp that started 30 h before: it runs until 02:00
        let long = dayInsulin(
            start,
            events: [temp(start.addingTimeInterval(-.hours(30)), rate: 2, minutes: 32 * 60 + 0.1)],
            coverage: [coverage(start, clock(12))]
        )
        XCTAssertEqual(long.basal, 2 * 2 + 10, accuracy: accuracy)
        XCTAssertEqual(long.hours[1].basal, 2, accuracy: accuracy)
        XCTAssertEqual(long.hours[2].basal, 1, accuracy: accuracy)
    }

    // MARK: - Timeline: splits

    func testMidnightAndHourSplitsAreAdditive() {
        let events = [
            temp(clock(23, 40), rate: 1.5, minutes: 40.1),
            temp(clock(10, 50), rate: 0.6, minutes: 20.1),
            bolus(clock(12, 59), 1)
        ]
        let rows = [coverage(clock(6), day(1).addingTimeInterval(.hours(6)))]
        let input = InsulinInput(events: events, coverage: rows, schedules: [flat(0.9)])
        let days = Engine.days([wholeDay(Self.day0), wholeDay(day(1))], input: input, now: day(5), calendar: calendar)
        for day in days {
            XCTAssertEqual(day.hours.reduce(0) { $0 + $1.basal }, day.basal, accuracy: 1E-9)
            XCTAssertEqual(day.hours.reduce(0) { $0 + $1.coveredSeconds }, day.coveredSeconds, accuracy: 1E-6)
            XCTAssertEqual(day.hours.reduce(0) { $0 + $1.scheduled }, day.scheduled, accuracy: 1E-9)
        }
        XCTAssertEqual(days[0].hours[23].basal, 0.9 * 40 / 60 + 1.5 * 20 / 60, accuracy: accuracy)
        XCTAssertEqual(days[1].hours[0].basal, 1.5 * 20 / 60 + 0.9 * 40 / 60, accuracy: accuracy)
        XCTAssertEqual(days[0].hours[10].basal, 0.9 * 50 / 60 + 0.6 * 10 / 60, accuracy: accuracy)
        XCTAssertEqual(days[0].hours[11].basal, 0.6 * 10 / 60 + 0.9 * 50 / 60, accuracy: accuracy)
        XCTAssertEqual(days[0].hours[12].bolus, 1, accuracy: accuracy)

        let timeline = segments(DateInterval(start: Self.day0, end: day(2)), events: events, coverage: rows, schedules: [
            flat(0.9)
        ])
        XCTAssertTrue(timeline.contains { $0.interval.end == day(1) })
        XCTAssertTrue(timeline.contains { $0.interval.start == day(1) && $0.cause == .temp })
        XCTAssertTrue(timeline.contains { $0.interval.start == clock(11) && $0.cause == .temp })
        // back to back, no overlap
        for (a, b) in zip(timeline, timeline.dropFirst()) {
            XCTAssertTrue(a.interval.end <= b.interval.start)
        }
    }

    // MARK: - DST and the 06:00 step

    func testSpringForwardDayWithAProfileStepAt0600() {
        let start = Self.springForward
        let schedules = [schedule(start.addingTimeInterval(-.days(30)), [("00:00", 0.5), ("06:00", 1)])]
        let whole = wholeDay(start)
        XCTAssertEqual(whole.duration, .hours(23))
        let day = dayInsulin(start, coverage: [coverage(start, whole.end)], schedules: schedules)
        // 00:00-06:00 is 5 real hours at 0.5, 06:00-24:00 18 hours at 1
        XCTAssertEqual(day.basal, 2.5 + 18, accuracy: accuracy)
        XCTAssertEqual(day.coveredSeconds, .hours(23), accuracy: accuracy)
        XCTAssertEqual(day.coverageFraction, 1, accuracy: accuracy)
        XCTAssertEqual(day.hours[2].coveredSeconds, 0)
        XCTAssertEqual(day.hours[5].basal, 0.5, accuracy: accuracy)
        XCTAssertEqual(day.hours[6].basal, 1, accuracy: accuracy)

        let step = start.addingTimeInterval(.hours(5))
        XCTAssertEqual(step, clock(6, on: start))
        let timeline = segments(whole, coverage: [coverage(start, whole.end)], schedules: schedules)
        XCTAssertEqual(timeline.first { $0.interval.end == step }?.rate, 0.5)
        XCTAssertEqual(timeline.first { $0.interval.start == step }?.rate, 1)
    }

    func testFallBackDayWithAProfileStepAt0600() {
        let start = Self.fallBack
        let schedules = [
            schedule(start.addingTimeInterval(-.days(30)), [("00:00", 0.5), ("02:00", 0.8), ("03:00", 0.5), ("06:00", 1)])
        ]
        let whole = wholeDay(start)
        XCTAssertEqual(whole.duration, .hours(25))
        let day = dayInsulin(start, coverage: [coverage(start, whole.end)], schedules: schedules)
        // 00-02 at 0.5, the repeated 02:00 hour at 0.8 twice, 03-06 at 0.5, 06-24 at 1
        XCTAssertEqual(day.basal, 1 + 1.6 + 1.5 + 18, accuracy: accuracy)
        XCTAssertEqual(day.hours[2].coveredSeconds, .hours(2), accuracy: accuracy)
        XCTAssertEqual(day.hours[2].basal, 1.6, accuracy: accuracy)
        XCTAssertEqual(day.hours[3].basal, 0.5, accuracy: accuracy)

        let step = start.addingTimeInterval(.hours(7))
        XCTAssertEqual(step, clock(6, on: start))
        let timeline = segments(whole, coverage: [coverage(start, whole.end)], schedules: schedules)
        XCTAssertEqual(timeline.first { $0.interval.end == step }?.rate, 0.5)
        XCTAssertEqual(timeline.first { $0.interval.start == step }?.rate, 1)
        // both passes of 02:00 start at the 0.8 entry: real 00:00 and 01:00 UTC
        XCTAssertEqual(timeline.first { $0.interval.start == start.addingTimeInterval(.hours(2)) }?.rate, 0.8)
        XCTAssertEqual(timeline.first { $0.interval.start == start.addingTimeInterval(.hours(3)) }?.rate, 0.8)
        XCTAssertEqual(timeline.first { $0.interval.start == start.addingTimeInterval(.hours(4)) }?.rate, 0.5)
    }

    func testDSTDaysWithAScheduleChangeOnTheDay() {
        for start in [Self.springForward, Self.fallBack] {
            let edit = clock(14, on: start)
            let schedules = [
                schedule(start.addingTimeInterval(-.days(30)), [("00:00", 0.5), ("06:00", 1)]),
                schedule(edit, [("00:00", 2)])
            ]
            let whole = wholeDay(start)
            let day = dayInsulin(start, coverage: [coverage(start, whole.end)], schedules: schedules)
            let before = edit.timeIntervalSince(clock(6, on: start)) / .hours(1)
            let early = clock(6, on: start).timeIntervalSince(start) / .hours(1)
            XCTAssertEqual(day.basal, early * 0.5 + before * 1 + 10 * 2, accuracy: accuracy)
            XCTAssertEqual(day.hours[13].basal, 1, accuracy: accuracy)
            XCTAssertEqual(day.hours[14].basal, 2, accuracy: accuracy)
            XCTAssertFalse(day.profileAssumed)
        }
    }

    // MARK: - Schedule history

    func testAnEditAt1400ChangesTheRateExactlyThen() {
        let edit = clock(14, 7)
        let schedules = [flat(1), schedule(edit, [("00:00", 2)])]
        let rows = [coverage(day(-1), day(1))]
        let input = InsulinInput(coverage: rows, schedules: schedules)
        let days = Engine.days([wholeDay(day(-1)), wholeDay(Self.day0)], input: input, now: day(3), calendar: calendar)
        // the day before keeps the old schedule
        XCTAssertEqual(days[0].basal, 24, accuracy: accuracy)
        XCTAssertEqual(days[0].scheduled, 24, accuracy: accuracy)
        XCTAssertEqual(days[1].basal, 14 + 7.0 / 60 + 2 * (10 - 7.0 / 60), accuracy: accuracy)
        XCTAssertEqual(days[1].hours[14].basal, 7.0 / 60 + 2 * 53 / 60, accuracy: accuracy)

        let timeline = segments(wholeDay(Self.day0), coverage: rows, schedules: schedules)
        XCTAssertEqual(timeline.first { $0.interval.end == edit }?.rate, 1)
        XCTAssertEqual(timeline.first { $0.interval.start == edit }?.rate, 2)
    }

    func testTimeBeforeTheOldestRecordUsesItAndIsFlagged() {
        let oldest = clock(12)
        let schedules = [schedule(oldest, [("00:00", 0.5), ("12:00", 1.5)])]
        let rows = [coverage(day(-1), day(2))]
        let input = InsulinInput(coverage: rows, schedules: schedules)
        let days = Engine.days(
            [wholeDay(day(-1)), wholeDay(Self.day0), wholeDay(day(1))],
            input: input,
            now: day(4),
            calendar: calendar
        )
        XCTAssertEqual(days[0].basal, 12 * 0.5 + 12 * 1.5, accuracy: accuracy)
        XCTAssertEqual(days[0].profileAssumedBefore, oldest)
        XCTAssertEqual(days[1].profileAssumedBefore, oldest)
        XCTAssertNil(days[2].profileAssumedBefore)
        XCTAssertFalse(days[2].profileAssumed)
        // an uncovered day before it isn't flagged
        let empty = dayInsulin(day(-1), events: [bolus(clock(8, on: day(-1)), 2)], schedules: schedules)
        XCTAssertFalse(empty.profileAssumed)
    }

    func testBasalVsScheduledOverTwoSchedules() {
        let second = day(-1)
        let schedules = [flat(1), schedule(second, [("00:00", 2)])]
        let events = [temp(clock(12, on: day(-2)), rate: 0, minutes: 6 * 60 + 0.1)]
        let input = InsulinInput(events: events, coverage: [coverage(day(-2), clock(9))], schedules: schedules)
        let now = clock(9)
        let days = Engine.days(
            [wholeDay(day(-2)), wholeDay(day(-1)), wholeDay(Self.day0)],
            input: input,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(days[0].basal, 18, accuracy: accuracy)
        XCTAssertEqual(days[0].scheduled, 24, accuracy: accuracy)
        XCTAssertEqual(days[1].basal, 48, accuracy: accuracy)
        XCTAssertEqual(days[1].scheduled, 48, accuracy: accuracy)
        let summary = Engine.summary(days, period: nil)
        XCTAssertEqual(summary.headlineDays, 2)
        XCTAssertEqual(summary.basalVsScheduled!, 66.0 / 72, accuracy: accuracy)
        XCTAssertEqual(summary.basalVsScheduledPercent, 92)
        XCTAssertEqual(summary.scheduledPerDay!, 36, accuracy: accuracy)
        XCTAssertEqual(summary.zeroBasalSecondsPerDay!, .hours(3), accuracy: accuracy)
        XCTAssertEqual(summary.profileAssumedBefore, nil)
    }

    // MARK: - IOB

    func testIOBSpansWithOneMinuteLoopsDuplicatesAndAGap() {
        let start = clock(10)
        var points = (0 ..< 60).map { IOBPoint(time: start.addingTimeInterval(.minutes($0)), iob: -0.2) }
        // a failed loop's row next to the next loop's
        points.append(IOBPoint(time: start.addingTimeInterval(.minutes(30) + 4), iob: 1))
        // after a 20-minute gap
        points.append(IOBPoint(time: start.addingTimeInterval(.minutes(79)), iob: 0.5))
        let spans = Engine.iobSpans(points, now: clock(20))
        XCTAssertEqual(spans.count, 61)
        XCTAssertEqual(spans[58].interval.duration, .minutes(1), accuracy: accuracy)
        // the last 1-minute row before the gap: 5 min
        XCTAssertEqual(spans[59].interval.duration, .minutes(5), accuracy: accuracy)
        XCTAssertEqual(spans[60].interval.duration, .minutes(5), accuracy: accuracy)
        XCTAssertEqual(spans.filter(\.isNegative).reduce(0) { $0 + $1.interval.duration }, .minutes(64), accuracy: accuracy)

        // 7.5 minutes is still the next row; the newest row isn't counted past now
        let wide = Engine.iobSpans(
            [IOBPoint(time: start, iob: -1), IOBPoint(time: start.addingTimeInterval(450), iob: -1)],
            now: start.addingTimeInterval(450 + 120)
        )
        XCTAssertEqual(wide.map(\.interval.duration), [450, 120])

        let day = dayInsulin(Self.day0, iob: points, now: clock(20))
        XCTAssertEqual(day.negativeIOBSeconds, .minutes(64), accuracy: accuracy)
        XCTAssertEqual(day.iobSeconds, .minutes(64 + 5), accuracy: accuracy)
        XCTAssertEqual(day.hours[10].negativeIOBSeconds, .minutes(60), accuracy: accuracy)
        XCTAssertEqual(day.hours[11].negativeIOBSeconds, .minutes(4), accuracy: accuracy)
    }

    func testIOBSpanSplitAtMidnight() {
        let late = clock(23, 58)
        let input = InsulinInput(iob: [IOBPoint(time: late, iob: -1)])
        let days = Engine.days([wholeDay(Self.day0), wholeDay(day(1))], input: input, now: day(3), calendar: calendar)
        XCTAssertEqual(days[0].negativeIOBSeconds, .minutes(2), accuracy: accuracy)
        XCTAssertEqual(days[1].negativeIOBSeconds, .minutes(3), accuracy: accuracy)
        XCTAssertEqual(days[1].hours[0].negativeIOBSeconds, .minutes(3), accuracy: accuracy)
    }

    // MARK: - IOB cards

    /// IOB rows every 5 minutes from `start`, one value each.
    private func iobRows(_ start: Date, _ values: [Double]) -> [IOBPoint] {
        values.enumerated().map { IOBPoint(time: start.addingTimeInterval(.minutes(5 * $0.offset)), iob: $0.element) }
    }

    /// The 15-minute means: each bin the IOB over the time its rows stand for, a row across a quarter hour split there;
    /// nil without IOB time. The lowest below zero, and the IOB × time below zero.
    func testIOBBinsAndLowest() {
        var points = iobRows(clock(10), [1, 2, 3, -1, -1, -1.5, 0.5])
        // 11:12 to 11:17 at 2, then 0 for 5 minutes (the newest row)
        points += [IOBPoint(time: clock(11, 12), iob: 2), IOBPoint(time: clock(11, 17), iob: 0)]
        let day = dayInsulin(Self.day0, iob: points, now: clock(20))
        let bins = day.iob.bins
        XCTAssertEqual(bins.count, 96)
        XCTAssertEqual(bins[40]!, 2, accuracy: accuracy)
        XCTAssertEqual(bins[41]!, -3.5 / 3, accuracy: accuracy)
        // 10:30's row alone: 5 minutes
        XCTAssertEqual(bins[42]!, 0.5, accuracy: accuracy)
        XCTAssertEqual(bins[44]!, 2, accuracy: accuracy)
        XCTAssertEqual(bins[45]!, 4.0 / 7, accuracy: accuracy)
        XCTAssertEqual(bins.compactMap { $0 }.count, 5)
        XCTAssertNil(bins[39])
        XCTAssertNil(bins[43])

        XCTAssertEqual(day.iob.lowest, DayIOB.Lowest(iob: -1.5, at: clock(10, 25)))
        XCTAssertEqual(day.iob.negativeArea, -3.5 * 300, accuracy: accuracy)
        XCTAssertEqual(day.negativeIOBSeconds, .minutes(15), accuracy: accuracy)
        // the first of equals
        let equal = dayInsulin(Self.day0, iob: iobRows(clock(10), [-1, 1, -1, 1]), now: clock(20))
        XCTAssertEqual(equal.iob.lowest, DayIOB.Lowest(iob: -1, at: clock(10)))

        // no rows: no bins, no lowest
        let empty = dayInsulin(Self.day0)
        XCTAssertEqual(empty.iob, .empty)
        XCTAssertNil(empty.iob.lowest)
    }

    /// The lowest row at 23:58 runs over midnight: both days' lowest keep its own time. The same days read one by one are
    /// the same.
    func testLowestRowOverMidnight() {
        let points = [
            IOBPoint(time: clock(23, 50), iob: -0.3),
            IOBPoint(time: clock(23, 55), iob: -0.3),
            IOBPoint(time: clock(23, 58), iob: -1),
            IOBPoint(time: clock(0, 3, on: day(1)), iob: -0.3),
            IOBPoint(time: clock(0, 8, on: day(1)), iob: 0.5)
        ]
        let rows = [coverage(Self.day0, day(2))]
        let input = InsulinInput(coverage: rows, schedules: [flat(1)], iob: points)
        let days = Engine.days([wholeDay(Self.day0), wholeDay(day(1))], input: input, now: day(3), calendar: calendar)
        XCTAssertEqual(days[0].iob.lowest, DayIOB.Lowest(iob: -1, at: clock(23, 58)))
        XCTAssertEqual(days[1].iob.lowest, DayIOB.Lowest(iob: -1, at: clock(23, 58)))
        // read one by one (the service's runs of days): the same days
        let alone = [wholeDay(Self.day0), wholeDay(day(1))].map {
            Engine.days([$0], input: input, now: day(3), calendar: calendar)[0]
        }
        XCTAssertEqual(alone.map(\.iob), days.map(\.iob))
        let stats = Engine.negativeIOB(days)
        XCTAssertEqual(stats.lowest, -1)
        XCTAssertEqual(stats.lowestAt, clock(23, 58))
        XCTAssertEqual(stats.lowestDay, 0)
        // 23 minutes of rows over two days: the rows cover little
        XCTAssertTrue(stats.isIOBLimited)
    }

    /// The Negative IOB card over the headline days: per day and share of the IOB time, the mean depth, the lowest, the
    /// time by hour (per day of IOB time); today and a day under half covered left out.
    func testNegativeIOBSummary() {
        var points: [IOBPoint] = []
        var rows: [CoveredInterval] = []
        // three days covered with rows all day: 03:00–03:30 at -0.4, 03:00–03:20 with -1.0 at 03:10, 05:00–05:10 at -0.2
        let negative: [Int: (start: Date, values: [Double])] = [
            0: (clock(3, on: weekDay(0)), [-0.4, -0.4, -0.4, -0.4, -0.4, -0.4]),
            1: (clock(3, on: weekDay(1)), [-0.6, -0.6, -1.0, -0.6]),
            2: (clock(5, on: weekDay(2)), [-0.2, -0.2])
        ]
        let now = clock(12, on: weekDay(3))
        for offset in 0 ... 3 {
            rows.append(coverage(weekDay(offset), Swift.min(weekDay(offset + 1), now)))
            var values = [Double](repeating: 1, count: 288)
            if let stretch = negative[offset] {
                let first = Int(stretch.start.timeIntervalSince(weekDay(offset)) / .minutes(5))
                values.replaceSubrange(first ..< first + stretch.values.count, with: stretch.values)
            }
            points += iobRows(weekDay(offset), values).filter { $0.time < now }
        }
        // today below zero too: not in the summary
        points = points.map { $0.time == clock(3, on: weekDay(3)) ? IOBPoint(time: $0.time, iob: -3) : $0 }
        let input = InsulinInput(coverage: rows, schedules: [flat(1)], iob: points)
        let days = Engine.days(Engine.lastDays(4, now: now, calendar: calendar), input: input, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.isHeadline), [true, true, true, false])

        let stats = Engine.negativeIOB(days)
        XCTAssertEqual(stats.headlineDays, 3)
        XCTAssertEqual(stats.secondsPerDay!, .minutes(20), accuracy: accuracy)
        XCTAssertEqual(stats.share!, 1.0 / 72, accuracy: accuracy)
        XCTAssertEqual(stats.meanDepth!, -1680.0 / 3600, accuracy: accuracy)
        XCTAssertEqual(stats.lowest, -1.0)
        XCTAssertEqual(stats.lowestAt, clock(3, 10, on: weekDay(1)))
        let hours = try? XCTUnwrap(stats.hours)
        XCTAssertEqual(hours?[3] ?? 0, .minutes(50) / 3, accuracy: accuracy)
        XCTAssertEqual(hours?[5] ?? 0, .minutes(10) / 3, accuracy: accuracy)
        XCTAssertEqual(hours?.reduce(0, +) ?? 0, stats.secondsPerDay!, accuracy: accuracy)
        XCTAssertEqual(stats.secondsPerDay!, Engine.summary(days, period: nil).negativeIOBSecondsPerDay!, accuracy: accuracy)

        // without a headline day: nothing
        let none = Engine.negativeIOB([days[3]])
        XCTAssertEqual(none.headlineDays, 0)
        XCTAssertNil(none.secondsPerDay)
        XCTAssertNil(none.meanDepth)
        XCTAssertNil(none.lowest)
        XCTAssertNil(none.hours)
    }

    /// The IOB by time of day: each bin's percentiles over the days' means, pooled with a bin on either side
    /// (wrapping at midnight); the quantiles linear between the closest ranks.
    func testIOBProfilePercentiles() {
        XCTAssertNil(Engine.quantile([], 0.5))
        XCTAssertEqual(Engine.quantile([5], 0.9), 5)
        XCTAssertEqual(Engine.quantile([1, 2, 3, 4], 0.5)!, 2.5, accuracy: accuracy)
        XCTAssertEqual(Engine.quantile([1, 2, 3, 4], 0)!, 1, accuracy: accuracy)
        XCTAssertEqual(Engine.quantile([1, 2, 3, 4], 1)!, 4, accuracy: accuracy)

        // four days, each a constant 0, 1, 2 and 3 U all day
        let days = (0 ... 3).map { offset in
            dayInsulin(weekDay(offset), iob: iobRows(weekDay(offset), [Double](repeating: Double(offset), count: 288)))
        }
        let profile = Engine.iobProfile(days)
        XCTAssertEqual(profile.count, 96)
        for bin in [0, 47, 95] {
            let p = try? XCTUnwrap(profile[bin])
            XCTAssertEqual(p?.p10 ?? -1, 0, accuracy: accuracy)
            XCTAssertEqual(p?.p25 ?? -1, 0.75, accuracy: accuracy)
            XCTAssertEqual(p?.p50 ?? -1, 1.5, accuracy: accuracy)
            XCTAssertEqual(p?.p75 ?? -1, 2.25, accuracy: accuracy)
            XCTAssertEqual(p?.p90 ?? -1, 3, accuracy: accuracy)
        }
        // a bin without a mean in it or beside it: nil; beside one: pooled from it
        let morning = dayInsulin(weekDay(0), iob: iobRows(clock(8, on: weekDay(0)), [1, 1, 1]))
        let sparse = Engine.iobProfile([morning])
        XCTAssertNotNil(sparse[31])
        XCTAssertNotNil(sparse[32])
        XCTAssertNotNil(sparse[33])
        XCTAssertNil(sparse[30])
        XCTAssertNil(sparse[34])
    }

    // MARK: - Summary (rule a)

    /// 7 days, today the 7th at 09:00: days 1-4 fully covered with 6 U of boluses each, day 5 70% covered with 6 U of
    /// boluses, day 6 40% covered, today covered up to 09:00 with a 10 U breakfast bolus. Flat 1 U/h.
    private func ruleAPeriod() -> (period: InsulinPeriod, now: Date) {
        let now = clock(9, on: weekDay(6))
        var rows = [coverage(weekDay(0), weekDay(4)), coverage(weekDay(4), weekDay(4).addingTimeInterval(.hours(16.8)))]
        rows.append(coverage(weekDay(5), weekDay(5).addingTimeInterval(.hours(9.6))))
        rows.append(coverage(weekDay(6), now))
        var events: [PumpEventRecord] = []
        for offset in 0 ... 4 {
            events.append(bolus(clock(8, on: weekDay(offset)), 4))
            events.append(bolus(clock(13, on: weekDay(offset)), 2, smb: true))
        }
        events.append(bolus(clock(8, on: weekDay(6)), 10))
        let input = InsulinInput(events: events, coverage: rows, schedules: [flat(1)])
        return (Engine.period(.days7, input: input, now: now, calendar: calendar), now)
    }

    func testRuleAExcludesTodayAndDaysUnderHalfCoveredAndScalesOnlyTheBasal() {
        let (period, _) = ruleAPeriod()
        let summary = period.summary
        XCTAssertEqual(period.days.count, 7)
        XCTAssertEqual(period.days.last?.isToday, true)
        XCTAssertEqual(period.days.map(\.isHeadline), [true, true, true, true, true, false, false])
        XCTAssertEqual(summary.headlineDays, 5)
        XCTAssertEqual(summary.calendarDays, 7)
        XCTAssertEqual(summary.daysWithData, 7)
        // the 70% day's 16.8 U of basal reads 24, its boluses stay 6
        XCTAssertEqual(period.days[4].scaledBasal, 24, accuracy: accuracy)
        XCTAssertEqual(summary.tdd!, 30, accuracy: accuracy)
        XCTAssertEqual(summary.basal!, 24, accuracy: accuracy)
        XCTAssertEqual(summary.bolus!, 4, accuracy: accuracy)
        XCTAssertEqual(summary.smb!, 2, accuracy: accuracy)
        XCTAssertEqual(summary.splitPercents, [80, 7, 13])
        XCTAssertEqual(summary.splitPercents.reduce(0, +), 100)
        // limited: 5 headline days < 6
        XCTAssertTrue(summary.isLimited)
        // (4 × 24 + 16.8 + 9.6 + 9) h of the 153 h up to the last heartbeat
        XCTAssertEqual(summary.coverage, 131.4 / 153, accuracy: 1E-9)
        XCTAssertEqual(summary.coveragePercent, 86)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertFalse(summary.needsCompleteDay)
        // today is shown "so far", not averaged
        XCTAssertEqual(period.days[6].total, 9 + 10, accuracy: accuracy)
    }

    func testTheMorningBolusDoesNotReadAsAWholeDay() {
        // a new user: today only, 09:00, 10 U breakfast bolus
        let now = clock(9, on: weekDay(6))
        let input = InsulinInput(
            events: [bolus(clock(8, on: weekDay(6)), 10)],
            coverage: [coverage(weekDay(6), now)],
            schedules: [flat(1)]
        )
        let summary = Engine.period(.days7, input: input, now: now, calendar: calendar).summary
        XCTAssertNil(summary.tdd)
        XCTAssertTrue(summary.needsCompleteDay)
        XCTAssertEqual(summary.splitPercents, [0, 0, 0])
        XCTAssertEqual(summary.daysWithData, 1)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertNil(summary.basalVsScheduled)
    }

    func testEmptyPeriod() {
        let summary = Engine.period(
            .days7,
            input: InsulinInput(schedules: [flat(1)]),
            now: clock(9, on: weekDay(6)),
            calendar: calendar
        )
        .summary
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.coverage, 0)
        XCTAssertNil(summary.negativeIOBSecondsPerDay)
    }

    func testLimitedAt99AndNotAt100Percent() {
        let now = clock(12, on: weekDay(6))
        let full = InsulinInput(coverage: [coverage(weekDay(0), now)], schedules: [flat(1)])
        let complete = Engine.period(.days7, input: full, now: now, calendar: calendar).summary
        XCTAssertEqual(complete.headlineDays, 6)
        XCTAssertEqual(complete.coveragePercent, 100)
        XCTAssertFalse(complete.isLimited)

        // 100 minutes missing of 156 h: 98.9%
        let short = InsulinInput(coverage: [coverage(weekDay(0).addingTimeInterval(.minutes(100)), now)], schedules: [flat(1)])
        let limited = Engine.period(.days7, input: short, now: now, calendar: calendar).summary
        XCTAssertEqual(limited.headlineDays, 6)
        XCTAssertEqual(limited.coveragePercent, 99)
        XCTAssertTrue(limited.isLimited)
    }

    func testLimitedWhenFewerHeadlineDaysThanCompleteDays() {
        let window = DateInterval(start: weekDay(0), end: weekDay(7))
        func summary(headlineDays: Int, coveragePercent: Int) -> InsulinSummary {
            InsulinSummary(
                window: window,
                calendarDays: 7,
                daysWithData: 7,
                headlineDays: headlineDays,
                tdd: 30,
                basal: 20,
                smb: 5,
                bolus: 5,
                splitPercents: [67, 17, 16],
                basalVsScheduled: 1,
                scheduledPerDay: 20,
                zeroBasalSecondsPerDay: 0,
                negativeIOBSecondsPerDay: nil,
                coverage: Double(coveragePercent) / 100,
                coveragePercent: coveragePercent,
                isEmpty: false,
                profileAssumedBefore: nil
            )
        }
        XCTAssertFalse(summary(headlineDays: 6, coveragePercent: 100).isLimited)
        XCTAssertTrue(summary(headlineDays: 5, coveragePercent: 100).isLimited)
        XCTAssertTrue(summary(headlineDays: 6, coveragePercent: 99).isLimited)
    }

    func testBasalVsScheduledIsADashAtZeroScheduled() {
        let now = clock(12, on: weekDay(2))
        let input = InsulinInput(
            events: [temp(clock(10, on: weekDay(0)), rate: 1, minutes: 60.1)],
            coverage: [coverage(weekDay(0), now)],
            schedules: [flat(0)]
        )
        let days = Engine.days([wholeDay(weekDay(0)), wholeDay(weekDay(1))], input: input, now: now, calendar: calendar)
        let summary = Engine.summary(days, period: nil)
        XCTAssertEqual(summary.headlineDays, 2)
        XCTAssertNil(summary.basalVsScheduled)
        XCTAssertNil(summary.basalVsScheduledPercent)
        XCTAssertEqual(summary.zeroBasalSecondsPerDay!, .hours(23.5), accuracy: accuracy)
    }

    func testNegativeIOBPerDayOverTheHeadlineDays() {
        let now = clock(12, on: weekDay(2))
        // day 0: 60 rows of 5 min, 12 of them negative; day 1: no rows
        let points = (0 ..< 60).map { index in
            IOBPoint(time: clock(10, on: weekDay(0)).addingTimeInterval(.minutes(5 * index)), iob: index < 12 ? -0.1 : 0.4)
        }
        let input = InsulinInput(coverage: [coverage(weekDay(0), now)], schedules: [flat(1)], iob: points)
        let days = Engine.days(
            [wholeDay(weekDay(0)), wholeDay(weekDay(1)), wholeDay(weekDay(2))],
            input: input,
            now: now,
            calendar: calendar
        )
        let summary = Engine.summary(days, period: nil)
        XCTAssertEqual(summary.negativeIOBSecondsPerDay!, .hours(1) / .hours(5) * .hours(24), accuracy: accuracy)
    }

    // MARK: - By hour

    func testHoursOverTheHeadlineDays() {
        let start = Self.fallBack
        // the DST day and the day after, both fully covered at 1 U/h; an SMB of 0.6 at 02:30 on each; today partial
        let rows = [coverage(start, clock(8, on: day(2, from: start)))]
        let events = [
            bolus(clock(2, 30, on: start), 0.6, smb: true),
            bolus(clock(2, 30, on: day(1, from: start)), 0.6, smb: true)
        ]
        let input = InsulinInput(events: events, coverage: rows, schedules: [flat(1)])
        let days = Engine.days(
            [wholeDay(start), wholeDay(day(1, from: start)), wholeDay(day(2, from: start))],
            input: input,
            now: clock(8, on: day(2, from: start)),
            calendar: calendar
        )
        let hours = Engine.hours(days)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[2].days, 2)
        // the repeated hour: 3 covered hours over the two days
        XCTAssertEqual(hours[2].coveredHours, 3, accuracy: accuracy)
        XCTAssertEqual(hours[2].basal!, 1, accuracy: accuracy)
        XCTAssertEqual(hours[2].scheduled!, 1, accuracy: accuracy)
        XCTAssertEqual(hours[2].basalVsScheduled!, 1, accuracy: accuracy)
        XCTAssertEqual(hours[2].smb, 0.6, accuracy: accuracy)
        XCTAssertEqual(hours[2].total, 1.6, accuracy: accuracy)
        XCTAssertEqual(hours[3].coveredHours, 2, accuracy: accuracy)
        XCTAssertEqual(hours[3].smb, 0, accuracy: accuracy)
        // today's hours aren't in it
        XCTAssertEqual(hours[7].coveredHours, 2, accuracy: accuracy)

        let none = Engine.hours([])
        XCTAssertNil(none[0].basal)
        XCTAssertEqual(none[0].smb, 0)
    }

    // MARK: - Period days

    func testPeriodDaysAreWholeCalendarDays() {
        let now = clock(9, on: Self.fallBack)
        let days = Engine.periodDays(.days7, now: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.start, Self.fallBack)
        XCTAssertEqual(days.last?.duration, .hours(25))
        XCTAssertEqual(days.first?.start, day(-6, from: Self.fallBack))
        // just after midnight today is still one of them
        let midnight = Engine.periodDays(.days7, now: Self.day0.addingTimeInterval(30), calendar: calendar)
        XCTAssertEqual(midnight.last?.start, Self.day0)
        XCTAssertEqual(midnight.count, 7)
    }

    // MARK: - Meals

    private func meal(
        _ date: Date,
        _ carbs: Double,
        fat: Double = 0,
        protein: Double = 0,
        id: String? = nil
    ) -> MealPoint {
        MealPoint(id: id ?? UUID().uuidString, actualDate: date, carbs: carbs, fat: fat, protein: protein)
    }

    func testMealsDuplicateIdsBecomeOneAtTheEarliestDate() {
        let points = [
            meal(clock(12, 5), 40, id: "a"),
            meal(clock(12), 40, id: "a"),
            meal(clock(12, 10), 40, id: "a"),
            meal(clock(13), 20, id: ""),
            meal(clock(13), 20, id: ""),
            meal(clock(14), 0, id: "zero"),
            meal(clock(15), 0, fat: 5, id: "fat")
        ]
        let clean = MealStatsEngine.clean(points)
        XCTAssertEqual(clean.map(\.actualDate), [clock(12), clock(13), clock(13), clock(15)])
        XCTAssertEqual(clean.first?.id, "a")
    }

    func testCarbEquivalents() {
        XCTAssertEqual(MealStatsEngine.carbEquivalents(fat: 20, protein: 30, factor: 0.5), 15, accuracy: accuracy)
        XCTAssertEqual(MealStatsEngine.carbEquivalents(fat: 0, protein: 0, factor: 0.5), 0)
    }

    /// 7 days, today the 7th at 18:00: entries on days 1, 3 and 4, and today.
    private func mealPeriod(logged: Bool = false) -> MealPeriod {
        let points = [
            meal(clock(8, on: day(0)), 40),
            meal(clock(12, 30, on: day(0)), 60),
            meal(clock(8, 15, on: day(2)), 30, fat: 20, protein: 30),
            meal(clock(13, on: day(2)), 50),
            meal(clock(19, on: day(3)), 60),
            meal(clock(19, 30, on: day(3)), 0, protein: 10),
            meal(clock(8, on: day(6)), 25),
            // after now
            meal(clock(20, on: day(6)), 80)
        ]
        return MealStatsEngine.period(
            .days7,
            points: points,
            fatOrProteinLogged: logged,
            factor: 0.5,
            now: clock(18, on: day(6)),
            calendar: calendar
        )
    }

    func testMealsAveragesOverTheCompleteDaysWithEntries() {
        let period = mealPeriod()
        let summary = period.summary
        XCTAssertEqual(period.days.count, 7)
        XCTAssertEqual(summary.completeDays, 6)
        XCTAssertEqual(summary.daysWithEntries, 3)
        XCTAssertTrue(summary.isLimited)
        XCTAssertEqual(summary.carbs, 240, accuracy: accuracy)
        XCTAssertEqual(summary.carbsPerDay!, 80, accuracy: accuracy)
        XCTAssertEqual(summary.entriesPerDay!, 2, accuracy: accuracy)
        // the protein-only entry has no carbs
        XCTAssertEqual(summary.perEntry!, 48, accuracy: accuracy)
        XCTAssertEqual(summary.fatPerDay!, 20.0 / 3, accuracy: accuracy)
        XCTAssertEqual(summary.proteinPerDay!, 40.0 / 3, accuracy: accuracy)
        XCTAssertEqual(summary.carbEquivalentsPerDay!, 17.0 / 3, accuracy: accuracy)
        XCTAssertFalse(summary.isEmpty)
        // today "so far", not averaged; the entry after now is left out
        XCTAssertEqual(period.days[6].carbs, 25, accuracy: accuracy)
        XCTAssertTrue(period.days[6].isToday)
        XCTAssertFalse(period.days[6].isAveraged)
    }

    func testMealsHoursSumToTheDayAndTopHoursTieToTheEarlier() {
        let period = mealPeriod()
        XCTAssertEqual(period.hours.reduce(0) { $0 + $1.carbsPerDay }, period.summary.carbsPerDay!, accuracy: accuracy)
        XCTAssertEqual(period.hours.reduce(0) { $0 + $1.share }, 1, accuracy: accuracy)
        XCTAssertEqual(period.hours[8].daysWithEntries, 2)
        XCTAssertEqual(period.hours[8].carbs, 70, accuracy: accuracy)
        XCTAssertEqual(period.hours[8].perEntry!, 35, accuracy: accuracy)
        XCTAssertEqual(period.hours[19].perEntry!, 60, accuracy: accuracy)
        XCTAssertEqual(period.hours[19].entries, 2)
        // 08 (70 g); 12 and 19 (60 g each): the earlier first
        XCTAssertEqual(period.topHours.map(\.hour), [8, 12, 19])
    }

    func testMealsEmptyAndTodayOnly() {
        let empty = MealStatsEngine.period(
            .days7,
            points: [],
            fatOrProteinLogged: false,
            factor: 0.5,
            now: clock(9),
            calendar: calendar
        )
        XCTAssertTrue(empty.summary.isEmpty)
        XCTAssertNil(empty.summary.carbsPerDay)
        XCTAssertTrue(empty.topHours.isEmpty)

        let today = MealStatsEngine.period(
            .days7,
            points: [meal(clock(8), 30)],
            fatOrProteinLogged: false,
            factor: 0.5,
            now: clock(9),
            calendar: calendar
        )
        XCTAssertFalse(today.summary.isEmpty)
        XCTAssertNil(today.summary.carbsPerDay)
        XCTAssertEqual(today.summary.daysWithEntries, 0)
        XCTAssertTrue(today.topHours.isEmpty)
    }

    func testLogsFatOrProteinOverNinetyDays() {
        let now = clock(9)
        let inside = meal(clock(8, on: day(-89)), 10, fat: 5)
        let outside = meal(clock(23, on: day(-90)), 10, protein: 5)
        XCTAssertTrue(MealStatsEngine.logsFatOrProtein([inside], now: now, calendar: calendar))
        XCTAssertFalse(MealStatsEngine.logsFatOrProtein([outside], now: now, calendar: calendar))
        XCTAssertFalse(MealStatsEngine.logsFatOrProtein([meal(clock(8), 50)], now: now, calendar: calendar))
        // the flag is passed through, whatever the period holds
        XCTAssertTrue(mealPeriod(logged: true).summary.logsFatOrProtein)
    }

    // MARK: - Nutrients

    private func food(
        _ date: Date,
        _ carbs: Double,
        fiber: Double = 0,
        _ micronutrients: [MicroNutrient: Double] = [:]
    ) -> MealPoint {
        MealPoint(id: UUID().uuidString, actualDate: date, carbs: carbs, fiber: fiber, micronutrients: micronutrients)
    }

    /// 7 days, today the 7th at 18:00: days counted (0, 4, 5), partly logged (1), without data (2), without entries (3).
    private func nutrientPeriod() -> NutrientPeriod {
        let points = [
            // 50 of 62.5 g with nutrient data: 80%, counted
            food(clock(8, on: day(0)), 50, fiber: 6, [.salt: 3, .vitaminC: 30]),
            food(clock(12, on: day(0)), 12.5),
            // 40 of 50.5 g: 79%, not counted
            food(clock(8, on: day(1)), 40, fiber: 10, [.salt: 9]),
            food(clock(12, on: day(1)), 10.5),
            food(clock(8, on: day(2)), 60),
            // the second food doesn't list vitamin C (0); folate stored in mg
            food(clock(8, on: day(4)), 30, fiber: 2, [.vitaminC: 60, .vitaminB9: 0.1]),
            food(clock(12, on: day(4)), 30, [.iron: 4]),
            food(clock(8, on: day(5)), 45, fiber: 4),
            // today: never counted
            food(clock(8, on: day(6)), 40, fiber: 8, [.salt: 2])
        ]
        let meals = MealStatsEngine.period(
            .days7,
            points: points,
            fatOrProteinLogged: false,
            factor: 0.5,
            now: clock(18, on: day(6)),
            calendar: calendar
        )
        return NutrientStatsEngine.period(meals.days, points: points, now: clock(18, on: day(6)), logsNutrients: true)
    }

    /// A complete day counts when its foods with nutrient data carry at least 80% of its carbs; the averages are over
    /// those days, a nutrient a food doesn't list adds 0, today and the partly logged days are left out.
    func testNutrientDaysCountAtEightyPercentOfTheCarbs() {
        let period = nutrientPeriod()
        let days = period.days
        XCTAssertEqual(days.map(\.isCounted), [true, false, false, false, true, true, false])
        XCTAssertEqual(days.map(\.hasData), [true, true, false, false, true, true, true])
        XCTAssertEqual(days[0].carbShareWithData, 0.8, accuracy: accuracy)
        XCTAssertEqual(days[1].entriesWithData, 1)
        XCTAssertEqual(days[1].entries, 2)
        XCTAssertEqual(days[1].carbShareWithData, 40 / 50.5, accuracy: accuracy)
        XCTAssertEqual(days[2].amounts, [:])
        XCTAssertEqual(days[3].entries, 0)
        XCTAssertEqual(days[4].amounts[.micro(.vitaminC)]!, 60, accuracy: accuracy)
        XCTAssertEqual(days[4].amounts[.micro(.zinc)], 0)
        XCTAssertTrue(days[6].isToday)
        XCTAssertEqual(days[6].amounts[.micro(.salt)]!, 2, accuracy: accuracy)

        let summary = period.summary
        XCTAssertEqual(summary.completeDays, 6)
        XCTAssertEqual(summary.countedDays, 3)
        XCTAssertTrue(summary.periodHasData)
        XCTAssertTrue(summary.logsNutrients)
        // 3 of 6: fewer than ⌈0.7 × 6⌉ = 5
        XCTAssertTrue(summary.isLimited)
        XCTAssertEqual(summary.perDay.count, StatsNutrient.all.count)
        XCTAssertEqual(summary.perDay[.fiber]!, 4, accuracy: accuracy)
        XCTAssertEqual(summary.perDay[.micro(.vitaminC)]!, 30, accuracy: accuracy)
        // day 1's 9 g is not in it
        XCTAssertEqual(summary.perDay[.micro(.salt)]!, 1, accuracy: accuracy)
        XCTAssertEqual(summary.perDay[.micro(.vitaminB9)]!, 100.0 / 3, accuracy: accuracy)
        XCTAssertEqual(summary.perDay[.micro(.iron)]!, 4.0 / 3, accuracy: accuracy)
        XCTAssertEqual(summary.perDay[.micro(.zinc)], 0)
    }

    /// No day with nutrient data, or only partly logged ones and today: nothing averaged, nothing to mark.
    func testNutrientsWithoutACountedDay() {
        let now = clock(18, on: day(6))
        func period(_ points: [MealPoint]) -> NutrientPeriod {
            let meals = MealStatsEngine.period(
                .days7,
                points: points,
                fatOrProteinLogged: false,
                factor: 0.5,
                now: now,
                calendar: calendar
            )
            return NutrientStatsEngine.period(meals.days, points: points, now: now, logsNutrients: false)
        }
        let none = period([food(clock(8, on: day(2)), 60)]).summary
        XCTAssertEqual(none.countedDays, 0)
        XCTAssertFalse(none.periodHasData)
        XCTAssertEqual(none.perDay, [:])
        XCTAssertFalse(none.isLimited)

        let partly = period([
            food(clock(8, on: day(2)), 30, fiber: 3),
            food(clock(9, on: day(2)), 60),
            food(clock(8, on: day(6)), 30, fiber: 3)
        ]).summary
        XCTAssertEqual(partly.countedDays, 0)
        XCTAssertTrue(partly.periodHasData)
        XCTAssertEqual(partly.perDay, [:])
        XCTAssertFalse(partly.isLimited)
    }

    /// Limited below 3 counted days, or below ⌈0.7 × the complete days⌉ (in whole numbers).
    func testNutrientsLimitedRule() {
        func summary(_ counted: Int, of complete: Int) -> NutrientSummary {
            NutrientSummary(completeDays: complete, countedDays: counted, perDay: [:], periodHasData: true, logsNutrients: true)
        }
        XCTAssertFalse(summary(0, of: 6).isLimited)
        XCTAssertTrue(summary(4, of: 6).isLimited)
        XCTAssertFalse(summary(5, of: 6).isLimited)
        XCTAssertTrue(summary(9, of: 13).isLimited)
        XCTAssertFalse(summary(10, of: 13).isLimited)
        XCTAssertTrue(summary(20, of: 29).isLimited)
        XCTAssertFalse(summary(21, of: 29).isLimited)
        XCTAssertTrue(summary(62, of: 89).isLimited)
        XCTAssertFalse(summary(63, of: 89).isLimited)
        XCTAssertFalse(summary(7, of: 10).isLimited)
        XCTAssertTrue(summary(2, of: 2).isLimited)
    }

    private func birthDate(_ years: Int, days: Int = 0, before now: Date) -> Date {
        calendar.date(byAdding: DateComponents(year: -years, day: days), to: now)!
    }

    /// The references need the sex (woman or man: "other" and "not set" are not set) and the birth date; no
    /// fallback.
    func testNutrientReferences() {
        let now = clock(12)
        func references(_ sex: Int, _ birthDate: Date) -> NutrientReferences? {
            NutrientReferences(.init(sexSetting: sex, birthDate: birthDate), now: now, calendar: calendar)
        }
        XCTAssertNil(references(3, birthDate(41, before: now)))
        XCTAssertNil(references(2, birthDate(41, before: now)))
        XCTAssertNil(references(0, .distantPast))
        XCTAssertNil(references(1, birthDate(121, before: now)))
        // the edges of 0...120 are accepted: born today, and the 120th birthday up to the day before the 121st
        XCTAssertEqual(references(0, birthDate(0, before: now))?.age, 0)
        XCTAssertEqual(references(1, birthDate(120, before: now))?.age, 120)
        XCTAssertEqual(references(1, birthDate(121, days: 1, before: now))?.age, 120)

        let woman = references(0, birthDate(41, before: now))!
        XCTAssertEqual(woman.person, .woman)
        XCTAssertEqual(woman.age, 41)
        XCTAssertEqual(woman.intakes.count, StatsNutrient.all.count)
        XCTAssertEqual(woman.intakes[.fiber], 25)
        XCTAssertEqual(woman.intakes[.micro(.iron)], 16)
        XCTAssertEqual(woman.intakes[.micro(.salt)], 5)
        XCTAssertEqual(woman.intakes[.micro(.vitaminB9)], 330)
        // the day before the 41st birthday
        XCTAssertEqual(references(0, birthDate(41, days: 1, before: now))?.age, 40)

        let man = references(1, birthDate(41, before: now))!
        XCTAssertEqual(man.person, .man)
        XCTAssertEqual(man.intakes[.micro(.iron)], 11)
        let child = references(0, birthDate(12, before: now))!
        XCTAssertEqual(child.intakes[.fiber], 21)
        XCTAssertEqual(child.intakes[.micro(.calcium)], 1150)
    }

    /// The units shown are the reference table's; the app stores B7 and B9 in mg, the table has them in µg.
    func testNutrientUnitsAreTheReferenceTables() {
        for age in [2, 12, 41] {
            for sex in [Sex.woman, .man, .other] {
                XCTAssertEqual(
                    EFSAReferenceIntakes.value(for: MacroNutrient.fiber, age: age, sex: sex).unit,
                    StatsNutrient.fiber.unit
                )
                for nutrient in MicroNutrient.allCases {
                    XCTAssertEqual(
                        EFSAReferenceIntakes.value(for: nutrient, age: age, sex: sex).unit,
                        StatsNutrient.micro(nutrient).unit,
                        "\(nutrient)"
                    )
                }
            }
        }
        XCTAssertEqual(MicroNutrient.vitaminB9.unit, "mg")
        let folate = food(clock(8), 10, [.vitaminB9: 0.33, .vitaminB7: 0.04, .iron: 2])
        XCTAssertEqual(StatsNutrient.micro(.vitaminB9).amount(in: folate), 330, accuracy: accuracy)
        XCTAssertEqual(StatsNutrient.micro(.vitaminB7).amount(in: folate), 40, accuracy: accuracy)
        XCTAssertEqual(StatsNutrient.micro(.iron).amount(in: folate), 2, accuracy: accuracy)
        XCTAssertEqual(StatsNutrient.micro(.zinc).amount(in: folate), 0)
    }

    /// With references: by the share of the reference, the largest first, ties in the app's order; only salt is marked
    /// above its reference (iron isn't). Without: the app's order, salt alone with
    /// its limit (it depends on neither sex nor age).
    func testNutrientRows() {
        let now = clock(12)
        let woman = NutrientReferences(
            .init(sexSetting: 0, birthDate: birthDate(41, before: now)),
            now: now,
            calendar: calendar
        )
        let amounts: [StatsNutrient: Double] = [.micro(.salt): 7.5, .micro(.iron): 32, .fiber: 12.5, .micro(.vitaminB9): 330]
        let rows = NutrientStatsEngine.rows(amounts, references: woman)
        XCTAssertEqual(rows.count, StatsNutrient.all.count)
        XCTAssertEqual(
            rows.prefix(5).map(\.nutrient),
            [.micro(.iron), .micro(.salt), .micro(.vitaminB9), .fiber, .micro(.vitaminA)]
        )
        XCTAssertEqual(rows.map { $0.percent ?? -1 }.prefix(4), [200, 150, 100, 50])
        XCTAssertEqual(rows.map(\.isOverLimit).prefix(3), [false, true, false])
        XCTAssertEqual(rows.last?.nutrient, .micro(.iodine))
        XCTAssertEqual(rows.last?.percent, 0)
        // at the limit isn't above it, nor just above it while its percent shows 100 (5.02 g); 5.03 g shows 101%
        XCTAssertFalse(NutrientStatsEngine.rows([.micro(.salt): 5], references: woman).contains(where: \.isOverLimit))
        XCTAssertFalse(NutrientStatsEngine.rows([.micro(.salt): 5.02], references: woman).contains(where: \.isOverLimit))
        XCTAssertEqual(NutrientStatsEngine.rows([.micro(.salt): 5.03], references: nil).filter(\.isOverLimit).count, 1)
        XCTAssertEqual(NutrientStatsEngine.shownPercent(100.4), 100)
        XCTAssertEqual(NutrientStatsEngine.shownPercent(100.5), 101)
        XCTAssertFalse(NutrientStatsEngine.isOverLimit(.micro(.salt), percent: nil))
        XCTAssertFalse(NutrientStatsEngine.isOverLimit(.micro(.iron), percent: 300))

        let plain = NutrientStatsEngine.rows(amounts, references: nil)
        XCTAssertEqual(plain.map(\.nutrient), StatsNutrient.all)
        XCTAssertEqual(plain.compactMap(\.percent), [150])
        XCTAssertEqual(plain.filter(\.isOverLimit).map(\.nutrient), [.micro(.salt)])
        XCTAssertEqual(plain.last?.amount, 7.5)
        XCTAssertEqual(NutrientStatsEngine.reference(of: .micro(.salt), references: nil), 5)
        XCTAssertNil(NutrientStatsEngine.reference(of: .fiber, references: nil))
    }

    /// The Carbs card's Fiber tile and its way in: a food (an entry with carbs) of the last 90 days with nutrient data.
    /// A nutrient-only entry (a supplement) or one of fat and protein alone never makes a day count, so it doesn't turn
    /// them on; a supplement isn't a Meals entry.
    func testLogsNutrientsOverNinetyDays() {
        let now = clock(9)
        let engine = NutrientStatsEngine.self
        XCTAssertTrue(engine.logsNutrients([food(clock(8, on: day(-89)), 10, fiber: 1)], now: now, calendar: calendar))
        XCTAssertFalse(engine.logsNutrients([food(clock(23, on: day(-90)), 10, fiber: 1)], now: now, calendar: calendar))
        XCTAssertFalse(engine.logsNutrients([food(clock(8), 50)], now: now, calendar: calendar))
        // a vitamin D preset alone, every day: nothing
        XCTAssertFalse(engine.logsNutrients([food(clock(8), 0, [.vitaminD: 20])], now: now, calendar: calendar))
        XCTAssertFalse(engine.logsNutrients(
            (0 ..< 90).map { food(clock(8, on: day(-$0)), 0, [.vitaminD: 20]) },
            now: now,
            calendar: calendar
        ))
        // fat only, with fiber
        XCTAssertFalse(engine.logsNutrients(
            [MealPoint(id: "fat", actualDate: clock(8), carbs: 0, fat: 10, fiber: 3)],
            now: now,
            calendar: calendar
        ))
        // the supplement with a food without data: still nothing; a food with data: on
        XCTAssertFalse(engine.logsNutrients(
            [food(clock(7), 0, [.vitaminD: 20]), food(clock(8), 50)],
            now: now,
            calendar: calendar
        ))
        XCTAssertTrue(engine.logsNutrients(
            [food(clock(7), 0, [.vitaminD: 20]), food(clock(8), 50, [.iron: 1])],
            now: now,
            calendar: calendar
        ))
        let points = [food(clock(8), 0, [.iron: 1]), food(clock(9), 0), food(clock(10), 20, fiber: 2)]
        XCTAssertEqual(MealStatsEngine.clean(points).map(\.actualDate), [clock(10)])
        XCTAssertEqual(engine.nutrientOnly(points).map(\.actualDate), [clock(8)])
    }

    /// A nutrient-only entry (a supplement: no carbs, fat or protein) is left out of the Meals tab and joins its day on
    /// the Nutrients screen: on a day with carbs it adds its nutrients (the 80% rule is over the carbs, which it has
    /// none of); alone, or on a day of fat and protein only, the day isn't counted. Deduplicated by id; after now, out.
    func testNutrientOnlyEntriesAreTheNutrientsScreensAlone() {
        let now = clock(18, on: day(6))
        func supplement(_ date: Date, id: String? = nil) -> MealPoint {
            MealPoint(id: id ?? UUID().uuidString, actualDate: date, carbs: 0, micronutrients: [.vitaminD: 20])
        }
        let points = [
            // counted: 50 of 50 g with data, and the supplement's vitamin D (twice saved: one)
            food(clock(8, on: day(0)), 50, fiber: 5),
            supplement(clock(7, on: day(0)), id: "d"),
            supplement(clock(7, 1, on: day(0)), id: "d"),
            // the supplement alone
            supplement(clock(7, on: day(1))),
            // fat only, with fiber: no carbs
            MealPoint(id: "fat", actualDate: clock(12, on: day(2)), carbs: 0, fat: 10, fiber: 3),
            supplement(clock(7, on: day(2))),
            // 40 g without data: the supplement carries none of the carbs
            food(clock(8, on: day(3)), 40),
            supplement(clock(7, on: day(3))),
            // counted: 30 g with data, no supplement
            food(clock(8, on: day(4)), 30, fiber: 3),
            supplement(clock(7, on: day(6))),
            // after now
            supplement(clock(20, on: day(6)))
        ]
        let meals = MealStatsEngine.period(
            .days7,
            points: points,
            fatOrProteinLogged: false,
            factor: 0.5,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(meals.days.map(\.entries.count), [1, 0, 1, 1, 1, 0, 0])
        XCTAssertEqual(meals.summary.daysWithEntries, 4)
        XCTAssertEqual(meals.summary.entries, 4)
        XCTAssertEqual(meals.hours[7].entries, 0)

        let period = NutrientStatsEngine.period(meals.days, points: points, now: now, logsNutrients: true)
        let days = period.days
        XCTAssertEqual(days.map(\.isCounted), [true, false, false, false, true, false, false])
        XCTAssertEqual(days.map(\.entries), [2, 1, 2, 2, 1, 0, 1])
        XCTAssertEqual(days.map(\.entriesWithData), [2, 1, 2, 1, 1, 0, 1])
        XCTAssertEqual(days.map(\.hasData), [true, true, true, true, true, false, true])
        XCTAssertEqual(days[0].points.map(\.actualDate), [clock(7, on: day(0)), clock(8, on: day(0))])
        XCTAssertEqual(days[0].carbShareWithData, 1, accuracy: accuracy)
        XCTAssertEqual(days[0].amounts[.micro(.vitaminD)]!, 20, accuracy: accuracy)
        XCTAssertEqual(days[1].amounts[.micro(.vitaminD)]!, 20, accuracy: accuracy)
        XCTAssertEqual(days[2].amounts[.fiber]!, 3, accuracy: accuracy)
        XCTAssertEqual(days[3].carbShareWithData, 0)
        XCTAssertEqual(days[6].points.count, 1)

        let summary = period.summary
        XCTAssertEqual(summary.countedDays, 2)
        XCTAssertEqual(summary.perDay[.micro(.vitaminD)]!, 10, accuracy: accuracy)
        XCTAssertEqual(summary.perDay[.fiber]!, 4, accuracy: accuracy)
    }

    /// The day chart's axis: three steps of 1, 2, 2.5 or 5 × a power of ten above the largest value.
    func testNutrientAxis() {
        XCTAssertEqual(NutrientStatsEngine.niceStep(0), 1)
        XCTAssertEqual(NutrientStatsEngine.niceStep(2.5), 2.5)
        XCTAssertEqual(NutrientStatsEngine.niceStep(7), 10)
        XCTAssertEqual(NutrientStatsEngine.axisLevels(maximum: 25), [0, 10, 20, 30])
        XCTAssertEqual(NutrientStatsEngine.axisLevels(maximum: 5), [0, 2, 4, 6])
        XCTAssertEqual(NutrientStatsEngine.axisLevels(maximum: 2800), [0, 1000, 2000, 3000])
        for (level, expected) in zip(NutrientStatsEngine.axisLevels(maximum: 0.3), [0, 0.2, 0.4, 0.6]) {
            XCTAssertEqual(level, expected, accuracy: accuracy)
        }
    }
}
