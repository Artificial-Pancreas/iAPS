import SwiftUI
import Swinject

extension Bolus {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: BolusProvider {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var settingsManager: SettingsManager!
        @Injected() var pumpHistotyStorage: PumpHistoryStorage!
        @Published var amount: Decimal = 0
        @Published var inslinRecommended: Decimal = 0
        @Published var inslinRequired: Decimal = 0
        @Published var waitForSuggestion: Bool
        let waitForSuggestionInitial: Bool

        init(provider: Provider, resolver: Resolver, waitForSuggestion: Bool) {
            self.waitForSuggestion = waitForSuggestion
            waitForSuggestionInitial = waitForSuggestion
            super.init(provider: provider, resolver: resolver)
        }

        required init(provider _: Provider, resolver _: Resolver) {
            error(.default, "init(provider:resolver:) has not been implemented")
        }

        override func subscribe() {
            setupInsulinRequired()
            broadcaster.register(SuggestionObserver.self, observer: self)

            if waitForSuggestionInitial {
                apsManager.determineBasal().sink { _ in }.store(in: &lifetime)
            }
        }

        func add() {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            let maxAmount = Double(min(amount, provider.pumpSettings().maxBolus))

            unlockmanager.unlock()
                .sink { _ in } receiveValue: {
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

            pumpHistotyStorage.storeEvents(
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
                self.inslinRequired = self.provider.suggestion?.insulinReq ?? 0
                self.inslinRecommended = self.apsManager
                    .roundBolus(amount: max(self.inslinRequired * (self.settingsManager.settings.insulinReqFraction ?? 0.7), 0))
            }
        }
    }
}

extension Bolus.ViewModel: SuggestionObserver {
    func suggestionDidUpdate(_: Suggestion) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
        setupInsulinRequired()
    }
}
