import Combine

enum PumpConfig {
    enum Config {}
}

protocol PumpConfigProvider: Provider {
    func rileyDisplayStates() -> AnyPublisher<[RileyDisplayState], Never>
}
