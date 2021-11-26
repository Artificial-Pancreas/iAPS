import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Published var items: [Item] = []

        override func subscribe() {
            setupItems()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
        }

        private func setupItems() {
            DispatchQueue.global().async {
                let units = self.settingsManager.settings.units

                let carbs = self.provider.carbs().map {
                    Item(units: units, type: .carbs, date: $0.createdAt, amount: $0.carbs)
                }

                let boluses = self.provider.pumpHistory()
                    .filter { $0.type == .bolus }
                    .map {
                        Item(units: units, type: .bolus, date: $0.timestamp, amount: $0.amount)
                    }

                let tempBasals = self.provider.pumpHistory()
                    .filter { $0.type == .tempBasal || $0.type == .tempBasalDuration }
                    .chunks(ofCount: 2)
                    .compactMap { chunk -> Item? in
                        let chunk = Array(chunk)
                        guard chunk.count == 2, chunk[0].type == .tempBasal,
                              chunk[1].type == .tempBasalDuration else { return nil }
                        return Item(
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
                        Item(
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
                        Item(units: units, type: .suspend, date: $0.timestamp)
                    }

                let resume = self.provider.pumpHistory()
                    .filter { $0.type == .pumpResume }
                    .map {
                        Item(units: units, type: .resume, date: $0.timestamp)
                    }

                DispatchQueue.main.async {
                    self.items = [carbs, boluses, tempBasals, tempTargets, suspend, resume]
                        .flatMap { $0 }
                        .sorted { $0.date > $1.date }
                }
            }
        }

        func deleteCarbs(at date: Date) {
            provider.deleteCarbs(at: date)
        }
    }
}

extension DataTable.StateModel:
    SettingsObserver,
    PumpHistoryObserver,
    TempTargetsObserver,
    CarbsObserver
{
    func settingsDidChange(_: FreeAPSSettings) {
        setupItems()
    }

    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupItems()
    }

    func tempTargetsDidUpdate(_: [TempTarget]) {
        setupItems()
    }

    func carbsDidUpdate(_: [CarbsEntry]) {
        setupItems()
    }
}
