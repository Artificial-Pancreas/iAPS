import SwiftUI

extension CGM {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: CGMProvider {
        @Injected() var settingsManager: SettingsManager!

        @Published var cgm: CGMType = .nightscout
        @Published var transmitterID = ""
        @Published var uploadGlucose = false

        override func subscribe() {
            cgm = settingsManager.settings.cgm ?? .nightscout
            uploadGlucose = settingsManager.settings.uploadGlucose ?? false
            transmitterID = UserDefaults.standard.dexcomTransmitterID ?? ""

            $cgm
                .removeDuplicates()
                .sink { [weak self] value in
                    self?.settingsManager.settings.cgm = value
                }
                .store(in: &lifetime)

            $uploadGlucose
                .removeDuplicates()
                .sink { [weak self] value in
                    self?.settingsManager.settings.uploadGlucose = value
                }
                .store(in: &lifetime)
        }

        func onChangeID() {
            UserDefaults.standard.dexcomTransmitterID = transmitterID
        }
    }
}
