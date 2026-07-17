import LoopKit
import LoopKitUI
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() private var alertHistoryStorage: AlertHistoryStorage!

        private let coreDataStorage = CoreDataStorage()

        @Published var pumpSetupPresented: Bool = false
        @Published var pumpSettingsPresented: Bool = false
        @Published private(set) var pumpIdentifierToSetUp: String? = nil

        private(set) var initialSettings: PumpInitialSettings = .default

        override func subscribe() async {
            let basalProfile = appCoordinator.basalProfile.value

            let concentration = await readConcentration()
            let basalSchedule = BasalRateSchedule(
                dailyItems: basalProfile.map {
                    $0.toLoopKit(concentration: concentration)
                }
            )

            let pumpSettings = await settingsManager.pumpSettings

            initialSettings = PumpInitialSettings(
                maxBolusUnits: Double(pumpSettings.maxBolus),
                maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                basalSchedule: basalSchedule ?? PumpInitialSettings.default.basalSchedule
            )
        }

        private func readConcentration() async -> Double {
            await coreDataStorage.insulinConcentration().concentration
        }

        func showCurrentPumpSettings() {
            pumpIdentifierToSetUp = nil
            pumpSettingsPresented = true
            pumpSetupPresented = false
        }

        func setupNewPump(_ identifier: String) {
            pumpIdentifierToSetUp = identifier
            pumpSettingsPresented = false
            pumpSetupPresented = true
        }

        func removePump() {
            Task {
                await deviceManager.removePump()
            }
        }

        func ack() {
            alertHistoryStorage.forceNotification()
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task { @MainActor in
            pumpSetupPresented = false
            pumpSettingsPresented = false
            pumpIdentifierToSetUp = nil
        }
    }
}
