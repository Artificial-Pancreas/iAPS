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

            if useFPU {
                // ----------- FPU ------------------------------------------------
                let interval = settings.settings.minuteInterval // Interval betwwen carbs
                let timeCap = settings.settings.timeCap // Max Duration
                let adjustment = settings.settings.individualAdjustmentFactor
                let delay = settings.settings.delay // Tme before first future carb entry

                let kcal = protein * 4 + fat * 9
                let carbEquivalents = (kcal / 10) * adjustment
                let fpus = carbEquivalents / 10

                // Duration in hours used for extended boluses with Warsaw Method. Here used for total duration of the computed carbquivalents instead, excluding the configurable delay.
                var computedDuration = 0
                switch fpus {
                case ..<2:
                    computedDuration = 3
                case 2 ... 3:
                    computedDuration = 4
                case 3 ... 4:
                    computedDuration = 5
                default:
                    computedDuration = timeCap
                }

                // Size of each created carb equivalent if 60 minutes interval
                var carbPortions: Decimal = carbEquivalents / Decimal(computedDuration)
                // Adjust for interval setting other than 60 minutes
                carbPortions /= Decimal(60 / interval)
                // Number of equivalents
                var numberOfPortions = carbEquivalents / carbPortions
                // Only use delay in first loop
                var firstIndex = true
                // New date for each carb equivalent
                var useDate = Date()
                
                // Loop and save all carb entries
                while carbEquivalents > 0, numberOfPortions > 0 {
                    if firstIndex {
                        useDate = date.addingTimeInterval(delay.minutes.timeInterval)
                        firstIndex = false
                    } else { useDate = date.addingTimeInterval(interval.minutes.timeInterval) }
                    carbsStorage.storeCarbs([
                        CarbsEntry(
                            id: UUID().uuidString, createdAt: useDate, carbs: carbPortions,
                            enteredBy: CarbsEntry.manual
                        )
                    ])
                    numberOfPortions -= 1
                    date = useDate // Update date
                }
            }
            // ------------------------- END OF TPU -----------------------------------------------

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
