import SwiftDate
import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var history: PumpHistoryStorage!
        @Injected() var temps: TempTargetsStorage!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var broadcaster: Broadcaster!

        @Published var glucose: [BloodGlucose] = []

        override func subscribe() {
            glucose = filteredGlucose(glucoseStorage.recent())
            broadcaster.register(GlucoseObserver.self, observer: self)
        }

        func addCarbs() {
            showModal(for: .addCarbs)
        }

        func runLoop() {
            apsManager.fetchAndLoop()
        }

        func addTempTarget() {
            showModal(for: .addTempTarget)
        }

        func bolus() {
            showModal(for: .bolus)
        }

        private func filteredGlucose(_ glucose: [BloodGlucose]) -> [BloodGlucose] {
            glucose.filter {
                $0.dateString.addingTimeInterval(3.hours.timeInterval) > Date()
            }
        }
    }
}

extension Home.ViewModel: GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose]) {
        self.glucose = filteredGlucose(glucose)
    }
}
