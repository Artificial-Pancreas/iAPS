import LoopKit
import LoopKitUI
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() private var alertHistoryStorage: AlertHistoryStorage!
        @Injected() private var appCoordinator: AppCoordinator!
        @Injected() private var storage: FileStorage!

        @Published var pumpSetupPresented: Bool = false
        @Published var pumpSettingsPresented: Bool = false
        @Published private(set) var pumpIdentifierToSetUp: String? = nil
        @Published private(set) var pumpInfo: PumpDisplayInfo? = nil
        @Published private(set) var pumpManagerStatus: PumpDisplayStatus? = nil

        private(set) var initialSettings: PumpInitialSettings = .default
        @Published var alertNotAck: Bool = false

        override func subscribe() async {
            pumpInfo = appCoordinator.pumpInfo.value
            pumpManagerStatus = appCoordinator.pumpStatus.value

            alertNotAck = await alertHistoryStorage.recentNotAck().isNotEmpty

            observe(appCoordinator.alertNotAckUpdates) { alertNotAck in
                await self.alertNotAckUpdated(alertNotAck)
            }
            observe(appCoordinator.pumpInfo) { pumpInfo in
                await self.pumpInfoUpdated(pumpInfo)
            }
            observe(appCoordinator.pumpStatus) { pumpStatus in
                await self.pumpStatusUpdated(pumpStatus)
            }

            let basalProfile = await fetchBasalProfile()
            let basalSchedule = BasalRateSchedule(
                dailyItems: basalProfile.map {
                    RepeatingScheduleValue(startTime: Double($0.minutes) * 60, value: Double($0.rate))
                }
            )

            let pumpSettings = await settingsManager.pumpSettings

            initialSettings = PumpInitialSettings(
                maxBolusUnits: Double(pumpSettings.maxBolus),
                maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                basalSchedule: basalSchedule! // TODO: we're force-unwrapping the value, it works but we should fix this
            )
        }

        private func alertNotAckUpdated(_ alertNotAck: Bool) {
            self.alertNotAck = alertNotAck
        }

        private func pumpInfoUpdated(_ info: PumpDisplayInfo?) {
            pumpInfo = info
        }

        private func pumpStatusUpdated(_ status: PumpDisplayStatus?) {
            pumpManagerStatus = status
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
            Task {
                await alertHistoryStorage.forceNotification()
            }
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
