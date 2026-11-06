import Foundation
import Swinject

final class StorageAssembly: Assembly {
    func assemble(container: Container) {
        container.register(FileManager.self) { _ in
            Foundation.FileManager.default
        }
        container.register(FileStorage.self) { _ in BaseFileStorage() }
        container.register(PumpHistoryStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BasePumpHistoryStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(GlucoseStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseGlucoseStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(TempTargetsStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseTempTargetsStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(CarbsStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let settingsManager = r.resolve(SettingsManager.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseCarbsStorage(
                storage: storage,
                settingsManager: settingsManager,
                appCoordinator: appCoordinator
            )
        }
        container.register(AnnouncementsStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            return BaseAnnouncementsStorage(
                storage: storage
            )
        }
        container.register(LoopEventsStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseLoopEventsStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(OverrideStorage.self) { r in
            OverrideStorage(appCoordinator: r.resolve(AppCoordinator.self)!)
        }
        container.register(GlucoseStatistics.self) { r in
            GlucoseStatistics(appCoordinator: r.resolve(AppCoordinator.self)!, source: CoreDataStorage())
        }
        container.register(PumpEventStore.self) { r in
            PumpEventStore(appCoordinator: r.resolve(AppCoordinator.self)!)
        }
        container.register(InsulinStatsService.self) { r in
            InsulinStatsService(appCoordinator: r.resolve(AppCoordinator.self)!, source: CoreDataStorage())
        }
        // one for the Home Loops card and the Loops screen: one day cache, the same numbers
        container.register(HomeLoopsStore.self) { r in
            let store = HomeLoopsStore(source: HomeLoopsCoreDataSource())
            store.follow(r.resolve(AppCoordinator.self)!)
            return store
        }
        container.register(SettingsManager.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseSettingsManager(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(Keychain.self) { _ in BaseKeychain() }
        container.register(UserToken.self) { r in PersistedUserToken(resolver: r) }
        container.register(AlertHistoryStorage.self) { r in BaseAlertHistoryStorage(resolver: r) }
        container.register(BasalProfileStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseBasalProfileStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(AutotuneStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseAutotuneStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(IsfScheduleStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseIsfScheduleStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(CarbRatioScheduleStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseCarbRatioScheduleStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(BgTargetsScheduleStorage.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseBgTargetsScheduleStorage(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
    }
}
