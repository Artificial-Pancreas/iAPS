import CoreData
import Foundation
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
        @Published var useFPUconversion: Bool = true
        @Published var dish: String = ""
        @Published var selection: Presets?
        @Published var summation: [String] = []
        @Published var maxCarbs: Decimal = 0

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            subscribeSetting(\.useFPUconversion, on: $useFPUconversion) { useFPUconversion = $0 }
            carbsRequired = provider.suggestion?.carbsReq
            maxCarbs = settings.settings.maxCarbs
        }

        func add() {
            guard carbs > 0 || fat > 0 || protein > 0 else {
                showModal(for: nil)
                return
            }
            carbs = min(carbs, maxCarbs)

            if useFPUconversion {
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
        }

        func addPresetToNewMeal() {
            let test: String = selection?.dish ?? "dontAdd"
            if test != "dontAdd" {
                summation.append(test)
            }
        }

        func addNewPresetToWaitersNotepad(_ dish: String) {
            summation.append(dish)
        }

        func addToSummation() {
            summation.append(selection?.dish ?? "")
        }

        func waitersNotepad() -> String {
            var filteredArray = summation.filter { !$0.isEmpty }

            if carbs == 0, protein == 0, fat == 0 {
                filteredArray = []
            }

            guard filteredArray != [] else {
                return ""
            }
            var carbs_: Decimal = 0.0
            var fat_: Decimal = 0.0
            var protein_: Decimal = 0.0
            var presetArray = [Presets]()

            coredataContext.performAndWait {
                let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
                try? presetArray = coredataContext.fetch(requestPresets)
            }
            var waitersNotepad = [String]()
            var stringValue = ""

            for each in filteredArray {
                let countedSet = NSCountedSet(array: filteredArray)
                let count = countedSet.count(for: each)
                if each != stringValue {
                    waitersNotepad.append("\(count) \(each)")
                }
                stringValue = each

                for sel in presetArray {
                    if sel.dish == each {
                        carbs_ += (sel.carbs)! as Decimal
                        fat_ += (sel.fat)! as Decimal
                        protein_ += (sel.protein)! as Decimal
                        break
                    }
                }
            }
            let extracarbs = carbs - carbs_
            let extraFat = fat - fat_
            let extraProtein = protein - protein_
            var addedString = ""

            if extracarbs > 0, filteredArray.isNotEmpty {
                addedString += "Additional carbs: \(extracarbs) "
            } else if extracarbs < 0 { addedString += "Removed carbs: \(extracarbs) " }

            if extraFat > 0, filteredArray.isNotEmpty {
                addedString += "Additional fat: \(extraFat) "
            } else if extraFat < 0 { addedString += "Removed fat: \(extraFat) " }

            if extraProtein > 0, filteredArray.isNotEmpty {
                addedString += "Additional protein: \(extraProtein) "
            } else if extraProtein < 0 { addedString += "Removed protein: \(extraProtein) " }

            if addedString != "" {
                waitersNotepad.append(addedString)
            }
            var waitersNotepadString = ""

            if waitersNotepad.count == 1 {
                waitersNotepadString = waitersNotepad[0]
            } else if waitersNotepad.count > 1 {
                for each in waitersNotepad {
                    if each != waitersNotepad.last {
                        waitersNotepadString += " " + each + ","
                    } else { waitersNotepadString += " " + each }
                }
            }
            return waitersNotepadString
        }
    }
}
