import ConnectIQ
import SwiftUI

enum AwConfig: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case HR
    case BGTarget
    case steps
    case isf

    var displayName: String {
        switch self {
        case .BGTarget:
            return NSLocalizedString("Glucose Target", comment: "")
        case .HR:
            return NSLocalizedString("Heart Rate", comment: "")
        case .steps:
            return NSLocalizedString("Steps", comment: "")
        case .isf:
            return NSLocalizedString("ISF", comment: "")
        }
    }
}

extension WatchConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!
        @Published var devices: [IQDevice] = []
        @Published var selectedAwConfig: AwConfig = .HR

        private(set) var preferences = Preferences()

        override func subscribe() {
            preferences = provider.preferences

            subscribeSetting(\.displayOnWatch, on: $selectedAwConfig) { selectedAwConfig = $0 }
            didSet: { [weak self] value in
                // for compatibility with old displayHR
                switch value {
                case .HR:
                    self?.settingsManager.settings.displayHR = true
                default:
                    self?.settingsManager.settings.displayHR = false
                }
            }

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
