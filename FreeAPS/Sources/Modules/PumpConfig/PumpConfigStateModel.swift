import LoopKit
import LoopKitUI
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() private var alertHistoryStorage: AlertHistoryStorage!
        @Injected() private var storage: FileStorage!

        private let coreDataStorage = CoreDataStorage()

        @Published var pumpSetupPresented: Bool = false
        @Published var pumpSettingsPresented: Bool = false
        @Published private(set) var pumpIdentifierToSetUp: String? = nil

        private(set) var initialSettings: PumpInitialSettings = .default

        override func subscribe() async {
            let basalProfile = await fetchBasalProfile()
            let concentration = readConcentration()
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

        private func readConcentration() -> Double {
            coreDataStorage.insulinConcentration().concentration
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

        func ack() {
            alertHistoryStorage.forceNotification()
        }

        private func fetchBasalProfile() async -> [BasalProfileEntry] {
            await storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
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
