@testable import FreeAPS
import PDFKit
import XCTest

/// The PDF reports' Patches, CGM and Settings parts: the settings' snapshot and its sums and units, the page models, the
/// pages' plan, the empty and unread states, the reads and the written file.
final class StatsReportDevicesSettingsTests: XCTestCase {
    private static let calendar = StatsFixtures.berlin

    /// 2026-10-16 12:00 Europe/Berlin: the 7 days are 10–16 Oct
    private static let now = StatsFixtures.week.addingTimeInterval(.days(6) + .hours(12))

    // MARK: - Fixtures

    private static func day(_ offset: Double) -> Date {
        StatsFixtures.week.addingTimeInterval(.days(offset))
    }

    /// A number as the locale writes it.
    private func d(_ text: String) -> String {
        text.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    // Patches

    private static let flatSchedule = BasalScheduleRecordValue(
        date: day(-400),
        source: .local,
        entries: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
    )

    /// A pump session `[activation, to]`, closed at its end; the id by its start.
    private static func patchRecord(_ plugin: String, activation: Date, to end: Date) -> PumpSessionValue {
        let seconds = Int64(activation.timeIntervalSince1970)
        return PumpSessionValue(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012lld", seconds))!,
            source: .pump,
            plugin: plugin,
            activation: activation,
            start: activation,
            localStart: activation,
            lastSeen: end,
            end: end,
            flags: PumpSessionRules.isPodOrPatch(plugin) ? [] : .site
        )
    }

    /// Patches of 72 h, 80 h apart, covered throughout, the last one ending two days before `now`.
    private static func patchRows(count: Int, plugin: String = "Medtrum") -> [PumpSessionValue] {
        let start = now.addingTimeInterval(-.days(2) - .hours(80 * Double(count)))
        return (0 ..< count).map { index in
            let activation = start.addingTimeInterval(.hours(80 * Double(index)))
            return patchRecord(plugin, activation: activation, to: activation.addingTimeInterval(.hours(72)))
        }
    }

    /// Every session of the rows, none in use, on the standard bands.
    private static func patches(
        _ rows: [PumpSessionValue],
        period: StatsPeriod = .days30,
        glucose: [GlucosePoint] = []
    ) -> Stat.PatchesResult {
        let sessions = PatchStatsEngine.sessions(rows)
        let stats = PatchStatsEngine.stats(
            sessions,
            input: PatchInput(
                insulin: InsulinInput(coverage: StatsFixtures.covered(rows), schedules: [flatSchedule]),
                glucose: glucose
            ),
            bands: Stat.ReportBuilder.standardBands(.mgdL),
            allowOneMinuteLoop: false,
            inUseID: nil,
            now: now,
            calendar: calendar
        )
        return Stat.PatchesResult(
            period: period,
            window: GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar),
            asOf: now,
            topic: PatchStatsEngine.topic(sessions, currentPlugin: nil),
            sessions: stats,
            inUse: nil,
            previous: [],
            scaleWear: PatchStatsEngine.scaleWear(sessions),
            recordingStart: sessions.map(\.dataStart).min()
        )
    }

    // CGM

    private static let window = DateInterval(start: StatsFixtures.week, end: now)

    /// A reading every 5 minutes in `[from, to)`: a slow wave, a little deterministic noise.
    private static func readings(from: Date, to: Date) -> [GlucosePoint] {
        stride(from: from.timeIntervalSince1970, to: to.timeIntervalSince1970, by: 300).enumerated().map { index, seconds in
            let wave = 40 * sin(Double(index) / 30)
            let noise = Double((index * 37) % 7) - 3
            return GlucosePoint(time: Date(timeIntervalSince1970: seconds), mgdl: Int16(130 + wave + noise))
        }
    }

    private static func session(
        _ cgmId: String,
        name: String,
        start: Date,
        end: Date?,
        life: TimeInterval,
        id: Int
    ) -> CGMSessionRecord {
        CGMSessionRecord(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", id))!,
            start: start,
            end: end,
            CGMSnapshot(
                plugin: cgmId,
                cgmId: cgmId,
                name: name,
                sensorStart: start,
                expectedLife: life,
                oneMinute: false,
                sensorId: nil
            )
        )
    }

    private static func cgm(_ readings: [GlucosePoint], _ sessions: [CGMSessionRecord]) -> Stat.CGMResult {
        Stat.Provider.cgmResult(
            readings: readings,
            sessions: sessions,
            period: .days7,
            window: window,
            generation: 0,
            now: now,
            calendar: calendar
        )
    }

    /// Unknown on the first day, a Dexcom G7 for three, a Libre 3 since.
    private static var twoCGMs: Stat.CGMResult {
        cgm(
            readings(from: window.start, to: now),
            [
                session("dexcomG7", name: "Dexcom G7", start: day(1), end: day(4), life: .days(10.5), id: 1),
                session("libre3", name: "Libre 3", start: day(4), end: nil, life: .days(14), id: 2)
            ]
        )
    }

    // Settings

    private static var snapshot: ReportSettingsSnapshot {
        var preferences = Preferences()
        preferences.maxIOB = 8.5
        preferences.maxSMBBasalMinutes = 90
        preferences.maxUAMSMBBasalMinutes = 120
        preferences.smbDeliveryRatio = 0.65
        var settings = FreeAPSSettings()
        settings.autoisf = true
        settings.autoisf_min = 0.7
        settings.autoisf_max = 1.4
        settings.iobThresholdPercent = 80
        return ReportSettingsSnapshot(
            basal: [
                BasalProfileEntry(start: "22:00:00", minutes: 1320, rate: 0.6),
                BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.8),
                BasalProfileEntry(start: "06:00:00", minutes: 360, rate: 1)
            ],
            sensitivities: InsulinSensitivities(
                units: .mmolL,
                userPreferredUnits: .mmolL,
                sensitivities: [
                    InsulinSensitivityEntry(sensitivity: 2.5, offset: 0, start: "00:00:00"),
                    InsulinSensitivityEntry(sensitivity: 2, offset: 480, start: "08:00:00")
                ]
            ),
            carbRatios: CarbRatios(
                units: .grams,
                schedule: [
                    CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 10),
                    CarbRatioEntry(start: "11:00:00", offset: 660, ratio: 8.5)
                ]
            ),
            targets: BGTargets(
                units: .mmolL,
                userPreferredUnits: .mmolL,
                targets: [
                    BGTargetEntry(low: 5.5, high: 5.5, start: "00:00:00", offset: 0),
                    BGTargetEntry(low: 5.5, high: 6.5, start: "22:00:00", offset: 1320)
                ]
            ),
            pump: PumpSettings(insulinActionCurve: 7, maxBolus: 8, maxBasal: 3.5),
            preferences: preferences,
            settings: settings
        )
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
        period: StatsPeriod = .days30,
        parts: [ReportPart] = [.patches, .cgm, .settings],
        units: [GlucoseUnits] = [.mgdL],
        paper: ReportPaper = .a4,
        cgmPick: Stat.CGMPick? = nil,
        snapshot: ReportSettingsSnapshot? = StatsReportDevicesSettingsTests.snapshot
    ) -> Stat.ReportRequest {
        Stat.ReportRequest(
            period: period,
            parts: parts,
            units: units,
            hbA1cUnit: .percent,
            paper: paper,
            // no insulin and carbs block: the fake reads none
            summary: ReportOptions.SummarySettings(insulinAndCarbs: false, gri: false),
            cgmPick: cgmPick,
            settingsSnapshot: snapshot
        )
    }

    /// A daily total as a number: the schedules' rates are decimal fractions a literal doesn't always give exactly.
    private func total(_ snapshot: ReportSettingsSnapshot) -> Double? {
        snapshot.basalDailyTotal.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    /// The report's data as the builder leaves it for the three parts: five patches, two CGMs.
    private func data(_ request: Stat.ReportRequest) throws -> Stat.ReportData {
        var data = try Stat.ReportBuilder.assemble(request, summary: Self.summary(request.period), bins: [], now: Self.now)
        if request.parts.contains(.patches) {
            data.patches = .value(Self.patches(Self.patchRows(count: 5), period: request.period))
        }
        if request.parts.contains(.cgm) {
            data.cgm = .value(Self.twoCGMs)
        }
        return data
    }

    private func page(_ part: ReportPart, units: GlucoseUnits = .mgdL, index: Int = 0) -> ReportPage {
        ReportPage(part: part, units: units, size: ReportPaper.a4.size, index: index)
    }

    // MARK: - The catalogue

    func testEveryPartIsOffered() throws {
        XCTAssertEqual(ReportPart.implemented, ReportPart.allCases)
        XCTAssertTrue(ReportPart.patches.isImplemented && ReportPart.cgm.isImplemented && ReportPart.settings.isImplemented)
        // Settings is off until picked
        XCTAssertFalse(ReportPart.defaultSelection.contains(.settings))
        for part in [ReportPart.patches, .cgm, .settings] {
            XCTAssertFalse(part.hasSettings)
            XCTAssertFalse(ReportPlan.isLandscape(part, dailyCharts: .init()))
            for period in ReportOptions.periods {
                XCTAssertEqual(part.availability(for: period), .available)
            }
        }
        // Patches and CGM have glucose values: once per unit; Settings is printed once, in the first unit
        XCTAssertTrue(ReportPart.patches.printsGlucose && ReportPart.cgm.printsGlucose)
        XCTAssertFalse(ReportPart.settings.printsGlucose)

        // the estimate is the parts at their most, and says so
        var options = ReportOptions(period: .days30, units: .mgdL, paper: .a4, parts: [.patches, .cgm, .settings])
        let patchesPages = ReportPlan.patchesPages(days: 30, paper: .a4)
        XCTAssertEqual(options.estimatedPageCount, patchesPages + ReportPlan.cgmPages + ReportPlan.settingsPages)
        XCTAssertTrue(options.estimateIsUpperBound)
        options.units = .both
        XCTAssertEqual(
            options.estimatedPageCount,
            2 * (patchesPages + ReportPlan.cgmPages) + ReportPlan.settingsPages
        )
        for part in [ReportPart.patches, .cgm, .settings] {
            XCTAssertTrue(ReportOptions(period: .days7, units: .mgdL, paper: .a4, parts: [part]).estimateIsUpperBound)
        }

        // the plan: five patches on a page, two CGMs with two pages each, the settings on one
        let single = try data(request())
        XCTAssertEqual(
            single.pages(calendar: Self.calendar).map(\.part),
            [.patches, .cgm, .cgm, .cgm, .cgm, .settings]
        )
        XCTAssertLessThanOrEqual(single.pages(calendar: Self.calendar).count, options.estimatedPageCount)
        let both = try data(request(units: [.mmolL, .mgdL])).pages(calendar: Self.calendar)
        XCTAssertEqual(both.map(\.part), [.patches, .patches] + Array(repeating: .cgm, count: 8) + [.settings])
        XCTAssertEqual(both.last?.units, .mmolL)
        XCTAssertEqual(both.prefix(2).map(\.units), [.mmolL, .mgdL])
    }

    // MARK: - Settings

    func testSettingsSnapshot() throws {
        let snapshot = Self.snapshot
        // the steps by their start
        XCTAssertEqual(snapshot.basal.map(\.minutes), [0, 360, 1320])
        XCTAssertEqual(snapshot.basal.map(\.value), [0.8, 1, 0.6])
        // 6 h at 0.8, 16 h at 1, 2 h at 0.6
        XCTAssertEqual(try XCTUnwrap(total(snapshot)), 22, accuracy: 1E-9)
        XCTAssertEqual(snapshot.sensitivities.map(\.value), [2.5, 2])
        XCTAssertEqual(snapshot.sensitivityUnits, .mmolL)
        XCTAssertEqual(snapshot.carbRatios.map(\.minutes), [0, 660])
        XCTAssertFalse(snapshot.carbRatiosInExchanges)
        // a target with one value has no upper end
        XCTAssertNil(snapshot.targets[0].upper)
        XCTAssertEqual(snapshot.targets[1].upper, 6.5)
        XCTAssertEqual(snapshot.insulinActionHours, 7)
        XCTAssertEqual(snapshot.insulinCurve, "rapid-acting")
        XCTAssertNil(snapshot.insulinPeakMinutes)
        XCTAssertEqual(snapshot.maxIOB, 8.5)
        XCTAssertEqual(snapshot.maxBolus, 8)
        XCTAssertEqual(snapshot.maxBasal, 3.5)
        XCTAssertEqual(snapshot.maxSMBBasalMinutes, 90)
        XCTAssertEqual(snapshot.maxUAMSMBBasalMinutes, 120)
        XCTAssertTrue(snapshot.autoISF)
        XCTAssertEqual(snapshot.autoISFMax, 1.4)
        XCTAssertEqual(snapshot.autoISFIOBThresholdPercent, 80)
        XCTAssertEqual(snapshot.smbDeliveryRatio, 0.65)
        // autoISF's own ratio: off while its glucose range is 0
        XCTAssertEqual(snapshot.smbDeliveryRatioBGRange, 0)
        XCTAssertFalse(snapshot.variesSMBDeliveryRatio)
        var ranged = FreeAPSSettings()
        ranged.autoisf = true
        ranged.smbDeliveryRatioMin = 0.8
        ranged.smbDeliveryRatioMax = 0.4
        ranged.smbDeliveryRatioBGrange = 40
        let varying = ReportSettingsSnapshot(
            basal: [],
            sensitivities: .initial,
            carbRatios: .initial,
            targets: .initial,
            pump: .defaultValue,
            preferences: Preferences(),
            settings: ranged
        )
        XCTAssertTrue(varying.variesSMBDeliveryRatio)
        // the lower and the higher of the two, as the algorithm takes them
        XCTAssertEqual(varying.smbDeliveryRatioMin, 0.4)
        XCTAssertEqual(varying.smbDeliveryRatioMax, 0.8)
        XCTAssertEqual(snapshot.longestSchedule, 3)

        // the daily total goes around the day: a schedule that starts at 02:00 has its last rate before it
        var late = ReportSettingsSnapshot()
        XCTAssertNil(late.basalDailyTotal)
        late.basal = [.init(minutes: 120, value: 1), .init(minutes: 720, value: 0.5)]
        // 10 h at 1, 14 h at 0.5
        XCTAssertEqual(try XCTUnwrap(total(late)), 17, accuracy: 1E-9)
        late.basal = [.init(minutes: 0, value: 0.85)]
        XCTAssertEqual(try XCTUnwrap(total(late)), 20.4, accuracy: 1E-9)
        // a step every half hour
        late.basal = (0 ..< 48).map { .init(minutes: $0 * 30, value: 0.5) }
        XCTAssertEqual(try XCTUnwrap(total(late)), 12, accuracy: 1E-9)
        XCTAssertEqual(late.longestSchedule, 48)

        // a custom peak time is said only when used
        var preferences = Preferences()
        preferences.useCustomPeakTime = true
        preferences.insulinPeakTime = 55
        preferences.curve = .ultraRapid
        let custom = ReportSettingsSnapshot(
            basal: [],
            sensitivities: .initial,
            carbRatios: CarbRatios(units: .exchanges, schedule: []),
            targets: .initial,
            pump: .defaultValue,
            preferences: preferences,
            settings: FreeAPSSettings()
        )
        XCTAssertEqual(custom.insulinPeakMinutes, 55)
        XCTAssertEqual(custom.insulinCurve, "ultra-rapid")
        XCTAssertTrue(custom.carbRatiosInExchanges)
        XCTAssertFalse(custom.autoISF)
        XCTAssertNil(custom.basalDailyTotal)
    }

    @MainActor func testSettingsPage() throws {
        typealias Page = Stat.ReportSettingsPage
        // mmol/L first: the glucose values as stored
        let data = try data(request(parts: [.settings], units: [.mmolL, .mgdL]))
        XCTAssertEqual(data.pages(calendar: Self.calendar).map(\.units), [.mmolL])
        let settings = Page(data, page: page(.settings, units: .mmolL), calendar: Self.calendar)
        XCTAssertNil(settings.emptyNote)
        // says that these are the current settings, and when
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = Self.calendar.timeZone
        let asOf = Self.now.formatted(style)
        XCTAssertEqual(settings.header.dateRange, "As of \(asOf)")
        XCTAssertEqual(settings.header.days, "the current settings")
        XCTAssertTrue(settings.intro.hasPrefix("Settings as of \(asOf), when this report was made."))
        XCTAssertTrue(settings.intro.contains("may differ from those in force during the report's period"))
        XCTAssertEqual(settings.unitsNote, "Glucose values in mmol/L.")

        XCTAssertEqual(settings.schedules.map(\.title), ["Basal", "Insulin Sensitivities", "Carb Ratios", "Target Glucose"])
        XCTAssertEqual(settings.schedules.map(\.unit), ["U per hour", "mmol/L per U", "g per U", "mmol/L"])
        let basal = settings.schedules[0]
        XCTAssertEqual(basal.rows.map(\.time), [0, 360, 1320].map { Stat.AGP.clockTime($0) })
        XCTAssertEqual(basal.rows.map(\.value), [d("0.80"), d("1.00"), d("0.60")])
        XCTAssertEqual(basal.total, "Total \(d("22.0")) U per day")
        XCTAssertNil(settings.schedules[1].total)
        XCTAssertEqual(settings.schedules[1].rows.map(\.value), [d("2.5"), d("2.0")])
        XCTAssertEqual(settings.schedules[2].rows.map(\.value), ["10", d("8.5")])
        XCTAssertEqual(settings.schedules[3].rows.map(\.value), [d("5.5"), d("5.5") + "–" + d("6.5")])

        // the other values, on the same page
        XCTAssertEqual(settings.groups.map(\.title), ["Insulin", "Limits", "Auto ISF"])
        // the curve as the app's picker shows it
        XCTAssertEqual(settings.groups[0].rows.map(\.value), ["rapid-acting", "7"])
        // the app's own names for the settings
        XCTAssertEqual(
            settings.groups[1].rows.map(\.title),
            [
                "Max IOB",
                "Max Bolus",
                "Max Basal",
                "Max SMB Basal Minutes",
                "Max UAM SMB Basal Minutes",
                "Max COB",
                "SMB DeliveryRatio"
            ]
        )
        // autoISF on with its glucose range at 0: the fixed SMB delivery ratio is in force, among the limits
        XCTAssertEqual(settings.groups[1].rows.map(\.value), [d("8.5"), "8", d("3.5"), "90", "120", "120", d("0.65")])
        XCTAssertEqual(
            settings.groups[2].rows.map(\.title),
            ["Auto ISF", "Auto ISF Min", "Auto ISF Max", "Max IOB Threshold Percent"]
        )
        XCTAssertEqual(settings.groups[2].rows.map(\.value), ["On", d("0.7"), d("1.4"), "80"])

        // autoISF varying the ratio with glucose: its minimum, maximum and range, in the page's unit, in place of
        // the fixed one
        var varying = Self.snapshot
        varying.smbDeliveryRatioMin = 0.4
        varying.smbDeliveryRatioMax = 0.8
        varying.smbDeliveryRatioBGRange = 40
        XCTAssertTrue(varying.variesSMBDeliveryRatio)
        let ranged = Page(
            try self.data(request(parts: [.settings], snapshot: varying)),
            page: page(.settings),
            calendar: Self.calendar
        )
        XCTAssertFalse(ranged.groups[1].rows.contains { $0.title == "SMB DeliveryRatio" })
        XCTAssertEqual(
            ranged.groups[2].rows.map(\.title).suffix(3),
            ["SMB Delivery Ratio Minimum", "SMB Delivery Ratio Maximum", "SMB Delivery Ratio BG Range"]
        )
        XCTAssertEqual(ranged.groups[2].rows.map(\.value).suffix(3), [d("0.4"), d("0.8"), "40"])
        XCTAssertEqual(ranged.groups[2].rows.last?.unit, "mg/dL")
        let rangedMmol = Page(
            try self.data(request(parts: [.settings], units: [.mmolL], snapshot: varying)),
            page: page(.settings, units: .mmolL),
            calendar: Self.calendar
        )
        XCTAssertEqual(rangedMmol.groups[2].rows.last?.value, d("2.2"))
        XCTAssertEqual(rangedMmol.groups[2].rows.last?.unit, "mmol/L")
        // a range under 10 is in mmol/L
        varying.smbDeliveryRatioBGRange = 2
        XCTAssertEqual(Page.groups(varying, units: .mmolL)[2].rows.last?.value, d("2.0"))
        XCTAssertEqual(Page.groups(varying, units: .mgdL)[2].rows.last?.value, "36")
        XCTAssertEqual(data.pageCount(of: .settings, calendar: Self.calendar), 1)

        // mg/dL first: the same values converted, whole numbers
        let converted = Page(
            try self.data(request(parts: [.settings], units: [.mgdL, .mmolL])),
            page: page(.settings),
            calendar: Self.calendar
        )
        XCTAssertEqual(converted.unitsNote, "Glucose values in mg/dL.")
        XCTAssertEqual(converted.schedules[1].unit, "mg/dL per U")
        XCTAssertEqual(converted.schedules[1].rows.map(\.value), ["45", "36"])
        XCTAssertEqual(converted.schedules[3].rows.map(\.value), ["99", "99–117"])
        // what isn't glucose is the same
        XCTAssertEqual(converted.schedules[0], basal)
        XCTAssertEqual(converted.groups, settings.groups)
        XCTAssertEqual(Page.glucose(100, stored: .mgdL, units: .mgdL), "100")
        XCTAssertEqual(Page.glucose(100, stored: .mgdL, units: .mmolL), d("5.6"))
        XCTAssertEqual(Page.glucose(5.5, stored: .mmolL, units: .mmolL), d("5.5"))

        // autoISF off: its limits aren't listed
        var plain = Self.snapshot
        plain.autoISF = false
        let off = Page(
            try self.data(request(parts: [.settings], snapshot: plain)),
            page: page(.settings),
            calendar: Self.calendar
        )
        XCTAssertEqual(off.groups[2].rows.map(\.value), ["Off"])
        XCTAssertEqual(off.groups[1].rows.last?.title, "SMB DeliveryRatio")
        XCTAssertEqual(off.groups[1].rows.last?.value, d("0.65"))
        // off: its glucose range doesn't matter, the fixed ratio is in force
        plain.smbDeliveryRatioBGRange = 40
        XCTAssertFalse(plain.variesSMBDeliveryRatio)
        XCTAssertEqual(Page.groups(plain, units: .mgdL)[1].rows.last?.value, d("0.65"))
        XCTAssertEqual(Page.groups(plain, units: .mgdL)[2].rows.count, 1)

        // a glucose value in the unit it is stored in is printed as stored; converted, a sensitivity keeps two decimals
        XCTAssertEqual(Page.glucose(2.75, stored: .mmolL, units: .mmolL, decimals: 2), d("2.75"))
        XCTAssertEqual(Page.glucose(2.75, stored: .mmolL, units: .mmolL), d("2.75"))
        XCTAssertEqual(Page.glucose(6, stored: .mmolL, units: .mmolL), d("6.0"))
        XCTAssertEqual(Page.glucose(45.5, stored: .mgdL, units: .mgdL), d("45.5"))
        XCTAssertEqual(Page.glucose(10, stored: .mgdL, units: .mmolL, decimals: 2), d("0.56"))
        XCTAssertEqual(Page.glucose(11, stored: .mgdL, units: .mmolL, decimals: 2), d("0.61"))
        XCTAssertEqual(Page.glucose(2.75, stored: .mmolL, units: .mgdL, decimals: 2), "50")
        var fine = Self.snapshot
        fine.sensitivities = [.init(minutes: 0, value: 10), .init(minutes: 720, value: 11)]
        fine.sensitivityUnits = .mgdL
        fine.targets = [.init(minutes: 0, value: 5.25, upper: 6.75)]
        let precise = Page(
            try self.data(request(parts: [.settings], units: [.mmolL], snapshot: fine)),
            page: page(.settings, units: .mmolL),
            calendar: Self.calendar
        )
        XCTAssertEqual(precise.schedules[1].rows.map(\.value), [d("0.56"), d("0.61")])
        XCTAssertEqual(precise.schedules[3].rows.map(\.value), [d("5.25") + "–" + d("6.75")])

        // the export's time in the injected calendar's time zone
        var newYork = Self.calendar
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertNotEqual(Page(data, page: page(.settings), calendar: newYork).header.dateRange, settings.header.dateRange)

        // a basal step every half hour: lower rows, and the other values on a second page where they don't fit
        var long = Self.snapshot
        long.basal = (0 ..< 48).map { .init(minutes: $0 * 30, value: 0.5) }
        let letter = try self.data(request(parts: [.settings], paper: .letter, snapshot: long))
        XCTAssertFalse(ReportSettingsLayout.fitsOnePage(steps: 48, paper: .letter))
        XCTAssertEqual(letter.pageCount(of: .settings, calendar: Self.calendar), 2)
        XCTAssertLessThanOrEqual(letter.pageCount(of: .settings, calendar: Self.calendar), ReportPlan.settingsPages)
        let first = Page(letter, page: page(.settings), calendar: Self.calendar)
        let second = Page(letter, page: page(.settings, index: 1), calendar: Self.calendar)
        XCTAssertEqual(first.schedules[0].rows.count, 48)
        XCTAssertEqual(first.rowHeight, 10)
        XCTAssertTrue(first.groups.isEmpty)
        XCTAssertTrue(second.schedules.isEmpty)
        XCTAssertEqual(second.groups.count, 3)
        // the schedules alone fit their page
        for paper in ReportPaper.allCases {
            XCTAssertLessThanOrEqual(
                ReportSettingsLayout.introHeight + ReportSettingsLayout.schedulesHeight(steps: 48),
                ReportTablesLayout.available(paper)
            )
        }
        XCTAssertTrue(ReportSettingsLayout.fitsOnePage(steps: 3, paper: .letter))

        // no settings given: a page saying so
        let none = try self.data(request(parts: [.settings], snapshot: nil))
        XCTAssertEqual(none.pageCount(of: .settings, calendar: Self.calendar), 1)
        let blank = Page(none, page: page(.settings), calendar: Self.calendar)
        XCTAssertEqual(blank.emptyNote, "The settings couldn't be read.")
        XCTAssertTrue(blank.schedules.isEmpty && blank.groups.isEmpty)

        // the page's frame: no glucose ranges, nothing about the time in ranges
        let pages = data.pages(calendar: Self.calendar)
        let content = try XCTUnwrap(Stat.ReportPageContent(data, page: pages[0], calendar: Self.calendar))
        let chrome = Stat.ReportPageChrome(
            data,
            page: pages[0],
            index: 0,
            count: 1,
            version: "9.9.9",
            calendar: Self.calendar,
            header: content.header
        )
        XCTAssertEqual(chrome.title, "Settings")
        XCTAssertEqual(chrome.dateRange, "As of \(asOf)")
        XCTAssertEqual(chrome.ranges, "")
        XCTAssertFalse(chrome.provenance.contains("Time in ranges"))
    }

    // MARK: - Patches

    func testPatchesLayout() {
        typealias Layout = ReportPatchesLayout
        for paper in ReportPaper.allCases {
            for wearDays in [1, 3, Layout.maximumWearDays] {
                let top = Layout.topHeight(wearDays: wearDays, hasPeriodNote: true)
                let first = Layout.rowsPerPage(paper, top: top)
                let later = Layout.rowsPerPage(paper, top: 0)
                XCTAssertGreaterThan(first, 8)
                XCTAssertGreaterThan(later, first)
                // what a page holds fits it
                let list = ReportTablesLayout.sectionHeight + ReportTablesLayout.headerHeight
                XCTAssertLessThanOrEqual(top + list + CGFloat(first) * Layout.rowHeight, ReportTablesLayout.available(paper))
                XCTAssertLessThanOrEqual(list + CGFloat(later) * Layout.rowHeight, ReportTablesLayout.available(paper))
                for rows in [0, 1, first, first + 1, 45, 90] {
                    let ranges = Layout.ranges(rows: rows, wearDays: wearDays, hasPeriodNote: true, paper: paper)
                    XCTAssertFalse(ranges.isEmpty)
                    XCTAssertEqual(ranges.flatMap { Array($0) }, Array(0 ..< rows))
                    XCTAssertLessThanOrEqual(ranges[0].count, first)
                    XCTAssertTrue(ranges.dropFirst().allSatisfy { $0.count <= later && !$0.isEmpty })
                }
            }
        }
        // five patches of three days: one page; thirty: within the estimate
        let few = Self.patches(Self.patchRows(count: 5))
        XCTAssertEqual(Layout.wearDays(few), 3)
        XCTAssertEqual(Layout.pageCount(few, paper: .a4), 1)
        let many = Self.patches(Self.patchRows(count: 26), period: .days90)
        XCTAssertEqual(many.sessions.count, 26)
        for paper in ReportPaper.allCases {
            XCTAssertLessThanOrEqual(Layout.pageCount(many, paper: paper), ReportPlan.patchesPages(days: 90, paper: paper))
            // a change a day for 90 days, whatever the wear days' table: within the estimate
            for wearDays in [1, 2, 3, Layout.maximumWearDays] {
                let daily = Layout.ranges(rows: 91, wearDays: wearDays, hasPeriodNote: true, paper: paper)
                XCTAssertLessThanOrEqual(daily.count, ReportPlan.patchesPages(days: 90, paper: paper), "\(paper) \(wearDays)")
                XCTAssertEqual(daily.count, 3)
            }
            XCTAssertEqual(ReportPlan.patchesPages(days: 7, paper: paper), 1)
            XCTAssertLessThanOrEqual(ReportPlan.patchesPages(days: 30, paper: paper), 2)
        }
        XCTAssertEqual(Layout.pageCount(Self.patches([]), paper: .a4), 1)
    }

    @MainActor func testPatchesPage() throws {
        let data = try data(request(parts: [.patches]))
        let result = try XCTUnwrap(data.patches?.value)
        XCTAssertEqual(result.sessions.count, 5)
        let patches = Stat.ReportPatches(data, page: page(.patches), calendar: Self.calendar)
        XCTAssertNil(patches.emptyNote)
        XCTAssertTrue(patches.isFirst)
        // the topic's own numbers
        let model = Stat.Patches(result, settings: Stat.StatsSettings(report: .mgdL, hbA1cUnit: .percent))
        XCTAssertEqual(patches.count, "5 patches")
        XCTAssertEqual(patches.countDetail, model.countDetail)
        // said once: the page's first line, not beside the dates too
        XCTAssertEqual(patches.header.days, "")
        XCTAssertNil(patches.wearDaysCut)
        XCTAssertFalse((patches.periodNote ?? "").contains("marked"))
        XCTAssertEqual(patches.figures.map(\.title), ["Wear time", "Per patch", "Insulin", "In range"])
        XCTAssertEqual(patches.figures.map(\.value), model.tiles.map(\.value))
        XCTAssertEqual(patches.periodNote, model.periodNote)
        // the period's days, to today
        let first = Self.calendar.startOfDay(for: result.window.start)
        XCTAssertEqual(
            patches.header.dateRange,
            Stat.ReportPageHeader.dateRange(first, Self.calendar.startOfDay(for: Self.now), calendar: Self.calendar)
        )
        // a row a wear day: the patches counted, in range, the mean, the insulin per 24 h
        XCTAssertEqual(patches.wearDays.rows.count, 3)
        XCTAssertEqual(patches.wearDays.rows.map(\.title), model.rangeRows.map(\.name))
        XCTAssertEqual(patches.wearDays.columns.map(\.title), ["Patches", "In range", "Mean", "Insulin"])
        XCTAssertEqual(patches.wearDays.columns[1].subtitle, "70–180")
        XCTAssertEqual(patches.wearDays.columns[2].subtitle, "mg/dL")
        XCTAssertTrue(patches.wearDays.rows.allSatisfy { $0.cells.count == 4 })
        XCTAssertEqual(patches.wearDays.rows.map { $0.cells[3] }, model.insulinRows.map(\.value))
        XCTAssertEqual(patches.wearDayNote, model.wearDayNote)
        // the list, newest first
        XCTAssertEqual(patches.listTitle, "Patch by patch")
        XCTAssertEqual(patches.rows.map(\.id), model.rows.map(\.id))
        XCTAssertEqual(patches.rows.map(\.span), model.rows.map(\.span))
        XCTAssertEqual(patches.rows.map(\.detail), model.rows.map(\.detail))

        // mmol/L beside mg/dL: the same patches and shares, the mean's column in the page's unit
        let both = try self.data(request(parts: [.patches], units: [.mgdL, .mmolL]))
        let mmol = Stat.ReportPatches(both, page: page(.patches, units: .mmolL), calendar: Self.calendar)
        XCTAssertEqual(mmol.rows, patches.rows)
        XCTAssertEqual(mmol.figures.map(\.value), patches.figures.map(\.value))
        XCTAssertEqual(mmol.wearDays.columns[2].subtitle, "mmol/L")
        XCTAssertEqual(mmol.wearDays.rows.map { $0.cells[1] }, patches.wearDays.rows.map { $0.cells[1] })

        // a long list goes on, without the numbers again
        var long = try self.data(request(period: .days90, parts: [.patches], paper: .letter))
        long.patches = .value(Self.patches(Self.patchRows(count: 26), period: .days90))
        let count = long.pageCount(of: .patches, calendar: Self.calendar)
        let pages = (0 ..< count).map { Stat.ReportPatches(long, page: page(.patches, index: $0), calendar: Self.calendar) }
        XCTAssertEqual(pages.flatMap(\.rows).count, 26)
        XCTAssertEqual(Set(pages.flatMap(\.rows).map(\.id)).count, 26)
        XCTAssertEqual(pages.map(\.isFirst), [true] + Array(repeating: false, count: count - 1))
        XCTAssertTrue(Stat.ReportPatches(long, page: page(.patches, index: count), calendar: Self.calendar).rows.isEmpty)

        // nothing in the period, by the topic's naming; unread
        var blank = data
        blank.patches = .value(Self.patches([]))
        XCTAssertEqual(blank.pageCount(of: .patches, calendar: Self.calendar), 1)
        XCTAssertEqual(
            Stat.ReportPatches(blank, page: page(.patches), calendar: Self.calendar).emptyNote,
            "No patches in this period"
        )
        XCTAssertEqual(Stat.ReportPatches.emptyText(PatchTopic(plugin: "Omni")), "No pods in this period")
        XCTAssertEqual(Stat.ReportPatches.emptyText(nil), "No patches in this period")
        blank.patches = .failed
        XCTAssertEqual(blank.pageCount(of: .patches, calendar: Self.calendar), 1)
        XCTAssertEqual(
            Stat.ReportPatches(blank, page: page(.patches), calendar: Self.calendar).emptyNote,
            "The pump data couldn't be read."
        )
    }

    // MARK: - CGM

    @MainActor func testCGMPages() throws {
        let data = try data(request(period: .days7, parts: [.cgm]))
        let result = try XCTUnwrap(data.cgm?.value)
        XCTAssertEqual(result.cgms.map(\.name), ["Dexcom G7", "Libre 3", "Unknown"])
        // every named CGM, an Overview and a Sensors page each; Unknown isn't printed beside them
        XCTAssertEqual(Stat.ReportCGM.picks(result, shown: nil), [.cgm("dexcomG7"), .cgm("libre3")])
        XCTAssertEqual(data.pageCount(of: .cgm, calendar: Self.calendar), 4)
        let pages = (0 ..< 4).map { Stat.ReportCGM(data, page: page(.cgm, index: $0), calendar: Self.calendar) }
        XCTAssertEqual(pages.map(\.kind), [.overview, .sensors, .overview, .sensors])
        XCTAssertEqual(pages.map(\.header.days), ["Dexcom G7", "Dexcom G7", "Libre 3", "Libre 3"])
        XCTAssertTrue(pages.allSatisfy { $0.emptyNote == nil })
        XCTAssertEqual(pages.map { $0.report?.pick }, [.cgm("dexcomG7"), .cgm("dexcomG7"), .cgm("libre3"), .cgm("libre3")])
        let first = Self.calendar.startOfDay(for: result.window.start)
        XCTAssertEqual(
            pages[0].header.dateRange,
            Stat.ReportPageHeader.dateRange(first, Self.calendar.startOfDay(for: Self.now), calendar: Self.calendar)
        )
        // the topic's own model, in the page's unit
        let model = Stat.CGMReport(result, pick: .cgm("dexcomG7"), units: .mgdL, smoothing: .none)
        XCTAssertEqual(pages[0].report?.overview, model.overview)
        XCTAssertNotNil(pages[0].report?.overview.comparison)
        // the sensors, with their length of the expected life
        XCTAssertEqual(pages[1].sensors.map(\.id), model.sensors.rows.map(\.id))
        XCTAssertEqual(pages[1].sensors.count, 1)
        XCTAssertEqual(pages[1].sensors[0].span, model.sensors.rows[0].span)
        XCTAssertTrue(pages[1].sensors[0].life.hasSuffix("%"))
        XCTAssertNil(pages[1].moreSensors)
        XCTAssertTrue(pages[3].sensors[0].title.hasSuffix("in use"))
        // the noise by sensor day: a bar a day
        XCTAssertEqual(pages[1].noiseBars?.bars.count ?? 0, model.sensors.noiseDays.count)
        if let bars = pages[1].noiseBars {
            XCTAssertEqual(bars.levels, model.sensors.noiseLevels)
            XCTAssertEqual(bars.ticks.count, bars.bars.count)
        }
        // the note says what a day is, and nothing more
        XCTAssertTrue(pages[1].noiseNote.hasPrefix("Day 1 is the first 24 hours after a sensor start"))
        XCTAssertFalse(pages[1].noiseNote.contains("pre-soaking"))

        // the other unit's pages: the same CGMs, their values in it
        let both = try self.data(request(period: .days7, parts: [.cgm], units: [.mgdL, .mmolL]))
        XCTAssertEqual(
            both.pages(calendar: Self.calendar).map(\.units),
            Array(repeating: .mgdL, count: 4) + Array(repeating: .mmolL, count: 4)
        )
        let mmol = Stat.ReportCGM(both, page: page(.cgm, units: .mmolL), calendar: Self.calendar)
        XCTAssertEqual(mmol.report?.units, .mmolL)
        XCTAssertEqual(mmol.report?.overview.readings.coverage, pages[0].report?.overview.readings.coverage)

        // a view's own export: the CGM on screen alone
        let own = try self.data(request(period: .days7, parts: [.cgm], cgmPick: .cgm("libre3")))
        XCTAssertEqual(own.pageCount(of: .cgm, calendar: Self.calendar), 2)
        XCTAssertEqual(Stat.ReportCGM(own, page: page(.cgm), calendar: Self.calendar).header.days, "Libre 3")
        XCTAssertEqual(Stat.ReportCGM.picks(result, shown: .unknown), [.unknown])
        // one the period lacks: every named one
        XCTAssertEqual(Stat.ReportCGM.picks(result, shown: .cgm("other")), [.cgm("dexcomG7"), .cgm("libre3")])
        // a page past the part's: nothing to print
        XCTAssertNotNil(Stat.ReportCGM(data, page: page(.cgm, index: 4), calendar: Self.calendar).emptyNote)

        // more CGMs than a report prints: the one the screen opens on, then the two with the most readings; the one
        // left out is named on the first page
        var crowded = data
        crowded.cgm = .value(
            Self.cgm(
                Self.readings(from: Self.window.start, to: Self.now),
                [
                    Self.session("dexcomG6", name: "Dexcom G6", start: Self.day(0), end: Self.day(2), life: .days(10), id: 1),
                    Self.session("dexcomG7", name: "Dexcom G7", start: Self.day(2), end: Self.day(4), life: .days(10.5), id: 2),
                    Self.session("libre2", name: "Libre 2", start: Self.day(4), end: Self.day(6.25), life: .days(14), id: 3),
                    Self.session("libre3", name: "Libre 3", start: Self.day(6.25), end: nil, life: .days(14), id: 4)
                ]
            )
        )
        let four = try XCTUnwrap(crowded.cgm?.value)
        // the newest one has the fewest readings, and is kept
        XCTAssertEqual(four.defaultPick, .cgm("libre3"))
        XCTAssertEqual(Stat.ReportCGM.picks(four, shown: nil), [.cgm("dexcomG6"), .cgm("libre2"), .cgm("libre3")])
        XCTAssertEqual(Stat.ReportCGM.omitted(four, shown: nil), ["Dexcom G7"])
        XCTAssertEqual(Stat.ReportCGM.omitted(four, shown: .cgm("libre2")), [])
        XCTAssertEqual(crowded.pageCount(of: .cgm, calendar: Self.calendar), ReportPlan.cgmPages)
        XCTAssertEqual(ReportPlan.cgmPages, 6)
        let crowdedPages = (0 ..< 6).map { Stat.ReportCGM(crowded, page: page(.cgm, index: $0), calendar: Self.calendar) }
        XCTAssertEqual(crowdedPages.map(\.omittedNote), ["Not printed: Dexcom G7", nil, nil, nil, nil, nil])
        XCTAssertEqual(crowdedPages.map(\.header.days), ["Dexcom G6", "Dexcom G6", "Libre 2", "Libre 2", "Libre 3", "Libre 3"])
        XCTAssertNil(pages[0].omittedNote)
        XCTAssertEqual(Stat.ReportCGM.omitted(result, shown: nil), [])
        XCTAssertNil(pages[0].unknownNote)

        // the page's frame: no ranges' line and nothing about the time in ranges (the page has no range figures)
        let cgmPages = data.pages(calendar: Self.calendar)
        let chrome = Stat.ReportPageChrome(
            data,
            page: cgmPages[0],
            index: 0,
            count: cgmPages.count,
            version: "9.9.9",
            calendar: Self.calendar,
            header: pages[0].header
        )
        XCTAssertEqual(chrome.ranges, "")
        XCTAssertFalse(chrome.provenance.contains("Time in ranges"))
        XCTAssertTrue(ReportPart.cgm.printsGlucose)
        XCTAssertFalse(ReportPart.cgm.printsRanges)
        XCTAssertTrue(ReportPart.patches.printsRanges && ReportPart.summary.printsRanges)
        XCTAssertFalse(ReportPart.settings.printsRanges || ReportPart.insulin.printsRanges)

        // the sensors a page lists depend on the paper, and on the noise chart under them
        for paper in ReportPaper.allCases {
            let withNoise = Stat.ReportCGM.maximumSensors(paper, hasNoise: true)
            let without = Stat.ReportCGM.maximumSensors(paper, hasNoise: false)
            XCTAssertGreaterThan(withNoise, 20)
            XCTAssertGreaterThan(without, withNoise)
            XCTAssertLessThanOrEqual(
                Stat.ReportCGM.sensorsChrome + Stat.ReportCGM.noiseHeight + CGFloat(withNoise) * Stat.ReportCGM.sensorRowHeight,
                ReportTablesLayout.available(paper)
            )
        }
        XCTAssertGreaterThan(
            Stat.ReportCGM.maximumSensors(.a4, hasNoise: true),
            Stat.ReportCGM.maximumSensors(.letter, hasNoise: true)
        )

        // readings no session names: Unknown alone is printed
        var unnamed = data
        unnamed.cgm = .value(Self.cgm(Self.readings(from: Self.window.start, to: Self.now), []))
        XCTAssertEqual(Stat.ReportCGM.picks(try XCTUnwrap(unnamed.cgm?.value), shown: nil), [.unknown])
        XCTAssertEqual(unnamed.pageCount(of: .cgm, calendar: Self.calendar), 2)
        let unknown = Stat.ReportCGM(unnamed, page: page(.cgm, index: 1), calendar: Self.calendar)
        XCTAssertNil(unknown.emptyNote)
        // what Unknown is, on its Overview
        let unknownOverview = Stat.ReportCGM(unnamed, page: page(.cgm), calendar: Self.calendar)
        XCTAssertTrue((unknownOverview.unknownNote ?? "").hasPrefix("Readings from before iAPS recorded which CGM was in use."))
        XCTAssertTrue(unknown.sensors.isEmpty)
        XCTAssertNil(unknown.noiseBars)

        // no reading in the period; unread
        var blank = data
        blank.cgm = .value(Self.cgm([], []))
        XCTAssertEqual(blank.pageCount(of: .cgm, calendar: Self.calendar), 1)
        XCTAssertEqual(Stat.ReportCGM(blank, page: page(.cgm), calendar: Self.calendar).emptyNote, "No CGM data in this period")
        blank.cgm = .failed
        XCTAssertEqual(blank.pageCount(of: .cgm, calendar: Self.calendar), 1)
        XCTAssertEqual(
            Stat.ReportCGM(blank, page: page(.cgm), calendar: Self.calendar).emptyNote,
            "The CGM readings couldn't be read."
        )
    }

    // MARK: - The reads

    private struct Failure: Error {}

    /// The provider's calls a report makes, faked.
    private actor FakeSource: ReportDataSource {
        typealias Fixtures = StatsReportDevicesSettingsTests

        private(set) var reads: [String] = []
        private(set) var inputs: [ReportPatchesInput] = []
        /// the clock and the calendar's time zone each device read was given
        private(set) var clocks: [Date] = []
        private(set) var zones: [String] = []
        private(set) var bands: [StatsBands] = []
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

        func reportInsulin(_: StatsPeriod) throws -> InsulinPeriod { throw CancellationError() }
        func reportMeals(_: StatsPeriod, factor _: Double) throws -> MealPeriod { throw CancellationError() }

        func reportDays(_ period: StatsPeriod) -> PeriodDays {
            reads.append("days")
            return PeriodDays(window: Fixtures.summary(period).window, endRule: .stalled, days: [])
        }

        func reportTrace(day _: Date, bands _: StatsBands) -> ReportDayTrace {
            ReportDayTrace(points: [], summary: Fixtures.summary(.days7))
        }

        func reportInsulinInput(_: DateInterval, now _: Date) -> InsulinInput { InsulinInput() }

        func reportHourOfDay(_ period: StatsPeriod, bands: StatsBands) -> Stat.HourOfDayResult {
            reads.append("hours")
            return Stat.HourOfDayResult(buckets: [], summary: Fixtures.summary(period), bands: bands)
        }

        func reportWeekday(_ period: StatsPeriod, bands: StatsBands) -> Stat.WeekdayResult {
            Stat.WeekdayResult(
                GlucoseStatsEngine.weekdayHours([], days: [], bands: bands, calendar: Fixtures.calendar),
                period: period
            )
        }

        func reportGoodBadDays(_ period: StatsPeriod, bands: StatsBands, allowOneMinuteLoop _: Bool) -> Stat.GoodBadDaysData {
            Stat.GoodBadDaysData(
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

        func reportPatches(
            _ period: StatsPeriod,
            bands: StatsBands,
            input: ReportPatchesInput,
            now: Date,
            calendar: Calendar
        ) throws -> Stat.PatchesResult {
            reads.append("patches \(period.rawValue)")
            clocks.append(now)
            zones.append(calendar.timeZone.identifier)
            inputs.append(input)
            self.bands.append(bands)
            if isFailing { throw Failure() }
            return Fixtures.patches(isEmpty ? [] : Fixtures.patchRows(count: 5), period: period)
        }

        func reportCGM(_ period: StatsPeriod, now: Date, calendar: Calendar) throws -> Stat.CGMResult {
            reads.append("cgm \(period.rawValue)")
            clocks.append(now)
            zones.append(calendar.timeZone.identifier)
            if isFailing { throw Failure() }
            return isEmpty ? Fixtures.cgm([], []) : Fixtures.twoCGMs
        }
    }

    private func build(_ request: Stat.ReportRequest, _ source: FakeSource) async throws -> Stat.ReportData {
        try await Stat.ReportBuilder.build(request, source: source, now: Self.now, calendar: Self.calendar)
    }

    func testBuilderReadsTheTopics() async throws {
        var input = ReportPatchesInput()
        input.currentPlugin = "Medtrum"
        input.allowOneMinuteLoop = true
        let request = Stat.ReportRequest(
            period: .days30,
            parts: [.summary, .patches, .cgm, .settings],
            units: [.mmolL, .mgdL],
            hbA1cUnit: .percent,
            paper: .a4,
            summary: ReportOptions.SummarySettings(insulinAndCarbs: false, gri: false),
            patchesInput: input,
            settingsSnapshot: Self.snapshot
        )
        let source = FakeSource()
        let data = try await build(request, source)
        let reads = await source.reads
        XCTAssertEqual(reads, ["profile", "patches days30", "cgm days30"])
        // the report's clock and calendar, not the device's
        let clocks = await source.clocks
        XCTAssertEqual(clocks, [Self.now, Self.now])
        let zones = await source.zones
        XCTAssertEqual(zones, ["Europe/Berlin", "Europe/Berlin"])
        // the screen's input as given, the report's bands (the first unit's)
        let inputs = await source.inputs
        XCTAssertEqual(inputs, [input])
        let bands = await source.bands
        XCTAssertEqual(bands, [Stat.ReportBuilder.standardBands(.mmolL)])
        XCTAssertEqual(data.patches?.value?.sessions.count, 5)
        XCTAssertEqual(data.cgm?.value?.cgms.count, 3)
        XCTAssertEqual(data.request.settingsSnapshot, Self.snapshot)

        // Settings alone: nothing is read, and no CGM data is needed
        let alone = FakeSource()
        let settings = try await build(self.request(parts: [.settings]), alone)
        let aloneReads = await alone.reads
        XCTAssertEqual(aloneReads, [])
        XCTAssertEqual(settings.pages(calendar: Self.calendar).map(\.part), [.settings])
        XCTAssertNil(self.request(parts: [.settings]).ownPart)

        // a read that fails doesn't fail the report: the part's page says so
        let failing = FakeSource()
        await failing.fail()
        let partial = try await build(self.request(parts: [.summary, .patches, .cgm]), failing)
        XCTAssertEqual(partial.patches, .failed)
        XCTAssertEqual(partial.cgm, .failed)
        XCTAssertEqual(partial.pages(calendar: Self.calendar).map(\.part), [.summary, .patches, .cgm])
        // without the parts: nothing of theirs is read
        let plain = FakeSource()
        let none = try await build(self.request(parts: [.summary]), plain)
        XCTAssertNil(none.patches)
        XCTAssertNil(none.cgm)
    }

    /// A topic's own "Export PDF" reads that topic alone; without its data, or unread, no report, saying why.
    func testOwnPartReads() async throws {
        let source = FakeSource()
        let patches = try await build(request(parts: [.patches]), source)
        let cgm = try await build(request(period: .days7, parts: [.cgm], cgmPick: .cgm("libre3")), source)
        let reads = await source.reads
        XCTAssertEqual(reads, ["patches days30", "cgm days7"])
        XCTAssertEqual(request(parts: [.patches]).ownPart, .patches)
        XCTAssertEqual(request(parts: [.cgm]).ownPart, .cgm)
        XCTAssertEqual(patches.pages(calendar: Self.calendar).map(\.part), [.patches])
        XCTAssertEqual(cgm.pages(calendar: Self.calendar).map(\.part), [.cgm, .cgm])

        // the file is named by the topic's days
        func name(_ data: Stat.ReportData) -> String {
            let days = data.fileDays(calendar: Self.calendar)
            return ReportPDFWriter.fileName(first: days.first, last: days.last, calendar: Self.calendar)
        }
        XCTAssertEqual(name(patches), "iAPS report 2026-09-17 – 2026-10-16.pdf")
        XCTAssertEqual(name(cgm), "iAPS report 2026-10-10 – 2026-10-16.pdf")

        let cases: [(ReportPart, Stat.ReportError, Stat.ReportError)] = [
            (.patches, .noPatches("No patches in this period"), .patchesNotRead),
            (.cgm, .noData, .cgmNotRead)
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
            let failing = FakeSource()
            await failing.fail()
            do {
                _ = try await build(request(period: .days7, parts: [part]), failing)
                XCTFail("\(part)")
            } catch {
                XCTAssertEqual(error as? Stat.ReportError, unread, "\(part)")
            }
            let blankReads = await blank.reads
            XCTAssertFalse(blankReads.contains("profile"))
        }

        typealias Exporter = Stat.ReportExporter
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.noPatches("No pods in this period")), "No pods in this period")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.patchesNotRead), "The pump data couldn't be read.")
        XCTAssertEqual(Exporter.failureText(Stat.ReportError.cgmNotRead), "The CGM readings couldn't be read.")
        for error in [Stat.ReportError.noPatches(""), .patchesNotRead, .cgmNotRead] {
            XCTAssertFalse(Exporter.isUnexpected(error))
        }
        // a cancellation the user didn't ask for (a read's own) is said, not swallowed
        XCTAssertEqual(Exporter.failureText(CancellationError()), "The report couldn't be created.")
        XCTAssertTrue(Exporter.isUnexpected(CancellationError()))
    }

    /// What the screen gives a report: the CGM on screen for the CGM topic's own export only, the Patches read's
    /// input and the settings as they are.
    @MainActor func testRequestsFromTheScreen() {
        let name = "test-report-devices-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: parent)
        }
        let preferences = ReportPreferences(defaults: defaults)
        let exporter = Stat.ReportExporter(preferences: preferences, parent: parent, calendar: { Self.calendar })
        var input = ReportPatchesInput()
        input.deliveringPlugin = "Medtrum"
        let context = Stat.ReportContext(
            source: FakeSource(),
            userUnits: .mmolL,
            hbA1cUnit: .percent,
            carbEquivalentFactor: 0.5,
            screenPeriod: .days14,
            patchesInput: input,
            cgmPick: .cgm("libre3"),
            settingsSnapshot: Self.snapshot
        )
        let cgm = exporter.partRequest(.cgm, context: context)
        XCTAssertEqual(cgm.parts, [.cgm])
        XCTAssertEqual(cgm.period, .days14)
        XCTAssertEqual(cgm.cgmPick, .cgm("libre3"))
        let patches = exporter.partRequest(.patches, context: context)
        XCTAssertEqual(patches.patchesInput, input)
        XCTAssertNil(patches.cgmPick)
        // a report made on the Reports screen prints every CGM, and has the settings
        preferences.parts = [.cgm, .settings]
        let report = context.request(preferences.options(userUnits: .mmolL))
        XCTAssertEqual(report.parts, [.cgm, .settings])
        XCTAssertNil(report.cgmPick)
        XCTAssertEqual(report.settingsSnapshot, Self.snapshot)
        XCTAssertEqual(report.patchesInput, input)
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
            .appendingPathComponent("stats-report-devices-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }

        let data = try data(request(period: .days7))
        let output = try await ReportPDFWriter.write(data, version: "9.9.9", parent: parent, calendar: Self.calendar)
        let document = try XCTUnwrap(PDFDocument(url: output.url))
        // the patches, two CGMs' Overview and Sensors, the settings
        XCTAssertEqual(document.pageCount, 6)
        for index in 0 ..< 6 {
            let size = try XCTUnwrap(document.page(at: index)).bounds(for: .mediaBox).size
            XCTAssertEqual(size.width, 595, accuracy: 0.5)
            XCTAssertEqual(size.height, 842, accuracy: 0.5)
        }
        let text = plainText(document)
        for expected in [
            "Patches",
            "By wear day",
            "Patch by patch",
            "CGM",
            "Dexcom G7",
            "Libre 3",
            "Rate of change",
            "Sensor by sensor",
            "Settings",
            "the current settings",
            "Insulin Sensitivities",
            "Max IOB",
            "Auto ISF",
            "Generated by iAPS 9.9.9",
            "Page 6 of 6"
        ] {
            XCTAssertTrue(text.contains(expected), expected)
        }
        // the settings' page has no line about the time in ranges; the others do
        let last = try XCTUnwrap(document.page(at: 5)?.string)
        XCTAssertFalse(last.contains("Time in ranges"))
        XCTAssertTrue((document.page(at: 0)?.string ?? "").contains("Time in ranges is time-weighted"))
    }
}
