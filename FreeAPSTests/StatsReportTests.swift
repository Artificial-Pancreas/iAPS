@testable import FreeAPS
import PDFKit
import XCTest

/// The PDF reports: the kept choices, the page plan, the consensus goals and GRI, the pages' models, and the written file.
final class StatsReportTests: XCTestCase {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// the same moments are other days there
    private static let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// 2026-10-20 00:00 Europe/Berlin
    private static let day0 = Date(timeIntervalSince1970: 1_792_447_200)

    // MARK: - Fixtures

    /// An empty store of its own, removed after the test
    private func reportPreferences() -> ReportPreferences {
        let name = "test-reports-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return ReportPreferences(defaults: defaults)
    }

    /// A summary of `days` days from `day0` with the given percents of its covered time at the given mg/dL values.
    private func glucoseSummary(
        values: [(mgdl: Int16, percent: Double)],
        units: GlucoseUnits = .mgdL,
        days: Int = 14,
        daysWithData: Int? = nil,
        covered: Double = 1
    ) -> GlucoseSummary {
        let total = TimeInterval.days(days)
        var histogram = GlucoseHistogram()
        for entry in values where entry.percent > 0 {
            let seconds = total * covered * entry.percent / 100
            histogram.add(WeightedPoint(time: Self.day0, mgdl: entry.mgdl, span: seconds), seconds: seconds, startsInside: true)
        }
        return GlucoseStatsEngine.summary(
            histogram,
            window: DateInterval(start: Self.day0, duration: total),
            endRule: .stalled,
            calendarDays: days,
            daysWithData: daysWithData ?? days,
            bands: Stat.ReportBuilder.standardBands(units)
        )
    }

    /// The percents of the time at 50, 60, 120, 200 and 300 mg/dL: one value in each band.
    private func glucoseSummary(
        percents: [Double],
        units: GlucoseUnits = .mgdL,
        days: Int = 14,
        daysWithData: Int? = nil,
        covered: Double = 1
    ) -> GlucoseSummary {
        glucoseSummary(
            values: zip([50, 60, 120, 200, 300] as [Int16], percents).map { (mgdl: $0, percent: $1) },
            units: units,
            days: days,
            daysWithData: daysWithData,
            covered: covered
        )
    }

    /// A profile with data in every bin: the median 120 at night, rising to `peak` at noon.
    private func bins(peak: Double = 180) -> [AGPBin?] {
        (0 ..< 96).map { index in
            let phase = sin(Double(index) / 96 * Double.pi)
            let median = 120 + (peak - 120) * phase
            return AGPBin(
                startMinute: index * 15,
                p5: median - 40,
                p25: median - 20,
                p50: median,
                p75: median + 25,
                p95: median + 60,
                seconds: 12600
            )
        }
    }

    private func insulin(headlineDays: Int = 13, isEmpty: Bool = false) -> InsulinSummary {
        InsulinSummary(
            window: DateInterval(start: Self.day0, duration: .days(14)),
            calendarDays: 14,
            daysWithData: isEmpty ? 0 : 14,
            headlineDays: isEmpty ? 0 : headlineDays,
            tdd: isEmpty ? nil : 38.2,
            basal: isEmpty ? nil : 17.1,
            smb: isEmpty ? nil : 9.4,
            bolus: isEmpty ? nil : 11.7,
            splitPercents: isEmpty ? [0, 0, 0] : [45, 24, 31],
            basalVsScheduled: 1,
            scheduledPerDay: 17,
            zeroBasalSecondsPerDay: 0,
            negativeIOBSecondsPerDay: nil,
            coverage: isEmpty ? 0 : 1,
            coveragePercent: isEmpty ? 0 : 100,
            isEmpty: isEmpty,
            profileAssumedBefore: nil
        )
    }

    private func meals(daysWithEntries: Int = 12, isEmpty: Bool = false) -> MealSummary {
        MealSummary(
            window: DateInterval(start: Self.day0, duration: .days(14)),
            completeDays: 13,
            daysWithEntries: isEmpty ? 0 : daysWithEntries,
            entries: isEmpty ? 0 : 40,
            carbs: isEmpty ? 0 : 2184,
            carbsPerDay: isEmpty ? nil : 182,
            entriesPerDay: isEmpty ? nil : 3.3,
            perEntry: isEmpty ? nil : 54.6,
            fatPerDay: nil,
            proteinPerDay: nil,
            carbEquivalentsPerDay: nil,
            logsFatOrProtein: false,
            isEmpty: isEmpty
        )
    }

    private func reportRequest(
        period: StatsPeriod = .days14,
        parts: [ReportPart] = ReportPart.implemented,
        units: [GlucoseUnits] = [.mgdL],
        paper: ReportPaper = .a4,
        summary: ReportOptions.SummarySettings = .init()
    ) -> Stat.ReportRequest {
        Stat.ReportRequest(
            period: period,
            parts: parts,
            units: units,
            hbA1cUnit: .percent,
            paper: paper,
            summary: summary
        )
    }

    private func reportData(
        _ request: Stat.ReportRequest,
        percents: [Double] = [1, 3, 70, 20, 6],
        withInsulin: Bool = true
    ) throws -> Stat.ReportData {
        try Stat.ReportBuilder.assemble(
            request,
            summary: glucoseSummary(percents: percents),
            bins: bins(),
            insulin: withInsulin ? .value(insulin()) : nil,
            meals: withInsulin ? .value(meals()) : nil,
            now: Self.day0.addingTimeInterval(TimeInterval.days(14) - TimeInterval.hours(10))
        )
    }

    // MARK: - Options

    /// Nothing stored: 14 days, the user's unit, the region's paper, every implemented part, both Summary settings on.
    func testReportPreferencesDefaults() {
        let preferences = reportPreferences()
        let options = preferences.options(userUnits: .mmolL, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(options.period, .days14)
        XCTAssertEqual(options.units, .mmolL)
        XCTAssertEqual(options.paper, .letter)
        XCTAssertEqual(options.parts, Set(ReportPart.implemented))
        XCTAssertEqual(options.orderedParts, [.summary, .percentileProfile])
        XCTAssertTrue(options.summary.insulinAndCarbs)
        XCTAssertTrue(options.summary.gri)
        XCTAssertNil(preferences.units)
        XCTAssertNil(preferences.paper)

        let other = preferences.options(userUnits: .mgdL, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(other.units, .mgdL)
        XCTAssertEqual(other.paper, .a4)
    }

    /// Written and read back by another store on the same defaults, under "iAPS.reports." keys.
    func testReportPreferencesRoundTrip() {
        let preferences = reportPreferences()
        for period in ReportOptions.periods {
            preferences.period = period
            XCTAssertEqual(preferences.period, period)
        }
        preferences.period = .days90
        preferences.units = .both
        preferences.paper = .letter
        preferences.parts = [.percentileProfile]
        preferences.summaryInsulinAndCarbs = false
        preferences.summaryGRI = false

        let next = ReportPreferences(defaults: preferences.defaults)
        let options = next.options(userUnits: .mgdL, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(options.period, .days90)
        XCTAssertEqual(options.units, .both)
        XCTAssertEqual(options.paper, .letter)
        XCTAssertEqual(options.parts, [.percentileProfile])
        XCTAssertFalse(options.summary.insulinAndCarbs)
        XCTAssertFalse(options.summary.gri)

        typealias Key = ReportPreferences.Key
        let defaults = preferences.defaults
        XCTAssertEqual(defaults.string(forKey: Key.period), "days90")
        XCTAssertEqual(defaults.string(forKey: Key.units), "both")
        XCTAssertEqual(defaults.string(forKey: Key.paper), "letter")
        XCTAssertEqual(defaults.array(forKey: Key.parts) as? [String], ["percentileProfile"])
        for key in [Key.period, Key.units, Key.paper, Key.parts, Key.summaryInsulinAndCarbs, Key.summaryGRI] {
            XCTAssertTrue(key.hasPrefix("iAPS.reports."), key)
        }

        // back to "not picked": the user's unit and the region's paper again
        next.units = nil
        next.paper = nil
        XCTAssertEqual(next.options(userUnits: .mmolL, locale: Locale(identifier: "de_DE")).units, .mmolL)
        XCTAssertEqual(next.options(userUnits: .mmolL, locale: Locale(identifier: "de_DE")).paper, .a4)
    }

    /// What the choices don't offer reads as the default, and isn't written.
    func testReportPreferencesValidation() {
        typealias Key = ReportPreferences.Key
        let preferences = reportPreferences()
        let defaults = preferences.defaults

        // a period a report doesn't offer, an unknown one, another type
        for stored in ["today", "last24h", "weeks13", "nonsense"] {
            defaults.set(stored, forKey: Key.period)
            XCTAssertEqual(preferences.period, .days14, stored)
        }
        defaults.set(30, forKey: Key.period)
        XCTAssertEqual(preferences.period, .days14)
        preferences.period = .days30
        preferences.period = .today
        XCTAssertEqual(defaults.string(forKey: Key.period), "days30")

        defaults.set("stone", forKey: Key.units)
        defaults.set("a5", forKey: Key.paper)
        XCTAssertNil(preferences.units)
        XCTAssertNil(preferences.paper)
        XCTAssertEqual(preferences.options(userUnits: .mmolL, locale: Locale(identifier: "en_GB")).units, .mmolL)
        XCTAssertEqual(preferences.options(userUnits: .mmolL, locale: Locale(identifier: "en_GB")).paper, .a4)

        // a part that isn't implemented yet, an unknown one: left out; nothing selected stays nothing
        defaults.set(["summary", "daysTable", "nonsense"], forKey: Key.parts)
        XCTAssertEqual(preferences.parts, [.summary])
        defaults.set([String](), forKey: Key.parts)
        XCTAssertEqual(preferences.parts, [])
        defaults.set("summary", forKey: Key.parts)
        XCTAssertEqual(preferences.parts, Set(ReportPart.implemented))
        preferences.parts = [.summary, .settings]
        XCTAssertEqual(defaults.array(forKey: Key.parts) as? [String], ["summary"])

        defaults.set("yes", forKey: Key.summaryInsulinAndCarbs)
        defaults.set("no", forKey: Key.summaryGRI)
        XCTAssertTrue(preferences.summaryInsulinAndCarbs)
        XCTAssertTrue(preferences.summaryGRI)
    }

    func testPaperByRegionAndSizes() {
        for identifier in ["en_US", "en_CA", "fr_CA", "es_MX", "es_CO", "en_PH"] {
            XCTAssertEqual(ReportPaper.regional(Locale(identifier: identifier)), .letter, identifier)
        }
        for identifier in ["en_GB", "de_DE", "ru_RU", "ja_JP", "en_AU", "pt_BR"] {
            XCTAssertEqual(ReportPaper.regional(Locale(identifier: identifier)), .a4, identifier)
        }
        XCTAssertEqual(ReportPaper.a4.size(landscape: false), CGSize(width: 595, height: 842))
        XCTAssertEqual(ReportPaper.a4.size(landscape: true), CGSize(width: 842, height: 595))
        XCTAssertEqual(ReportPaper.letter.size(landscape: false), CGSize(width: 612, height: 792))
        XCTAssertEqual(ReportPaper.letter.size(landscape: true), CGSize(width: 792, height: 612))
    }

    func testImplementedPartsAndUnits() {
        XCTAssertEqual(ReportPart.implemented, [.summary, .percentileProfile])
        XCTAssertEqual(ReportPart.allCases.count, 13)
        XCTAssertFalse(ReportPart.summary.isLandscape)
        XCTAssertTrue(ReportPart.percentileProfile.isLandscape)
        XCTAssertTrue(ReportPart.summary.hasSettings)
        XCTAssertFalse(ReportPart.percentileProfile.hasSettings)
        XCTAssertEqual(ReportPart.percentileProfile.title, "Percentile profile")

        XCTAssertEqual(ReportUnits.mgdL.printed(userUnits: .mmolL), [.mgdL])
        XCTAssertEqual(ReportUnits.mmolL.printed(userUnits: .mgdL), [.mmolL])
        XCTAssertEqual(ReportUnits.both.printed(userUnits: .mgdL), [.mgdL, .mmolL])
        XCTAssertEqual(ReportUnits.both.printed(userUnits: .mmolL), [.mmolL, .mgdL])

        // the period on screen -> the report's
        XCTAssertEqual(ReportOptions.period(nearest: .today), .days7)
        XCTAssertEqual(ReportOptions.period(nearest: .last24h), .days7)
        XCTAssertEqual(ReportOptions.period(nearest: .days30), .days30)
        XCTAssertEqual(ReportOptions.period(nearest: .weeks13), .days90)
    }

    // MARK: - Pages

    /// The estimate is the plan's count: a page per part, once per unit.
    func testPageCountEstimate() {
        var options = ReportOptions(period: .days14, units: .mgdL, paper: .a4, parts: Set(ReportPart.implemented))
        XCTAssertEqual(options.estimatedPageCount, 2)
        options.units = .both
        XCTAssertEqual(options.estimatedPageCount, 4)
        options.parts = [.percentileProfile]
        XCTAssertEqual(options.estimatedPageCount, 2)
        options.units = .mmolL
        XCTAssertEqual(options.estimatedPageCount, 1)
        options.parts = []
        XCTAssertEqual(options.estimatedPageCount, 0)

        for units in ReportUnits.allCases {
            for parts in [[ReportPart.summary], [.percentileProfile], ReportPart.implemented] {
                let options = ReportOptions(period: .days14, units: units, paper: .letter, parts: Set(parts))
                let request = reportRequest(parts: options.orderedParts, units: units.printed(userUnits: .mgdL), paper: .letter)
                XCTAssertEqual(request.pages.count, options.estimatedPageCount)
            }
        }
    }

    func testPagesOrderAndSizes() {
        let pages = reportRequest(units: [.mmolL, .mgdL], paper: .letter).pages
        XCTAssertEqual(pages.map(\.part), [.summary, .summary, .percentileProfile, .percentileProfile])
        XCTAssertEqual(pages.map(\.units), [.mmolL, .mgdL, .mmolL, .mgdL])
        XCTAssertEqual(pages[0].size, CGSize(width: 612, height: 792))
        XCTAssertEqual(pages[2].size, CGSize(width: 792, height: 612))
    }

    /// The period's first and last day in the calendar's time zone, whatever the phone's.
    func testFileName() {
        let calendar = Self.calendar
        let last = calendar.date(byAdding: .day, value: 13, to: Self.day0)!
        XCTAssertEqual(
            ReportPDFWriter.fileName(first: Self.day0, last: last, calendar: calendar),
            "iAPS report 2026-10-20 – 2026-11-02.pdf"
        )
        // the same moments are other days in Los Angeles
        XCTAssertEqual(
            ReportPDFWriter.fileName(first: Self.day0, last: last, calendar: Self.losAngeles),
            "iAPS report 2026-10-19 – 2026-11-01.pdf"
        )
    }

    // MARK: - Bands, goals and GRI

    /// Always 70–180, whatever the user's low/high: mg/dL as they are, mmol/L the edges displayed like them.
    func testStandardBands() {
        let mgdl = Stat.ReportBuilder.standardBands(.mgdL)
        XCTAssertEqual(mgdl.low, 70)
        XCTAssertEqual(mgdl.high, 180)
        XCTAssertEqual(mgdl.tirRange, 70 ... 180)
        XCTAssertEqual(mgdl.titrRange, 70 ... 140)
        let mmol = Stat.ReportBuilder.standardBands(.mmolL)
        XCTAssertEqual(mmol.low, 70)
        XCTAssertEqual(mmol.high, 181)
    }

    /// On the exact value: no rounding before the comparison.
    func testGoalThresholds() {
        XCTAssertFalse(ReportGoal.inRange.isMet(70))
        XCTAssertTrue(ReportGoal.inRange.isMet(70.4))
        XCTAssertTrue(ReportGoal.below70.isMet(3.99))
        XCTAssertFalse(ReportGoal.below70.isMet(4))
        XCTAssertFalse(ReportGoal.below70.isMet(4.18))
        XCTAssertTrue(ReportGoal.below54.isMet(0.99))
        XCTAssertFalse(ReportGoal.below54.isMet(1))
        XCTAssertTrue(ReportGoal.above180.isMet(24.6))
        XCTAssertFalse(ReportGoal.above180.isMet(25))
        XCTAssertTrue(ReportGoal.above250.isMet(4.9))
        XCTAssertFalse(ReportGoal.above250.isMet(5))
        XCTAssertTrue(ReportGoal.cv.isMet(36))
        XCTAssertFalse(ReportGoal.cv.isMet(36.2))
        XCTAssertTrue(ReportGoal.days.isMet(14))
        XCTAssertFalse(ReportGoal.days.isMet(13))
        XCTAssertTrue(ReportGoal.cgmActive.isMet(70))
        XCTAssertFalse(ReportGoal.cgmActive.isMet(69.6))
    }

    func testGoalsOfASummary() throws {
        let missed = glucoseSummary(percents: [1.5, 3.5, 68, 21, 6], daysWithData: 13, covered: 0.6)
        XCTAssertEqual(try XCTUnwrap(ReportGoal.inRange.value(missed)), 68, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(ReportGoal.below70.value(missed)), 5, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(ReportGoal.below54.value(missed)), 1.5, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(ReportGoal.above180.value(missed)), 27, accuracy: 1E-9)
        XCTAssertEqual(try XCTUnwrap(ReportGoal.above250.value(missed)), 6, accuracy: 1E-9)
        XCTAssertEqual(ReportGoal.days.value(missed), 13)
        XCTAssertEqual(try XCTUnwrap(ReportGoal.cgmActive.value(missed)), 60, accuracy: 1E-9)
        for goal in ReportGoal.allCases where goal != .cv {
            XCTAssertEqual(goal.isMet(missed), false, "\(goal)")
        }

        let met = glucoseSummary(percents: [0, 2, 80, 15, 3])
        for goal in ReportGoal.allCases where goal != .cv {
            XCTAssertEqual(goal.isMet(met), true, "\(goal)")
        }
        XCTAssertEqual(ReportGoal.cv.value(met), met.cv)

        let empty = glucoseSummary(percents: [0, 0, 0, 0, 0])
        for goal in ReportGoal.allCases {
            XCTAssertNil(goal.value(empty))
            XCTAssertNil(goal.isMet(empty))
        }
    }

    /// The marks follow the exact fractions, not the percents printed: very low 0.59% and low 3.59% are 4.18% below 70
    /// (not met, printed "4%", never the 3% a sum of floors would give); 70.4% in range is more than 70%.
    @MainActor func testGoalsOnExactFractions() throws {
        let summary = glucoseSummary(percents: [0.59, 3.59, 70.4, 19.92, 5.5])
        XCTAssertEqual(ReportGoal.below70.isMet(summary), false)
        XCTAssertEqual(ReportGoal.inRange.isMet(summary), true)
        XCTAssertEqual(ReportGoal.below54.isMet(summary), true)
        XCTAssertEqual(ReportGoal.above250.isMet(summary), false)

        let data = try Stat.ReportBuilder.assemble(reportRequest(), summary: summary, bins: bins(), now: Self.day0)
        let page = Stat.ReportSummary(data, units: .mgdL)
        // very high, high, in range, low, very low
        XCTAssertEqual(page.rows[3].goal?.text, "Below 70: 4% · goal <4%")
        XCTAssertEqual(page.rows[3].goal?.isMet, false)
        XCTAssertEqual(page.rows[2].percent, "70%")
        XCTAssertEqual(page.rows[2].goal?.text, "Goal >70%")
        XCTAssertEqual(page.rows[2].goal?.isMet, true)
        XCTAssertEqual(page.rows[4].goal?.isMet, true)
        XCTAssertEqual(page.rows[1].goal?.text, "Above 180: 25% · goal <25%")
        XCTAssertEqual(page.rows[1].goal?.isMet, false)
        XCTAssertEqual(page.rows[0].goal?.isMet, false)

        // 3.6% below 70 prints "4%" and is met: the mark is the exact value's
        let under = Stat.ReportSummary(
            try Stat.ReportBuilder.assemble(
                reportRequest(),
                summary: glucoseSummary(percents: [0.3, 3.3, 76.4, 17, 3]),
                bins: bins(),
                now: Self.day0
            ),
            units: .mgdL
        )
        XCTAssertEqual(under.rows[3].goal?.text, "Below 70: 4% · goal <4%")
        XCTAssertEqual(under.rows[3].goal?.isMet, true)

        // a trace of time below 70 is "<1%", not "0%"
        let trace = Stat.ReportSummary(
            try Stat.ReportBuilder.assemble(
                reportRequest(),
                summary: glucoseSummary(percents: [0.1, 0.2, 80, 16.7, 3]),
                bins: bins(),
                now: Self.day0
            ),
            units: .mgdL
        )
        XCTAssertEqual(trace.rows[3].goal?.text, "Below 70: <1% · goal <4%")
    }

    /// A CV of exactly 36% meets "≤36%".
    @MainActor func testCVGoalAtItsEdge() throws {
        // half the time at 64, half at 136: mean 100, SD 36
        let summary = glucoseSummary(values: [(64, 50), (136, 50)])
        XCTAssertEqual(summary.cv, 36)
        XCTAssertEqual(ReportGoal.cv.isMet(summary), true)
        let data = try Stat.ReportBuilder.assemble(reportRequest(), summary: summary, bins: bins(), now: Self.day0)
        let page = Stat.ReportSummary(data, units: .mgdL)
        XCTAssertEqual(page.metrics[4].value, "36%")
        XCTAssertEqual(page.metrics[4].goal?.isMet, true)

        // 37%: not met
        let above = glucoseSummary(values: [(63, 50), (137, 50)])
        XCTAssertEqual(ReportGoal.cv.isMet(above), false)
    }

    /// 3.0 × very low + 2.4 × low + 1.6 × very high + 0.8 × high, of the band shares of the summary's own bands.
    func testPeriodGRI() throws {
        let percents: [Double] = [1, 3, 70, 20, 6]
        let summary = glucoseSummary(percents: percents)
        let gri = try XCTUnwrap(Stat.ReportBuilder.gri(summary))
        XCTAssertEqual(gri.value, 3.0 * 1 + 2.4 * 3 + 1.6 * 6 + 0.8 * 20, accuracy: 1E-9)
        XCTAssertEqual(gri.zone, .b)
        let shares = summary.bandShares.fractions.map { $0 * 100 }
        XCTAssertEqual(gri.value, 3.0 * shares[0] + 2.4 * shares[1] + 1.6 * shares[4] + 0.8 * shares[3], accuracy: 1E-9)

        // 181 mg/dL is high on the mg/dL bands and in range on the mmol/L ones: the GRI follows the rows
        let edge: [(mgdl: Int16, percent: Double)] = [(120, 80), (181, 20)]
        XCTAssertEqual(try XCTUnwrap(Stat.ReportBuilder.gri(glucoseSummary(values: edge))).value, 0.8 * 20, accuracy: 1E-9)
        XCTAssertEqual(Stat.ReportBuilder.gri(glucoseSummary(values: edge, units: .mmolL))?.value, 0)

        XCTAssertEqual(Stat.ReportBuilder.gri(glucoseSummary(percents: [0, 0, 100, 0, 0]))?.value, 0)
        XCTAssertEqual(Stat.ReportBuilder.gri(glucoseSummary(percents: [0, 0, 100, 0, 0]))?.zone, .a)
        XCTAssertEqual(Stat.ReportBuilder.gri(glucoseSummary(percents: [40, 0, 0, 0, 60]))?.value, 100)
        XCTAssertEqual(Stat.ReportBuilder.gri(glucoseSummary(percents: [40, 0, 0, 0, 60]))?.zone, .e)
        XCTAssertNil(Stat.ReportBuilder.gri(glucoseSummary(percents: [0, 0, 0, 0, 0])))
    }

    // MARK: - Data

    /// One set of numbers, on the first unit's bands, whatever bands the summary came on.
    func testAssembleUsesTheFirstUnitsBands() throws {
        let data = try reportData(reportRequest(units: [.mgdL, .mmolL]))
        XCTAssertEqual(data.summary.bands, Stat.ReportBuilder.standardBands(.mgdL))
        XCTAssertNotNil(data.gri)
        XCTAssertEqual(data.pages.count, 4)
        let days = data.days(calendar: Self.calendar)
        XCTAssertEqual(days.first, Self.day0)
        // across the end of summer time: the 14th day's start, not 13 × 24 h on
        XCTAssertEqual(days.last, Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))

        let mmolFirst = try reportData(reportRequest(units: [.mmolL, .mgdL]))
        XCTAssertEqual(mmolFirst.summary.bands, Stat.ReportBuilder.standardBands(.mmolL))
        XCTAssertEqual(mmolFirst.summary.histogram, data.summary.histogram)

        // GRI off, or no Summary part: none
        XCTAssertNil(try reportData(reportRequest(summary: .init(insulinAndCarbs: true, gri: false))).gri)
        XCTAssertNil(try reportData(reportRequest(parts: [.percentileProfile])).gri)
        XCTAssertFalse(reportRequest(parts: [.percentileProfile]).needsInsulinAndCarbs)
        XCTAssertFalse(reportRequest(summary: .init(insulinAndCarbs: false, gri: true)).needsInsulinAndCarbs)
        XCTAssertTrue(reportRequest().needsInsulinAndCarbs)
    }

    func testAssembleWithoutDataOrParts() {
        XCTAssertThrowsError(
            try Stat.ReportBuilder.assemble(
                reportRequest(),
                summary: glucoseSummary(percents: [0, 0, 0, 0, 0]),
                bins: [],
                now: Self.day0
            )
        ) { XCTAssertEqual($0 as? Stat.ReportError, .noData) }
        XCTAssertThrowsError(
            try Stat.ReportBuilder.assemble(
                reportRequest(parts: []),
                summary: glucoseSummary(percents: [0, 0, 100, 0, 0]),
                bins: [],
                now: Self.day0
            )
        ) { XCTAssertEqual($0 as? Stat.ReportError, .nothingSelected) }
    }

    /// Both units in one report: the same numbers on both pages, also with time at exactly 181 and 141 mg/dL (in
    /// range and tight in mmol/L's bands, not in mg/dL's); only the labels and the values' unit differ.
    @MainActor func testBothUnitsPagesAgree() throws {
        let values: [(mgdl: Int16, percent: Double)] = [(60, 3), (120, 50), (141, 17), (181, 24), (300, 6)]
        func pages(_ units: [GlucoseUnits]) throws -> [Stat.ReportSummary] {
            let data = try Stat.ReportBuilder.assemble(
                reportRequest(units: units),
                summary: glucoseSummary(values: values),
                bins: bins(),
                now: Self.day0
            )
            return units.map { Stat.ReportSummary(data, units: $0) }
        }
        func numbers(_ page: Stat.ReportSummary) -> [String] {
            page.rows.map(\.percent) + page.rows.map(\.perDay) + page.rows.map { "\($0.goal?.isMet ?? false)" }
                + [5, 6, 9].map { page.metrics[$0].value } + page.metrics.map { "\($0.goal?.isMet ?? false)" }
        }

        let mgdlFirst = try pages([.mgdL, .mmolL])
        XCTAssertEqual(numbers(mgdlFirst[0]), numbers(mgdlFirst[1]))
        // mg/dL's bands: 181 is high, 141 is outside 70–140
        XCTAssertEqual(mgdlFirst[1].rows.map(\.percent), ["6%", "24%", "67%", "3%", "0%"])
        XCTAssertEqual(mgdlFirst[1].metrics[5].value, "67%")
        XCTAssertEqual(mgdlFirst[1].metrics[6].value, "50%")
        XCTAssertEqual(mgdlFirst[0].rows.map(\.range), ["> 250", "181–250", "70–180", "54–69", "< 54"])
        XCTAssertEqual(mgdlFirst[0].metrics[5].title, "TIR 70–180")
        XCTAssertNotEqual(mgdlFirst[0].metrics[5].title, mgdlFirst[1].metrics[5].title)
        XCTAssertNotEqual(mgdlFirst[0].rows.map(\.range), mgdlFirst[1].rows.map(\.range))
        // the chart's edges are drawn where the page's unit writes them
        XCTAssertEqual(mgdlFirst[0].plot.edges, [70, 180])
        XCTAssertEqual(mgdlFirst[1].plot.edges, [70, 181])
        XCTAssertEqual(mgdlFirst[1].plot.axis, 0 ... 360)

        let mmolFirst = try pages([.mmolL, .mgdL])
        XCTAssertEqual(numbers(mmolFirst[0]), numbers(mmolFirst[1]))
        // mmol/L's bands: 181 shows as 10.0 (in range), 141 as 7.8 (tight)
        XCTAssertEqual(mmolFirst[0].rows.map(\.percent), ["6%", "0%", "91%", "3%", "0%"])
        XCTAssertEqual(mmolFirst[1].metrics[5].value, "91%")
        XCTAssertEqual(mmolFirst[1].metrics[6].value, "67%")
        XCTAssertEqual(mmolFirst[1].plot.edges, [70, 180])
        XCTAssertEqual(mmolFirst[1].plot.levels.map(\.label).contains("181"), false)

        // a single unit: its own bands
        XCTAssertEqual(try pages([.mgdL])[0].rows.map(\.percent), mgdlFirst[0].rows.map(\.percent))
        XCTAssertEqual(try pages([.mmolL])[0].rows.map(\.percent), mmolFirst[0].rows.map(\.percent))
    }

    // MARK: - Pages' models

    func testPercentileAxisAndLevels() {
        typealias Plot = Stat.ReportPercentilePlot
        XCTAssertEqual(Plot.axis(highest: nil, units: .mgdL), 0 ... 350)
        XCTAssertEqual(Plot.axis(highest: 350, units: .mgdL), 0 ... 350)
        XCTAssertEqual(Plot.axis(highest: 351, units: .mgdL), 0 ... 400)
        XCTAssertEqual(Plot.axis(highest: 460, units: .mgdL), 0 ... 500)
        XCTAssertEqual(Plot.axis(highest: 240, units: .mmolL), 0 ... 360)
        XCTAssertEqual(Plot.axis(highest: 361, units: .mmolL), 0 ... 396)
        XCTAssertEqual(Plot.axis(highest: 600, units: .mgdL).upperBound, 600)

        let bands = Stat.ReportBuilder.standardBands(.mgdL)
        XCTAssertEqual(Plot.levels(bands: bands, axis: 0 ... 350, minimumGap: 0.04), [0, 54, 70, 180, 250, 350])
        // the compact chart: 54 is too close to 70
        XCTAssertEqual(Plot.levels(bands: bands, axis: 0 ... 350, minimumGap: 0.1), [0, 70, 180, 250, 350])
    }

    @MainActor func testSummaryModel() throws {
        let data = try reportData(reportRequest())
        let summary = Stat.ReportSummary(data, units: .mgdL)
        XCTAssertEqual(summary.rows.map(\.band), [.veryHigh, .high, .inRange, .low, .veryLow])
        XCTAssertEqual(summary.rows.map(\.percent), ["6%", "20%", "70%", "3%", "1%"])
        XCTAssertEqual(summary.rows.map(\.range), ["> 250", "181–250", "70–180", "54–69", "< 54"])
        XCTAssertEqual(summary.rows[2].goal?.text, "Goal >70%")
        XCTAssertEqual(summary.rows[1].goal?.text, "Above 180: 26% · goal <25%")
        XCTAssertEqual(summary.rows[1].goal?.isMet, false)
        XCTAssertEqual(summary.rows[0].goal?.text, "Goal <5%")
        XCTAssertEqual(summary.rows[0].goal?.isMet, false)
        XCTAssertEqual(summary.rows[4].goal?.text, "Goal <1%")
        XCTAssertEqual(summary.segments.map(\.band), [.veryHigh, .high, .inRange, .low, .veryLow])

        XCTAssertEqual(summary.metrics.map(\.id), Array(0 ... 9))
        XCTAssertEqual(summary.metrics[5].title, "TIR 70–180")
        XCTAssertEqual(summary.metrics[5].value, "70%")
        XCTAssertEqual(summary.metrics[6].title, "TITR 70–140")
        XCTAssertEqual(summary.metrics[4].goal?.text, "Goal ≤36%")
        XCTAssertEqual(summary.metrics[7].value, "100%")
        XCTAssertEqual(summary.metrics[7].goal?.isMet, true)
        XCTAssertEqual(summary.metrics[8].value, "14 of 14")
        XCTAssertEqual(summary.metrics[8].goal?.text, "Goal ≥14")
        XCTAssertEqual(summary.metrics[8].goal?.isMet, true)
        XCTAssertEqual(summary.metrics[9].value, "36 · zone B")
        XCTAssertNil(summary.limitedNote)
        XCTAssertEqual(summary.plot.axis, 0 ... 350)
        XCTAssertEqual(summary.plot.edges, [70, 180])
        XCTAssertEqual(summary.plot.xTicks.map(\.minute), [0, 360, 720, 1080])

        let block = try XCTUnwrap(summary.insulinAndCarbs)
        XCTAssertEqual(block.amounts.count, 5)
        XCTAssertEqual(block.amounts.map(\.detail), ["", "45%", "24%", "31%", ""])
        XCTAssertEqual(
            block.notes,
            ["Insulin: the mean of 13 complete days with pump data", "Carbs: the mean of 12 complete days with entries"]
        )

        // the block and GRI off
        let plain = Stat.ReportSummary(
            try reportData(reportRequest(summary: .init(insulinAndCarbs: false, gri: false)), withInsulin: false),
            units: .mgdL
        )
        XCTAssertNil(plain.insulinAndCarbs)
        XCTAssertEqual(plain.metrics.count, 9)

        // mmol/L alone: its own bands and labels
        let mmol = Stat.ReportSummary(try reportData(reportRequest(units: [.mmolL])), units: .mmolL)
        XCTAssertEqual(mmol.rows.map(\.percent), ["6%", "20%", "70%", "3%", "1%"])
        XCTAssertEqual(mmol.plot.axis, 0 ... 360)
        XCTAssertEqual(mmol.plot.edges, [70, 181])
    }

    /// The insulin and carbs block when a read failed, when there is nothing, and over one day.
    @MainActor func testInsulinAndCarbsBlockWithoutData() throws {
        func block(_ insulin: ReportRead<InsulinSummary>?, _ meals: ReportRead<MealSummary>?) throws
            -> Stat.ReportSummary.InsulinAndCarbs?
        {
            let data = try Stat.ReportBuilder.assemble(
                reportRequest(),
                summary: glucoseSummary(percents: [1, 3, 70, 20, 6]),
                bins: bins(),
                insulin: insulin,
                meals: meals,
                now: Self.day0
            )
            return Stat.ReportSummary(data, units: .mgdL).insulinAndCarbs
        }

        let failed = try XCTUnwrap(block(.failed, .failed))
        XCTAssertEqual(failed.amounts.map(\.value), ["–", "–", "–", "–", "–"])
        XCTAssertEqual(failed.amounts.map(\.detail), ["", "", "", "", ""])
        XCTAssertEqual(failed.notes, ["The pump data couldn't be read.", "The carb entries couldn't be read."])

        let empty = try XCTUnwrap(block(.value(insulin(isEmpty: true)), .value(meals(isEmpty: true))))
        XCTAssertEqual(empty.amounts.map(\.value), ["–", "–", "–", "–", "–"])
        XCTAssertEqual(empty.amounts.map(\.detail), ["", "", "", "", ""])
        XCTAssertEqual(empty.notes, ["No pump data in this period", "No carb entries in this period"])

        // one read failed: the other's numbers stay
        let half = try XCTUnwrap(block(.failed, .value(meals())))
        XCTAssertEqual(half.amounts.map(\.value).prefix(4), ["–", "–", "–", "–"])
        XCTAssertNotEqual(half.amounts[4].value, "–")
        XCTAssertEqual(half.notes.first, "The pump data couldn't be read.")

        let oneDay = try XCTUnwrap(block(.value(insulin(headlineDays: 1)), .value(meals(daysWithEntries: 1))))
        XCTAssertEqual(oneDay.notes, ["Insulin: 1 complete day with pump data", "Carbs: 1 complete day with entries"])

        // not asked for
        XCTAssertNil(try block(nil, nil))
    }

    /// Fewer than 14 days with data in a 14-day period: the note, and the days goal not met.
    @MainActor func testLimitedDataNote() throws {
        let limited = try Stat.ReportBuilder.assemble(
            reportRequest(),
            summary: glucoseSummary(percents: [1, 3, 70, 20, 6], daysWithData: 9),
            bins: bins(),
            now: Self.day0
        )
        let summary = Stat.ReportSummary(limited, units: .mgdL)
        XCTAssertNotNil(summary.limitedNote)
        XCTAssertEqual(summary.metrics[8].value, "9 of 14")
        XCTAssertEqual(summary.metrics[8].goal?.isMet, false)
        XCTAssertNotNil(Stat.ReportPercentile(limited, units: .mgdL).limitedNote)
    }

    /// A 7-day period can't have 14 days: the count without a mark, the note; CGM active keeps its mark.
    @MainActor func testShortPeriodHasNoDaysGoal() throws {
        let week = try Stat.ReportBuilder.assemble(
            reportRequest(period: .days7),
            summary: glucoseSummary(percents: [1, 3, 70, 20, 6], days: 7),
            bins: bins(),
            now: Self.day0
        )
        let summary = Stat.ReportSummary(week, units: .mgdL)
        XCTAssertEqual(summary.metrics[8].value, "7 of 7")
        XCTAssertNil(summary.metrics[8].goal)
        XCTAssertEqual(summary.metrics[7].goal?.isMet, true)
        XCTAssertNotNil(summary.limitedNote)

        let low = try Stat.ReportBuilder.assemble(
            reportRequest(period: .days7),
            summary: glucoseSummary(percents: [1, 3, 70, 20, 6], days: 7, covered: 0.5),
            bins: bins(),
            now: Self.day0
        )
        XCTAssertEqual(Stat.ReportSummary(low, units: .mgdL).metrics[7].goal?.isMet, false)
    }

    @MainActor func testPercentileModel() throws {
        let percentile = Stat.ReportPercentile(try reportData(reportRequest()), units: .mgdL)
        XCTAssertEqual(percentile.times.count, 8)
        XCTAssertEqual(percentile.rows.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertTrue(percentile.rows.allSatisfy { $0.values.count == 8 })
        // 00:00: the first bin's
        XCTAssertEqual(percentile.rows.map { $0.values[0] }, ["180", "145", "120", "100", "80"])
        XCTAssertEqual(percentile.plot.xTicks.count, 8)
        XCTAssertEqual(percentile.plot.gridMinutes.last, 1440)
        XCTAssertEqual(percentile.plot.levels.map(\.mgdl), [0, 54, 70, 180, 250, 350])
        XCTAssertNil(percentile.limitedNote)

        // a bin without data is a dash
        var bins = self.bins()
        bins[0] = nil
        let gap = try Stat.ReportBuilder.assemble(
            reportRequest(),
            summary: glucoseSummary(percents: [1, 3, 70, 20, 6]),
            bins: bins,
            now: Self.day0
        )
        XCTAssertEqual(Stat.ReportPercentile(gap, units: .mgdL).rows.map { $0.values[0] }, ["–", "–", "–", "–", "–"])
    }

    /// The header's days are the calendar's: across the end of summer time (25 Oct), and whatever the phone's zone.
    @MainActor func testPageChrome() throws {
        let data = try reportData(reportRequest(units: [.mgdL, .mmolL]))
        let calendar = Self.calendar
        let chrome = Stat.ReportPageChrome(data, page: data.pages[2], index: 2, count: 4, version: "9.9.9", calendar: calendar)
        XCTAssertEqual(chrome.title, "Percentile profile")
        XCTAssertEqual(chrome.days, "14 of 14 days with data")
        XCTAssertEqual(chrome.pageNumber, "Page 3 of 4")
        XCTAssertEqual(
            chrome.ranges,
            "Ranges (mg/dL): very low < 54 · low 54–69 · in range 70–180 · high 181–250 · very high > 250 · TITR 70–140"
        )
        XCTAssertTrue(chrome.provenance.hasPrefix("Generated by iAPS 9.9.9 from data on this device · "))
        XCTAssertTrue(chrome.provenance.hasSuffix(" · Time in ranges is time-weighted"))

        let style = Stat.ReportPageChrome.dayStyle(calendar)
        let last = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        XCTAssertEqual(chrome.dateRange, "\(Self.day0.formatted(style)) – \(last.formatted(style))")
        // 13 × 24 h after the first day is still 1 Nov there (a 25-hour day in between)
        XCTAssertNotEqual(last.formatted(style), Self.day0.addingTimeInterval(.days(13)).formatted(style))

        // the same data for a phone in Los Angeles: its days
        let west = Stat.ReportPageChrome(
            data,
            page: data.pages[0],
            index: 0,
            count: 4,
            version: "9.9.9",
            calendar: Self.losAngeles
        )
        XCTAssertNotEqual(west.dateRange, chrome.dateRange)
        let westStyle = Stat.ReportPageChrome.dayStyle(Self.losAngeles)
        XCTAssertTrue(west.dateRange.hasPrefix(Self.day0.formatted(westStyle)))

        // the other unit's page: its labels
        let mmol = Stat.ReportPageChrome(data, page: data.pages[1], index: 1, count: 4, version: "9.9.9", calendar: calendar)
        XCTAssertTrue(mmol.ranges.hasPrefix("Ranges (mmol/L): "))
        XCTAssertEqual(mmol.dateRange, chrome.dateRange)
    }

    // MARK: - The builder

    /// The provider's calls a report makes, faked.
    private actor FakeSource: ReportDataSource {
        struct Failure: Error {}

        let summary: GlucoseSummary
        let bins: [AGPBin?]
        let insulin: InsulinSummary?
        let meals: MealSummary?
        private(set) var begun = 0
        private(set) var ended = 0
        private(set) var reads: [String] = []

        init(summary: GlucoseSummary, bins: [AGPBin?], insulin: InsulinSummary?, meals: MealSummary?) {
            self.summary = summary
            self.bins = bins
            self.insulin = insulin
            self.meals = meals
        }

        func beginSession() { begun += 1 }
        func endSession() { ended += 1 }

        func reportProfile(_: StatsPeriod, bands _: StatsBands) -> Stat.AGPResult {
            reads.append("profile")
            let axis = GlucoseStatsEngine.agpAxis(bins)
            return Stat.AGPResult(
                bins: bins,
                points: GlucoseStatsEngine.agpPlotPoints(bins, axis: axis),
                axis: axis,
                summary: summary
            )
        }

        func reportInsulin(_: StatsPeriod) throws -> InsulinSummary {
            reads.append("insulin")
            guard let insulin else { throw Failure() }
            return insulin
        }

        func reportMeals(_: StatsPeriod, factor _: Double) throws -> MealSummary {
            reads.append("meals")
            guard let meals else { throw Failure() }
            return meals
        }
    }

    private func fakeSource(percents: [Double] = [1, 3, 70, 20, 6], readsFail: Bool = false) -> FakeSource {
        FakeSource(
            summary: glucoseSummary(percents: percents, units: .mmolL),
            bins: bins(),
            insulin: readsFail ? nil : insulin(),
            meals: readsFail ? nil : meals()
        )
    }

    /// The reads run inside one statistics session, closed on every way out.
    func testBuilderReadsInsideASession() async throws {
        let source = fakeSource()
        let data = try await Stat.ReportBuilder.build(reportRequest(), source: source, now: Self.day0)
        XCTAssertEqual(data.summary.bands, Stat.ReportBuilder.standardBands(.mgdL))
        XCTAssertEqual(data.insulin, .value(insulin()))
        XCTAssertEqual(data.meals, .value(meals()))
        var reads = await source.reads
        XCTAssertEqual(reads, ["profile", "insulin", "meals"])
        var sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions, [1, 1])

        // the block off, or no Summary: only the profile is read
        let profileOnly = fakeSource()
        let plain = try await Stat.ReportBuilder.build(
            reportRequest(parts: [.percentileProfile]),
            source: profileOnly,
            now: Self.day0
        )
        XCTAssertNil(plain.insulin)
        XCTAssertNil(plain.meals)
        reads = await profileOnly.reads
        XCTAssertEqual(reads, ["profile"])

        // a failed insulin or meals read marks its block, the report is still made
        let failing = fakeSource(readsFail: true)
        let partial = try await Stat.ReportBuilder.build(reportRequest(), source: failing, now: Self.day0)
        XCTAssertEqual(partial.insulin, .failed)
        XCTAssertEqual(partial.meals, .failed)
        sessions = await [failing.begun, failing.ended]
        XCTAssertEqual(sessions, [1, 1])

        // no CGM data: nothing to print
        let empty = fakeSource(percents: [0, 0, 0, 0, 0])
        do {
            _ = try await Stat.ReportBuilder.build(reportRequest(), source: empty, now: Self.day0)
            XCTFail("an empty period built a report")
        } catch {
            XCTAssertEqual(error as? Stat.ReportError, .noData)
        }
        sessions = await [empty.begun, empty.ended]
        XCTAssertEqual(sessions, [1, 1])

        // cancelled before it starts: nothing is read, the session is closed
        let cancelled = fakeSource()
        let request = reportRequest()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Stat.ReportBuilder.build(request, source: cancelled, now: Self.day0)
        }
        do {
            _ = try await task.value
            XCTFail("a cancelled build returned")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        sessions = await [cancelled.begun, cancelled.ended]
        XCTAssertEqual(sessions[0], sessions[1])
    }

    // MARK: - The written file

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-report-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// The text of a PDF without line breaks and runs of spaces (the extraction's own).
    private func plainText(_ document: PDFDocument) -> String {
        (document.string ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The pages a write reported.
    @MainActor private final class Steps {
        var done: [Int] = []
    }

    /// The files under a directory, at any depth.
    private func files(in directory: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        return (enumerator?.allObjects as? [URL] ?? []).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    /// Summary and Percentile profile on A4: two pages, portrait then landscape, with their text.
    @MainActor func testWritesSummaryAndPercentileProfile() async throws {
        let data = try reportData(reportRequest(paper: .a4))
        var steps: [Int] = []
        let parent = try temporaryDirectory()
        let output = try await ReportPDFWriter
            .write(data, version: "9.9.9", parent: parent, calendar: Self.calendar) { done, total in
                XCTAssertEqual(total, 2)
                steps.append(done)
            }
        XCTAssertEqual(steps, [1, 2])
        XCTAssertEqual(output.pageCount, 2)
        XCTAssertEqual(output.url.lastPathComponent, "iAPS report 2026-10-20 – 2026-11-02.pdf")
        XCTAssertEqual(output.url.deletingLastPathComponent().path, output.directory.path)
        XCTAssertEqual(output.directory.deletingLastPathComponent().path, parent.path)

        let document = try XCTUnwrap(PDFDocument(url: output.url))
        XCTAssertEqual(document.pageCount, 2)
        let first = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox).size
        let second = try XCTUnwrap(document.page(at: 1)).bounds(for: .mediaBox).size
        XCTAssertEqual(first.width, 595, accuracy: 0.5)
        XCTAssertEqual(first.height, 842, accuracy: 0.5)
        XCTAssertEqual(second.width, 842, accuracy: 0.5)
        XCTAssertEqual(second.height, 595, accuracy: 0.5)

        let attributes = document.documentAttributes ?? [:]
        XCTAssertEqual(attributes[PDFDocumentAttribute.titleAttribute] as? String, "iAPS report 2026-10-20 – 2026-11-02")
        XCTAssertEqual(attributes[PDFDocumentAttribute.creatorAttribute] as? String, "iAPS 9.9.9")
        XCTAssertNil(attributes[PDFDocumentAttribute.authorAttribute])

        let text = plainText(document)
        for expected in [
            "Summary",
            "Percentile profile",
            "70–180",
            "GMI",
            "Date of birth",
            "Generated by iAPS 9.9.9 from data on this device",
            "Time in ranges is time-weighted",
            "Page 1 of 2",
            "Page 2 of 2",
            "Glycemia Risk Index",
            "Insulin and carbs per day"
        ] {
            XCTAssertTrue(text.contains(expected), "missing \"\(expected)\"")
        }
    }

    /// US Letter, both units: every page twice, the sizes the paper's.
    @MainActor func testWritesBothUnitsOnLetter() async throws {
        let data = try reportData(reportRequest(units: [.mgdL, .mmolL], paper: .letter))
        let parent = try temporaryDirectory()
        let output = try await ReportPDFWriter.write(data, version: "9.9.9", parent: parent, calendar: Self.calendar)
        let document = try XCTUnwrap(PDFDocument(url: output.url))
        XCTAssertEqual(document.pageCount, 4)
        let sizes = try (0 ..< 4).map { try XCTUnwrap(document.page(at: $0)).bounds(for: .mediaBox).size }
        for size in sizes.prefix(2) {
            XCTAssertEqual(size.width, 612, accuracy: 0.5)
            XCTAssertEqual(size.height, 792, accuracy: 0.5)
        }
        for size in sizes.suffix(2) {
            XCTAssertEqual(size.width, 792, accuracy: 0.5)
            XCTAssertEqual(size.height, 612, accuracy: 0.5)
        }
        let text = plainText(document)
        XCTAssertTrue(text.contains("mg/dL"))
        XCTAssertTrue(text.contains("mmol/L"))
        XCTAssertTrue(text.contains("Page 4 of 4"))
    }

    /// A single part; a write cancelled before it starts, or between two pages, leaves nothing behind.
    @MainActor func testWritesOnePartAndCancels() async throws {
        let parent = try temporaryDirectory()
        let calendar = Self.calendar
        let one = try reportData(reportRequest(parts: [.percentileProfile]))
        let output = try await ReportPDFWriter.write(one, version: "9.9.9", parent: parent, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: output.url)).pageCount, 1)
        try FileManager.default.removeItem(at: output.directory)

        let early = Task { @MainActor in
            try await ReportPDFWriter.write(one, version: "9.9.9", parent: parent, calendar: calendar)
        }
        early.cancel()
        do {
            _ = try await early.value
            XCTFail("a cancelled write returned")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(files(in: parent), [])

        // cancelled after the first of four pages: the others aren't drawn
        let four = try reportData(reportRequest(units: [.mgdL, .mmolL]))
        let steps = Steps()
        let between = Task { @MainActor in
            try await ReportPDFWriter.write(four, version: "9.9.9", parent: parent, calendar: calendar) { done, _ in
                steps.done.append(done)
                if done == 1 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do {
            _ = try await between.value
            XCTFail("a write cancelled between two pages returned")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(steps.done, [1])
        XCTAssertEqual(files(in: parent), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [])
    }

    // MARK: - The exporter

    /// Waits for the main actor's `condition`, up to 20 s.
    @MainActor private func wait(for condition: () -> Bool) async {
        for _ in 0 ..< 4000 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @MainActor private func makeExporter(_ source: FakeSource, parent: URL) -> Stat.ReportExporter {
        let exporter = Stat.ReportExporter(preferences: reportPreferences(), parent: parent, calendar: { Self.calendar })
        exporter.context = {
            Stat.ReportContext(
                source: source,
                userUnits: .mgdL,
                hbA1cUnit: .percent,
                carbEquivalentFactor: 0.5,
                screenPeriod: .today
            )
        }
        return exporter
    }

    /// A view's "Export PDF": the file goes to the root's preview only, and is removed with it.
    @MainActor func testExporterMakesAPartAndRemovesItWithThePreview() async throws {
        let parent = try temporaryDirectory()
        // left by an earlier run: gone when the exporter is made
        let stale = parent.appendingPathComponent("stale.pdf")
        try Data([1]).write(to: stale)
        let exporter = makeExporter(fakeSource(), parent: parent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertFalse(exporter.isRunning)

        exporter.export(part: .summary)
        XCTAssertEqual(exporter.running, .part(.summary))
        await wait { !exporter.isRunning }
        let preview = try XCTUnwrap(exporter.preview)
        XCTAssertEqual(preview.origin, .part(.summary))
        // Today on screen: the nearest period a report has, 7 days... the fake's summary is 14 days long
        XCTAssertTrue(preview.url.lastPathComponent.hasPrefix("iAPS report 2026-10-20"))
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: preview.url)).pageCount, 1)
        XCTAssertEqual(files(in: parent).map(\.lastPathComponent), [preview.url.lastPathComponent])
        XCTAssertNil(exporter.failure)
        XCTAssertEqual(exporter.progress, 0)

        // only the presenter of its side sees it
        XCTAssertEqual(exporter.previewBinding(screen: false).wrappedValue, preview.url)
        XCTAssertNil(exporter.previewBinding(screen: true).wrappedValue)
        exporter.previewBinding(screen: true).wrappedValue = nil
        XCTAssertNotNil(exporter.preview)

        // dismissed: the file goes
        exporter.previewBinding(screen: false).wrappedValue = nil
        XCTAssertNil(exporter.preview)
        XCTAssertEqual(files(in: parent), [])
    }

    /// The Reports screen's report: every selected part, to its own preview; the next report removes the one before.
    @MainActor func testExporterMakesTheScreensReport() async throws {
        let parent = try temporaryDirectory()
        let exporter = makeExporter(fakeSource(), parent: parent)
        var options = exporter.preferences.options(userUnits: .mgdL)
        options.units = .both
        exporter.export(options)
        XCTAssertEqual(exporter.running, .screen)
        await wait { !exporter.isRunning }
        let first = try XCTUnwrap(exporter.preview)
        XCTAssertEqual(first.origin, .screen)
        XCTAssertEqual(try XCTUnwrap(PDFDocument(url: first.url)).pageCount, 4)
        XCTAssertNil(exporter.previewBinding(screen: false).wrappedValue)
        XCTAssertEqual(exporter.previewBinding(screen: true).wrappedValue, first.url)

        exporter.export(part: .percentileProfile)
        XCTAssertNil(exporter.preview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        await wait { !exporter.isRunning }
        XCTAssertEqual(exporter.preview?.origin, .part(.percentileProfile))
        XCTAssertEqual(files(in: parent).count, 1)
    }

    /// A failure is said where the report was asked for, and goes with the next report or a change of view.
    @MainActor func testExporterFailureBelongsToItsOrigin() async throws {
        let parent = try temporaryDirectory()
        let exporter = makeExporter(fakeSource(percents: [0, 0, 0, 0, 0]), parent: parent)
        exporter.export(part: .summary)
        await wait { !exporter.isRunning }
        XCTAssertNil(exporter.preview)
        XCTAssertEqual(exporter.failure(at: .part(.summary)), "No CGM data in this period")
        XCTAssertNil(exporter.failure(at: .part(.percentileProfile)))
        XCTAssertNil(exporter.failure(at: .screen))
        XCTAssertEqual(files(in: parent), [])

        exporter.clearFailure()
        XCTAssertNil(exporter.failure(at: .part(.summary)))

        exporter.export(part: .summary)
        await wait { !exporter.isRunning }
        XCTAssertNotNil(exporter.failure(at: .part(.summary)))
        // the next one starts clean
        exporter.export(part: .percentileProfile)
        XCTAssertNil(exporter.failure)
        await wait { !exporter.isRunning }
        XCTAssertNil(exporter.failure(at: .part(.summary)))
        XCTAssertNotNil(exporter.failure(at: .part(.percentileProfile)))

        // nothing selected on the Reports screen
        var options = exporter.preferences.options(userUnits: .mgdL)
        options.parts = []
        exporter.export(options)
        await wait { !exporter.isRunning }
        XCTAssertEqual(exporter.failure(at: .screen), "Select at least one part.")
    }

    /// Cancel, Statistics going down, or the exporter gone: no report is running, shown or left on disk.
    @MainActor func testExporterCancelAndLifetime() async throws {
        let parent = try temporaryDirectory()
        let source = fakeSource()
        var exporter: Stat.ReportExporter? = makeExporter(source, parent: parent)
        var options = try XCTUnwrap(exporter).preferences.options(userUnits: .mgdL)
        options.units = .both

        exporter?.export(options)
        exporter?.cancel()
        XCTAssertEqual(exporter?.isRunning, false)
        XCTAssertEqual(exporter?.progress, 0)
        // the cancelled run ends on its own: its session closed, nothing shown, nothing written
        await wait { self.files(in: parent).isEmpty }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(exporter?.preview)
        XCTAssertNil(exporter?.failure)
        XCTAssertEqual(exporter?.isRunning, false)
        XCTAssertEqual(files(in: parent), [])
        var sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions[0], sessions[1])

        // after a cancel it makes the next one
        exporter?.export(part: .summary)
        await wait { exporter?.isRunning == false }
        XCTAssertNotNil(exporter?.preview)

        // gone while a report is being made (Statistics closed): the run stops and removes what it wrote
        exporter?.export(options)
        exporter = nil
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(files(in: parent), [])
        sessions = await [source.begun, source.ended]
        XCTAssertEqual(sessions[0], sessions[1])
    }
}
