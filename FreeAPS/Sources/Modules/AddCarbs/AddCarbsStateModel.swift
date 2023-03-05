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

            let interval = settings.settings.minuteInterval
            let timeCap = settings.settings.timeCap * (60 / Decimal(interval))
            let adjustment = settings.settings.individualAdjustmentFactor
            let delay = settings.settings.delay

            // Convert fat and protein to carb equivalents and store as future carbs
            let fpucarb = 0.4 * protein + 0.9 * fat
            let fpus = (fat * 9.0 + protein * 4.0) / 100.0
            var counter: Decimal = (fpus * 2) - 1.0
            counter = min(timeCap, counter)
            var roundedCounter: Decimal = 0
            NSDecimalRound(&roundedCounter, &counter, 0, .up)
            let carbequiv = (fpucarb / roundedCounter) * adjustment
            let firstDate = date.addingTimeInterval(delay.minutes.timeInterval)
            var previousDate = date

            while counter > 0, carbequiv > 0 {
                var useDate = date + 1 * Double(interval * 60)
                // Fix Interval and Delay
                useDate = max(previousDate.addingTimeInterval(interval.minutes.timeInterval), useDate, firstDate)
                if useDate > previousDate {
                    carbsStorage.storeCarbs([
                        CarbsEntry(
                            id: UUID().uuidString, createdAt: useDate, carbs: carbequiv,
                            enteredBy: CarbsEntry.manual
                        )
                    ])
                }
                previousDate = useDate
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
