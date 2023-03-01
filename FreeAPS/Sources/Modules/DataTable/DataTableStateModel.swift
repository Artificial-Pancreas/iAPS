import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var unlockmanager: UnlockManager!

        @Published var mode: Mode = .treatments
        @Published var treatments: [Treatment] = []
        @Published var glucose: [Glucose] = []
        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            setupTreatments()
            setupGlucose()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(GlucoseObserver.self, observer: self)
        }

        private func setupTreatments() {
            DispatchQueue.global().async {
                let units = self.settingsManager.settings.units

                let carbs = self.provider.carbs()
                    .filter { !($0.isFPU ?? false) }
                    .map {
                        if let id = $0.id {
                            return Treatment(
                                units: units,
                                type: .carbs,
                                date: $0.createdAt,
                                amount: $0.carbs,
                                id: id
                            )
                        } else {
                            return Treatment(units: units, type: .carbs, date: $0.createdAt, amount: $0.carbs)
                        }
                    }

                let fpus = self.provider.fpus()
                    .filter { $0.isFPU ?? false }
                    .map {
                        Treatment(
                            units: units,
                            type: .fpus,
                            date: $0.createdAt,
                            amount: $0.carbs,
                            id: $0.id
                        )
                    }

                let boluses = self.provider.pumpHistory()
                    .filter { $0.type == .bolus }
                    .map {
                        Treatment(units: units, type: .bolus, date: $0.timestamp, amount: $0.amount, idPumpEvent: $0.id)
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
                            amount: $0.targetBottom ?? 0,
                            secondAmount: $0.targetTop,
                            duration: $0.duration
                        )
                    }

                let suspend = self.provider.pumpHistory()
                    .filter { $0.type == .pumpSuspend }
                    .map {
                        Treatment(units: units, type: .suspend, date: $0.timestamp)
                    }

                let resume = self.provider.pumpHistory()
                    .filter { $0.type == .pumpResume }
                    .map {
                        Treatment(units: units, type: .resume, date: $0.timestamp)
                    }

                DispatchQueue.main.async {
                    self.treatments = [carbs, boluses, tempBasals, tempTargets, suspend, resume, fpus]
                        .flatMap { $0 }
                        .sorted { $0.date > $1.date }
                }
            }
        }

        func setupGlucose() {
            DispatchQueue.main.async {
                self.glucose = self.provider.glucose().map(Glucose.init)
            }
        }

        func deleteCarbs(_ treatment: Treatment) {
            provider.deleteCarbs(treatment)
        }

        func deleteInsulin(_ treatment: Treatment) {
            unlockmanager.unlock()
                .sink { _ in } receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.provider.deleteInsulin(treatment)
                }
                .store(in: &lifetime)
        }

        func deleteGlucose(at index: Int) {
            let id = glucose[index].id
            provider.deleteGlucose(id: id)
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
