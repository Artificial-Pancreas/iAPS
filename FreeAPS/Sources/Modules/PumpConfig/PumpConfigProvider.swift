import Combine
import RileyLinkBLEKit

extension PumpConfig {
    final class Provider: BaseProvider, PumpConfigProvider {
        @Injected() var apsManager: APSManager!

        var deviceProvider: RileyLinkDeviceProvider { apsManager.deviceProvider }

        func rileyDisplayStates() -> AnyPublisher<[RileyDisplayState], Never> {
            apsManager.rileyDisplayStates.eraseToAnyPublisher()
        }
    }
}
