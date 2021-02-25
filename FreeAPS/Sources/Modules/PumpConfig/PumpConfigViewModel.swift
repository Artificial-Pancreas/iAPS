import LoopKitUI
import SwiftUI

extension PumpConfig {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: PumpConfigProvider {
        @Published var setupPump = false
        private(set) var setupPumpType: PumpType = .minimed
        @Published var pumpState: PumpDisplayState?

        override func subscribe() {
            provider.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpState, on: self)
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

extension PumpConfig.ViewModel: PumpManagerSetupViewControllerDelegate {
    func pumpManagerSetupViewController(_: PumpManagerSetupViewController, didSetUpPumpManager pumpManager: PumpManagerUI) {
        provider.setPumpManager(pumpManager)
        setupPump = false
    }
}
