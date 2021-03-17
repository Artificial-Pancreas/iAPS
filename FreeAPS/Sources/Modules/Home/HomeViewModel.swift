import SwiftDate
import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var settingsManager: SettingsManager!

        private(set) var filteredHours = 24

        @Published var glucose: [BloodGlucose] = []
        @Published var suggestion: Suggestion?
        @Published var recentGlucose: BloodGlucose?
        @Published var glucoseDelta: Int?
        @Published var basals: [PumpHistoryEvent] = []

        @Published var allowManualTemp = false
        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            setupGlucose()
            setupBasals()
            suggestion = provider.suggestion
            units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
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
            filteredHours = hours
        }

        private func setupGlucose() {
            glucose = provider.filteredGlucose(hours: filteredHours)
            recentGlucose = glucose.last
            if glucose.count >= 2 {
                glucoseDelta = (recentGlucose?.glucose ?? 0) - (glucose[glucose.count - 2].glucose ?? 0)
            } else {
                glucoseDelta = nil
            }
        }

        private func setupBasals() {
            basals = provider.pumpHistory(hours: filteredHours).filter {
                $0.type == .tempBasal || $0.type == .tempBasalDuration
            }
        }
    }
}

extension Home.ViewModel: GlucoseObserver, SuggestionObserver, SettingsObserver, PumpHistoryObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        self.suggestion = suggestion
    }

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupBasals()
    }
}
