
import SwiftUI
import Swinject

extension Bolus {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() var carbsStorage: CarbsStorage!
        @Published var suggestion: Suggestion?
        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var insulinCalculated: Decimal = 0
        @Published var cRatio: Decimal = 0
        @Published var Isfs: Decimal = 0
        @Published var Carbs: Decimal = 0
        @Published var BZ: Decimal = 0
        @Published var DeltaBZ: Decimal = 0
        @Published var IOB: Decimal = 0
        @Published var overrideFactor: Decimal = 80
        @Published var COB: Decimal = 0
        @Published var glucose: [BloodGlucose] = []
        @Published var recentGlucose: BloodGlucose?
        @Published var waitForSuggestion: Bool = false
        var waitForSuggestionInitial: Bool = false

        override func subscribe() {
            setupInsulinRequired()
            broadcaster.register(SuggestionObserver.self, observer: self)

            if waitForSuggestionInitial {
                apsManager.determineBasal()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] ok in
                        guard let self = self else { return }
                        if !ok {
                            self.waitForSuggestion = false
                            self.insulinRequired = 0
                            self.insulinRecommended = 0
                        }
                    }.store(in: &lifetime)
            }
        }

        func updateBZ() {
            let glucose = glucoseStorage.recent()
            guard glucose.count >= 3 else { return }

            let lastGlucose = glucose.last!
            let glucoseValue = lastGlucose.glucose!
            let thirdLastGlucose = glucose[glucose.count - 3]
            let delta = Decimal(lastGlucose.glucose!) - Decimal(thirdLastGlucose.glucose!)

            BZ = Decimal(glucoseValue) // Update BZ with the current glucose value
            DeltaBZ = delta
        }

        func updateCarbs() {
            suggestion = provider.suggestion
        }

        func calculateBolus() {
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)

            // defining CarbRatios for me.....
            if hour >= 0, hour < 5 {
                cRatio = 12
            } else if hour >= 5, hour < 8 {
                cRatio = 7
            } else if hour >= 8, hour < 10 {
                cRatio = 10
            } else {
                cRatio = 12
            }
        }

        func add() {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            let maxAmount = Double(min(amount, provider.pumpSettings().maxBolus))

            unlockmanager.unlock()
                .sink { _ in } receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.apsManager.enactBolus(amount: maxAmount, isSMB: false)
                    self.showModal(for: nil)
                }
                .store(in: &lifetime)
        }

        func addWithoutBolus() {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            pumpHistoryStorage.storeEvents(
                [
                    PumpHistoryEvent(
                        id: UUID().uuidString,
                        type: .bolus,
                        timestamp: Date(),
                        amount: amount,
                        duration: nil,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil
                    )
                ]
            )
            showModal(for: nil)
        }

        func setupInsulinRequired() {
            DispatchQueue.main.async {
                self.insulinRequired = self.provider.suggestion?.insulinReq ?? 0
                self.calculateBolus()
                self.updateBZ()
                self.updateCarbs()
            }
        }
    }
}

extension Bolus.StateModel: SuggestionObserver {
    func suggestionDidUpdate(_: Suggestion) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
        setupInsulinRequired()
    }
}
