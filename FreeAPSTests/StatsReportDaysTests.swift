import CoreData
@testable import FreeAPS
import PDFKit
import XCTest

/// The PDF reports' Days table and Daily charts: the rows and their averages, the pages, the charts' days and panels,
/// the kept settings, and the written file.
final class StatsReportDaysTests: XCTestCase {
    /// Europe/Berlin, weeks from Monday
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// 2026-10-20 00:00 Europe/Berlin, a Tuesday; summer time ends on the 25th (a 25-hour day)
    private static let day0 = Date(timeIntervalSince1970: 1_792_447_200)

    // MARK: - Fixtures

    private func dayStart(_ offset: Int) -> Date {
        Self.calendar.date(byAdding: .day, value: offset, to: Self.day0)!
    }

    private func dayInterval(_ offset: Int) -> DateInterval {
        DateInterval(start: dayStart(offset), end: dayStart(offset + 1))
    }

    /// A day with the given shares (0...1) of its length at the given values; without any: no readings.
    private func aggregate(_ offset: Int, _ values: [(mgdl: Int16, share: Double)] = []) -> DayAggregate {
        let day = dayInterval(offset)
        var histogram = GlucoseHistogram()
        for value in values where value.share > 0 {
            let seconds = day.duration * value.share
            histogram.add(WeightedPoint(time: day.start, mgdl: value.mgdl, span: seconds), seconds: seconds, startsInside: true)
        }
        return DayAggregate(day: day, histogram: histogram)
    }

    private func periodDays(_ count: Int, _ day: (Int) -> DayAggregate) -> PeriodDays {
        PeriodDays(
            window: DateInterval(start: Self.day0, end: dayStart(count)),
            endRule: .stalled,
            days: (0 ..< count).map(day)
        )
    }

    /// Every day in range at 120, but the odd ones half of the time at 200.
    private func plainDays(_ count: Int) -> PeriodDays {
        periodDays(count) { offset in
            offset % 2 == 0 ? self.aggregate(offset, [(120, 1)]) : self.aggregate(offset, [(120, 0.5), (200, 0.5)])
        }
    }

    private func insulinDay(
        _ offset: Int,
        basal: Double,
        smb: Double,
        bolus: Double,
        covered: Double = 1,
        isToday: Bool = false
    ) -> DayInsulin {
        let day = dayInterval(offset)
        return DayInsulin(
            day: day,
            isToday: isToday,
            basal: basal,
            smb: smb,
            bolus: bolus,
            scheduled: basal,
            zeroBasalSeconds: 0,
            coveredSeconds: day.duration * covered,
            negativeIOBSeconds: 0,
            iobSeconds: 0,
            iob: .empty,
            hours: [],
            hasDeliveries: true,
            coveredUntil: day.start.addingTimeInterval(day.duration * covered),
            profileAssumedBefore: nil,
            boluses: []
        )
    }

    /// - Parameter entries: the hour of the day and the grams of each
    private func mealDay(_ offset: Int, _ entries: [(hour: Double, grams: Double)], isToday: Bool = false) -> DayMeals {
        let day = dayInterval(offset)
        let points = entries.map {
            MealPoint(id: nil, actualDate: day.start.addingTimeInterval(.hours($0.hour)), carbs: $0.grams)
        }
        return DayMeals(
            day: day,
            isToday: isToday,
            entries: points,
            carbs: points.reduce(0) { $0 + $1.carbs },
            fat: 0,
            protein: 0,
            carbEquivalents: 0
        )
    }

    private func request(
        period: StatsPeriod = .days14,
        parts: [ReportPart] = [.daysTable],
        units: [GlucoseUnits] = [.mgdL],
        paper: ReportPaper = .a4,
        daysTable: ReportOptions.DaysTableSettings = .init(),
        dailyCharts: ReportOptions.DailyChartsSettings = .init(),
        day: Date? = nil
    ) -> Stat.ReportRequest {
        Stat.ReportRequest(
            period: period,
            parts: parts,
            units: units,
            hbA1cUnit: .percent,
            paper: paper,
            daysTable: daysTable,
            dailyCharts: dailyCharts,
            day: day
        )
    }

    private func data(
        _ request: Stat.ReportRequest,
        days: PeriodDays,
        insulin: [DayInsulin] = [],
        meals: [DayMeals] = [],
        charts: [ReportChartDay] = []
    ) throws -> Stat.ReportData {
        let bands = Stat.ReportBuilder.standardBands(request.units.first ?? .mgdL)
        return try Stat.ReportBuilder.assemble(
            request,
            summary: GlucoseStatsEngine.summary(
                days: days.days,
                window: days.window,
                endRule: days.endRule,
                period: request.period,
                bands: bands
            ),
            bins: [],
            glucoseDays: days,
            insulinDays: insulin,
            mealDays: meals,
            chartDays: charts,
            now: days.window.end
        )
    }

    private func dayRow(_ row: ReportDaysRow) -> (day: Date, numbers: ReportDaysNumbers)? {
        if case let .day(day, numbers) = row { return (day, numbers) }
        return nil
    }

    private func page(_ part: ReportPart, units: GlucoseUnits = .mgdL, paper: ReportPaper = .a4, index: Int = 0) -> ReportPage {
        ReportPage(part: part, units: units, size: paper.size(landscape: true), index: index)
    }

    // MARK: - Days table: rows

    /// A row for every day, also one without readings, then the Average row.
    func testRowsCoverEveryDay() throws {
        let days = periodDays(14) { offset in
            offset == 3 ? self.aggregate(offset) : self.aggregate(offset, [(120, 1)])
        }
        let rows = ReportDaysBuilder.rows(try data(request(), days: days), calendar: Self.calendar)
        XCTAssertEqual(rows.count, 15)
        XCTAssertEqual(rows.prefix(14).compactMap { dayRow($0)?.day }, (0 ..< 14).map(dayStart))
        // across the end of summer time: the calendar's days, not 24 hours apart
        XCTAssertEqual(dayRow(rows[13])?.day, Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))

        let missing = try XCTUnwrap(dayRow(rows[3])).numbers
        XCTAssertFalse(missing.hasGlucose)
        XCTAssertNil(missing.mean)
        XCTAssertNil(missing.below)
        XCTAssertNil(missing.coverage)
        let full = try XCTUnwrap(dayRow(rows[2])).numbers
        XCTAssertEqual(full.shares?.percents[GlucoseBand.inRange.rawValue], 100)
        XCTAssertEqual(full.mean, 120)
        XCTAssertEqual(full.lowest, 120)
        XCTAssertEqual(full.highest, 120)
        XCTAssertEqual(full.coverage, 100)

        guard case let .average(count, average) = rows[14] else { return XCTFail("the last row isn't the Average") }
        XCTAssertEqual(count, 14)
        XCTAssertEqual(average.shares?.percents[GlucoseBand.inRange.rawValue], 100)
        // 13 of the 14 days are covered
        XCTAssertEqual(average.coverage, 93)

        // without the part's data: no rows
        let none = try Stat.ReportBuilder.assemble(
            request(),
            summary: GlucoseStatsEngine.summary(
                days: days.days,
                window: days.window,
                endRule: .stalled,
                period: .days14,
                bands: Stat.ReportBuilder.standardBands(.mgdL)
            ),
            bins: [],
            now: Self.day0
        )
        XCTAssertEqual(ReportDaysBuilder.rows(none, calendar: Self.calendar), [])
    }

    /// The averages: glucose pooled over the days (time-weighted), insulin over the complete days as the Insulin tab's
    /// summary, carbs over the complete days with entries.
    func testAveragingRules() throws {
        let days = plainDays(4)
        let insulin = [
            insulinDay(0, basal: 20, smb: 5, bolus: 10),
            insulinDay(1, basal: 24, smb: 6, bolus: 10),
            // pump data for a quarter of the day: as delivered, outside the averages
            insulinDay(2, basal: 5, smb: 1, bolus: 2, covered: 0.25),
            insulinDay(3, basal: 9, smb: 2, bolus: 4, isToday: true)
        ]
        let meals = [
            mealDay(0, [(8, 40), (13, 20)]),
            mealDay(1, [(12, 100)]),
            mealDay(2, []),
            mealDay(3, [(9, 30)], isToday: true)
        ]
        let rows = ReportDaysBuilder.rows(
            try data(request(period: .days7), days: days, insulin: insulin, meals: meals),
            calendar: Self.calendar
        )
        XCTAssertEqual(rows.count, 5)

        let first = try XCTUnwrap(dayRow(rows[0])).numbers
        XCTAssertEqual(first.tdd, 35)
        XCTAssertEqual(first.basal, 20)
        XCTAssertEqual(first.bolus, 15)
        XCTAssertFalse(first.insulinOutsideAverage)
        XCTAssertEqual(first.carbs, 60)

        let partial = try XCTUnwrap(dayRow(rows[2])).numbers
        XCTAssertEqual(partial.tdd, 8)
        XCTAssertTrue(partial.insulinOutsideAverage)
        XCTAssertNil(partial.carbs)

        let today = try XCTUnwrap(dayRow(rows[3])).numbers
        XCTAssertEqual(today.tdd, 15)
        XCTAssertTrue(today.insulinOutsideAverage)
        XCTAssertEqual(today.carbs, 30)

        guard case let .average(_, average) = rows[4] else { return XCTFail("the last row isn't the Average") }
        // two days all in range, two half above: pooled
        XCTAssertEqual(try XCTUnwrap(average.above), 25, accuracy: 1E-6)
        XCTAssertEqual(try XCTUnwrap(average.below), 0, accuracy: 1E-6)
        XCTAssertEqual(average.shares?.percents[GlucoseBand.inRange.rawValue], 75)
        XCTAssertEqual(try XCTUnwrap(average.mean), 140, accuracy: 1E-6)
        XCTAssertEqual(average.lowest, 120)
        XCTAssertEqual(average.highest, 200)
        // the two complete days
        let summary = InsulinStatsEngine.summary(insulin, period: nil)
        XCTAssertEqual(average.tdd, summary.tdd)
        XCTAssertEqual(try XCTUnwrap(average.tdd), 37.5, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(average.basal), 22, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(average.bolus), 15.5, accuracy: 1E-9)
        // the two complete days with entries
        XCTAssertEqual(average.carbs, 80)

        // a day without an insulin or meals record: nothing
        let bare = ReportDaysBuilder.rows(try data(request(period: .days7), days: days), calendar: Self.calendar)
        XCTAssertNil(try XCTUnwrap(dayRow(bare[0])).numbers.tdd)
        XCTAssertNil(bare[4].numbers.tdd)
        XCTAssertNil(bare[4].numbers.carbs)
    }

    /// Subtotals by week and by month: a row after the days of each (a part of one at the period's ends), across the
    /// 25-hour day, by the calendar's first weekday.
    func testSubtotals() throws {
        func subtotals(_ kind: ReportOptions.DaysTableSettings.Subtotals, calendar: Calendar) throws
            -> [(first: Date, last: Date, days: Int)]
        {
            var settings = ReportOptions.DaysTableSettings()
            settings.subtotals = kind
            let rows = ReportDaysBuilder.rows(
                try data(request(daysTable: settings), days: plainDays(14)),
                calendar: calendar
            )
            XCTAssertEqual(rows.filter(\.isDay).count, 14)
            guard case .average = rows.last else {
                XCTFail("the last row isn't the Average")
                return []
            }
            return rows.compactMap { row in
                guard case let .subtotal(first, last, _) = row else { return nil }
                let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
                return (first, last, days + 1)
            }
        }

        // Tue 20 Oct … Mon 2 Nov, weeks from Monday: Tue–Sun, a whole week, the Monday
        let weeks = try subtotals(.week, calendar: Self.calendar)
        XCTAssertEqual(weeks.map(\.days), [6, 7, 1])
        XCTAssertEqual(weeks.map(\.first), [dayStart(0), dayStart(6), dayStart(13)])
        XCTAssertEqual(weeks.map(\.last), [dayStart(5), dayStart(12), dayStart(13)])

        var sunday = Self.calendar
        sunday.firstWeekday = 1
        XCTAssertEqual(try subtotals(.week, calendar: sunday).map(\.days), [5, 7, 2])

        let months = try subtotals(.month, calendar: Self.calendar)
        XCTAssertEqual(months.map(\.days), [12, 2])
        XCTAssertEqual(months.map(\.last), [dayStart(11), dayStart(13)])

        XCTAssertEqual(try subtotals(.none, calendar: Self.calendar).count, 0)

        // a subtotal row follows its days, with their average
        var settings = ReportOptions.DaysTableSettings()
        settings.subtotals = .week
        let rows = ReportDaysBuilder.rows(try data(request(daysTable: settings), days: plainDays(14)), calendar: Self.calendar)
        XCTAssertEqual(rows.count, 14 + 3 + 1)
        XCTAssertTrue(rows[5].isDay)
        guard case let .subtotal(_, _, week) = rows[6] else { return XCTFail("no subtotal after the first week") }
        // Tue … Sun: three days in range, three half above
        XCTAssertEqual(try XCTUnwrap(week.above), 25, accuracy: 0.5)
        XCTAssertTrue(rows[7].isDay)
    }

    /// Newest first: the days back from today, each subtotal still after its days, the Average last.
    func testNewestFirst() throws {
        var settings = ReportOptions.DaysTableSettings()
        settings.newestFirst = true
        settings.subtotals = .week
        let rows = ReportDaysBuilder.rows(try data(request(daysTable: settings), days: plainDays(14)), calendar: Self.calendar)
        XCTAssertEqual(rows.compactMap { dayRow($0)?.day }, (0 ..< 14).reversed().map(dayStart))
        XCTAssertEqual(dayRow(rows[0])?.day, dayStart(13))
        guard case let .subtotal(first, last, _) = rows[1] else { return XCTFail("no subtotal after the newest week") }
        XCTAssertEqual(first, dayStart(13))
        XCTAssertEqual(last, dayStart(13))
        guard case let .subtotal(start, end, _) = rows[9] else { return XCTFail("no subtotal after the whole week") }
        XCTAssertEqual(start, dayStart(6))
        XCTAssertEqual(end, dayStart(12))
        guard case .average = rows.last else { return XCTFail("the last row isn't the Average") }
    }

    // MARK: - Days table: pages

    func testRowsPerPageAndPagination() throws {
        XCTAssertEqual(ReportPlan.daysTableRowsPerPage(.a4), 25)
        XCTAssertEqual(ReportPlan.daysTableRowsPerPage(.letter), 26)
        XCTAssertEqual(ReportPlan.pageCount(0, perPage: 25), 0)
        XCTAssertEqual(ReportPlan.pageCount(25, perPage: 25), 1)
        XCTAssertEqual(ReportPlan.pageCount(26, perPage: 25), 2)

        let data = try data(request(period: .days90), days: plainDays(90))
        let rows = ReportDaysBuilder.rows(data, calendar: Self.calendar)
        XCTAssertEqual(rows.count, 91)
        let pages = ReportDaysBuilder.pages(rows, perPage: ReportPlan.daysTableRowsPerPage(.a4))
        XCTAssertEqual(pages.map(\.count), [25, 25, 25, 16])
        XCTAssertEqual(pages.flatMap { $0 }, rows)
        guard case .average = pages.last?.last else { return XCTFail("the Average row doesn't end the last page") }
        XCTAssertEqual(data.pageCount(of: .daysTable, calendar: Self.calendar), 4)

        // the Average row is never alone on a page: the last day comes over with it
        let alone = ReportDaysBuilder.pages(Array(rows.prefix(50)) + [rows[90]], perPage: 25)
        XCTAssertEqual(alone.map(\.count), [25, 24, 2])
        XCTAssertEqual(alone.flatMap { $0 }, Array(rows.prefix(50)) + [rows[90]])
        XCTAssertTrue(alone[2][0].isDay)
        XCTAssertEqual(ReportDaysBuilder.pages([rows[90]], perPage: 25).map(\.count), [1])

        let letter = try self.data(request(period: .days90, paper: .letter), days: plainDays(90))
        XCTAssertEqual(letter.pageCount(of: .daysTable, calendar: Self.calendar), 4)
        let both = try self.data(request(period: .days90, units: [.mgdL, .mmolL]), days: plainDays(90))
        let planned = both.pages(calendar: Self.calendar)
        XCTAssertEqual(planned.count, 8)
        // a part's pages in the first unit, then in the second
        XCTAssertEqual(
            planned.map(\.units),
            Array(repeating: GlucoseUnits.mgdL, count: 4) + Array(repeating: GlucoseUnits.mmolL, count: 4)
        )
        XCTAssertEqual(planned.map(\.index), [0, 1, 2, 3, 0, 1, 2, 3])
        XCTAssertTrue(planned.allSatisfy { $0.size == CGSize(width: 842, height: 595) })
    }

    /// Every page has the column titles; its rows are its share of the table.
    @MainActor func testDaysPages() throws {
        let data = try data(request(period: .days90), days: plainDays(90))
        let pages = (0 ..< 4).map { Stat.ReportDaysPage(data, page: page(.daysTable, index: $0), calendar: Self.calendar) }
        XCTAssertEqual(pages.map(\.rows.count), [25, 25, 25, 16])
        XCTAssertTrue(pages.allSatisfy { $0.columns == pages[0].columns && $0.columns.isNotEmpty })
        XCTAssertEqual(pages[3].rows.last?.style, .average)
        XCTAssertEqual(pages[3].rows.last?.title, "Average of 90 days")
        XCTAssertTrue(pages[0].rows.allSatisfy { $0.style == .day })
        XCTAssertEqual(pages[0].rows.first?.title, Self.day0.formatted(Stat.ReportDaysPage.dayStyle(Self.calendar)))
        // past the table: nothing
        XCTAssertEqual(Stat.ReportDaysPage(data, page: page(.daysTable, index: 4), calendar: Self.calendar).rows, [])
    }

    /// The columns by the settings, the cells' strings, the dashes of a day without data.
    @MainActor func testDaysPageCells() throws {
        typealias Kind = Stat.ReportDaysPage.Kind
        let days = periodDays(4) { offset in
            switch offset {
            case 0: return self.aggregate(offset, [(120, 1)])
            case 1: return self.aggregate(offset, [(60, 0.004), (120, 0.496), (200, 0.5)])
            case 2: return self.aggregate(offset)
            default: return self.aggregate(offset, [(120, 0.5)])
            }
        }
        let insulin = [insulinDay(0, basal: 20, smb: 5, bolus: 10), insulinDay(1, basal: 5, smb: 1, bolus: 2, covered: 0.25)]
        let meals = [mealDay(0, [(8, 40), (13, 20)])]
        let plain = Stat.ReportDaysPage(
            try data(request(period: .days7), days: days, insulin: insulin, meals: meals),
            page: page(.daysTable),
            calendar: Self.calendar
        )
        XCTAssertEqual(
            plain.columns.map(\.kind),
            [Kind.inRange, .below, .above, .mean, .sd, .cv, .tdd, .basal, .bolus, .carbs]
        )
        XCTAssertEqual(plain.columns[0].subtitle, "70–180")
        XCTAssertEqual(plain.columns[1].subtitle, "< 70")
        XCTAssertEqual(plain.columns[2].subtitle, "> 180")
        XCTAssertEqual(plain.columns[3].subtitle, "mg/dL")
        XCTAssertEqual(plain.rows.count, 5)
        XCTAssertEqual(
            plain.rows[0].cells,
            [
                "100%",
                "0%",
                "0%",
                "120",
                "0",
                "0%",
                StatsAmount.number(35, digits: 1),
                StatsAmount.number(20, digits: 1),
                StatsAmount.number(15, digits: 1),
                StatsAmount.number(60, digits: 0)
            ]
        )
        XCTAssertEqual(plain.rows[0].segments.map(\.band), [.inRange])
        // 0.4% low: "<1%", not "0%"
        XCTAssertEqual(plain.rows[1].cells[1], "<1%")
        XCTAssertEqual(plain.rows[1].cells[2], "50%")
        // outside the insulin averages: marked
        XCTAssertEqual(plain.rows[1].cells[6], StatsAmount.number(8, digits: 1) + "*")
        XCTAssertEqual(plain.rows[1].cells[9], "–")
        // no readings: dashes, no bar
        XCTAssertEqual(plain.rows[2].cells, Array(repeating: "–", count: 10))
        XCTAssertEqual(plain.rows[2].segments, [])
        XCTAssertEqual(plain.rows[4].title, "Average of 4 days")

        var settings = ReportOptions.DaysTableSettings()
        settings.insulin = false
        settings.carbs = false
        settings.sdAndCV = false
        settings.lowestAndHighest = true
        settings.cgmCoverage = true
        let other = Stat.ReportDaysPage(
            try data(request(period: .days7, units: [.mmolL], daysTable: settings), days: days),
            page: page(.daysTable, units: .mmolL),
            calendar: Self.calendar
        )
        XCTAssertEqual(other.columns.map(\.kind), [Kind.inRange, .below, .above, .mean, .lowHigh, .coverage])
        XCTAssertEqual(other.columns[3].subtitle, "mmol/L")
        XCTAssertEqual(other.rows[3].cells[5], "50%")
        XCTAssertEqual(
            other.rows[1].cells[4],
            StatsFormatting.glucose(60, units: .mmolL) + "–" + StatsFormatting.glucose(200, units: .mmolL)
        )

        // the subtotals' titles: a week's days, a month's name
        var weekly = ReportOptions.DaysTableSettings()
        weekly.subtotals = .week
        let byWeek = Stat.ReportDaysPage(
            try data(request(daysTable: weekly), days: plainDays(14)),
            page: page(.daysTable),
            calendar: Self.calendar
        )
        XCTAssertEqual(byWeek.rows.filter { $0.style == .subtotal }.count, 3)
        XCTAssertEqual(byWeek.rows[6].style, .subtotal)
        var monthly = ReportOptions.DaysTableSettings()
        monthly.subtotals = .month
        let byMonth = Stat.ReportDaysPage(
            try data(request(daysTable: monthly), days: plainDays(14)),
            page: page(.daysTable),
            calendar: Self.calendar
        )
        XCTAssertEqual(byMonth.rows.filter { $0.style == .subtotal }.count, 2)
        XCTAssertNotEqual(byMonth.rows[12].title, byWeek.rows[6].title)
    }

    // MARK: - Daily charts: the days

    private func points(
        _ offset: Int,
        fromHour: Double,
        toHour: Double,
        everyMinutes: Double,
        mgdl: Int16 = 120
    ) -> [GlucosePoint] {
        let start = dayStart(offset)
        return stride(from: fromHour * 60, to: toHour * 60, by: everyMinutes).map {
            GlucosePoint(time: start.addingTimeInterval(.minutes($0)), mgdl: mgdl)
        }
    }

    private func trace(_ offset: Int, _ points: [GlucosePoint]) -> ReportDayTrace {
        var histogram = GlucoseHistogram()
        for point in points {
            histogram.add(
                WeightedPoint(time: point.time, mgdl: point.mgdl, span: .minutes(5)),
                seconds: .minutes(5),
                startsInside: true
            )
        }
        let day = dayInterval(offset)
        return ReportDayTrace(
            points: points,
            summary: GlucoseStatsEngine.summary(
                histogram,
                window: day,
                endRule: .stalled,
                calendarDays: 1,
                daysWithData: points.isEmpty ? 0 : 1,
                bands: Stat.ReportBuilder.standardBands(.mgdL)
            )
        )
    }

    func testThinningAndStretches() {
        // a 1-minute CGM for an hour: about one reading per 5 minutes, both ends kept
        let minute = points(0, fromHour: 0, toHour: 1, everyMinutes: 1)
        let thinned = ReportChartsBuilder.thinned(minute)
        XCTAssertEqual(thinned.first, minute.first)
        XCTAssertEqual(thinned.last, minute.last)
        // the first, one of each 4.5 minutes (their lowest and highest are the same reading here), the last
        XCTAssertEqual(thinned.count, 14)
        // 5-minute readings stay as they are
        let five = points(0, fromHour: 0, toHour: 2, everyMinutes: 5)
        XCTAssertEqual(ReportChartsBuilder.thinned(five), five)
        XCTAssertEqual(ReportChartsBuilder.thinned([]), [])

        // a gap over 15 minutes breaks the line; the readings beside it are kept
        let gapped = points(0, fromHour: 0, toHour: 1, everyMinutes: 1) + points(0, fromHour: 2, toHour: 3, everyMinutes: 1)
        let kept = ReportChartsBuilder.thinned(gapped)
        XCTAssertTrue(kept.contains(gapped[59]))
        XCTAssertTrue(kept.contains(gapped[60]))
        let stretches = ReportChartsBuilder.stretches(kept)
        XCTAssertEqual(stretches.count, 2)
        XCTAssertEqual(stretches[0].last, gapped[59])
        XCTAssertEqual(stretches[1].first, gapped[60])
        // 15 minutes apart is still one line
        XCTAssertEqual(ReportChartsBuilder.stretches(points(0, fromHour: 0, toHour: 2, everyMinutes: 15)).count, 1)
        XCTAssertEqual(ReportChartsBuilder.stretches(points(0, fromHour: 0, toHour: 2, everyMinutes: 16)).count, 8)
    }

    func testLabelMerging() {
        let start = Self.day0
        func carbs(_ minute: Double, _ grams: Double) -> ReportCarbEntry {
            ReportCarbEntry(time: start.addingTimeInterval(.minutes(minute)), grams: grams)
        }
        // 10 and 15 minutes after the first are its group; 40 minutes after isn't
        XCTAssertEqual(
            ReportChartsBuilder.mergedCarbs([carbs(600, 20), carbs(610, 15), carbs(615, 5), carbs(640, 30)]),
            [carbs(600, 40), carbs(640, 30)]
        )
        XCTAssertEqual(ReportChartsBuilder.mergedCarbs([]), [])

        func bolus(_ minute: Double, _ units: Double, smb: Bool = false, external: Bool = false) -> InsulinBolus {
            InsulinBolus(date: start.addingTimeInterval(.minutes(minute)), units: units, isSMB: smb, isExternal: external)
        }
        // the SMBs are left out; a pen's insulin next to a bolus is one label
        XCTAssertEqual(
            ReportChartsBuilder
                .mergedBoluses([bolus(600, 4), bolus(603, 0.3, smb: true), bolus(610, 1, external: true), bolus(700, 2)]),
            [bolus(600, 5, external: true), bolus(700, 2)]
        )
    }

    /// The days with something to draw; a day without any is left out.
    func testChartDays() {
        let days = (0 ..< 4).map(dayInterval)
        let traces = [
            trace(0, points(0, fromHour: 0, toHour: 24, everyMinutes: 5)),
            trace(1, []),
            trace(2, []),
            trace(3, [])
        ]
        let input = InsulinInput(
            events: [
                PumpEventRecord(date: dayStart(3).addingTimeInterval(.hours(8)), kind: .bolus, source: .pump, units: 4),
                PumpEventRecord(
                    date: dayStart(3).addingTimeInterval(.hours(9)),
                    kind: .bolus,
                    source: .pump,
                    units: 0.3,
                    isSMB: true
                ),
                PumpEventRecord(
                    date: dayStart(3).addingTimeInterval(.hours(10)),
                    kind: .tempBasal,
                    source: .pump,
                    units: -1,
                    rate: 1.5,
                    durationMin: 60
                )
            ]
        )
        func chartDays(_ settings: ReportOptions.DailyChartsSettings, input: InsulinInput?) -> [ReportChartDay] {
            ReportChartsBuilder.days(
                days,
                traces: traces,
                insulinDays: [insulinDay(0, basal: 20, smb: 5, bolus: 10)],
                mealDays: [mealDay(0, [(8, 40)]), mealDay(2, [(12, 30), (12.1, 10), (18, 0)])],
                input: input,
                settings: settings,
                now: dayStart(4),
                calendar: Self.calendar
            )
        }

        let all = chartDays(.init(), input: input)
        // the second day has nothing
        XCTAssertEqual(all.map(\.day), [days[0], days[2], days[3]])
        XCTAssertEqual(all[0].points.count, 288)
        XCTAssertEqual(all[0].mean, 120)
        XCTAssertEqual(all[0].shares?.percents[GlucoseBand.inRange.rawValue], 100)
        XCTAssertEqual(all[0].tdd, 35)
        XCTAssertEqual(all[0].carbs, 40)
        XCTAssertEqual(all[0].carbEntries.count, 1)
        // carbs only: no trace, no numbers of it; the entry without carbs isn't drawn
        XCTAssertEqual(all[1].points, [])
        XCTAssertNil(all[1].mean)
        XCTAssertNil(all[1].tdd)
        XCTAssertEqual(all[1].carbs, 40)
        XCTAssertEqual(all[1].carbEntries.map(\.grams), [30, 10])
        // pump events only
        XCTAssertEqual(all[2].boluses.map(\.units), [4, 0.3])
        XCTAssertEqual(all[2].boluses.map(\.isSMB), [false, true])
        XCTAssertEqual(all[2].basal.count, 1)
        XCTAssertEqual(all[2].basal.first?.rate, 1.5)
        XCTAssertEqual(all[2].basal.first?.interval.start, dayStart(3).addingTimeInterval(.hours(10)))
        XCTAssertEqual(try XCTUnwrap(all[2].basal.first?.interval.duration), .hours(1), accuracy: 60)
        XCTAssertNil(all[2].basal.first?.scheduled)

        // everything off, or the events not read: only what the trace and the totals give
        var bare = ReportOptions.DailyChartsSettings()
        bare.boluses = false
        bare.carbs = false
        bare.basal = false
        let traceOnly = chartDays(bare, input: input)
        XCTAssertEqual(traceOnly.map(\.day), [days[0]])
        XCTAssertEqual(traceOnly[0].carbs, 40)
        XCTAssertEqual(traceOnly[0].carbEntries, [])
        XCTAssertEqual(chartDays(.init(), input: nil).map(\.day), [days[0], days[2]])
    }

    // MARK: - Daily charts: the pages

    private func chartDay(_ offset: Int, mgdl: Int16 = 120) -> ReportChartDay {
        var day = ReportChartDay(day: dayInterval(offset))
        day.points = points(offset, fromHour: 6, toHour: 12, everyMinutes: 5, mgdl: mgdl)
        day.shares = BandShares(fractions: [0, 0, 1, 0, 0])
        day.mean = Double(mgdl)
        return day
    }

    private func chartsData(
        _ settings: ReportOptions.DailyChartsSettings,
        _ charts: [ReportChartDay],
        units: [GlucoseUnits] = [.mgdL]
    ) throws -> Stat.ReportData {
        try data(request(parts: [.dailyCharts], units: units, dailyCharts: settings), days: plainDays(14), charts: charts)
    }

    func testChartsLayoutsAndPageCounts() throws {
        typealias Settings = ReportOptions.DailyChartsSettings
        func settings(_ perPage: Int) -> Settings {
            var settings = Settings()
            settings.daysPerPage = perPage
            return settings
        }
        XCTAssertEqual(Settings.daysPerPageChoices, [1, 2, 4, 8])
        XCTAssertEqual(Settings().daysPerPage, 4)
        XCTAssertEqual([1, 2, 4, 8].map { settings($0).columns }, [1, 1, 1, 2])
        XCTAssertEqual([1, 2, 4, 8].map { settings($0).rows }, [1, 2, 4, 4])
        XCTAssertEqual([1, 2, 4, 8].map { settings($0).isLandscape }, [true, false, false, false])

        // 6 days with data of the 14
        let charts = (0 ..< 6).map { chartDay($0 * 2) }
        XCTAssertEqual(
            try [1, 2, 4, 8].map { try chartsData(settings($0), charts).pageCount(of: .dailyCharts, calendar: Self.calendar) },
            [6, 3, 2, 1]
        )
        let pages = try chartsData(settings(4), charts, units: [.mgdL, .mmolL]).pages(calendar: Self.calendar)
        XCTAssertEqual(pages.map(\.index), [0, 1, 0, 1])
        XCTAssertTrue(pages.allSatisfy { $0.size == CGSize(width: 595, height: 842) })
        XCTAssertEqual(
            try chartsData(settings(1), charts).pages(calendar: Self.calendar).first?.size,
            CGSize(width: 842, height: 595)
        )
        // nothing to draw: one page saying so
        XCTAssertEqual(try chartsData(settings(4), []).pageCount(of: .dailyCharts, calendar: Self.calendar), 1)
    }

    @MainActor func testChartsPageModel() throws {
        var settings = ReportOptions.DailyChartsSettings()
        var charts = (0 ..< 6).map { chartDay($0) }
        // a high day on the second page
        charts[5] = chartDay(5, mgdl: 380)
        charts[0].tdd = 35
        charts[0].carbs = 60
        charts[0].carbEntries = [
            ReportCarbEntry(time: dayStart(0).addingTimeInterval(.hours(8)), grams: 40),
            ReportCarbEntry(time: dayStart(0).addingTimeInterval(.hours(8.1)), grams: 20)
        ]
        charts[0].boluses = [
            InsulinBolus(date: dayStart(0).addingTimeInterval(.hours(8)), units: 4, isSMB: false, isExternal: false),
            InsulinBolus(date: dayStart(0).addingTimeInterval(.hours(9)), units: 0.3, isSMB: true, isExternal: false)
        ]
        charts[0].basal = [
            ReportBasalStep(interval: DateInterval(start: dayStart(0), duration: .hours(6)), rate: 0.8, scheduled: 1.2)
        ]
        let data = try chartsData(settings, charts)
        let chartsPage = ReportPage(part: .dailyCharts, units: .mgdL, size: ReportPaper.a4.size, index: 0)
        let first = Stat.ReportChartsPage(data, page: chartsPage, calendar: Self.calendar)
        XCTAssertEqual(first.panels.count, 4)
        XCTAssertEqual(first.columns, 1)
        XCTAssertEqual(first.rows, 4)
        XCTAssertNil(first.emptyNote)
        // one scale for the page's panels; the high day is on the next
        XCTAssertEqual(first.axis, 0 ... 350)
        XCTAssertEqual(first.low, 70)
        XCTAssertEqual(first.high, 180)
        XCTAssertEqual(first.hairlines, [54, 250])
        XCTAssertEqual(first.basalMax, 2)
        XCTAssertEqual(first.bolusMax, 4)
        XCTAssertEqual(first.smbMax, 0.3)
        let panel = first.panels[0]
        XCTAssertEqual(panel.lines.count, 1)
        XCTAssertEqual(try XCTUnwrap(panel.lines.first?.first?.x), 0.25, accuracy: 1E-9)
        // the two entries six minutes apart: one label
        XCTAssertEqual(panel.carbs.map(\.amount), [60])
        XCTAssertNotNil(panel.carbs.first?.label)
        XCTAssertEqual(panel.boluses.map(\.amount), [4])
        XCTAssertEqual(panel.smbs.map(\.amount), [0.3])
        XCTAssertEqual(panel.basal, [.init(from: 0, to: 0.25, rate: 0.8, scheduled: 1.2)])
        XCTAssertEqual(panel.ticks.count, 8)
        XCTAssertTrue(panel.stats.hasPrefix("In range 100% · Mean 120 mg/dL · Insulin "))
        XCTAssertTrue(first.panels[1].stats.hasPrefix("In range 100% · Mean 120 mg/dL"))
        XCTAssertEqual(first.legend.map(\.key), [.glucose, .range, .bolus, .smb, .carbs, .basal, .scheduled])

        var secondPage = chartsPage
        secondPage.index = 1
        let second = Stat.ReportChartsPage(data, page: secondPage, calendar: Self.calendar)
        XCTAssertEqual(second.panels.count, 2)
        XCTAssertEqual(second.axis, 0 ... 400)

        // the 25-hour day: six hours in is 6/25 of it; its clock still has eight 3-hour ticks
        let long = Stat.ReportChartsPage(try chartsData(settings, [chartDay(5)]), page: chartsPage, calendar: Self.calendar)
        XCTAssertEqual(try XCTUnwrap(long.panels[0].lines.first?.first?.x), 6.0 / 25, accuracy: 1E-9)
        XCTAssertEqual(long.panels[0].ticks.count, 8)

        // newest first
        settings.newestFirst = true
        let reversed = Stat.ReportChartsPage(try chartsData(settings, charts), page: chartsPage, calendar: Self.calendar)
        XCTAssertEqual(reversed.axis, 0 ... 400)
        XCTAssertEqual(reversed.panels.count, 4)
        XCTAssertNotEqual(reversed.panels[0].title, first.panels[0].title)

        // eight a page: two columns, 6-hour ticks, no carb labels, short numbers; the settings' keys only
        settings.newestFirst = false
        settings.daysPerPage = 8
        settings.basal = false
        settings.boluses = false
        let eight = Stat.ReportChartsPage(try chartsData(settings, charts), page: chartsPage, calendar: Self.calendar)
        XCTAssertEqual(eight.panels.count, 6)
        XCTAssertEqual(eight.columns, 2)
        XCTAssertEqual(eight.panels[0].ticks.count, 4)
        XCTAssertNil(eight.panels[0].carbs.first?.label)
        XCTAssertTrue(eight.panels[0].stats.hasPrefix("100% · 120 · "))
        XCTAssertFalse(eight.showsBasal)
        XCTAssertEqual(eight.legend.map(\.key), [.glucose, .range, .carbs])

        // mmol/L: the labels' unit, the scale's top
        let mmol = Stat.ReportChartsPage(
            try chartsData(.init(), charts, units: [.mmolL]),
            page: ReportPage(part: .dailyCharts, units: .mmolL, size: ReportPaper.a4.size, index: 0),
            calendar: Self.calendar
        )
        XCTAssertEqual(mmol.axis, 0 ... 360)
        XCTAssertEqual(mmol.high, 181)

        let empty = Stat.ReportChartsPage(try chartsData(.init(), []), page: chartsPage, calendar: Self.calendar)
        XCTAssertEqual(empty.panels.count, 0)
        XCTAssertNotNil(empty.emptyNote)
    }

    func testBasalScale() {
        typealias Page = Stat.ReportChartsPage
        XCTAssertEqual(Page.basalScale(0), 0.5)
        XCTAssertEqual(Page.basalScale(0.5), 0.5)
        XCTAssertEqual(Page.basalScale(0.8), 1)
        XCTAssertEqual(Page.basalScale(1.2), 2)
        XCTAssertEqual(Page.basalScale(4), 5)
        XCTAssertEqual(Page.basalScale(50), 50)
    }

    // MARK: - Settings and the estimate

    private func preferences() -> ReportPreferences {
        let name = "test-report-days-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return ReportPreferences(defaults: defaults)
    }

    func testNewSettingsDefaultsAndRoundTrip() {
        typealias Key = ReportPreferences.Key
        let store = preferences()
        XCTAssertEqual(store.daysTable, ReportOptions.DaysTableSettings())
        XCTAssertEqual(store.dailyCharts, ReportOptions.DailyChartsSettings())
        let standard = store.daysTable
        XCTAssertTrue(standard.insulin && standard.carbs && standard.sdAndCV)
        XCTAssertFalse(standard.lowestAndHighest || standard.cgmCoverage || standard.newestFirst)
        XCTAssertEqual(standard.subtotals, .none)
        XCTAssertTrue(store.dailyCharts.boluses && store.dailyCharts.carbs && store.dailyCharts.basal)
        XCTAssertFalse(store.dailyCharts.newestFirst)

        var days = ReportOptions.DaysTableSettings()
        days.insulin = false
        days.carbs = false
        days.sdAndCV = false
        days.lowestAndHighest = true
        days.cgmCoverage = true
        days.subtotals = .month
        days.newestFirst = true
        store.daysTable = days
        var charts = ReportOptions.DailyChartsSettings()
        charts.daysPerPage = 8
        charts.boluses = false
        charts.carbs = false
        charts.basal = false
        charts.newestFirst = true
        store.dailyCharts = charts

        let next = ReportPreferences(defaults: store.defaults)
        XCTAssertEqual(next.daysTable, days)
        XCTAssertEqual(next.dailyCharts, charts)
        let options = next.options(userUnits: .mgdL, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(options.daysTable, days)
        XCTAssertEqual(options.dailyCharts, charts)
        XCTAssertEqual(store.defaults.string(forKey: Key.daysSubtotals), "month")
        XCTAssertEqual(store.defaults.object(forKey: Key.chartsDaysPerPage) as? Int, 8)
        for key in [
            Key.daysInsulin, Key.daysCarbs, Key.daysSDAndCV, Key.daysLowestAndHighest, Key.daysCGMCoverage,
            Key.daysSubtotals, Key.daysNewestFirst, Key.chartsDaysPerPage, Key.chartsBoluses, Key.chartsCarbs,
            Key.chartsBasal, Key.chartsNewestFirst
        ] {
            XCTAssertTrue(key.hasPrefix("iAPS.reports."), key)
            XCTAssertNotNil(store.defaults.object(forKey: key), key)
        }
    }

    func testNewSettingsValidation() {
        typealias Key = ReportPreferences.Key
        let store = preferences()
        let defaults = store.defaults
        // days per page that isn't a layout, or of another type: 4
        for stored in [0, 3, 5, 16, -1] {
            defaults.set(stored, forKey: Key.chartsDaysPerPage)
            XCTAssertEqual(store.dailyCharts.daysPerPage, 4, "\(stored)")
        }
        defaults.set("eight", forKey: Key.chartsDaysPerPage)
        XCTAssertEqual(store.dailyCharts.daysPerPage, 4)
        // a stored Bool isn't 1 a page, nor is a fraction
        defaults.set(true, forKey: Key.chartsDaysPerPage)
        XCTAssertEqual(store.dailyCharts.daysPerPage, 4)
        defaults.set(2.5, forKey: Key.chartsDaysPerPage)
        XCTAssertEqual(store.dailyCharts.daysPerPage, 4)
        for stored in [1, 2, 4, 8] {
            defaults.set(stored, forKey: Key.chartsDaysPerPage)
            XCTAssertEqual(store.dailyCharts.daysPerPage, stored)
        }
        // and never written
        var charts = store.dailyCharts
        charts.daysPerPage = 3
        store.dailyCharts = charts
        XCTAssertEqual(defaults.object(forKey: Key.chartsDaysPerPage) as? Int, 8)

        defaults.set("fortnight", forKey: Key.daysSubtotals)
        XCTAssertEqual(store.daysTable.subtotals, .none)
        defaults.set("week", forKey: Key.daysSubtotals)
        XCTAssertEqual(store.daysTable.subtotals, .week)
        defaults.set("yes", forKey: Key.daysInsulin)
        defaults.set("no", forKey: Key.daysLowestAndHighest)
        XCTAssertTrue(store.daysTable.insulin)
        XCTAssertFalse(store.daysTable.lowestAndHighest)
        defaults.set("no", forKey: Key.chartsBasal)
        XCTAssertTrue(store.dailyCharts.basal)

        // the new parts are offered, and not selected until picked
        XCTAssertEqual(store.parts, [.summary, .percentileProfile])
        store.parts = [.daysTable, .dailyCharts]
        XCTAssertEqual(store.parts, [.daysTable, .dailyCharts])
        XCTAssertEqual(store.options(userUnits: .mgdL).orderedParts, [.daysTable, .dailyCharts])
    }

    /// The estimate: the Days table by its rows on the paper, Daily charts by the days per page, twice in both units.
    func testPageCountEstimate() {
        var options = ReportOptions(period: .days90, units: .mgdL, paper: .a4, parts: [.daysTable])
        // 90 days and the Average row, 25 a page
        XCTAssertEqual(options.estimatedPageCount, 4)
        options.daysTable.subtotals = .week
        // and up to 14 week rows
        XCTAssertEqual(options.estimatedPageCount, 5)
        options.daysTable.subtotals = .none
        options.period = .days14
        XCTAssertEqual(options.estimatedPageCount, 1)
        options.period = .days30
        XCTAssertEqual(options.estimatedPageCount, 2)

        options.parts = [.dailyCharts]
        options.period = .days14
        XCTAssertEqual(options.estimatedPageCount, 4)
        options.dailyCharts.daysPerPage = 1
        XCTAssertEqual(options.estimatedPageCount, 14)
        options.dailyCharts.daysPerPage = 8
        XCTAssertEqual(options.estimatedPageCount, 2)
        options.period = .days90
        XCTAssertEqual(options.estimatedPageCount, 12)
        options.units = .both
        XCTAssertEqual(options.estimatedPageCount, 24)

        options.parts = Set(ReportPart.implemented)
        options.units = .mgdL
        options.period = .days14
        options.dailyCharts.daysPerPage = 4
        XCTAssertEqual(options.estimatedPageCount, 1 + 1 + 1 + 4)
        options.units = .both
        XCTAssertEqual(options.estimatedPageCount, 14)

        // the plan of a period with data on every day is the estimate
        XCTAssertEqual(ReportPlan.estimatedSubtotals(days: 14, .week), 3)
        XCTAssertEqual(ReportPlan.estimatedSubtotals(days: 90, .month), 4)
        XCTAssertEqual(ReportPlan.estimatedSubtotals(days: 90, .none), 0)
    }

    // MARK: - The builder

    /// The provider's calls a report makes, faked.
    private actor FakeSource: ReportDataSource {
        struct Failure: Error {}

        let days: PeriodDays
        /// by the day's start
        let traces: [Date: ReportDayTrace]
        let insulin: [DayInsulin]
        let meals: [DayMeals]
        let input: InsulinInput
        /// the reads that throw
        let failing: Set<ReportReadFailure>
        /// the profile's summary when it isn't the days' (a reading came in between the two reads)
        let profile: GlucoseSummary?
        /// the trace read (from 1) that cancels the task reading it
        let cancelsAtTrace: Int?
        private(set) var reads: [String] = []
        private(set) var periods: [StatsPeriod] = []
        private(set) var inputNow: Date?
        private(set) var begun = 0
        private(set) var ended = 0

        init(
            days: PeriodDays,
            traces: [Date: ReportDayTrace],
            insulin: [DayInsulin],
            meals: [DayMeals],
            input: InsulinInput,
            failing: Set<ReportReadFailure> = [],
            profile: GlucoseSummary? = nil,
            cancelsAtTrace: Int? = nil
        ) {
            self.days = days
            self.traces = traces
            self.insulin = insulin
            self.meals = meals
            self.input = input
            self.failing = failing
            self.profile = profile
            self.cancelsAtTrace = cancelsAtTrace
        }

        private var summary: GlucoseSummary {
            GlucoseStatsEngine.summary(
                days: days.days,
                window: days.window,
                endRule: days.endRule,
                period: nil,
                bands: Stat.ReportBuilder.standardBands(.mgdL)
            )
        }

        func beginSession() { begun += 1 }
        func endSession() { ended += 1 }

        func reportProfile(_: StatsPeriod, bands _: StatsBands) -> Stat.AGPResult {
            reads.append("profile")
            return Stat.AGPResult(bins: [], points: [], axis: 40 ... 300, summary: profile ?? summary)
        }

        func reportInsulin(_ period: StatsPeriod) throws -> InsulinPeriod {
            reads.append("insulin")
            periods.append(period)
            if failing.contains(.insulin) { throw Failure() }
            return InsulinPeriod(summary: InsulinStatsEngine.summary(insulin, period: nil), days: insulin, hours: [])
        }

        func reportMeals(_ period: StatsPeriod, factor _: Double) throws -> MealPeriod {
            reads.append("meals")
            periods.append(period)
            if failing.contains(.meals) { throw Failure() }
            let empty = MealStatsEngine.period(
                period,
                points: [],
                fatOrProteinLogged: false,
                factor: 0.5,
                now: days.window.end,
                calendar: StatsReportDaysTests.calendar
            )
            return MealPeriod(summary: empty.summary, days: meals, hours: [], topHours: [])
        }

        func reportDays(_: StatsPeriod) -> PeriodDays {
            reads.append("days")
            return days
        }

        func reportTrace(day: Date, bands _: StatsBands) -> ReportDayTrace {
            reads.append("trace")
            if reads.filter({ $0 == "trace" }).count == cancelsAtTrace {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return traces[day] ?? ReportDayTrace(points: [], summary: summary)
        }

        func reportInsulinInput(_: DateInterval, now: Date) throws -> InsulinInput {
            reads.append("events")
            inputNow = now
            if failing.contains(.pumpEvents) { throw Failure() }
            return input
        }
    }

    private func traces(_ offsets: [Int]) -> [Date: ReportDayTrace] {
        Dictionary(
            offsets.map { (dayStart($0), trace($0, points($0, fromHour: 0, toHour: 24, everyMinutes: 5))) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The last 7 days before `now`'s day end: readings on three of them.
    private func weekSource() -> (source: FakeSource, now: Date) {
        let days = plainDays(7)
        let dayTraces = traces([0, 2, 6])
        let input = InsulinInput(
            events: [PumpEventRecord(date: dayStart(4).addingTimeInterval(.hours(8)), kind: .bolus, source: .pump, units: 4)]
        )
        let source = FakeSource(
            days: days,
            traces: dayTraces,
            insulin: (0 ..< 7).map { insulinDay($0, basal: 20, smb: 5, bolus: 10) },
            meals: [mealDay(0, [(8, 40)])],
            input: input
        )
        // noon of the seventh day
        return (source, dayStart(6).addingTimeInterval(.hours(12)))
    }

    /// The period's reads: the profile first (it holds the readings), each day's trace, the pump events once.
    func testBuilderReadsTheDaysOnce() async throws {
        let (source, now) = weekSource()
        let data = try await Stat.ReportBuilder.build(
            request(period: .days7, parts: [.daysTable, .dailyCharts]),
            source: source,
            now: now,
            calendar: Self.calendar
        )
        let reads = await source.reads
        XCTAssertEqual(reads.first, "profile")
        XCTAssertEqual(reads.filter { $0 == "trace" }.count, 7)
        XCTAssertEqual(reads.filter { $0 == "events" }.count, 1)
        XCTAssertEqual(reads.filter { $0 == "insulin" }.count, 1)
        XCTAssertEqual(reads.filter { $0 == "meals" }.count, 1)
        XCTAssertEqual(reads.filter { $0 == "days" }.count, 1)
        let sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions, [1, 1])

        XCTAssertEqual(data.glucoseDays?.days.count, 7)
        XCTAssertEqual(data.insulinDays.count, 7)
        XCTAssertEqual(data.mealDays.count, 1)
        // the days with readings, and the one with only a bolus
        XCTAssertEqual(data.chartDays.map(\.day.start), [0, 2, 4, 6].map(dayStart))
        XCTAssertEqual(data.chartDays[2].boluses.map(\.units), [4])
        XCTAssertEqual(data.chartDays[0].tdd, 35)
        XCTAssertEqual(data.chartDays[0].carbs, 40)
        // no Summary: its block isn't filled
        XCTAssertNil(data.insulin)
        XCTAssertNil(data.meals)
        // a 7-day table on one page, four charts on one
        XCTAssertEqual(data.pages(calendar: Self.calendar).map(\.part), [.daysTable, .dailyCharts])

        // the Days table alone, its insulin and carbs columns off: only the profile and the days
        let (plain, _) = weekSource()
        var settings = ReportOptions.DaysTableSettings()
        settings.insulin = false
        settings.carbs = false
        _ = try await Stat.ReportBuilder.build(
            request(period: .days7, daysTable: settings),
            source: plain,
            now: now,
            calendar: Self.calendar
        )
        let plainReads = await plain.reads
        XCTAssertEqual(plainReads, ["profile", "days"])
    }

    /// The Day view's export: that day alone, on one landscape page, whatever the saved period and layout.
    func testSingleDayRequest() async throws {
        var settings = ReportOptions.DailyChartsSettings()
        settings.daysPerPage = 8
        let single = request(
            period: .days14,
            parts: [.summary, .daysTable],
            dailyCharts: settings,
            day: dayStart(2).addingTimeInterval(.hours(15))
        )
        XCTAssertEqual(single.parts, [.dailyCharts])
        XCTAssertEqual(single.dailyCharts.daysPerPage, 1)
        XCTAssertEqual(single.period, Stat.ReportRequest.dayPeriod)
        XCTAssertEqual(single.size(of: .dailyCharts), CGSize(width: 842, height: 595))

        let (source, now) = weekSource()
        let data = try await Stat.ReportBuilder.build(single, source: source, now: now, calendar: Self.calendar)
        XCTAssertEqual(data.chartDays.map(\.day.start), [dayStart(2)])
        XCTAssertEqual(data.chartDays[0].tdd, 35)
        let days = data.days(calendar: Self.calendar)
        XCTAssertEqual(days.first, dayStart(2))
        XCTAssertEqual(days.last, dayStart(2))
        let pages = data.pages(calendar: Self.calendar)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.size, CGSize(width: 842, height: 595))
        // the day's readings first; its insulin and meals from the smallest period holding it (it is 5 days back)
        let reads = await source.reads
        XCTAssertEqual(reads, ["trace", "insulin", "meals", "events"])
        let periods = await source.periods
        XCTAssertEqual(periods, [.days7, .days7])
        let inputNow = await source.inputNow
        XCTAssertEqual(inputNow, now)
        let sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions, [1, 1])
        XCTAssertEqual(Stat.ReportBuilder.period(containing: dayStart(6), now: now, calendar: Self.calendar), .days7)
        XCTAssertEqual(Stat.ReportBuilder.period(containing: dayStart(0), now: now, calendar: Self.calendar), .days7)
        XCTAssertEqual(Stat.ReportBuilder.period(containing: dayStart(-1), now: now, calendar: Self.calendar), .days14)
        XCTAssertEqual(Stat.ReportBuilder.period(containing: dayStart(-20), now: now, calendar: Self.calendar), .days30)
        XCTAssertEqual(Stat.ReportBuilder.period(containing: dayStart(-83), now: now, calendar: Self.calendar), .days90)
        XCTAssertNil(Stat.ReportBuilder.period(containing: dayStart(-84), now: now, calendar: Self.calendar))

        // a day without readings: nothing to print, also the one with a bolus
        for offset in [1, 4] {
            let (empty, _) = weekSource()
            do {
                _ = try await Stat.ReportBuilder.build(
                    request(day: dayStart(offset)),
                    source: empty,
                    now: now,
                    calendar: Self.calendar
                )
                XCTFail("a day without readings made a report")
            } catch {
                XCTAssertEqual(error as? Stat.ReportError, .noDataOnDay)
            }
            // nothing else was read for it
            let emptyReads = await empty.reads
            XCTAssertEqual(emptyReads, ["trace"])
            let emptySessions = await [empty.begun, empty.ended]
            XCTAssertEqual(emptySessions, [1, 1])
        }

        // readings, but no insulin or meals of the day: the chart is made
        let bare = FakeSource(
            days: plainDays(7),
            traces: traces([2]),
            insulin: [],
            meals: [],
            input: InsulinInput()
        )
        let glucoseOnly = try await Stat.ReportBuilder.build(
            request(day: dayStart(2)),
            source: bare,
            now: now,
            calendar: Self.calendar
        )
        XCTAssertEqual(glucoseOnly.chartDays.count, 1)
        XCTAssertNil(glucoseOnly.chartDays[0].tdd)
        XCTAssertNil(glucoseOnly.chartDays[0].carbs)
        XCTAssertEqual(glucoseOnly.chartDays[0].boluses, [])
        XCTAssertEqual(glucoseOnly.pages(calendar: Self.calendar).count, 1)
    }

    // MARK: - The written file

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-report-days-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func plainText(_ document: PDFDocument) -> String {
        (document.string ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// A week's Days table (one landscape page) and Daily charts (seven days, four a page: two portrait pages).
    @MainActor func testWritesDaysTableAndDailyCharts() async throws {
        let (source, now) = weekSource()
        let built = try await Stat.ReportBuilder.build(
            request(period: .days7, parts: [.daysTable, .dailyCharts]),
            source: source,
            now: now,
            calendar: Self.calendar
        )
        // every day drawn: a trace on each
        var data = built
        data.chartDays = (0 ..< 7).map { offset in
            var day = chartDay(offset)
            day.tdd = 35
            day.carbs = 60
            day.carbEntries = [ReportCarbEntry(time: dayStart(offset).addingTimeInterval(.hours(8)), grams: 60)]
            day.boluses = [
                InsulinBolus(date: dayStart(offset).addingTimeInterval(.hours(8)), units: 4, isSMB: false, isExternal: false),
                InsulinBolus(date: dayStart(offset).addingTimeInterval(.hours(10)), units: 0.4, isSMB: true, isExternal: false)
            ]
            day.basal = [ReportBasalStep(interval: dayInterval(offset), rate: 0.9, scheduled: 0.8)]
            return day
        }
        var steps: [Int] = []
        let parent = try temporaryDirectory()
        let output = try await ReportPDFWriter
            .write(data, version: "9.9.9", parent: parent, calendar: Self.calendar) { done, total in
                XCTAssertEqual(total, 3)
                steps.append(done)
            }
        XCTAssertEqual(steps, [1, 2, 3])
        XCTAssertEqual(output.url.lastPathComponent, "iAPS report 2026-10-20 – 2026-10-26.pdf")
        let document = try XCTUnwrap(PDFDocument(url: output.url))
        XCTAssertEqual(document.pageCount, 3)
        let sizes = try (0 ..< 3).map { try XCTUnwrap(document.page(at: $0)).bounds(for: .mediaBox).size }
        XCTAssertEqual(sizes[0].width, 842, accuracy: 0.5)
        XCTAssertEqual(sizes[0].height, 595, accuracy: 0.5)
        for size in sizes.suffix(2) {
            XCTAssertEqual(size.width, 595, accuracy: 0.5)
            XCTAssertEqual(size.height, 842, accuracy: 0.5)
        }
        let text = plainText(document)
        for expected in [
            "Days table",
            "Daily charts",
            "Average of 7 days",
            "Bolus + SMB",
            "In range 100%",
            "Scheduled basal",
            // drawn inside the charts' canvas: real text too
            hourLabel(3),
            StatsAmount.number(4, digits: 1 ... 2),
            "350",
            "Page 3 of 3",
            "Time in ranges is time-weighted"
        ] {
            XCTAssertTrue(text.contains(expected), "missing \"\(expected)\"")
        }
    }

    /// One day on a landscape Letter page, in both units: two pages.
    @MainActor func testWritesASingleDay() async throws {
        let (source, now) = weekSource()
        let data = try await Stat.ReportBuilder.build(
            request(units: [.mgdL, .mmolL], paper: .letter, day: dayStart(2)),
            source: source,
            now: now,
            calendar: Self.calendar
        )
        let parent = try temporaryDirectory()
        let output = try await ReportPDFWriter.write(data, version: "9.9.9", parent: parent, calendar: Self.calendar)
        XCTAssertEqual(output.url.lastPathComponent, "iAPS report 2026-10-22 – 2026-10-22.pdf")
        let document = try XCTUnwrap(PDFDocument(url: output.url))
        XCTAssertEqual(document.pageCount, 2)
        let size = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox).size
        XCTAssertEqual(size.width, 792, accuracy: 0.5)
        XCTAssertEqual(size.height, 612, accuracy: 0.5)
        let text = plainText(document)
        XCTAssertTrue(text.contains("Daily charts"))
        XCTAssertTrue(text.contains("mmol/L"))
    }

    /// "3:00" as a chart's tick writes it.
    private func hourLabel(_ hour: Int) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = Self.calendar.timeZone
        return dayStart(0).addingTimeInterval(.hours(hour)).formatted(style)
    }

    // MARK: - Review fixes

    /// Thinning keeps every stretch's extremes: a low or a peak of a minute is drawn, and the scale covers it.
    @MainActor func testThinningKeepsExtremes() throws {
        func minutes(_ values: [Int16], from start: Date) -> [GlucosePoint] {
            values.enumerated().map { GlucosePoint(time: start.addingTimeInterval(.minutes($0.offset)), mgdl: $0.element) }
        }
        let dip = minutes([58, 55, 52, 53, 56, 60], from: dayStart(0))
        let kept = ReportChartsBuilder.thinned(dip)
        XCTAssertTrue(kept.contains(dip[2]), "the lowest reading was thinned away")
        XCTAssertEqual(kept.first, dip.first)
        XCTAssertEqual(kept.last, dip.last)
        XCTAssertEqual(kept, kept.sorted { $0.time < $1.time })

        // a day at 120 with a one-minute peak of 390 and a one-minute low of 45
        var day = points(0, fromHour: 0, toHour: 24, everyMinutes: 1)
        day[600] = GlucosePoint(time: day[600].time, mgdl: 390)
        day[900] = GlucosePoint(time: day[900].time, mgdl: 45)
        let thinned = ReportChartsBuilder.thinned(day)
        XCTAssertTrue(thinned.contains(day[600]))
        XCTAssertTrue(thinned.contains(day[900]))
        XCTAssertEqual(thinned.map(\.mgdl).max(), 390)
        XCTAssertEqual(thinned.map(\.mgdl).min(), 45)
        // still thinned: at most two readings of each 4.5 minutes, and the stretch's ends
        XCTAssertLessThan(thinned.count, day.count / 2)
        XCTAssertEqual(thinned, thinned.sorted { $0.time < $1.time })
        XCTAssertEqual(Set(thinned.map(\.time)).count, thinned.count)

        // through the builder to the page: the axis' top covers the raw maximum
        let charts = ReportChartsBuilder.days(
            [dayInterval(0)],
            traces: [trace(0, day)],
            insulinDays: [],
            mealDays: [],
            input: nil,
            settings: .init(),
            now: dayStart(1),
            calendar: Self.calendar
        )
        XCTAssertEqual(charts.first?.points.map(\.mgdl).max(), 390)
        let page = Stat.ReportChartsPage(
            try chartsData(.init(), charts),
            page: ReportPage(part: .dailyCharts, units: .mgdL, size: ReportPaper.a4.size, index: 0),
            calendar: Self.calendar
        )
        XCTAssertEqual(page.axis, 0 ... 400)
        XCTAssertEqual(page.panels[0].lines.flatMap { $0 }.map(\.mgdl).max(), 390)
    }

    /// The header's insulin of a day outside the averages has the Days table's `*`, explained once under the legend.
    @MainActor func testChartHeaderMarksInsulinOutsideTheAverages() throws {
        let days = (0 ..< 3).map(dayInterval)
        let dayTraces = (0 ..< 3).map { trace($0, points($0, fromHour: 0, toHour: 24, everyMinutes: 5)) }
        let charts = ReportChartsBuilder.days(
            days,
            traces: dayTraces,
            insulinDays: [
                insulinDay(0, basal: 20, smb: 5, bolus: 10),
                insulinDay(1, basal: 5, smb: 1, bolus: 2, covered: 0.25),
                insulinDay(2, basal: 9, smb: 2, bolus: 4, isToday: true)
            ],
            mealDays: [],
            input: nil,
            settings: .init(),
            now: dayStart(3),
            calendar: Self.calendar
        )
        XCTAssertEqual(charts.map(\.tddOutsideAverage), [false, true, true])
        let chartsPage = ReportPage(part: .dailyCharts, units: .mgdL, size: ReportPaper.a4.size, index: 0)
        let page = Stat.ReportChartsPage(try chartsData(.init(), charts), page: chartsPage, calendar: Self.calendar)
        XCTAssertTrue(page.panels[0].stats.hasSuffix("Insulin " + StatsAmount.units(35, digits: 1)))
        XCTAssertTrue(page.panels[1].stats.hasSuffix("Insulin " + StatsAmount.units(8, digits: 1) + "*"))
        XCTAssertTrue(page.panels[2].stats.hasSuffix("Insulin " + StatsAmount.units(15, digits: 1) + "*"))
        XCTAssertEqual(page.notes.count, 1)
        XCTAssertTrue(page.notes[0].hasPrefix("* "))
        // the note takes a line of the page: the panels are that much shorter
        let plain = Stat.ReportChartsPage(try chartsData(.init(), [charts[0]]), page: chartsPage, calendar: Self.calendar)
        XCTAssertEqual(plain.notes, [])
        XCTAssertLessThan(page.panelSize.height, plain.panelSize.height)
        XCTAssertEqual(page.panelSize.width, plain.panelSize.width)
    }

    /// Marks whose labels would overprint are one: the window comes from the label's width on the layout's plot.
    @MainActor func testMergeWindowByLayout() throws {
        typealias Metrics = ReportChartMetrics
        func bolus(_ hour: Double, _ units: Double) -> InsulinBolus {
            InsulinBolus(date: dayStart(0).addingTimeInterval(.hours(hour)), units: units, isSMB: false, isExternal: false)
        }
        func chartsPage(_ perPage: Int, paper: ReportPaper) throws -> Stat.ReportChartsPage {
            var settings = ReportOptions.DailyChartsSettings()
            settings.daysPerPage = perPage
            var day = chartDay(0)
            // 40 and 70 minutes apart, and at the day's edges
            day.boluses = [bolus(0, 1), bolus(8, 4), bolus(8.67, 2), bolus(12, 3), bolus(13.17, 1), bolus(23.99, 2)]
            day.carbEntries = [8, 8.5, 12, 12.2].map {
                ReportCarbEntry(time: dayStart(0).addingTimeInterval(.hours($0)), grams: 20)
            }
            return Stat.ReportChartsPage(
                try chartsData(settings, [day]),
                page: ReportPage(part: .dailyCharts, units: .mgdL, size: paper.size(landscape: settings.isLandscape), index: 0),
                calendar: Self.calendar
            )
        }
        for paper in ReportPaper.allCases {
            var windows: [Int: TimeInterval] = [:]
            for perPage in ReportOptions.DailyChartsSettings.daysPerPageChoices {
                let page = try chartsPage(perPage, paper: paper)
                let plotWidth = Metrics.plotWidth(panelWidth: page.panelSize.width)
                let size = perPage == 8 ? Metrics.compactBolusLabelSize : Metrics.labelSize
                let labelWidth = Metrics.labelWidth(characters: Metrics.bolusLabelCharacters, size: size)
                XCTAssertEqual(
                    page.bolusMergeWindow,
                    Swift.max(TimeInterval((labelWidth + 2) / plotWidth) * .hours(24), .minutes(15)),
                    accuracy: 1E-6
                )
                // two labels a window apart don't touch
                XCTAssertGreaterThanOrEqual(CGFloat(page.bolusMergeWindow / .hours(24)) * plotWidth, labelWidth)
                XCTAssertGreaterThanOrEqual(page.bolusMergeWindow, .minutes(15))
                let boluses = page.panels[0].boluses
                for (first, second) in zip(boluses, boluses.dropFirst()) {
                    XCTAssertGreaterThan(
                        CGFloat(second.x - first.x) * plotWidth,
                        labelWidth,
                        "\(perPage) a page on \(paper): bolus labels overprint"
                    )
                }
                // merged or not, the units are all there
                XCTAssertEqual(boluses.reduce(0) { $0 + $1.amount }, 13, accuracy: 1E-9)
                XCTAssertEqual(page.panels[0].carbs.reduce(0) { $0 + $1.amount }, 80, accuracy: 1E-9)
                if perPage == 8 {
                    // no carb labels: only entries a quarter of an hour apart are one mark
                    XCTAssertEqual(page.carbsMergeWindow, .minutes(15))
                    XCTAssertEqual(page.panels[0].carbs.map(\.amount), [20, 20, 40])
                } else {
                    let carbsWidth = Metrics.labelWidth(characters: Metrics.carbsLabelCharacters, size: Metrics.labelSize)
                    XCTAssertGreaterThanOrEqual(CGFloat(page.carbsMergeWindow / .hours(24)) * plotWidth, carbsWidth)
                }
                windows[perPage] = page.bolusMergeWindow
            }
            // the narrower the plot, the longer the window
            XCTAssertLessThan(try XCTUnwrap(windows[1]), try XCTUnwrap(windows[4]))
            XCTAssertEqual(try XCTUnwrap(windows[2]), try XCTUnwrap(windows[4]), accuracy: 1E-6)
            XCTAssertLessThan(try XCTUnwrap(windows[4]), try XCTUnwrap(windows[8]))
        }
        // one a page on A4: 40 minutes apart are two marks, four a page one
        XCTAssertEqual(try chartsPage(1, paper: .a4).panels[0].boluses.map(\.amount), [1, 4, 2, 3, 1, 2])
        XCTAssertEqual(try chartsPage(4, paper: .a4).panels[0].boluses.map(\.amount), [1, 6, 3, 1, 2])
        XCTAssertEqual(Metrics.mergeWindow(labelWidth: 1, plotWidth: 1000), .minutes(15))
    }

    /// The Days table and Daily charts say what couldn't be read, apart from "no data".
    @MainActor func testFailedReadsAreSaid() async throws {
        let (plainSource, now) = weekSource()
        let plain = try await Stat.ReportBuilder.build(
            request(period: .days7, parts: [.daysTable, .dailyCharts]),
            source: plainSource,
            now: now,
            calendar: Self.calendar
        )
        XCTAssertEqual(plain.failedReads, [])

        let failing = FakeSource(
            days: plainDays(7),
            traces: traces([0, 2, 6]),
            insulin: [],
            meals: [],
            input: InsulinInput(),
            failing: [.insulin, .meals, .pumpEvents]
        )
        let data = try await Stat.ReportBuilder.build(
            request(period: .days7, parts: [.daysTable, .dailyCharts]),
            source: failing,
            now: now,
            calendar: Self.calendar
        )
        XCTAssertEqual(data.failedReads, [.insulin, .meals, .pumpEvents])
        let sessions = await [failing.begun, failing.ended]
        XCTAssertEqual(sessions, [1, 1])
        // the report is still made, with what was read
        XCTAssertEqual(data.chartDays.count, 3)
        XCTAssertEqual(data.insulinDays, [])

        let table = Stat.ReportDaysPage(data, page: page(.daysTable), calendar: Self.calendar)
        XCTAssertTrue(table.footnote.hasPrefix("Insulin data could not be read. Carb entries could not be read. "))
        XCTAssertFalse(table.footnote.contains("Insulin is averaged"))
        XCTAssertFalse(table.footnote.contains("Carbs are averaged"))
        let okTable = Stat.ReportDaysPage(plain, page: page(.daysTable), calendar: Self.calendar)
        XCTAssertFalse(okTable.footnote.contains("could not be read"))
        XCTAssertTrue(okTable.footnote.contains("Insulin is averaged"))

        let chartsPage = ReportPage(part: .dailyCharts, units: .mgdL, size: ReportPaper.a4.size, index: 0)
        let charts = Stat.ReportChartsPage(data, page: chartsPage, calendar: Self.calendar)
        XCTAssertEqual(charts.notes.count, 1)
        XCTAssertTrue(charts.notes[0].contains("Insulin data could not be read."))
        XCTAssertTrue(charts.notes[0].contains("Pump events could not be read"))
        XCTAssertTrue(charts.notes[0].contains("Carb entries could not be read."))
        XCTAssertEqual(Stat.ReportChartsPage(plain, page: chartsPage, calendar: Self.calendar).notes, [])

        // a column that is off isn't reported; the single day's report carries its failures too
        var settings = ReportOptions.DaysTableSettings()
        settings.insulin = false
        let hidden = try Stat.ReportBuilder.assemble(
            request(period: .days7, daysTable: settings),
            summary: data.summary,
            bins: [],
            glucoseDays: data.glucoseDays,
            failedReads: [.insulin],
            now: now
        )
        XCTAssertFalse(
            Stat.ReportDaysPage(hidden, page: page(.daysTable), calendar: Self.calendar).footnote
                .contains("could not")
        )

        let single = FakeSource(
            days: plainDays(7),
            traces: traces([2]),
            insulin: [],
            meals: [],
            input: InsulinInput(),
            failing: [.insulin, .pumpEvents]
        )
        let day = try await Stat.ReportBuilder.build(request(day: dayStart(2)), source: single, now: now, calendar: Self.calendar)
        XCTAssertEqual(day.failedReads, [.insulin, .pumpEvents])
        XCTAssertEqual(day.chartDays.count, 1)
    }

    /// Cancelled between two days' traces: the build stops there, its session closed.
    func testBuilderCancelledBetweenTraces() async throws {
        let (_, now) = weekSource()
        let source = FakeSource(
            days: plainDays(7),
            traces: traces([0, 2, 6]),
            insulin: [],
            meals: [],
            input: InsulinInput(),
            cancelsAtTrace: 3
        )
        let charts = request(period: .days7, parts: [.dailyCharts])
        let calendar = Self.calendar
        let task = Task { try await Stat.ReportBuilder.build(charts, source: source, now: now, calendar: calendar) }
        do {
            _ = try await task.value
            XCTFail("a cancelled build returned")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let reads = await source.reads
        XCTAssertEqual(reads.filter { $0 == "trace" }.count, 3)
        XCTAssertFalse(reads.contains("events"))
        let sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions, [1, 1])
    }

    /// The Days table's days, its Average row and the Summary's numbers are one read's: the profile's own summary
    /// (read a moment earlier) isn't used beside the table.
    @MainActor func testAverageRowIsTheSummary() async throws {
        let (_, now) = weekSource()
        let days = plainDays(7)
        // the profile was read before a high stretch came in
        let earlier = GlucoseStatsEngine.summary(
            days: periodDays(7) { self.aggregate($0, [(120, 1)]) }.days,
            window: days.window,
            endRule: .stalled,
            period: .days7,
            bands: Stat.ReportBuilder.standardBands(.mgdL)
        )
        func source() -> FakeSource {
            FakeSource(days: days, traces: [:], insulin: [], meals: [], input: InsulinInput(), profile: earlier)
        }
        let data = try await Stat.ReportBuilder.build(
            request(period: .days7, parts: [.summary, .daysTable]),
            source: source(),
            now: now,
            calendar: Self.calendar
        )
        XCTAssertNotEqual(data.summary.bandShares, earlier.bandShares)
        let rows = ReportDaysBuilder.rows(data, calendar: Self.calendar)
        guard case let .average(_, average) = rows.last else { return XCTFail("the last row isn't the Average") }
        XCTAssertEqual(average.shares, data.summary.bandShares)
        XCTAssertEqual(average.mean, data.summary.mean)
        XCTAssertEqual(average.sd, data.summary.sd)
        XCTAssertEqual(average.coverage, data.summary.coveragePercent)
        let summary = Stat.ReportSummary(data, units: .mgdL)
        let table = Stat.ReportDaysPage(data, page: page(.daysTable), calendar: Self.calendar)
        XCTAssertEqual(table.rows.last?.cells[0], summary.rows[2].percent)
        XCTAssertEqual(table.rows.last?.cells[3] ?? "", String(summary.metrics[0].value.prefix(3)))

        // without the table the Summary is the profile's
        let alone = try await Stat.ReportBuilder.build(
            request(period: .days7, parts: [.summary]),
            source: source(),
            now: now,
            calendar: Self.calendar
        )
        XCTAssertEqual(alone.summary.bandShares, earlier.bandShares)
    }

    /// Subtotals and the Average are time-weighted: a half-covered day counts half, the 25-hour day a little more.
    func testPoolingIsTimeWeighted() throws {
        var settings = ReportOptions.DaysTableSettings()
        settings.subtotals = .week
        // Mon 26 Oct: all day at 120; Tue: half the day, all of it at 200; then the next week
        let days = PeriodDays(
            window: DateInterval(start: dayStart(6), end: dayStart(8)),
            endRule: .stalled,
            days: [aggregate(6, [(120, 1)]), aggregate(7, [(200, 0.5)])]
        )
        let rows = ReportDaysBuilder.rows(
            try data(request(period: .days7, daysTable: settings), days: days),
            calendar: Self.calendar
        )
        XCTAssertEqual(rows.count, 4)
        guard case let .subtotal(_, _, week) = rows[2], case let .average(_, average) = rows[3] else {
            return XCTFail("no subtotal and Average after the two days")
        }
        // 24 h in range, 12 h above: a third above, not the days' mean of 0% and 100%
        XCTAssertEqual(try XCTUnwrap(week.above), 100.0 / 3, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(week.mean), (24 * 120.0 + 12 * 200) / 36, accuracy: 1E-9)
        XCTAssertEqual(week.coverage, 75)
        XCTAssertEqual(average, week)
        XCTAssertEqual(try XCTUnwrap(dayRow(rows[1])).numbers.coverage, 50)
        XCTAssertEqual(try XCTUnwrap(dayRow(rows[1])).numbers.above, 100)

        // Sat 24 Oct (24 h) at 200, Sun 25 Oct (25 h, the end of summer time) at 120
        let change = PeriodDays(
            window: DateInterval(start: dayStart(4), end: dayStart(6)),
            endRule: .stalled,
            days: [aggregate(4, [(200, 1)]), aggregate(5, [(120, 1)])]
        )
        XCTAssertEqual(dayInterval(5).duration, .hours(25))
        let long = ReportDaysBuilder.rows(
            try data(request(period: .days7, daysTable: settings), days: change),
            calendar: Self.calendar
        )
        guard case let .subtotal(_, _, weekend) = long[2] else { return XCTFail("no subtotal after the two days") }
        XCTAssertEqual(try XCTUnwrap(weekend.above), 24.0 / 49 * 100, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(weekend.mean), (24 * 200.0 + 25 * 120) / 49, accuracy: 1E-9)
        XCTAssertEqual(weekend.coverage, 100)
    }

    /// Today as the service gives it: clipped at the last reading's end, or still empty just after midnight.
    func testTodayAsTheServiceGivesIt() throws {
        // ten hours into the 14th day
        let end = dayStart(13).addingTimeInterval(.hours(10))
        var today = GlucoseHistogram()
        today.add(WeightedPoint(time: dayStart(13), mgdl: 200, span: .hours(10)), seconds: .hours(10), startsInside: true)
        let partial = PeriodDays(
            window: DateInterval(start: Self.day0, end: end),
            endRule: .stalled,
            days: (0 ..< 13).map { self.aggregate($0, [(120, 1)]) }
                + [DayAggregate(day: DateInterval(start: dayStart(13), end: end), histogram: today)]
        )
        let data = try data(request(), days: partial)
        let rows = ReportDaysBuilder.rows(data, calendar: Self.calendar)
        XCTAssertEqual(rows.count, 15)
        let row = try XCTUnwrap(dayRow(rows[13]))
        XCTAssertEqual(row.day, dayStart(13))
        // of the day so far
        XCTAssertEqual(row.numbers.coverage, 100)
        XCTAssertEqual(row.numbers.above, 100)
        guard case let .average(count, average) = rows[14] else { return XCTFail("the last row isn't the Average") }
        XCTAssertEqual(count, 14)
        XCTAssertEqual(average.coverage, 100)
        // 13 days and an hour (the 25-hour day) at 120, ten hours at 200
        XCTAssertEqual(try XCTUnwrap(average.above), 10.0 / (13 * 24 + 1 + 10) * 100, accuracy: 1E-9)
        XCTAssertEqual(average.shares, data.summary.bandShares)
        XCTAssertEqual(data.days(calendar: Self.calendar).last, dayStart(13))

        // just after midnight: today is an empty day of no length at its start, and still a row
        let midnight = PeriodDays(
            window: DateInterval(start: Self.day0, end: dayStart(13)),
            endRule: .stalled,
            days: (0 ..< 13).map { self.aggregate($0, [(120, 1)]) }
                + [DayAggregate(day: DateInterval(start: dayStart(13), duration: 0), histogram: GlucoseHistogram())]
        )
        let early = try self.data(request(), days: midnight)
        let earlyRows = ReportDaysBuilder.rows(early, calendar: Self.calendar)
        XCTAssertEqual(earlyRows.count, 15)
        let empty = try XCTUnwrap(dayRow(earlyRows[13]))
        XCTAssertEqual(empty.day, dayStart(13))
        XCTAssertFalse(empty.numbers.hasGlucose)
        guard case let .average(_, earlyAverage) = earlyRows[14] else { return XCTFail("the last row isn't the Average") }
        XCTAssertEqual(earlyAverage.coverage, 100)
        XCTAssertEqual(earlyAverage.shares?.percents[GlucoseBand.inRange.rawValue], 100)
        XCTAssertEqual(early.days(calendar: Self.calendar).last, dayStart(13))
        XCTAssertEqual(early.pages(calendar: Self.calendar).count, 1)
    }

    /// The basal lane's steps through the engine's timeline: a temp running in over midnight, a suspension as zero,
    /// time without pump data, and steps cut at midnight.
    func testChartBasalThroughTheTimeline() throws {
        func at(_ day: Int, _ hour: Double) -> Date { dayStart(day).addingTimeInterval(.hours(hour)) }
        let schedule = BasalScheduleRecordValue(
            date: dayStart(-2),
            source: .local,
            entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
        )
        let input = InsulinInput(
            events: [
                // running into the window: started half an hour before its first midnight
                PumpEventRecord(date: at(0, 23.5), kind: .tempBasal, source: .pump, units: -1, rate: 1.5, durationMin: 60.1),
                PumpEventRecord(date: at(1, 10), kind: .suspend, source: .pump),
                PumpEventRecord(date: at(1, 11), kind: .resume, source: .pump),
                // outside the pump data
                PumpEventRecord(date: at(1, 20), kind: .tempBasal, source: .pump, units: -1, rate: 2, durationMin: 30.1)
            ],
            coverage: [
                CoveredInterval(interval: DateInterval(start: at(1, 0), end: at(1, 18)), source: .pump),
                CoveredInterval(interval: DateInterval(start: at(1, 22), end: at(3, 0)), source: .pump)
            ],
            schedules: [schedule]
        )
        let days = [dayInterval(1), dayInterval(2)]
        let charts = ReportChartsBuilder.days(
            days,
            traces: [],
            insulinDays: [],
            mealDays: [],
            input: input,
            settings: .init(),
            now: dayStart(3),
            calendar: Self.calendar
        )
        XCTAssertEqual(charts.map(\.day), days)
        let first = charts[0].basal
        func step(_ steps: [ReportBasalStep], at date: Date) -> ReportBasalStep? {
            steps.first { $0.interval.start <= date && date < $0.interval.end }
        }
        // the temp's second half hour
        XCTAssertEqual(first.first?.interval.start, at(1, 0))
        XCTAssertEqual(step(first, at: at(1, 0.25))?.rate, 1.5)
        XCTAssertEqual(step(first, at: at(1, 0.25))?.scheduled, 1)
        XCTAssertEqual(try XCTUnwrap(first.first?.interval.end.timeIntervalSince(at(1, 0.5))), 0, accuracy: 1)
        // then the schedule
        XCTAssertEqual(step(first, at: at(1, 5))?.rate, 1)
        XCTAssertEqual(step(first, at: at(1, 5))?.scheduled, 1)
        // the hours of the schedule are one step, not 24
        XCTAssertEqual(step(first, at: at(1, 1))?.interval.end, at(1, 10))
        // suspended: zero delivered, the schedule still drawn
        XCTAssertEqual(step(first, at: at(1, 10.5))?.rate, 0)
        XCTAssertEqual(step(first, at: at(1, 10.5))?.scheduled, 1)
        XCTAssertEqual(step(first, at: at(1, 12))?.rate, 1)
        // no pump data: nothing, but a temp there is drawn, without a scheduled line
        XCTAssertNil(step(first, at: at(1, 19)))
        XCTAssertEqual(step(first, at: at(1, 20.25))?.rate, 2)
        XCTAssertNil(try XCTUnwrap(step(first, at: at(1, 20.25))).scheduled)
        XCTAssertNil(step(first, at: at(1, 21)))
        // covered again, and cut at midnight: each day has its own steps
        XCTAssertEqual(first.last?.interval, DateInterval(start: at(1, 22), end: at(2, 0)))
        XCTAssertEqual(charts[1].basal, [ReportBasalStep(interval: dayInterval(2), rate: 1, scheduled: 1)])
        XCTAssertTrue(first.allSatisfy { $0.interval.start >= days[0].start && $0.interval.end <= days[0].end })
    }

    /// The day's positions by the elapsed time, its ticks by the clock: the 23-hour day, and the repeated hour of the
    /// 25-hour one.
    @MainActor func testPanelsOnDaysOfAClockChange() throws {
        let calendar = Self.calendar
        // Sun 29 Mar 2026: 02:00 becomes 03:00
        let spring = Date(timeIntervalSince1970: 1_774_738_800)
        let short = DateInterval(start: spring, end: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: spring)))
        XCTAssertEqual(short.duration, .hours(23))
        var shortDay = ReportChartDay(day: short)
        shortDay.points = (0 ..< 12)
            .map { GlucosePoint(time: spring.addingTimeInterval(.hours(6) + .minutes(5 * $0)), mgdl: 120) }
        shortDay.shares = BandShares(fractions: [0, 0, 1, 0, 0])
        // Sun 25 Oct 2026: 03:00 becomes 02:00; a bolus in each pass of the repeated hour
        var longDay = chartDay(5)
        XCTAssertEqual(longDay.day.duration, .hours(25))
        longDay.boluses = [2.5, 3.5].map {
            InsulinBolus(date: dayStart(5).addingTimeInterval(.hours($0)), units: 1, isSMB: true, isExternal: false)
        }
        var settings = ReportOptions.DailyChartsSettings()
        settings.daysPerPage = 2
        let page = Stat.ReportChartsPage(
            try chartsData(settings, [shortDay, longDay]),
            page: ReportPage(part: .dailyCharts, units: .mgdL, size: ReportPaper.a4.size, index: 0),
            calendar: calendar
        )
        let shortPanel = page.panels[0]
        // six hours in is 07:00 that day, 6/23 of it
        XCTAssertEqual(try XCTUnwrap(shortPanel.lines.first?.first?.x), 6.0 / 23, accuracy: 1E-9)
        XCTAssertEqual(shortPanel.ticks.count, 8)
        // 03:00 is two hours in, 06:00 five
        XCTAssertEqual(shortPanel.ticks.map(\.x)[1], 2.0 / 23, accuracy: 1E-9)
        XCTAssertEqual(shortPanel.ticks.map(\.x)[2], 5.0 / 23, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(shortPanel.ticks.last?.x), 20.0 / 23, accuracy: 1E-9)

        let longPanel = page.panels[1]
        // 02:30 twice: an hour apart on the panel
        XCTAssertEqual(longPanel.smbs.map(\.x)[0], 2.5 / 25, accuracy: 1E-9)
        XCTAssertEqual(longPanel.smbs.map(\.x)[1], 3.5 / 25, accuracy: 1E-9)
        XCTAssertEqual(longPanel.ticks.count, 8)
        // 03:00 is four hours in, 06:00 seven
        XCTAssertEqual(longPanel.ticks.map(\.x)[1], 4.0 / 25, accuracy: 1E-9)
        XCTAssertEqual(longPanel.ticks.map(\.x)[2], 7.0 / 25, accuracy: 1E-9)
        XCTAssertTrue(page.panels.flatMap(\.ticks).allSatisfy { $0.x >= 0 && $0.x < 1 })
    }

    /// The estimate is never under the report's pages, and exact when every day has data and there are no subtotals.
    func testEstimateAgainstTheRealPlan() throws {
        typealias Days = ReportOptions.DaysTableSettings
        func real(_ options: ReportOptions, days count: Int, chartDays: [Int]) throws -> Int {
            let units = options.units.printed(userUnits: .mgdL)
            let planned = request(
                period: options.period,
                parts: options.orderedParts,
                units: units,
                paper: options.paper,
                daysTable: options.daysTable,
                dailyCharts: options.dailyCharts
            )
            let charts = chartDays.map { chartDay($0) }
            let built: Stat.ReportData = try data(planned, days: plainDays(count), charts: charts)
            return built.pages(calendar: Self.calendar).count
        }
        for (period, count) in [(StatsPeriod.days7, 7), (.days14, 14), (.days30, 30), (.days90, 90)] {
            for paper in ReportPaper.allCases {
                for units in ReportUnits.allCases {
                    for perPage in ReportOptions.DailyChartsSettings.daysPerPageChoices {
                        var options = ReportOptions(
                            period: period,
                            units: units,
                            paper: paper,
                            parts: Set(ReportPart.implemented)
                        )
                        options.dailyCharts.daysPerPage = perPage
                        // every day has data, no subtotals: exact
                        XCTAssertFalse(ReportPlan.isUpperBound([.daysTable], daysTable: options.daysTable))
                        XCTAssertTrue(options.estimateIsUpperBound)
                        XCTAssertEqual(
                            try real(options, days: count, chartDays: Array(0 ..< count)),
                            options.estimatedPageCount,
                            "\(period) \(paper) \(units) \(perPage)"
                        )
                        // some days without anything to draw: at most the estimate
                        XCTAssertLessThanOrEqual(
                            try real(options, days: count, chartDays: Array(stride(from: 0, to: count, by: 3))),
                            options.estimatedPageCount
                        )
                        for subtotals in [Days.Subtotals.week, .month] {
                            options.daysTable.subtotals = subtotals
                            XCTAssertLessThanOrEqual(
                                try real(options, days: count, chartDays: Array(0 ..< count)),
                                options.estimatedPageCount,
                                "\(period) \(paper) \(units) \(perPage) \(subtotals)"
                            )
                        }
                    }
                }
            }
        }
        var table = ReportOptions(period: .days90, units: .mgdL, paper: .a4, parts: [.summary, .percentileProfile, .daysTable])
        XCTAssertFalse(table.estimateIsUpperBound)
        table.daysTable.subtotals = .month
        XCTAssertTrue(table.estimateIsUpperBound)
        XCTAssertEqual(ReportsScreen.pages(7), "7 pages")
        XCTAssertEqual(ReportsScreen.pages(7, upTo: true), "Up to 7 pages")
        XCTAssertEqual(ReportsScreen.pages(1, upTo: true), "1 page")
    }

    /// The window's pump events from the store: the state running into it, nothing after the report's `now`.
    func testInsulinInputFromTheStore() async throws {
        let container = StatsFixtures.inMemoryContainer()
        let window = DateInterval(start: dayStart(1), end: dayStart(2))
        let now = dayStart(1).addingTimeInterval(.hours(12))
        let events = [
            PumpEventRecord(
                date: dayStart(1).addingTimeInterval(-.minutes(20)),
                kind: .tempBasal,
                source: .pump,
                units: -1,
                rate: 1.5,
                durationMin: 60.1
            ),
            PumpEventRecord(date: dayStart(1).addingTimeInterval(.hours(8)), kind: .bolus, source: .pump, units: 4),
            PumpEventRecord(
                date: dayStart(1).addingTimeInterval(.hours(9)),
                kind: .bolus,
                source: .pump,
                units: 0.3,
                isSMB: true
            ),
            // after the report's now
            PumpEventRecord(date: dayStart(1).addingTimeInterval(.hours(13)), kind: .bolus, source: .pump, units: 9)
        ]
        let schedule = BasalScheduleRecordValue(
            date: dayStart(-2),
            source: .local,
            entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
        )
        try await container.performBackgroundTask { context in
            for record in events {
                CoreDataPumpEventDatabase.apply(record, to: PumpEvent(context: context))
            }
            let row = BasalScheduleRecord(context: context)
            row.date = schedule.date
            row.source = schedule.source.rawValue
            row.entries = BasalScheduleRecordValue.encode(schedule.entries)
            row.fingerprint = BasalScheduleRecordValue.fingerprint(schedule.entries)
            try context.save()
        }
        let input = try await Stat.ReportBuilder.insulinInput(window, now: now, source: CoreDataStorage(container: container))
        XCTAssertEqual(input.events.filter { $0.kind == .bolus }.map(\.units).sorted(), [0.3, 4])
        XCTAssertEqual(input.events.filter { $0.kind == .tempBasal }.map(\.rate), [1.5])
        XCTAssertEqual(input.schedules.map(\.date), [schedule.date])
        XCTAssertEqual(input.iob, [])

        // through the builder's cut: the bolus and the SMB of the day, the temp's rest after midnight
        let charts = ReportChartsBuilder.days(
            [dayInterval(1)],
            traces: [],
            insulinDays: [],
            mealDays: [],
            input: input,
            settings: .init(),
            now: now,
            calendar: Self.calendar
        )
        XCTAssertEqual(charts.first?.boluses.map(\.units), [4, 0.3])
        XCTAssertEqual(charts.first?.basal.first?.rate, 1.5)
        XCTAssertEqual(charts.first?.basal.first?.interval.start, dayStart(1))
    }
}
