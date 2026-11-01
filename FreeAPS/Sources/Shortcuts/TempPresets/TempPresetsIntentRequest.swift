import Foundation

final class TempPresetsIntentRequest: BaseIntentsRequest {
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    /// The stored presets plus the Cancel entry, which has a fixed id (see `TempTarget.cancelPreset`).
    private func presetsWithCancel() async -> [TempTarget] {
        await tempTargetsStorage.presets() + [TempTarget.cancelPreset]
    }

    private func convert(tt: [TempTarget]) -> [TempPreset] {
        tt.compactMap { TempPreset.convert($0) }
    }

    func fetchAll() async -> [TempPreset] {
        convert(tt: await presetsWithCancel())
    }

    /// In the requested order, as the entity query contract expects.
    func fetchIDs(_ uuid: [TempPreset.ID]) async -> [TempPreset] {
        let presets = convert(tt: await presetsWithCancel())
        return uuid.compactMap { id in presets.first(where: { $0.id == id }) }
    }

    func fetchOne(_ uuid: TempPreset.ID) async -> TempPreset? {
        // Compare as UUIDs: the app stores upper-case ids, presets from elsewhere may not.
        guard let found = await presetsWithCancel().first(where: { UUID(uuidString: $0.id) == uuid }) else { return nil }
        return TempPreset.convert(found)
    }

    func findTempTarget(_ tempPreset: TempPreset) async throws -> TempTarget {
        // Compare as UUIDs: the app stores upper-case ids, presets from elsewhere may not.
        let tempTargetFound = await tempTargetsStorage.presets().filter { UUID(uuidString: $0.id) == tempPreset.id }
        guard let tempOneTarget = tempTargetFound.first else { throw TempPresetsError.noTempTargetFound }
        return tempOneTarget
    }

    func enactTempTarget(_ presetTarget: TempTarget) async throws -> TempTarget {
        guard let tempTarget = await tempTargetsStorage.enactPreset(id: presetTarget.id) else {
            throw TempPresetsError.noTempTargetFound
        }
        return tempTarget
    }

    func cancelTempTarget() async throws {
        await tempTargetsStorage.cancelTempTarget()
    }
}
