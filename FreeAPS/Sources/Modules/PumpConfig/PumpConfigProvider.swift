import Combine

extension PumpConfig {
    final class Provider: BaseProvider, PumpConfigProvider {
        @Injected() var apsManager: APSManager!

        func rileyDisplayStates() -> AnyPublisher<[RileyDisplayState], Never> {
            apsManager.rileyDisplayStates.eraseToAnyPublisher()
        }
    }
}
