import CoreData
import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider>, UIBindingOwner {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() private var storage: FileStorage!
        @Injected() var carbStorage: CarbsStorage!
        @Injected() var aps: APSManager!
        @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() private var carbsStorage: CarbsStorage!
        @Injected() private var tempTargetsStorage: TempTargetsStorage!
        @Injected() private var glucoseStorage: GlucoseStorage!
        @Injected() private var overrideStorage: OverrideStorage!

        private let coreDataStorage = CoreDataStorage()
        private let totalDailyDose = TotalDailyDose()
        let uiBindings = UIBindings()

        @Published var mode: Mode = .treatments
        @Published var treatments: [Treatment] = []
        @Published var glucose: [Glucose] = []
        @Published var manualGlucose: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var externalInsulinAmount: Decimal = 0
        @Published var externalInsulinDate = Date()
        @Published var tdd: (Decimal, Decimal, Double) = (0, 0, 0)
        @Published var insulinToday: (Decimal, Decimal, Double) = (0, 0, 0)
        @Published var basalInsulin: Decimal = 0

        @Published var meal = EditableMeal()
        @Published var oldCarbs: Decimal = 0
        @Published var carbEquivalents: Decimal = 0
        @Published var treatment: Treatment?

        var units: GlucoseUnits = .mmolL

        override func subscribe() async {
            let settings = await settingsManager.settings
            let pumpSettings = await settingsManager.pumpSettings
            units = settings.units
            maxBolus = pumpSettings.maxBolus

            await setupTreatments()
            setupGlucose(appCoordinator.glucoseHistoryRaw.value)

            observeUI(appCoordinator.settings, dropInitial: true) { me, _ in
                await me.setupTreatments()
            }
            observeUI(appCoordinator.preferences, dropInitial: true) { me, _ in
                await me.setupTreatments()
            }
            observeUI(appCoordinator.pumpSettings, dropInitial: true) { me, _ in
                await me.setupTreatments()
            }
            observeUI(appCoordinator.pumpHistory, dropInitial: true) { me, _ in
                await me.setupTreatments()
            }
            observeUI(appCoordinator.tempTargets, dropInitial: true) { me, _ in
                await me.setupTreatments()
            }
            observeUI(appCoordinator.carbHistory, dropInitial: true) { me, _ in
                await me.setupTreatments()
            }
            observeUI(appCoordinator.glucoseHistoryRaw, dropInitial: true) { me, glucoseHistory in
                me.setupGlucose(glucoseHistory)
            }
        }

        private func setupTreatments() async {
            let settings = await settingsManager.settings
            let pumpSettings = await settingsManager.pumpSettings
            let preferences = await settingsManager.preferences
            let pumpHistory = appCoordinator.pumpHistory.value
            let carbHistory = appCoordinator.carbHistory.value
            let recentTempTargets = appCoordinator.tempTargets.value

            self.units = settings.units
            maxBolus = pumpSettings.maxBolus

            // TODO: move these computations off the main actor?

            let units = settings.units
            let carbs = carbHistory
                .filter { !($0.isFPU ?? false) }
                .map {
                    if let id = $0.id {
                        return Treatment(
                            units: units,
                            type: .carbs,
                            date: $0.actualDate ?? $0.createdAt,
                            creationDate: $0.createdAt,
                            amount: $0.carbs,
                            id: id,
                            note: $0.note
                        )
                    } else {
                        return Treatment(
                            units: units,
                            type: .carbs,
                            date: $0.actualDate ?? $0.createdAt,
                            creationDate: $0.createdAt,
                            amount: $0.carbs,
                            note: $0.note
                        )
                    }
                }

            let boluses = pumpHistory
                .filter { $0.type == .bolus }
                .map {
                    Treatment(
                        units: units,
                        type: .bolus,
                        date: $0.timestamp,
                        creationDate: $0.timestamp,
                        amount: $0.amount,
                        idPumpEvent: $0.id,
                        isSMB: $0.isSMB,
                        isExternal: $0.isExternal
                    )
                }

            let tempBasals = pumpHistory
                .filter { $0.type == .tempBasal || $0.type == .tempBasalDuration }
                .chunks(ofCount: 2)
                .compactMap { chunk -> Treatment? in
                    let chunk = Array(chunk)
                    guard chunk.count == 2 else { return nil }
                    let durationEntry = chunk[0]
                    let tempBasalEntry = chunk[1]
                    guard tempBasalEntry.type == .tempBasal,
                          durationEntry.type == .tempBasalDuration else { return nil }
                    return Treatment(
                        units: units,
                        type: .tempBasal,
                        date: tempBasalEntry.timestamp,
                        creationDate: tempBasalEntry.timestamp,
                        amount: tempBasalEntry.rate ?? 0,
                        secondAmount: nil,
                        duration: durationEntry.durationMin ?? 0
                    )
                }

            let tempTargets = recentTempTargets
                .map {
                    Treatment(
                        units: units,
                        type: .tempTarget,
                        date: $0.createdAt,
                        creationDate: $0.createdAt,
                        amount: $0.targetBottom ?? 0,
                        secondAmount: $0.targetTop,
                        duration: $0.duration
                    )
                }

            let suspend = pumpHistory
                .filter { $0.type == .pumpSuspend }
                .map {
                    Treatment(units: units, type: .suspend, date: $0.timestamp, creationDate: $0.timestamp)
                }

            let resume = pumpHistory
                .filter { $0.type == .pumpResume }
                .map {
                    Treatment(units: units, type: .resume, date: $0.timestamp, creationDate: $0.timestamp)
                }

            treatments = [carbs, boluses, tempBasals, tempTargets, suspend, resume]
                .flatMap { $0 }
                .sorted { $0.date > $1.date }

            let increments = preferences.bolusIncrement
            tdd = totalDailyDose.totalDailyDose(pumpHistory, increment: Double(increments))
            insulinToday = totalDailyDose.insulinToday(pumpHistory, increment: Double(increments))
        }

        private func setupGlucose(_ glucoseHistory: [BloodGlucose]) {
            glucose = glucoseHistory.map(Glucose.init)
        }

        func deleteCarbs(_ treatment: Treatment, storage: Meals?) {
            Task {
                await doDeleteCarbs(treatment.creationDate)

                // In need of CoreData deletion?
                if let data = storage {
                    await coreDataStorage.deleteBatch(identifier: data.id, entity: "Meals")
                }

                // In need of a loop update?
                if treatment.creationDate.timeIntervalSinceNow > .hours(-2) {
                    _ = try? await aps.determineBasal(temporaryCarbs: nil)
                }
            }
        }

        func deleteInsulin(_ treatment: Treatment) {
            Task {
                do {
                    try await unlockmanager.unlock()
                    await doDeleteInsulin(treatment)
                } catch {}
            }
        }

        func deleteGlucose(_ glucose: Glucose) {
            Task {
                await glucoseStorage.removeGlucose(ids: [glucose.id])
            }
        }

        func addManualGlucose() {
            Task {
                let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
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
            }
        }

        func addExternalInsulin() {
            guard externalInsulinAmount > 0 else {
                showModal(for: nil)
                return
            }

            Task {
                externalInsulinAmount = min(externalInsulinAmount, maxBolus * 3) // Allow for 3 * Max Bolus for external insulin
                do {
                    _ = try await unlockmanager.unlock()
                    await pumpHistoryStorage.storeEvents(
                        [
                            PumpHistoryEvent(
                                id: UUID().uuidString,
                                type: .bolus,
                                timestamp: externalInsulinDate,
                                amount: externalInsulinAmount,
                                duration: nil,
                                durationMin: nil,
                                rate: nil,
                                temp: nil,
                                carbInput: nil,
                                isExternal: true
                            )
                        ]
                    )
                    debug(.default, "External insulin saved to pumphistory.json")

                    // Reset amount to 0 for next entry.
                    externalInsulinAmount = 0
                } catch {}
            }
        }

        /// Update Carbs or Carb equivalents in storage, data table
        func updateCarbs(treatment: Treatment?, computed: Meals?) {
            guard let old = treatment else { return }

            Task {
                let newCarbs = CarbsEntry(
                    id: old.id,
                    createdAt: old.creationDate,
                    actualDate: old.date,
                    carbs: meal.carbs,
                    fat: meal.fat,
                    protein: meal.protein,
                    fiber: meal.fiber,
                    note: meal.note,
                    enteredBy: CarbsEntry.manual,
                    isFPU: false,
                    micronutrient: meal.micronutrient
                )

                // Remove old CoreData meal
                if let deleteOld = computed {
                    await coreDataStorage.deleteBatch(
                        identifier: deleteOld.id,
                        entity: "Meals"
                    )
                }

                // Remove old carb entry
                await doDeleteCarbs(old.creationDate)

                // Save updated CoreData meal + micros
                await coreDataStorage.saveMeal(
                    [newCarbs],
                    now: old.creationDate,
                    savedToFile: true
                )

                // Store updated meal to file. To Do: remove
                await carbStorage.storeCarbs([newCarbs])

                debug(
                    .apsManager,
                    "Carbs updated: \(old.amountText) -> \(meal.carbs) g"
                )

                if newCarbs.carbs != oldCarbs,
                   (newCarbs.actualDate ?? .distantPast).timeIntervalSinceNow > TimeInterval.hours(-3)
                {
                    _ = try? await aps.determineBasal(temporaryCarbs: nil)
                }
            }
        }

        func updateVariables(mealItem: Treatment, complex: Meals?) {
            treatment = mealItem
            let string = (mealItem.amountText.components(separatedBy: " ").first ?? "0")
                .replacingOccurrences(of: ",", with: ".")
            meal.carbs = string.toDecimal ?? 0
            oldCarbs = meal.carbs
            meal.fat = (complex?.fat ?? 0) as Decimal
            meal.protein = (complex?.protein ?? 0) as Decimal
            meal.fiber = (complex?.fiber ?? 0) as Decimal
            meal.note = complex?.note ?? "Meal"
            meal.micronutrient = complex?.micronutrientValues ?? []
        }

        private func doDeleteCarbs(_ date: Date) async {
            await carbStorage.deleteCarbsAndFPUs(at: date)
        }

        private func doDeleteInsulin(_ treatment: Treatment) async {
            await pumpHistoryStorage.deleteInsulin(at: treatment.date)
        }
    }
}
