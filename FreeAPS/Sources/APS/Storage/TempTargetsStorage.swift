import Foundation
import SwiftDate
import Swinject

protocol TempTargetsStorage: Sendable {
    func storeTempTargets(_ targets: [TempTarget]) async
    func syncDate() async -> Date
    func storePresets(_ targets: [TempTarget]) async
    func presets() async -> [TempTarget]
    func current() async -> TempTarget?

    func saveRawJSON(_ raw: RawJSON) async throws

    /// Enacts a temp target, `hbt` != nil makes it a % temp target.
    func enactTempTarget(_ target: TempTarget, hbt: Double?) async
    /// Enacts the preset (with its HBT, if it is a % preset). Returns the enacted temp target, nil if there is no such preset.
    @discardableResult func enactPreset(id: String) async -> TempTarget?
    func cancelTempTarget() async
    /// Adds a preset, `hbt` != nil makes it a % preset.
    func storePreset(_ preset: TempTarget, hbt: Double?) async
    func removePreset(id: String) async
    /// The HBT of the newest % preset, to seed the slider.
    func lastHalfBasalTarget() async -> Double?
}

actor BaseTempTargetsStorage: TempTargetsStorage, AppService {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    private let coreDataStorage = CoreDataStorage()

    /// One operation at a time: the temp target (file) and its HBT row (Core Data) are written by the same
    /// operation, which must not interleave with another one (the actor is reentrant across the awaits).
    private let serializer = TaskSerializer()

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called on app start
    func start() async {
        await resetCache()
    }

    func saveRawJSON(_ raw: RawJSON) async throws {
        try await serializer.run {
            try await storage.save(raw: raw, as: OpenAPS.Settings.tempTargets, decodingInto: [TempTarget].self)
            await resetCache()
        }
    }

    private func resetCache() async {
        // newest->oldest
        let history = await storage.retrieve(OpenAPS.Settings.tempTargets, as: [TempTarget].self) ?? []
        appCoordinator.setTempTargets(history)
    }

    func storeTempTargets(_ targets: [TempTarget]) async {
        await serializer.run {
            await storeTempTargets(targets, isPresets: false)
        }
    }

    private func storeTempTargets(_ targets: [TempTarget], isPresets: Bool) async {
        var targets = targets
        let now = Date()
        if !isPresets {
            if await current() != nil, let newActive = targets.last(where: {
                $0.createdAt.addingTimeInterval(.minutes(Int($0.duration))) > now
                    && $0.createdAt <= now
            }) {
                // cancel current
                targets += [TempTarget.cancel(at: newActive.createdAt.subtractingTimeInterval(.seconds(1)))]
            }
        }

        let file = isPresets ? OpenAPS.FreeAPS.tempTargetsPresets : OpenAPS.Settings.tempTargets
        let uniqEvents: [TempTarget] = await self.storage.appendAndModify(targets, to: file, uniqBy: \.createdAt) {
            $0
                .filter {
                    guard !isPresets else { return true }
                    return $0.createdAt > now.subtractingTimeInterval(.hours(24))
                }
                .sorted { $0.createdAt > $1.createdAt }
        }
        // presets are not temp targets: publishing them would hand them to the loop as the temp target history
        guard !isPresets else { return }
        // newest->oldest
        appCoordinator.setTempTargets(uniqEvents)
    }

    func syncDate() -> Date {
        Date().subtractingTimeInterval(.hours(24))
    }

    func current() async -> TempTarget? {
        let history = await storage.retrieve(OpenAPS.Settings.tempTargets, as: [TempTarget].self) ?? []
        guard let current = history.first, current.isActive(at: Date()) else {
            return nil
        }
        return current
    }

    func storePresets(_ targets: [TempTarget]) async {
        await serializer.run {
            // TODO: implement as one call/write - .replace?
            await storage.remove(OpenAPS.FreeAPS.tempTargetsPresets)
            await storeTempTargets(targets, isPresets: true)
            appCoordinator.tempTargetPresetsDidChange()
        }
    }

    func presets() async -> [TempTarget] {
        await storage.retrieve(OpenAPS.FreeAPS.tempTargetsPresets, as: [TempTarget].self)?.reversed() ?? []
    }

    func enactTempTarget(_ target: TempTarget, hbt: Double?) async {
        await serializer.run {
            await enact(target, hbt: hbt)
        }
    }

    @discardableResult func enactPreset(id: String) async -> TempTarget? {
        await serializer.run {
            guard var preset = await presets().first(where: { $0.id == id }) else { return nil }
            preset.createdAt = Date()
            let hbt = await coreDataStorage.fetchTempTargetHBTPreset(id: id)?.hbt
            await enact(preset, hbt: hbt)
            return preset
        }
    }

    func cancelTempTarget() async {
        await serializer.run {
            let cancel = TempTarget.cancel(at: Date())
            await coreDataStorage.saveTempTargetHBT(
                id: cancel.id,
                active: false,
                hbt: nil,
                duration: 0,
                startDate: cancel.createdAt
            )
            await storeTempTargets([cancel], isPresets: false)
        }
    }

    func storePreset(_ preset: TempTarget, hbt: Double?) async {
        await serializer.run {
            // the HBT row first: a % preset without it would enact as a plain temp target
            if let hbt {
                await coreDataStorage.saveTempTargetHBTPreset(id: preset.id, hbt: hbt, duration: preset.duration)
            }
            await storeTempTargets([preset], isPresets: true)
            appCoordinator.tempTargetPresetsDidChange()
        }
    }

    func removePreset(id: String) async {
        await serializer.run {
            await storage.delete(file: OpenAPS.FreeAPS.tempTargetsPresets, as: TempTarget.self) { $0.id == id }
            await coreDataStorage.deleteTempTargetHBTPresets(id: id)
            appCoordinator.tempTargetPresetsDidChange()
        }
    }

    func lastHalfBasalTarget() async -> Double? {
        await coreDataStorage.fetchLastHBT()
    }

    /// Not serialized: callers run it inside the serializer.
    private func enact(_ target: TempTarget, hbt: Double?) async {
        await coreDataStorage.saveTempTargetHBT(
            id: target.id,
            active: hbt != nil,
            hbt: hbt,
            duration: target.duration,
            startDate: target.createdAt
        )
        await storeTempTargets([target], isPresets: false)
    }
}
