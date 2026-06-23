import CoreData
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
        var tempTarget = presetTarget
        tempTarget.createdAt = Date()
        await tempTargetsStorage.storeTempTargets([tempTarget])

        let tempTargetID = tempTarget.id

        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            var tempTargetsArray = [TempTargetsSlider]()
            let requestTempTargets = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            try? tempTargetsArray = context.fetch(requestTempTargets)

            let whichID = tempTargetsArray.first(where: { $0.id == tempTargetID })

            if whichID != nil {
                let saveToCoreData = TempTargets(context: context)
                saveToCoreData.active = true
                saveToCoreData.date = Date()
                saveToCoreData.hbt = whichID?.hbt ?? 160
                saveToCoreData.startDate = Date()
                saveToCoreData.duration = whichID?.duration ?? 0

                try? context.save()
            } else {
                let saveToCoreData = TempTargets(context: context)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                try? context.save()
            }
        }

        return tempTarget
    }

    func cancelTempTarget() async throws {
        await tempTargetsStorage.storeTempTargets([TempTarget.cancel(at: Date())])

        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveToCoreData = TempTargets(context: context)
            saveToCoreData.active = false

            let setHBT = TempTargetsSlider(context: context)
            setHBT.enabled = false

            if context.hasChanges {
                saveToCoreData.date = Date()
                setHBT.date = Date()
                try? context.save()
            }
        }
    }
}
