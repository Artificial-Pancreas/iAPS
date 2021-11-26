import SwiftUI

extension AddCarbs {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var apsManager: APSManager!
        @Published var carbs: Decimal = 0
        @Published var date = Date()
        @Published var carbsRequired: Decimal?

        override func subscribe() {
            carbsRequired = provider.suggestion?.carbsReq
        }

        func add() {
            guard carbs > 0 else {
                showModal(for: nil)
                return
            }

            carbsStorage.storeCarbs([
                CarbsEntry(createdAt: date, carbs: carbs, enteredBy: CarbsEntry.manual)
            ])

            if settingsManager.settings.skipBolusScreenAfterCarbs {
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else {
                showModal(for: .bolus(waitForSuggestion: true))
            }
        }
    }
}
