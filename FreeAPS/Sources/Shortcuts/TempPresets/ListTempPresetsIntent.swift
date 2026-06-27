import AppIntents
import Foundation

struct tempPresetsQuery: EntityQuery {
    @MainActor func entities(for identifiers: [TempPreset.ID]) async throws -> [TempPreset] {
        let request = TempPresetsIntentRequest()
        try await BaseIntentsRequest.awaitStartup()

        let tempTargets = await request.fetchIDs(identifiers)
        return tempTargets
    }

    @MainActor func suggestedEntities() async throws -> [TempPreset] {
        let request = TempPresetsIntentRequest()
        try await BaseIntentsRequest.awaitStartup()

        let tempTargets = await request.fetchAll()
        return tempTargets
    }
}
