import SwiftUI

extension AutotuneConfig {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AutotuneConfigProvider {
        @Injected() var settingsManager: SettingsManager!
        @Published var useAutotune = false
        @Published var autotune: Autotune?
        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            autotune = provider.autotune
            units = settingsManager.settings.units
            useAutotune = settingsManager.settings.useAutotune

            $useAutotune
                .removeDuplicates()
                .sink { [weak self] use in
                    self?.settingsManager.settings.useAutotune = use
                }
                .store(in: &lifetime)
        }

        func run() {
            provider.runAutotune()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] result in
                    self?.autotune = result
                }.store(in: &lifetime)
        }

        func delete() {
            provider.deleteAutotune()
            autotune = nil
        }
    }
}
