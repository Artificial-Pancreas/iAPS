import SwiftUI

extension AddCarbs {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AddCarbsProvider {
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var apsManager: APSManager!
        @Published var carbs: Decimal = 0
        @Published var date = Date()

        override func subscribe() {}

        func add() {
            carbsStorage.storeCarbs([
                CarbsEntry(createdAt: date, carbs: carbs, enteredBy: CarbsEntry.manual)
            ])
            apsManager.determineBasal().sink { _ in }.store(in: &lifetime)
            showModal(for: nil)
        }
    }
}
