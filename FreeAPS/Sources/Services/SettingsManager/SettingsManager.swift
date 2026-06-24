import Foundation
import LoopKit
import Swinject

protocol SettingsManager: AnyObject, Sendable {
    var settings: FreeAPSSettings { get async }
    var preferences: Preferences { get async }
    var pumpSettings: PumpSettings { get async }

    func updateInsulinCurve(_ insulinType: InsulinType?) async
    func updateSettings(_ settings: FreeAPSSettings) async
    @discardableResult func updateSettings(_ update: @Sendable(FreeAPSSettings) -> FreeAPSSettings) async -> FreeAPSSettings
    func updatePumpSettings(_ settings: PumpSettings) async
    func updatePreferences(_ settings: Preferences) async

    /// forces a re-read from files
    func resetCachedSettings() async
}

// protocol SettingsObserver {
//    func settingsDidChange(_: FreeAPSSettings)
// }

extension InsulinType: @retroactive @unchecked Sendable {}

actor BaseSettingsManager: SettingsManager, AppService {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    private var cachedSettings: FreeAPSSettings?
    private var cachedPreferences: Preferences?
    private var cachedPumpSettings: PumpSettings?

    var settings: FreeAPSSettings {
        get async {
            if let cachedSettings {
                return cachedSettings
            }
            let retrievedSettings = await storage.retrieve(OpenAPS.FreeAPS.settings, as: FreeAPSSettings.self)
                ?? FreeAPSSettings(from: OpenAPS.defaults(for: OpenAPS.FreeAPS.settings))
                ?? FreeAPSSettings()
            cachedSettings = retrievedSettings
            return retrievedSettings
        }
    }

    var preferences: Preferences {
        get async {
            if let cachedPreferences {
                return cachedPreferences
            }
            let retrievedPreferences = await storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
                ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                ?? Preferences()
            cachedPreferences = retrievedPreferences
            return retrievedPreferences
        }
    }

    var pumpSettings: PumpSettings {
        get async {
            if let cachedPumpSettings {
                return cachedPumpSettings
            }
            let retrievedPumpSettings = await storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 4)
            cachedPumpSettings = retrievedPumpSettings
            return retrievedPumpSettings
        }
    }

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called on app start, before anything is rendered
    func start() async {
        await updateAppCoordinator()
    }

    func resetCachedSettings() async {
        cachedSettings = nil
        cachedPreferences = nil
        cachedPumpSettings = nil
        await updateAppCoordinator()
    }

    private func updateAppCoordinator() async {
        let settings = await self.settings
        self.appCoordinator.setSettings(settings)
        let pumpSettings = await self.pumpSettings
        self.appCoordinator.setPumpSettings(pumpSettings)
        let preferences = await self.preferences
        self.appCoordinator.setPreferences(preferences)
    }

    func updateInsulinCurve(_ insulinType: InsulinType?) async {
        var prefs = await self.preferences

        switch insulinType {
        case .apidra,
             .humalog,
             .novolog:
            prefs.curve = .rapidActing

        case .fiasp,
             .lyumjev:
            prefs.curve = .ultraRapid
        default:
            prefs.curve = .rapidActing
        }
        await updatePreferences(prefs)
    }

    func updateSettings(_ settings: FreeAPSSettings) async {
        if self.cachedSettings != settings {
            self.cachedSettings = settings
            await storage.save(settings, as: OpenAPS.FreeAPS.settings)
            self.appCoordinator.setSettings(settings)
        }
    }

    @discardableResult func updateSettings(_ update: @Sendable(FreeAPSSettings) -> FreeAPSSettings) async -> FreeAPSSettings {
        let updated = update(await settings)
        await updateSettings(updated)
        return updated
    }

    func updatePumpSettings(_ settings: PumpSettings) async {
        if self.cachedPumpSettings != settings {
            self.cachedPumpSettings = settings
            await storage.save(settings, as: OpenAPS.Settings.settings)
            self.appCoordinator.setPumpSettings(settings)
        }
    }

    func updatePreferences(_ preferences: Preferences) async {
        if self.cachedPreferences != preferences {
            self.cachedPreferences = preferences
            await storage.save(preferences, as: OpenAPS.Settings.preferences)
            self.appCoordinator.setPreferences(preferences)
        }
    }
}
