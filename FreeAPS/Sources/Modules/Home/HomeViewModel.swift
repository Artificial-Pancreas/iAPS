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
        @Published var tempBasals: [PumpHistoryEvent] = []
        @Published var maxBasal: Decimal = 2
        @Published var basalProfile: [BasalProfileEntry] = []

        @Published var allowManualTemp = false
        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            setupGlucose()
            setupBasals()
            setupPumpSettings()
            setupBasalProfile()
            suggestion = provider.suggestion
            units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
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
            DispatchQueue.main.async {
                self.glucose = self.provider.filteredGlucose(hours: self.filteredHours)
                self.recentGlucose = self.glucose.last
                if self.glucose.count >= 2 {
                    self.glucoseDelta = (self.recentGlucose?.glucose ?? 0) - (self.glucose[self.glucose.count - 2].glucose ?? 0)
                } else {
                    self.glucoseDelta = nil
                }
            }
        }

        private func setupBasals() {
            DispatchQueue.main.async {
                self.tempBasals = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .tempBasal || $0.type == .tempBasalDuration
                }
            }
        }

        private func setupPumpSettings() {
            DispatchQueue.main.async {
                self.maxBasal = self.provider.pumpSettings().maxBasal
            }
        }

        private func setupBasalProfile() {
            DispatchQueue.main.async {
                self.basalProfile = self.provider.basalProfile()
            }
        }
    }
}

extension Home.ViewModel: GlucoseObserver, SuggestionObserver, SettingsObserver, PumpHistoryObserver, PumpSettingsObserver,
    BasalProfileObserver
{
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

    func pumpSettingsDidChange(_: PumpSettings) {
        setupPumpSettings()
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        setupBasalProfile()
    }
}
