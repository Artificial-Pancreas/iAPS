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
    static let implemented: [ReportPart] = [.summary, .percentileProfile]

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

    /// printed on a landscape page
    var isLandscape: Bool {
        self == .percentileProfile
    }

    /// The pages the part takes in one unit (every part of this slice is one page).
    var pageCount: Int { 1 }

    /// the part has settings of its own (shown under it when it is selected)
    var hasSettings: Bool {
        self == .summary
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

    /// the periods a report offers; they end today
    static let periods: [StatsPeriod] = [.days7, .days14, .days30, .days90]
    static let defaultPeriod: StatsPeriod = .days14

    var period: StatsPeriod
    var units: ReportUnits
    var paper: ReportPaper
    /// the parts selected, of the implemented ones
    var parts: Set<ReportPart>
    var summary = SummarySettings()

    /// the selected parts in the report's order
    var orderedParts: [ReportPart] {
        ReportPart.implemented.filter { parts.contains($0) }
    }

    /// The pages the report will have.
    var estimatedPageCount: Int {
        Self.pageCount(parts: orderedParts, unitCount: units == .both ? 2 : 1)
    }

    static func pageCount(parts: [ReportPart], unitCount: Int) -> Int {
        parts.reduce(0) { $0 + $1.pageCount } * Swift.max(unitCount, 0)
    }

    /// The period a report is made for from the period on screen: the nearest one offered (Today and 24 h: 7 d).
    static func period(nearest period: StatsPeriod) -> StatsPeriod {
        Stat.StateModel.nearest(period, in: periods)
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

    /// The parts selected: every implemented one until picked; a stored part that isn't implemented is left out.
    var parts: Set<ReportPart> {
        get {
            guard let raw = defaults.array(forKey: Key.parts) as? [String] else { return Set(ReportPart.implemented) }
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

    /// The choices as stored, the ones never picked from the user's unit and the region.
    func options(userUnits: GlucoseUnits, locale: Locale = .current) -> ReportOptions {
        ReportOptions(
            period: period,
            units: units ?? ReportUnits(userUnits),
            paper: paper ?? ReportPaper.regional(locale),
            parts: parts,
            summary: summary
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
