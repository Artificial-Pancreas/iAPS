import SwiftUI

extension CGM {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: CGMProvider {
        @Injected() var settingsManager: SettingsManager!

        @Published var cgm: CGMType = .nightscout

        override func subscribe() {
            cgm = settingsManager.settings.cgm ?? .nightscout

            $cgm
                .removeDuplicates()
                .sink { [weak self] value in
                    self?.settingsManager.settings.cgm = value
                }
                .store(in: &lifetime)
        }
    }
}
