import CoreData
import Foundation
import SwiftUI

extension AddCarbs {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var storage: FileStorage!
        @Injected() private var carbsStorage: CarbsStorage!
        @Injected() private var apsManager: APSManager!
        @Injected() private var overrideStorage: OverrideStorage!
        @Injected() private var overrideManager: OverrideManager!

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

        /// The meal handed to Bolus, pushed on the navigation stack. SwiftUI sets it back to nil when Bolus is popped
        @Published var bolusDraft: Bolus.MealDraft? {
            // a real pop (a cancelled back swipe leaves it set): Bolus discards the meal
            didSet { if bolusDraft == nil { oldValue?.popped.fire() } }
        }
        /// A save or a hand-off is running (or the meal is saved and the view is closing): no second one
        private var adding = false

        let now = Date.now

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() async {
            carbsRequired = appCoordinator.suggested.value?.carbsReq
            let settings = appCoordinator.settings.value
            id = settings.profileID
            maxCarbs = settings.maxCarbs
            skipBolus = settings.skipBolusScreenAfterCarbs
            useFPUconversion = settings.useFPUconversion
            ai = settings.ai
            mealViewMicronutrients = settings.mealViewMicronutrients
        }

        func add(_ continue_: Bool, fetch: Bool) {
            guard beginAdding() else { return }
            Task {
                carbs = min(carbs, maxCarbs)
                id_ = UUID().uuidString

                let entry = CarbsEntry(
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
                )
                await add(continue_, fetch: fetch, entry: entry)
            }
        }

        func addAIFood(_ continue_: Bool, fetch: Bool, food: FoodItemDetailed, date: Date?) {
            guard beginAdding() else { return }
            Task {
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

                let entry = CarbsEntry(
                    id: id_,
                    createdAt: now,
                    // no time picked: the meal's time, as for a manual meal (Bolus and the FPUs need one)
                    actualDate: date ?? self.date,
                    carbs: carbs,
                    fat: fat,
                    protein: protein,
                    fiber: fibers,
                    note: note,
                    enteredBy: CarbsEntry.manual,
                    isFPU: false,
                    micronutrient: micronutrients
                )

                await add(continue_, fetch: fetch, entry: entry)
            }
        }

        /// A double tap must not save twice (the FPU entries get new ids) or push Bolus twice
        private func beginAdding() -> Bool {
            guard !adding, bolusDraft == nil else { return false }
            adding = true
            return true
        }

        private func add(_ continue_: Bool, fetch: Bool, entry: CarbsEntry) async {
            if hypoTreatment {
                await hypo()
            }
            let fat = entry.fat ?? 0
            let protein = entry.protein ?? 0
            let fiber = entry.fiber ?? 0
            let hasMicronutrients = entry.micronutrient != nil

            let empty = entry.carbs <= 0 && fat <= 0 && protein <= 0 && fiber <= 0 && !hasMicronutrients

            if (skipBolus && !continue_ && !fetch) || hypoTreatment {
                await storeMeal(entry)
            } else if entry.carbs > 0 {
                // Bolus stores it (or not, on back / cancel)
                bolusDraft = Bolus.MealDraft(entry: entry)
                adding = false
            } else if !empty {
                await storeMeal(entry)
            } else {
                hideModal()
            }
        }

        /// Saves the meal (row, then carbs), refreshes the suggestion and closes
        private func storeMeal(_ entry: CarbsEntry) async {
            await carbsStorage.storeMeal(entry)
            _ = try? await apsManager.determineBasal(temporaryCarbs: nil)
            showModal(for: nil)
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

                coredataContext.delete(selection!)
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

        private func hypo() async {
            // Cancel any override that is already active
            // TODO: we are cancelling an override, but below we might not start a hypo override. Is this intended?
            await overrideManager.cancelActiveOverride()

            guard let profileID = id, profileID != "None" else {
                return
            }
            // Enable New Override
            if profileID == "Hypo Treatment" {
                // transient, non-persisted override preset
                let override = OverridePresetsSnapshot(
                    id: profileID,
                    name: "📉",
                    percentage: 90,
                    indefinite: false,
                    duration: 45,
                    target: 117,
                    advancedSettings: true,
                    smbIsOff: true,
                    date: Date.now,
                )

                // the preset does not exist, so `fromSavedPreset: true` is a lie, but when determining the present name - this case is handled and the override name is set to the hypo emoji
                // TODO: instead, the preset name should become part of the override entity, so that we don't need to fetch and reconstruct it every time later on
                await overrideManager.activateOverride(preset: override, fromSavedPreset: true)
            } else if let preset = await overrideStorage.fetchOverridePreset(id: profileID) {
                await overrideManager.activateOverride(preset: preset, fromSavedPreset: true)
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
