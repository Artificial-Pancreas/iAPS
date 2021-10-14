import SwiftUI

extension CGM {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: CGMProvider {
        @Injected() var settingsManager: SettingsManager!

        @Published var cgm: CGMType = .nightscout
        @Published var transmitterID: String = ""

        override func subscribe() {
            cgm = settingsManager.settings.cgm ?? .nightscout
            transmitterID = UserDefaults.standard.dexcomTransmitterID ?? ""

            $cgm
                .removeDuplicates()
                .sink { [weak self] value in
                    self?.settingsManager.settings.cgm = value
                }
                .store(in: &lifetime)
        }

        func onChangeID() {
            UserDefaults.standard.dexcomTransmitterID = transmitterID
        }
    }
}
