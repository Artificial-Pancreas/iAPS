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

        @Published var combinedPresets: [(preset: Presets?, portions: Int)] = []

        let now = Date.now

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
        let coredataContextBackground = CoreDataStack.shared.persistentContainer.newBackgroundContext()

        override func subscribe() {
            carbsRequired = provider.suggestion?.carbsReq
            id = settings.settings.profileID
            maxCarbs = settings.settings.maxCarbs
            skipBolus = settingsManager.settings.skipBolusScreenAfterCarbs
            useFPUconversion = settingsManager.settings.useFPUconversion
        }

        func add(_ continue_: Bool, fetch: Bool) {
            guard carbs > 0 || fat > 0 || protein > 0 else {
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
                note: note,
                enteredBy: CarbsEntry.manual,
                isFPU: false
            )]

            if hypoTreatment { hypo() }

            if (skipBolus && !continue_ && !fetch) || hypoTreatment {
                carbsStorage.storeCarbs(carbsToStore)
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else if carbs > 0 {
                saveToCoreData(carbsToStore)
                showModal(for: .bolus(waitForSuggestion: true, fetch: true))
            } else if !empty {
                carbsStorage.storeCarbs(carbsToStore)
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else {
                hideModal()
            }
        }

        func deletePreset() {
            if selection != nil {
                carbs -= ((selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
                fat -= ((selection?.fat ?? 0) as NSDecimalNumber) as Decimal
                protein -= ((selection?.protein ?? 0) as NSDecimalNumber) as Decimal
                try? coredataContext.delete(selection!)
                try? coredataContext.save()
            }
        }

        func removePresetFromNewMeal() {
            if let index = combinedPresets.firstIndex(where: { $0.preset == selection }) {
                if combinedPresets[index].portions > 1 {
                    combinedPresets[index].portions -= 1
                } else if combinedPresets[index].portions == 1 {
                    combinedPresets.remove(at: index)
                    selection = nil
                }
            }
        }

        func addPresetToNewMeal() {
            if let index = combinedPresets.firstIndex(where: { $0.preset == selection }) {
                combinedPresets[index].portions += 1
            } else {
                combinedPresets.append((selection, 1))
            }
        }

        func waitersNotepad() -> [String] {
            guard combinedPresets.isNotEmpty else { return [] }

            if carbs == 0, protein == 0, fat == 0 {
                return []
            }

            var presetsString: [String] = combinedPresets.map { item in
                "\(item.portions) \(item.preset?.dish ?? "")"
            }

            if presetsString.isNotEmpty {
                let totCarbs = combinedPresets
                    .compactMap({ each in (each.preset?.carbs ?? 0) as Decimal * Decimal(each.portions) })
                    .reduce(0, +)
                let totFat = combinedPresets.compactMap({ each in (each.preset?.fat ?? 0) as Decimal * Decimal(each.portions) })
                    .reduce(0, +)
                let totProtein = combinedPresets
                    .compactMap({ each in (each.preset?.protein ?? 0) as Decimal * Decimal(each.portions) }).reduce(0, +)

                if carbs > totCarbs {
                    presetsString.append("+ \(carbs - totCarbs) carbs")
                } else if carbs < totCarbs {
                    presetsString.append("- \(totCarbs - carbs) carbs")
                }

                if fat > totFat {
                    presetsString.append("+ \(fat - totFat) fat")
                } else if fat < totFat {
                    presetsString.append("- \(totFat - fat) fat")
                }

                if protein > totProtein {
                    presetsString.append("+ \(protein - totProtein) protein")
                } else if protein < totProtein {
                    presetsString.append("- \(totProtein - protein) protein")
                }
            }

            return presetsString.removeDublicates()
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

                    self.carbs = Decimal(mealToEdit.first?.carbs ?? 0)
                    self.fat = Decimal(mealToEdit.first?.fat ?? 0)
                    self.protein = Decimal(mealToEdit.first?.protein ?? 0)
                    self.note = mealToEdit.first?.note ?? ""
                    self.id_ = mealToEdit.first?.id ?? ""
                }
            }
        }

        func subtract() {
            let presetCarbs = ((selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
            if carbs != 0, carbs - presetCarbs >= 0 {
                carbs -= presetCarbs
            } else { carbs = 0 }

            let presetFat = ((selection?.fat ?? 0) as NSDecimalNumber) as Decimal
            if fat != 0, presetFat >= 0 {
                fat -= presetFat
            } else { fat = 0 }

            let presetProtein = ((selection?.protein ?? 0) as NSDecimalNumber) as Decimal
            if protein != 0, presetProtein >= 0 {
                protein -= presetProtein
            } else { protein = 0 }

            removePresetFromNewMeal()
        }

        func plus() {
            carbs += ((selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
            fat += ((selection?.fat ?? 0) as NSDecimalNumber) as Decimal
            protein += ((selection?.protein ?? 0) as NSDecimalNumber) as Decimal
            addPresetToNewMeal()
        }

        func addU(_ selection: Presets?) {
            carbs += ((selection?.carbs ?? 0) as NSDecimalNumber) as Decimal
            fat += ((selection?.fat ?? 0) as NSDecimalNumber) as Decimal
            protein += ((selection?.protein ?? 0) as NSDecimalNumber) as Decimal
            addPresetToNewMeal()
        }

        func saveToCoreData(_ stored: [CarbsEntry]) {
            CoreDataStorage().saveMeal(stored, now: now)
        }

        private var empty: Bool {
            carbs <= 0 && fat <= 0 && protein <= 0
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
    }
}
