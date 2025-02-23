import AppIntents
import Foundation
import Intents

struct MealPresetEntity: AppEntity, Identifiable {
    static var defaultQuery = MealPresetQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meals"
}

enum MealPresetIntentError: Error {
    case StateIntentUnknownError
    case NoPresets
}

struct ApplyMealPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "iAPS Meal Presets"
    static var description = IntentDescription("Allow to use iAPS Meal Presets")
    internal var intentRequest: MealPresetIntentRequest

    init() {
        intentRequest = MealPresetIntentRequest()
    }

    @Parameter(title: "Preset") var preset: MealPresetEntity?

    @Parameter(
        title: "Confirm Before activating",
        description: "If toggled, you will need to confirm before activating",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyMealPresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately applying \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        })
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            let presetToApply: MealPresetEntity
            if let preset = preset {
                presetToApply = preset
            } else {
                presetToApply = try await $preset.requestDisambiguation(
                    among: intentRequest.fetchPresets(),
                    dialog: "Which meal preset would you like to use?"
                )
            }

            let displayName: String = presetToApply.id
            if confirmBeforeApplying {
                try await requestConfirmation(
                    result: .result(dialog: "Are you sure you want to use the meal preset \(displayName)?")
                )
            }

            let preset = try intentRequest.findPreset(displayName)
            let finalOverrideApply = try intentRequest.enactPreset(preset)
            let isDone = finalOverrideApply != nil ? true : false

            let displayDetail: String = isDone ?
                NSLocalizedString("The Meal", comment: "") + " \(displayName)  " +
                NSLocalizedString("has been added to iAPS", comment: "") : "Adding Meal Failed"
            return .result(
                dialog: IntentDialog(stringLiteral: displayDetail)
            )
        } catch {
            throw error
        }
    }
}

struct MealPresetQuery: EntityQuery {
    internal var intentRequest: MealPresetIntentRequest

    init() {
        intentRequest = MealPresetIntentRequest()
    }

    func entities(for identifiers: [MealPresetEntity.ID]) async throws -> [MealPresetEntity] {
        let presets = intentRequest.fetchIDs(identifiers)
        return presets
    }

    func suggestedEntities() async throws -> [MealPresetEntity] {
        let presets = try intentRequest.fetchPresets()
        return presets
    }
}

final class MealPresetIntentRequest: BaseIntentsRequest {
    func fetchPresets() throws -> ([MealPresetEntity]) {
        let presets = coreDataStorage.fetchMealPresets().flatMap { preset -> [MealPresetEntity] in
            [MealPresetEntity(id: preset.dish ?? "")]
        }
        return presets
    }

    func findPreset(_ name: String) throws -> Presets {
        let presetFound = coreDataStorage.fetchMealPresets().filter({ $0.dish == name })
        guard let preset = presetFound.first else { throw MealPresetIntentError.NoPresets }
        return preset
    }

    func fetchIDs(_: [MealPresetEntity.ID]) -> [MealPresetEntity] {
        let presets = coreDataStorage.fetchMealPresets()
            .map { preset -> MealPresetEntity in
                let dish = preset.dish ?? ""
                return MealPresetEntity(id: dish)
            }
        return presets
    }

    func enactPreset(_ preset: Presets) throws -> String? {
        guard let mealPreset = coreDataStorage.fetchMealPreset(preset.dish ?? "") else {
            return nil
        }

        let quantityCarbs = (mealPreset.carbs ?? 0) as Decimal
        let quantityFat = (mealPreset.fat ?? 0) as Decimal
        let quantityProtein = (mealPreset.protein ?? 0) as Decimal

        guard quantityCarbs >= 0.0 || quantityFat >= 0.0 || quantityProtein >= 0.0 else {
            return nil
        }

        let carbs = min(quantityCarbs, settingsManager.settings.maxCarbs)
        let now = Date.now

        carbsStorage.storeCarbs(
            [CarbsEntry(
                id: UUID().uuidString,
                createdAt: now,
                actualDate: now,
                carbs: carbs,
                fat: quantityFat,
                protein: quantityProtein,
                note: mealPreset.dish ?? "",
                enteredBy: CarbsEntry.manual,
                isFPU: (quantityFat > 0 || quantityProtein > 0) ? true : false
            )]
        )

        return "OK"
    }
}
