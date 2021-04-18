import SwiftUI

extension AddCarbs {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AddCarbsProvider {
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var settingsManager: SettingsManager!
        @Injected() var apsManager: APSManager!
        @Published var carbs: Decimal = 0
        @Published var date = Date()

        override func subscribe() {}

        func add() {
            guard carbs > 0 else {
                showModal(for: nil)
                return
            }

            carbsStorage.storeCarbs([
                CarbsEntry(createdAt: date, carbs: carbs, enteredBy: CarbsEntry.manual)
            ])

            if settingsManager.settings.skipBolusScreenAfterCarbs ?? false {
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else {
                showModal(for: .bolus(waitForDuggestion: true))
            }
        }
    }
}
