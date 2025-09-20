import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!

        @Published var pumpSetupPresented: Bool = false
        @Published private(set) var pumpIdentifierToSetUp: String? = nil
        @Published private(set) var pumpManagerStatus: PumpManagerStatus? = nil

        private(set) var initialSettings: PumpInitialSettings = .default
        @Published var alertNotAck: Bool = false

        override func subscribe() {
            alertNotAck = provider.initialAlertNotAck()
            provider.alertNotAck
                .receive(on: DispatchQueue.main)
                .assign(to: \.alertNotAck, on: self)
                .store(in: &lifetime)

            deviceManager.pumpManagerStatus
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpManagerStatus, on: self)
                .store(in: &lifetime)

            let basalSchedule = BasalRateSchedule(
                dailyItems: provider.basalProfile().map {
                    RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                }
            )

            let pumpSettings = provider.pumpSettings()

            initialSettings = PumpInitialSettings(
                maxBolusUnits: Double(pumpSettings.maxBolus),
                maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                basalSchedule: basalSchedule!
            )
        }

        func setupPump(_ identifier: String?) {
            pumpIdentifierToSetUp = identifier
            pumpSetupPresented = identifier != nil
        }

        func ack() {
            provider.deviceManager.alertHistoryStorage.forceNotification()
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task { @MainActor in
            setupPump(nil)
        }
    }
}
