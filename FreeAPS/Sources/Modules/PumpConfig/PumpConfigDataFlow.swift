import Combine
import LoopKitUI

enum PumpConfig {
    enum Config {}

    enum PumpType: Equatable {
        case minimed
        case omnipod
    }
}

protocol PumpConfigProvider: Provider {
    func rileyDisplayStates() -> AnyPublisher<[RileyDisplayState], Never>
    var setupDelegate: PumpManagerSetupViewControllerDelegate { get }
}
