import SwiftDate
import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var settingsManager: SettingsManager!

        private(set) var filteredGlucoseHours = 24

        @Published var glucose: [BloodGlucose] = []
        @Published var suggestion: Suggestion?
        @Published var recentGlucose: BloodGlucose?
        @Published var glucoseDelta: Int?

        @Published var allowManualTemp = false
        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            setupGlucose()
            suggestion = provider.suggestion
            units = settingsManager.settings.units
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

        func setFilteredGlucoseHours(hours: Int) {
            filteredGlucoseHours = hours
        }

        private func setupGlucose() {
            glucose = provider.filteredGlucose(hours: filteredGlucoseHours)
            recentGlucose = glucose.last
            if glucose.count >= 2 {
                glucoseDelta = (recentGlucose?.glucose ?? 0) - (glucose[glucose.count - 2].glucose ?? 0)
            } else {
                glucoseDelta = nil
            }
        }
    }
}

extension Home.ViewModel: GlucoseObserver, SuggestionObserver, SettingsObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        self.suggestion = suggestion
    }

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
    }
}
