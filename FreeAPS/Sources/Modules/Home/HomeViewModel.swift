import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var history: PumpHistoryStorage!
        @Injected() var temps: TempTargetsStorage!

        func addCarbs() {
            history.storeJournalCarbs(15)
        }

        func runLoop() {
            apsManager.loop()
        }

        func addHighTempTarget() {
            temps
                .storeTempTargets([TempTarget(
                    id: UUID().uuidString,
                    createdAt: Date(),
                    targetTop: 126,
                    targetBottom: 126,
                    duration: 10
                )])
        }

        func addLowTempTarget() {
            temps
                .storeTempTargets([TempTarget(
                    id: UUID().uuidString,
                    createdAt: Date(),
                    targetTop: 81,
                    targetBottom: 81,
                    duration: 10
                )])
        }
    }
}
