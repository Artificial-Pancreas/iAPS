import Combine
import LoopKitUI
import RileyLinkBLEKit

extension PumpConfig {
    final class Provider: BaseProvider, PumpConfigProvider {
        @Injected() var apsManager: APSManager!

        func setPumpManager(_ manager: PumpManagerUI) {
            apsManager.setPumpManager(manager)
        }

        var pumpDisplayState: AnyPublisher<PumpDisplayState?, Never> {
            apsManager.pumpDisplayState.eraseToAnyPublisher()
        }
    }
}
