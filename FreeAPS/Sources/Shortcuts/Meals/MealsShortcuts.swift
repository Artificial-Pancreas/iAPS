import AppIntents
import Foundation
import Intents

struct MealPresetEntity: AppEntity, Identifiable, Hashable {
    static let defaultQuery = MealPresetQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meals"
}

enum MealPresetIntentError: Error {
    case StateIntentUnknownError
    case NoPresets
}

struct ApplyMealPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "iAPS Meal Presets"
    static let description = IntentDescription("Allow to use iAPS Meal Presets")

    @Parameter(title: "Preset") var preset: MealPresetEntity?

    @Parameter(
        title: "Confirm Before activating",
        description: "If toggled, you will need to confirm before activating",
        default: false
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
        let presetToApply: MealPresetEntity

        let intentRequest = MealPresetIntentRequest()
        try await BaseIntentsRequest.awaitStartup()

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
            // deprecated, but the fix is iOS 18+ only
            try await requestConfirmation(
                result: .result(dialog: "Are you sure you want to use the meal preset \(displayName)?")
            )
        }

        let preset = try await intentRequest.findPreset(displayName)
        let finalOverrideApply = try await intentRequest.enactPreset(preset)
        let isDone = finalOverrideApply != nil

        let displayDetail: String = isDone ?
            NSLocalizedString("The Meal", comment: "") + " \(displayName) " +
            NSLocalizedString("has been added to iAPS", comment: "") : "Adding Meal Failed"
        return .result(
            dialog: IntentDialog(stringLiteral: displayDetail)
        )
    }
}

struct MealPresetQuery: EntityQuery {
    @MainActor func entities(for identifiers: [MealPresetEntity.ID]) async throws -> [MealPresetEntity] {
        let intentRequest = MealPresetIntentRequest()
        try await BaseIntentsRequest.awaitStartup()

        let presets = await intentRequest.fetchIDs(identifiers)
        return presets
    }

    @MainActor func suggestedEntities() async throws -> [MealPresetEntity] {
        let intentRequest = MealPresetIntentRequest()
        try await BaseIntentsRequest.awaitStartup()

        let presets = await intentRequest.fetchPresets()
        return presets
    }
}

final class MealPresetIntentRequest: BaseIntentsRequest {
    func fetchPresets() async -> ([MealPresetEntity]) {
        let presets = await coreDataStorage.fetchMealPresets()
            .compactMap { preset -> MealPresetEntity in
                MealPresetEntity(id: preset.dish ?? "Empty")
            }
        return presets.filter({ $0.id != "Empty" && $0.id != " " }).removeDublicates()
    }

    func findPreset(_ name: String) async throws -> PresetsSnapshot {
        let presetFound = await coreDataStorage.fetchMealPresets().filter({ $0.dish == name })
        guard let preset = presetFound.first else { throw MealPresetIntentError.NoPresets }
        return preset
    }

    func fetchIDs(_: [MealPresetEntity.ID]) async -> [MealPresetEntity] {
        let presets = await coreDataStorage.fetchMealPresets()
            .map { preset -> MealPresetEntity in
                let dish = preset.dish ?? "Empty"
                return MealPresetEntity(id: dish)
            }
        return presets.filter({ $0.id != "Empty" && $0.id != " " })
    }

    func enactPreset(_ preset: PresetsSnapshot) async throws -> String? {
        guard let mealPreset = await coreDataStorage.fetchMealPreset(preset.dish ?? "") else {
            return nil
        }

        let quantityCarbs = (mealPreset.carbs ?? 0) as Decimal
        let quantityFat = (mealPreset.fat ?? 0) as Decimal
        let quantityProtein = (mealPreset.protein ?? 0) as Decimal
        let quantityFiber = (mealPreset.fiber ?? 0) as Decimal

        guard quantityCarbs > 0.0 || quantityFat > 0.0 || quantityProtein > 0.0 else {
            return nil
        }

        let settings = await settingsManager.settings

        let carbs = min(quantityCarbs, settings.maxCarbs)
        let now = Date.now

        await carbsStorage.storeCarbs(
            [CarbsEntry(
                id: UUID().uuidString,
                createdAt: now,
                actualDate: now,
                carbs: carbs,
                fat: quantityFat,
                protein: quantityProtein,
                fiber: quantityFiber,
                note: mealPreset.dish ?? "",
                enteredBy: CarbsEntry.shortcut,
                isFPU: (quantityFat > 0 || quantityProtein > 0) ? true : false
            )]
        )

        return "OK"
    }
}
