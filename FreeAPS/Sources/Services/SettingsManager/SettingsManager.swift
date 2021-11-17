import Foundation
import Swinject

protocol SettingsManager {
    var settings: FreeAPSSettings { get set }
    var preferences: Preferences { get }
}

protocol SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings)
}

final class BaseSettingsManager: SettingsManager, Injectable {
    @Injected() var broadcaster: Broadcaster!
    @Injected() var storage: FileStorage!

    var settings: FreeAPSSettings {
        didSet {
            if oldValue != settings {
                save()
                DispatchQueue.main.async {
                    self.broadcaster.notify(SettingsObserver.self, on: .main) {
                        $0.settingsDidChange(self.settings)
                    }
                }
            }
        }
    }

    init(resolver: Resolver) {
        let storage = resolver.resolve(FileStorage.self)!
        settings = storage.retrieve(OpenAPS.FreeAPS.settings, as: FreeAPSSettings.self)
            ?? FreeAPSSettings(from: OpenAPS.defaults(for: OpenAPS.FreeAPS.settings))
            ?? FreeAPSSettings()

        injectServices(resolver)
    }

    private func save() {
        storage.save(settings, as: OpenAPS.FreeAPS.settings)
    }

    var preferences: Preferences {
        storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
            ?? Preferences()
    }
}
