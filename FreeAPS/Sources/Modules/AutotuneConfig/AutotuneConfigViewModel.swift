import Combine
import SwiftUI

extension AutotuneConfig {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AutotuneConfigProvider {
        @Injected() var settingsManager: SettingsManager!
        @Injected() var apsManager: APSManager!
        @Published var useAutotune = false
        @Published var autotune: Autotune?
        private(set) var units: GlucoseUnits = .mmolL
        @Published var publishedDate = Date()
        @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date() {
            didSet {
                publishedDate = lastAutotuneDate
            }
        }

        override func subscribe() {
            autotune = provider.autotune
            units = settingsManager.settings.units
            useAutotune = settingsManager.settings.useAutotune
            publishedDate = lastAutotuneDate

            $useAutotune
                .removeDuplicates()
                .flatMap { use -> AnyPublisher<Bool, Never> in
                    self.settingsManager.settings.useAutotune = use
                    return self.apsManager.makeProfiles()
                }
                .sink { _ in }
                .store(in: &lifetime)
        }

        func run() {
            provider.runAutotune()
                .receive(on: DispatchQueue.main)
                .flatMap { result -> AnyPublisher<Bool, Never> in
                    self.autotune = result
                    return self.apsManager.makeProfiles()
                }
                .sink { _ in
                    self.lastAutotuneDate = Date()
                }.store(in: &lifetime)
        }

        func delete() {
            provider.deleteAutotune()
            autotune = nil
            apsManager.makeProfiles()
                .sink { _ in }
                .store(in: &lifetime)
        }
    }
}
