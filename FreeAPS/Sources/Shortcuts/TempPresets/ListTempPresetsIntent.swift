import AppIntents
import Foundation

struct tempPresetsQuery: EntityQuery {
    func entities(for identifiers: [TempPreset.ID]) async throws -> [TempPreset] {
        let request = TempPresetsIntentRequest()
        let tempTargets = await request.fetchIDs(identifiers)
        return tempTargets
    }

    func suggestedEntities() async throws -> [TempPreset] {
        let request = TempPresetsIntentRequest()
        let tempTargets = await request.fetchAll()
        return tempTargets
    }
}
