import SwiftDate
import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var broadcaster: Broadcaster!

        @Published var glucose: [BloodGlucose] = []
        @Published var suggestion: Suggestion?

        override func subscribe() {
            glucose = provider.filteredGlucose()
            suggestion = provider.suggestion
            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
        }

        func addCarbs() {
            showModal(for: .addCarbs)
        }

        func runLoop() {
            provider.fetchAndLoop()
        }

        func addTempTarget() {
            showModal(for: .addTempTarget)
        }

        func manualTampBasal() {
            showModal(for: .manualTempBasal)
        }

        func bolus() {
            showModal(for: .bolus)
        }
    }
}

extension Home.ViewModel: GlucoseObserver, SuggestionObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        glucose = provider.filteredGlucose()
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        self.suggestion = suggestion
    }
}
