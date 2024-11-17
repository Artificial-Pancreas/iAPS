import LoopKit
import SwiftUI
import Swinject

extension Bolus {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        // added for bolus calculator
        @Injected() var settings: SettingsManager!
        @Injected() var nsManager: NightscoutManager!
        @Injected() var announcementStorage: AnnouncementsStorage!

        @Published var suggestion: Suggestion?
        @Published var predictions: Predictions?
        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var units: GlucoseUnits = .mmolL
        @Published var percentage: Decimal = 0
        @Published var threshold: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var errorString: Decimal = 0
        @Published var evBG: Decimal = 0
        @Published var insulin: Decimal = 0
        @Published var isf: Decimal = 0
        @Published var error: Bool = false
        @Published var minPredBG: Decimal = 0
        @Published var minDelta: Decimal = 0
        @Published var expectedDelta: Decimal = 0
        @Published var waitForSuggestion: Bool = false
        @Published var carbRatio: Decimal = 0

        var waitForSuggestionInitial: Bool = false

        // added for bolus calculator
        @Published var recentGlucose: BloodGlucose?
        @Published var target: Decimal = 0
        @Published var cob: Decimal = 0
        @Published var iob: Decimal = 0

        @Published var currentBG: Decimal = 0
        @Published var fifteenMinInsulin: Decimal = 0
        @Published var deltaBG: Decimal = 0
        @Published var targetDifferenceInsulin: Decimal = 0
        @Published var wholeCobInsulin: Decimal = 0
        @Published var iobInsulinReduction: Decimal = 0
        @Published var wholeCalc: Decimal = 0
        @Published var insulinCalculated: Decimal = 0
        @Published var roundedInsulinCalculated: Decimal = 0
        @Published var fraction: Decimal = 0
        @Published var useCalc: Bool = true
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var useFattyMealCorrectionFactor: Bool = false
        @Published var displayPredictions: Bool = true

        @Published var meal: [CarbsEntry]?
        @Published var carbs: Decimal = 0
        @Published var fat: Decimal = 0
        @Published var protein: Decimal = 0
        @Published var note: String = ""
        @Published var data = [InsulinRequired(agent: "Something", amount: 0)]
        @Published var bolusIncrement: Decimal = 0.1
        @Published var eventualBG: Bool = false
        @Published var minimumPrediction: Bool = false
        @Published var closedLoop: Bool = false
        @Published var loopDate: Date = .distantFuture
        @Published var now = Date.now

        let loopReminder: CGFloat = 4

        private var loopFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        override func subscribe() {
            setupInsulinRequired()
            broadcaster.register(SuggestionObserver.self, observer: self)
            units = settingsManager.settings.units
            minimumPrediction = settingsManager.settings.minumimPrediction
            threshold = settingsManager.preferences.threshold_setting
            maxBolus = provider.pumpSettings().maxBolus
            // added
            fraction = settings.settings.overrideFactor
            useCalc = settings.settings.useCalc
            fattyMeals = settings.settings.fattyMeals
            fattyMealFactor = settings.settings.fattyMealFactor
            eventualBG = settings.settings.eventualBG
            displayPredictions = settings.settings.displayPredictions
            bolusIncrement = settings.preferences.bolusIncrement
            closedLoop = settings.settings.closedLoop
            loopDate = apsManager.lastLoopDate

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
                loopDate = apsManager.lastLoopDate
            }
            if let notNilSugguestion = provider.suggestion {
                suggestion = notNilSugguestion
                if let notNilPredictions = suggestion?.predictions {
                    predictions = notNilPredictions
                }
            }
        }

        func getDeltaBG() {
            let glucose = provider.fetchGlucose()
            guard let lastGlucose = glucose.first, glucose.count >= 4 else { return }
            deltaBG = Decimal(lastGlucose.glucose + glucose[1].glucose) / 2 -
                (Decimal(glucose[3].glucose + glucose[2].glucose) / 2)
        }

        func calculateInsulin() -> Decimal {
            let conversion: Decimal = units == .mmolL ? 0.0555 : 1
            // The actual glucose threshold
            threshold = max(target - 0.5 * (target - 40 * conversion), threshold * conversion)

            // Use either the eventual glucose prediction or just the Swift code
            if eventualBG {
                if evBG > target {
                    // Use Oref0 predictions{
                    insulin = (evBG - target) / isf
                } else { insulin = 0 }
            } else {
                let targetDifference = currentBG - target
                targetDifferenceInsulin = isf == 0 ? 0 : targetDifference / isf
            }

            // more or less insulin because of bg trend in the last 15 minutes
            fifteenMinInsulin = isf == 0 ? 0 : (deltaBG * conversion) / isf

            // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
            wholeCobInsulin = carbRatio != 0 ? cob / carbRatio : 0

            // determine how much the calculator reduces/ increases the bolus because of IOB
            iobInsulinReduction = (-1) * iob

            // adding everything together
            // add a calc for the case that no fifteenMinInsulin is available
            if deltaBG != 0 {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinInsulin)
            } else {
                // add (rare) case that no glucose value is available -> maybe display warning?
                // if no bg is available, ?? sets its value to 0
                if currentBG == 0 {
                    wholeCalc = (iobInsulinReduction + wholeCobInsulin)
                } else {
                    wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
                }
            }

            // apply custom factor at the end of the calculations
            let result = !eventualBG ? wholeCalc * fraction : insulin * fraction

            // apply custom factor if fatty meal toggle in bolus calc config settings is on and the box for fatty meals is checked (in RootView)
            if useFattyMealCorrectionFactor {
                insulinCalculated = result * fattyMealFactor
            } else {
                insulinCalculated = result
            }

            // A blend of Oref0 predictions and the Swift calculator {
            if minimumPrediction, minPredBG < threshold {
                if eventualBG { insulin = 0 }
                return 0
            }

            // Account for increments (Don't use the apsManager function as that gets much too slow)
            insulinCalculated = roundBolus(insulinCalculated)
            // 0 up to maxBolus
            insulinCalculated = min(max(insulinCalculated, 0), maxBolus)

            prepareData()

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

        func setupInsulinRequired() {
            let conversion: Decimal = units == .mmolL ? 0.0555 : 1
            DispatchQueue.main.async {
                if let suggestion = self.provider.suggestion {
                    self.insulinRequired = suggestion.insulinReq ?? 0
                    self.evBG = Decimal(suggestion.eventualBG ?? 0) * conversion
                    self.iob = suggestion.iob ?? 0
                    self.currentBG = (suggestion.bg ?? 0) * conversion
                    self.cob = suggestion.cob ?? 0
                }
                // Unwrap. We can't have NaN values.
                if let reasons = CoreDataStorage().fetchReason(), let target = reasons.target, let isf = reasons.isf,
                   let carbRatio = reasons.cr, let minPredBG = reasons.minPredBG
                {
                    self.target = target as Decimal
                    self.isf = isf as Decimal
                    self.carbRatio = carbRatio as Decimal
                    self.minPredBG = minPredBG as Decimal
                }

                if self.useCalc {
                    self.getDeltaBG()
                    self.insulinCalculated = self.roundBolus(max(self.calculateInsulin(), 0))
                    self.prepareData()
                }
            }
        }

        func backToCarbsView(
            complexEntry: Bool,
            _ meal: FetchedResults<Meals>,
            override: Bool,
            deleteNothing: Bool,
            editMode: Bool
        ) {
            if !deleteNothing { delete(deleteTwice: complexEntry, meal: meal) }
            showModal(for: .addCarbs(editMode: editMode, override: override))
        }

        func delete(deleteTwice: Bool, meal: FetchedResults<Meals>) {
            guard let meals = meal.first else {
                return
            }

            let mealArray = DataTable.Treatment(
                units: units,
                type: .carbs,
                date: (deleteTwice ? (meals.createdAt ?? Date()) : meals.actualDate) ?? Date(),
                id: meals.id ?? "",
                isFPU: deleteTwice ? true : false,
                fpuID: deleteTwice ? (meals.fpuID ?? "") : ""
            )

            if deleteTwice {
                nsManager.deleteNormalCarbs(mealArray)
                nsManager.deleteFPUs(mealArray)
            } else {
                nsManager.deleteNormalCarbs(mealArray)
            }
        }

        func carbsView(fetch: Bool, hasFatOrProtein: Bool, mealSummary: FetchedResults<Meals>) -> Bool {
            var keepForNextWiew = false
            if fetch {
                keepForNextWiew = true
                backToCarbsView(complexEntry: hasFatOrProtein, mealSummary, override: false, deleteNothing: false, editMode: true)
            } else {
                backToCarbsView(complexEntry: false, mealSummary, override: true, deleteNothing: true, editMode: false)
            }
            return keepForNextWiew
        }

        func remoteBolus() -> String? {
            if let enactedAnnouncement = announcementStorage.recentEnacted() {
                let components = enactedAnnouncement.notes.split(separator: ":")
                guard components.count == 2 else { return nil }
                let command = String(components[0]).lowercased()
                let eventual: String = units == .mmolL ? evBG.asMmolL
                    .formatted(.number.grouping(.never).rounded().precision(.fractionLength(1))) : evBG.formatted()

                if command == "bolus" {
                    return "\n" + NSLocalizedString("A Remote Bolus ", comment: "Remote Bolus Alert, part 1") +
                        NSLocalizedString("was delivered", comment: "Remote Bolus Alert, part 2") + (
                            -1 * enactedAnnouncement.createdAt
                                .timeIntervalSinceNow
                                .minutes
                        )
                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) +
                        NSLocalizedString(
                            " minutes ago, triggered remotely from Nightscout, by a caregiver or a parent. Do you still want to bolus?\n\nPredicted eventual glucose, if you don't bolus, is: ",
                            comment: "Remote Bolus Alert, part 3"
                        ) + eventual + " " + units.rawValue
                }
            }
            return nil
        }

        func notActive() {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: IAPSconfig.inBolusView)
            // print("Active: NO") // For testing
        }

        func viewActive() {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: IAPSconfig.inBolusView)
            // print("Active: YES") // For testing
        }

        private func prepareData() {
            if !eventualBG {
                var prepareData = [
                    InsulinRequired(agent: NSLocalizedString("Carbs", comment: ""), amount: wholeCobInsulin),
                    InsulinRequired(agent: NSLocalizedString("IOB", comment: ""), amount: iobInsulinReduction),
                    InsulinRequired(agent: NSLocalizedString("Glucose", comment: ""), amount: targetDifferenceInsulin),
                    InsulinRequired(agent: NSLocalizedString("Trend", comment: ""), amount: fifteenMinInsulin),
                    InsulinRequired(agent: NSLocalizedString("Factors", comment: ""), amount: 0),
                    InsulinRequired(agent: NSLocalizedString("Amount", comment: ""), amount: insulinCalculated)
                ]
                let total = prepareData.dropLast().map(\.amount).reduce(0, +)
                if total > 0 {
                    let factor = -1 * (total - insulinCalculated)
                    prepareData[4].amount = abs(factor) >= bolusIncrement ? factor : 0
                }
                data = prepareData
            }
        }

        func lastLoop() -> String? {
            guard closedLoop else { return nil }
            guard abs(now.timeIntervalSinceNow / 60) > loopReminder else { return nil }
            let minAgo = abs(loopDate.timeIntervalSinceNow / 60)

            let stringAgo = loopFormatter.string(from: minAgo as NSNumber) ?? ""
            return "Last loop \(stringAgo) minutes ago. Complete or cancel this meal/bolus transaction to allow for next loop cycle to run"
        }

        private func roundBolus(_ amount: Decimal) -> Decimal {
            // Account for increments (don't use the APSManager function as that gets too slow)
            Decimal(round(Double(amount / bolusIncrement))) * bolusIncrement
        }
    }
}

extension Bolus.StateModel: SuggestionObserver {
    func suggestionDidUpdate(_: Suggestion) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
        setupInsulinRequired()
        loopDate = apsManager.lastLoopDate

        if abs(now.timeIntervalSinceNow / 60) > loopReminder * 1.5 {
            hideModal()
            notActive()
            debug(.apsManager, "Force Closing Bolus View", printToConsole: true)
        }
    }
}

extension Decimal {
    /// Account for increments
    func roundBolus(increment: Double) -> Decimal {
        Decimal(round(Double(self) / increment)) * Decimal(increment)
    }
}
