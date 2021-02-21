import Combine

enum PumpConfig {
    enum Config {}

    enum PumpType: Equatable {
        case minimed
        case omnipod
    }
}

protocol PumpConfigProvider: Provider {
    func rileyDisplayStates() -> AnyPublisher<[RileyDisplayState], Never>
}
