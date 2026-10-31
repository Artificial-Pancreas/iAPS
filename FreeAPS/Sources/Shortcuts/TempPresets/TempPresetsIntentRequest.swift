import CoreData
import Foundation

final class TempPresetsIntentRequest: BaseIntentsRequest {
    enum TempPresetsError: Error {
        case noTempTargetFound
        case noDurationDefined
    }

    /// The "Cancel" entry is not a stored preset, so it needs a fixed identifier: Shortcuts persists the
    /// chosen entity's ID and resolves it again on every run. A fresh UUID per call (the previous
    /// behaviour) never resolved, which made the "Apply or cancel" action prompt for a preset each time.
    static let cancelPresetID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var cancelPreset: tempPreset {
        tempPreset(id: Self.cancelPresetID, name: TempTarget.cancel, targetTop: 0, targetBottom: 0, duration: 0)
    }

    private func convert(tt: [TempTarget]) -> [tempPreset] {
        tt.compactMap { tempPreset.convert($0) }
    }

    func fetchAll() -> [tempPreset] {
        convert(tt: tempTargetsStorage.presets()) + [cancelPreset]
    }

    /// In the requested order, as the entity query contract expects; `fetchOne` knows the Cancel entry.
    func fetchIDs(_ uuid: [tempPreset.ID]) -> [tempPreset] {
        uuid.compactMap { fetchOne($0) }
    }

    func fetchOne(_ uuid: tempPreset.ID) -> tempPreset? {
        if uuid == Self.cancelPresetID { return cancelPreset }
        let UUIDTempTarget = tempTargetsStorage.presets().filter { UUID(uuidString: $0.id) == uuid }
        guard let OneTempTarget = UUIDTempTarget.first else { return nil }
        return tempPreset.convert(OneTempTarget)
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
