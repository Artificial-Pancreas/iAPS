import SwiftUI

extension AddCarbs {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AddCarbsProvider {
        @Injected() var carbsStorage: CarbsStorage!
        @Published var carbs: Decimal = 0
        @Published var date = Date()

        override func subscribe() {}

        func add() {
            carbsStorage.storeCarbs([
                CarbsEntry(createdAt: date, carbs: carbs, enteredBy: CarbsEntry.manual)
            ])
            showModal(for: nil)
        }
    }
}
