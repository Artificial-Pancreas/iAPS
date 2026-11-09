import Foundation
import LoopKitUI

enum Home {
    enum Config {}

    /// The Loops card's one range: the last 24 hours.
    static let loopsRange: StatsPeriod = .last24h
    /// The stats bar's GMI line: the last 90 days (`HomeStatsBar.Content.gmiLine`), a read of its own beside the bar's
    /// range.
    static let gmiPeriod: StatsPeriod = .days90

    /// What the stats bar depends on: its range (`StatsDisplayPreferences.homeStatsRange`), and from the settings the
    /// bands (low/high and units) and the HbA1c unit.
    struct StatsConfig: Equatable, Sendable {
        let range: StatsPeriod
        let settings: Stat.StatsSettings
    }

    /// What the Loops card depends on from the settings: the 1-minute loop (the readings a loop can run on, the gaps'
    /// cadence). Its range is fixed (`Home.loopsRange`).
    struct LoopsConfig: Equatable, Sendable {
        let allowOneMinuteLoop: Bool

        init(_ settings: FreeAPSSettings) {
            allowOneMinuteLoop = settings.allowOneMinuteLoop
        }
    }
}

protocol HomeProvider: Provider {
    func heartbeatNow() async
    func smoothedGlucose(hours: Int) async -> [BloodGlucose]
    func rawGlucose(hours: Int) async -> [BloodGlucose]
    func carbs(hours: Int) -> [CarbsEntry]
    func announcement(_ hours: Int) async -> [Announcement]
    /// The stats bar's summary: the same call the Statistics Overview makes.
    func glucoseSummary(_ period: StatsPeriod, bands: StatsBands) async -> GlucoseSummary
    /// The Loops card's numbers for the range, up to now; nil when the readings couldn't be read.
    func loopStats(_ period: StatsPeriod, allowOneMinuteLoop: Bool) async -> HomeLoopStats?
    /// The meal card (Today), up to now; nil when the meals couldn't be read.
    func mealsCard() async -> HomeMealsCard.Content?
    /// The insulin card (Today), up to now; nil when the insulin data couldn't be read.
    func insulinCard() async -> HomeInsulinCard.Content?
//    func overrides() async -> [OverrideSnapshot]
}
