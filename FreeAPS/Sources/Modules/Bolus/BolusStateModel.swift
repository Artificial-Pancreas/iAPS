import Foundation
import LoopKit
import SwiftUI
import Swinject

extension Bolus {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var unlockmanager: UnlockManager!
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var apsManager: APSManager!

        // added for bolus calculator

        @Injected() private var announcementStorage: AnnouncementsStorage!
        @Injected() private var carbsStorage: CarbsStorage!
        @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var storage: FileStorage!

        private let coreDataStorage = CoreDataStorage()

        @Published var suggestion: Suggestion?
        @Published var predictions: Predictions?
        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var units: GlucoseUnits = .mmolL
        @Published var percentage: Decimal = 0
        @Published var threshold: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var errorString: String = ""
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
        @Published var waitForCarbs: Bool = false

        // added for bolus calculator
        @Published var recentGlucose: BloodGlucose?
        @Published var target: Decimal = 100
        @Published var cob: Decimal = 0

        @Published var currentBG: Decimal = 0
        @Published var manualGlucose: Decimal = 0
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
        @Published var eventualBG: Bool = false
        @Published var minimumPrediction: Bool = false
        @Published var closedLoop: Bool = false
        @Published var loopDate: Date = .distantFuture
        @Published var now = Date.now
        @Published var bolus: Decimal = 0
        @Published var carbToStore: CarbsEntry? = nil
        @Published var disable15MinTrend: Bool = false
        @Published var minBolus: Decimal = 0.05

        private var concentration: (concentration: Double, increment: Double) {
            get async {
                await coreDataStorage.insulinConcentration()
            }
        }

        let bolusIncrement: Decimal = 0.05
        let loopReminder: CGFloat = 4
        private let oldGlucoseThreshold: TimeInterval = .minutes(15)

        /// When IOB module fail
        private var recentIOB: Decimal = 0

        private static let loopFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }()

        override init(resolver: Resolver) {
            super.init(resolver: resolver)
            let settings = appCoordinator.settings.value
            // need to initialize these before subscribe()
            useCalc = settings.useCalc
            eventualBG = settings.eventualBG
        }

        override func subscribe() async {
            let settings = appCoordinator.settings.value
            let preferences = appCoordinator.preferences.value
            let pumpSettings = appCoordinator.pumpSettings.value
            units = settings.units
            minimumPrediction = settings.minumimPrediction
            threshold = preferences.threshold_setting
            maxBolus = pumpSettings.maxBolus
            fraction = settings.overrideFactor
            useCalc = settings.useCalc
            fattyMeals = settings.fattyMeals
            fattyMealFactor = settings.fattyMealFactor
            eventualBG = settings.eventualBG
            displayPredictions = settings.displayPredictions
            closedLoop = settings.closedLoop
            loopDate = appCoordinator.lastLoopDate.value ?? .distantPast
            disable15MinTrend = settings.disable15MinTrend
            recentIOB = appCoordinator.iobTicks.value?.first?.iob ?? 0

            await updateMinBolus(appCoordinator.pumpStatus.value)

            observe(appCoordinator.lastLoopDate) { me, lastLoopDate in
                await me.lastLoopDateUpdated(lastLoopDate)
            }
            // autoclose the view. TODO: should we use just a timer instead?
            observe(appCoordinator.suggested) { me, suggestion in
                await me.suggestionDidUpdate(suggestion)
            }
            observe(appCoordinator.pumpStatus) { me, pumpStatus in
                await me.updateMinBolus(pumpStatus)
            }
        }

        private func updateMinBolus(_ pumpStatus: PumpDisplayStatus?) async {
            let concentration = await self.concentration
            minBolus = Decimal(pumpStatus?.supportedBolusVolumes.first ?? Double(bolusIncrement)) *
                Decimal(concentration.concentration)
        }

        private func suggestionDidUpdate(_: Suggestion?) async {
            if Date.now >= now.addingTimeInterval(.minutes(loopReminder * 1.5)) {
                hideModal()
                notActive()
                debug(.apsManager, "Force Closing Bolus View")
            }
        }

        private func lastLoopDateUpdated(_ lastLoopDate: Date?) {
            loopDate = lastLoopDate ?? .distantPast
        }

        func start() {
            Task {
                if waitForSuggestionInitial {
                    if waitForCarbs {
                        await setupBolusData()
                    }

                    self.suggestion = try? await apsManager.determineBasal(temporaryCarbs: carbToStore)
                    self.predictions = self.suggestion?.predictions
                    if self.suggestion == nil {
                        self.insulinRequired = 0
                        self.insulinRecommended = 0
                    }
                    loopDate = self.suggestion?.deliverAt ?? .distantPast

                    self.waitForSuggestion = false
                }
                setupInsulinRequired()
            }
        }

        func getDeltaBG() {
            let twoHoursAgo = DateFilter.twoHours.startDate as Date
            let glucose = appCoordinator.glucoseRaw.value.filter { $0.dateString >= twoHoursAgo }
            guard let lastGlucose = glucose.first else { return }
            guard lastGlucose.dateString >= Date.now.subtractingTimeInterval(oldGlucoseThreshold) else {
                currentBG = 0
                print("BG time ago: \(lastGlucose.dateString.timeIntervalSinceNow.minutes) minutes")
                return
            }
            currentBG = Decimal(lastGlucose.glucose) * conversion
            guard glucose.count >= 4 else { return }
            deltaBG = Decimal(lastGlucose.glucose + glucose[1].glucose) / 2 -
                (Decimal(glucose[3].glucose + glucose[2].glucose) / 2)
        }

        func calculateInsulin() {
            // The actual glucose threshold
            threshold = max(target - 0.5 * (target - 40 * conversion), threshold * conversion)
            // Use either the eventual glucose prediction or just the Swift code
            if eventualBG {
                if evBG > target {
                    // Use Oref0 predictions{
                    insulin = (evBG - target) / isf
                } else { insulin = 0 }
            } else if manualGlucose > 0 {
                let targetDifference = (units == .mmolL ? manualGlucose.asMmolL : manualGlucose) - target
                targetDifferenceInsulin = isf == 0 ? 0 : targetDifference / isf
            } else if currentBG > 0 {
                let targetDifference = currentBG - target
                print("BG: \(currentBG), target: \(target), isf: \(isf)")
                targetDifferenceInsulin = isf == 0 ? 0 : targetDifference / isf
            } else {
                targetDifferenceInsulin = 0
                print("BG: \(currentBG), target: \(target), isf: \(isf)")
            }

            // more or less insulin because of bg trend in the last 15 minutes
            fifteenMinInsulin = (isf == 0 || disable15MinTrend) ? 0 : (deltaBG * conversion) / isf
            print("fifteenMinInsulin isf: \(isf), deltaBG: \(deltaBG * conversion)")

            // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
            // If failed recent suggestion use recent carb entry
            wholeCobInsulin = carbRatio != 0 ? max(cob, recentCarbs) / carbRatio : 0

            // determine how much the calculator reduces/ increases the bolus because of IOB
            // If failed recent suggestion use recent IOB value
            iobInsulinReduction = -recentIOB

            // adding everything together
            // add a calc for the case that no fifteenMinInsulin is available
            if deltaBG != 0 {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinInsulin)
            } else if currentBG == 0, manualGlucose == 0 {
                wholeCalc = (iobInsulinReduction + wholeCobInsulin)
            } else {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
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
                insulinCalculated = 0
                return
            }

            // Account for increments (Don't use the apsManager function as that is much too slow)
            insulinCalculated = roundBolus(insulinCalculated)
            // 0 up to maxBolus
            insulinCalculated = min(max(insulinCalculated, 0), maxBolus)

            prepareData()
        }

        /// When COB module fail
        var recentCarbs: Decimal {
            var temporaryCarbs: Decimal = 0
            guard let temporary = carbToStore else { return 0 }
            let timeDifference = (temporary.actualDate ?? .distantPast).timeIntervalSinceNow
            if timeDifference <= 0, timeDifference > TimeInterval.minutes(-15) {
                temporaryCarbs = temporary.carbs
            }
            return temporaryCarbs
        }

        func add() {
            Task {
                guard amount > 0 else {
                    showModal(for: nil)
                    return
                }

                let pumpSettings = appCoordinator.pumpSettings.value
                let maxAmount = Double(min(amount, pumpSettings.maxBolus))

                do {
                    try await unlockmanager.unlock()
                    self.save()
                    await self.apsManager.enactBolus(amount: maxAmount, isSMB: false)
                    self.showModal(for: nil)
                } catch {
                    debug(.default, "device was not unlocked, skipping bolus")
                }
            }
        }

        func save() {
            guard let carbToStore, !carbToStore.isEmpty else { return }
            Task {
                await coreDataStorage.updateLatestMeal(to: true)
                await carbsStorage.storeCarbs([carbToStore])
            }
        }

        func saveMeal() {
            Task {
                if let recent = await coreDataStorage.recentMeal() {
                    carbToStore = CarbsEntry(
                        id: recent.id,
                        createdAt: (recent.createdAt ?? Date.now).addingTimeInterval(.seconds(5)),
                        actualDate: recent.actualDate,
                        carbs: (recent.carbs ?? 0) as Decimal,
                        fat: (recent.fat ?? 0) as Decimal,
                        protein: (recent.protein ?? 0) as Decimal,
                        fiber: (recent.fiber ?? 0) as Decimal,
                        note: recent.note,
                        enteredBy: CarbsEntry.manual,
                        isFPU: false,
                        micronutrient: recent.micronutrientValues
                    )
                }

                guard let carbToStore, !carbToStore.isEmpty else { return }

                await carbsStorage.storeCarbs([carbToStore])
                await coreDataStorage.saveMeal([carbToStore], now: Date.now, savedToFile: true)
            }
        }

        func setupInsulinRequired() {
            let conversion: Decimal = units == .mmolL ? 0.0555 : 1

            if let suggestion = self.suggestion {
                insulinRequired = suggestion.insulinReq ?? 0
                evBG = Decimal(suggestion.eventualBG ?? 0) * conversion
                recentIOB = suggestion.iob ?? 0
                cob = suggestion.cob ?? 0

                if let target = suggestion.targetBG,
                   let isf = suggestion.iaps?.isf,
                   let carbRatio = suggestion.iaps?.cr,
                   let minPredBG = suggestion.iaps?.minPredBG
                {
                    self.target = target
                    self.isf = isf
                    self.carbRatio = carbRatio
                    self.minPredBG = minPredBG
                }
            }

            if useCalc {
                getDeltaBG()
                calculateInsulin()
                prepareData()
            }
        }

        func backToCarbsView(override: Bool, editMode: Bool) {
            showModal(for: .addCarbs(editMode: editMode, override: override, mode: .meal))
        }

        func carbsView(fetch: Bool, hasFatOrProtein _: Bool, mealSummary _: FetchedResults<Meals>) -> Bool {
            var keepForNextWiew = false
            if fetch {
                keepForNextWiew = true
                backToCarbsView(override: false, editMode: true)
            } else {
                backToCarbsView(override: true, editMode: false)
            }
            return keepForNextWiew
        }

        func remoteBolus() async -> String? {
            if let enactedAnnouncement = await announcementStorage.recentEnacted() {
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

        var conversion: Decimal {
            units == .mmolL ? 0.0555 : 1
        }

        func addManualGlucose() {
            Task {
                let glucose = manualGlucose
                let now = Date()
                let id = UUID().uuidString

                let saveToJSON = BloodGlucose(
                    _id: id,
                    sgv: Int(glucose),
                    date: Decimal(now.timeIntervalSince1970) * 1000,
                    dateString: now,
                    unfiltered: glucose,
                    uncalibrated: glucose,
                    glucose: Int(glucose),
                    type: GlucoseType.manual.rawValue
                )
                _ = await glucoseStorage.storeGlucose([saveToJSON])
                debug(.default, "Manual Glucose saved to glucose.json")
                // Save to Health
                var saveToHealth = [BloodGlucose]()
                saveToHealth.append(saveToJSON)
            }
        }

        private func prepareData() {
            if !eventualBG {
                var prepareData = !disable15MinTrend ? [
                    InsulinRequired(agent: NSLocalizedString("Carbs", comment: ""), amount: wholeCobInsulin),
                    InsulinRequired(agent: NSLocalizedString("IOB", comment: ""), amount: iobInsulinReduction),
                    InsulinRequired(agent: NSLocalizedString("Glucose", comment: ""), amount: targetDifferenceInsulin),
                    InsulinRequired(agent: NSLocalizedString("Trend", comment: ""), amount: fifteenMinInsulin),
                    InsulinRequired(agent: NSLocalizedString("Factors", comment: ""), amount: 0),
                    InsulinRequired(agent: NSLocalizedString("Amount", comment: ""), amount: insulinCalculated)
                ] :
                    [
                        InsulinRequired(agent: NSLocalizedString("Carbs", comment: ""), amount: wholeCobInsulin),
                        InsulinRequired(agent: NSLocalizedString("IOB", comment: ""), amount: iobInsulinReduction),
                        InsulinRequired(agent: NSLocalizedString("Glucose", comment: ""), amount: targetDifferenceInsulin),
                        InsulinRequired(agent: NSLocalizedString("Factors", comment: ""), amount: 0),
                        InsulinRequired(agent: NSLocalizedString("Amount", comment: ""), amount: insulinCalculated)
                    ]
                let total = prepareData.dropLast().map(\.amount).reduce(0, +)
                if total > 0 {
                    let factor = -1 * (total - insulinCalculated)
                    prepareData[!disable15MinTrend ? 4 : 3]
                        .amount = abs(factor) >= minBolus ? factor : 0
                }
                data = prepareData
            }
        }

        func lastLoop() -> String? {
            guard closedLoop else { return nil }
            guard abs(now.timeIntervalSinceNow / 60) > loopReminder else { return nil }
            let minAgo = abs(loopDate.timeIntervalSinceNow / 60)

            let stringAgo = Self.loopFormatter.string(from: minAgo as NSNumber) ?? ""
            return "Last loop \(stringAgo) minutes ago. Complete or cancel this meal/bolus transaction to allow for next loop cycle to run"
        }

        private func roundBolus(_ amount: Decimal) -> Decimal {
            // Account for increments (don't use the APSManager function as that gets too slow)
            let increment = minBolus
            return Decimal(round(Double(amount / increment))) * increment
        }

        private func setupBolusData() async {
            if let recent = await coreDataStorage.recentMeal() {
                carbToStore = CarbsEntry(
                    id: recent.id,
                    createdAt: (recent.createdAt ?? Date.now).addingTimeInterval(.seconds(5)),
                    actualDate: recent.actualDate,
                    carbs: (recent.carbs ?? 0) as Decimal,
                    fat: (recent.fat ?? 0) as Decimal,
                    protein: (recent.protein ?? 0) as Decimal,
                    fiber: (recent.fiber ?? 0) as Decimal,
                    note: recent.note,
                    enteredBy: CarbsEntry.manual,
                    isFPU: false,
                    micronutrient: recent.micronutrientValues
                )
            }
        }

        func determineBasal() {
            Task {
                _ = try? await apsManager.determineBasal(temporaryCarbs: nil)
            }
        }

        private func fetchGlucose() async -> [ReadingsSnapshot] {
            await coreDataStorage.fetchGlucose(interval: DateFilter.twoHours.startDate)
        }
    }
}

extension Decimal {
    /// Account for increments
    func roundBolusIncrements(increment: Double) -> Decimal {
        Decimal(round(Double(self) / increment)) * Decimal(increment)
    }
}
