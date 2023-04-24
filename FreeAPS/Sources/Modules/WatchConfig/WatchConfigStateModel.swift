import ConnectIQ
import SwiftUI

enum AwConfig: String, CaseIterable, Identifiable {
    var id: Self { self }
    case HR = "Heart Rate"
    case BGTarget = "Glucose Target"
}

extension WatchConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!
        @Published var devices: [IQDevice] = []
        @Published var selectedAwConfig: AwConfig = .HR
        @Published var displayHR = false

        private(set) var preferences = Preferences()

        override func subscribe() {
            preferences = provider.preferences
            switch settingsManager.settings.displayHR {
            case true:
                selectedAwConfig = .HR
            case false:
                selectedAwConfig = .BGTarget
            }

            $selectedAwConfig.removeDuplicates()
                .map {
                    switch $0 {
                    case .HR:
                        return true
                    case .BGTarget:
                        return false
                    }
                }
                .sink { [weak self] value in
                    self?.settingsManager.settings.displayHR = value
                }
                .store(in: &lifetime)

            devices = garmin.devices
        }

        func selectGarminDevices() {
            garmin.selectDevices()
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.devices, on: self)
                .store(in: &lifetime)
        }

        func deleteGarminDevice() {
            garmin.updateListDevices(devices: devices)
        }
    }
}
