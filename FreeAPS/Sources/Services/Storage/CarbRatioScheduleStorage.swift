import Foundation
import LoopKit
import Swinject

protocol CarbRatioScheduleStorage: AnyObject, Sendable {
    var crSchedule: CarbRatios { get async }
    func updateCrSchedule(_ schedule: CarbRatios) async

    func resetCache() async
}

actor BaseCarbRatioScheduleStorage: CarbRatioScheduleStorage, AppService {
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
        appCoordinator.setCrSchedule(await self.crSchedule)
    }

    var crSchedule: CarbRatios {
        get async {
            await storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                ?? CarbRatios.initial
        }
    }

    func updateCrSchedule(_ schedule: CarbRatios) async {
        await self.storage.save(schedule, as: OpenAPS.Settings.carbRatios)
        appCoordinator.setCrSchedule(schedule)
    }
}
