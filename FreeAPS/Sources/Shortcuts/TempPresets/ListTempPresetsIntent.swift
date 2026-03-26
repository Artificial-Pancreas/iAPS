import AppIntents
import Foundation

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
