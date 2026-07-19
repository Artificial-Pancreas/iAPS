import Foundation

protocol OverrideManager: Sendable {
    @discardableResult func cancelActiveOverride() async -> Bool
}

actor BaseOverrideManager: OverrideManager, LifetimeOwner, AppService {
    private let overrideStorage: OverrideStorage
    private let nightscoutManager: NightscoutManager

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

    func cancelActiveOverride() async -> Bool {
        // Is there a saved Override?
        guard let activeOveride = await overrideStorage.fetchLatestOverride().first, activeOveride.enabled else {
            return false
        }
        let presetName = await getOverrideName(for: activeOveride)
        guard let duration = await overrideStorage.cancelProfile() else {
            return false
        }
        await nightscoutManager.uploadOverride(presetName, duration, activeOveride.date ?? Date.now)
        return true
    }

    private func getOverrideName(for override: OverrideSnapshot) async -> String {
        // Is the Override a Preset?
        if let presetName = await overrideStorage.isPresetName() {
            return presetName
        }

        if override.isPreset { // Because hard coded Hypo treatment isn't actually a preset
            return "📉"
        } else {
            return override.percentage.formatted() != "100" ? override.percentage.formatted() + " %" : "Custom"
        }
    }
}
