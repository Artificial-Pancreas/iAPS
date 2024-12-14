import Combine

extension AutotuneConfig {
    final class Provider: BaseProvider, AutotuneConfigProvider {
        @Injected() private var apsManager: APSManager!

        var autotune: Autotune? {
            storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
        }

        func runAutotune() -> AnyPublisher<Autotune?, Never> {
            apsManager.autotune()
        }

        func deleteAutotune() {
            storage.remove(OpenAPS.Settings.autotune)
        }

        var profile: [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }
    }
}
