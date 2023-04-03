import CoreData
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
        @Published var useFPU: Bool = true
        @Published var dish: String = ""
        @Published var selection: Presets?
        @Published var summation: [String] = []

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        // @Environment(\.managedObjectContext) var moc

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
                // -------------------------- FPU--------------------------------------
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
                case 2 ..< 3:
                    computedDuration = 4
                case 3 ..< 4:
                    computedDuration = 5
                default:
                    computedDuration = timeCap
                }

                // Size of each created carb equivalent if 60 minutes interval
                var equivalent: Decimal = carbEquivalents / Decimal(computedDuration)
                // Adjust for interval setting other than 60 minutes
                equivalent /= Decimal(60 / interval)
                // Round to 1 fraction digit
                // equivalent = Decimal(round(Double(equivalent * 10) / 10))
                let roundedEquivalent: Double = round(Double(equivalent * 10)) / 10
                equivalent = Decimal(roundedEquivalent)
                // Number of equivalents
                var numberOfEquivalents = carbEquivalents / equivalent
                // Only use delay in first loop
                var firstIndex = true
                // New date for each carb equivalent
                var useDate = date
                // Group and Identify all FPUs together
                let fpuID = UUID().uuidString

                // Create an array of all future carb equivalents.
                var futureCarbArray = [CarbsEntry]()
                while carbEquivalents > 0, numberOfEquivalents > 0 {
                    if firstIndex {
                        useDate = useDate.addingTimeInterval(delay.minutes.timeInterval)
                        firstIndex = false
                    } else { useDate = useDate.addingTimeInterval(interval.minutes.timeInterval) }

                    let eachCarbEntry = CarbsEntry(
                        id: UUID().uuidString, createdAt: useDate, carbs: equivalent, enteredBy: CarbsEntry.manual, isFPU: true,
                        fpuID: fpuID
                    )
                    futureCarbArray.append(eachCarbEntry)
                    numberOfEquivalents -= 1
                }
                // Save the array
                if carbEquivalents > 0 {
                    carbsStorage.storeCarbs(futureCarbArray)
                }
            } // ------------------------- END OF TPU ----------------------------------------

            // Store the real carbs
            if carbs > 0 {
                carbsStorage
                    .storeCarbs([CarbsEntry(
                        id: UUID().uuidString,
                        createdAt: date,
                        carbs: carbs,
                        enteredBy: CarbsEntry.manual,
                        isFPU: false, fpuID: nil
                    )])
            }

            if settingsManager.settings.skipBolusScreenAfterCarbs {
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else {
                showModal(for: .bolus(waitForSuggestion: true))
            }
        }

        func deletePreset() {
            if selection != nil {
                try? coredataContext.delete(selection!)
                try? coredataContext.save()
                carbs = 0
                fat = 0
                protein = 0
            }
            selection = nil
        }

        func removePresetFromNewMeal() {
            let a = summation.firstIndex(where: { $0 == selection?.dish! })
            if a != nil, summation[a ?? 0] != "" {
                summation.remove(at: a!)
            }
            if (selection?.carbs ?? 0) as Decimal == carbs, (selection?.fat ?? 0) as Decimal == fat,
               (selection?.protein ?? 0) as Decimal == protein
            {
                carbs = 0
                fat = 0
                protein = 0
            }
        }

        func addPresetToNewMeal() {
            let test: String = selection?.dish ?? "dontAdd"
            if test != "dontAdd" {
                summation.append(test)
            }
        }

        func fullMeal() -> [String] {
            let filteredArray = summation.filter { !$0.isEmpty }
            return filteredArray
        }
    }
}
