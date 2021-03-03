import Foundation
import Swinject

protocol SettingsManager {
    var settings: FreeAPSSettings { get set }
}

final class BaseFSettingsManager: SettingsManager, Injectable {
    var settings: FreeAPSSettings {
        didSet { save() }
    }

    @Injected() var storage: FileStorage!

    init(resolver: Resolver) {
        let storage = resolver.resolve(FileStorage.self)!
        settings = (try? storage.retrieve(OpenAPS.Settings.freeAPSSettings, as: FreeAPSSettings.self))
            ?? FreeAPSSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.freeAPSSettings))
            ?? FreeAPSSettings(units: .mmolL, closedLoop: false)

        injectServices(resolver)
    }

    private func save() {
        try? storage.save(settings, as: OpenAPS.Settings.freeAPSSettings)
    }
}
