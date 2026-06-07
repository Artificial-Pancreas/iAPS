import SwiftUI

extension ManualTempBasal {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var apsManager: APSManager!
        @Injected() private var appCoordinator: AppCoordinator!

        @Published var rate: Decimal = 0
        @Published var durationIndex = 0
        @Published var maxBasalExceeded = false
        @Published var maxBasal: Decimal = 0

        let durationValues = stride(from: 30.0, to: 720.1, by: 30.0).map { $0 }

        override func subscribe() async {
            maxBasal = await settingsManager.pumpSettings.maxBasal

            // TODO: AppUIState instead
            observe(appCoordinator.pumpSettingsUpdates) { me, pumpSettings in
                await me.pumpSettingsUpdated(pumpSettings)
            }
        }

        private func pumpSettingsUpdated(_ pumpSettings: PumpSettings) {
            maxBasal = pumpSettings.maxBasal
        }

        func cancel() {
            Task {
                await apsManager.enactTempBasal(rate: 0, duration: 0)
                showModal(for: nil)
            }
        }

        func enact() {
            guard rate <= maxBasal else {
                maxBasalExceeded = true
                return
            }
            let duration = durationValues[durationIndex]
            Task {
                await apsManager.enactTempBasal(rate: Double(rate), duration: duration * 60)
                showModal(for: nil)
            }
        }
    }
}
