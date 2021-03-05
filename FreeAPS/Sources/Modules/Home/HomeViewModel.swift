import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var history: PumpHistoryStorage!
        @Injected() var temps: TempTargetsStorage!

        func addCarbs() {
            showModal(for: .addCarbs)
        }

        func runLoop() {
            apsManager.loop()
        }

        func addTempTarget() {
            showModal(for: .addTempTarget)
        }
    }
}
