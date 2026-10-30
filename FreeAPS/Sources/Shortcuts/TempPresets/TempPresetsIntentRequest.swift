import Foundation

final class TempPresetsIntentRequest: BaseIntentsRequest {
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    private func convert(tt: [TempTarget]) -> [TempPreset] {
        let presets = tt + [TempTarget.cancel(at: Date())]
        return presets.map { TempPreset.convert($0) }
    }

    func fetchAll() async -> [TempPreset] {
        convert(tt: await tempTargetsStorage.presets())
    }

    func fetchIDs(_ uuid: [TempPreset.ID]) async -> [TempPreset] {
        let UUIDTempTarget = await tempTargetsStorage.presets().filter { uuid.contains(UUID(uuidString: $0.id)!) }
        return convert(tt: UUIDTempTarget)
    }

    func fetchOne(_ uuid: TempPreset.ID) async -> TempPreset? {
        let UUIDTempTarget = await tempTargetsStorage.presets().filter { UUID(uuidString: $0.id) == uuid }
        guard let OneTempTarget = UUIDTempTarget.first else { return nil }
        return TempPreset.convert(OneTempTarget)
    }

    func findTempTarget(_ tempPreset: TempPreset) async throws -> TempTarget {
        let tempTargetFound = await tempTargetsStorage.presets().filter { $0.id == tempPreset.id.uuidString }
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
