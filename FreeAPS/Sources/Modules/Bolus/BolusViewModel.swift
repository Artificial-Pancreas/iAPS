import SwiftUI

extension Bolus {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: BolusProvider {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Published var amount: Decimal = 0

        override func subscribe() {}

        func add() {
            guard amount > 0 else { return }
            unlockmanager.unlock()
                .sink { _ in } receiveValue: {
                    self.apsManager.enactBolus(amount: Double(self.amount))
                    self.showModal(for: nil)
                }
                .store(in: &lifetime)
        }
    }
}
