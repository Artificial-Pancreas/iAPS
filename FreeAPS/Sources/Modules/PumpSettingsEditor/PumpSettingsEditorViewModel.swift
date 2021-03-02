import SwiftUI

extension PumpSettingsEditor {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: PumpSettingsEditorProvider {
        @Published var maxBasal = 0.0
        @Published var maxBolus = 0.0
        @Published var dia = 0.0

        @Published var syncInProgress = false

        override func subscribe() {
            let settings = provider.settings()
            maxBasal = Double(settings.maxBasal)
            maxBolus = Double(settings.maxBolus)
            dia = Double(settings.insulinActionCurve)
        }

        func save() {
            syncInProgress = true
            let settings = PumpSettings(
                insulinActionCurve: Decimal(dia),
                maxBolus: Decimal(maxBolus),
                maxBasal: Decimal(maxBasal)
            )
            provider.save(settings: settings)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    self.syncInProgress = false
                } receiveValue: {}
                .store(in: &lifetime)
        }
    }
}
