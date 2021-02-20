import SwiftUI

extension PumpConfig {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: PumpConfigProvider {
        @Published var rileyDisplayStates: [RileyDisplayState] = []

        override func subscribe() {
            provider.rileyDisplayStates()
                .receive(on: DispatchQueue.main)
                .assign(to: \.rileyDisplayStates, on: self)
                .store(in: &lifetime)
        }
    }
}
