import Combine
import LoopKitUI
import RileyLinkBLEKit

extension PumpConfig {
    final class Provider: BaseProvider, PumpConfigProvider {
        @Injected() var apsManager: APSManager!

        var deviceProvider: RileyLinkDeviceProvider { apsManager.deviceProvider }
        var setupDelegate: PumpManagerSetupViewControllerDelegate { apsManager }

        func rileyDisplayStates() -> AnyPublisher<[RileyDisplayState], Never> {
            apsManager.rileyDisplayStates.eraseToAnyPublisher()
        }
    }
}
