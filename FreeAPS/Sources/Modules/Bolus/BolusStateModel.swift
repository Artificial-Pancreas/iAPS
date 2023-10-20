
import SwiftUI
import Swinject

extension Bolus {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var settings: SettingsManager!

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
        @Published var COB: Decimal = 0
        @Published var glucose: [BloodGlucose] = []
        @Published var recentGlucose: BloodGlucose?
        @Published var units: GlucoseUnits = .mmolL
        @Published var percentage: Decimal = 0
        @Published var threshold: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var errorString: Decimal = 0
        @Published var evBG: Int = 0
        @Published var insulin: Decimal = 0
        @Published var isf: Decimal = 0
        @Published var iob: Decimal = 0
        @Published var error: Bool = false
        @Published var minGuardBG: Decimal = 0
        @Published var minDelta: Decimal = 0
        @Published var expectedDelta: Decimal = 0
        @Published var minPredBG: Decimal = 0
        @Published var target: Decimal = 0
        @Published var currentBG: Decimal = 0
        @Published var cob: Decimal = 0

        @Published var waitForSuggestion: Bool = false

        var waitForSuggestionInitial: Bool = false

        // new variables
        @Published var InsulinfifteenMinDelta: Decimal = 0
        @Published var bgDependentInsulinCorrection: Decimal = 0
        @Published var insulinWholeCOB: Decimal = 0
        @Published var showIobCalc: Decimal = 0
        @Published var wholeCalc: Decimal = 0
        @Published var roundedWholeCalc: Decimal = 0
        @Published var fraction: Decimal = 0
        @Published var useCalc: Bool = false
        @Published var basal: Decimal = 0
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var useFattyMealCorrectionFactor: Bool = false

        override func subscribe() {
            setupInsulinRequired()
            broadcaster.register(SuggestionObserver.self, observer: self)
            units = settingsManager.settings.units
            percentage = settingsManager.settings.insulinReqPercentage
            threshold = provider.suggestion?.threshold ?? 0
            maxBolus = provider.pumpSettings().maxBolus

            // added
            fraction = settings.settings.overrideFactor
            useCalc = settings.settings.useCalc
            fattyMeals = settings.settings.fattyMeals
            fattyMealFactor = settings.settings.fattyMealFactor

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

        // CALCULATIONS FOR THE BOLUS CALCULATOR
        func calculateInsulin() -> Decimal {
            // more or less insulin because of bg trend in the last 15 minutes
            let fifteenMinDelta = DeltaBZ
            let FactorfifteenMinDelta = (suggestion?.isf ?? 0) / fifteenMinDelta
            InsulinfifteenMinDelta = (1 / FactorfifteenMinDelta)

            // determine how much insulin is needed for the current bg

            let deltaBg = BZ - (suggestion?.current_target ?? 0)
            let bgFactor = (suggestion?.isf ?? 0) / deltaBg
            bgDependentInsulinCorrection = (1 / bgFactor)

            // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
            let wholeCOB = (suggestion?.cob ?? 0) + Carbs
            insulinWholeCOB = wholeCOB / cRatio

            // determine how much the calculator reduces/ increases the bolus because of IOB
            showIobCalc = (-1) * (suggestion?.iob ?? 0)

            // adding all the factors together
            // add a calc for the case that no InsulinfifteenMinDelta is available
            if DeltaBZ != 0 {
                wholeCalc = (bgDependentInsulinCorrection + showIobCalc + insulinWholeCOB + InsulinfifteenMinDelta)
            } else {
                if BZ == 0 {
                    wholeCalc = (showIobCalc + insulinWholeCOB)
                } else {
                    wholeCalc = (bgDependentInsulinCorrection + showIobCalc + insulinWholeCOB)
                }
            }
            let doubleWholeCalc = Double(wholeCalc)
            roundedWholeCalc = Decimal(round(10 * doubleWholeCalc) / 10)

            let normalCalculation = wholeCalc * fraction

            // if meal is fatty bolus will be reduced
            if useFattyMealCorrectionFactor {
                insulinCalculated = normalCalculation * fattyMealFactor
            } else {
                insulinCalculated = normalCalculation
            }
            insulinCalculated = max(insulinCalculated, 0)
            return insulinCalculated
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
            amount = min(amount, maxBolus * 3)

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

                var conversion: Decimal = 1.0
                if self.units == .mmolL {
                    conversion = 0.0555
                }

                self.evBG = self.provider.suggestion?.eventualBG ?? 0
                self.insulin = self.provider.suggestion?.insulinForManualBolus ?? 0
                self.target = self.provider.suggestion?.current_target ?? 0
                self.isf = self.provider.suggestion?.isf ?? 0
                self.iob = self.provider.suggestion?.iob ?? 0
                self.currentBG = (self.provider.suggestion?.bg ?? 0)
                self.cob = self.provider.suggestion?.cob ?? 0
                self.basal = self.provider.suggestion?.rate ?? 0

                if self.settingsManager.settings.insulinReqPercentage != 100 {
                    self.insulinRecommended = self.insulin * (self.settingsManager.settings.insulinReqPercentage / 100)
                } else { self.insulinRecommended = self.insulin }

                self.errorString = self.provider.suggestion?.manualBolusErrorString ?? 0
                if self.errorString != 0 {
                    self.error = true
                    self.minGuardBG = (self.provider.suggestion?.minGuardBG ?? 0) * conversion
                    self.minDelta = (self.provider.suggestion?.minDelta ?? 0) * conversion
                    self.expectedDelta = (self.provider.suggestion?.expectedDelta ?? 0) * conversion
                    self.minPredBG = (self.provider.suggestion?.minPredBG ?? 0) * conversion
                } else { self.error = false }

                self.insulinRecommended = self.apsManager
                    .roundBolus(amount: max(self.insulinRecommended, 0))

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
