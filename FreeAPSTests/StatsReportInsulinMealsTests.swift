@testable import FreeAPS
import PDFKit
import XCTest

/// The PDF reports' Insulin and Meals parts: the amounts that add up as printed, the tables' pages, the page models,
/// the empty states, the kept setting, the reads and the written file.
final class StatsReportInsulinMealsTests: XCTestCase {
    typealias Layout = ReportTablesLayout

    /// Europe/Berlin, weeks from Monday
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// 2027-01-20 12:00 Europe/Berlin, a Wednesday
    private static let now = calendar.date(from: DateComponents(year: 2027, month: 1, day: 20, hour: 12))!

    // MARK: - Fixtures

    private static func days(_ period: StatsPeriod) -> [DateInterval] {
        InsulinStatsEngine.periodDays(period, now: now, calendar: calendar)
    }

    /// A day's insulin, the same every hour: `covered` of the day has pump data.
    private static func insulinDay(
        _ day: DateInterval,
        basal: Double,
        smb: Double,
        bolus: Double,
        covered: Double = 1,
        isToday: Bool = false,
        hasDeliveries: Bool = true
    ) -> DayInsulin {
        let hours = (0 ..< 24).map { hour -> HourInsulin in
            var value = HourInsulin(hour: hour)
            value.basal = basal / 24
            value.smb = smb / 24
            value.bolus = bolus / 24
            value.scheduled = basal / 24
            value.coveredSeconds = .hours(1) * covered
            value.zeroBasalSeconds = hour == 3 ? .minutes(20) * covered : 0
            return value
        }
        return DayInsulin(
            day: day,
            isToday: isToday,
            basal: basal,
            smb: smb,
            bolus: bolus,
            scheduled: basal,
            zeroBasalSeconds: .minutes(20) * covered,
            coveredSeconds: day.duration * covered,
            negativeIOBSeconds: 0,
            iobSeconds: 0,
            iob: .empty,
            hours: hours,
            hasDeliveries: hasDeliveries,
            coveredUntil: covered > 0 ? day.start.addingTimeInterval(day.duration * covered) : nil,
            profileAssumedBefore: nil,
            boluses: []
        )
    }

    /// The period's days: amounts that don't round to their total part by part (20.04 + 5.04 + 3.04 = 28.12), the
    /// fourth day with pump data for a third of it, the sixth without any, the last one today, half over.
    private static func insulin(_ period: StatsPeriod) -> InsulinPeriod {
        let intervals = days(period)
        let days = intervals.enumerated().map { index, day -> DayInsulin in
            let basal = 20.04 + Double(index % 5) * 0.31
            if index == intervals.count - 1 {
                return insulinDay(day, basal: basal / 2, smb: 2.52, bolus: 1.52, covered: 0.5, isToday: true)
            }
            if index == 3 {
                return insulinDay(day, basal: basal * 0.3, smb: 1.04, bolus: 2.04, covered: 0.3)
            }
            if index == 5 {
                return insulinDay(day, basal: 0, smb: 0, bolus: 0, covered: 0, hasDeliveries: false)
            }
            return insulinDay(day, basal: basal, smb: 5.04, bolus: 3.04)
        }
        return InsulinPeriod(
            summary: InsulinStatsEngine.summary(days, period: period),
            days: days,
            hours: InsulinStatsEngine.hours(days)
        )
    }

    private static func noInsulin(_ period: StatsPeriod) -> InsulinPeriod {
        let days = days(period).map { insulinDay($0, basal: 0, smb: 0, bolus: 0, covered: 0, hasDeliveries: false) }
        return InsulinPeriod(summary: InsulinStatsEngine.summary(days, period: period), days: days, hours: [])
    }

    /// Three meals a day with amounts that leave fractions per hour, fat and protein at dinner; the third day without
    /// an entry, today one so far.
    private static func meals(_ period: StatsPeriod, logged: Bool = true, today: Bool = true) -> MealPeriod {
        let intervals = days(period)
        var points: [MealPoint] = []
        for (index, day) in intervals.enumerated() {
            if index == 2 { continue }
            if index == intervals.count - 1 {
                if today {
                    points.append(MealPoint(id: nil, actualDate: day.start.addingTimeInterval(.hours(8)), carbs: 33))
                }
                continue
            }
            points
                .append(MealPoint(id: nil, actualDate: day.start.addingTimeInterval(.hours(8)), carbs: 40.4 + Double(index % 3)))
            points.append(MealPoint(id: nil, actualDate: day.start.addingTimeInterval(.hours(13.2)), carbs: 60.3))
            points.append(
                MealPoint(
                    id: nil,
                    actualDate: day.start.addingTimeInterval(.hours(19.5)),
                    carbs: 70.2,
                    fat: logged ? 22 : 0,
                    protein: logged ? 31 : 0
                )
            )
        }
        return MealStatsEngine.period(
            period,
            points: points,
            fatOrProteinLogged: logged,
            factor: 0.5,
            now: now,
            calendar: calendar
        )
    }

    private static func noMeals(_ period: StatsPeriod) -> MealPeriod {
        MealStatsEngine.period(period, points: [], fatOrProteinLogged: false, factor: 0.5, now: now, calendar: calendar)
    }

    /// A summary with data, on the standard bands: the period in range at 120.
    private static func summary(_ period: StatsPeriod) -> GlucoseSummary {
        let window = GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar)
        let aggregates = GlucoseStatsEngine.days(for: period, window: window, calendar: calendar).map { day -> DayAggregate in
            var histogram = GlucoseHistogram()
            histogram.add(
                WeightedPoint(time: day.start, mgdl: 120, span: day.duration),
                seconds: day.duration,
                startsInside: true
            )
            return DayAggregate(day: day, histogram: histogram)
        }
        return GlucoseStatsEngine.summary(
            days: aggregates,
            window: window,
            endRule: .stalled,
            period: period,
            bands: Stat.ReportBuilder.standardBands(.mgdL)
        )
    }

    private func request(
        period: StatsPeriod = .days14,
        parts: [ReportPart] = [.insulin, .meals],
        units: [GlucoseUnits] = [.mgdL],
        paper: ReportPaper = .a4,
        nutrients: Bool = false,
        tables: Bool = true
    ) -> Stat.ReportRequest {
        Stat.ReportRequest(
            period: period,
            parts: parts,
            units: units,
            hbA1cUnit: .percent,
            paper: paper,
            meals: ReportOptions.MealsSettings(includeNutrients: nutrients, detailedTables: tables),
            insulin: ReportOptions.InsulinSettings(detailedTables: tables)
        )
    }

    /// The report's data as the builder leaves it for the two parts.
    private func data(_ request: Stat.ReportRequest, logged: Bool = true) throws -> Stat.ReportData {
        var data = try Stat.ReportBuilder.assemble(request, summary: Self.summary(request.period), bins: [], now: Self.now)
        if request.parts.contains(.insulin) {
            data.insulinPeriod = .value(Self.insulin(request.period))
        }
        if request.parts.contains(.meals) {
            data.mealPeriod = .value(Self.meals(request.period, logged: logged))
        }
        return data
    }

    private func page(_ part: ReportPart, index: Int = 0) -> ReportPage {
        ReportPage(part: part, units: .mgdL, size: ReportPaper.a4.size, index: index)
    }

    /// A printed number, whatever the locale's decimal separator; nil for "–".
    private func number(_ text: String) -> Double? {
        let digits = text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    // MARK: - Amounts

    func testAmountsAddUpAsPrinted() {
        // each part rounds down, the total up: a tenth goes to the first of the equal remainders
        var split = ReportAmounts.split([20.04, 5.04, 3.04], decimals: 1)
        XCTAssertEqual(split.total, 28.1, accuracy: 1E-9)
        XCTAssertEqual(split.parts[0], 20.1, accuracy: 1E-9)
        XCTAssertEqual(split.parts[1], 5.0, accuracy: 1E-9)
        XCTAssertEqual(split.parts[2], 3.0, accuracy: 1E-9)
        // the largest remainder first
        split = ReportAmounts.split([1.26, 1.24, 1.24], decimals: 1)
        XCTAssertEqual(split.total, 3.7, accuracy: 1E-9)
        XCTAssertEqual(split.parts[0], 1.3, accuracy: 1E-9)
        XCTAssertEqual(split.parts[1], 1.2, accuracy: 1E-9)
        XCTAssertEqual(split.parts[2], 1.2, accuracy: 1E-9)
        // already exact, nothing, whole numbers, a negative value
        split = ReportAmounts.split([1.5, 2.5], decimals: 1)
        XCTAssertEqual(split.parts, [1.5, 2.5])
        XCTAssertEqual(split.total, 4)
        XCTAssertEqual(ReportAmounts.split([], decimals: 1).total, 0)
        XCTAssertEqual(ReportAmounts.split([0, 0, 0], decimals: 2).parts, [0, 0, 0])
        XCTAssertEqual(ReportAmounts.split([0.4, 0.4, 0.4], decimals: 0).parts.reduce(0, +), 1)
        split = ReportAmounts.split([-3, 2.04], decimals: 1)
        XCTAssertEqual(split.total, 2, accuracy: 1E-9)
        XCTAssertEqual(split.parts.count, 2)
        XCTAssertEqual(split.parts[0], 0, accuracy: 1E-9)
        XCTAssertEqual(split.parts[1], 2, accuracy: 1E-9)
        // remainders equal but for the binary fractions' noise, in any order: the step goes to the earliest
        for values in [[5.04, 20.04, 3.04], [3.04, 5.04, 20.04], [0.14, 0.14, 0.14, 0.14]] {
            let result = ReportAmounts.split(values, decimals: 1)
            let floors = values.map { ($0 * 10).rounded(.down) / 10 }
            XCTAssertEqual(result.parts[0], floors[0] + 0.1, accuracy: 1E-9, "\(values)")
            for index in 1 ..< values.count where values.count == 3 {
                XCTAssertEqual(result.parts[index], floors[index], accuracy: 1E-9, "\(values)")
            }
        }
        // any amounts: the parts as printed are the total as printed, each within a step of its exact value
        var seed: UInt64 = 7
        for _ in 0 ..< 200 {
            let values = (0 ..< 3).map { _ -> Double in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 40) / 1000
            }
            for decimals in [0, 1, 2] {
                let result = ReportAmounts.split(values, decimals: decimals)
                let step = pow(10, -Double(decimals))
                XCTAssertEqual(result.parts.reduce(0, +), result.total, accuracy: step / 1000)
                XCTAssertEqual(result.total, values.reduce(0, +), accuracy: step / 2 + 1E-9)
                for (part, value) in zip(result.parts, values) {
                    XCTAssertLessThan(abs(part - value), step)
                }
            }
        }
    }

    /// The Days table prints a day's insulin as the Insulin part does: the same split, so the two never differ by a
    /// tenth in one report.
    @MainActor func testDaysTableUsesTheSameAmounts() throws {
        let interval = try XCTUnwrap(Self.days(.days7).first)
        let day = Self.insulinDay(interval, basal: 20.04, smb: 5.04, bolus: 3.04)
        let numbers = ReportDaysBuilder.day(
            DayAggregate(day: interval, histogram: GlucoseHistogram()),
            endRule: .stalled,
            bands: Stat.ReportBuilder.standardBands(.mgdL),
            insulin: day,
            meals: nil
        )
        let cells = Stat.ReportInsulin.cells(day)
        XCTAssertEqual(try XCTUnwrap(numbers.tdd), 28.1, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(numbers.basal), 20.1, accuracy: 1E-9)
        // the SMBs and the boluses in one column: the two parts as printed
        XCTAssertEqual(try XCTUnwrap(numbers.bolus), 8.0, accuracy: 1E-9)
        XCTAssertEqual(number(cells[0]), 28.1)
        XCTAssertEqual(number(cells[1]), 20.1)
        XCTAssertEqual(try XCTUnwrap(number(cells[2])) + (try XCTUnwrap(number(cells[3]))), 8.0, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(numbers.basal) + (try XCTUnwrap(numbers.bolus)), try XCTUnwrap(numbers.tdd), accuracy: 1E-9)
        // the averages too
        let days = Self.days(.days7).map { Self.insulinDay($0, basal: 20.04, smb: 5.04, bolus: 3.04) }
        let average = ReportDaysBuilder.average(
            days.map { DayAggregate(day: $0.day, histogram: GlucoseHistogram()) },
            endRule: .stalled,
            bands: Stat.ReportBuilder.standardBands(.mgdL),
            insulin: days,
            meals: []
        )
        XCTAssertEqual(try XCTUnwrap(average.tdd), 28.1, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(average.basal), 20.1, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(average.bolus), 8.0, accuracy: 1E-9)
    }

    // MARK: - The tables' pages

    func testTablesLayout() {
        for paper in ReportPaper.allCases {
            for hourRows in [Stat.ReportInsulin.hourRows, Stat.ReportMeals.hourRows] {
                let first = Layout.rowsPerPage(paper, hourRows: hourRows)
                let later = Layout.rowsPerPage(paper, hourRows: nil)
                // two weeks' days and their averages go under the clock hours
                XCTAssertGreaterThanOrEqual(first, 15)
                XCTAssertGreaterThan(later, first)
                // what a page holds fits it
                let chrome = Layout.sectionHeight + Layout.headerHeight + Layout.footnoteHeight
                XCTAssertLessThanOrEqual(
                    Layout.hoursHeight(hourRows) + chrome + CGFloat(first) * Layout.rowHeight,
                    Layout.available(paper)
                )
                XCTAssertLessThanOrEqual(chrome + CGFloat(later) * Layout.rowHeight, Layout.available(paper))
                for rows in [0, 1, 8, first, first + 1, first + 2, 31, first + later + 1, 91] {
                    let ranges = Layout.dayRanges(rows: rows, paper: paper, hourRows: hourRows)
                    XCTAssertFalse(ranges.isEmpty)
                    // every row once, in order
                    XCTAssertEqual(ranges.flatMap { Array($0) }, Array(0 ..< rows))
                    XCTAssertLessThanOrEqual(ranges[0].count, first)
                    XCTAssertTrue(ranges.dropFirst().allSatisfy { $0.count <= later && !$0.isEmpty })
                    // the averages' row is never alone on the last page
                    if ranges.count > 1 {
                        XCTAssertGreaterThan(ranges[ranges.count - 1].count, 1, "\(paper) \(rows)")
                    }
                }
                // the overview, and up to two weeks' tables on one page
                XCTAssertEqual(Layout.pageCount(days: 7, paper: paper, hourRows: hourRows), 2)
                XCTAssertEqual(Layout.pageCount(days: 14, paper: paper, hourRows: hourRows), 2)
                XCTAssertLessThanOrEqual(Layout.pageCount(days: 90, paper: paper, hourRows: hourRows), 4)
            }
        }
    }

    /// The parts have no glucose values: printed once, whatever the units; the estimate is the plan.
    func testPagePlan() throws {
        for period in ReportOptions.periods {
            for paper in ReportPaper.allCases {
                let single = try data(request(period: period, paper: paper))
                let both = try data(request(period: period, units: [.mmolL, .mgdL], paper: paper))
                let pages = single.pages(calendar: Self.calendar)
                let days = period.calendarDayCount ?? 0
                let count = Layout.pageCount(days: days, paper: paper, hourRows: Stat.ReportInsulin.hourRows)
                let mealPages = Layout.pageCount(days: days, paper: paper, hourRows: Stat.ReportMeals.hourRows)
                XCTAssertEqual(
                    pages.map(\.part),
                    Array(repeating: .insulin, count: count) + Array(repeating: .meals, count: mealPages)
                )
                XCTAssertEqual(pages.prefix(count).map(\.index), Array(0 ..< count))
                XCTAssertTrue(pages.allSatisfy { $0.size == paper.size })
                XCTAssertEqual(both.pages(calendar: Self.calendar).count, pages.count)
                XCTAssertTrue(both.pages(calendar: Self.calendar).allSatisfy { $0.units == .mmolL })
                for units in ReportUnits.allCases {
                    let options = ReportOptions(period: period, units: units, paper: paper, parts: [.insulin, .meals])
                    XCTAssertEqual(options.estimatedPageCount, pages.count, "\(period) \(paper) \(units)")
                    // without data a part is one page: "Up to N pages"
                    XCTAssertTrue(options.estimateIsUpperBound)
                }
            }
        }
        // beside a part with glucose values: that one once per unit, these once
        let options = ReportOptions(period: .days7, units: .both, paper: .a4, parts: [.summary, .insulin, .meals])
        XCTAssertEqual(options.estimatedPageCount, 2 + 2 + 2)
        var mixed = try data(request(period: .days7, parts: [.summary, .insulin, .meals], units: [.mgdL, .mmolL]))
        XCTAssertEqual(
            mixed.pages(calendar: Self.calendar).map(\.part),
            [.summary, .summary, .insulin, .insulin, .meals, .meals]
        )
        XCTAssertEqual(mixed.pages(calendar: Self.calendar).map(\.units), [.mgdL, .mmolL, .mgdL, .mgdL, .mgdL, .mgdL])

        // without data, or unread: one page saying so
        mixed.insulinPeriod = .value(Self.noInsulin(.days7))
        mixed.mealPeriod = .failed
        XCTAssertEqual(mixed.pageCount(of: .insulin, calendar: Self.calendar), 1)
        XCTAssertEqual(mixed.pageCount(of: .meals, calendar: Self.calendar), 1)

        XCTAssertFalse(ReportPart.insulin.printsGlucose || ReportPart.meals.printsGlucose)
        XCTAssertTrue(ReportPart.summary.printsGlucose && ReportPart.goodBadDays.printsGlucose)
        XCTAssertTrue(ReportPart.insulin.isImplemented && ReportPart.meals.isImplemented)
        XCTAssertEqual(ReportPart.insulin.availability(for: .days7), .available)
        XCTAssertEqual(ReportPart.meals.availability(for: .days7), .available)
        XCTAssertFalse(ReportPlan.isLandscape(.insulin, dailyCharts: .init()))
        XCTAssertFalse(ReportPlan.isLandscape(.meals, dailyCharts: .init()))
    }

    // MARK: - Insulin

    @MainActor func testInsulinOverview() throws {
        let data = try data(request(parts: [.insulin]))
        let period = try XCTUnwrap(data.insulinPeriod?.value)
        let summary = period.summary
        let overview = Stat.ReportInsulin(data, page: page(.insulin), calendar: Self.calendar)
        XCTAssertTrue(overview.isOverview)
        XCTAssertNil(overview.emptyNote)
        XCTAssertNil(overview.hourTable)
        XCTAssertNil(overview.dayTable)

        // the header: the tab's days, the days with pump data
        let first = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 7)))
        let last = try XCTUnwrap(Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 20)))
        XCTAssertEqual(overview.header.dateRange, Stat.ReportPageHeader.dateRange(first, last, calendar: Self.calendar))
        XCTAssertEqual(overview.header.days, "Days with pump data \(summary.daysWithData) of 14")
        XCTAssertEqual(summary.daysWithData, 13)
        // 11 complete days: not the one a third covered, not the one without data, not today
        XCTAssertEqual(summary.headlineDays, 11)
        XCTAssertTrue(overview.tddNote.contains("11 complete days"))

        // basal, SMB and bolus as printed add up to the total as printed, and their shares to 100%
        let total = try XCTUnwrap(number(overview.tdd))
        XCTAssertEqual(overview.parts.map(\.name), ["Basal", "SMB", "Bolus"])
        XCTAssertEqual(overview.parts.compactMap { number($0.value) }.reduce(0, +), total, accuracy: 1E-6)
        XCTAssertEqual(overview.parts.compactMap { number($0.percent) }.reduce(0, +), 100, accuracy: 1E-6)
        XCTAssertEqual(overview.parts.map(\.fraction).reduce(0, +), 1, accuracy: 1E-6)
        XCTAssertEqual(total, try XCTUnwrap(summary.tdd), accuracy: 0.05 + 1E-9)
        XCTAssertEqual(overview.figures.count, 5)
        XCTAssertEqual(overview.figures[0].value, "100%")
        XCTAssertEqual(overview.figures[2].value, StatsFormatting.duration(seconds: .minutes(20)))
        // no IOB rows: no time below zero to say
        XCTAssertEqual(overview.figures[3].value, "–")
        // pump data doesn't cover every complete day: said under the figures
        XCTAssertEqual(overview.notes, [try XCTUnwrap(Stat.Insulin.limitedNote(summary))])

        // a bar a day, "*" above the days outside the averages (a third covered, today), none above the day without
        XCTAssertEqual(overview.dayBars.bars.count, 14)
        XCTAssertEqual(overview.dayBars.bars.filter(\.isMarked).map(\.id), [3, 13])
        XCTAssertEqual(overview.dayBars.bars[5].values, [0, 0, 0])
        XCTAssertEqual(overview.dayBars.average, summary.tdd)
        XCTAssertEqual(overview.dayBars.styles.count, 3)
        XCTAssertEqual(overview.dayBars.levels.first, 0)
        XCTAssertGreaterThanOrEqual(overview.dayBars.top, 28)
        XCTAssertEqual(overview.dayBars.levelLabels.count, overview.dayBars.levels.count)
        XCTAssertEqual(overview.dayBars.ticks.map(\.id), [0, 2, 4, 6, 8, 10, 12])
        XCTAssertEqual(overview.dayBars.legend.map(\.id), [0, 1, 2, 10, 11])
        // a bar a clock hour, the scheduled basal as steps
        XCTAssertEqual(overview.hourBars.bars.count, 24)
        XCTAssertEqual(overview.hourBars.steps.count, 24)
        XCTAssertTrue(overview.hourBars.steps.allSatisfy { $0 != nil })
        XCTAssertNil(overview.hourBars.average)
        XCTAssertEqual(overview.hourBars.ticks.map(\.id), [0, 3, 6, 9, 12, 15, 18, 21])
    }

    @MainActor func testInsulinTables() throws {
        let data = try data(request(parts: [.insulin]))
        let period = try XCTUnwrap(data.insulinPeriod?.value)
        XCTAssertEqual(data.pageCount(of: .insulin, calendar: Self.calendar), 2)
        let tables = Stat.ReportInsulin(data, page: page(.insulin, index: 1), calendar: Self.calendar)
        XCTAssertFalse(tables.isOverview)

        // the clock hours: basal, SMB and bolus as printed add up to the total as printed
        let hours = try XCTUnwrap(tables.hourTable)
        XCTAssertEqual(hours.rows.count, 24)
        XCTAssertEqual(hours.columns.count, 7)
        XCTAssertTrue(hours.rows.allSatisfy { $0.cells.count == 7 })
        for row in hours.rows {
            let cells = row.cells.map { number($0) }
            let parts = try [XCTUnwrap(cells[0]), XCTUnwrap(cells[2]), XCTUnwrap(cells[3])]
            XCTAssertEqual(parts.reduce(0, +), try XCTUnwrap(cells[4]), accuracy: 1E-6, row.title)
            XCTAssertEqual(row.cells[5], "100%")
        }
        XCTAssertEqual(hours.rows[3].cells[6], StatsFormatting.duration(seconds: .minutes(20)))
        XCTAssertEqual(hours.rows[4].cells[6], StatsFormatting.duration(seconds: 0))

        // the days, then the averages
        let days = try XCTUnwrap(tables.dayTable)
        XCTAssertEqual(days.rows.count, 15)
        XCTAssertEqual(days.columns.count, 7)
        XCTAssertTrue(days.rows.allSatisfy { $0.cells.count == 7 })
        XCTAssertEqual(days.rows.filter(\.isEmphasized).map(\.id), [14])
        for (index, row) in days.rows.enumerated() where index != 5 {
            let cells = row.cells.map { number($0) }
            let parts = try [XCTUnwrap(cells[1]), XCTUnwrap(cells[2]), XCTUnwrap(cells[3])]
            XCTAssertEqual(parts.reduce(0, +), try XCTUnwrap(cells[0]), accuracy: 1E-6, row.title)
        }
        // 20.04 + 5.04 + 3.04: the total as printed is 28.1, and the parts add up to it
        XCTAssertEqual(number(days.rows[0].cells[0]), 28.1)
        XCTAssertEqual(number(days.rows[0].cells[1]), 20.1)
        XCTAssertEqual(number(days.rows[0].cells[2]), 5.0)
        XCTAssertEqual(number(days.rows[0].cells[3]), 3.0)
        XCTAssertFalse(days.rows[0].cells[0].hasSuffix("*"))
        XCTAssertEqual(days.rows[0].cells[4], "100%")
        XCTAssertEqual(days.rows[0].cells[6], "100%")
        // "*": a third of the day covered, and today (so far: no share of the day said)
        XCTAssertEqual(days.rows.indices.filter { days.rows[$0].cells[0].hasSuffix("*") }, [3, 13])
        XCTAssertEqual(days.rows[3].cells[6], "30%")
        XCTAssertEqual(days.rows[13].cells[6], "–")
        // no pump data that day
        XCTAssertEqual(days.rows[5].cells, Array(repeating: "–", count: 7))
        // the averages are the overview's
        let overview = Stat.ReportInsulin(data, page: page(.insulin), calendar: Self.calendar)
        XCTAssertEqual(days.rows[14].cells[0], overview.tdd)
        XCTAssertEqual(days.rows[14].title, "Average of 11 complete days")
        XCTAssertTrue(tables.footnote.contains("* a day outside them"))
        // the averages' pump data: of the complete days averaged, all covered in full
        XCTAssertEqual(days.rows[14].cells[6], "100%")
        XCTAssertEqual(Stat.ReportInsulin.averageCoverage(period.days), 100)
        let mixed = Self.days(.days7).enumerated().map { index, day in
            Self.insulinDay(
                day,
                basal: 20,
                smb: 5,
                bolus: 3,
                covered: index < 3 ? 0.8 : (index == 3 ? 0.3 : 1),
                isToday: index == 6
            )
        }
        // three days at 80%, two at 100%; not the one a third covered, not today
        XCTAssertEqual(Stat.ReportInsulin.averageCoverage(mixed), 88)
        XCTAssertNil(Stat.ReportInsulin.averageCoverage([]))

        // a day covered just under half: outside the averages ("*"), though its share prints as 50%
        let half = Self.insulinDay(try XCTUnwrap(Self.days(.days7).first), basal: 10, smb: 2, bolus: 1, covered: 0.499)
        XCTAssertFalse(half.isHeadline)
        let halfCells = Stat.ReportInsulin.cells(half)
        XCTAssertTrue(halfCells[0].hasSuffix("*"))
        XCTAssertEqual(halfCells[6], "50%")
        let justHalf = Self.insulinDay(try XCTUnwrap(Self.days(.days7).first), basal: 10, smb: 2, bolus: 1, covered: 0.5)
        XCTAssertFalse(Stat.ReportInsulin.cells(justHalf)[0].hasSuffix("*"))

        // nothing starred on the page: the note doesn't explain a "*". Today without pump data has none.
        var plain = data
        let plainDays = Self.days(.days14).enumerated().map { index, day in
            index == 13
                ? Self.insulinDay(day, basal: 0, smb: 0, bolus: 0, covered: 0, isToday: true, hasDeliveries: false)
                : Self.insulinDay(day, basal: 20, smb: 5, bolus: 3)
        }
        plain.insulinPeriod = .value(
            InsulinPeriod(
                summary: InsulinStatsEngine.summary(plainDays, period: .days14),
                days: plainDays,
                hours: InsulinStatsEngine.hours(plainDays)
            )
        )
        let unmarked = Stat.ReportInsulin(plain, page: page(.insulin, index: 1), calendar: Self.calendar)
        XCTAssertEqual(unmarked.dayTable?.rows[13].cells, Array(repeating: "–", count: 7))
        XCTAssertFalse(Stat.ReportInsulin.isMarked(unmarked.dayTable))
        XCTAssertFalse(unmarked.footnote.contains("*"))
        XCTAssertTrue(unmarked.footnote.hasPrefix("Insulin is averaged over complete days"))
        XCTAssertTrue(Stat.ReportInsulin.isMarked(days))

        // the days' names by the injected calendar: a day that starts at midnight in Berlin is the evening before in
        // New York
        let style = Stat.ReportDaysPage.dayStyle(Self.calendar)
        XCTAssertEqual(days.rows.prefix(14).map(\.title), period.days.map { $0.day.start.formatted(style) })
        var newYork = Self.calendar
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let shifted = Stat.ReportInsulin(data, page: page(.insulin, index: 1), calendar: newYork)
        XCTAssertNotEqual(shifted.dayTable?.rows.map(\.title), days.rows.map(\.title))

        // 90 days: the hours and the first days, then the rest; every day once, the averages last
        let quarter = try self.data(request(period: .days90, parts: [.insulin]))
        let count = quarter.pageCount(of: .insulin, calendar: Self.calendar)
        XCTAssertEqual(count, Layout.pageCount(days: 90, paper: .a4, hourRows: Stat.ReportInsulin.hourRows))
        let pages = (1 ..< count).map { Stat.ReportInsulin(quarter, page: page(.insulin, index: $0), calendar: Self.calendar) }
        XCTAssertEqual(pages.map { $0.hourTable != nil }, [true] + Array(repeating: false, count: count - 2))
        let rows = pages.flatMap { $0.dayTable?.rows ?? [] }
        XCTAssertEqual(rows.map(\.id), Array(0 ... 90))
        XCTAssertEqual(rows.last?.isEmphasized, true)
        // the "*" is explained on the pages with a starred day (the fourth day, and today), not on the one between
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages.map { $0.footnote.contains("*") }, [true, false, true])
        XCTAssertEqual(pages[0].dayTable?.rows.count, Layout.rowsPerPage(.a4, hourRows: Stat.ReportInsulin.hourRows))
        // a page past the part's: nothing
        let past = Stat.ReportInsulin(quarter, page: page(.insulin, index: count), calendar: Self.calendar)
        XCTAssertNil(past.dayTable)
        XCTAssertNil(past.hourTable)
    }

    // MARK: - Meals

    @MainActor func testMealsOverview() throws {
        let data = try data(request(parts: [.meals]))
        let period = try XCTUnwrap(data.mealPeriod?.value)
        let summary = period.summary
        let overview = Stat.ReportMeals(data, page: page(.meals), calendar: Self.calendar)
        XCTAssertTrue(overview.isOverview)
        XCTAssertNil(overview.emptyNote)
        XCTAssertFalse(overview.showsNutrients)
        // 13 complete days, one of them without an entry
        XCTAssertEqual(summary.completeDays, 13)
        XCTAssertEqual(summary.daysWithEntries, 12)
        XCTAssertEqual(overview.header.days, "Days with entries 12 of 13")
        XCTAssertEqual(overview.carbs, StatsAmount.number(try XCTUnwrap(summary.carbsPerDay), digits: 0))
        XCTAssertTrue(overview.carbsNote.contains("12 days with entries"))
        // entries per day and per entry; the fat and protein only when asked for
        XCTAssertEqual(overview.figures.map(\.id), [0, 1])
        XCTAssertEqual(overview.figures[0].value, StatsAmount.number(3, digits: 1))
        XCTAssertEqual(overview.notes, [try XCTUnwrap(Stat.Meals.limitedNote(summary))])
        XCTAssertEqual(overview.dayBars.bars.count, 14)
        XCTAssertEqual(overview.dayBars.bars[2].values, [0, 0])
        // "*" above today
        XCTAssertEqual(overview.dayBars.bars.filter(\.isMarked).map(\.id), [13])
        XCTAssertEqual(overview.dayBars.average, summary.carbsPerDay)
        XCTAssertEqual(overview.dayBars.legend.map(\.id), [0, 10, 11])
        XCTAssertEqual(overview.hourBars.bars.count, 24)
        XCTAssertGreaterThan(overview.hourBars.bars[19].values[0], overview.hourBars.bars[8].values[0])
        XCTAssertEqual(overview.topHours.map(\.id), [19, 13, 8])
        XCTAssertTrue(overview.topHours[0].detail.hasPrefix("entries on 12 of 12 days"))

        // with the nutrients: the fat, the protein and their carb equivalents
        let full = Stat.ReportMeals(
            try self.data(request(parts: [.meals], nutrients: true)),
            page: page(.meals),
            calendar: Self.calendar
        )
        XCTAssertTrue(full.showsNutrients)
        XCTAssertEqual(full.figures.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertEqual(full.figures[2].value, "22")
        XCTAssertEqual(full.figures[3].value, "31")
        XCTAssertEqual(full.dayBars.legend.map(\.id), [0, 1, 10, 11])
        XCTAssertGreaterThan(full.dayBars.bars[0].values[1], 0)
        // asked for, but nothing logged: as without
        let unlogged = Stat.ReportMeals(
            try self.data(request(parts: [.meals], nutrients: true), logged: false),
            page: page(.meals),
            calendar: Self.calendar
        )
        XCTAssertFalse(unlogged.showsNutrients)
        XCTAssertEqual(unlogged.figures.map(\.id), [0, 1])
        XCTAssertTrue(Stat.ReportMeals.printsNutrients(.init(includeNutrients: true), summary: summary))
        XCTAssertFalse(Stat.ReportMeals.printsNutrients(.init(), summary: summary))
        XCTAssertFalse(Stat.ReportMeals.printsNutrients(.init(includeNutrients: true), summary: nil))
    }

    @MainActor func testMealsTables() throws {
        let data = try data(request(parts: [.meals]))
        let period = try XCTUnwrap(data.mealPeriod?.value)
        let tables = Stat.ReportMeals(data, page: page(.meals, index: 1), calendar: Self.calendar)
        XCTAssertFalse(tables.isOverview)

        // the clock hours and the line under them: the carbs as printed add up to its total, the shares to 100%
        let hours = try XCTUnwrap(tables.hourTable)
        XCTAssertEqual(hours.rows.count, Stat.ReportMeals.hourRows)
        XCTAssertEqual(hours.columns.count, 5)
        XCTAssertTrue(hours.rows.allSatisfy { $0.cells.count == 5 })
        let carbs = hours.rows.prefix(24).compactMap { number($0.cells[0]) }
        XCTAssertEqual(carbs.count, 24)
        XCTAssertEqual(carbs.reduce(0, +), try XCTUnwrap(number(hours.rows[24].cells[0])), accuracy: 1E-6)
        XCTAssertEqual(
            try XCTUnwrap(number(hours.rows[24].cells[0])),
            try XCTUnwrap(period.summary.carbsPerDay),
            accuracy: 0.05 + 1E-9
        )
        XCTAssertEqual(hours.rows.prefix(24).compactMap { number($0.cells[1]) }.reduce(0, +), 100, accuracy: 1E-6)
        XCTAssertEqual(hours.rows[24].cells[1], "100%")
        XCTAssertTrue(hours.rows[24].isEmphasized)
        XCTAssertEqual(hours.rows[8].cells[2], "12")
        XCTAssertEqual(hours.rows[8].cells[3], "12 of 12")
        XCTAssertEqual(hours.rows[9].cells, [StatsAmount.number(0, digits: 1), "0%", "0", "0 of 12", "–"])
        XCTAssertEqual(hours.rows[24].cells[2], "36")
        // the hours' days are of the days averaged: nothing adds up under them
        XCTAssertEqual(hours.rows[24].cells[3], "–")
        // "Most carbs" says the shares the table prints
        let overviewPage = Stat.ReportMeals(data, page: page(.meals), calendar: Self.calendar)
        for top in overviewPage.topHours {
            XCTAssertEqual(top.percent, hours.rows[top.id].cells[1], top.time)
        }
        XCTAssertEqual(Stat.ReportMeals.shares(period.hours).reduce(0, +), 100)

        // the days, then the averages
        let days = try XCTUnwrap(tables.dayTable)
        XCTAssertEqual(days.columns.count, 2)
        XCTAssertEqual(days.rows.count, 15)
        XCTAssertTrue(days.rows.allSatisfy { $0.cells.count == 2 })
        XCTAssertEqual(days.rows[0].cells, [StatsAmount.number(40.4 + 60.3 + 70.2, digits: 0), "3"])
        // no entry that day
        XCTAssertEqual(days.rows[2].cells, ["–", "0"])
        // "*": today, so far
        XCTAssertEqual(days.rows.indices.filter { days.rows[$0].cells[0].hasSuffix("*") }, [13])
        XCTAssertEqual(days.rows[13].cells, ["33*", "1"])
        XCTAssertEqual(days.rows[14].title, "Average of 12 days with entries")
        XCTAssertTrue(days.rows[14].isEmphasized)
        let overview = Stat.ReportMeals(data, page: page(.meals), calendar: Self.calendar)
        XCTAssertEqual(days.rows[14].cells[0], overview.carbs)
        XCTAssertEqual(days.rows[14].cells[1], overview.figures[0].value)
        XCTAssertTrue(tables.footnote.contains("* today"))
        // today without an entry: nothing starred, nothing about a "*"
        var quiet = data
        quiet.mealPeriod = .value(Self.meals(.days14, today: false))
        let unmarked = Stat.ReportMeals(quiet, page: page(.meals, index: 1), calendar: Self.calendar)
        XCTAssertEqual(unmarked.dayTable?.rows[13].cells, ["–", "0"])
        XCTAssertEqual(unmarked.footnote, "Carbs are averaged over complete days with entries.")
        XCTAssertTrue(
            Stat.ReportMeals(quiet, page: page(.meals), calendar: Self.calendar).dayBars.bars
                .allSatisfy { !$0.isMarked }
        )
        // 90 days: the pages before the last have no "*"
        var long = try self.data(request(period: .days90, parts: [.meals]))
        long.mealPeriod = .value(Self.meals(.days90))
        let count = long.pageCount(of: .meals, calendar: Self.calendar)
        let notes = (1 ..< count).map {
            Stat.ReportMeals(long, page: page(.meals, index: $0), calendar: Self.calendar).footnote.contains("*")
        }
        XCTAssertEqual(notes, Array(repeating: false, count: count - 2) + [true])
        let style = Stat.ReportDaysPage.dayStyle(Self.calendar)
        XCTAssertEqual(days.rows.prefix(14).map(\.title), period.days.map { $0.day.start.formatted(style) })

        // with the nutrients: three more columns
        let full = Stat.ReportMeals(
            try self.data(request(parts: [.meals], nutrients: true)),
            page: page(.meals, index: 1),
            calendar: Self.calendar
        )
        let wide = try XCTUnwrap(full.dayTable)
        XCTAssertEqual(wide.columns.count, 5)
        XCTAssertTrue(wide.rows.allSatisfy { $0.cells.count == 5 })
        XCTAssertEqual(
            Array(wide.rows[0].cells.suffix(3)),
            ["22", "31", StatsAmount.number(period.days[0].carbEquivalents, digits: 0)]
        )
        XCTAssertEqual(wide.rows[2].cells, ["–", "0", "–", "–", "–"])
        XCTAssertEqual(Array(wide.rows[14].cells.suffix(3).prefix(2)), ["22", "31"])
    }

    // MARK: - Nothing to print

    @MainActor func testEmptyAndUnread() throws {
        var data = try data(request(period: .days7))
        data.insulinPeriod = .value(Self.noInsulin(.days7))
        data.mealPeriod = .value(Self.noMeals(.days7))
        XCTAssertEqual(data.pages(calendar: Self.calendar).map(\.part), [.insulin, .meals])
        let insulin = Stat.ReportInsulin(data, page: page(.insulin), calendar: Self.calendar)
        XCTAssertEqual(insulin.emptyNote, "No pump data in this period")
        XCTAssertEqual(insulin.tdd, "–")
        XCTAssertNil(insulin.dayTable)
        let meals = Stat.ReportMeals(data, page: page(.meals), calendar: Self.calendar)
        XCTAssertEqual(meals.emptyNote, "No carb entries in this period")
        XCTAssertEqual(meals.carbs, "–")
        XCTAssertTrue(meals.topHours.isEmpty)

        data.insulinPeriod = .failed
        data.mealPeriod = .failed
        XCTAssertEqual(
            Stat.ReportInsulin(data, page: page(.insulin), calendar: Self.calendar).emptyNote,
            "The pump data couldn't be read."
        )
        XCTAssertEqual(
            Stat.ReportMeals(data, page: page(.meals), calendar: Self.calendar).emptyNote,
            "The carb entries couldn't be read."
        )
        // the page's frame: the period's days, no line of glucose ranges
        let pages = data.pages(calendar: Self.calendar)
        let content = try XCTUnwrap(Stat.ReportPageContent(data, page: pages[0], calendar: Self.calendar))
        let chrome = Stat.ReportPageChrome(
            data,
            page: pages[0],
            index: 0,
            count: pages.count,
            version: "9.9.9",
            calendar: Self.calendar,
            header: content.header
        )
        XCTAssertEqual(chrome.title, "Insulin")
        XCTAssertEqual(chrome.ranges, "")
        XCTAssertEqual(chrome.days, "")
        // nothing about the time in ranges under a part without glucose
        XCTAssertTrue(chrome.provenance.hasPrefix("Generated by iAPS 9.9.9 · "))
        XCTAssertFalse(chrome.provenance.contains("Time in ranges"))
        let summary = Stat.ReportPageChrome(
            data,
            page: ReportPage(part: .summary, units: .mgdL, size: ReportPaper.a4.size),
            index: 0,
            count: 1,
            version: "9.9.9",
            calendar: Self.calendar
        )
        XCTAssertTrue(summary.ranges.hasPrefix("Ranges (mg/dL)"))
        XCTAssertTrue(summary.provenance.hasSuffix("Time in ranges is time-weighted"))

        // only today has an entry: nothing to average yet
        let day = try XCTUnwrap(Self.days(.days7).last)
        var today = data
        today.mealPeriod = .value(
            MealStatsEngine.period(
                .days7,
                points: [MealPoint(id: nil, actualDate: day.start.addingTimeInterval(.hours(8)), carbs: 30)],
                fatOrProteinLogged: false,
                factor: 0.5,
                now: Self.now,
                calendar: Self.calendar
            )
        )
        let soFar = Stat.ReportMeals(today, page: page(.meals), calendar: Self.calendar)
        XCTAssertNil(soFar.emptyNote)
        XCTAssertEqual(soFar.carbs, "–")
        XCTAssertEqual(soFar.carbsNote, Stat.Meals.noCompleteDay)
    }

    // MARK: - The kept setting

    func testMealsSettingIsKept() {
        typealias Key = ReportPreferences.Key
        let name = "test-report-insulin-meals-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = ReportPreferences(defaults: defaults)
        // off until switched on
        XCTAssertFalse(store.meals.includeNutrients)
        XCTAssertFalse(store.options(userUnits: .mgdL).meals.includeNutrients)
        XCTAssertFalse(ReportOptions.MealsSettings().includeNutrients)
        store.meals = ReportOptions.MealsSettings(includeNutrients: true)
        XCTAssertEqual(defaults.object(forKey: Key.mealsNutrients) as? Bool, true)
        XCTAssertTrue(Key.mealsNutrients.hasPrefix("iAPS.reports."))
        let next = ReportPreferences(defaults: defaults)
        XCTAssertTrue(next.meals.includeNutrients)
        XCTAssertTrue(next.options(userUnits: .mgdL).meals.includeNutrients)
        // a value of another type reads as the default
        defaults.set("yes", forKey: Key.mealsNutrients)
        XCTAssertFalse(store.meals.includeNutrients)

        XCTAssertTrue(ReportPart.meals.hasSettings)
        XCTAssertTrue(ReportPart.insulin.hasSettings)
        store.parts = [.insulin, .meals]
        XCTAssertEqual(store.parts, [.insulin, .meals])
        XCTAssertEqual(store.options(userUnits: .mgdL).orderedParts, [.insulin, .meals])
    }

    /// "Detailed tables", a toggle for each part: on until switched off, kept; off, the part is its overview page alone.
    @MainActor func testDetailedTablesOption() throws {
        typealias Key = ReportPreferences.Key
        let name = "test-report-detailed-tables-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: parent)
        }
        let store = ReportPreferences(defaults: defaults)
        // on by default
        XCTAssertTrue(ReportOptions.InsulinSettings().detailedTables)
        XCTAssertTrue(ReportOptions.MealsSettings().detailedTables)
        XCTAssertTrue(store.insulin.detailedTables)
        XCTAssertTrue(store.meals.detailedTables)
        XCTAssertTrue(store.options(userUnits: .mgdL).insulin.detailedTables)
        // each kept on its own, under the reports' keys
        store.insulin = ReportOptions.InsulinSettings(detailedTables: false)
        XCTAssertEqual(defaults.object(forKey: Key.insulinTables) as? Bool, false)
        XCTAssertTrue(Key.insulinTables.hasPrefix("iAPS.reports.insulin."))
        XCTAssertTrue(Key.mealsTables.hasPrefix("iAPS.reports.meals."))
        XCTAssertTrue(store.meals.detailedTables)
        var meals = store.meals
        meals.detailedTables = false
        meals.includeNutrients = true
        store.meals = meals
        let next = ReportPreferences(defaults: defaults)
        XCTAssertFalse(next.insulin.detailedTables)
        XCTAssertEqual(next.meals, ReportOptions.MealsSettings(includeNutrients: true, detailedTables: false))
        XCTAssertFalse(next.options(userUnits: .mgdL).insulin.detailedTables)
        XCTAssertFalse(next.options(userUnits: .mgdL).meals.detailedTables)
        // a value of another type reads as the default
        defaults.set("no", forKey: Key.insulinTables)
        XCTAssertTrue(store.insulin.detailedTables)
        defaults.set(false, forKey: Key.insulinTables)

        // off: the overview page of each, whatever the period; the estimate is the plan
        for period in [StatsPeriod.days7, .days90] {
            for paper in ReportPaper.allCases {
                let off = try data(request(period: period, paper: paper, tables: false))
                XCTAssertEqual(off.pages(calendar: Self.calendar).map(\.part), [.insulin, .meals], "\(period)")
                XCTAssertEqual(off.pages(calendar: Self.calendar).map(\.index), [0, 0])
                XCTAssertEqual(off.pageCount(of: .insulin, calendar: Self.calendar), 1)
                XCTAssertEqual(off.pageCount(of: .meals, calendar: Self.calendar), 1)
                var options = ReportOptions(period: period, units: .both, paper: paper, parts: [.insulin, .meals])
                options.insulin.detailedTables = false
                options.meals.detailedTables = false
                XCTAssertEqual(options.estimatedPageCount, 2)
                // one off, the other on
                options.meals.detailedTables = true
                var mixed = Stat.ReportRequest(
                    period: period,
                    parts: [.insulin, .meals],
                    units: [.mgdL],
                    hbA1cUnit: .percent,
                    paper: paper,
                    insulin: ReportOptions.InsulinSettings(detailedTables: false)
                )
                let half = try data(mixed)
                let mealPages = Layout.pageCount(
                    days: period.calendarDayCount ?? 0,
                    paper: paper,
                    hourRows: Stat.ReportMeals.hourRows
                )
                XCTAssertEqual(half.pages(calendar: Self.calendar).count, 1 + mealPages)
                XCTAssertEqual(options.estimatedPageCount, 1 + mealPages)
                XCTAssertGreaterThanOrEqual(options.estimatedPageCount, half.pages(calendar: Self.calendar).count)
                mixed = request(period: period, paper: paper)
                XCTAssertGreaterThan(try data(mixed).pages(calendar: Self.calendar).count, 1 + mealPages)
            }
        }
        // the overview is the same page with or without the tables after it
        let on = Stat.ReportInsulin(try data(request(parts: [.insulin])), page: page(.insulin), calendar: Self.calendar)
        let off = Stat.ReportInsulin(
            try data(request(parts: [.insulin], tables: false)),
            page: page(.insulin),
            calendar: Self.calendar
        )
        XCTAssertEqual(off, on)

        // a tab's own export follows the saved toggle
        let exporter = Stat.ReportExporter(preferences: next, parent: parent, calendar: { Self.calendar })
        let context = Stat.ReportContext(
            source: FakeSource(),
            userUnits: .mgdL,
            hbA1cUnit: .percent,
            carbEquivalentFactor: 0.5,
            screenPeriod: .days30
        )
        XCTAssertFalse(exporter.partRequest(.insulin, context: context).insulin.detailedTables)
        XCTAssertFalse(exporter.partRequest(.meals, context: context).meals.detailedTables)
        next.insulin = ReportOptions.InsulinSettings()
        XCTAssertTrue(exporter.partRequest(.insulin, context: context).insulin.detailedTables)
        XCTAssertFalse(context.request(next.options(userUnits: .mgdL)).meals.detailedTables)
    }

    // MARK: - The reads

    private struct Failure: Error {}

    /// The provider's calls a report makes, faked.
    private actor FakeSource: ReportDataSource {
        typealias Fixtures = StatsReportInsulinMealsTests

        private(set) var reads: [String] = []
        private var isEmpty = false
        private var isFailing = false

        func empty() { isEmpty = true }
        func fail() { isFailing = true }

        func beginSession() {}
        func endSession() {}

        func reportProfile(_ period: StatsPeriod, bands _: StatsBands) -> Stat.AGPResult {
            reads.append("profile")
            return Stat.AGPResult(bins: [], points: [], axis: 40 ... 300, summary: Fixtures.summary(period))
        }

        func reportInsulin(_ period: StatsPeriod) throws -> InsulinPeriod {
            reads.append("insulin \(period.rawValue)")
            if isFailing { throw Failure() }
            return isEmpty ? Fixtures.noInsulin(period) : Fixtures.insulin(period)
        }

        func reportMeals(_ period: StatsPeriod, factor: Double) throws -> MealPeriod {
            reads.append("meals \(period.rawValue) \(factor)")
            if isFailing { throw Failure() }
            return isEmpty ? Fixtures.noMeals(period) : Fixtures.meals(period)
        }

        func reportDays(_ period: StatsPeriod) -> PeriodDays {
            reads.append("days")
            return PeriodDays(window: Fixtures.summary(period).window, endRule: .stalled, days: [])
        }

        func reportTrace(day _: Date, bands _: StatsBands) -> ReportDayTrace {
            reads.append("trace")
            return ReportDayTrace(points: [], summary: Fixtures.summary(.days7))
        }

        func reportInsulinInput(_: DateInterval, now _: Date) -> InsulinInput {
            reads.append("events")
            return InsulinInput()
        }

        func reportHourOfDay(_ period: StatsPeriod, bands: StatsBands) -> Stat.HourOfDayResult {
            reads.append("hours")
            return Stat.HourOfDayResult(buckets: [], summary: Fixtures.summary(period), bands: bands)
        }

        func reportWeekday(_ period: StatsPeriod, bands: StatsBands) -> Stat.WeekdayResult {
            reads.append("weekday")
            return Stat.WeekdayResult(
                GlucoseStatsEngine.weekdayHours([], days: [], bands: bands, calendar: Fixtures.calendar),
                period: period
            )
        }

        func reportPatches(
            _: StatsPeriod,
            bands _: StatsBands,
            input _: ReportPatchesInput,
            now _: Date,
            calendar _: Calendar
        ) throws -> Stat.PatchesResult {
            throw CancellationError()
        }

        func reportCGM(_: StatsPeriod, now _: Date, calendar _: Calendar) throws -> Stat.CGMResult { throw CancellationError() }

        func reportGoodBadDays(_ period: StatsPeriod, bands: StatsBands, allowOneMinuteLoop _: Bool) -> Stat.GoodBadDaysData {
            reads.append("goodBadDays")
            return Stat.GoodBadDaysData(
                period: period,
                result: GoodBadDaysEngine.result(
                    period: period,
                    days: [],
                    readings: [],
                    bands: bands,
                    calendar: Fixtures.calendar
                )
            )
        }
    }

    private func build(_ request: Stat.ReportRequest, _ source: FakeSource) async throws -> Stat.ReportData {
        try await Stat.ReportBuilder.build(request, source: source, now: Self.now, calendar: Self.calendar)
    }

    /// In a report the two parts take the tabs' periods, read once each, whatever else needs them.
    func testBuilderReadsTheTabsPeriods() async throws {
        let source = FakeSource()
        let data = try await build(request(period: .days30, parts: [.summary, .insulin, .meals]), source)
        let reads = await source.reads
        XCTAssertEqual(reads, ["profile", "insulin days30", "meals days30 0.5"])
        XCTAssertEqual(data.insulinPeriod?.value?.days.count, 30)
        XCTAssertEqual(data.mealPeriod?.value?.days.count, 30)
        XCTAssertNotNil(data.insulinPeriod?.value?.hours.first)
        // the Summary's block is the same read
        XCTAssertEqual(data.insulin?.value, data.insulinPeriod?.value?.summary)
        XCTAssertEqual(data.meals?.value, data.mealPeriod?.value?.summary)

        // without the parts: nothing of theirs is kept
        let plain = try await build(request(period: .days30, parts: [.summary]), FakeSource())
        XCTAssertNil(plain.insulinPeriod)
        XCTAssertNil(plain.mealPeriod)

        // a read that fails doesn't fail the report: the part's page says so
        let failing = FakeSource()
        await failing.fail()
        let partial = try await build(request(period: .days7, parts: [.summary, .insulin, .meals]), failing)
        XCTAssertEqual(partial.insulinPeriod, .failed)
        XCTAssertEqual(partial.mealPeriod, .failed)
        XCTAssertEqual(partial.pages(calendar: Self.calendar).map(\.part), [.summary, .insulin, .meals])

        // nothing in the tabs' periods: a page each saying so
        let blank = FakeSource()
        await blank.empty()
        let none = try await build(request(period: .days7, parts: [.summary, .insulin, .meals]), blank)
        XCTAssertEqual(none.insulinPeriod?.value?.summary.isEmpty, true)
        XCTAssertEqual(none.mealPeriod?.value?.summary.isEmpty, true)
        XCTAssertEqual(none.pages(calendar: Self.calendar).map(\.part), [.summary, .insulin, .meals])
    }

    /// A report of Insulin and Meals only doesn't read the glucose, and is made without CGM data.
    func testNoGlucoseIsReadWithoutAGlucosePart() async throws {
        let source = FakeSource()
        let data = try await build(request(period: .days14, parts: [.insulin, .meals], units: [.mmolL, .mgdL]), source)
        let reads = await source.reads
        XCTAssertEqual(reads, ["insulin days14", "meals days14 0.5"])
        XCTAssertTrue(data.summary.isEmpty)
        XCTAssertEqual(data.insulinPeriod?.value?.days.count, 14)
        XCTAssertEqual(data.mealPeriod?.value?.days.count, 14)
        XCTAssertEqual(data.pages(calendar: Self.calendar).map(\.part), [.insulin, .insulin, .meals, .meals])
        // the period's days name the file
        let days = data.fileDays(calendar: Self.calendar)
        XCTAssertEqual(
            ReportPDFWriter.fileName(first: days.first, last: days.last, calendar: Self.calendar),
            "iAPS report 2027-01-07 – 2027-01-20.pdf"
        )
        XCTAssertNil(request(parts: [.insulin, .meals]).ownPart)

        // a read that fails, a period without data: said on the part's page, the report is made
        let failing = FakeSource()
        await failing.fail()
        let unread = try await build(request(period: .days7, parts: [.insulin, .meals]), failing)
        XCTAssertEqual(unread.insulinPeriod, .failed)
        XCTAssertEqual(unread.mealPeriod, .failed)
        XCTAssertEqual(unread.pages(calendar: Self.calendar).map(\.part), [.insulin, .meals])
        let unreadDays = unread.days(calendar: Self.calendar)
        XCTAssertEqual(unreadDays.first, Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 14)))
        XCTAssertEqual(unreadDays.last, Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 20)))
        let blank = FakeSource()
        await blank.empty()
        let none = try await build(request(period: .days7, parts: [.insulin, .meals]), blank)
        XCTAssertEqual(none.pages(calendar: Self.calendar).map(\.part), [.insulin, .meals])
        let blankReads = await blank.reads
        XCTAssertFalse(blankReads.contains("profile"))
        // with a glucose part beside them the profile is read as before
        let mixed = FakeSource()
        _ = try await build(request(period: .days7, parts: [.byHour, .insulin]), mixed)
        let mixedReads = await mixed.reads
        XCTAssertEqual(mixedReads, ["profile", "insulin days7", "hours"])
    }

    /// Why a report wasn't made, as said under the button.
    func testFailureTexts() {
        typealias Exporter = Stat.ReportExporter
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.noPumpData), "No pump data in this period")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.noCarbEntries), "No carb entries in this period")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.pumpDataNotRead), "The pump data couldn't be read.")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.carbEntriesNotRead), "The carb entries couldn't be read.")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.noData), "No CGM data in this period")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.noDataOnDay), "No CGM data on this day")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.nothingSelected), "Select at least one part.")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.notWritten), "The report couldn't be created.")
        XCTAssertEqual(Exporter.failureText(Failure()), "The report couldn't be created.")
        // only what isn't one of the report's own reasons is logged
        XCTAssertTrue(Exporter.isUnexpected(Failure()))
        XCTAssertTrue(Exporter.isUnexpected(Stat.ReportError.notWritten))
        for error in [Stat.ReportError.noPumpData, .noCarbEntries, .pumpDataNotRead, .carbEntriesNotRead, .noData] {
            XCTAssertFalse(Exporter.isUnexpected(error))
        }
    }

    /// The Meals tab's own export prints the fat and protein as the tab shows them, whatever the saved toggle; a
    /// report made on the Reports screen follows the toggle.
    @MainActor func testMealsPartRequest() {
        let name = "test-report-meals-request-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: parent)
        }
        let preferences = ReportPreferences(defaults: defaults)
        let exporter = Stat.ReportExporter(preferences: preferences, parent: parent, calendar: { Self.calendar })
        let context = Stat.ReportContext(
            source: FakeSource(),
            userUnits: .mgdL,
            hbA1cUnit: .percent,
            carbEquivalentFactor: 0.5,
            screenPeriod: .days30
        )
        XCTAssertFalse(preferences.meals.includeNutrients)
        let own = exporter.partRequest(.meals, context: context)
        XCTAssertEqual(own.parts, [.meals])
        XCTAssertEqual(own.period, .days30)
        XCTAssertTrue(own.meals.includeNutrients)
        XCTAssertEqual(own.ownPart, .meals)
        // the toggle isn't touched, and the Reports screen's report follows it
        XCTAssertFalse(preferences.meals.includeNutrients)
        XCTAssertFalse(context.request(preferences.options(userUnits: .mgdL)).meals.includeNutrients)
        preferences.meals = ReportOptions.MealsSettings(includeNutrients: true)
        XCTAssertTrue(context.request(preferences.options(userUnits: .mgdL)).meals.includeNutrients)
        // the other tabs' exports keep the saved setting
        preferences.meals = ReportOptions.MealsSettings()
        XCTAssertFalse(exporter.partRequest(.insulin, context: context).meals.includeNutrients)
        // nothing logged: the page has no fat or protein, asked for or not
        XCTAssertFalse(Stat.ReportMeals.printsNutrients(own.meals, summary: Self.meals(.days14, logged: false).summary))
        XCTAssertTrue(Stat.ReportMeals.printsNutrients(own.meals, summary: Self.meals(.days14).summary))
    }

    /// A tab's own "Export PDF" reads that tab's period alone: no glucose, and no report without its data.
    func testOwnPartReads() async throws {
        let source = FakeSource()
        let insulin = try await build(request(period: .days14, parts: [.insulin]), source)
        let meals = try await build(request(period: .days30, parts: [.meals]), source)
        let reads = await source.reads
        XCTAssertEqual(reads, ["insulin days14", "meals days30 0.5"])
        XCTAssertEqual(request(parts: [.insulin]).ownPart, .insulin)
        XCTAssertEqual(request(parts: [.meals]).ownPart, .meals)
        XCTAssertNil(request(parts: [.insulin, .meals]).ownPart)
        XCTAssertNil(insulin.mealPeriod)
        XCTAssertNil(meals.insulinPeriod)
        XCTAssertEqual(insulin.pages(calendar: Self.calendar).count, 2)
        XCTAssertEqual(
            meals.pages(calendar: Self.calendar).count,
            Layout.pageCount(days: 30, paper: .a4, hourRows: Stat.ReportMeals.hourRows)
        )

        // the file and the header are the tab's days
        func name(_ data: Stat.ReportData) -> String {
            let days = data.fileDays(calendar: Self.calendar)
            return ReportPDFWriter.fileName(first: days.first, last: days.last, calendar: Self.calendar)
        }
        XCTAssertEqual(name(insulin), "iAPS report 2027-01-07 – 2027-01-20.pdf")
        XCTAssertEqual(name(meals), "iAPS report 2026-12-22 – 2027-01-20.pdf")

        // nothing in the period: no report, and why
        let cases: [(ReportPart, Stat.ReportError, Stat.ReportError)] = [
            (.insulin, .noPumpData, .pumpDataNotRead),
            (.meals, .noCarbEntries, .carbEntriesNotRead)
        ]
        for (part, expected, unread) in cases {
            let blank = FakeSource()
            await blank.empty()
            do {
                _ = try await build(request(period: .days7, parts: [part]), blank)
                XCTFail("\(part)")
            } catch {
                XCTAssertEqual(error as? Stat.ReportError, expected, "\(part)")
            }
            // the read failing fails the report, saying which read
            let failing = FakeSource()
            await failing.fail()
            do {
                _ = try await build(request(period: .days7, parts: [part]), failing)
                XCTFail("\(part)")
            } catch {
                XCTAssertEqual(error as? Stat.ReportError, unread, "\(part)")
            }
        }
    }

    // MARK: - The written file

    private func plainText(_ document: PDFDocument) -> String {
        (document.string ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @MainActor func testWritesTheParts() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-report-insulin-meals-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }

        let data = try data(request(period: .days14, units: [.mgdL, .mmolL], nutrients: true))
        let output = try await ReportPDFWriter.write(data, version: "9.9.9", parent: parent, calendar: Self.calendar)
        let document = try XCTUnwrap(PDFDocument(url: output.url))
        // the overview and the tables of each, once for both units
        XCTAssertEqual(document.pageCount, 4)
        XCTAssertEqual(output.pageCount, 4)
        for index in 0 ..< 4 {
            let size = try XCTUnwrap(document.page(at: index)).bounds(for: .mediaBox).size
            XCTAssertEqual(size.width, 595, accuracy: 0.5)
            XCTAssertEqual(size.height, 842, accuracy: 0.5)
        }
        let text = plainText(document)
        for expected in [
            "Insulin",
            "Total daily dose",
            "Days with pump data 13 of 14",
            "Day by day",
            "By hour",
            "Scheduled basal",
            "Average of 11 complete days",
            "Meals",
            "Days with entries 12 of 13",
            "Most carbs",
            "By time of day",
            "Carb equivalents",
            "Average of 12 days with entries",
            "Generated by iAPS 9.9.9",
            "Page 4 of 4"
        ] {
            XCTAssertTrue(text.contains(expected), expected)
        }
        // no glucose on these pages
        XCTAssertFalse(text.contains("Ranges ("))
        XCTAssertFalse(text.contains("mmol/L"))
    }
}
