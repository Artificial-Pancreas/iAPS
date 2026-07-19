import Foundation
import LoopKit
import Swinject

protocol IsfScheduleStorage: AnyObject, Sendable {
    var isfSchedule: InsulinSensitivities { get async }
    func updateIsfSchedule(_ schedule: InsulinSensitivities) async

    func resetCache() async
}

actor BaseIsfScheduleStorage: IsfScheduleStorage, AppService {
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

    func resetCache() async {
        appCoordinator.setIsfSchedule(await self.isfSchedule)
    }

    var isfSchedule: InsulinSensitivities {
        get async {
            await storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities.initial
        }
    }

    func updateIsfSchedule(_ schedule: InsulinSensitivities) async {
        await self.storage.save(schedule, as: OpenAPS.Settings.insulinSensitivities)
        appCoordinator.setIsfSchedule(schedule)
    }
}
