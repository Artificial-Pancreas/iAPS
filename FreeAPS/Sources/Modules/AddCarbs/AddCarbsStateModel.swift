import CoreData
import Foundation
import SwiftUI

extension AddCarbs {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var apsManager: APSManager!
        @Injected() var settings: SettingsManager!
        @Injected() var nightscoutManager: NightscoutManager!

        @Published var carbs: Decimal = 0
        @Published var date = Date()
        @Published var protein: Decimal = 0
        @Published var fiber: Decimal = 0
        @Published var fat: Decimal = 0
        @Published var carbsRequired: Decimal?
        @Published var useFPUconversion: Bool = false
        @Published var dish: String = ""
        @Published var selection: Presets?
        @Published var maxCarbs: Decimal = 0
        @Published var note: String = ""
        @Published var id_: String = ""
        @Published var skipBolus: Bool = false
        @Published var id: String?
        @Published var hypoTreatment = false
        @Published var presetToEdit: Presets?
        @Published var edit = false
        @Published var ai = false
        @Published var mealViewMicronutrients = false

        @Published var micronutrient: [MicronutrientValue] = []

        @Published var combinedPresets: [(preset: Presets?, portions: Double)] = []

        let now = Date.now

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        let coredataContextBackground = CoreDataStack.shared.persistentContainer.newBackgroundContext()

        override func subscribe() {
            carbsRequired = provider.suggestion?.carbsReq
            id = settings.settings.profileID
            maxCarbs = settings.settings.maxCarbs
            skipBolus = settingsManager.settings.skipBolusScreenAfterCarbs
            useFPUconversion = settingsManager.settings.useFPUconversion
            ai = settingsManager.settings.ai
            mealViewMicronutrients = settingsManager.settings.mealViewMicronutrients
        }

        func add(_ continue_: Bool, fetch: Bool) {
            carbs = min(carbs, maxCarbs)
            id_ = UUID().uuidString

            let carbsToStore = [CarbsEntry(
                id: id_,
                createdAt: now,
                actualDate: date,
                carbs: carbs,
                fat: fat,
                protein: protein,
                fiber: fiber,
                note: note,
                enteredBy: CarbsEntry.manual,
                isFPU: false,
                micronutrient: micronutrient
            )]
            add(continue_, fetch: fetch, carbsToStore: carbsToStore)
        }

        func addAIFood(_ continue_: Bool, fetch: Bool, food: FoodItemDetailed, date: Date?) {
            var carbs = food.nutrientInThisPortion(.carbs) ?? 0
            let fat = food.nutrientInThisPortion(.fat) ?? 0
            let protein = food.nutrientInThisPortion(.protein) ?? 0
            let fibers = food.nutrientInThisPortion(.fiber) ?? 0
            let note = food.name

            let micronutrients = food.micronutrient.compactMap { value -> MicronutrientValue? in
                guard let amount = food.micronutrientInThisPortion(value.substance),
                      amount > 0
                else {
                    return nil
                }

                return MicronutrientValue(
                    substance: value.substance,
                    amount: amount,
                    amountPer100: value.amountPer100
                )
            }

            guard carbs > 0 || fat > 0 || protein > 0 || fibers > 0 || !micronutrients.isEmpty else {
                showModal(for: nil)
                return
            }

            carbs = min(carbs, maxCarbs)
            id_ = UUID().uuidString

            let carbsToStore = [CarbsEntry(
                id: id_,
                createdAt: now,
                actualDate: date,
                carbs: carbs,
                fat: fat,
                protein: protein,
                fiber: fibers,
                note: note,
                enteredBy: CarbsEntry.manual,
                isFPU: false,
                micronutrient: micronutrients
            )]

            add(continue_, fetch: fetch, carbsToStore: carbsToStore)
        }

        func add(_ continue_: Bool, fetch: Bool, carbsToStore: [CarbsEntry]) {
            if hypoTreatment { hypo() }
            let carbs = carbsToStore.map(\.carbs).reduce(0, +)
            let fat = carbsToStore.compactMap(\.fat).reduce(0, +)
            let protein = carbsToStore.compactMap(\.protein).reduce(0, +)
            let fiber = carbsToStore.compactMap(\.fiber).reduce(0, +)
            var hasMicronutrients = false

            // To Do: Remove
            print("Micros: true")
            if let last = carbsToStore.last {
                if let items = last.micronutrient {
                    hasMicronutrients = true
                    for item in items {
                        print("Micros:  \(item.substance) " + item.formattedAmount)
                    }
                }
            }

            let empty = carbs <= 0 && fat <= 0 && protein <= 0 && fiber <= 0 && !hasMicronutrients

            if (skipBolus && !continue_ && !fetch) || hypoTreatment {
                saveToCoreData(carbsToStore, savedToFile: true)
                carbsStorage.storeCarbs(carbsToStore)
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else if carbs > 0 {
                saveToCoreData(carbsToStore, savedToFile: false)
                showModal(for: .bolus(waitForSuggestion: true, fetch: true))
            } else if !empty {
                saveToCoreData(carbsToStore, savedToFile: true)
                carbsStorage.storeCarbs(carbsToStore)
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else {
                hideModal()
            }
        }

        private func saveMicro(
            from foodItem: FoodItemDetailed,
            to carbDataForStats: Meals
        ) {
            for value in foodItem.micronutrient {
                guard let amount = foodItem.micronutrientInThisPortion(value.substance),
                      amount > 0
                else { continue }

                let micro = Micronutrient(context: coredataContext)
                micro.id = UUID()
                micro.name = value.name
                micro.type = value.substance.coreDataType
                micro.unit = value.unit
                micro.amount = NSDecimalNumber(decimal: amount)
                micro.meal = carbDataForStats
            }
        }

        func deletePreset() {
            if selection != nil {
                carbs -= ((selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                fat -= ((selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                protein -= ((selection?.protein ?? 0) as NSDecimalNumber) as Decimal

                if let presetMicros = selection?.micronutrientValuesTyped() {
                    mergeMicronutrients(presetMicros, multiplier: -1)
                }

                try? coredataContext.delete(selection!)
                try? coredataContext.save()
            }
        }

        func removePresetFromNewMeal() {
            if let index = combinedPresets.firstIndex(where: { $0.preset == selection }) {
                if combinedPresets[index].portions > 0.5 {
                    combinedPresets[index].portions -= 0.5
                } else if combinedPresets[index].portions == 0.5 {
                    combinedPresets.remove(at: index)
                    selection = nil
                }
            }
        }

        func addPresetToNewMeal(half: Bool = false) {
            if let index = combinedPresets.firstIndex(where: { $0.preset == selection }) {
                combinedPresets[index].portions += (half ? 0.5 : 1)
            } else {
                combinedPresets.append((selection, 1))
            }
        }

        func loadEntries(_ editMode: Bool) {
            if editMode {
                coredataContext.performAndWait {
                    var mealToEdit = [Meals]()
                    let requestMeal = Meals.fetchRequest() as NSFetchRequest<Meals>
                    let sortMeal = NSSortDescriptor(key: "createdAt", ascending: false)
                    requestMeal.sortDescriptors = [sortMeal]
                    requestMeal.fetchLimit = 1
                    try? mealToEdit = self.coredataContext.fetch(requestMeal)

                    self.carbs = (mealToEdit.first?.carbs ?? 0) as Decimal
                    self.fat = (mealToEdit.first?.fat ?? 0) as Decimal
                    self.protein = (mealToEdit.first?.protein ?? 0) as Decimal
                    self.fiber = (mealToEdit.first?.fiber ?? 0) as Decimal
                    self.note = mealToEdit.first?.note ?? ""
                    self.id_ = mealToEdit.first?.id ?? ""
                }
            }
        }

        func addU(_ selection: Presets?) {
            carbs += ((selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
            fat += ((selection?.fat ?? 0) as NSDecimalNumber) as Decimal
            protein += ((selection?.protein ?? 0) as NSDecimalNumber) as Decimal
            fiber += ((selection?.fiber ?? 0) as NSDecimalNumber) as Decimal

            if let presetMicros = selection?.micronutrientValuesTyped() {
                mergeMicronutrients(presetMicros, multiplier: 1)
            }

            addPresetToNewMeal()
        }

        func saveToCoreData(_ stored: [CarbsEntry], savedToFile: Bool) {
            print("Meal Flow 1: saving to CoreData")

            for a in stored {
                guard let b = a.micronutrient else { continue }
                for c in b {
                    print("Meal Flow 1: Micros: " + c.name + " " + c.formattedAmount)
                }
            }

            CoreDataStorage().saveMeal(stored, now: now, savedToFile: savedToFile)
        }

        private func hypo() {
            let os = OverrideStorage()

            // Cancel any eventual Other Override already active
            if let activeOveride = os.fetchLatestOverride().first {
                let presetName = os.isPresetName()
                // Is the Override a Preset?
                if let preset = presetName {
                    if let duration = os.cancelProfile() {
                        // Update in Nightscout
                        nightscoutManager.editOverride(preset, duration, activeOveride.date ?? Date.now)
                    }
                } else if activeOveride.isPreset { // Because hard coded Hypo treatment isn't actually a preset
                    if let duration = os.cancelProfile() {
                        nightscoutManager.editOverride("📉", duration, activeOveride.date ?? Date.now)
                    }
                } else {
                    let nsString = activeOveride.percentage.formatted() != "100" ? activeOveride.percentage
                        .formatted() + " %" : "Custom"
                    if let duration = os.cancelProfile() {
                        nightscoutManager.editOverride(nsString, duration, activeOveride.date ?? Date.now)
                    }
                }
            }

            guard let profileID = id, profileID != "None" else {
                return
            }
            // Enable New Override
            if profileID == "Hypo Treatment" {
                let override = OverridePresets(context: coredataContextBackground)
                override.percentage = 90
                override.smbIsOff = true
                override.duration = 45
                override.name = "📉"
                override.advancedSettings = true
                override.target = 117
                override.date = Date.now
                override.indefinite = false
                os.overrideFromPreset(override, profileID)
                // Upload to Nightscout
                nightscoutManager.uploadOverride(
                    "📉",
                    Double(45),
                    override.date ?? Date.now
                )
            } else {
                os.activatePreset(profileID)
            }
        }

        private func mergeMicronutrients(
            _ values: [MicronutrientValue],
            multiplier: Decimal
        ) {
            var dict: [MicroNutrient: MicronutrientValue] = Dictionary(
                uniqueKeysWithValues: micronutrient.map { ($0.substance, $0) }
            )

            for value in values {
                let adjustedAmount = value.amount * multiplier
                let adjustedPer100 = value.amountPer100 * multiplier

                if let existing = dict[value.substance] {
                    let newAmount = max(0, existing.amount + adjustedAmount)
                    let newPer100 = max(0, existing.amountPer100 + adjustedPer100)

                    dict[value.substance] = MicronutrientValue(
                        substance: value.substance,
                        amount: newAmount,
                        amountPer100: newPer100
                    )
                } else if adjustedAmount > 0 || adjustedPer100 > 0 {
                    dict[value.substance] = MicronutrientValue(
                        substance: value.substance,
                        amount: adjustedAmount,
                        amountPer100: adjustedPer100
                    )
                }
            }

            micronutrient = dict.values
                .filter { $0.amount > 0 || $0.amountPer100 > 0 }
                .sorted { $0.name < $1.name }
        }

        var aggregatedMicronutrients: [MicroNutrient: Decimal] {
            var result: [MicroNutrient: Decimal] = [:]

            for value in micronutrient {
                result[value.substance, default: 0] += value.amount
            }

            return result
        }
    }
}
