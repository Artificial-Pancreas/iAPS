import Foundation

protocol OverrideManager: Sendable {
    @discardableResult func cancelActiveOverride() async -> Bool
    /// Cancels the active override (if any), activates the new one and uploads it to Nightscout.
    @discardableResult func activateOverride(
        preset: OverridePresetsSnapshot,
        fromSavedPreset: Bool,
        defaultMaxIOB: Decimal?
    ) async -> OverrideSnapshot?
    func autoCancelOverrideIfNeeded() async
    /// Preset changes that can affect the active override's successor (already uploaded to Nightscout).
    func updateOverridePreset(_ draft: OverridePresetsSnapshot) async
    func deleteOverridePresets(ids: [String]) async
}

extension OverrideManager {
    @discardableResult func activateOverride(
        preset: OverridePresetsSnapshot,
        fromSavedPreset: Bool
    ) async -> OverrideSnapshot? {
        await activateOverride(preset: preset, fromSavedPreset: fromSavedPreset, defaultMaxIOB: nil)
    }
}

actor BaseOverrideManager: OverrideManager, LifetimeOwner, AppService {
    private let overrideStorage: OverrideStorage
    private let nightscoutManager: NightscoutManager

    private let coreDataStorage = CoreDataStorage()

    /// One operation at a time: the storage changes are atomic, but the NS uploads following them must be enqueued
    /// in the same order (the actor is reentrant across the awaits in between).
    private let serializer = TaskSerializer()

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
        await serializer.run {
            guard let cancellation = await overrideStorage.cancelActiveOverride() else { return false }
            await uploadCancellation(cancellation)
            return true
        }
    }

    @discardableResult func activateOverride(
        preset: OverridePresetsSnapshot,
        fromSavedPreset: Bool,
        defaultMaxIOB: Decimal?
    ) async -> OverrideSnapshot? {
        await serializer.run {
            guard let result = await overrideStorage.activateOverrideFromPreset(
                preset: preset,
                fromSavedPreset: fromSavedPreset,
                defaultMaxIOB: defaultMaxIOB
            ) else { return nil }

            if let replaced = result.replaced {
                await uploadCancellation(replaced)
            }
            await uploadActivation(result.activated)
            return result.activated
        }
    }

    /// Only cancels when `expected` is still the active override: the auto-cancel checks run across awaits, so an
    /// overlapping pass may have ended it (and started its successor), or the user may have replaced it.
    private func cancelOverride(expected: OverrideSnapshot) async -> Bool {
        guard let cancellation = await overrideStorage.cancelActiveOverride(expected: expected) else { return false }
        await uploadCancellation(cancellation)
        return true
    }

    private func uploadCancellation(_ cancellation: OverrideCancellation) async {
        let override = cancellation.override
        let name = await getOverrideName(for: override)
        await nightscoutManager.uploadOverride(name, cancellation.duration, override.date ?? Date.now)

        // The projected successor entry is obsolete either way: the successor either never runs, or
        // is uploaded again with its real start date when it gets activated.
        if let projectedStart = override.succeedingStart {
            await nightscoutManager.deleteOverride(at: projectedStart)
        }
    }

    private func uploadActivation(_ activated: OverrideSnapshot) async {
        let name = await getOverrideName(for: activated)
        await nightscoutManager.uploadOverride(name, uploadDuration(of: activated), activated.date ?? Date.now)

        // Show the scheduled successor in Nightscout right away
        if let successor = await scheduledSuccessor(of: activated) {
            await uploadProjection(of: successor)
        }
    }

    private func uploadProjection(of successor: (preset: OverridePresetsSnapshot, start: Date)) async {
        await nightscoutManager.uploadOverride(
            successor.preset.name ?? "",
            successor.preset.indefinite ? 0 : Double(successor.preset.duration ?? 0),
            successor.start
        )
    }

    func updateOverridePreset(_ draft: OverridePresetsSnapshot) async {
        await serializer.run {
            await overrideStorage.updateOverridePreset(draft)
            await syncProjectedSuccessor(changedPresets: [draft.id])
        }
    }

    func deleteOverridePresets(ids: [String]) async {
        await serializer.run {
            await overrideStorage.deleteOverridePresets(ids: ids)
            await syncProjectedSuccessor(changedPresets: Set(ids))
        }
    }

    /// The projected successor entry in NS mirrors the preset: re-upload it (NS replaces the entry at the same
    /// created_at) or, when the preset is gone, delete it - the successor won't run.
    private func syncProjectedSuccessor(changedPresets: Set<String>) async {
        guard let active = await overrideStorage.fetchCurrentActiveOverride(),
              let id = active.succeeding, changedPresets.contains(id),
              let start = active.succeedingStart
        else { return }

        if let successor = await scheduledSuccessor(of: active) {
            await uploadProjection(of: successor)
        } else {
            await nightscoutManager.deleteOverride(at: start)
        }
    }

    func autoCancelOverrideIfNeeded() async {
        await serializer.run {
            await performAutoCancelIfNeeded()
        }
    }

    private func performAutoCancelIfNeeded() async {
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

        // Ending the override and activating its successor is one storage change: an app termination can't end it
        // without starting the successor. Neither happens when another override got activated in the meantime.
        if let successor = await scheduledSuccessor(of: activeOverride) {
            guard let result = await overrideStorage.activateOverrideFromPreset(
                preset: successor.preset,
                fromSavedPreset: true,
                ifActive: .replaceIfStill(activeOverride)
            ) else { return false }
            debug(.apsManager, "Override ended, duration: \(duration) minutes")
            debug(.apsManager, "Succeeding override \(successor.preset.name ?? "") activated")
            if let replaced = result.replaced {
                await uploadCancellation(replaced)
            }
            await uploadActivation(result.activated)
            return true
        }

        guard await cancelOverride(expected: activeOverride) else { return false }
        debug(.apsManager, "Override ended, duration: \(duration) minutes")
        return true
    }

    private func scheduledSuccessor(of override: OverrideSnapshot) async -> (preset: OverridePresetsSnapshot, start: Date)? {
        guard let start = override.succeedingStart,
              let id = override.succeeding,
              let preset = await overrideStorage.fetchOverridePreset(id: id)
        else { return nil }
        return (preset, start)
    }

    /// 0 = indefinite (uploaded as 48h)
    private func uploadDuration(of override: OverrideSnapshot) -> Double {
        override.indefinite ? 0 : Double(override.duration ?? 0)
    }

    private func cancelOverrideAfterCarbsIfApplicable(_ activeOverride: OverrideSnapshot) async -> Bool {
        guard activeOverride.endWIthNewCarbs, let overrideStarted = activeOverride.date else { return false }
        // TODO: should we cancel on ANY meal (as before) or only when carbs are announced?
        guard let recent = await coreDataStorage.recentMeal(), !recent.isEmpty,
              let mealDate = recent.actualDate else { return false }
        guard mealDate > overrideStarted else { return false }

        guard await cancelOverride(expected: activeOverride) else { return false }

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

        guard await cancelOverride(expected: activeOverride) else { return false }

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

        guard await cancelOverride(expected: activeOverride) else { return false }

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
