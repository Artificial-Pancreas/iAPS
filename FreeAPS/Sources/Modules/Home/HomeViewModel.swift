import SwiftDate
import SwiftUI

extension Home {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: HomeProvider {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var settingsManager: SettingsManager!
        @Injected() var apsManager: APSManager!
        private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
        private(set) var filteredHours = 24

        @Published var glucose: [BloodGlucose] = []
        @Published var suggestion: Suggestion?
        @Published var enactedSuggestion: Suggestion?
        @Published var recentGlucose: BloodGlucose?
        @Published var glucoseDelta: Int?
        @Published var tempBasals: [PumpHistoryEvent] = []
        @Published var boluses: [PumpHistoryEvent] = []
        @Published var maxBasal: Decimal = 2
        @Published var basalProfile: [BasalProfileEntry] = []
        @Published var tempTargets: [TempTarget] = []
        @Published var carbs: [CarbsEntry] = []
        @Published var timerDate = Date()
        @Published var closedLoop = false
        @Published var isLooping = false
        @Published var statusTitle = ""
        @Published var lastLoopDate: Date = .distantPast
        @Published var tempRate: Decimal?

        @Published var allowManualTemp = false
        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            setupGlucose()
            setupBasals()
            setupBoluses()
            setupPumpSettings()
            setupBasalProfile()
            setupTempTargets()
            setupCarbs()

            suggestion = provider.suggestion
            enactedSuggestion = provider.enactedSuggestion
            units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            closedLoop = settingsManager.settings.closedLoop
            setStatusTitle()

            if closedLoop,
               enactedSuggestion?.deliverAt == suggestion?.deliverAt || (suggestion?.rate == nil && suggestion?.units == nil)
            {
                lastLoopDate = enactedSuggestion?.timestamp ?? .distantPast
            } else {
                lastLoopDate = suggestion?.timestamp ?? .distantPast
            }

            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(EnactedSuggestionObserver.self, observer: self)

            timer.assign(to: \.timerDate, on: self)
                .store(in: &lifetime)

            apsManager.isLooping
                .receive(on: DispatchQueue.main)
                .assign(to: \.isLooping, on: self)
                .store(in: &lifetime)

            apsManager.lastLoopDate
                .receive(on: DispatchQueue.main)
                .assign(to: \.lastLoopDate, on: self)
                .store(in: &lifetime)
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
                let lastTempBasal = Array(self.tempBasals.suffix(2))
                guard lastTempBasal.count == 2 else {
                    self.tempRate = nil
                    return
                }

                guard let lastRate = lastTempBasal[0].rate, let lastDuration = lastTempBasal[1].durationMin else {
                    self.tempRate = nil
                    return
                }
                let lastDate = lastTempBasal[0].timestamp
                guard Date().timeIntervalSince(lastDate.addingTimeInterval(lastDuration.minutes.timeInterval)) < 0 else {
                    self.tempRate = nil
                    return
                }
                self.tempRate = lastRate
            }
        }

        private func setupBoluses() {
            DispatchQueue.main.async {
                self.boluses = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .bolus
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

        private func setupTempTargets() {
            DispatchQueue.main.async {
                self.tempTargets = self.provider.tempTargets(hours: self.filteredHours)
            }
        }

        private func setupCarbs() {
            DispatchQueue.main.async {
                self.carbs = self.provider.carbs(hours: self.filteredHours)
            }
        }

        private func setStatusTitle() {
            guard let suggestion = suggestion else {
                statusTitle = "No suggestion"
                return
            }

            if closedLoop,
               enactedSuggestion?.deliverAt == suggestion.deliverAt || (suggestion.rate == nil && suggestion.units == nil)
            {
                statusTitle = "Enacted"
            } else {
                statusTitle = "Suggested"
            }
        }
    }
}

extension Home.ViewModel:
    GlucoseObserver,
    SuggestionObserver,
    SettingsObserver,
    PumpHistoryObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    CarbsObserver,
    EnactedSuggestionObserver
{
    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }

    func suggestionDidUpdate(_ suggestion: Suggestion) {
        self.suggestion = suggestion
        setStatusTitle()
    }

    func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
        closedLoop = settingsManager.settings.closedLoop
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupBasals()
        setupBoluses()
    }

    func pumpSettingsDidChange(_: PumpSettings) {
        setupPumpSettings()
    }

    func basalProfileDidChange(_: [BasalProfileEntry]) {
        setupBasalProfile()
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTempTargets()
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        setupCarbs()
    }

    func enactedSuggestionDidUpdate(_ suggestion: Suggestion) {
        enactedSuggestion = suggestion
        setStatusTitle()
    }
}
