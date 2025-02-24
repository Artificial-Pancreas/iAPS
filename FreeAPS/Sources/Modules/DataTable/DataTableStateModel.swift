import CoreData
import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var unlockmanager: UnlockManager!
        @Injected() private var storage: FileStorage!
        @Injected() var carbStorage: CarbsStorage!
        @Injected() var aps: APSManager!
        @Injected() private var nightscout: NightscoutManager!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

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

        @Published var meal: (carbs: Decimal, fat: Decimal, protein: Decimal) = (0, 0, 0)
        @Published var oldCarbs: Decimal = 0
        @Published var carbEquivalents: Decimal = 0
        @Published var treatment: Treatment?

        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            maxBolus = provider.pumpSettings().maxBolus
            setupTreatments()
            setupGlucose()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(GlucoseObserver.self, observer: self)
        }

        private let processQueue = DispatchQueue(label: "setupTreatments.processQueue")

        private func setupTreatments() {
            debug(.service, "setupTreatments() started")
            processQueue.async {
                let units = self.settingsManager.settings.units
                let carbs = self.provider.carbs()
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

                let boluses = self.provider.pumpHistory()
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

                let tempBasals = self.provider.pumpHistory()
                    .filter { $0.type == .tempBasal || $0.type == .tempBasalDuration }
                    .chunks(ofCount: 2)
                    .compactMap { chunk -> Treatment? in
                        let chunk = Array(chunk)
                        guard chunk.count == 2, chunk[0].type == .tempBasal,
                              chunk[1].type == .tempBasalDuration else { return nil }
                        return Treatment(
                            units: units,
                            type: .tempBasal,
                            date: chunk[0].timestamp,
                            creationDate: chunk[0].timestamp,
                            amount: chunk[0].rate ?? 0,
                            secondAmount: nil,
                            duration: Decimal(chunk[1].durationMin ?? 0)
                        )
                    }

                let tempTargets = self.provider.tempTargets()
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

                let suspend = self.provider.pumpHistory()
                    .filter { $0.type == .pumpSuspend }
                    .map {
                        Treatment(units: units, type: .suspend, date: $0.timestamp, creationDate: $0.timestamp)
                    }

                let resume = self.provider.pumpHistory()
                    .filter { $0.type == .pumpResume }
                    .map {
                        Treatment(units: units, type: .resume, date: $0.timestamp, creationDate: $0.timestamp)
                    }

                DispatchQueue.main.async {
                    self.treatments = [carbs, boluses, tempBasals, tempTargets, suspend, resume]
                        .flatMap { $0 }
                        .sorted { $0.date > $1.date }
                }

                DispatchQueue.main.async {
                    let increments = self.settingsManager.preferences.bolusIncrement
                    self.tdd = TotalDailyDose().totalDailyDose(self.provider.pumpHistory(), increment: Double(increments))
                    self.insulinToday = TotalDailyDose().insulinToday(self.provider.pumpHistory(), increment: Double(increments))
                }
            }
        }

        func setupGlucose() {
            DispatchQueue.main.async {
                self.glucose = self.provider.glucose().map(Glucose.init)
            }
        }

        func deleteCarbs(_ date: Date) {
            provider.deleteCarbs(date)

            if date.timeIntervalSinceNow > -2.hours.timeInterval {
                aps.determineBasalSync()
            }
        }

        func deleteInsulin(_ treatment: Treatment) {
            unlockmanager.unlock()
                .sink { _ in } receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.provider.deleteInsulin(treatment)
                }
                .store(in: &lifetime)
        }

        func deleteGlucose(_ glucose: Glucose) {
            let id = glucose.id
            provider.deleteGlucose(id: id)

            OverrideStorage().DeleteBatch(identifier: id, entity: "Readings")

            // Deletes Manual Glucose
            if (glucose.glucose.type ?? "") == GlucoseType.manual.rawValue {
                provider.deleteManualGlucose(date: glucose.glucose.dateString)
            }
        }

        func addManualGlucose() {
            let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
            let now = Date()
            let id = UUID().uuidString

            let saveToJSON = BloodGlucose(
                _id: id,
                sgv: Int(glucose),
                date: Decimal(now.timeIntervalSince1970) * 1000,
                dateString: now,
                glucose: Int(glucose),
                type: GlucoseType.manual.rawValue
            )
            provider.glucoseStorage.storeGlucose([saveToJSON])
            debug(.default, "Manual Glucose saved to glucose.json")
            // Save to Health
            var saveToHealth = [BloodGlucose]()
            saveToHealth.append(saveToJSON)
        }

        func addExternalInsulin() {
            guard externalInsulinAmount > 0 else {
                showModal(for: nil)
                return
            }

            externalInsulinAmount = min(externalInsulinAmount, maxBolus * 3) // Allow for 3 * Max Bolus for external insulin
            unlockmanager.unlock()
                .sink { _ in } receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    pumpHistoryStorage.storeEvents(
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
                }
                .store(in: &lifetime)
        }

        /// Update Carbs or Carb equivalents in storage, data table and Nightscout and Healthkit (where applicable)
        func updateCarbs(treatment: Treatment?, computed: Carbohydrates?) {
            guard let old = treatment else { return }

            let now = Date.now
            let newCarbs = CarbsEntry(
                id: UUID().uuidString,
                createdAt: now,
                actualDate: old.date,
                carbs: meal.carbs,
                fat: meal.fat,
                protein: meal.protein,
                note: old.note,
                enteredBy: CarbsEntry.manual,
                isFPU: false
            )

            if let deleteOld = computed {
                OverrideStorage().DeleteBatch(identifier: deleteOld.id, entity: "Carbohydrates")
            }
            carbStorage.storeCarbs([newCarbs])
            nightscout.deleteCarbs(old.creationDate)
            debug(.apsManager, "Carbs updated: \(old.amountText) -> \(meal.carbs) g")
            if newCarbs.carbs != oldCarbs, (newCarbs.actualDate ?? .distantPast).timeIntervalSinceNow > -3.hours.timeInterval {
                aps.determineBasalSync()
            }
        }

        func updateVariables(mealItem: Treatment, complex: Carbohydrates?) {
            treatment = mealItem
            let string = (mealItem.amountText.components(separatedBy: " ").first ?? "0")
                .replacingOccurrences(of: ",", with: ".")
            meal.carbs = Decimal(string: string) ?? 0
            oldCarbs = meal.carbs
            meal.fat = (complex?.fat ?? 0) as Decimal
            meal.protein = (complex?.protein ?? 0) as Decimal
        }
    }
}

extension DataTable.StateModel:
    SettingsObserver,
    PumpHistoryObserver,
    TempTargetsObserver,
    CarbsObserver,
    GlucoseObserver
{
    func settingsDidChange(_: FreeAPSSettings) {
        setupTreatments()
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupTreatments()
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTreatments()
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        setupTreatments()
    }

    func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }
}
