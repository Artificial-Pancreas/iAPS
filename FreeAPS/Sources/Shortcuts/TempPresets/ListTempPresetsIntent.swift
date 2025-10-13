import AppIntents
import Foundation

struct ListTempPresetsIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static let title: LocalizedStringResource = "Choose Temporary Presets"

    // Description of the action in the Shortcuts app
    static let description = IntentDescription(
        "Allow to list and choose a specific temporary Preset.",
        categoryName: "Navigation"
    )

    @Parameter(title: "Preset") var preset: tempPreset?

    static var parameterSummary: some ParameterSummary {
        Summary("Choose the temp preset  \(\.$preset)")
    }

    @MainActor func perform() async throws -> some ReturnsValue<tempPreset> {
        .result(
            value: preset!
        )
    }
}

struct tempPresetsQuery: EntityQuery {
    func entities(for identifiers: [tempPreset.ID]) async throws -> [tempPreset] {
        let request = TempPresetsIntentRequest()
        let tempTargets = request.fetchIDs(identifiers)
        return tempTargets
    }

    func suggestedEntities() async throws -> [tempPreset] {
        let request = TempPresetsIntentRequest()
        let tempTargets = request.fetchAll()
        return tempTargets
    }
}
