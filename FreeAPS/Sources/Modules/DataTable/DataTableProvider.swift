import Foundation

extension DataTable {
    final class Provider: BaseProvider, DataTableProvider {
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var healthkitManager: HealthKitManager!

        func pumpHistory() -> [PumpHistoryEvent] {
            pumpHistoryStorage.recent()
        }

        func tempTargets() -> [TempTarget] {
            tempTargetsStorage.recent()
        }

        func carbs() -> [CarbsEntry] {
            carbsStorage.recent()
        }

        func deleteCarbs(at date: Date) {
            nightscoutManager.deleteCarbs(at: date)
        }

        func glucose() -> [BloodGlucose] {
            glucoseStorage.recent().sorted { $0.date > $1.date }
        }

        func deleteGlucose(id: String) {
            glucoseStorage.removeGlucose(ids: [id])
            healthkitManager.deleteGlucise(syncID: id)
        }
    }
}
