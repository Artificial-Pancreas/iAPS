import LoopKitUI
import SwiftUI

extension PumpConfig {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: PumpConfigProvider {
        @Published var rileyDisplayStates: [RileyDisplayState] = []
        @Published var setupPump = false
        private(set) var setupPumpType: PumpType = .minimed

        override func subscribe() {
            provider.rileyDisplayStates()
                .receive(on: DispatchQueue.main)
                .assign(to: \.rileyDisplayStates, on: self)
                .store(in: &lifetime)
        }

        func addPump(_ type: PumpType) {
            setupPump = true
            setupPumpType = type
        }
    }
}

extension PumpConfig.ViewModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}
