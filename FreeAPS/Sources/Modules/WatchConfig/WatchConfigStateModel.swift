import ConnectIQ
import SwiftUI

enum AwConfig: String, JSON, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }
    case HR
    case BGTarget
    case steps
    case isf
    case override

    var displayName: String {
        switch self {
        case .BGTarget:
            return NSLocalizedString("Eventual Glucose", comment: "")
        case .HR:
            return NSLocalizedString("Heart Rate", comment: "")
        case .steps:
            return NSLocalizedString("Steps", comment: "")
        case .isf:
            return NSLocalizedString("ISF", comment: "")
        case .override:
            return NSLocalizedString("% Override", comment: "")
        }
    }
}

extension WatchConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var garmin: GarminManager!

        @Published var devices: [CodableDevice] = []
        @Published var selectedAwConfig: AwConfig = .HR
        @Published var displayFatAndProteinOnWatch = false
        @Published var confirmBolusFaster = false
        @Published var profilesOrTempTargets = false

        override func subscribe() async {
            subscribeSetting(\.displayFatAndProteinOnWatch, on: $displayFatAndProteinOnWatch) {
                self.displayFatAndProteinOnWatch = $0 }
            subscribeSetting(\.confirmBolusFaster, on: $confirmBolusFaster) { self.confirmBolusFaster = $0 }
            subscribeSetting(\.profilesOrTempTargets, on: $profilesOrTempTargets) { self.profilesOrTempTargets = $0 }
            subscribeSetting(
                \.displayOnWatch, on: $selectedAwConfig,
                initial: { self.selectedAwConfig = $0 },
                didSet: { value in
                    Task { [weak self] in
                        guard let self else { return }
                        // for compatibility with old displayHR
                        await settingsManager.updateSettings { settings in
                            var updated = settings
                            switch value {
                            case .HR:
                                updated.displayHR = true
                            default:
                                updated.displayHR = false
                            }
                            return updated
                        }
                    }
                }
            )

            devices = garmin.devices
        }

        func selectGarminDevices() {
            Task {
                self.devices = await garmin.selectDevices()
            }
        }

        func deleteGarminDevice() {
            garmin.updateListDevices(devices: devices)
        }
    }
}
