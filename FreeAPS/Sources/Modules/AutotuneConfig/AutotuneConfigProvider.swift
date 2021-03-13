import Combine

extension AutotuneConfig {
    final class Provider: BaseProvider, AutotuneConfigProvider {
        @Injected() private var apsManager: APSManager!

        var autotune: Autotune? {
            try? storage.retrieve(OpenAPS.Settings.autotune, as: Autotune.self)
        }

        func runAutotune() -> AnyPublisher<Autotune?, Never> {
            apsManager.autotune()
        }

        func deleteAutotune() {
            try? storage.remove(OpenAPS.Settings.autotune)
        }
    }
}
