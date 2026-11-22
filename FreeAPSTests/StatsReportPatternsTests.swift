@testable import FreeAPS
import PDFKit
import XCTest

/// The PDF reports' By hour, By weekday, Weekly and Good & bad days: which periods hold them, their pages' models from
/// synthetic readings run through the engines, the page plan, the kept settings, and the written file.
final class StatsReportPatternsTests: XCTestCase {
    typealias Engine = GlucoseStatsEngine

    /// Europe/Berlin, weeks from Monday
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// 2027-01-20 12:00 Europe/Berlin, a Wednesday: the reports' "now"
    private static let now: Date = calendar.date(from: DateComponents(year: 2027, month: 1, day: 20, hour: 12))!

    // MARK: - Fixtures

    /// 100 days of 5-minute readings up to `now`: 120 mg/dL, 200 in the afternoon (13:00–17:00), 60 in the small
    /// hours of the weekend (02:00–04:00); every third day the afternoon is higher and longer, so the days differ.
    private static let points: [GlucosePoint] = {
        let calendar = StatsReportPatternsTests.calendar
        let start = calendar.date(byAdding: .day, value: -100, to: calendar.startOfDay(for: now))!
        var points: [GlucosePoint] = []
        var time = start
        var index = 0
        while time < now {
            let parts = calendar.dateComponents([.hour, .weekday, .day], from: time)
            let hour = parts.hour ?? 0
            let weekend = parts.weekday == 1 || parts.weekday == 7
            let rough = (parts.day ?? 0) % 3 == 0
            var value: Int16 = 120
            if hour >= 13, hour < (rough ? 21 : 17) { value = rough ? 260 : 200 }
            if weekend, hour >= 2, hour < 4 { value = 60 }
            points.append(GlucosePoint(time: time, mgdl: value))
            index += 1
            time = start.addingTimeInterval(.minutes(5 * index))
        }
        return points
    }()

    private static let weighted = Engine.weigh(points)

    private static func bands(_ units: GlucoseUnits = .mgdL) -> StatsBands {
        Stat.ReportBuilder.standardBands(units)
    }

    private static func aggregates(_ period: StatsPeriod) -> (window: DateInterval, days: [DayAggregate]) {
        let window = Engine.window(for: period, now: Self.now, end: Self.now, calendar: Self.calendar)
        let days = Engine.days(for: period, window: window, calendar: Self.calendar)
        return (window, Engine.dayAggregates(Self.weighted, days: days))
    }

    private static func summary(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> GlucoseSummary {
        let (window, days) = aggregates(period)
        return Engine.summary(days: days, window: window, endRule: .stalled, period: period, bands: bands(units))
    }

    private static func hourOfDay(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> Stat.HourOfDayResult {
        let window = Engine.window(for: period, now: Self.now, end: Self.now, calendar: Self.calendar)
        return Stat.HourOfDayResult(
            buckets: Engine.hourOfDay(Self.weighted, calendar: Self.calendar, clippedTo: window),
            summary: summary(period, units: units),
            bands: bands(units)
        )
    }

    private static func weekday(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> Stat.WeekdayResult {
        let days = Engine.weekdayDays(weeks: period.weekCount ?? 0, today: Self.now, calendar: Self.calendar)
        return Stat.WeekdayResult(
            Engine.weekdayHours(Self.weighted, days: days, bands: bands(units), calendar: Self.calendar),
            period: period
        )
    }

    private static func weekly(units: GlucoseUnits, bandsOf: GlucoseUnits = .mgdL) -> Stat.WeeklyResult {
        let (window, days) = aggregates(.weeks13)
        return Stat.WeeklyResult(
            summary: Engine.summary(days: days, window: window, endRule: .stalled, period: .weeks13, bands: bands(bandsOf)),
            weeks: Engine.weeks(days, count: 13),
            units: units
        )
    }

    private static func goodBadDays(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> Stat.GoodBadDaysData {
        let days = Engine.completeDays(count: period.calendarDayCount ?? 0, today: Self.now, calendar: Self.calendar)
        return Stat.GoodBadDaysData(
            period: period,
            result: GoodBadDaysEngine.result(
                period: period,
                days: Engine.dayAggregates(Self.weighted, days: days),
                readings: Self.weighted,
                bands: bands(units),
                calendar: Self.calendar
            )
        )
    }

    /// 14 days of which the last 8 have readings: thirds too small to compare.
    private static func fewDays() -> Stat.GoodBadDaysData {
        let days = Engine.completeDays(count: 14, today: Self.now, calendar: Self.calendar)
        let readings = Engine.weigh(points.filter { $0.time >= Self.now.addingTimeInterval(-.days(8.5)) })
        return Stat.GoodBadDaysData(
            period: .days14,
            result: GoodBadDaysEngine.result(
                period: .days14,
                days: Engine.dayAggregates(readings, days: days),
                readings: readings,
                bands: bands(.mgdL),
                calendar: Self.calendar
            )
        )
    }

    /// 30 complete days without a reading.
    private static func nothingScored() -> Stat.GoodBadDaysData {
        let days = Engine.completeDays(count: 30, today: Self.now, calendar: Self.calendar)
        return Stat.GoodBadDaysData(
            period: .days30,
            result: GoodBadDaysEngine.result(
                period: .days30,
                days: Engine.dayAggregates([], days: days),
                readings: [],
                bands: bands(.mgdL),
                calendar: Self.calendar
            )
        )
    }

    /// 4 whole weeks without a reading.
    private static func emptyWeekday() -> Stat.WeekdayResult {
        let days = Engine.weekdayDays(weeks: 4, today: Self.now, calendar: Self.calendar)
        return Stat.WeekdayResult(Engine.weekdayHours([], days: days, bands: bands(), calendar: Self.calendar), period: .weeks4)
    }

    /// Weekly's 13 weeks of some readings, in a unit.
    private static func weekly(of points: [GlucosePoint], units: GlucoseUnits = .mgdL) -> Stat.WeeklyResult {
        let window = Engine.window(for: .weeks13, now: Self.now, end: Self.now, calendar: Self.calendar)
        let days = Engine.dayAggregates(
            Engine.weigh(points),
            days: Engine.days(for: .weeks13, window: window, calendar: Self.calendar)
        )
        return Stat.WeeklyResult(
            summary: Engine.summary(days: days, window: window, endRule: .stalled, period: .weeks13, bands: bands()),
            weeks: Engine.weeks(days, count: 13),
            units: units
        )
    }

    /// An hour of 1000 one-minute readings (05:00–06:00 over 17 days): 13 very low, 13 low, 974 in range, so the shares
    /// are fractional (1.3%, 1.3%, 97.4%; less the last reading of each day's hour, which runs a little longer).
    private static func fractionalHours() -> Stat.HourOfDayResult {
        var points: [GlucosePoint] = []
        let first = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: now))!
        for index in 0 ..< 1000 {
            let day = calendar.date(byAdding: .day, value: index / 60, to: first)!
            let time = day.addingTimeInterval(.hours(5) + .minutes(index % 60))
            let value: Int16 = index % 77 == 10 ? 50 : (index % 77 == 20 ? 60 : 120)
            points.append(GlucosePoint(time: time, mgdl: value))
        }
        let window = Engine.window(for: .days30, now: now, end: now, calendar: calendar)
        return Stat.HourOfDayResult(
            buckets: Engine.hourOfDay(Engine.weigh(points), calendar: calendar, clippedTo: window),
            summary: summary(.days30),
            bands: bands()
        )
    }

    private func summary(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> GlucoseSummary {
        Self.summary(period, units: units)
    }

    private func hourOfDay(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> Stat.HourOfDayResult {
        Self.hourOfDay(period, units: units)
    }

    private func weekday(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> Stat.WeekdayResult {
        Self.weekday(period, units: units)
    }

    private func weekly(units: GlucoseUnits, bandsOf: GlucoseUnits = .mgdL) -> Stat.WeeklyResult {
        Self.weekly(units: units, bandsOf: bandsOf)
    }

    private func goodBadDays(_ period: StatsPeriod, units: GlucoseUnits = .mgdL) -> Stat.GoodBadDaysData {
        Self.goodBadDays(period, units: units)
    }

    private func request(
        period: StatsPeriod = .days30,
        parts: [ReportPart] = [.byHour, .byWeekday, .weekly, .goodBadDays],
        units: [GlucoseUnits] = [.mgdL],
        paper: ReportPaper = .a4,
        byHour: ReportOptions.ByHourSettings = .init(),
        byWeekday: ReportOptions.ByWeekdaySettings = .init(),
        partPeriod: StatsPeriod? = nil
    ) -> Stat.ReportRequest {
        Stat.ReportRequest(
            period: period,
            parts: parts,
            units: units,
            hbA1cUnit: .percent,
            paper: paper,
            byHour: byHour,
            byWeekday: byWeekday,
            partPeriod: partPeriod
        )
    }

    /// The report's data as the builder leaves it: every part's result the request's periods give.
    private func data(_ request: Stat.ReportRequest) throws -> Stat.ReportData {
        let first = request.units.first ?? .mgdL
        var data = try Stat.ReportBuilder.assemble(
            request,
            summary: summary(request.period, units: first),
            bins: [],
            now: Self.now
        )
        if request.parts.contains(.byHour) {
            data.hourOfDay = hourOfDay(request.period, units: first)
        }
        if request.parts.contains(.byWeekday), let weeks = request.weekdayPeriod {
            data.weekday = weekday(weeks, units: first)
        }
        if request.parts.contains(.weekly), request.printsWeekly {
            data.weekly = request.units.map { weekly(units: $0, bandsOf: first) }
        }
        if request.parts.contains(.goodBadDays), let period = request.goodBadDaysPeriod {
            data.goodBadDays = goodBadDays(period, units: first)
        }
        return data
    }

    /// A row for every factor, with a value in both groups: "What was different" at its longest.
    private func allFactors() -> [GoodBadDaysFactorRow] {
        GoodBadFactor.allCases.map { factor in
            GoodBadDaysFactorRow(
                id: factor,
                reference: GoodBadDaysResult.Values(median: 10, p25: 8, p75: 12, n: 10),
                compared: GoodBadDaysResult.Values(median: 14, p25: 11, p75: 16, n: 10),
                referenceYes: 3,
                comparedYes: 6,
                notLogged: 0,
                unavailable: false
            )
        }
    }

    private func page(_ part: ReportPart, units: GlucoseUnits = .mgdL, index: Int = 0) -> ReportPage {
        ReportPage(part: part, units: units, size: ReportPaper.a4.size, index: index)
    }

    // MARK: - Availability

    /// By weekday and Weekly need 30 days, Good & bad days 14; the others any period.
    func testPartAvailability() {
        for part in [ReportPart.summary, .percentileProfile, .daysTable, .dailyCharts, .byHour] {
            for period in ReportOptions.periods {
                XCTAssertEqual(part.availability(for: period), .available, "\(part) \(period)")
            }
        }
        for part in [ReportPart.byWeekday, .weekly] {
            XCTAssertEqual(part.availability(for: .days7), .needsDays(30))
            XCTAssertEqual(part.availability(for: .days14), .needsDays(30))
            XCTAssertEqual(part.availability(for: .days30), .available)
            XCTAssertEqual(part.availability(for: .days90), .available)
        }
        XCTAssertEqual(ReportPart.goodBadDays.availability(for: .days7), .needsDays(14))
        XCTAssertEqual(ReportPart.goodBadDays.availability(for: .days14), .available)
        XCTAssertEqual(ReportPart.goodBadDays.availability(for: .days90), .available)
        XCTAssertEqual(ReportPartAvailability.needsDays(30).note, "needs 30 days or more")
        XCTAssertNil(ReportPartAvailability.available.note)
        XCTAssertFalse(ReportPartAvailability.needsDays(14).isAvailable)

        // a selected part the period can't hold is kept selected, and left out of the report
        var options = ReportOptions(period: .days7, units: .mgdL, paper: .a4, parts: Set(ReportPart.implemented))
        XCTAssertEqual(options.orderedParts, [.summary, .percentileProfile, .daysTable, .dailyCharts, .byHour])
        options.period = .days14
        XCTAssertEqual(options.orderedParts.suffix(2), [.byHour, .goodBadDays])
        options.period = .days30
        XCTAssertEqual(options.orderedParts, ReportPart.implemented)
        XCTAssertEqual(options.parts, Set(ReportPart.implemented))
    }

    /// The parts' own periods: By weekday's whole weeks, Weekly's 13, Good & bad days' days; a view's own win.
    func testPartPeriods() {
        XCTAssertNil(request(period: .days7).weekdayPeriod)
        XCTAssertNil(request(period: .days14).weekdayPeriod)
        XCTAssertEqual(request(period: .days30).weekdayPeriod, .weeks4)
        XCTAssertEqual(request(period: .days90).weekdayPeriod, .weeks13)
        XCTAssertEqual(request(period: .days90, partPeriod: .weeks8).weekdayPeriod, .weeks8)
        XCTAssertEqual(request(period: .days7, partPeriod: .weeks4).weekdayPeriod, .weeks4)
        // another view's period isn't By weekday's
        XCTAssertEqual(request(period: .days30, partPeriod: .days14).weekdayPeriod, .weeks4)

        XCTAssertNil(request(period: .days7).goodBadDaysPeriod)
        XCTAssertEqual(request(period: .days14).goodBadDaysPeriod, .days14)
        XCTAssertEqual(request(period: .days90).goodBadDaysPeriod, .days90)
        XCTAssertEqual(request(period: .days90, partPeriod: .days30).goodBadDaysPeriod, .days30)

        XCTAssertEqual(Stat.ReportRequest.weeklyPeriod, .weeks13)
        XCTAssertFalse(request(period: .days14).printsWeekly)
        XCTAssertTrue(request(period: .days30).printsWeekly)
        // Weekly's own "Export PDF"
        XCTAssertTrue(request(period: .days14, parts: [.weekly]).printsWeekly)
    }

    // MARK: - The plan and the estimate

    func testPagePlan() throws {
        // 30 days: a page each (Good & bad days without factor rows fits one)
        var month = try data(request())
        var pages = month.pages(calendar: Self.calendar)
        XCTAssertEqual(pages.map(\.part), [.byHour, .byWeekday, .weekly, .goodBadDays])
        XCTAssertTrue(pages.allSatisfy { $0.size == CGSize(width: 595, height: 842) })
        // with every factor row: what was different starts under the comparison and goes on, with the days, on a
        // second page
        month.goodBadDays?.factors = allFactors()
        pages = month.pages(calendar: Self.calendar)
        XCTAssertEqual(pages.map(\.part), [.byHour, .byWeekday, .weekly, .goodBadDays, .goodBadDays])
        XCTAssertEqual(pages.suffix(2).map(\.index), [0, 1])
        XCTAssertEqual(month.pageCount(of: .goodBadDays, calendar: Self.calendar), 2)

        // both units: a part's pages in the first unit, then in the second
        var bothData = try data(request(units: [.mmolL, .mgdL]))
        bothData.goodBadDays?.factors = allFactors()
        let both = bothData.pages(calendar: Self.calendar)
        XCTAssertEqual(both.count, 10)
        XCTAssertEqual(both.prefix(2).map(\.units), [.mmolL, .mgdL])
        XCTAssertEqual(both.suffix(4).map(\.units), [.mmolL, .mmolL, .mgdL, .mgdL])

        // 7 days: By weekday, Weekly and Good & bad days are left out, not failed
        let week = try data(request(period: .days7))
        XCTAssertNil(week.weekday)
        XCTAssertEqual(week.weekly, [])
        XCTAssertNil(week.goodBadDays)
        XCTAssertEqual(week.pages(calendar: Self.calendar).map(\.part), [.byHour])

        // 14 days: Good & bad days is in, with thirds of 5 days; no factor rows here, so it is one page
        let fortnight = try data(request(period: .days14))
        XCTAssertEqual(fortnight.pages(calendar: Self.calendar).map(\.part), [.byHour, .goodBadDays])
        XCTAssertEqual(fortnight.goodBadDays?.result.thirds.isComparable, true)

        // the estimate is never under the plan
        for period in ReportOptions.periods {
            for units in ReportUnits.allCases {
                let options = ReportOptions(
                    period: period,
                    units: units,
                    paper: .a4,
                    parts: [.byHour, .byWeekday, .weekly, .goodBadDays]
                )
                let planned =
                    try data(request(period: period, parts: options.orderedParts, units: units.printed(userUnits: .mgdL)))
                        .pages(calendar: Self.calendar).count
                XCTAssertLessThanOrEqual(planned, options.estimatedPageCount, "\(period) \(units)")
                XCTAssertEqual(options.estimateIsUpperBound, options.orderedParts.contains(.goodBadDays))
            }
        }
        var options = ReportOptions(period: .days30, units: .mgdL, paper: .a4, parts: [.byHour, .byWeekday, .weekly])
        XCTAssertEqual(options.estimatedPageCount, 3)
        XCTAssertFalse(options.estimateIsUpperBound)
        options.parts.insert(.goodBadDays)
        XCTAssertEqual(options.estimatedPageCount, 3 + ReportPlan.goodBadDaysPages)
        options.period = .days7
        XCTAssertEqual(options.estimatedPageCount, 1)
        XCTAssertEqual(
            ReportPart.implemented.filter { ReportPlan.isLandscape($0, dailyCharts: .init()) },
            [.percentileProfile, .daysTable]
        )
    }

    /// The blocks flow in the screen's order: each under the one before it while it fits, else on the next page; the
    /// factors break between sections; never past the page.
    func testGoodBadDaysLayout() throws {
        typealias Layout = ReportGoodBadDaysLayout
        func sections(_ pages: [[Layout.Block]]) -> [[Layout.Section]] {
            pages.flatMap { $0 }.compactMap { block in
                if case let .factors(sections, _, _) = block { return sections }
                return nil
            }
        }
        func flags(_ pages: [[Layout.Block]]) -> [[Bool]] {
            pages.flatMap { $0 }.compactMap { block in
                if case let .factors(_, isFirst, isLast) = block { return [isFirst, isLast] }
                return nil
            }
        }
        var month = goodBadDays(.days30)
        XCTAssertTrue(month.result.thirds.isComparable)
        XCTAssertEqual(month.result.thirds.reference.days.count, 10)
        // no factor rows: no block for them, everything on one page
        XCTAssertTrue(Layout.factorSections(month).isEmpty)
        XCTAssertEqual(Layout.pages(month, paper: .a4), [[.comparison, .lists]])
        XCTAssertEqual(Layout.pages(month, paper: .letter), [[.comparison, .lists]])

        // every factor row: the first page is filled with the sections that fit under the comparison, the rest and the
        // days are on the second, under the title again
        month.factors = allFactors()
        XCTAssertEqual(Layout.factorSections(month).map(\.section), Layout.Section.allCases)
        XCTAssertEqual(Layout.factorSections(month).reduce(0) { $0 + $1.rows }, GoodBadFactor.allCases.count)
        for paper in ReportPaper.allCases {
            let pages = Layout.pages(month, paper: paper)
            XCTAssertEqual(pages.count, 2, "\(paper)")
            XCTAssertEqual(pages[0].first, .comparison)
            XCTAssertEqual(pages[0].count, 2)
            XCTAssertEqual(pages[1].last, .lists)
            XCTAssertEqual(flags(pages), [[true, false], [false, true]])
            // every section once, whole, in the screen's order
            XCTAssertEqual(sections(pages).flatMap { $0 }, Layout.Section.allCases)
            XCTAssertTrue(sections(pages).allSatisfy(\.isNotEmpty))
            // the first page is filled: the next section wouldn't have fitted
            let used = pages[0].reduce(0) { $0 + Layout.height($1, month) }
            let next = try XCTUnwrap(Layout.factorSections(month).first { $0.section == sections(pages)[1][0] })
            XCTAssertGreaterThan(used + Layout.factorSectionHeight(rows: next.rows), Layout.available(paper))
        }
        // a few rows fit whole under the comparison; the days no longer do
        var some = goodBadDays(.days30)
        some.factors = Array(allFactors().prefix(7))
        XCTAssertEqual(
            Layout.pages(some, paper: .a4),
            [[.comparison, .factors(sections: [.meals], isFirst: true, isLast: true)], [.lists]]
        )

        var quarter = goodBadDays(.days90)
        quarter.factors = allFactors()
        XCTAssertEqual(quarter.result.thirds.reference.days.count, 30)
        // a long list is in two columns: 15 rows for 30 days
        XCTAssertEqual(Layout.listRows(30), 15)
        XCTAssertEqual(Layout.listRows(12), 12)
        XCTAssertEqual(Layout.listRows(13), 7)
        XCTAssertGreaterThan(Layout.listsHeight(quarter), Layout.listsHeight(month))
        // a section whose read failed: its title line, no row
        var failed = goodBadDays(.days30)
        failed.factors = allFactors().map { row in
            row.id.section == .insulin
                ? GoodBadDaysFactorRow(
                    id: row.id,
                    reference: nil,
                    compared: nil,
                    referenceYes: 0,
                    comparedYes: 0,
                    notLogged: 0,
                    unavailable: true
                )
                : row
        }
        XCTAssertEqual(Layout.factorSections(failed).first { $0.section == .insulin }?.rows, 0)
        XCTAssertEqual(Layout.factorSections(failed).count, Layout.Section.allCases.count)

        for data in [goodBadDays(.days14), goodBadDays(.days30), month, some, failed, goodBadDays(.days90), quarter] {
            for paper in ReportPaper.allCases {
                let pages = Layout.pages(data, paper: paper)
                XCTAssertLessThanOrEqual(pages.count, ReportPlan.goodBadDaysPages)
                XCTAssertEqual(pages.flatMap { $0 }.first, .comparison)
                XCTAssertEqual(pages.flatMap { $0 }.last, .lists)
                XCTAssertEqual(sections(pages).flatMap { $0 }, Layout.factorSections(data).map(\.section))
                // only the first block opens the factors, only the last closes them
                let marks = flags(pages)
                XCTAssertEqual(marks.map { $0[0] }, marks.indices.map { $0 == 0 })
                XCTAssertEqual(marks.map { $0[1] }, marks.indices.map { $0 == marks.count - 1 })
                for blocks in pages {
                    XCTAssertFalse(blocks.isEmpty)
                    XCTAssertLessThanOrEqual(
                        blocks.reduce(0) { $0 + Layout.height($1, data) },
                        Layout.available(paper),
                        "\(paper)"
                    )
                }
            }
        }

        // 14 days: thirds of 5, the same comparison
        let fortnight = goodBadDays(.days14)
        XCTAssertEqual(Layout.pages(fortnight, paper: .letter), [[.comparison, .lists]])
        XCTAssertEqual(Layout.comparisonHeight(fortnight), Layout.comparisonHeight(month))

        // too few days for the comparison: a message in its place, no table and no factors
        var few = Self.fewDays()
        few.factors = allFactors()
        XCTAssertFalse(few.result.thirds.isComparable)
        XCTAssertTrue(Layout.factorSections(few).isEmpty)
        XCTAssertLessThan(Layout.comparisonHeight(few), Layout.comparisonHeight(month))
        XCTAssertEqual(Layout.pages(few, paper: .a4), [[.comparison, .lists]])

        // nothing scored: a line saying so, alone
        let none = Self.nothingScored()
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(Layout.pages(none, paper: .a4), [[.empty]])
    }

    // MARK: - By hour

    @MainActor func testHoursPage() throws {
        let data = try data(request(period: .days14, parts: [.byHour]))
        let hours = Stat.ReportHours(data, units: .mgdL)
        XCTAssertFalse(hours.isEmpty)
        XCTAssertTrue(hours.showsChart && hours.showsTable)
        XCTAssertEqual(hours.rows.map(\.id), Array(0 ..< 24))
        XCTAssertEqual(hours.bars.count, 24)
        XCTAssertEqual(hours.columns.count, 8)
        XCTAssertEqual(hours.columns.map(\.subtitle).prefix(3), ["70–180", "< 70", "> 180"])
        XCTAssertTrue(hours.rows.allSatisfy { $0.cells.count == 8 })
        XCTAssertEqual(hours.ticks.map(\.id), [0, 3, 6, 9, 12, 15, 18, 21])
        XCTAssertEqual(hours.levels, ["0%", "50%", "100%"])
        XCTAssertEqual(hours.legend.map(\.band), [.veryHigh, .high, .inRange, .low, .veryLow])
        // 08:00: always 120
        XCTAssertEqual(hours.rows[8].cells.prefix(7), ["100%", "0%", "0%", "0%", "0%", "0%", "0%"])
        // 14:00: above every day, very high on the rough ones
        XCTAssertEqual(hours.rows[14].cells[0], "0%")
        XCTAssertEqual(hours.rows[14].cells[2], "100%")
        // 03:00: low on the weekends' four days of the 14
        XCTAssertEqual(hours.rows[3].cells[1], "29%")
        XCTAssertEqual(hours.rows[3].cells[4], hours.rows[3].cells[1])
        // the lows' line is its hour's row
        let lowsRow = try XCTUnwrap(hours.rows.first { $0.time == hours.peaks[0].time })
        XCTAssertEqual(hours.peaks[0].detail, "below 70 · " + lowsRow.cells[1] + " of that hour")
        // lows, highs, most in range
        XCTAssertEqual(hours.peaks.map(\.band), [.low, .high, .inRange])
        XCTAssertEqual(hours.peaks.map(\.title), ["Lows", "Highs", "Most in range"])
        XCTAssertTrue(hours.peaks[0].detail.hasPrefix("below 70 · "))
        XCTAssertTrue(hours.peaks[1].detail.hasPrefix("above 180 · 100%"))
        XCTAssertEqual(hours.peaks[2].detail, "100% of that hour in range")
        XCTAssertTrue(hours.note.contains("14 days"))

        // fractional shares (very low 1.3%, low 1.3%, in range 97.4%): below is the sum of the two percents shown, not
        // the rounded sum of the shares, so the row adds up to 100 and "When it happens" says the same
        var fractional = try self.data(request(period: .days30, parts: [.byHour]))
        fractional.hourOfDay = Self.fractionalHours()
        let shares = Stat.ReportHours(fractional, units: .mgdL)
        XCTAssertEqual(Array(shares.rows[5].cells.prefix(7)), ["98%", "2%", "0%", "1%", "1%", "0%", "0%"])
        XCTAssertEqual(shares.peaks.first?.detail, "below 70 · 2% of that hour")
        XCTAssertEqual(shares.peaks.first?.time, shares.rows[5].time)
        XCTAssertEqual(shares.peaks.last?.detail, "98% of that hour in range")
        for row in shares.rows + hours.rows where row.cells[0] != "–" {
            let percents = row.cells.prefix(3).compactMap { Int($0.dropLast()) }
            XCTAssertEqual(percents.count, 3)
            XCTAssertEqual(percents.reduce(0, +), 100, row.time)
        }
        let hour = try XCTUnwrap(Self.fractionalHours().hours.first { $0.hour == 5 })
        XCTAssertEqual(Stat.ReportHours.percent(.below, of: hour), "2%")
        XCTAssertEqual(Stat.ReportHours.percent(.above, of: hour), "0%")

        // the content setting
        var settings = ReportOptions.ByHourSettings()
        settings.content = .chart
        let chart = Stat.ReportHours(try self.data(request(period: .days14, parts: [.byHour], byHour: settings)), units: .mgdL)
        XCTAssertTrue(chart.showsChart)
        XCTAssertFalse(chart.showsTable)
        settings.content = .table
        XCTAssertFalse(settings.showsChart)
        XCTAssertTrue(settings.showsTable)

        // mmol/L beside mg/dL: the same percents, the ranges written in the page's unit
        let both = try self.data(request(period: .days14, parts: [.byHour], units: [.mgdL, .mmolL]))
        let mmol = Stat.ReportHours(both, units: .mmolL)
        XCTAssertEqual(mmol.rows.map(\.cells), hours.rows.map(\.cells))
        XCTAssertNotEqual(mmol.columns.map(\.subtitle), hours.columns.map(\.subtitle))
        XCTAssertTrue(mmol.peaks[0].detail.hasPrefix("below " + StatsFormatting.glucose(70, units: .mmolL)))

        // mmol/L first: the numbers are on its bands, and the mg/dL page after it has the same ones under its labels
        let mmolFirst = try self.data(request(period: .days14, parts: [.byHour], units: [.mmolL, .mgdL]))
        let leading = Stat.ReportHours(mmolFirst, units: .mmolL)
        let trailing = Stat.ReportHours(mmolFirst, units: .mgdL)
        XCTAssertEqual(trailing.rows.map(\.cells), leading.rows.map(\.cells))
        XCTAssertEqual(trailing.peaks.map(\.time), leading.peaks.map(\.time))
        XCTAssertEqual(trailing.columns.map(\.subtitle).prefix(3), ["70–180", "< 70", "> 180"])
        XCTAssertTrue(trailing.peaks[0].detail.hasPrefix("below 70 · "))
        XCTAssertTrue(trailing.legend.contains { $0.text == "In range 70–180" })

        // no result: nothing to show
        let none = Stat.ReportHours(try self.data(request(period: .days14, parts: [.summary])), units: .mgdL)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.rows.count, 0)
    }

    // MARK: - By weekday

    @MainActor func testWeekdaysPage() throws {
        let data = try data(request(period: .days30, parts: [.byWeekday]))
        let weekdays = try XCTUnwrap(Stat.ReportWeekdays(data, units: .mgdL, calendar: Self.calendar))
        // the header says the weeks used: 4 whole weeks to yesterday (Tue 19 Jan)
        XCTAssertTrue(weekdays.header.days.hasPrefix("4 whole weeks to yesterday · "))
        let first = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 12, day: 23)))
        let last = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 19)))
        XCTAssertEqual(weekdays.header.dateRange, Stat.ReportPageHeader.dateRange(first, last, calendar: Self.calendar))
        XCTAssertEqual(weekdays.model.columns.count, 7)
        XCTAssertEqual(weekdays.metric, .inRange)
        XCTAssertTrue(weekdays.heatTitle.hasPrefix("Time in range"))
        XCTAssertEqual(weekdays.legend.steps.count, 5)
        // seven weekdays, eight 3-hour blocks, a value in each
        XCTAssertEqual(weekdays.cells.count, 7)
        XCTAssertTrue(weekdays.cells.allSatisfy { $0.count == 8 })
        XCTAssertTrue(weekdays.cells.flatMap { $0 }.allSatisfy { $0.step != nil && $0.text.hasSuffix("%") })
        // 06:00–09:00 is in range on every weekday
        XCTAssertTrue(weekdays.cells.allSatisfy { $0[2].text == "100%" && $0[2].step == 4 })
        // 00:00–03:00: an hour low on the weekend, at the end of the columns
        XCTAssertEqual(weekdays.cells[0][0].text, "100%")
        XCTAssertEqual(weekdays.cells[6][0].text, "67%")
        XCTAssertNotNil(weekdays.model.workdays)
        XCTAssertNotNil(weekdays.model.weekend)
        XCTAssertEqual(weekdays.model.tableRows.first?.values.count, 7)

        // the other metrics the screen has
        var settings = ReportOptions.ByWeekdaySettings()
        settings.heatMap = .low
        let low = try XCTUnwrap(
            Stat.ReportWeekdays(
                try self.data(request(parts: [.byWeekday], byWeekday: settings)),
                units: .mgdL,
                calendar: Self.calendar
            )
        )
        XCTAssertEqual(low.metric, .low)
        XCTAssertEqual(low.cells[0][0].text, "0%")
        XCTAssertEqual(low.cells[6][0].text, "33%")
        settings.heatMap = .mean
        let mean = try XCTUnwrap(
            Stat.ReportWeekdays(
                try self.data(request(parts: [.byWeekday], byWeekday: settings)),
                units: .mgdL,
                calendar: Self.calendar
            )
        )
        XCTAssertEqual(mean.cells[0][2].text, "120")
        XCTAssertEqual(ReportOptions.ByWeekdaySettings.HeatMap.allCases.map(\.metric), [.inRange, .low, .mean])

        // 90 days: 13 weeks; a view's own 8
        let quarter = try XCTUnwrap(
            Stat.ReportWeekdays(
                try self.data(request(period: .days90, parts: [.byWeekday])),
                units: .mgdL,
                calendar: Self.calendar
            )
        )
        XCTAssertTrue(quarter.header.days.hasPrefix("13 whole weeks to yesterday"))
        let eight = try XCTUnwrap(
            Stat.ReportWeekdays(
                try self.data(request(period: .days90, parts: [.byWeekday], partPeriod: .weeks8)),
                units: .mgdL,
                calendar: Self.calendar
            )
        )
        XCTAssertTrue(eight.header.days.hasPrefix("8 whole weeks to yesterday"))

        // mmol/L beside mg/dL: the same percents; the mean's cells in the page's unit
        let both = try self.data(request(parts: [.byWeekday], units: [.mgdL, .mmolL]))
        let mmol = try XCTUnwrap(Stat.ReportWeekdays(both, units: .mmolL, calendar: Self.calendar))
        XCTAssertEqual(mmol.cells, weekdays.cells)
        XCTAssertEqual(mmol.model.tableRows[1].values, weekdays.model.tableRows[1].values)
        XCTAssertNotEqual(mmol.model.tableRows[2].values, weekdays.model.tableRows[2].values)

        XCTAssertNil(weekdays.emptyNote)

        // the mean's map on both units: the steps are the first unit's on both pages, the key and the values in the
        // page's unit
        settings.heatMap = .mean
        let meanBoth = try self.data(request(parts: [.byWeekday], units: [.mgdL, .mmolL], byWeekday: settings))
        let meanFirst = try XCTUnwrap(Stat.ReportWeekdays(meanBoth, units: .mgdL, calendar: Self.calendar))
        let meanSecond = try XCTUnwrap(Stat.ReportWeekdays(meanBoth, units: .mmolL, calendar: Self.calendar))
        XCTAssertEqual(meanSecond.cells.map { $0.map(\.step) }, meanFirst.cells.map { $0.map(\.step) })
        XCTAssertEqual(meanFirst.cells[0][2].text, "120")
        XCTAssertEqual(meanSecond.cells[0][2].text, StatsFormatting.glucose(120.0, units: .mmolL))
        XCTAssertEqual(meanFirst.legend.steps, ["<110", "110–130", "130–150", "150–170", "≥170"])
        XCTAssertEqual(meanFirst.legend.title, "mg/dL")
        XCTAssertEqual(meanSecond.legend.title, "mmol/L")
        XCTAssertEqual(meanSecond.legend.steps.count, 5)
        XCTAssertEqual(meanSecond.legend.steps.first, "<" + StatsFormatting.glucose(110.0, units: .mmolL))
        XCTAssertEqual(meanSecond.legend.steps.last, "≥" + StatsFormatting.glucose(170.0, units: .mmolL))
        // mmol/L first: its round edges, written in mg/dL on the second page; the same steps again
        let meanFlipped = try self.data(request(parts: [.byWeekday], units: [.mmolL, .mgdL], byWeekday: settings))
        let flippedFirst = try XCTUnwrap(Stat.ReportWeekdays(meanFlipped, units: .mmolL, calendar: Self.calendar))
        let flippedSecond = try XCTUnwrap(Stat.ReportWeekdays(meanFlipped, units: .mgdL, calendar: Self.calendar))
        XCTAssertEqual(flippedFirst.legend, flippedFirst.model.legends[.mean])
        XCTAssertEqual(flippedFirst.legend.steps, ["<6", "6–7", "7–8", "8–9", "≥9"])
        XCTAssertEqual(flippedSecond.cells.map { $0.map(\.step) }, flippedFirst.cells.map { $0.map(\.step) })
        XCTAssertEqual(flippedSecond.legend.steps, ["<108", "108–126", "126–144", "144–162", "≥162"])
        XCTAssertEqual(flippedSecond.legend.title, "mg/dL")
        XCTAssertEqual(flippedSecond.cells[0][2].text, "120")
        // the other metrics' keys are the screen's on every page
        XCTAssertNil(Stat.ReportWeekdays.legend(.inRange, of: .mmolL, in: .mgdL))
        XCTAssertNil(Stat.ReportWeekdays.legend(.mean, of: .mgdL, in: .mgdL))
        // in range on mmol/L first: the mg/dL page has the same cells and numbers under its own labels
        let inRangeFlipped = try self.data(request(parts: [.byWeekday], units: [.mmolL, .mgdL]))
        let rangeFirst = try XCTUnwrap(Stat.ReportWeekdays(inRangeFlipped, units: .mmolL, calendar: Self.calendar))
        let rangeSecond = try XCTUnwrap(Stat.ReportWeekdays(inRangeFlipped, units: .mgdL, calendar: Self.calendar))
        XCTAssertEqual(rangeSecond.cells, rangeFirst.cells)
        XCTAssertEqual(rangeSecond.model.tableRows[0].values, rangeFirst.model.tableRows[0].values)
        XCTAssertEqual(rangeSecond.model.tableRows[1].values, weekdays.model.tableRows[1].values)
        XCTAssertEqual(rangeSecond.model.tableRows[2].values, weekdays.model.tableRows[2].values)
        XCTAssertTrue(rangeSecond.model.barsFootnote.contains("mg/dL"))

        // weeks without a reading: a line in place of the bars and the map
        var blank = try self.data(request(parts: [.byWeekday]))
        blank.weekday = Self.emptyWeekday()
        let empty = try XCTUnwrap(Stat.ReportWeekdays(blank, units: .mgdL, calendar: Self.calendar))
        XCTAssertEqual(empty.emptyNote, "No CGM data in this period")
        XCTAssertTrue(empty.header.days.hasPrefix("4 whole weeks to yesterday"))
        XCTAssertTrue(empty.cells.flatMap { $0 }.allSatisfy { $0.step == nil && $0.text == "–" })
        XCTAssertNil(empty.fewNote)

        // a period too short for it: no page
        XCTAssertNil(
            Stat
                .ReportWeekdays(
                    try self.data(request(period: .days14, parts: [.byWeekday])),
                    units: .mgdL,
                    calendar: Self.calendar
                )
        )
    }

    // MARK: - Weekly

    @MainActor func testWeeksPage() throws {
        let data = try data(request(period: .days30, parts: [.weekly], units: [.mgdL, .mmolL]))
        XCTAssertEqual(data.weekly.map(\.units), [.mgdL, .mmolL])
        let weeks = try XCTUnwrap(Stat.ReportWeeks(data, units: .mgdL, calendar: Self.calendar))
        // 13 weeks whatever the report's period, said in the header
        XCTAssertEqual(weeks.header.days, "13 weeks, the last one to today")
        let first = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        XCTAssertEqual(
            weeks.header.dateRange,
            Stat.ReportPageHeader.dateRange(first, Self.calendar.startOfDay(for: Self.now), calendar: Self.calendar)
        )
        XCTAssertEqual(weeks.model.rows.count, 13)
        XCTAssertTrue(weeks.model.rows.allSatisfy { $0.values != nil })
        XCTAssertEqual(weeks.columns.map(\.title), ["In range", "Δ", "Mean", "Δ"])
        XCTAssertEqual(weeks.columns[0].subtitle, "70–180")
        XCTAssertEqual(weeks.columns[2].subtitle, "mg/dL")
        XCTAssertTrue(weeks.inRangeTitle.hasPrefix("In range 70–180"))
        XCTAssertEqual(weeks.model.inRangePlot.slots.count, 13)
        XCTAssertEqual(weeks.model.meanPlot.slots.count, 13)
        XCTAssertTrue(weeks.note.contains("13 weeks"))

        // the other unit's page: its own result, the same in-range percents and Δ, the means in its unit
        let mmol = try XCTUnwrap(Stat.ReportWeeks(data, units: .mmolL, calendar: Self.calendar))
        XCTAssertEqual(mmol.model.rows.map { $0.values?.inRange }, weeks.model.rows.map { $0.values?.inRange })
        XCTAssertEqual(mmol.model.rows.map { $0.values?.inRangeDelta }, weeks.model.rows.map { $0.values?.inRangeDelta })
        XCTAssertNotEqual(mmol.model.rows.map { $0.values?.mean }, weeks.model.rows.map { $0.values?.mean })
        XCTAssertEqual(mmol.columns[2].subtitle, "mmol/L")
        XCTAssertEqual(mmol.header, weeks.header)
        XCTAssertEqual(Stat.ReportWeeks.result(data, units: .mmolL)?.units, .mmolL)
        XCTAssertNil(weeks.emptyNote)

        // a week without a reading: its row says so, the others stay
        let gapStart = Self.now.addingTimeInterval(-.days(30))
        let gapEnd = Self.now.addingTimeInterval(-.days(16))
        var gappy = data
        gappy.weekly = [Self.weekly(of: Self.points.filter { $0.time < gapStart || $0.time >= gapEnd })]
        let gap = try XCTUnwrap(Stat.ReportWeeks(gappy, units: .mgdL, calendar: Self.calendar))
        XCTAssertNil(gap.emptyNote)
        XCTAssertEqual(gap.model.rows.count, 13)
        XCTAssertGreaterThanOrEqual(gap.model.rows.filter { $0.values == nil }.count, 1)
        XCTAssertLessThan(gap.model.inRangePlot.bars.count, 13)
        XCTAssertEqual(gap.model.inRangePlot.slots.count, 13)

        // every week the same: no Δ, and the charts still have a scale
        var flat = data
        flat.weekly = [Self.weekly(of: Self.points.map { GlucosePoint(time: $0.time, mgdl: 120) })]
        let equal = try XCTUnwrap(Stat.ReportWeeks(flat, units: .mgdL, calendar: Self.calendar))
        XCTAssertNil(equal.emptyNote)
        XCTAssertTrue(equal.model.rows.allSatisfy { $0.values?.inRange == "100%" && $0.values?.inRangeDelta == "±0" })
        XCTAssertLessThan(equal.model.inRangePlot.domain.lowerBound, equal.model.inRangePlot.domain.upperBound)
        XCTAssertLessThan(equal.model.meanPlot.domain.lowerBound, equal.model.meanPlot.domain.upperBound)

        // no reading in the 13 weeks: a line in place of the charts and the table
        var blank = data
        blank.weekly = [Self.weekly(of: [])]
        let empty = try XCTUnwrap(Stat.ReportWeeks(blank, units: .mgdL, calendar: Self.calendar))
        XCTAssertEqual(empty.emptyNote, "No CGM data in this period")
        XCTAssertEqual(empty.header.days, "13 weeks, the last one to today")

        // without the part's result: no page
        XCTAssertNil(
            Stat
                .ReportWeeks(
                    try self.data(request(period: .days14, parts: [.byHour, .weekly])),
                    units: .mgdL,
                    calendar: Self.calendar
                )
        )
    }

    // MARK: - Good & bad days

    @MainActor func testGoodBadDaysPages() throws {
        let data = try data(request(period: .days30, parts: [.goodBadDays]))
        let first = try XCTUnwrap(Stat.ReportGoodBadDays(data, page: page(.goodBadDays), calendar: Self.calendar))
        // without factor rows: the comparison and the days on one page
        XCTAssertEqual(first.blocks, [.comparison, .lists])
        XCTAssertEqual(first.content.factorSections.flatMap(\.rows).count, 0)
        // with every factor row: what was different starts under the comparison and goes on, with the days, on the
        // second page
        var full = data
        full.goodBadDays?.factors = allFactors()
        let front = try XCTUnwrap(Stat.ReportGoodBadDays(full, page: page(.goodBadDays), calendar: Self.calendar))
        let second = try XCTUnwrap(Stat.ReportGoodBadDays(full, page: page(.goodBadDays, index: 1), calendar: Self.calendar))
        XCTAssertEqual(front.blocks, ReportGoodBadDaysLayout.pages(try XCTUnwrap(full.goodBadDays), paper: .a4)[0])
        XCTAssertEqual(front.blocks.first, .comparison)
        XCTAssertEqual(front.blocks.count, 2)
        XCTAssertEqual(second.blocks.count, 2)
        XCTAssertEqual(second.blocks.last, .lists)
        XCTAssertEqual(second.header, first.header)
        // the sections the plan counted are the ones the page has: every one, with as many rows
        let planned = ReportGoodBadDaysLayout.factorSections(try XCTUnwrap(full.goodBadDays))
        XCTAssertEqual(second.content.factorSections.map(\.id), planned.map(\.section))
        XCTAssertEqual(second.content.factorSections.map(\.rows.count), planned.map(\.rows))
        // 10 days in each third: not limited, so no such note under the chart
        XCTAssertFalse(first.content.isLimited)
        XCTAssertFalse(first.chartNote.contains(first.model.limitedNote))
        XCTAssertTrue(first.chartNote.hasPrefix("Lines: each group's median."))
        XCTAssertTrue(first.chartNote.contains(try XCTUnwrap(first.content.caption)))
        XCTAssertNil(first.emptyNote)

        // a section whose read failed: its title with why, no row; the plan has its line
        var failed = data
        failed.goodBadDays?.factors = allFactors().map { row in
            row.id.section == .insulin
                ? GoodBadDaysFactorRow(
                    id: row.id,
                    reference: nil,
                    compared: nil,
                    referenceYes: 0,
                    comparedYes: 0,
                    notLogged: 0,
                    unavailable: true
                )
                : row
        }
        let partly = try XCTUnwrap(Stat.ReportGoodBadDays(failed, page: page(.goodBadDays), calendar: Self.calendar))
        let insulin = try XCTUnwrap(partly.content.factorSections.first { $0.id == .insulin })
        XCTAssertEqual(insulin.rows.count, 0)
        XCTAssertNotNil(insulin.unavailable)
        XCTAssertEqual(
            partly.content.factorSections.map(\.id),
            ReportGoodBadDaysLayout.factorSections(try XCTUnwrap(failed.goodBadDays)).map(\.section)
        )

        // 30 complete days to yesterday, all scored
        XCTAssertEqual(first.header.days, "30 complete days to yesterday · 30 with enough CGM data")
        let start = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2026, month: 12, day: 21)))
        let end = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 19)))
        XCTAssertEqual(first.header.dateRange, Stat.ReportPageHeader.dateRange(start, end, calendar: Self.calendar))

        let content = first.content
        XCTAssertTrue(content.isComparable)
        XCTAssertNil(content.message)
        XCTAssertEqual(content.reference.dayCount, 10)
        XCTAssertEqual(content.compared.dayCount, 10)
        XCTAssertEqual(content.reference.days.count, 10)
        XCTAssertFalse(content.reference.points.isEmpty)
        XCTAssertFalse(content.compared.points.isEmpty)
        XCTAssertEqual(content.glucoseRows.count, GoodBadDaysResult.GlucoseRowID.allCases.count)
        XCTAssertTrue(first.rangeLegend.hasPrefix("Range 70–180"))
        XCTAssertFalse(first.griNote.isEmpty)
        // the rough days (every third) are the worst third
        XCTAssertTrue(content.compared.days.allSatisfy { day in
            Self.calendar.component(.day, from: day.id) % 3 == 0
        })

        // mmol/L beside mg/dL: the same days in each third, the same GRI; the glucose rows in the page's unit
        let both = try self.data(request(period: .days30, parts: [.goodBadDays], units: [.mgdL, .mmolL]))
        let mmol = try XCTUnwrap(
            Stat.ReportGoodBadDays(both, page: page(.goodBadDays, units: .mmolL), calendar: Self.calendar)
        )
        XCTAssertEqual(mmol.content.reference.days.map(\.id), content.reference.days.map(\.id))
        XCTAssertEqual(mmol.content.compared.days.map(\.gri), content.compared.days.map(\.gri))
        XCTAssertEqual(mmol.content.glucoseRows.first?.reference, content.glucoseRows.first?.reference)
        XCTAssertTrue(mmol.rangeLegend.contains("mmol/L"))

        // mmol/L first: the days are grouped on its bands once, and the mg/dL page after it has the same days and
        // figures under its own labels
        let flipped = try self.data(request(period: .days30, parts: [.goodBadDays], units: [.mmolL, .mgdL]))
        let leading = try XCTUnwrap(
            Stat.ReportGoodBadDays(flipped, page: page(.goodBadDays, units: .mmolL), calendar: Self.calendar)
        )
        let trailing = try XCTUnwrap(
            Stat.ReportGoodBadDays(flipped, page: page(.goodBadDays, units: .mgdL), calendar: Self.calendar)
        )
        XCTAssertEqual(trailing.content.reference.days.map(\.id), leading.content.reference.days.map(\.id))
        XCTAssertEqual(trailing.content.compared.days.map(\.gri), leading.content.compared.days.map(\.gri))
        XCTAssertEqual(trailing.content.compared.days.map(\.detail), leading.content.compared.days.map(\.detail))
        XCTAssertEqual(trailing.content.counts, leading.content.counts)
        XCTAssertEqual(trailing.content.glucoseRows.first?.reference, leading.content.glucoseRows.first?.reference)
        XCTAssertEqual(trailing.content.glucoseRows[1].compared.value, leading.content.glucoseRows[1].compared.value)
        XCTAssertTrue(trailing.rangeLegend.hasPrefix("Range 70–180 mg/dL"))
        XCTAssertTrue(leading.rangeLegend.contains("mmol/L"))

        // too few scored days: no comparison, a message in its place and the days under it
        var sparse = try self.data(request(period: .days14, parts: [.goodBadDays]))
        sparse.goodBadDays = Self.fewDays()
        let few = try XCTUnwrap(Stat.ReportGoodBadDays(sparse, page: page(.goodBadDays), calendar: Self.calendar))
        XCTAssertFalse(few.content.isComparable)
        XCTAssertNotNil(few.content.message)
        XCTAssertEqual(few.blocks, [.comparison, .lists])

        // nothing scored: a line saying so, alone on the page
        var blank = try self.data(request(period: .days30, parts: [.goodBadDays]))
        blank.goodBadDays = Self.nothingScored()
        let empty = try XCTUnwrap(Stat.ReportGoodBadDays(blank, page: page(.goodBadDays), calendar: Self.calendar))
        XCTAssertEqual(empty.blocks, [.empty])
        XCTAssertEqual(empty.emptyNote, "No day in this period has enough CGM data to be scored: the days end yesterday")
        XCTAssertEqual(blank.pageCount(of: .goodBadDays, calendar: Self.calendar), 1)

        // 14 days: thirds of 5, compared, on one page without factor rows
        let short = try XCTUnwrap(
            Stat.ReportGoodBadDays(
                try self.data(request(period: .days14, parts: [.goodBadDays])),
                page: page(.goodBadDays),
                calendar: Self.calendar
            )
        )
        XCTAssertTrue(short.content.isComparable)
        XCTAssertNil(short.content.message)
        XCTAssertEqual(short.content.reference.days.count, 5)
        XCTAssertEqual(short.blocks, [.comparison, .lists])
        // under 10 days in a group: the first page says under the chart that the figures are provisional
        XCTAssertTrue(short.content.isLimited)
        XCTAssertTrue(short.chartNote.hasSuffix(short.model.limitedNote))
        XCTAssertEqual(short.header.days, "14 complete days to yesterday · 14 with enough CGM data")

        // 7 days: no result, no page
        XCTAssertNil(
            Stat.ReportGoodBadDays(
                try self.data(request(period: .days7, parts: [.goodBadDays])),
                page: page(.goodBadDays),
                calendar: Self.calendar
            )
        )
    }

    /// A page's own header replaces the report's period in the page's frame.
    @MainActor func testPartHeadersInTheChrome() throws {
        let data = try data(request())
        let pages = data.pages(calendar: Self.calendar)
        func chrome(_ index: Int) throws -> Stat.ReportPageChrome {
            let content = try XCTUnwrap(Stat.ReportPageContent(data, page: pages[index], calendar: Self.calendar))
            return Stat.ReportPageChrome(
                data,
                page: pages[index],
                index: index,
                count: pages.count,
                version: "9.9.9",
                calendar: Self.calendar,
                header: content.header
            )
        }
        // By hour: the report's 30 days
        let hours = try chrome(0)
        XCTAssertEqual(hours.title, "By hour")
        XCTAssertEqual(hours.days, "30 of 30 days with data")
        XCTAssertTrue(try chrome(1).days.hasPrefix("4 whole weeks to yesterday"))
        XCTAssertEqual(try chrome(2).days, "13 weeks, the last one to today")
        XCTAssertTrue(try chrome(3).days.hasPrefix("30 complete days to yesterday"))
        XCTAssertEqual(try chrome(3).title, "Good & bad days")
        XCTAssertNotEqual(try chrome(1).dateRange, hours.dateRange)
        XCTAssertNotEqual(try chrome(2).dateRange, hours.dateRange)
        XCTAssertEqual(try chrome(3).pageNumber, "Page 4 of 4")
    }

    // MARK: - Settings

    func testPatternSettings() {
        typealias Key = ReportPreferences.Key
        let name = "test-report-patterns-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = ReportPreferences(defaults: defaults)
        XCTAssertEqual(store.byHour.content, .chartAndTable)
        XCTAssertEqual(store.byWeekday.heatMap, .inRange)

        var hour = ReportOptions.ByHourSettings()
        hour.content = .table
        store.byHour = hour
        var weekdays = ReportOptions.ByWeekdaySettings()
        weekdays.heatMap = .mean
        store.byWeekday = weekdays
        let next = ReportPreferences(defaults: defaults)
        XCTAssertEqual(next.byHour, hour)
        XCTAssertEqual(next.byWeekday, weekdays)
        XCTAssertEqual(defaults.string(forKey: Key.hourContent), "table")
        XCTAssertEqual(defaults.string(forKey: Key.weekdayHeatMap), "mean")
        XCTAssertTrue(Key.hourContent.hasPrefix("iAPS.reports."))
        XCTAssertTrue(Key.weekdayHeatMap.hasPrefix("iAPS.reports."))
        let options = next.options(userUnits: .mgdL, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(options.byHour, hour)
        XCTAssertEqual(options.byWeekday, weekdays)

        // what the choices don't offer: the defaults
        defaults.set("everything", forKey: Key.hourContent)
        defaults.set("above", forKey: Key.weekdayHeatMap)
        XCTAssertEqual(store.byHour.content, .chartAndTable)
        XCTAssertEqual(store.byWeekday.heatMap, .inRange)
        defaults.set(3, forKey: Key.hourContent)
        XCTAssertEqual(store.byHour.content, .chartAndTable)

        // the four parts are offered, with settings for By hour and By weekday only
        XCTAssertTrue(ReportPart.byHour.hasSettings && ReportPart.byWeekday.hasSettings)
        XCTAssertFalse(ReportPart.weekly.hasSettings || ReportPart.goodBadDays.hasSettings)
        store.parts = [.byHour, .byWeekday, .weekly, .goodBadDays]
        XCTAssertEqual(store.parts, [.byHour, .byWeekday, .weekly, .goodBadDays])
    }

    // MARK: - The builder

    /// The provider's calls a report makes, faked. Every read is recorded with the bands it was given; the days' read
    /// answers differently each time it is asked (a reading coming in between two reads), so a report that read
    /// Weekly's days once per unit would print two different pages.
    private actor FakeSource: ReportDataSource {
        typealias Fixtures = StatsReportPatternsTests

        private(set) var reads: [String] = []
        private(set) var bands: [StatsBands] = []
        private(set) var begun = 0
        private(set) var ended = 0
        private var dayReads = 0
        /// answers as a store without readings
        var isEmpty = false

        func empty() { isEmpty = true }

        func beginSession() { begun += 1 }
        func endSession() { ended += 1 }

        func reportProfile(_ period: StatsPeriod, bands: StatsBands) -> Stat.AGPResult {
            reads.append("profile \(period.rawValue)")
            self.bands.append(bands)
            return Stat.AGPResult(bins: [], points: [], axis: 40 ... 300, summary: Fixtures.summary(period))
        }

        func reportInsulin(_: StatsPeriod) throws -> InsulinPeriod { throw CancellationError() }
        func reportMeals(_: StatsPeriod, factor _: Double) throws -> MealPeriod { throw CancellationError() }

        func reportDays(_ period: StatsPeriod) -> PeriodDays {
            reads.append("days \(period.rawValue)")
            dayReads += 1
            let (window, days) = Fixtures.aggregates(period)
            // a later read has lost its newest days
            let kept = isEmpty ? [] : Array(days.dropLast((dayReads - 1) * 20))
            return PeriodDays(window: window, endRule: .stalled, days: kept)
        }

        func reportTrace(day _: Date, bands: StatsBands) -> ReportDayTrace {
            self.bands.append(bands)
            return ReportDayTrace(points: [], summary: Fixtures.summary(.days7))
        }

        func reportInsulinInput(_: DateInterval, now _: Date) -> InsulinInput { InsulinInput() }

        func reportHourOfDay(_ period: StatsPeriod, bands: StatsBands) -> Stat.HourOfDayResult {
            reads.append("hours \(period.rawValue)")
            self.bands.append(bands)
            if isEmpty {
                return Stat.HourOfDayResult(
                    buckets: [],
                    summary: GlucoseStatsEngine.summary(
                        days: [],
                        window: Fixtures.aggregates(period).window,
                        endRule: .stalled,
                        period: period,
                        bands: bands
                    ),
                    bands: bands
                )
            }
            return Fixtures.hourOfDay(period)
        }

        func reportWeekday(_ period: StatsPeriod, bands: StatsBands) -> Stat.WeekdayResult {
            reads.append("weekday \(period.rawValue)")
            self.bands.append(bands)
            return isEmpty ? Fixtures.emptyWeekday() : Fixtures.weekday(period)
        }

        func reportGoodBadDays(_ period: StatsPeriod, bands: StatsBands, allowOneMinuteLoop: Bool) -> Stat.GoodBadDaysData {
            reads.append("goodBadDays \(period.rawValue) \(allowOneMinuteLoop)")
            self.bands.append(bands)
            return isEmpty ? Fixtures.nothingScored() : Fixtures.goodBadDays(period)
        }
    }

    /// Each part read once inside the session, with its own period and the first unit's bands; a part the period can't
    /// hold isn't read.
    func testBuilderReadsTheParts() async throws {
        let source = FakeSource()
        let data = try await Stat.ReportBuilder.build(
            request(period: .days90, units: [.mgdL, .mmolL]),
            source: source,
            now: Self.now,
            calendar: Self.calendar
        )
        let reads = await source.reads
        XCTAssertEqual(
            reads,
            [
                "profile days90",
                "hours days90",
                "weekday weeks13",
                "days weeks13",
                "goodBadDays days90 false"
            ]
        )
        let sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions, [1, 1])
        XCTAssertNotNil(data.hourOfDay)
        XCTAssertEqual(data.weekday?.weeks, 13)
        XCTAssertEqual(data.weekly.map(\.units), [.mgdL, .mmolL])
        XCTAssertEqual(data.goodBadDays?.period, .days90)
        // every read on the first unit's bands
        let bands = await source.bands
        XCTAssertEqual(bands.count, 4)
        XCTAssertTrue(bands.allSatisfy { $0 == Stat.ReportBuilder.standardBands(.mgdL) })
        XCTAssertEqual(data.weekly.map(\.summary.bands), Array(repeating: Stat.ReportBuilder.standardBands(.mgdL), count: 2))

        // mmol/L first: its bands for every read, and for Weekly's summary
        let flipped = FakeSource()
        let mmolFirst = try await Stat.ReportBuilder.build(
            request(period: .days90, units: [.mmolL, .mgdL]),
            source: flipped,
            now: Self.now,
            calendar: Self.calendar
        )
        let flippedBands = await flipped.bands
        XCTAssertEqual(flippedBands.count, 4)
        XCTAssertTrue(flippedBands.allSatisfy { $0 == Stat.ReportBuilder.standardBands(.mmolL) })
        XCTAssertTrue(mmolFirst.weekly.allSatisfy { $0.summary.bands == Stat.ReportBuilder.standardBands(.mmolL) })

        // 7 days: only By hour is read, the report is still made
        let short = FakeSource()
        let week = try await Stat.ReportBuilder.build(
            request(period: .days7),
            source: short,
            now: Self.now,
            calendar: Self.calendar
        )
        let shortReads = await short.reads
        XCTAssertEqual(shortReads, ["profile days7", "hours days7"])
        XCTAssertEqual(week.pages(calendar: Self.calendar).map(\.part), [.byHour])
    }

    /// Weekly on both units comes from one read of the weeks' days: the two pages can't differ in anything but how the
    /// means are written.
    @MainActor func testWeeklyIsReadOnce() async throws {
        let source = FakeSource()
        let data = try await Stat.ReportBuilder.build(
            request(period: .days30, parts: [.byHour, .weekly], units: [.mgdL, .mmolL]),
            source: source,
            now: Self.now,
            calendar: Self.calendar
        )
        let reads = await source.reads
        XCTAssertEqual(reads.filter { $0.hasPrefix("days") }, ["days weeks13"])
        XCTAssertEqual(data.weekly.count, 2)
        XCTAssertEqual(data.weekly[0].summary, data.weekly[1].summary)
        XCTAssertEqual(data.weekly[0].weeks.map(\.days), data.weekly[1].weeks.map(\.days))
        XCTAssertEqual(data.weekly[0].weeks.map(\.hasData), data.weekly[1].weeks.map(\.hasData))
        let first = try XCTUnwrap(Stat.ReportWeeks(data, units: .mgdL, calendar: Self.calendar))
        let second = try XCTUnwrap(Stat.ReportWeeks(data, units: .mmolL, calendar: Self.calendar))
        XCTAssertEqual(second.header, first.header)
        XCTAssertEqual(second.model.rows.map(\.title), first.model.rows.map(\.title))
        XCTAssertEqual(second.model.rows.map { $0.values?.inRange }, first.model.rows.map { $0.values?.inRange })
        XCTAssertEqual(second.model.rows.map { $0.values?.inRangeDelta }, first.model.rows.map { $0.values?.inRangeDelta })
        XCTAssertEqual(second.model.inRangeAverage, first.model.inRangeAverage)
        XCTAssertEqual(second.model.inRangePlot, first.model.inRangePlot)
        XCTAssertTrue(first.model.rows.allSatisfy { $0.values != nil })
        // the fake's second read would have lost 20 days: it was never asked
        let again = await source.reportDays(.weeks13)
        XCTAssertLessThan(again.days.count, 91)
    }

    /// A view's own "Export PDF" of one of the four parts reads that part alone: no profile of the report's period.
    func testOwnPartReads() async throws {
        func build(_ request: Stat.ReportRequest, _ source: FakeSource) async throws -> Stat.ReportData {
            try await Stat.ReportBuilder.build(request, source: source, now: Self.now, calendar: Self.calendar)
        }
        func single(_ part: ReportPart, period: StatsPeriod, partPeriod: StatsPeriod?) -> Stat.ReportRequest {
            Stat.ReportRequest(
                period: period,
                parts: [part],
                units: [.mmolL, .mgdL],
                hbA1cUnit: .percent,
                paper: .a4,
                allowOneMinuteLoop: true,
                partPeriod: partPeriod
            )
        }
        let source = FakeSource()
        let weekday = try await build(single(.byWeekday, period: .days90, partPeriod: .weeks8), source)
        let days = try await build(single(.goodBadDays, period: .days30, partPeriod: .days14), source)
        let weekly = try await build(single(.weekly, period: .days7, partPeriod: .days7), source)
        let hours = try await build(single(.byHour, period: .days90, partPeriod: .days90), source)
        let reads = await source.reads
        XCTAssertEqual(reads, ["weekday weeks8", "goodBadDays days14 true", "days weeks13", "hours days90"])
        let bands = await source.bands
        XCTAssertTrue(bands.allSatisfy { $0 == Stat.ReportBuilder.standardBands(.mmolL) })
        let sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions, [4, 4])
        XCTAssertEqual(weekday.weekday?.weeks, 8)
        XCTAssertEqual(weekday.pages(calendar: Self.calendar).map(\.part), [.byWeekday, .byWeekday])
        XCTAssertEqual(days.goodBadDays?.period, .days14)
        // Weekly alone is printed whatever the period
        XCTAssertEqual(weekly.weekly.count, 2)
        XCTAssertEqual(weekly.pages(calendar: Self.calendar).map(\.part), [.weekly, .weekly])
        XCTAssertEqual(hours.summary, hours.hourOfDay?.summary)

        // the file is named by the part's own days where its header states them
        func name(_ data: Stat.ReportData) -> String {
            let days = data.fileDays(calendar: Self.calendar)
            return ReportPDFWriter.fileName(first: days.first, last: days.last, calendar: Self.calendar)
        }
        XCTAssertEqual(name(weekday), "iAPS report 2026-11-25 – 2027-01-19.pdf")
        XCTAssertEqual(name(days), "iAPS report 2027-01-06 – 2027-01-19.pdf")
        XCTAssertEqual(name(weekly), "iAPS report 2026-10-22 – 2027-01-20.pdf")
        XCTAssertEqual(name(hours), "iAPS report 2026-10-23 – 2027-01-20.pdf")
        // a report of several parts: its period
        let report = try await build(request(period: .days30), FakeSource())
        XCTAssertEqual(name(report), "iAPS report 2026-12-22 – 2027-01-20.pdf")

        // nothing in the part: no report
        for part in [ReportPart.byHour, .byWeekday, .weekly, .goodBadDays] {
            let blank = FakeSource()
            await blank.empty()
            do {
                _ = try await build(single(part, period: .days30, partPeriod: nil), blank)
                XCTFail("\(part)")
            } catch {
                XCTAssertEqual(error as? Stat.ReportError, .noData, "\(part)")
            }
            let blankReads = await blank.reads
            XCTAssertFalse(blankReads.contains { $0.hasPrefix("profile") })
        }
    }

    /// A view's own request mirrors its screen: By weekday's weeks and the metric shown, Good & bad days' days, Weekly
    /// whatever the period; a report made on the Reports screen keeps the saved settings.
    @MainActor func testPartRequests() throws {
        let name = "test-report-part-requests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: parent)
        }
        let preferences = ReportPreferences(defaults: defaults)
        var saved = ReportOptions.ByWeekdaySettings()
        saved.heatMap = .low
        preferences.byWeekday = saved
        var hour = ReportOptions.ByHourSettings()
        hour.content = .table
        preferences.byHour = hour
        preferences.period = .days7
        let exporter = Stat.ReportExporter(preferences: preferences, parent: parent, calendar: { Self.calendar })
        func context(_ period: StatsPeriod, metric: WeekdayMetric? = nil) -> Stat.ReportContext {
            Stat.ReportContext(
                source: FakeSource(),
                userUnits: .mgdL,
                hbA1cUnit: .percent,
                carbEquivalentFactor: 0.5,
                screenPeriod: period,
                allowOneMinuteLoop: true,
                weekdayMetric: metric
            )
        }
        // By weekday at 8 weeks, its map showing the mean
        let weekday = exporter.partRequest(.byWeekday, context: context(.weeks8, metric: .mean))
        XCTAssertEqual(weekday.parts, [.byWeekday])
        XCTAssertEqual(weekday.weekdayPeriod, .weeks8)
        XCTAssertEqual(weekday.byWeekday.heatMap, .mean)
        XCTAssertEqual(weekday.ownPart, .byWeekday)
        XCTAssertEqual(exporter.partRequest(.byWeekday, context: context(.weeks4, metric: .inRange)).byWeekday.heatMap, .inRange)
        // without a screen's metric: the saved one
        XCTAssertEqual(exporter.partRequest(.byWeekday, context: context(.weeks4)).byWeekday.heatMap, .low)
        // the saved setting isn't touched, and a report made on the Reports screen uses it
        XCTAssertEqual(preferences.byWeekday.heatMap, .low)
        let screen = context(.weeks8, metric: .mean)
        let report = screen.request(preferences.options(userUnits: .mgdL))
        XCTAssertEqual(report.byWeekday.heatMap, .low)
        XCTAssertNil(report.partPeriod)
        XCTAssertNil(report.ownPart)
        // By hour keeps its saved content; the screen's metric is By weekday's alone
        let hours = exporter.partRequest(.byHour, context: context(.days30, metric: .mean))
        XCTAssertEqual(hours.byHour.content, .table)
        XCTAssertEqual(hours.byWeekday.heatMap, .low)
        XCTAssertEqual(hours.period, .days30)
        // Weekly is printed whatever the period on screen and the saved one
        let weekly = exporter.partRequest(.weekly, context: context(.days7))
        XCTAssertTrue(weekly.printsWeekly)
        XCTAssertEqual(weekly.ownPart, .weekly)
        // Good & bad days: the screen's days
        let days = exporter.partRequest(.goodBadDays, context: context(.days14))
        XCTAssertEqual(days.goodBadDaysPeriod, .days14)
        XCTAssertTrue(days.allowOneMinuteLoop)
        // a day's chart isn't one of the parts read alone
        XCTAssertNil(exporter.partRequest(.dailyCharts, day: Self.now, context: context(.days7)).ownPart)
        XCTAssertNil(exporter.partRequest(.daysTable, context: context(.days7)).ownPart)
    }

    // MARK: - The written file

    private func plainText(_ document: PDFDocument) -> String {
        (document.string ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// All four parts on A4: five portrait pages, with their titles, headers and key strings.
    @MainActor func testWritesThePatternParts() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-report-patterns-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }

        var data = try data(request())
        data.goodBadDays?.factors = allFactors()
        let output = try await ReportPDFWriter.write(data, version: "9.9.9", parent: parent, calendar: Self.calendar)
        let document = try XCTUnwrap(PDFDocument(url: output.url))
        XCTAssertEqual(document.pageCount, 5)
        for index in 0 ..< 5 {
            let size = try XCTUnwrap(document.page(at: index)).bounds(for: .mediaBox).size
            XCTAssertEqual(size.width, 595, accuracy: 0.5)
            XCTAssertEqual(size.height, 842, accuracy: 0.5)
        }
        let text = plainText(document)
        for expected in [
            "By hour",
            "When it happens",
            "Most in range",
            "By weekday",
            "4 whole weeks to yesterday",
            "Weekdays vs weekends",
            "Weekly",
            "13 weeks, the last one to today",
            "Good & bad days",
            "30 complete days to yesterday",
            "Glucose on those days",
            "What was different on those days",
            "The days",
            "Page 5 of 5",
            "Time in ranges is time-weighted"
        ] {
            XCTAssertTrue(text.contains(expected), "missing \"\(expected)\"")
        }

        // Letter, both units, a 7-day period: only By hour, twice
        let short = try self.data(request(period: .days7, units: [.mgdL, .mmolL], paper: .letter))
        let shortOutput = try await ReportPDFWriter.write(short, version: "9.9.9", parent: parent, calendar: Self.calendar)
        let shortDocument = try XCTUnwrap(PDFDocument(url: shortOutput.url))
        XCTAssertEqual(shortDocument.pageCount, 2)
        let size = try XCTUnwrap(shortDocument.page(at: 0)).bounds(for: .mediaBox).size
        XCTAssertEqual(size.width, 612, accuracy: 0.5)
        XCTAssertEqual(size.height, 792, accuracy: 0.5)
        XCTAssertTrue(plainText(shortDocument).contains("mmol/L"))
    }
}
