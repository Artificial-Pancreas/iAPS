import CoreData
import Foundation

final class TempPresetsIntentRequest: BaseIntentsRequest {
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    /// The stored presets plus the Cancel entry, which has a fixed id (see `TempTarget.cancelPreset`).
    private var presetsWithCancel: [TempTarget] {
        tempTargetsStorage.presets() + [TempTarget.cancelPreset]
    }

    private func convert(tt: [TempTarget]) -> [tempPreset] {
        tt.compactMap { tempPreset.convert($0) }
    }

    func fetchAll() -> [tempPreset] {
        convert(tt: presetsWithCancel)
    }

    /// In the requested order, as the entity query contract expects.
    func fetchIDs(_ uuid: [tempPreset.ID]) -> [tempPreset] {
        uuid.compactMap { fetchOne($0) }
    }

    func fetchOne(_ uuid: tempPreset.ID) -> tempPreset? {
        // Compare as UUIDs: the app stores upper-case ids, presets from elsewhere may not.
        guard let found = presetsWithCancel.first(where: { UUID(uuidString: $0.id) == uuid }) else { return nil }
        return tempPreset.convert(found)
    }

    func findTempTarget(_ tempPreset: tempPreset) throws -> TempTarget {
        // Compare as UUIDs: the app stores upper-case ids, presets from elsewhere may not.
        let tempTargetFound = tempTargetsStorage.presets().filter { UUID(uuidString: $0.id) == tempPreset.id }
        guard let tempOneTarget = tempTargetFound.first else { throw TempPresetsError.noTempTargetFound }
        return tempOneTarget
    }

    func enactTempTarget(_ presetTarget: TempTarget) throws -> TempTarget {
        var tempTarget = presetTarget
        tempTarget.createdAt = Date()
        storage.storeTempTargets([tempTarget])

        coredataContext.performAndWait {
            var tempTargetsArray = [TempTargetsSlider]()
            let requestTempTargets = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            try? tempTargetsArray = coredataContext.fetch(requestTempTargets)

            let whichID = tempTargetsArray.first(where: { $0.id == tempTarget.id })

            if whichID != nil {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = true
                saveToCoreData.date = Date()
                saveToCoreData.hbt = whichID?.hbt ?? 160
                saveToCoreData.startDate = Date()
                saveToCoreData.duration = whichID?.duration ?? 0

                try? self.coredataContext.save()
            } else {
                let saveToCoreData = TempTargets(context: self.coredataContext)
                saveToCoreData.active = false
                saveToCoreData.date = Date()
                try? self.coredataContext.save()
            }
        }

        return tempTarget
    }

    func cancelTempTarget() throws {
        storage.storeTempTargets([TempTarget.cancel(at: Date())])
        try coredataContext.perform {
            let saveToCoreData = TempTargets(context: self.coredataContext)
            saveToCoreData.active = false

            let setHBT = TempTargetsSlider(context: self.coredataContext)
            setHBT.enabled = false

            if self.coredataContext.hasChanges {
                saveToCoreData.date = Date()
                setHBT.date = Date()
                try self.coredataContext.save()
            }
        }
    }
}
