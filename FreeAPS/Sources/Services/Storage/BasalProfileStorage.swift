import Foundation
import LoopKit
import Swinject

protocol BasalProfileStorage: AnyObject, Sendable {
    var basalProfile: [BasalProfileEntry] { get async }
    func updateBasalProfile(_ profile: [BasalProfileEntry]) async
}

actor BaseBasalProfileStorage: BasalProfileStorage, AppService {
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
        appCoordinator.setBasalProfile(await self.basalProfile)
    }

    var basalProfile: [BasalProfileEntry] {
        get async {
            await storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? (try? [BasalProfileEntry].decodeFrom(json: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile)))
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }
    }

    func updateBasalProfile(_ schedule: [BasalProfileEntry]) async {
        await self.storage.save(schedule, as: OpenAPS.Settings.basalProfile)
        appCoordinator.setBasalProfile(schedule)
    }
}
