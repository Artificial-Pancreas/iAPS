import Foundation
import LoopKit
import Swinject

protocol BgTargetsScheduleStorage: AnyObject, Sendable {
    var bgTargetsSchedule: BGTargets { get async }
    func updateBgTargetsSchedule(_ schedule: BGTargets) async

    func saveRawJSON(_ raw: RawJSON) async throws
}

actor BaseBgTargetsScheduleStorage: BgTargetsScheduleStorage, AppService {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called on app start, before anything is rendered
    func start() async {
        await resetCache()
    }

    private func resetCache() async {
        appCoordinator.setBgTargetsSchedule(await self.bgTargetsSchedule)
    }

    var bgTargetsSchedule: BGTargets {
        get async {
            await storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets.initial
        }
    }

    func updateBgTargetsSchedule(_ schedule: BGTargets) async {
        await self.storage.save(schedule, as: OpenAPS.Settings.bgTargets)
        appCoordinator.setBgTargetsSchedule(schedule)
    }

    func saveRawJSON(_ raw: RawJSON) async throws {
        try await storage.save(raw: raw, as: OpenAPS.Settings.bgTargets, decodingInto: BGTargets.self)
        await resetCache()
    }
}
