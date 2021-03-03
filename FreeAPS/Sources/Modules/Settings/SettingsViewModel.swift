import SwiftUI

extension Settings {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: SettingsProvider {
        @Injected() private var settingsManager: SettingsManager!
        @Published var closedLoop = false

        override func subscribe() {
            closedLoop = settingsManager.settings.closedLoop

            $closedLoop
                .removeDuplicates()
                .sink { [weak self] value in
                    self?.settingsManager.settings.closedLoop = value
                }.store(in: &lifetime)
        }
    }
}
