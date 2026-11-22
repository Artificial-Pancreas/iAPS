import CoreGraphics
import Foundation

/// The parts a PDF report can hold, in the order they are printed. Only `implemented` ones are offered.
enum ReportPart: String, CaseIterable, Identifiable, Sendable, Hashable {
    case summary
    case percentileProfile
    case daysTable
    case dailyCharts
    case byHour
    case byWeekday
    case weekly
    case goodBadDays
    case insulin
    case meals
    case patches
    case cgm
    case settings

    /// The parts that can be printed so far, in the report's order.
    static let implemented: [ReportPart] = [.summary, .percentileProfile, .daysTable, .dailyCharts]
    /// The parts selected until the user picks: the two one-page ones.
    static let defaultSelection: Set<ReportPart> = [.summary, .percentileProfile]

    var id: String { rawValue }

    var isImplemented: Bool { Self.implemented.contains(self) }

    var title: String {
        switch self {
        case .summary: return NSLocalizedString("Summary", comment: "PDF report part")
        case .percentileProfile: return NSLocalizedString("Percentile profile", comment: "PDF report part")
        case .daysTable: return NSLocalizedString("Days table", comment: "PDF report part")
        case .dailyCharts: return NSLocalizedString("Daily charts", comment: "PDF report part")
        case .byHour: return NSLocalizedString("By hour", comment: "Statistics view: time in ranges by the hour of the day")
        case .byWeekday: return NSLocalizedString("By weekday", comment: "Statistics view: the weekdays, and each one's hours")
        case .weekly: return NSLocalizedString("Weekly", comment: "Statistics view: the last 13 weeks, week by week")
        case .goodBadDays: return NSLocalizedString(
                "Good & bad days",
                comment: "Statistics view: the days scored by GRI, two groups of them compared"
            )
        case .insulin: return NSLocalizedString("Insulin", comment: "Statistics topic")
        case .meals: return NSLocalizedString("Meals", comment: "Statistics topic")
        case .patches: return NSLocalizedString("Patches", comment: "Statistics topic: the pump's patches")
        case .cgm: return NSLocalizedString("CGM", comment: "Statistics topic: the CGM's own readings")
        case .settings: return NSLocalizedString("Settings", comment: "PDF report part")
        }
    }

    /// the part has settings of its own (shown under it when it is selected)
    var hasSettings: Bool {
        self == .summary || self == .daysTable || self == .dailyCharts
    }
}

/// The glucose units of a report: one of them, or both (every page once per unit).
enum ReportUnits: String, CaseIterable, Sendable, Hashable {
    case mgdL
    case mmolL
    case both

    init(_ units: GlucoseUnits) {
        self = units == .mmolL ? .mmolL : .mgdL
    }

    /// The units printed, in the pages' order: with both, the user's own first.
    func printed(userUnits: GlucoseUnits) -> [GlucoseUnits] {
        switch self {
        case .mgdL: return [.mgdL]
        case .mmolL: return [.mmolL]
        case .both: return userUnits == .mmolL ? [.mmolL, .mgdL] : [.mgdL, .mmolL]
        }
    }
}

/// The paper of a report, in points.
enum ReportPaper: String, CaseIterable, Sendable, Hashable {
    case a4
    case letter

    /// the regions printing on US Letter (CLDR's paper size data)
    static let letterRegions: Set<String> = [
        "US", "CA", "MX", "BZ", "CL", "CO", "CR", "GT", "NI", "PA", "PH", "PR", "SV", "VE"
    ]

    /// Letter in the regions that print on it, A4 everywhere else (and without a region).
    static func regional(_ locale: Locale = .current) -> ReportPaper {
        guard let region = locale.region?.identifier else { return .a4 }
        return letterRegions.contains(region.uppercased()) ? .letter : .a4
    }

    /// portrait
    var size: CGSize {
        switch self {
        case .a4: return CGSize(width: 595, height: 842)
        case .letter: return CGSize(width: 612, height: 792)
        }
    }

    func size(landscape: Bool) -> CGSize {
        landscape ? CGSize(width: size.height, height: size.width) : size
    }
}

/// What a report is made of: the user's choices on the Reports screen.
struct ReportOptions: Equatable, Sendable {
    /// The Summary part's own settings.
    struct SummarySettings: Equatable, Sendable {
        /// "Insulin and carbs per day"
        var insulinAndCarbs = true
        /// "Glycemia Risk Index"
        var gri = true
    }

    /// The Days table's own settings: the columns after the glucose ones, the subtotal rows and the order.
    struct DaysTableSettings: Equatable, Sendable {
        enum Subtotals: String, CaseIterable, Sendable, Hashable {
            case none
            /// after each calendar week (it starts on the calendar's first weekday)
            case week
            case month
        }

        var insulin = true
        var carbs = true
        /// "SD and CV"
        var sdAndCV = true
        /// "Lowest and highest"
        var lowestAndHighest = false
        /// "CGM coverage"
        var cgmCoverage = false
        var subtotals: Subtotals = .none
        var newestFirst = false
    }

    /// The Daily charts' own settings.
    struct DailyChartsSettings: Equatable, Sendable {
        /// the layouts: 1 a landscape page, 2 and 4 stacked on a portrait page, 8 in two columns
        static let daysPerPageChoices = [1, 2, 4, 8]
        static let defaultDaysPerPage = 4

        /// one of `daysPerPageChoices`
        var daysPerPage = DailyChartsSettings.defaultDaysPerPage
        /// "Boluses and SMBs"
        var boluses = true
        var carbs = true
        var basal = true
        var newestFirst = false

        /// two columns of panels
        var columns: Int { daysPerPage == 8 ? 2 : 1 }
        var rows: Int { daysPerPage / columns }
        var isLandscape: Bool { daysPerPage == 1 }
    }

    /// the periods a report offers; they end today
    static let periods: [StatsPeriod] = [.days7, .days14, .days30, .days90]
    static let defaultPeriod: StatsPeriod = .days14

    var period: StatsPeriod
    var units: ReportUnits
    var paper: ReportPaper
    /// the parts selected, of the implemented ones
    var parts: Set<ReportPart>
    var summary = SummarySettings()
    var daysTable = DaysTableSettings()
    var dailyCharts = DailyChartsSettings()

    /// the selected parts in the report's order
    var orderedParts: [ReportPart] {
        ReportPart.implemented.filter { parts.contains($0) }
    }

    /// The pages the report will have.
    /// The pages the report will have, about: every day of the period counted as a day with data (Daily charts
    /// leaves out the days without any), the subtotal rows by the period's length.
    var estimatedPageCount: Int {
        let days = period.calendarDayCount ?? 1
        let pages = orderedParts.reduce(0) { total, part in
            total + ReportPlan.estimatedPages(part, days: days, paper: paper, daysTable: daysTable, dailyCharts: dailyCharts)
        }
        return pages * (units == .both ? 2 : 1)
    }

    /// `estimatedPageCount` is an upper bound ("up to N pages"), not the exact count.
    var estimateIsUpperBound: Bool {
        ReportPlan.isUpperBound(orderedParts, daysTable: daysTable)
    }

    /// The period a report is made for from the period on screen: the nearest one offered (Today and 24 h: 7 d).
    static func period(nearest period: StatsPeriod) -> StatsPeriod {
        Stat.StateModel.nearest(period, in: periods)
    }
}

/// How a report's parts are laid out on pages: what the estimate and the real plan (`Stat.ReportData.pages`) share.
enum ReportPlan {
    /// a row of the Days table, points
    static let daysTableRowHeight: CGFloat = 15
    /// what a Days table page holds besides its rows: the margins, the page's header and footer, the column titles and
    /// the footnote
    static let daysTableChrome: CGFloat = 212

    /// The rows a Days table page holds (landscape), by the paper's height.
    static func daysTableRowsPerPage(_ paper: ReportPaper) -> Int {
        let height = paper.size(landscape: true).height
        return Swift.max(Int((height - daysTableChrome) / daysTableRowHeight), 8)
    }

    /// The pages `count` items take at `perPage` each.
    /// The estimate can be more than the report has: Daily charts leaves out the days without anything to draw, and
    /// the subtotal rows are counted at their most.
    static func isUpperBound(_ parts: [ReportPart], daysTable: ReportOptions.DaysTableSettings) -> Bool {
        parts.contains(.dailyCharts) || (parts.contains(.daysTable) && daysTable.subtotals != .none)
    }

    static func pageCount(_ count: Int, perPage: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + Swift.max(perPage, 1) - 1) / Swift.max(perPage, 1)
    }

    /// The subtotal rows of a period of `days` days, at most: a part of a week or a month at either end.
    static func estimatedSubtotals(days: Int, _ subtotals: ReportOptions.DaysTableSettings.Subtotals) -> Int {
        switch subtotals {
        case .none: return 0
        case .week: return (days + 6) / 7 + 1
        case .month: return days / 28 + 1
        }
    }

    /// The pages a part takes in one unit, about (see `ReportOptions.estimatedPageCount`).
    static func estimatedPages(
        _ part: ReportPart,
        days: Int,
        paper: ReportPaper,
        daysTable: ReportOptions.DaysTableSettings,
        dailyCharts: ReportOptions.DailyChartsSettings
    ) -> Int {
        switch part {
        case .daysTable:
            // the days, the subtotals and the Average row
            let rows = days + estimatedSubtotals(days: days, daysTable.subtotals) + 1
            return pageCount(rows, perPage: daysTableRowsPerPage(paper))
        case .dailyCharts:
            return pageCount(days, perPage: dailyCharts.daysPerPage)
        default:
            return part.isImplemented ? 1 : 0
        }
    }

    /// A part's pages are landscape: the Percentile profile, the Days table, Daily charts one a page.
    static func isLandscape(_ part: ReportPart, dailyCharts: ReportOptions.DailyChartsSettings) -> Bool {
        switch part {
        case .daysTable,
             .percentileProfile: return true
        case .dailyCharts: return dailyCharts.isLandscape
        default: return false
        }
    }
}

/// The Reports screen's choices, kept on the phone in `UserDefaults` (as `StatsDisplayPreferences`: UI-only, not in
/// `FreeAPSSettings`). A missing value, or one the choice doesn't offer, reads as the default; a value the choice
/// doesn't offer is never written. Tests pass a `UserDefaults(suiteName:)`.
struct ReportPreferences {
    enum Key {
        static let period = "iAPS.reports.period"
        static let units = "iAPS.reports.units"
        static let paper = "iAPS.reports.paper"
        static let parts = "iAPS.reports.parts"
        static let summaryInsulinAndCarbs = "iAPS.reports.summary.insulinAndCarbs"
        static let summaryGRI = "iAPS.reports.summary.gri"
        static let daysInsulin = "iAPS.reports.days.insulin"
        static let daysCarbs = "iAPS.reports.days.carbs"
        static let daysSDAndCV = "iAPS.reports.days.sdAndCV"
        static let daysLowestAndHighest = "iAPS.reports.days.lowestAndHighest"
        static let daysCGMCoverage = "iAPS.reports.days.cgmCoverage"
        static let daysSubtotals = "iAPS.reports.days.subtotals"
        static let daysNewestFirst = "iAPS.reports.days.newestFirst"
        static let chartsDaysPerPage = "iAPS.reports.charts.daysPerPage"
        static let chartsBoluses = "iAPS.reports.charts.boluses"
        static let chartsCarbs = "iAPS.reports.charts.carbs"
        static let chartsBasal = "iAPS.reports.charts.basal"
        static let chartsNewestFirst = "iAPS.reports.charts.newestFirst"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 7, 14, 30 or 90 days (14 by default)
    var period: StatsPeriod {
        get {
            guard let raw = defaults.string(forKey: Key.period), let period = StatsPeriod(rawValue: raw),
                  ReportOptions.periods.contains(period)
            else { return ReportOptions.defaultPeriod }
            return period
        }
        nonmutating set {
            guard ReportOptions.periods.contains(newValue) else { return }
            defaults.set(newValue.rawValue, forKey: Key.period)
        }
    }

    /// nil until picked: the user's unit
    var units: ReportUnits? {
        get { defaults.string(forKey: Key.units).flatMap { ReportUnits(rawValue: $0) } }
        nonmutating set { set(newValue?.rawValue, Key.units) }
    }

    /// nil until picked: the region's paper
    var paper: ReportPaper? {
        get { defaults.string(forKey: Key.paper).flatMap { ReportPaper(rawValue: $0) } }
        nonmutating set { set(newValue?.rawValue, Key.paper) }
    }

    /// The parts selected: `ReportPart.defaultSelection` until picked; a stored part that isn't implemented is left out.
    var parts: Set<ReportPart> {
        get {
            guard let raw = defaults.array(forKey: Key.parts) as? [String] else { return ReportPart.defaultSelection }
            return Set(raw.compactMap { ReportPart(rawValue: $0) }.filter(\.isImplemented))
        }
        nonmutating set {
            defaults.set(ReportPart.implemented.filter { newValue.contains($0) }.map(\.rawValue), forKey: Key.parts)
        }
    }

    /// on by default
    var summaryInsulinAndCarbs: Bool {
        get { defaults.object(forKey: Key.summaryInsulinAndCarbs) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.summaryInsulinAndCarbs) }
    }

    /// on by default
    var summaryGRI: Bool {
        get { defaults.object(forKey: Key.summaryGRI) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.summaryGRI) }
    }

    var summary: ReportOptions.SummarySettings {
        ReportOptions.SummarySettings(insulinAndCarbs: summaryInsulinAndCarbs, gri: summaryGRI)
    }

    /// The Days table's settings: a missing value, or one of another type, is the default; an unknown subtotal none.
    var daysTable: ReportOptions.DaysTableSettings {
        get {
            typealias Settings = ReportOptions.DaysTableSettings
            let standard = Settings()
            return Settings(
                insulin: bool(Key.daysInsulin, standard.insulin),
                carbs: bool(Key.daysCarbs, standard.carbs),
                sdAndCV: bool(Key.daysSDAndCV, standard.sdAndCV),
                lowestAndHighest: bool(Key.daysLowestAndHighest, standard.lowestAndHighest),
                cgmCoverage: bool(Key.daysCGMCoverage, standard.cgmCoverage),
                subtotals: defaults.string(forKey: Key.daysSubtotals).flatMap { Settings.Subtotals(rawValue: $0) }
                    ?? standard.subtotals,
                newestFirst: bool(Key.daysNewestFirst, standard.newestFirst)
            )
        }
        nonmutating set {
            defaults.set(newValue.insulin, forKey: Key.daysInsulin)
            defaults.set(newValue.carbs, forKey: Key.daysCarbs)
            defaults.set(newValue.sdAndCV, forKey: Key.daysSDAndCV)
            defaults.set(newValue.lowestAndHighest, forKey: Key.daysLowestAndHighest)
            defaults.set(newValue.cgmCoverage, forKey: Key.daysCGMCoverage)
            defaults.set(newValue.subtotals.rawValue, forKey: Key.daysSubtotals)
            defaults.set(newValue.newestFirst, forKey: Key.daysNewestFirst)
        }
    }

    /// The Daily charts' settings: a missing value, or one of another type, is the default; days per page that isn't a
    /// layout reads as 4 and is never written.
    var dailyCharts: ReportOptions.DailyChartsSettings {
        get {
            typealias Settings = ReportOptions.DailyChartsSettings
            let standard = Settings()
            let stored = integer(Key.chartsDaysPerPage)
            return Settings(
                daysPerPage: stored.flatMap { Settings.daysPerPageChoices.contains($0) ? $0 : nil } ?? standard.daysPerPage,
                boluses: bool(Key.chartsBoluses, standard.boluses),
                carbs: bool(Key.chartsCarbs, standard.carbs),
                basal: bool(Key.chartsBasal, standard.basal),
                newestFirst: bool(Key.chartsNewestFirst, standard.newestFirst)
            )
        }
        nonmutating set {
            if ReportOptions.DailyChartsSettings.daysPerPageChoices.contains(newValue.daysPerPage) {
                defaults.set(newValue.daysPerPage, forKey: Key.chartsDaysPerPage)
            }
            defaults.set(newValue.boluses, forKey: Key.chartsBoluses)
            defaults.set(newValue.carbs, forKey: Key.chartsCarbs)
            defaults.set(newValue.basal, forKey: Key.chartsBasal)
            defaults.set(newValue.newestFirst, forKey: Key.chartsNewestFirst)
        }
    }

    /// A stored whole number; nil for anything else, a stored Bool too (it would read as 0 or 1).
    private func integer(_ key: String) -> Int? {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              Double(number.intValue) == number.doubleValue
        else { return nil }
        return number.intValue
    }

    private func bool(_ key: String, _ standard: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? standard
    }

    /// The choices as stored, the ones never picked from the user's unit and the region.
    func options(userUnits: GlucoseUnits, locale: Locale = .current) -> ReportOptions {
        ReportOptions(
            period: period,
            units: units ?? ReportUnits(userUnits),
            paper: paper ?? ReportPaper.regional(locale),
            parts: parts,
            summary: summary,
            daysTable: daysTable,
            dailyCharts: dailyCharts
        )
    }

    private func set(_ value: String?, _ key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
