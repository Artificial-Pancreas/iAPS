import SwiftDate
import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var settingsManager: SettingsManager!

        @Published var glucose: [BloodGlucose] = []
        @Published var suggestion: Suggestion?

        @Published var allowManualTemp = false

        override func subscribe() {
            glucose = provider.filteredGlucose()
            suggestion = provider.suggestion
            allowManualTemp = !settingsManager.settings.closedLoop
            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
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

        func settings() {
            showModal(for: .settings)
        }
    }
}

extension Home.ViewModel: GlucoseObserver, SuggestionObserver, SettingsObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        glucose = provider.filteredGlucose()
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        self.suggestion = suggestion
    }

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
    }
}
