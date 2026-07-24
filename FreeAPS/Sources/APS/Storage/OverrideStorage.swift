import Combine
import CoreData
import Foundation
import SwiftDate

final class OverrideStorage: Sendable {
    private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
    private let appCoordinator: AppCoordinator

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }

    private func fetchAutoIsfArray(ids: [String]) -> [Auto_ISF] {
        let request = Auto_ISF.fetchRequest()
        request.predicate = NSPredicate(
            format: "id IN %@", ids
        )
        return (try? coredataContext.fetch(request)) ?? []
    }

    private func fetchAutoIsf(id: String?) -> Auto_ISF? {
        guard let id else { return nil }
        let request = Auto_ISF.fetchRequest() as NSFetchRequest<Auto_ISF>
        request.predicate = NSPredicate(
            format: "id == %@", id
        )
        request.fetchLimit = 1
        return (try? coredataContext.fetch(request))?.first
    }

    /// Must be called on the Core Data context's queue.
    private func fetchAutoIsfSettings(id: String?) -> AutoISFsettings? {
        fetchAutoIsf(id: id)?.toAutoISFsettings
    }

    func fetchCurrentActiveOverride() async -> OverrideSnapshot? {
        await coredataContext.perform {
            let request = Override.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.fetchLimit = 1
            guard let override = try? self.coredataContext.fetch(request).first else { return nil }
            guard override.enabled else { return nil }
            let aisf = self.fetchAutoIsfSettings(id: override.id)
            return OverrideSnapshot.create(from: override, aisf: aisf)
        }
    }

    func fetchOverridePreset(id: String) async -> OverridePresetsSnapshot? {
        await coredataContext.perform {
            let requestOverrides = OverridePresets.fetchRequest()
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "id == %@", id as String
            )
            guard let override = (try? self.coredataContext.fetch(requestOverrides))?.first else { return nil }
            let aisf = self.fetchAutoIsfSettings(id: override.id)
            return OverridePresetsSnapshot.create(from: override, aisf: aisf)
        }
    }

    func fetchOverrideHistory(interval: NSDate) async -> [OverrideHistorySnapshot] {
        await coredataContext.perform {
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)

            // overrides that started within the window.
            let requestOverrides = OverrideHistory.fetchRequest() as NSFetchRequest<OverrideHistory>
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate(
                format: "date > %@", interval
            )
            var overrideArray = (try? self.coredataContext.fetch(requestOverrides)) ?? []

            // plus the most recent override that started before the window but may still overlap it
            let precedingRequest = OverrideHistory.fetchRequest() as NSFetchRequest<OverrideHistory>
            precedingRequest.sortDescriptors = [sortOverride]
            precedingRequest.predicate = NSPredicate(format: "date <= %@", interval)
            precedingRequest.fetchLimit = 1
            if let preceding = (try? self.coredataContext.fetch(precedingRequest))?.first,
               let start = preceding.date,
               start.addingTimeInterval(.minutes(preceding.duration)) > (interval as Date)
            {
                overrideArray.append(preceding)
            }

            return overrideArray.map { OverrideHistorySnapshot.create(from: $0) }
        }
    }

    func cancelActiveOverride() async -> Double? {
        guard let latest = await fetchCurrentActiveOverride() else { return nil }

        defer {
            appCoordinator.overridesDidChange()
        }

        return await coredataContext.perform {
            var duration: Double?

            let tomb = Override(context: self.coredataContext)
            let history = OverrideHistory(context: self.coredataContext)

            let now = Date()
            history.duration = now.timeIntervalSince(latest.date ?? now).minutes
            history.date = latest.date ?? now
            // Looks better in Home View Main Chart when target isn't == 0.
            if latest.target ?? 100 < 6 {
                history.target = 6
            } else {
                history.target = Double(latest.target ?? 100)
            }
            duration = history.duration

            tomb.enabled = false
            tomb.id = UUID().uuidString // all rows should have an ID
            tomb.date = Date()
            try? self.coredataContext.save()

            return duration
        }
    }

    func activateOverrideFromPreset(presetId id: String) async -> OverrideSnapshot? {
        let overridePreset = await coredataContext.perform { () -> OverridePresetsSnapshot? in
            let requestPresets = OverridePresets.fetchRequest()
            requestPresets.predicate = NSPredicate(
                format: "id == %@", id
            )
            guard let preset = (try? self.coredataContext.fetch(requestPresets))?.first else { return nil }
            let aisf = self.fetchAutoIsfSettings(id: preset.id)
            return OverridePresetsSnapshot.create(from: preset, aisf: aisf)
        }
        guard let overridePreset else { return nil }
        return await activateOverrideFromPreset(preset: overridePreset, fromSavedPreset: true)
    }

    func fetchOverridePreset(name: String) async -> OverridePresetsSnapshot? {
        await coredataContext.perform {
            let requestPresets = OverridePresets.fetchRequest()
            requestPresets.predicate = NSPredicate(
                format: "name == %@", name
            )
            guard let preset = (try? self.coredataContext.fetch(requestPresets))?.first else { return nil }
            let aisf = self.fetchAutoIsfSettings(id: preset.id)
            return OverridePresetsSnapshot.create(from: preset, aisf: aisf)
        }
    }

    func fetchOverridePresets() async -> [OverridePresetsSnapshot] {
        await coredataContext.perform {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(
                    format: "name != %@", ""
                ),
                NSPredicate(
                    format: "name != %@", "Empty"
                )
            ])
            requestPresets.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            let presetsArray = (try? self.coredataContext.fetch(requestPresets)) ?? []
            let aisfArray = self.fetchAutoIsfArray(ids: presetsArray.compactMap(\.id))
            return presetsArray.compactMap { preset in
                let aisf = preset.id.flatMap { overrideId in aisfArray.first(where: { $0.id == overrideId }) }

                return OverridePresetsSnapshot.create(from: preset, aisf: aisf?.toAutoISFsettings)
            }
        }
    }

    // TODO: make this a presetName field inside OverrideSnapshot instead
    func getPresetName(for override: OverrideSnapshot) async -> String? {
        await coredataContext.perform {
            let requestPresets = OverridePresets.fetchRequest() as NSFetchRequest<OverridePresets>
            requestPresets.predicate = NSPredicate(
                format: "id == %@", override.id
            )
            requestPresets.fetchLimit = 1
            guard let presetsArray = try? self.coredataContext.fetch(requestPresets) else { return nil }

            return presetsArray.first?.name
        }
    }

    func storeOverridePreset(_ draft: OverridePresetsSnapshot) async {
        await coredataContext.perform {
            let preset = OverridePresets(context: self.coredataContext)
            self.applyChangesToOverridePreset(preset: preset, draft: draft)
            try? self.coredataContext.save()
        }
        appCoordinator.overridesDidChange()
    }

    func updateOverridePreset(_ draft: OverridePresetsSnapshot) async {
        await coredataContext.perform {
            let request = OverridePresets.fetchRequest()
            request.predicate = NSPredicate(format: "id = %@", draft.id)
            request.fetchLimit = 1

            guard let preset = (try? self.coredataContext.fetch(request))?.first else { return }

            self.applyChangesToOverridePreset(preset: preset, draft: draft)

            try? self.coredataContext.save()
        }
        appCoordinator.overridesDidChange()
    }

    private func applyChangesToOverridePreset(preset: OverridePresets, draft: OverridePresetsSnapshot) {
        preset.id = draft.id
        preset.date = Date.now
        preset.end = draft.end.map { $0 as NSDecimalNumber }
        preset.name = draft.name
        preset.emoji = draft.emoji
        preset.advancedSettings = draft.advancedSettings
        preset.basal = draft.basal
        preset.cr = draft.cr
        preset.duration = draft.duration.map { $0 as NSDecimalNumber }
        preset.endWIthNewCarbs = draft.endWIthNewCarbs
        preset.glucoseOverrideThreshold = draft.glucoseOverrideThreshold.map { $0 as NSDecimalNumber }
        preset.glucoseOverrideThresholdActive = draft.glucoseOverrideThresholdActive
        preset.glucoseOverrideThresholdActiveDown = draft.glucoseOverrideThresholdActiveDown
        preset.glucoseOverrideThresholdDown = draft.glucoseOverrideThresholdDown.map { $0 as NSDecimalNumber }
        preset.indefinite = draft.indefinite
        preset.isf = draft.isf
        preset.isfAndCr = draft.isfAndCr
        preset.maxIOB = draft.maxIOB.map { $0 as NSDecimalNumber }
        preset.overrideAutoISF = draft.overrideAutoISF
        preset.overrideMaxIOB = draft.overrideMaxIOB
        preset.percentage = draft.percentage
        preset.smbIsAlwaysOff = draft.smbIsAlwaysOff
        preset.smbIsOff = draft.smbIsOff
        preset.smbMinutes = draft.smbMinutes.map { $0 as NSDecimalNumber }
        preset.start = draft.start.map { $0 as NSDecimalNumber }
        preset.target = draft.target.map { $0 as NSDecimalNumber }
        preset.uamMinutes = draft.uamMinutes.map { $0 as NSDecimalNumber }

        if let aisf = draft.aisf {
            _ = createOrUpdateAutoISF(id: draft.id, autoISFsettings: aisf)
        }
    }

    private func createOrUpdateAutoISF(id identifier: String, autoISFsettings: AutoISFsettings) -> Auto_ISF {
        let oldObject = fetchAutoIsf(id: identifier)
        let saveAutoISF: Auto_ISF
        if let oldObject {
            saveAutoISF = oldObject
        } else {
            saveAutoISF = Auto_ISF(context: coredataContext)
            saveAutoISF.id = identifier
        }

        saveAutoISF.autoISFhourlyChange = autoISFsettings.autoISFhourlyChange as NSDecimalNumber
        saveAutoISF.autoisf = autoISFsettings.autoisf
        saveAutoISF.autocr = autoISFsettings.autocr
        saveAutoISF.autoisf_min = autoISFsettings.autoisf_min as NSDecimalNumber
        saveAutoISF.autoisf_max = autoISFsettings.autoisf_max as NSDecimalNumber
        saveAutoISF.enableBGacceleration = autoISFsettings.enableBGacceleration
        saveAutoISF.bgAccelISFweight = autoISFsettings.bgAccelISFweight as NSDecimalNumber
        saveAutoISF.bgBrakeISFweight = autoISFsettings.bgBrakeISFweight as NSDecimalNumber
        saveAutoISF.lowerISFrangeWeight = autoISFsettings.lowerISFrangeWeight as NSDecimalNumber
        saveAutoISF.higherISFrangeWeight = autoISFsettings.higherISFrangeWeight as NSDecimalNumber
        saveAutoISF.iTime_Start_Bolus = autoISFsettings.iTime_Start_Bolus as NSDecimalNumber
        saveAutoISF.iTime_target = autoISFsettings.iTime_target as NSDecimalNumber
        saveAutoISF.use_B30 = autoISFsettings.use_B30
        saveAutoISF.b30_duration = autoISFsettings.b30_duration as NSDecimalNumber
        saveAutoISF.b30factor = autoISFsettings.b30factor as NSDecimalNumber
        saveAutoISF.b30targetLevel = autoISFsettings.b30targetLevel as NSDecimalNumber
        saveAutoISF.b30upperLimit = autoISFsettings.b30upperLimit as NSDecimalNumber
        saveAutoISF.b30upperdelta = autoISFsettings.b30upperdelta as NSDecimalNumber
        saveAutoISF.iobThresholdPercent = autoISFsettings.iobThresholdPercent as NSDecimalNumber
        saveAutoISF.ketoProtect = autoISFsettings.ketoProtect
        saveAutoISF.ketoProtectAbsolut = autoISFsettings.ketoProtectAbsolut
        saveAutoISF.ketoProtectBasalAbsolut = autoISFsettings.ketoProtectBasalAbsolut as NSDecimalNumber
        saveAutoISF.variableKetoProtect = autoISFsettings.variableKetoProtect
        saveAutoISF.ketoProtectBasalPercent = autoISFsettings.ketoProtectBasalPercent as NSDecimalNumber
        saveAutoISF.smbDeliveryRatioMin = autoISFsettings.smbDeliveryRatioMin as NSDecimalNumber
        saveAutoISF.smbDeliveryRatioMax = autoISFsettings.smbDeliveryRatioMax as NSDecimalNumber
        saveAutoISF.smbDeliveryRatioBGrange = autoISFsettings.smbDeliveryRatioBGrange as NSDecimalNumber
        saveAutoISF.postMealISFweight = autoISFsettings.postMealISFweight as NSDecimalNumber
        saveAutoISF.date = Date.now

        return saveAutoISF
    }

    func deleteOverridePresets(ids: [String]) async {
        defer {
            appCoordinator.overridesDidChange()
        }
        await coredataContext.perform {
            let request = OverridePresets.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)

            if let objects = try? self.coredataContext.fetch(request) {
                for object in objects {
                    self.coredataContext.delete(object)
                }
            }

//            TODO: we cannot delete the Auto_ISF rows because the current active override can be referencing it.
//            figure out and fix later
//            let aisfRequest = Auto_ISF.fetchRequest()
//            aisfRequest.predicate = NSPredicate(format: "id IN %@", ids)
//            if let objects = try? self.coredataContext.fetch(aisfRequest) {
//                for object in objects {
//                    self.coredataContext.delete(object)
//                }
//            }

            try? self.coredataContext.save()
        }
    }

    /// Activates an override.
    ///
    /// `fromSavedPreset` distinguishes the two entry points:
    /// - `true`: the override was created from a saved preset. Its `Auto_ISF` row already
    ///   exists under `preset.id` (the new Override reuses that id), so it is only fetched.
    /// - `false`: a custom override built in the editor, carrying a fresh `id`. Its AISF
    ///   settings live only in `preset.aisf`, so they are persisted here.
    func activateOverrideFromPreset(
        preset: OverridePresetsSnapshot,
        fromSavedPreset: Bool,
        defaultMaxIOB: Decimal? = nil
    ) async -> OverrideSnapshot? {
        defer {
            appCoordinator.overridesDidChange()
        }
        return await coredataContext.perform {
            let saveOverride = Override(context: self.coredataContext)
            saveOverride.duration = (preset.duration ?? 0) as NSDecimalNumber
            saveOverride.indefinite = preset.indefinite
            saveOverride.percentage = preset.percentage
            saveOverride.enabled = true
            saveOverride.smbIsOff = preset.smbIsOff
            saveOverride.isPreset = fromSavedPreset
            saveOverride.date = Date()
            saveOverride.id = preset.id
            saveOverride.isfAndCr = preset.isfAndCr
            saveOverride.overrideAutoISF = preset.overrideAutoISF

            if let tar = preset.target, tar == 0 {
                saveOverride.target = 6
            } else {
                saveOverride.target = preset.target as? NSDecimalNumber
            }

            saveOverride.advancedSettings = preset.advancedSettings
            if preset.advancedSettings {
                if !preset.isfAndCr {
                    saveOverride.isf = preset.isf
                    saveOverride.cr = preset.cr
                    saveOverride.basal = preset.basal
                }
                saveOverride.smbIsAlwaysOff = preset.smbIsAlwaysOff
                if preset.smbIsAlwaysOff {
                    saveOverride.start = preset.start as? NSDecimalNumber
                    saveOverride.end = preset.end as? NSDecimalNumber
                }

                saveOverride.smbMinutes = (preset.smbMinutes ?? 0) as NSDecimalNumber
                saveOverride.uamMinutes = (preset.uamMinutes ?? 0) as NSDecimalNumber
                saveOverride.maxIOB = (preset.maxIOB ?? defaultMaxIOB) as NSDecimalNumber?
                saveOverride.overrideMaxIOB = preset.overrideMaxIOB

                saveOverride.endWIthNewCarbs = preset.endWIthNewCarbs

                saveOverride.glucoseOverrideThresholdActive = preset.glucoseOverrideThresholdActive
                if preset.glucoseOverrideThresholdActive {
                    saveOverride.glucoseOverrideThreshold = (preset.glucoseOverrideThreshold ?? 100) as NSDecimalNumber
                }

                saveOverride.glucoseOverrideThresholdActiveDown = preset.glucoseOverrideThresholdActiveDown
                if preset.glucoseOverrideThresholdActiveDown {
                    saveOverride.glucoseOverrideThresholdDown = (preset.glucoseOverrideThresholdDown ?? 90) as NSDecimalNumber
                }
            }

            // A custom override (not from a saved preset) carries its AISF settings only in
            // the draft, under a fresh id persist them (if overrideAutoISF == true).
            if !fromSavedPreset, preset.overrideAutoISF, let aisf = preset.aisf {
                _ = self.createOrUpdateAutoISF(id: preset.id, autoISFsettings: aisf)
            }

            try? self.coredataContext.save()

            return OverrideSnapshot.create(from: saveOverride, aisf: preset.aisf)
        }
    }
}

private extension Auto_ISF {
    var toAutoISFsettings: AutoISFsettings {
        AutoISFsettings(
            autoisf: autoisf,
            autocr: autocr,
            smbDeliveryRatioBGrange: smbDeliveryRatioBGrange?.decimalValue ?? 0,
            smbDeliveryRatioMin: smbDeliveryRatioMin?.decimalValue ?? 0,
            smbDeliveryRatioMax: smbDeliveryRatioMax?.decimalValue ?? 0,
            autoISFhourlyChange: autoISFhourlyChange?.decimalValue ?? 0,
            higherISFrangeWeight: higherISFrangeWeight?.decimalValue ?? 0,
            lowerISFrangeWeight: lowerISFrangeWeight?.decimalValue ?? 0,
            postMealISFweight: postMealISFweight?.decimalValue ?? 0,
            enableBGacceleration: enableBGacceleration,
            bgAccelISFweight: bgAccelISFweight?.decimalValue ?? 0,
            bgBrakeISFweight: bgBrakeISFweight?.decimalValue ?? 0,
            iobThresholdPercent: iobThresholdPercent?.decimalValue ?? 0,
            autoisf_max: autoisf_max?.decimalValue ?? 0,
            autoisf_min: autoisf_min?.decimalValue ?? 0,
            use_B30: use_B30,
            iTime_Start_Bolus: iTime_Start_Bolus?.decimalValue ?? 1.5,
            b30targetLevel: b30targetLevel?.decimalValue ?? 80,
            b30upperLimit: b30upperLimit?.decimalValue ?? 140,
            b30upperdelta: b30upperdelta?.decimalValue ?? 8,
            b30factor: b30factor?.decimalValue ?? 5,
            b30_duration: b30_duration?.decimalValue ?? 30,
            ketoProtect: ketoProtect,
            variableKetoProtect: variableKetoProtect,
            ketoProtectBasalPercent: ketoProtectBasalPercent?.decimalValue ?? 0,
            ketoProtectAbsolut: ketoProtectAbsolut,
            ketoProtectBasalAbsolut: ketoProtectBasalAbsolut?.decimalValue ?? 0.2,
            id: id ?? "",
            nightTime: nightTime.map {
                NightTimeConfiguration(
                    startHour: $0.startHour,
                    startMinute: $0.startMinute,
                    endHour: $0.endHour,
                    endMinute: $0.endMinute,
                    enabled: $0.enabled
                )
            } ?? .default
        )
    }
}
