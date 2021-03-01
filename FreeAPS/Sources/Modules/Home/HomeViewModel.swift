import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var history: PumpHistoryStorage!

        func runOpenAPS() {
            apsManager.runTest()
        }

        func makeProfiles() {
            apsManager.makeProfiles()
        }

        func fetchGlucose() {
            apsManager.fetchLastGlucose()
        }

        func addCarbs() {
            history.storeJournalCarbs(15)
        }

        func runLoop() {
            apsManager.loop()
        }
    }
}
