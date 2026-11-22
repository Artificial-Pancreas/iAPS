import CoreGraphics
import Foundation

// The Settings part of a report: the therapy settings as they are when the report is made. No history of the settings
// is kept, so the page says that they are the current ones and may differ from those in force during the period.
// Nothing is computed from them but the basal schedule's daily total; glucose values are written in the report's
// first unit, and the page says which.

/// The therapy settings a report prints, copied when it is asked for from the values the app already publishes
/// (`AppCoordinator`'s subjects, read only): plain values, so the report is made off the main actor without touching
/// the settings.
struct ReportSettingsSnapshot: Sendable, Equatable {
    /// A step of a schedule: from its minute of the day to the next one's.
    struct Step: Sendable, Equatable {
        /// minutes from 00:00
        let minutes: Int
        let value: Decimal
        /// a glucose target's upper end; nil elsewhere, and when it is the lower one
        var upper: Decimal?
    }

    /// U per hour
    var basal: [Step] = []
    /// per U, in `sensitivityUnits`
    var sensitivities: [Step] = []
    var sensitivityUnits: GlucoseUnits = .mgdL
    /// g (or exchanges) per U
    var carbRatios: [Step] = []
    var carbRatiosInExchanges = false
    /// in `targetUnits`
    var targets: [Step] = []
    var targetUnits: GlucoseUnits = .mgdL

    /// hours
    var insulinActionHours: Decimal?
    /// "rapid-acting", "ultra-rapid", "bilinear" (`InsulinCurve`)
    var insulinCurve: String?
    /// minutes; nil unless a custom peak time is used
    var insulinPeakMinutes: Decimal?

    var maxIOB: Decimal?
    var maxBolus: Decimal?
    /// U per hour
    var maxBasal: Decimal?
    var maxSMBBasalMinutes: Decimal?
    var maxUAMSMBBasalMinutes: Decimal?
    var maxCOB: Decimal?

    var autoISF = false
    var autoISFMin: Decimal?
    var autoISFMax: Decimal?
    var autoISFIOBThresholdPercent: Decimal?
    /// the share of the insulin required an SMB gives: the fixed one (oref's), used unless autoISF varies it
    var smbDeliveryRatio: Decimal?
    /// autoISF's own: the ratio goes from the minimum at the target to the maximum at the target + the range. A range
    /// of 0 switches that off (the fixed ratio is used). The range is in mmol/L when under 10, else in mg/dL
    /// (`autoisf.js`, `determine_varSMBratio`).
    var smbDeliveryRatioMin: Decimal?
    var smbDeliveryRatioMax: Decimal?
    var smbDeliveryRatioBGRange: Decimal = 0

    /// autoISF is on and varies the SMB delivery ratio with glucose: the fixed ratio isn't used.
    var variesSMBDeliveryRatio: Bool {
        autoISF && smbDeliveryRatioBGRange > 0
    }

    init() {}

    /// From the values the app publishes; nothing is changed, converted or stored.
    init(
        basal: [BasalProfileEntry],
        sensitivities: InsulinSensitivities,
        carbRatios: CarbRatios,
        targets: BGTargets,
        pump: PumpSettings,
        preferences: Preferences,
        settings: FreeAPSSettings
    ) {
        self.basal = basal.map { Step(minutes: $0.minutes, value: $0.rate) }.sorted { $0.minutes < $1.minutes }
        self.sensitivities = sensitivities.sensitivities
            .map { Step(minutes: $0.offset, value: $0.sensitivity) }.sorted { $0.minutes < $1.minutes }
        sensitivityUnits = sensitivities.units
        self.carbRatios = carbRatios.schedule.map { Step(minutes: $0.offset, value: $0.ratio) }.sorted { $0.minutes < $1.minutes }
        carbRatiosInExchanges = carbRatios.units == .exchanges
        self.targets = targets.targets
            .map { Step(minutes: $0.offset, value: $0.low, upper: $0.high == $0.low ? nil : $0.high) }
            .sorted { $0.minutes < $1.minutes }
        targetUnits = targets.units

        insulinActionHours = pump.insulinActionCurve
        insulinCurve = preferences.curve.rawValue
        insulinPeakMinutes = preferences.useCustomPeakTime ? preferences.insulinPeakTime : nil
        maxIOB = preferences.maxIOB
        maxBolus = pump.maxBolus
        maxBasal = pump.maxBasal
        maxSMBBasalMinutes = preferences.maxSMBBasalMinutes
        maxUAMSMBBasalMinutes = preferences.maxUAMSMBBasalMinutes
        maxCOB = preferences.maxCOB

        autoISF = settings.autoisf
        autoISFMin = settings.autoisf_min
        autoISFMax = settings.autoisf_max
        autoISFIOBThresholdPercent = settings.iobThresholdPercent
        smbDeliveryRatio = preferences.smbDeliveryRatio
        smbDeliveryRatioMin = Swift.min(settings.smbDeliveryRatioMin, settings.smbDeliveryRatioMax)
        smbDeliveryRatioMax = Swift.max(settings.smbDeliveryRatioMin, settings.smbDeliveryRatioMax)
        smbDeliveryRatioBGRange = settings.smbDeliveryRatioBGrange
    }

    /// The basal schedule's daily total, U: each rate over the time to the next step, around the day (a schedule that
    /// doesn't start at midnight has its last rate before its first step). nil without a schedule.
    var basalDailyTotal: Decimal? {
        guard basal.isNotEmpty else { return nil }
        let day = 24 * 60
        var total: Decimal = 0
        for (index, step) in basal.enumerated() {
            let next = index + 1 < basal.count ? basal[index + 1].minutes : basal[0].minutes + day
            total += step.value * Decimal(Swift.max(next - step.minutes, 0)) / 60
        }
        return total
    }

    /// the longest schedule's steps
    var longestSchedule: Int {
        Swift.max(Swift.max(basal.count, sensitivities.count), Swift.max(carbRatios.count, targets.count))
    }
}

/// How the Settings part is laid out: the four schedules side by side, the other values in three groups under them,
/// or on a second page when the schedules are long.
enum ReportSettingsLayout {
    /// what the page says first: that these are the current settings
    static let introHeight: CGFloat = 40
    /// a section's title with its rule and the space around it
    static let sectionHeight: CGFloat = 28
    /// a schedule's column titles
    static let headerHeight: CGFloat = 16
    /// the groups of values under the schedules, at their longest
    static let valuesHeight: CGFloat = 28 + 8 * 13 + 10

    /// A schedule's row: lower for the longest schedules (a basal step every half hour).
    static func rowHeight(steps: Int) -> CGFloat {
        steps > 36 ? 10 : 11.5
    }

    /// The schedules' height: the title, the column titles, the longest one's steps and the line under them.
    static func schedulesHeight(steps: Int) -> CGFloat {
        sectionHeight + headerHeight + CGFloat(Swift.max(steps, 1) + 1) * rowHeight(steps: steps) + 8
    }

    /// The values go under the schedules on one page.
    static func fitsOnePage(steps: Int, paper: ReportPaper) -> Bool {
        introHeight + schedulesHeight(steps: steps) + valuesHeight <= ReportTablesLayout.available(paper)
    }

    static func pageCount(_ snapshot: ReportSettingsSnapshot?, paper: ReportPaper) -> Int {
        guard let snapshot else { return 1 }
        return fitsOnePage(steps: snapshot.longestSchedule, paper: paper) ? 1 : 2
    }
}

extension Stat {
    /// A page of the Settings part.
    struct ReportSettingsPage: Equatable {
        /// A schedule: its steps by the time they start at.
        struct Schedule: Equatable, Identifiable {
            let id: Int
            /// "Basal"
            let title: String
            /// "U per hour"
            let unit: String
            let rows: [Row]
            /// "Total 21.6 U per day"; nil but for the basal
            let total: String?
        }

        struct Row: Equatable, Identifiable {
            let id: Int
            /// "00:00"
            let time: String
            /// "0.85", "5.0–6.5"
            let value: String
        }

        /// A group of values: "Insulin", "Limits", "autoISF".
        struct Group: Equatable, Identifiable {
            let id: Int
            let title: String
            let rows: [ReportFigure]
        }

        let header: ReportPageHeader
        /// in place of everything: the settings weren't given to the report
        let emptyNote: String?
        /// "Settings as of 20 Jan 2027 at 12:00, when this report was made. No history of the settings is kept: they may
        /// differ from those in force during the report's period."
        let intro: String
        /// "Glucose values in mg/dL."
        let unitsNote: String
        /// the schedules; none on a second page
        let schedules: [Schedule]
        /// the other values; none on the first page when they are on the second
        let groups: [Group]
        /// a schedule's row height
        let rowHeight: CGFloat

        /// A glucose value of a schedule in the page's unit. In the unit it is stored in: as stored, every decimal it
        /// has (up to three; mmol/L with one at least). Converted: a whole mg/dL, mmol/L to `decimals` (one for a
        /// target, two for a sensitivity, where a tenth is too coarse).
        static func glucose(_ value: Decimal, stored: GlucoseUnits, units: GlucoseUnits, decimals: Int = 1) -> String {
            guard stored != units else { return number(value, digits: units == .mmolL ? 1 : 0, maximum: 3) }
            return units == .mmolL ? number(value.asMmolL, digits: decimals) : number(value.asMgdL, digits: 0)
        }

        /// A number with up to `maximum` decimals (exactly `digits` at least), as the locale writes it.
        static func number(_ value: Decimal, digits: Int, maximum: Int? = nil) -> String {
            value.formatted(
                .number.precision(.fractionLength(digits ... Swift.max(maximum ?? digits, digits)))
                    .rounded(rule: .toNearestOrAwayFromZero)
            )
        }

        /// - Parameters:
        ///   - page: one of the part's (`index`)
        ///   - calendar: the time zone the export's time is written in
        @MainActor init(_ data: ReportData, page: ReportPage, calendar: Calendar) {
            typealias Layout = ReportSettingsLayout
            let snapshot = data.request.settingsSnapshot
            // one unit for the glucose values, the report's first: the page is printed once
            let units = data.request.units.first ?? page.units
            let unit = StatsFormatting.unit(units)

            var timeStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
            timeStyle.timeZone = calendar.timeZone
            let asOf = data.generatedAt.formatted(timeStyle)
            header = ReportPageHeader(
                dateRange: String(
                    format: NSLocalizedString("As of %@", comment: "PDF report, Settings header: when the report was made"),
                    asOf
                ),
                days: NSLocalizedString("the current settings", comment: "PDF report, Settings header: what the page holds")
            )
            emptyNote = snapshot == nil
                ? NSLocalizedString("The settings couldn't be read.", comment: "PDF report, Settings: no settings were given")
                : nil
            intro = String(
                format: NSLocalizedString(
                    "Settings as of %@, when this report was made. No history of the settings is kept: they may differ from those in force during the report's period.",
                    comment: "PDF report, Settings: the page's first line, the export's date and time"
                ),
                asOf
            )
            unitsNote = String(
                format: NSLocalizedString(
                    "Glucose values in %@.",
                    comment: "PDF report, Settings: the unit of the glucose values"
                ),
                unit
            )

            let steps = snapshot?.longestSchedule ?? 0
            rowHeight = Layout.rowHeight(steps: steps)
            let onePage = Layout.fitsOnePage(steps: steps, paper: data.request.paper)
            let showsSchedules = page.index == 0
            let showsGroups = onePage ? page.index == 0 : page.index == 1

            func rows(_ steps: [ReportSettingsSnapshot.Step], _ value: (ReportSettingsSnapshot.Step) -> String) -> [Row] {
                steps.enumerated().map { index, step in Row(id: index, time: AGP.clockTime(step.minutes), value: value(step)) }
            }
            if let snapshot, showsSchedules {
                let perUnit = NSLocalizedString("per U", comment: "PDF report, Settings: a value per unit of insulin")
                schedules = [
                    Schedule(
                        id: 0,
                        title: NSLocalizedString("Basal", comment: "Statistics Insulin: the basal insulin"),
                        unit: NSLocalizedString("U per hour", comment: "Statistics Insulin by hour: the unit"),
                        rows: rows(snapshot.basal) { Self.number($0.value, digits: 2, maximum: 3) },
                        total: snapshot.basalDailyTotal.map {
                            String(
                                format: NSLocalizedString(
                                    "Total %@ U per day",
                                    comment: "PDF report, Settings: the basal schedule's daily total"
                                ),
                                Self.number($0, digits: 1, maximum: 2)
                            )
                        }
                    ),
                    Schedule(
                        id: 1,
                        title: NSLocalizedString("Insulin Sensitivities", comment: ""),
                        unit: unit + " " + perUnit,
                        rows: rows(snapshot.sensitivities) {
                            Self.glucose($0.value, stored: snapshot.sensitivityUnits, units: units, decimals: 2)
                        },
                        total: nil
                    ),
                    Schedule(
                        id: 2,
                        title: NSLocalizedString("Carb Ratios", comment: ""),
                        unit: (
                            snapshot.carbRatiosInExchanges
                                ? NSLocalizedString("exchanges", comment: "PDF report, Settings: carb ratios in exchanges")
                                : NSLocalizedString("g", comment: "Statistics Meals: grams")
                        ) + " " + perUnit,
                        rows: rows(snapshot.carbRatios) { Self.number($0.value, digits: 0, maximum: 2) },
                        total: nil
                    ),
                    Schedule(
                        id: 3,
                        title: NSLocalizedString("Target Glucose", comment: ""),
                        unit: unit,
                        rows: rows(snapshot.targets) { step in
                            let low = Self.glucose(step.value, stored: snapshot.targetUnits, units: units)
                            guard let upper = step.upper else { return low }
                            return low + "–" + Self.glucose(upper, stored: snapshot.targetUnits, units: units)
                        },
                        total: nil
                    )
                ]
            } else {
                schedules = []
            }
            groups = snapshot.flatMap { showsGroups ? Self.groups($0, units: units) : nil } ?? []
        }

        /// Insulin, the limits, autoISF: each value with its name (the app's own) and unit; a value the snapshot lacks is
        /// left out. The SMB delivery ratio is the fixed one among the limits, unless autoISF varies it with glucose:
        /// then its minimum, maximum and glucose range are in autoISF's group instead.
        /// - Parameter units: the page's, for autoISF's glucose range
        @MainActor static func groups(_ snapshot: ReportSettingsSnapshot, units: GlucoseUnits) -> [Group] {
            let insulinUnits = NSLocalizedString("U", comment: "Insulin unit")
            let minutes = NSLocalizedString("min", comment: "PDF report, Settings: minutes")
            func figure(
                _ id: Int,
                _ title: String,
                _ value: Decimal?,
                digits: Int,
                maximum: Int,
                unit: String?
            ) -> ReportFigure? {
                value
                    .map {
                        ReportFigure(id: id, title: title, value: Self.number($0, digits: digits, maximum: maximum), unit: unit) }
            }
            let curve: ReportFigure? = snapshot.insulinCurve.map { raw in
                ReportFigure(
                    id: 0,
                    title: NSLocalizedString("Insulin curve", comment: "PDF report, Settings: the insulin's action curve"),
                    // as the app's picker shows it
                    value: raw
                )
            }
            let insulin = [
                curve,
                figure(
                    1,
                    NSLocalizedString("Duration of Insulin Action", comment: ""),
                    snapshot.insulinActionHours,
                    digits: 0,
                    maximum: 1,
                    unit: NSLocalizedString("h", comment: "PDF report, Settings: hours")
                ),
                figure(
                    2,
                    NSLocalizedString("Insulin Peak Time", comment: ""),
                    snapshot.insulinPeakMinutes,
                    digits: 0,
                    maximum: 0,
                    unit: minutes
                )
            ]
            let varies = snapshot.variesSMBDeliveryRatio
            let limits = [
                figure(0, NSLocalizedString("Max IOB", comment: ""), snapshot.maxIOB, digits: 0, maximum: 2, unit: insulinUnits),
                figure(
                    1,
                    NSLocalizedString("Max Bolus", comment: ""),
                    snapshot.maxBolus,
                    digits: 0,
                    maximum: 2,
                    unit: insulinUnits
                ),
                figure(
                    2,
                    NSLocalizedString("Max Basal", comment: ""),
                    snapshot.maxBasal,
                    digits: 0,
                    maximum: 2,
                    unit: NSLocalizedString("U per hour", comment: "Statistics Insulin by hour: the unit")
                ),
                figure(
                    3,
                    NSLocalizedString("Max SMB Basal Minutes", comment: ""),
                    snapshot.maxSMBBasalMinutes,
                    digits: 0,
                    maximum: 0,
                    unit: minutes
                ),
                figure(
                    4,
                    NSLocalizedString("Max UAM SMB Basal Minutes", comment: ""),
                    snapshot.maxUAMSMBBasalMinutes,
                    digits: 0,
                    maximum: 0,
                    unit: minutes
                ),
                figure(
                    5,
                    NSLocalizedString("Max COB", comment: ""),
                    snapshot.maxCOB,
                    digits: 0,
                    maximum: 0,
                    unit: NSLocalizedString("g", comment: "Statistics Meals: grams")
                ),
                // the fixed ratio: not in force while autoISF varies it
                varies ? nil : figure(
                    6,
                    NSLocalizedString("SMB DeliveryRatio", comment: ""),
                    snapshot.smbDeliveryRatio,
                    digits: 1,
                    maximum: 2,
                    unit: nil
                )
            ]
            let state = ReportFigure(
                id: 0,
                title: NSLocalizedString("Auto ISF", comment: ""),
                value: snapshot.autoISF
                    ? NSLocalizedString("On", comment: "PDF report, Settings: a setting that is on")
                    : NSLocalizedString("Off", comment: "PDF report, Settings: a setting that is off")
            )
            // the range as stored: mmol/L when under 10 (`autoisf.js`)
            let rangeUnits: GlucoseUnits = snapshot.smbDeliveryRatioBGRange < 10 ? .mmolL : .mgdL
            // its limits only while it is on
            let autoISF: [ReportFigure?] = [state] + (
                snapshot.autoISF
                    ? [
                        figure(
                            1,
                            NSLocalizedString("Auto ISF Min", comment: ""),
                            snapshot.autoISFMin,
                            digits: 1,
                            maximum: 2,
                            unit: nil
                        ),
                        figure(
                            2,
                            NSLocalizedString("Auto ISF Max", comment: ""),
                            snapshot.autoISFMax,
                            digits: 1,
                            maximum: 2,
                            unit: nil
                        ),
                        figure(
                            3,
                            NSLocalizedString("Max IOB Threshold Percent", comment: ""),
                            snapshot.autoISFIOBThresholdPercent,
                            digits: 0,
                            maximum: 0,
                            unit: "%"
                        )
                    ] + (
                        varies
                            ? [
                                figure(
                                    4,
                                    NSLocalizedString("SMB Delivery Ratio Minimum", comment: ""),
                                    snapshot.smbDeliveryRatioMin,
                                    digits: 1,
                                    maximum: 2,
                                    unit: nil
                                ),
                                figure(
                                    5,
                                    NSLocalizedString("SMB Delivery Ratio Maximum", comment: ""),
                                    snapshot.smbDeliveryRatioMax,
                                    digits: 1,
                                    maximum: 2,
                                    unit: nil
                                ),
                                ReportFigure(
                                    id: 6,
                                    title: NSLocalizedString("SMB Delivery Ratio BG Range", comment: ""),
                                    value: Self.glucose(snapshot.smbDeliveryRatioBGRange, stored: rangeUnits, units: units),
                                    unit: StatsFormatting.unit(units)
                                )
                            ]
                            : []
                    )
                    : []
            )
            return [
                Group(id: 0, title: NSLocalizedString("Insulin", comment: "Statistics topic"), rows: insulin.compactMap { $0 }),
                Group(
                    id: 1,
                    title: NSLocalizedString("Limits", comment: "PDF report, Settings: the algorithm's limits"),
                    rows: limits.compactMap { $0 }
                ),
                Group(id: 2, title: NSLocalizedString("Auto ISF", comment: ""), rows: autoISF.compactMap { $0 })
            ]
        }
    }
}
