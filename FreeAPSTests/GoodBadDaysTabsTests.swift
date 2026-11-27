@testable import FreeAPS
import LoopKit
import SwiftUI
import Swinject
import XCTest

/// Good & bad days: the view in the title menu and its own period, the picks without a read, a day opened on the Day
/// tab, the content formatted from the engine's result (the counts, the captions, the too-few-days message, the day
/// lists), the GRI sheet's strings.
final class GoodBadDaysTabsTests: XCTestCase {
    // MARK: - Fixtures

    private let calendar = StatsFixtures.berlin
    private let bands = StatsBands(low: 70, high: 180, units: .mgdL)

    /// 2026-09-01 00:00 Europe/Berlin: 54 days of 24 hours follow (to the change to CET on 25 Oct)
    private var start: Date { calendar.date(byAdding: .day, value: -49, to: StatsFixtures.day0)! }

    /// An expected string with its decimal points as the locale writes them.
    private func d(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    /// The whole calendar day `offset` days after `start`.
    private func interval(_ offset: Int) -> DateInterval {
        let dayStart = calendar.date(byAdding: .day, value: offset, to: start)!
        return DateInterval(start: dayStart, end: StatsClock.endOfDay(dayStart, calendar: calendar))
    }

    /// The local clock time on the day `offset` days after `start`.
    private func clock(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: interval(offset).start)!
    }

    /// The kinds of the fixture's days, by GRI.
    private enum Kind {
        /// all of it at 120: GRI 0
        case good
        /// 10 % at 60 (02:00–04:24 in the readings: 02:00–04:00): GRI 24
        case low
        /// 60 % at 220 (in the readings 14:00–20:00): GRI 48
        case high
        /// 5 % at 60, 55 % at 220: GRI 56
        case lowAndHigh
        /// 40 % at 200 (08:00–18:00): GRI 32
        case neither
        /// 40 % covered
        case uncovered
    }

    private func aggregate(_ offset: Int, _ kind: Kind) -> DayAggregate {
        let entries: [(mgdl: Int16, percent: Double)]
        switch kind {
        case .good: entries = [(120, 100)]
        case .low: entries = [(60, 10), (120, 90)]
        case .high: entries = [(220, 60), (120, 40)]
        case .lowAndHigh: entries = [(60, 5), (220, 55), (120, 40)]
        case .neither: entries = [(200, 40), (120, 60)]
        case .uncovered: entries = [(120, 40)]
        }
        let day = interval(offset)
        var histogram = GlucoseHistogram()
        for entry in entries {
            let seconds = entry.percent * day.duration / 100
            histogram.add(WeightedPoint(time: day.start, mgdl: entry.mgdl, span: seconds), seconds: seconds, startsInside: true)
        }
        return DayAggregate(day: day, histogram: histogram)
    }

    /// A day's readings every 5 minutes: 120, 60 from 02:00 to 04:00 on a low day, 220 from 14:00 to 20:00 on a high one.
    private func readings(_ kinds: [Kind]) -> [WeightedPoint] {
        let points = kinds.enumerated().flatMap { offset, kind in
            let day = interval(offset)
            return stride(from: 0, to: day.duration, by: 300).map { seconds -> GlucosePoint in
                let hour = Int(seconds) / 3600
                var mgdl: Int16 = 120
                if kind == .low || kind == .lowAndHigh, (2 ..< 4).contains(hour) {
                    mgdl = 60
                }
                if kind == .high || kind == .lowAndHigh, (14 ..< 20).contains(hour) {
                    mgdl = 220
                }
                if kind == .neither, (8 ..< 18).contains(hour) {
                    mgdl = 200
                }
                return GlucosePoint(time: day.start.addingTimeInterval(seconds), mgdl: mgdl)
            }
        }
        return GlucoseStatsEngine.weigh(GlucoseStatsEngine.clean(points))
    }

    /// 30 days: 14 good, 6 low, 2 low and high, 5 high, 3 neither. The best third the 10 newest good days (4–13, the
    /// newer day first on a tie), the worst the low and high, the high and the neither days (20–29).
    private var month: [Kind] {
        Array(repeating: .good, count: 14) + Array(repeating: .low, count: 6) + [.lowAndHigh, .lowAndHigh]
            + Array(repeating: .high, count: 5) + Array(repeating: .neither, count: 3)
    }

    private func result(_ kinds: [Kind], period: StatsPeriod = .days30) -> GoodBadDaysResult {
        GoodBadDaysEngine.result(
            period: period,
            days: kinds.enumerated().map { aggregate($0.offset, $0.element) },
            readings: readings(kinds),
            bands: bands,
            calendar: calendar
        )
    }

    private var settings: Stat.StatsSettings {
        var freeAPSSettings = FreeAPSSettings()
        freeAPSSettings.units = .mgdL
        freeAPSSettings.low = 70
        freeAPSSettings.high = 180
        return Stat.StatsSettings(freeAPSSettings)
    }

    @MainActor private func model(_ kinds: [Kind], period: StatsPeriod = .days30) -> Stat.GoodBadDays {
        Stat.GoodBadDays(
            Stat.GoodBadDaysData(period: period, result: result(kinds, period: period)),
            settings: settings,
            now: clock(kinds.count, 12),
            calendar: calendar
        )
    }

    // MARK: - The tab

    /// In the Glucose topic right after the AGP, with its title and a symbol; computed from the readings and the bands.
    @MainActor func testTheTabAndTheMenu() {
        let views = StatsTopic.glucose.views
        XCTAssertEqual(views.firstIndex(of: .goodBadDays), views.firstIndex(of: .agp)! + 1)
        XCTAssertEqual(StatsTab.allCases.firstIndex(of: .goodBadDays), StatsTab.allCases.firstIndex(of: .agp)! + 1)
        XCTAssertEqual(StatsTab.goodBadDays.topic, .glucose)
        XCTAssertTrue(StatsTab.goodBadDays.isGlucose)
        XCTAssertTrue(StatsTab.goodBadDays.usesBands)
        XCTAssertEqual(StatsViewMenu.title(.goodBadDays), "Good & bad days")
        XCTAssertEqual(StatsViewMenu.navigationTitle(.goodBadDays), "Glucose · Good & bad days")
        XCTAssertEqual(StatsViewMenu.systemImage(.goodBadDays), "square.split.2x1")
        XCTAssertNotNil(UIImage(systemName: StatsViewMenu.systemImage(.goodBadDays)))
    }

    /// 14, 30 and 90 days (no 7: a group needs 5 days), a period of its own: 30 when Statistics opens whatever the
    /// preferred one, a pick there leaves the preferred one (and By weekday's) as it is, a pick elsewhere leaves its own.
    @MainActor func testAPeriodOfItsOwn() {
        typealias Model = Stat.StateModel
        XCTAssertEqual(StatsTab.goodBadDays.validPeriods, [.days14, .days30, .days90])
        XCTAssertFalse(StatsTab.goodBadDays.validPeriods.contains(.days7))
        XCTAssertTrue(StatsTab.goodBadDays.hasPeriodControl)
        XCTAssertEqual(Model.goodBadDaysOpeningPeriod, .days30)

        for preferred in StatsPeriod.allCases {
            // opening: 30 days, not the preferred one (7 d, say)
            XCTAssertEqual(Model.shownPeriod(on: .goodBadDays, preferred: preferred, weekday: .weeks8), .days30, "\(preferred)")
            for own in StatsTab.goodBadDays.validPeriods {
                XCTAssertEqual(
                    Model.shownPeriod(on: .goodBadDays, preferred: preferred, weekday: .weeks8, goodBadDays: own),
                    own
                )
            }
        }
        // a pick on it: the preferred one and By weekday's stay, so every other view shows what it showed
        let picked = Model.picking(.days90, on: .goodBadDays, preferred: .days7, weekday: .weeks4, goodBadDays: .days30)
        XCTAssertEqual(picked.preferred, .days7)
        XCTAssertEqual(picked.weekday, .weeks4)
        XCTAssertEqual(picked.goodBadDays, .days90)
        for tab in StatsTab.allCases where tab != .goodBadDays {
            XCTAssertEqual(
                Model.shownPeriod(on: tab, preferred: picked.preferred, weekday: picked.weekday, goodBadDays: picked.goodBadDays),
                Model.shownPeriod(on: tab, preferred: .days7, weekday: .weeks4, goodBadDays: .days30),
                "\(tab)"
            )
        }
        // a period it doesn't offer changes nothing
        XCTAssertEqual(Model.picking(.days7, on: .goodBadDays, preferred: .days14, weekday: .weeks8).goodBadDays, .days30)
        // a pick elsewhere: its own stays
        let elsewhere = Model.picking(.days7, on: .agp, preferred: .days30, weekday: .weeks8, goodBadDays: .days90)
        XCTAssertEqual(elsewhere.preferred, .days7)
        XCTAssertEqual(elsewhere.goodBadDays, .days90)
        XCTAssertEqual(
            Model.picking(.weeks4, on: .weekday, preferred: .days7, weekday: .weeks8, goodBadDays: .days14).goodBadDays,
            .days14
        )
    }

    /// The time and the open lists are picks, not requests: a pick calls only the pick hook (the first interaction
    /// after midnight reads again); another period (the screen's reset) opens the time on the main stretch again, the
    /// day lists stay open.
    @MainActor func testThePicksReadNothing() {
        let model = model(month)
        let selection = GoodBadDaysSelection()
        var picks = 0
        selection.onPick = { picks += 1 }
        XCTAssertNil(selection.bin)
        XCTAssertEqual(selection.bin(opening: model.content.openingBin), model.content.openingBin)

        selection.select(bin: 10)
        selection.toggle(.compared)
        XCTAssertEqual(selection.bin, 10)
        XCTAssertEqual(selection.open, [.compared])
        XCTAssertEqual(picks, 2)

        // the same one again: a pick, nothing changes
        selection.select(bin: 10)
        XCTAssertEqual(selection.bin, 10)
        XCTAssertEqual(picks, 3)

        // another period (the screen's reset, not a pick): the time only
        selection.showMainStretch()
        XCTAssertNil(selection.bin)
        XCTAssertEqual(selection.open, [.compared])
        XCTAssertEqual(picks, 3)

        selection.toggle(.compared)
        XCTAssertEqual(selection.open, [])
    }

    /// A day of a list opens the Day tab on that day, not on today: a past day by its start (it stays inside the
    /// selector's 90 days); today's as Today.
    func testADayOpensTheDayTabOnIt() {
        typealias TraceDay = Stat.TraceDay
        let today = interval(30).start
        let day = interval(27)
        let opened = Stat.StateModel.openedDay(day.start.addingTimeInterval(.hours(5)), today: today, calendar: calendar)
        XCTAssertEqual(opened, .day(day.start))
        XCTAssertNotEqual(opened, .today)
        XCTAssertEqual(opened.shown(today: today, calendar: calendar), .day(day.start))
        XCTAssertEqual(opened.range(requestedAt: today, calendar: calendar), .day(day.start))
        XCTAssertEqual(Stat.StateModel.openedDay(today, today: today, calendar: calendar), .today)
    }

    // MARK: - The content

    /// The counts and the thirds' ranges under them, the days left out; the GRI caption.
    @MainActor func testTheCountsAndTheLines() {
        let content = model(month + [.uncovered]).content
        XCTAssertEqual(content.counts, "10 best · 10 worst · 10 in between")
        XCTAssertEqual(content.lines, [
            "Best third: GRI 0–0, in range 100–100%",
            "Worst third: GRI 32–56, in range 40–60%",
            "1 day with too little CGM data left out"
        ])
        XCTAssertEqual(Stat.GoodBadDays.griCaption, "Days are ranked by GRI, the Glycemia Risk Index: 0 is best, 100 worst.")
    }

    /// Both groups shown: the caption names the main stretch with both medians (and when the worst third is lower),
    /// the chart opens on its middle hour, the stretches are drawn split at midnight, the glucose rows show; a group
    /// under 10 days is marked.
    @MainActor func testTheCaptionAndTheTime() {
        let content = model(month).content
        XCTAssertTrue(content.isComparable)
        XCTAssertNil(content.message)
        // the clock times as the locale shows them
        func time(_ minute: Int) -> String { Stat.AGP.clockTime(minute) }
        // the stretch's medians are the engine's means over its bins: the worst third's mixes 220 and 200 (the neither
        // days until 18:00), its first and last bins pool a neighbour outside it, so it comes out near 206 and the low
        // one near 65, too near a rounding to hard-code: the caption is checked against the engine's values, these
        // near them
        let highMain = result(month).thirds.highlights[0]
        XCTAssertEqual(highMain.compared, 206, accuracy: 5)
        XCTAssertEqual(
            content.caption,
            "Medians differ most \(time(840))–\(time(1200)): 120 vs \(Int(highMain.compared.rounded())) mg/dL"
        )
        XCTAssertEqual(content.highlights, [840 ..< 1200])
        // 17:00
        XCTAssertEqual(content.openingBin, 68)
        // thirds of 10: not limited
        XCTAssertFalse(content.isLimited)
        XCTAssertEqual(content.glucoseRows.map(\.id), GoodBadDaysResult.GlucoseRowID.allCases)
        XCTAssertEqual(content.reference.readouts[68], ["120", "120", "120"])
        // 7 of the 10 worst days at 220 at 17:00, the 3 others at 200: the median between them
        let worst = result(month).thirds.compared.bins[68]?.p50
        XCTAssertEqual(worst ?? 0, 214, accuracy: 3)
        XCTAssertEqual(content.compared.readouts[68]?[1], worst.map { StatsFormatting.glucose($0, units: .mgdL) })
        XCTAssertEqual(content.compared.plottedMedians[68], worst)

        // the worst third lower: 10 good days, 5 low ones (thirds of 5)
        let lowKinds = Array(repeating: Kind.good, count: 10) + Array(repeating: .low, count: 5)
        let lowMain = result(lowKinds).thirds.highlights[0]
        XCTAssertEqual(lowMain.compared, 65, accuracy: 2.5)
        let low = model(lowKinds).content
        XCTAssertEqual(
            low.caption,
            "Medians differ most \(time(120))–\(time(240)): 120 vs \(Int(lowMain.compared.rounded())) mg/dL, lower on the worst third"
        )
        XCTAssertEqual(low.openingBin, 12)
        XCTAssertTrue(low.isLimited)
        XCTAssertTrue(low.profileNote.hasSuffix("Under 10 days in a group: the profile and the figures are provisional."))

        // a stretch across midnight: drawn as two, named by its clock times
        XCTAssertEqual(Stat.GoodBadDays.drawn(1320 ..< 1560), [1320 ..< 1440, 0 ..< 120])
        XCTAssertEqual(Stat.GoodBadDays.drawn(840 ..< 1200), [840 ..< 1200])
        XCTAssertEqual(Stat.GoodBadDays.stretch(1320 ..< 1560), "\(time(1320))–\(time(120))")
    }

    /// The glucose rows: both medians with their IQR, the difference compared − reference as shown.
    @MainActor func testTheGlucoseRows() {
        let rows = model(month).content.glucoseRows
        let gri = rows[0]
        XCTAssertEqual(gri.name, "GRI")
        XCTAssertEqual(gri.reference.value, "0")
        XCTAssertEqual(gri.reference.range, "(0–0)")
        // 32 × 3, 48 × 5, 56 × 2
        XCTAssertEqual(gri.compared.value, "48")
        XCTAssertEqual(gri.difference, "+48")
        let inRange = rows[1]
        XCTAssertEqual(inRange.detail, "70–180")
        XCTAssertEqual(inRange.reference.value, "100%")
        XCTAssertEqual(inRange.compared.value, "40%")
        XCTAssertEqual(inRange.difference, "−60 pt")
        let below = rows[2]
        XCTAssertEqual(below.name, "Below 70")
        XCTAssertEqual(below.reference.value, d("0.0%"))
        XCTAssertEqual(below.difference, d("±0.0 pt"))
        let mean = rows[3]
        XCTAssertEqual(mean.detail, "mg/dL")
        XCTAssertEqual(mean.reference.value, "120")
        // 152 × 3, 172 × 2, 180 × 5: between the 5th and the 6th
        XCTAssertEqual(mean.compared.value, "176")
        XCTAssertEqual(mean.difference, "+56")
    }

    /// Thirds under 5 days (under 14 days scored): no comparison, the message says why, the rows hidden, the day lists
    /// kept. 14 days scored: thirds of 5, shown, marked as limited.
    @MainActor func testTooFewDays() {
        let fourteen: [Kind] = Array(repeating: .good, count: 8) + [.high, .high] + Array(repeating: .neither, count: 4)
        let fortnight = model(fourteen, period: .days14).content
        XCTAssertTrue(fortnight.isComparable)
        XCTAssertTrue(fortnight.isLimited)

        // a day without enough CGM data: thirds of 4
        let thirteen = model(Array(fourteen.dropLast()) + [.uncovered], period: .days14).content
        XCTAssertFalse(thirteen.isComparable)
        XCTAssertNil(thirteen.caption)
        XCTAssertEqual(thirteen.glucoseRows, [])
        XCTAssertEqual(thirteen.factorSections, [])
        XCTAssertEqual(thirteen.message?.title, "Too few days: each group needs at least 5")
        XCTAssertEqual(thirteen.message?.detail, "13 of 14 days scored, so each third has 4.")
        XCTAssertFalse(thirteen.reference.isShown)
        XCTAssertFalse(thirteen.compared.isShown)
        XCTAssertEqual(thirteen.compared.points, [])
        XCTAssertEqual(thirteen.compared.days.count, 4)
        XCTAssertFalse(thirteen.isLimited)

        // a group of one day: its span is that date
        let single = model([.good, .high], period: .days14).content
        XCTAssertEqual(single.compared.span, interval(1).start.formatted(.dateTime.day().month(.abbreviated)))
    }

    /// A group's days, newest first: TIR, GRI with its zone; the group's span.
    @MainActor func testTheDayLists() {
        let content = model(month).content
        let days = content.compared.days
        XCTAssertEqual(days.map(\.id), (20 ... 29).reversed().map { interval($0).start })
        XCTAssertEqual(content.compared.title, "Worst third (10)")
        XCTAssertEqual(content.compared.name, "Worst third")
        // 40 % at 200: GRI 1.6 × 20 = 32 (zone B)
        XCTAssertEqual(days[0].detail, "in range 60%")
        XCTAssertEqual(days[0].gri, "GRI 32 · B")
        // 5 % at 60, 55 % at 220: GRI 3 × 4 + 1.6 × 27.5 = 56 (zone C)
        XCTAssertEqual(days[9].detail, "in range 40%")
        XCTAssertEqual(days[9].gri, "GRI 56 · C")
        XCTAssertEqual(days[9].segments.map(\.band), [.low, .inRange, .high])
        XCTAssertEqual(content.reference.days.map(\.id), (4 ... 13).reversed().map { interval($0).start })
        XCTAssertEqual(content.reference.title, "Best third (10)")
        XCTAssertEqual(content.reference.name, "Best third")
        XCTAssertNotEqual(content.reference.span, "None")
    }

    // MARK: - The factors

    /// The meals of a day of the kind (the low treatments of a low day: during the low at 02:30, 20 min after it at 04:20).
    private func meals(_ offset: Int, _ kind: Kind) -> [MealPoint] {
        func entry(_ hour: Int, _ minute: Int, _ carbs: Double, fat: Double = 0, protein: Double = 0) -> MealPoint {
            MealPoint(
                id: "\(offset)-\(hour)-\(minute)",
                actualDate: clock(offset, hour, minute),
                carbs: carbs,
                fat: fat,
                protein: protein
            )
        }
        var entries: [MealPoint]
        switch kind {
        case .high,
             .lowAndHigh:
            // 170 g: a meal at 08:00, a large fatty one at 20:30, a late snack at 22:00
            entries = [entry(8, 0, 40), entry(20, 30, 100, fat: 30), entry(22, 0, 30)]
        case .good,
             .low,
             .neither,
             .uncovered:
            // 110 g: breakfast in two entries 20 min apart (one meal of 50 g), dinner at 19:00
            entries = [entry(8, 0, 40, fat: 5, protein: 10), entry(8, 20, 10), entry(19, 0, 60, fat: 5, protein: 10)]
        }
        if kind == .low || kind == .lowAndHigh {
            entries += [entry(2, 30, 15), entry(4, 20, 12)]
        }
        return entries
    }

    /// A day's insulin: 1 U/h scheduled and delivered, an SMB of 0.5 U, a bolus of 5 U (8 U on a high day).
    private func insulin(_ kinds: [Kind]) -> [DayInsulin] {
        let days = kinds.indices.map { interval($0) }
        var events: [PumpEventRecord] = []
        for (offset, kind) in kinds.enumerated() {
            let bolus = kind == .high || kind == .lowAndHigh ? 8.0 : 5.0
            events.append(PumpEventRecord(date: clock(offset, 8), kind: .bolus, source: .pump, units: bolus, isSMB: false))
            events.append(PumpEventRecord(date: clock(offset, 9), kind: .bolus, source: .pump, units: 0.5, isSMB: true))
        }
        let input = InsulinInput(
            events: events,
            coverage: days.map { CoveredInterval(interval: $0, source: .pump) },
            schedules: [BasalScheduleRecordValue(
                date: interval(-400).start,
                source: .local,
                entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
            )]
        )
        return InsulinStatsEngine.days(days, input: input, now: clock(kinds.count, 12), calendar: calendar)
    }

    /// A patch changed every third evening at 20:00 from the first day's.
    private var patches: [PatchSession] {
        (0 ..< 11).map { index in
            let activation = clock(index * 3, 20)
            return PatchSession(
                id: "\(index)",
                plugin: "Medtrum",
                kind: .patch,
                activation: activation,
                isActivationKnown: true,
                end: clock(index * 3 + 3, 20),
                dataStart: activation,
                gaps: []
            )
        }
    }

    /// A CGM sensor changed every 10 days at 07:00 from the third day's; the first one started before the recording.
    private var sensors: [GoodBadDaysSensor] {
        [GoodBadDaysSensor(start: clock(-8, 7), sessions: [DateInterval(start: interval(0).start, end: clock(2, 7))])]
            + [2, 12, 22].map { first in
                GoodBadDaysSensor(
                    start: clock(first, 7),
                    sessions: [DateInterval(start: clock(first, 7), end: first == 22 ? .distantFuture : clock(first + 10, 7))]
                )
            }
    }

    /// The month's factor input: the meals (one high day without any), the insulin, the patches, the CGM sensors, the
    /// loop's slots (none on days 20–25: only 4 of the worst third's days have them), every day's GRI.
    private func factorInput(_ kinds: [Kind]) -> GoodBadDaysFactorInput {
        var input = GoodBadDaysFactorInput()
        input.meals = kinds.enumerated().flatMap { offset, kind in offset == 22 ? [] : meals(offset, kind) }
        input.logsFatOrProtein = true
        input.insulin = insulin(kinds)
        input.sessions = patches
        input.sensors = sensors
        var loops: [StatsDayKey: HomeLoopStats.Slots] = [:]
        for (offset, kind) in kinds.enumerated() where !(20 ..< 26).contains(offset) {
            loops[StatsDayKey(interval(offset).start, calendar)] = HomeLoopStats.Slots(
                count: 288,
                successes: kind == .high || kind == .lowAndHigh ? 270 : 280
            )
        }
        input.loops = loops
        for (offset, kind) in kinds.enumerated() {
            if let day = GoodBadDaysEngine.score(aggregate(offset, kind), nightTIR: nil, bands: bands, calendar: calendar) {
                input.gri[day.key] = day.gri.value
            }
        }
        return input
    }

    private func row(_ factor: GoodBadFactor, _ rows: [GoodBadDaysFactorRow]) -> GoodBadDaysFactorRow? {
        rows.first { $0.id == factor }
    }

    /// The rows in their fixed order; the values over each third's days with one, the low treatments left out of the
    /// meals, a day without meal entries not logged (not 0 g); a row hidden under 5 days with a value in a group. The
    /// best third: good days 4–13; the worst: the low and high days 20–21, the high days 22–26 (22 without meal
    /// entries), the neither days 27–29.
    func testTheFactorRows() {
        let result = result(month)
        let rows = GoodBadDaysEngine.factors(result, input: factorInput(month), calendar: calendar)
        XCTAssertEqual(rows.map(\.id), GoodBadFactor.allCases)
        XCTAssertEqual(
            GoodBadFactor.allCases.map(\.section).reduce(into: [GoodBadFactor.Section]()) { if $0.last != $1 { $0.append($1) } },
            GoodBadFactor.Section.allCases
        )

        // carbs: 110 g on the best third, 170 g on the 6 high-type days logged and 110 on the 3 others; the one
        // without entries not logged, not 0 g
        let carbs = row(.carbs, rows)
        XCTAssertEqual(carbs?.reference?.median, 110)
        XCTAssertEqual(carbs?.reference?.n, 10)
        XCTAssertEqual(carbs?.compared?.median, 170)
        XCTAssertEqual(carbs?.compared?.p25, 110)
        XCTAssertEqual(carbs?.compared?.n, 9)
        XCTAssertEqual(carbs?.notLogged, 1)
        XCTAssertEqual(row(.largestMeal, rows)?.reference?.median, 60)
        XCTAssertEqual(row(.largestMeal, rows)?.compared?.median, 100)
        XCTAssertEqual(row(.meals, rows)?.reference?.median, 2)
        XCTAssertEqual(row(.meals, rows)?.compared?.median, 3)
        XCTAssertEqual(row(.lastMeal, rows)?.reference?.median, 19 * 60)
        XCTAssertEqual(row(.lastMeal, rows)?.compared?.median, 22 * 60)
        XCTAssertEqual(row(.lateCarbs, rows)?.compared?.median, 30)
        XCTAssertEqual(row(.fatAndProtein, rows)?.reference?.median, 30)
        // the evening before: the one after the day without entries has none
        XCTAssertEqual(row(.lateCarbsEveningBefore, rows)?.reference?.n, 10)
        XCTAssertEqual(row(.lateCarbsEveningBefore, rows)?.compared?.n, 9)
        XCTAssertEqual(row(.lateCarbsEveningBefore, rows)?.compared?.median, 30)
        XCTAssertEqual(row(.lateCarbsEveningBefore, rows)?.notLogged, 1)
        // a day whose only entries are low treatments: no meals, no value
        guard let lowDay = GoodBadDaysEngine.score(aggregate(14, .low), nightTIR: nil, bands: bands, calendar: calendar)
        else { return XCTFail("scored") }
        let treatments = GoodBadDaysEngine.dayValues(
            [lowDay],
            input: GoodBadDaysFactorInput(meals: [
                MealPoint(id: "treatment", actualDate: lowDay.day.start.addingTimeInterval(.hours(2.5)), carbs: 15)
            ]),
            lowTreatments: result.lowTreatmentTimes,
            calendar: calendar
        )[lowDay.key]
        XCTAssertEqual(treatments?.mealsLogged, false)
        XCTAssertNil(treatments?.values[.carbs])

        // a low day's treatments (02:30 in the low, 04:20 within 30 min after it) left out: the low and high days of
        // the worst third have 170 g, as the high days, not 197
        XCTAssertEqual(result.lowTreatmentTimes.count, 8)
        let both = result.thirds.compared.days[0]
        XCTAssertEqual(both.day, interval(20))
        let bothValues = GoodBadDaysEngine.dayValues(
            [both],
            input: factorInput(month),
            lowTreatments: result.lowTreatmentTimes,
            calendar: calendar
        )[both.key]
        XCTAssertEqual(bothValues?.values[.carbs], 170)
        XCTAssertEqual(bothValues?.values[.largestMeal], 100)
        XCTAssertEqual(bothValues?.values[.meals], 3)
        XCTAssertEqual(carbs?.compared?.p75, 170)

        // insulin: 29.5 U with a 5 U bolus, 32.5 U with 8 U
        XCTAssertEqual(row(.totalInsulin, rows)?.reference?.median ?? 0, 29.5, accuracy: 1E-9)
        XCTAssertEqual(row(.totalInsulin, rows)?.compared?.median ?? 0, 32.5, accuracy: 1E-9)
        XCTAssertEqual(row(.bolusShare, rows)?.compared?.median ?? 0, 8 / 32.5, accuracy: 1E-9)
        XCTAssertEqual(row(.smb, rows)?.compared?.median ?? 0, 0.5, accuracy: 1E-9)
        XCTAssertEqual(row(.zeroBasal, rows)?.compared?.median, 0)
        XCTAssertEqual(row(.basalVsScheduled, rows)?.compared?.median ?? 0, 1, accuracy: 1E-9)
        // late or no bolus: the 08:00 bolus is breakfast's, dinner and a high day's late meals have none (the day
        // without entries no value); the low treatments (15 and 12 g, without a bolus) left out
        let lateBolus = row(.lateBolus, rows)
        XCTAssertEqual(lateBolus?.reference?.median ?? 0, 0.5, accuracy: 1E-9)
        XCTAssertEqual(lateBolus?.reference?.n, 10)
        XCTAssertEqual(lateBolus?.compared?.median ?? 0, 2.0 / 3, accuracy: 1E-9)
        XCTAssertEqual(lateBolus?.compared?.n, 9)
        XCTAssertEqual(lateBolus?.notLogged, 0)
        XCTAssertEqual(bothValues?.values[.lateBolus] ?? 0, 2.0 / 3, accuracy: 1E-9)

        // the site: the wear day at noon, a change on every third day
        let siteDay = row(.siteDay, rows)
        XCTAssertEqual(siteDay?.reference?.n, 10)
        XCTAssertEqual(siteDay?.reference?.median, 2)
        let change = row(.siteChange, rows)
        XCTAssertEqual(change?.reference?.n, 10)
        XCTAssertEqual(change?.referenceYes, 3)
        XCTAssertEqual(change?.comparedYes, 3)
        XCTAssertEqual(change?.compared?.n, 10)

        // the CGM sensor: its day at noon, a change on days 2, 12 and 22
        let sensorDay = row(.sensorDay, rows)
        XCTAssertEqual(sensorDay?.reference?.n, 10)
        XCTAssertEqual(sensorDay?.reference?.median, 5.5)
        XCTAssertEqual(sensorDay?.compared?.n, 10)
        XCTAssertEqual(sensorDay?.compared?.median, 5.5)
        let sensorChange = row(.sensorChange, rows)
        XCTAssertEqual(sensorChange?.reference?.n, 10)
        XCTAssertEqual(sensorChange?.referenceYes, 1)
        XCTAssertEqual(sensorChange?.compared?.n, 10)
        XCTAssertEqual(sensorChange?.comparedYes, 1)
        XCTAssertEqual(sensorChange?.unavailable, false)

        // the loop: 4 of the worst third's days with slots: hidden
        XCTAssertNotNil(row(.loopSuccess, rows)?.reference)
        XCTAssertNil(row(.loopSuccess, rows)?.compared)
        XCTAssertFalse(row(.loopSuccess, rows)?.isShown ?? true)
        XCTAssertEqual(row(.cgmCoverage, rows)?.compared?.median, 1)

        // the calendar: the weekend by the locale, the previous day's GRI (0 before the best third's days; before the
        // worst third's 24, 56 × 2, 48 × 5, 32 × 2)
        let weekend = Set(GlucoseStatsEngine.weekend(calendar: calendar, around: start))
        let bestWeekendDays = (4 ..< 14).filter { weekend.contains(calendar.component(.weekday, from: interval($0).start)) }
        XCTAssertEqual(row(.weekend, rows)?.referenceYes, bestWeekendDays.count)
        XCTAssertEqual(row(.previousGRI, rows)?.reference?.n, 10)
        XCTAssertEqual(row(.previousGRI, rows)?.reference?.median, 0)
        XCTAssertEqual(row(.previousGRI, rows)?.compared?.median ?? 0, 48, accuracy: 1E-9)

        // no fat or protein logged: no row; a read that failed: its rows unavailable, the others there
        var input = factorInput(month)
        input.logsFatOrProtein = false
        input.insulin = nil
        let partial = GoodBadDaysEngine.factors(result, input: input, calendar: calendar)
        XCTAssertNil(row(.fatAndProtein, partial))
        for factor in GoodBadFactor.allCases where factor.source == .insulin {
            XCTAssertEqual(row(factor, partial)?.unavailable, true, "\(factor)")
            XCTAssertNil(row(factor, partial)?.reference)
        }
        XCTAssertEqual(row(.carbs, partial)?.unavailable, false)

        // thirds of 4 (13 days scored): no rows
        let thirteen = Array(repeating: Kind.good, count: 13) + [.uncovered]
        XCTAssertEqual(
            GoodBadDaysEngine
                .factors(self.result(thirteen, period: .days14), input: factorInput(thirteen), calendar: calendar),
            []
        )
    }

    /// A day's meals: entries within 30 min of a meal's first are that meal, the meals of 5 g or more count, the late
    /// carbs from 21:00 by the clock; none without an entry.
    func testADaysMeals() {
        let entries = [
            MealPoint(id: "a", actualDate: clock(0, 7, 0), carbs: 30),
            MealPoint(id: "b", actualDate: clock(0, 7, 30), carbs: 10),
            MealPoint(id: "c", actualDate: clock(0, 7, 31), carbs: 3),
            MealPoint(id: "d", actualDate: clock(0, 20, 59), carbs: 20, protein: 15),
            MealPoint(id: "e", actualDate: clock(0, 21, 0), carbs: 4)
        ]
        let facts = GoodBadDaysEngine.mealFacts(entries, in: interval(0), calendar: calendar)
        XCTAssertEqual(facts?.carbs, 67)
        // 07:00 + 07:30 (30 min after its first) = 40 g; 07:31 a meal of 3 g; 20:59 with 21:00: 24 g
        XCTAssertEqual(facts?.largest, 40)
        XCTAssertEqual(facts?.count, 2)
        XCTAssertEqual(facts?.lastStart, 20 * 60 + 59)
        XCTAssertEqual(facts?.late, 4)
        XCTAssertEqual(facts?.fatAndProtein, 15)
        // the meals of 10 g or more, for the bolus
        XCTAssertEqual(facts?.bolusMealStarts, [clock(0, 7, 0), clock(0, 20, 59)])
        XCTAssertNil(GoodBadDaysEngine.mealFacts(entries, in: interval(1), calendar: calendar))
    }

    /// A day's late or no bolus from the insulin days as the cache keeps them: a pre-bolus on time, an SMB at a meal's
    /// start no bolus, a meal under 10 g not counted; the day before's bolus counts for a meal after midnight; a day
    /// without a meal of 10 g, or with pump data for under half of it, has no value.
    func testADaysLateOrNoBolus() {
        let days = (-1 ... 2).map { interval($0) }
        let events = [
            // the day before, 23:50: a pre-bolus for 00:10
            PumpEventRecord(date: clock(-1, 23, 50), kind: .bolus, source: .pump, units: 2, isSMB: false),
            // day 0: 07:45 a pre-bolus for 08:00; 19:00 an SMB, then a bolus at 19:40
            PumpEventRecord(date: clock(0, 7, 45), kind: .bolus, source: .pump, units: 4, isSMB: false),
            PumpEventRecord(date: clock(0, 19), kind: .bolus, source: .pump, units: 0.5, isSMB: true),
            PumpEventRecord(date: clock(0, 19, 40), kind: .bolus, source: .pump, units: 3, isSMB: false),
            // day 2, pump data for 6 h only: on time, but no value
            PumpEventRecord(date: clock(2, 8), kind: .bolus, source: .pump, units: 4, isSMB: false)
        ]
        let insulin = InsulinStatsEngine.days(
            days,
            input: InsulinInput(
                events: events,
                coverage: days.dropLast().map { CoveredInterval(interval: $0, source: .pump) }
                    + [CoveredInterval(interval: DateInterval(start: interval(2).start, duration: .hours(6)), source: .pump)],
                schedules: [BasalScheduleRecordValue(
                    date: interval(-400).start,
                    source: .local,
                    entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
                )]
            ),
            now: clock(10, 12),
            calendar: calendar
        )
        // the cache's past days: the SMB isn't kept
        XCTAssertEqual(insulin[1].boluses.map(\.date), [clock(0, 7, 45), clock(0, 19, 40)])

        func entry(_ offset: Int, _ hour: Int, _ minute: Int, _ carbs: Double) -> MealPoint {
            MealPoint(id: "\(offset)-\(hour)-\(minute)", actualDate: clock(offset, hour, minute), carbs: carbs)
        }
        var input = GoodBadDaysFactorInput()
        input.meals = [
            entry(0, 0, 10, 20), entry(0, 8, 0, 40), entry(0, 13, 0, 9), entry(0, 19, 0, 60),
            entry(1, 12, 0, 9),
            entry(2, 8, 0, 40)
        ]
        input.insulin = insulin
        let scored = (0 ... 2).compactMap {
            GoodBadDaysEngine.score(aggregate($0, .good), nightTIR: nil, bands: bands, calendar: calendar)
        }
        let values = GoodBadDaysEngine.dayValues(scored, input: input, lowTreatments: [], calendar: calendar)
        // 00:10 and 08:00 on time, 19:00 late (the SMB isn't a bolus), 13:00 under 10 g
        XCTAssertEqual(values[scored[0].key]?.values[.lateBolus] ?? -1, 1.0 / 3, accuracy: 1E-9)
        XCTAssertNil(values[scored[1].key]?.values[.lateBolus])
        XCTAssertNil(values[scored[2].key]?.values[.lateBolus])
        // without the meals, no value (the meals' section says they couldn't be read)
        input.meals = nil
        XCTAssertNil(
            GoodBadDaysEngine.dayValues(scored, input: input, lowTreatments: [], calendar: calendar)[scored[0].key]?
                .values[.lateBolus]
        )
    }

    /// The rows as shown: both medians with their IQR and n, the days not logged, the difference as a direction; the
    /// sections in their order with the loop rows' note, a section whose read failed says so.
    @MainActor func testTheFactorRowsFormatted() {
        let result = result(month)
        let data = Stat.GoodBadDaysData(
            period: .days30,
            result: result,
            factors: GoodBadDaysEngine.factors(result, input: factorInput(month), calendar: calendar),
            sensorsRecordedFrom: interval(0).start
        )
        let model = Stat.GoodBadDays(data, settings: settings, now: clock(30, 12), calendar: calendar)
        let content = model.content
        XCTAssertEqual(content.factorSections.map(\.id), GoodBadFactor.Section.allCases)
        XCTAssertEqual(
            content.factorIntro,
            "Each row: both groups’ median and middle half, then how the worst third differs from the best third. A row needs 5 days with a value in each group."
        )
        let meals = content.factorSections[0]
        XCTAssertEqual(meals.title, "Meals")
        XCTAssertEqual(
            meals.note,
            "Low treatments are left out: carb entries made during a low (below 70 mg/dL), or within 30 min after it ends."
        )
        let carbs = meals.rows[0]
        XCTAssertEqual(carbs.name, "Carbs")
        XCTAssertEqual(carbs.values, "Best 110 g (110–110) · Worst 170 g (110–170) · n 10 / 9 · no meals logged on 1 day")
        XCTAssertEqual(carbs.difference, "+60 g")
        XCTAssertEqual(carbs.direction, "more")
        let last = meals.rows.first { $0.id == .lastMeal }
        XCTAssertEqual(last?.difference, "+" + StatsFormatting.duration(minutes: 180))
        XCTAssertEqual(last?.direction, "later")
        XCTAssertEqual(meals.rows.first { $0.id == .lateCarbs }?.note, "Entries from \(Stat.AGP.clockTime(21 * 60)) to midnight.")

        let insulin = content.factorSections[1]
        XCTAssertEqual(insulin.rows.first { $0.id == .totalInsulin }?.difference, d("+3.0 U"))
        XCTAssertEqual(insulin.rows.first { $0.id == .bolusShare }?.difference, "+8 pt")
        let lateBolus = insulin.rows.first { $0.id == .lateBolus }
        XCTAssertEqual(lateBolus?.name, "Meals with a late or no bolus")
        XCTAssertEqual(lateBolus?.difference, "+17 pt")
        XCTAssertEqual(lateBolus?.direction, "more")
        XCTAssertEqual(
            lateBolus?.note,
            "Meals of 10 g or more with no bolus by 15 min after the start. Moderately reliable: a meal entered at bolus time hides a late bolus."
        )
        let loop = content.factorSections[2]
        XCTAssertEqual(loop.title, "What you and the loop did")
        XCTAssertEqual(loop.note, "These follow glucose: a bad day brings more corrections and more time at zero basal.")
        XCTAssertEqual(loop.rows.first { $0.id == .zeroBasal }?.direction, "the same")
        let site = content.factorSections[3]
        XCTAssertEqual(site.rows.first { $0.id == .siteChange }?.values, "Best 3 of 10 days · Worst 3 of 10 days")
        XCTAssertEqual(site.rows.first { $0.id == .siteChange }?.difference, "±0 pt")
        XCTAssertEqual(site.rows.first { $0.id == .siteChange }?.direction, "the same")
        let sensor = content.factorSections[4]
        XCTAssertEqual(sensor.title, "CGM sensor")
        XCTAssertEqual(sensor.rows.map(\.id), [.sensorDay, .sensorChange])
        XCTAssertEqual(sensor.rows[0].name, "Sensor day")
        XCTAssertEqual(sensor.rows[0].direction, "the same")
        XCTAssertEqual(
            sensor.rows[0].note,
            "At noon; sensors started before \(CGMFormat.day(interval(0).start)) weren’t recorded."
        )
        XCTAssertEqual(sensor.rows[1].name, "Sensor change that day")
        XCTAssertEqual(sensor.rows[1].values, "Best 1 of 10 days · Worst 1 of 10 days")
        XCTAssertEqual(sensor.rows[1].direction, "the same")
        // the loop row hidden (4 of the worst third's days), the coverage shown
        XCTAssertEqual(content.factorSections[5].rows.map(\.id), [.cgmCoverage])

        // a failed read: the section says so, without rows
        var input = factorInput(month)
        input.insulin = nil
        let failed = Stat.GoodBadDays(
            Stat.GoodBadDaysData(
                period: .days30,
                result: result,
                factors: GoodBadDaysEngine.factors(result, input: input, calendar: calendar)
            ),
            settings: settings,
            now: clock(30, 12),
            calendar: calendar
        ).content
        let failedInsulin = failed.factorSections.first { $0.id == .insulin }
        XCTAssertEqual(failedInsulin?.unavailable, "The pump data couldn't be read.")
        XCTAssertEqual(failedInsulin?.rows, [])
        // thirds of 4: no factors
        XCTAssertEqual(
            self.model(Array(repeating: .good, count: 13) + [.uncovered], period: .days14).content.factorSections,
            []
        )
    }

    /// The sensors of the effective sessions, merged as the CGM topic merges them (a CGM switched away and back is the
    /// same sensor: its days go on, the return no change), each with its own start: a sensor running when the recording
    /// began has its wear day, a switch to a sensor started the evening before counts from then and is no change (the
    /// change is on the day it started), an entered session's sensor counts as a recorded one's. A day with a session
    /// of a sensor not identified (no sensor start: a sensorless CGM, an entered or backfilled session without one), or
    /// without a session (Unknown), has neither value.
    func testTheSensorRowsFromTheSessions() {
        func session(
            _ cgmId: String,
            start: Date,
            end: Date?,
            sensorStart: Date?,
            source: CGMSessionSource = .recorded,
            id: Int
        ) -> CGMSessionRecord {
            CGMSessionRecord(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", id))!,
                start: start,
                end: end,
                CGMSnapshot(plugin: cgmId, cgmId: cgmId, name: cgmId, sensorStart: sensorStart, oneMinute: false, sensorId: nil),
                source: source
            )
        }
        let sessions = [
            // the recording began on day 0 at 08:00, the sensor running since day -3 09:00
            session("dexcomG7", start: clock(0, 8), end: clock(4, 10), sensorStart: clock(-3, 9), id: 1),
            // a new sensor on day 4 at 10:00, switched away on day 8 at 09:00 to a Libre started on day 7 at 20:00, and
            // back a day later, to day 12
            session("dexcomG7", start: clock(4, 10), end: clock(8, 9), sensorStart: clock(4, 10), id: 2),
            session("libre3", start: clock(8, 9), end: clock(9, 9), sensorStart: clock(7, 20), id: 3),
            session("dexcomG7", start: clock(9, 9), end: interval(12).start, sensorStart: clock(4, 10), id: 4),
            // days 12 and 13 Unknown; then an entered session with its sensor's start
            session(
                "dexcomG7",
                start: interval(14).start,
                end: interval(16).start,
                sensorStart: interval(14).start,
                source: .entered,
                id: 5
            ),
            // a sensorless CGM to day 17 at 06:00, then a new sensor
            session("nightscout", start: interval(16).start, end: clock(17, 6), sensorStart: nil, id: 6),
            session("dexcomG7", start: clock(17, 6), end: nil, sensorStart: clock(17, 6), id: 7)
        ]
        let sensors = Stat.Provider.goodBadDaysSensors(sessions)
        XCTAssertEqual(
            sensors.map(\.start),
            [clock(-3, 9), clock(4, 10), clock(7, 20), interval(14).start, nil, clock(17, 6)]
        )
        XCTAssertEqual(sensors[1].sessions.count, 2)

        var input = GoodBadDaysFactorInput()
        input.sensors = sensors
        let scored = (0 ... 18).compactMap {
            GoodBadDaysEngine.score(aggregate($0, .good), nightTIR: nil, bands: bands, calendar: calendar)
        }
        let values = GoodBadDaysEngine.dayValues(scored, input: input, lowTreatments: [], calendar: calendar)
        func value(_ factor: GoodBadFactor, _ offset: Int) -> Double? {
            values[scored[offset].key]?.values[factor]
        }
        let expected: [(offset: Int, day: Double?, change: Double?)] = [
            // day -3 09:00 to day 0 12:00: 3 d 3 h, the 4th day
            (0, 4, 0), (3, 7, 0), (4, 1, 1),
            // the Libre started on day 7 (a change then); on day 8 at noon its first day, and no change
            (7, 4, 1), (8, 1, 0),
            (9, 6, 0), (10, 7, 0), (11, 8, 0),
            (12, nil, nil), (13, nil, nil), (14, 1, 1), (15, 2, 0),
            // the sensorless CGM's days, and the day it ends with a new sensor: neither
            (16, nil, nil), (17, nil, nil), (18, 2, 0)
        ]
        for (offset, day, change) in expected {
            XCTAssertEqual(value(.sensorDay, offset), day, "sensor day \(offset)")
            XCTAssertEqual(value(.sensorChange, offset), change, "change \(offset)")
        }
    }

    /// A Libre the old rule split at its jumps after short dropouts, entered as three sessions with inferred starts:
    /// read as the CGM topic reads them (`CGMUnknownInference.joinedEntered`), one sensor whose wear days go on across
    /// the joined boundaries, a change only on the day it started.
    func testTheSensorDayGoesOnAcrossJoinedEnteredSessions() {
        let starts = [clock(0, 8), clock(2, 9), clock(3, 15)]
        let end = clock(10, 0)
        var points: [GlucosePoint] = []
        for (index, from) in starts.enumerated() {
            // 3 minutes missing before the next part, its level 40 mg/dL up
            let to = index + 1 < starts.count ? starts[index + 1].addingTimeInterval(-.minutes(3)) : end
            for time in stride(from: from.timeIntervalSince1970, to: to.timeIntervalSince1970, by: 60) {
                points.append(GlucosePoint(time: Date(timeIntervalSince1970: time), mgdl: Int16(120 + 40 * (index % 2))))
            }
        }
        let sessions = starts.enumerated().map { index, from in
            CGMSessionRecord(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", index + 1))!,
                start: from,
                end: index + 1 < starts.count ? starts[index + 1] : points.last!.time.addingTimeInterval(1),
                CGMSnapshot(
                    plugin: "LibreLoopCGMManager",
                    cgmId: "libre3",
                    name: "Libre 3",
                    sensorStart: from,
                    expectedLife: .days(14),
                    oneMinute: true,
                    sensorId: nil
                ),
                source: .entered
            )
        }
        let sensors = Stat.Provider.goodBadDaysSensors(CGMUnknownInference.joinedEntered(sessions, readings: points))
        XCTAssertEqual(sensors.map(\.start), [clock(0, 8)])

        var input = GoodBadDaysFactorInput()
        input.sensors = sensors
        let scored = (0 ... 9).compactMap {
            GoodBadDaysEngine.score(aggregate($0, .good), nightTIR: nil, bands: bands, calendar: calendar)
        }
        let values = GoodBadDaysEngine.dayValues(scored, input: input, lowTreatments: [], calendar: calendar)
        let days: [Double?] = (1 ... 10).map { Double($0) }
        let changes: [Double?] = [1] + Array(repeating: 0, count: 9)
        XCTAssertEqual(scored.map { values[$0.key]?.values[.sensorDay] }, days)
        XCTAssertEqual(scored.map { values[$0.key]?.values[.sensorChange] }, changes)
    }

    // MARK: - The state model, driven

    /// An empty display preferences store of its own, removed after the test
    private func displayPreferences() -> StatsDisplayPreferences {
        StatsDisplayPreferences(defaults: temporaryDefaults("test-good-bad-days-display"))
    }

    /// A `UserDefaults` suite of its own, removed after the test
    private func temporaryDefaults(_ prefix: String) -> UserDefaults {
        let name = "\(prefix)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// The screen's state model on fakes (no readings, no pump data, no Nightscout), on Good & bad days.
    @MainActor private func stateModel(displayPreferences: StatsDisplayPreferences? = nil) -> Stat.StateModel {
        let coordinator = AppCoordinator()
        let container = Container()
        container.register(Router.self) { resolver in BaseRouter(resolver: resolver) }
        container.register(SettingsManager.self) { _ in NoSettings() }
        container.register(AppCoordinator.self) { _ in coordinator }
        let statistics = GlucoseStatistics(appCoordinator: coordinator, source: Readings(points: []))
        container.register(GlucoseStatistics.self) { _ in statistics }
        let insulin = InsulinStatsService(appCoordinator: coordinator, source: NoInsulin())
        container.register(InsulinStatsService.self) { _ in insulin }
        let sessions = CGMSessionStore(
            container: StatsFixtures.inMemoryContainer(),
            defaults: temporaryDefaults("test-good-bad-days")
        )
        container.register(CGMSessionStore.self) { _ in sessions }
        container.register(NightscoutManager.self) { _ in NoNightscout() }
        let loops = HomeLoopsStore(source: Loops(readings: [], records: []))
        container.register(HomeLoopsStore.self) { _ in loops }
        return Stat.StateModel(
            resolver: container,
            period: .days7,
            tab: .goodBadDays,
            displayPreferences: displayPreferences ?? self.displayPreferences()
        )
    }

    /// Until what is shown isn't loading (the first refresh, from `subscribe`, comes a turn later).
    @MainActor private func settled(_ model: Stat.StateModel, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 500 {
            if !model.glucoseContent.isLoading {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("still loading", file: file, line: line)
    }

    /// The Day tab's usual day: shown and its baseline as the phone keeps them (`StatsDisplayPreferences`), not the
    /// settings; a change written through, a period it doesn't offer ignored.
    @MainActor func testTheUsualDayPicksAreKeptOnThePhone() async {
        let preferences = displayPreferences()
        preferences.usualDayShown = true
        preferences.usualDayPeriod = .days30
        let model = stateModel(displayPreferences: preferences)
        XCTAssertTrue(model.usualDayShown)
        XCTAssertEqual(model.usualDayPeriod, .days30)
        await settled(model)

        model.select(usualDayPeriod: .days90)
        XCTAssertEqual(model.usualDayPeriod, .days90)
        XCTAssertEqual(preferences.usualDayPeriod, .days90)
        model.select(usualDayPeriod: .days7)
        XCTAssertEqual(model.usualDayPeriod, .days90)
        XCTAssertEqual(preferences.usualDayPeriod, .days90)
        model.showUsualDay(false)
        XCTAssertFalse(model.usualDayShown)
        XCTAssertFalse(preferences.usualDayShown)

        // the next opening
        let next = stateModel(displayPreferences: StatsDisplayPreferences(defaults: preferences.defaults))
        XCTAssertFalse(next.usualDayShown)
        XCTAssertEqual(next.usualDayPeriod, .days90)
        // nothing stored: off, 14 days
        let fresh = stateModel()
        XCTAssertFalse(fresh.usualDayShown)
        XCTAssertEqual(fresh.usualDayPeriod, .days14)
    }

    /// A period picked: its own, the preferred one left as it is, the time back to the main stretch, one refresh. A day
    /// opened: the Day tab on that day with one refresh. The menu back: the period, the time and the open list as they
    /// were.
    @MainActor func testOpeningADayAndComingBack() async {
        let model = stateModel()
        await settled(model)
        XCTAssertEqual(model.tab, .goodBadDays)
        XCTAssertEqual(model.period, .days30)
        XCTAssertEqual(model.goodBadDaysPeriod, .days30)
        XCTAssertEqual(model.preferredPeriod, .days7)

        let selection = model.goodBadDaysSelection
        selection.toggle(.compared)
        selection.select(bin: 10)
        var refreshes = model.refreshCount
        model.select(period: .days90)
        XCTAssertEqual(model.goodBadDaysPeriod, .days90)
        XCTAssertEqual(model.period, .days90)
        XCTAssertEqual(model.preferredPeriod, .days7)
        XCTAssertNil(selection.bin)
        XCTAssertEqual(selection.open, [.compared])
        XCTAssertEqual(model.refreshCount, refreshes + 1)
        await settled(model)

        selection.select(bin: 20)
        refreshes = model.refreshCount
        let today = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.date(byAdding: .day, value: -3, to: today)!
        model.openDay(day.addingTimeInterval(.hours(5)))
        XCTAssertEqual(model.tab, .trace)
        XCTAssertEqual(model.traceDay, .day(day))
        XCTAssertEqual(model.traceShownDay, .day(day))
        XCTAssertEqual(model.refreshCount, refreshes + 1)
        await settled(model)
        XCTAssertEqual(model.refreshCount, refreshes + 1)
        XCTAssertEqual(model.preferredPeriod, .days7)

        model.select(tab: .goodBadDays)
        XCTAssertEqual(model.tab, .goodBadDays)
        XCTAssertEqual(model.refreshCount, refreshes + 2)
        XCTAssertEqual(model.period, .days90)
        XCTAssertEqual(selection.open, [.compared])
        XCTAssertEqual(selection.bin, 20)
        await settled(model)
    }

    // MARK: - The loop days

    /// The loop store's days of a window: its whole days only (read up to `now`, the part of today and a day the window
    /// starts inside left out); nil when a read fails.
    func testTheLoopDaysOfAWindow() async {
        let now = clock(3, 12)
        let readings = stride(from: interval(0).start.timeIntervalSince1970, to: now.timeIntervalSince1970, by: 300)
            .map { Date(timeIntervalSince1970: $0) }
        let records = readings.map { HomeLoopStats.Record(start: $0.addingTimeInterval(30), success: true) }
        let store = HomeLoopsStore(source: Loops(readings: readings, records: records))
        let window = DateInterval(start: interval(0).start, end: interval(2).end)
        let days = await store.days(of: window, now: now, allowOneMinuteLoop: false, calendar: calendar)
        XCTAssertEqual(days?.map(\.day), [interval(0), interval(1), interval(2)])
        XCTAssertEqual(days?.map(\.interval), [interval(0), interval(1), interval(2)])
        // every day's slots, its loops in them (successes count slots too)
        XCTAssertTrue(days?.allSatisfy { $0.slots.successes > 0 } ?? false)

        let fromNoon = await store.days(
            of: DateInterval(start: clock(0, 12), end: interval(2).end),
            now: now,
            allowOneMinuteLoop: false,
            calendar: calendar
        )
        XCTAssertEqual(fromNoon?.map(\.day), [interval(1), interval(2)])

        let failing = HomeLoopsStore(source: Loops(readings: readings, records: records, fails: true))
        let none = await failing.days(of: window, now: now, allowOneMinuteLoop: false, calendar: calendar)
        XCTAssertNil(none)
    }

    // MARK: - 90 days

    /// What 90 days cost after the reads: the scores, the thirds, their profiles and the night TIRs from 26k
    /// readings (cold: read, cleaned and the days aggregated; warm: held and cached), then the factors. Logged.
    func testNinetyDaysTime() async {
        let now = clock(92, 12)
        let points = stride(from: interval(0).start.timeIntervalSince1970, to: now.timeIntervalSince1970, by: 300)
            .enumerated()
            .map { index, seconds -> GlucosePoint in
                let day = index / 288
                let phase = Double(index % 288) / 288 * 2 * .pi
                var mgdl = 130 + 50 * sin(phase)
                if day % 5 == 0 { mgdl += 90 }
                if day % 7 == 0 { mgdl -= 75 }
                return GlucosePoint(time: Date(timeIntervalSince1970: seconds), mgdl: Int16(Swift.min(Swift.max(mgdl, 40), 400)))
            }
        let calendar = self.calendar
        let statistics = GlucoseStatistics(
            appCoordinator: AppCoordinator(),
            source: Readings(points: points),
            calendar: { calendar },
            now: { now }
        )
        await statistics.beginSession()
        let clock = ContinuousClock()
        func milliseconds(_ duration: Duration) -> Int {
            Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1E15).rounded())
        }

        var started = clock.now
        let glucose = await statistics.goodBadDays(count: 90, bands: bands, now: now)
        let cold = clock.now - started
        started = clock.now
        _ = await statistics.goodBadDays(count: 90, bands: bands, now: now)
        let warm = clock.now - started
        started = clock.now
        var input = GoodBadDaysFactorInput(meals: (0 ..< 92).flatMap { meals($0, .good) })
        input.gri = glucose.gri
        let factors = GoodBadDaysEngine.factors(glucose.result, input: input, calendar: calendar)
        let factorTime = clock.now - started
        print(
            "Good & bad days, 90 d (simulator, debug): cold \(milliseconds(cold)) ms, warm \(milliseconds(warm)) ms, "
                + "factors \(milliseconds(factorTime)) ms"
        )
        await statistics.endSession()

        XCTAssertEqual(glucose.result.scored, 90)
        XCTAssertTrue(glucose.result.thirds.isComparable)
        XCTAssertEqual(factors.count, GoodBadFactor.allCases.count - 1)
    }

    // MARK: - The GRI sheet

    /// The doc's strings, the standard levels in the user's units, the Statistics range named.
    @MainActor func testTheGRISheetInBothUnits() {
        let mgdl = GRIInfoSheet.Content(bands: bands, units: .mgdL)
        XCTAssertEqual(mgdl.title, "Glycemia Risk Index (GRI)")
        XCTAssertEqual(mgdl.lead, "GRI sums up a day’s glucose in one number from 0 to 100. Lower is better.")
        XCTAssertEqual(mgdl.sections[2].paragraphs, [
            "Very low: below 54 mg/dL",
            "Low: 54–69 mg/dL",
            "High: 181–250 mg/dL",
            "Very high: above 250 mg/dL"
        ])
        XCTAssertEqual(mgdl.sections[4].zones.map(\.id), ["A", "B", "C", "D", "E"])
        XCTAssertEqual(mgdl.sections[4].zones.map(\.range), ["0–20", "21–40", "41–60", "61–80", "81–100"])
        XCTAssertEqual(
            mgdl.sections[4].notes,
            ["Zones: A 0–20 · B 21–40 · C 41–60 · D 61–80 · E 81–100. Zone A is the lowest risk."]
        )
        // the zones as the engine has them: 20 is A, 21 B
        XCTAssertEqual(GlucoseStatsEngine.griZone(20), .a)
        XCTAssertEqual(GlucoseStatsEngine.griZone(21), .b)
        XCTAssertTrue(mgdl.sections[5].notes[0].contains("(70–180 mg/dL)"))

        let mmolBands = StatsBands(low: 72, high: 162, units: .mmolL)
        let mmol = GRIInfoSheet.Content(bands: mmolBands, units: .mmolL)
        XCTAssertEqual(mmol.sections[2].paragraphs, [
            d("Very low: below 3.0 mmol/L"),
            // the engine's edges: 54–69 and 182–250 (the mmol TIR range ends at 181)
            d("Low: 3.0–3.8 mmol/L"),
            d("High: 10.1–13.9 mmol/L"),
            d("Very high: above 13.9 mmol/L")
        ])
        XCTAssertTrue(mmol.sections[5].notes[0].contains(d("(4.0–9.0 mmol/L)")), mmol.sections[5].notes[0])
        XCTAssertEqual(
            mmol.sections[5].notes[0],
            String(
                format: "GRI always uses these standard ranges, not your Statistics range (%@). Changing your range doesn’t change a day’s GRI or its group.",
                d("4.0–9.0 mmol/L")
            )
        )
    }
}

// MARK: - Fakes

/// The readings given.
private struct Readings: GlucosePointSource {
    let points: [GlucosePoint]

    func fetchGlucosePoints(from: Date, to: Date) async throws -> [GlucosePoint] {
        points.filter { $0.time >= from && $0.time < to }
    }
}

/// No pump data.
private struct NoInsulin: InsulinDataSource {
    func fetchPumpEvents(from _: Date, to _: Date) async throws -> [PumpEventRecord] { [] }
    func fetchPumpEventsRunningInto(_: Date) async throws -> [PumpEventRecord] { [] }
    func fetchCoverage(from _: Date, to _: Date) async throws -> [CoveredInterval] { [] }
    func fetchBasalSchedules(from _: Date, to _: Date) async throws -> [BasalScheduleRecordValue] { [] }
    func fetchIOBPoints(from _: Date, to _: Date) async throws -> [IOBPoint] { [] }
}

/// The loop records and readings given; every read throws with `fails`.
private struct Loops: HomeLoopsSource {
    struct Failure: Error {}

    let readings: [Date]
    let records: [HomeLoopStats.Record]
    var fails = false

    private func check() throws {
        if fails {
            throw Failure()
        }
    }

    func loopRecords(in range: DateInterval, throughEnd: Bool) async throws -> [HomeLoopStats.Record] {
        try check()
        return records.filter { $0.start >= range.start && (throughEnd ? $0.start <= range.end : $0.start < range.end) }
    }

    func loopRecordCount(in range: DateInterval) async throws -> Int {
        try check()
        return records.filter { $0.start >= range.start && $0.start < range.end }.count
    }

    func lastLoopStart(before date: Date) async throws -> Date? {
        try check()
        return records.last { $0.start < date }?.start
    }

    func readingTimes(in range: DateInterval) async throws -> [Date] {
        try check()
        return readings.filter { $0 >= range.start && $0 < range.end }
    }
}

/// The default settings, nothing saved.
private final class NoSettings: SettingsManager, @unchecked Sendable {
    var settings: FreeAPSSettings { get async { FreeAPSSettings() } }
    var preferences: Preferences { get async { Preferences() } }
    var pumpSettings: PumpSettings { get async { PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2) } }

    func updateInsulinCurve(_: InsulinType?) async {}
    func updateSettings(_: FreeAPSSettings) async {}
    func updateSettings(_ update: @Sendable(FreeAPSSettings) -> FreeAPSSettings) async -> FreeAPSSettings {
        update(FreeAPSSettings())
    }

    func updatePumpSettings(_: PumpSettings) async {}
    func updatePreferences(_: Preferences) async {}
    func saveRawSettings(_: RawJSON) async throws {}
    func saveRawPreferences(_: RawJSON) async throws {}
    func saveRawPumpSettings(_: RawJSON) async throws {}
}

/// Nightscout not configured.
private struct NoNightscout: NightscoutManager {
    func isConfigured() async -> Bool { false }
    func fetchGlucose(since _: Date) async -> AsyncStream<FetchGlucoseProgress> { AsyncStream { $0.finish() } }
    func fetchCarbs() async -> [CarbsEntry] { [] }
    func fetchTempTargets() async -> [TempTarget] { [] }
    func fetchAnnouncements() async -> [Announcement] { [] }
    func uploadOldGlucose(bloodGlucose _: [BloodGlucose]) async -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func uploadProfileAndSettings(profile _: NightscoutProfileStore?, force _: Bool) async {}
    func uploadOverride(_: String, _: Double, _: Date) async {}
    func deleteOverride(at _: Date) async {}
    func deleteAnnouncements() async {}
    func deleteAllNSoverrrides() async {}
    func fetchProfile() async throws -> [FetchedNightscoutProfileStore] { [] }
    func fetchInsulin(since _: Date) async -> AsyncStream<FetchInsulinProgress> { AsyncStream { $0.finish() } }
    func cgmBackfillSource() async -> NightscoutCGMBackfillSource? { nil }
}
