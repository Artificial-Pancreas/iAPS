import Foundation

protocol OverrideManager: Sendable {
    @discardableResult func cancelActiveOverride() async -> Bool
    func autoCancelOverrideIfNeeded() async
}

actor BaseOverrideManager: OverrideManager, LifetimeOwner, AppService {
    private let overrideStorage: OverrideStorage
    private let nightscoutManager: NightscoutManager

    private let coreDataStorage = CoreDataStorage()

    let lifetime = Lifetime()

    init(
        overrideStorage: OverrideStorage,
        nightscoutManager: NightscoutManager
    ) {
        self.overrideStorage = overrideStorage
        self.nightscoutManager = nightscoutManager
    }

    // this is called at the app start
    func start() async {}

    @discardableResult func cancelActiveOverride() async -> Bool {
        guard let activeOveride = await overrideStorage.fetchCurrentActiveOverride() else {
            return false
        }
        let presetName = await getOverrideName(for: activeOveride)
        guard let duration = await overrideStorage.cancelProfile() else {
            return false
        }
        await nightscoutManager.uploadOverride(presetName, duration, activeOveride.date ?? Date.now)
        return true
    }

    func autoCancelOverrideIfNeeded() async {
        guard let activeOverride = await overrideStorage.fetchCurrentActiveOverride() else {
            return
        }

        if await cancelOverrideAfterDurationIfApplicable(activeOverride) {
            return
        }

        guard activeOverride.advancedSettings else { return }

        // End with new Meal, when applicable
        if await cancelOverrideAfterCarbsIfApplicable(activeOverride) {
            return
        }

        // End with new glucose trending up, when applicable
        if await cancelOverrideWhenTrendingUpIfApplicable(activeOverride) {
            return
        }

        // End with new glucose when lower than setting, when applicable
        if await cancelOverrideWhenGlucoseBelowThresholdIfApplicable(activeOverride) {
            return
        }
    }

    private func cancelOverrideAfterDurationIfApplicable(_ activeOverride: OverrideSnapshot) async -> Bool {
        guard !activeOverride.indefinite else { return false }
        guard let date = activeOverride.date else { return false }

        let duration = activeOverride.duration ?? 0

        guard Date() > date.addingTimeInterval(.minutes(duration)) else { return false }

        guard await cancelActiveOverride() else { return false }

        debug(.apsManager, "Override ended, duration: \(duration) minutes")
        return true
    }

    private func cancelOverrideAfterCarbsIfApplicable(_ activeOverride: OverrideSnapshot) async -> Bool {
        guard activeOverride.endWIthNewCarbs, let overrideStarted = activeOverride.date else { return false }
        // TODO: should we cancel on ANY meal (as before) or only when carbs are announced?
        guard let recent = await coreDataStorage.recentMeal(), !recent.isEmpty,
              let mealDate = recent.actualDate else { return false }
        guard mealDate > overrideStarted else { return false }

        guard await cancelActiveOverride() else { return false }

        debug(
            .apsManager,
            "Override ended, because of new meal: \(recent.carbs ?? 0) g carbs"
        )
        return true
    }

    private func cancelOverrideWhenTrendingUpIfApplicable(_ activeOverride: OverrideSnapshot) async -> Bool {
        guard activeOverride.glucoseOverrideThresholdActive else { return false }
        guard let g = await coreDataStorage.fetchRecentGlucose() else { return false }
        guard let glucoseDirection = g.direction else { return false }

        let glucose = Decimal(g.glucose)
        let glucoseOverrideThreshold = activeOverride.glucoseOverrideThreshold ?? 100
        guard glucose > glucoseOverrideThreshold else { return false }
        guard glucoseDirection == BloodGlucose.Direction.fortyFiveUp.symbol ||
            glucoseDirection == BloodGlucose.Direction.singleUp.symbol ||
            glucoseDirection == BloodGlucose.Direction.doubleUp.symbol
        else { return false }

        guard await cancelActiveOverride() else { return false }

        debug(
            .apsManager,
            "Override ended, because of new glucose: \(g.glucose) mg/dl \(glucoseDirection)"
        )
        return true
    }

    private func cancelOverrideWhenGlucoseBelowThresholdIfApplicable(_ activeOverride: OverrideSnapshot) async -> Bool {
        guard activeOverride.glucoseOverrideThresholdActiveDown else { return false }
        guard let g = await coreDataStorage.fetchRecentGlucose() else { return false }

        let glucose = Decimal(g.glucose)
        let glucoseThreshold = activeOverride.glucoseOverrideThresholdDown ?? 90
        guard glucose < glucoseThreshold else { return false }

        guard await cancelActiveOverride() else { return false }

        debug(
            .apsManager,
            "Override ended, because of new glucose: \(g.glucose) mg/dl \(g.direction ?? "")"
        )
        return true
    }

    private func getOverrideName(for override: OverrideSnapshot) async -> String {
        // Is the Override a Preset?
        if let presetName = await overrideStorage.getPresetName(for: override) {
            return presetName
        }

        if override.isPreset { // Because hard coded Hypo treatment isn't actually a preset
            return "📉"
        } else {
            return override.percentage.formatted() != "100" ? override.percentage.formatted() + " %" : "Custom"
        }
    }
}
