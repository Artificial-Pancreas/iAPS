import SwiftUI

extension AddCarbs {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var apsManager: APSManager!
        @Injected() var settings: SettingsManager!
        @Published var carbs: Decimal = 0
        @Published var date = Date()
        @Published var protein: Decimal = 0
        @Published var fat: Decimal = 0
        @Published var carbsRequired: Decimal?
        @Published var useFPU: Bool = false

        override func subscribe() {
            carbsRequired = provider.suggestion?.carbsReq
            useFPU = settingsManager.settings.useFPUconversion
        }

        func add() {
            guard carbs > 0 || fat > 0 || protein > 0 else {
                showModal(for: nil)
                return
            }

            // Convert fat and protein to carb equivalents and store as future carbs
            let fpucarb = 0.4 * protein + 0.9 * fat
            let fpus = (fat * 9.0 + protein * 4.0) / 100.0
            // Default is 1 hour (60 minutes)
            let timeInterval = 60 * settings.settings.minuteInterval
            // Deffault is 8 hours
            let timeCap = settings.settings.timeCap
            let adjustment = settings.settings.individualAdjustmentFactor
            var counter: Decimal = (fpus * 2) - 1.0
            counter = min(timeCap, counter)
            var roundedCounter: Decimal = 0
            NSDecimalRound(&roundedCounter, &counter, 0, .up)
            let carbequiv = (fpucarb / roundedCounter) * adjustment

            while counter > 0, counter <= timeCap {
                let newdate = 1.0 + trunc(Double(truncating: counter as NSNumber))
                carbsStorage.storeCarbs([
                    CarbsEntry(
                        id: UUID().uuidString, createdAt: date + (newdate * Double(timeInterval)), carbs: carbequiv,
                        enteredBy: CarbsEntry.manual
                    )
                ])
                counter -= 1
            }
            // Store the real carbs
            if carbs > 0 {
                carbsStorage
                    .storeCarbs([CarbsEntry(id: UUID().uuidString, createdAt: date, carbs: carbs, enteredBy: CarbsEntry.manual)])
            }

            if settingsManager.settings.skipBolusScreenAfterCarbs {
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else {
                showModal(for: .bolus(waitForSuggestion: true))
            }
        }
    }
}
