import SwiftUI

extension ManualTempBasal {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var apsManager: APSManager!
        @Injected() private var appCoordinator: AppCoordinator!

        @Published var rate: Decimal = 0
        @Published var durationIndex = 0
        @Published var maxBasalExceeded = false

        let durationValues = stride(from: 30.0, to: 720.1, by: 30.0).map { $0 }

        func cancel() {
            Task {
                await apsManager.enactTempBasal(rate: 0, duration: 0)
                showModal(for: nil)
            }
        }

        func enact() {
            guard rate <= appCoordinator.pumpSettings.value.maxBasal else {
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
