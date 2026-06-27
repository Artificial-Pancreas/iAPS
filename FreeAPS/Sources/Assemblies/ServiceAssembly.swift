import Foundation
import HealthKit
import LoopKitUI
import Swinject

final class ServiceAssembly: Assembly {
    func assemble(container: Container) {
        container.register(DataMigrations.self) { _ in DataMigrations() }

        container.register(AppCoordinator.self) { _ in AppCoordinator() }

        // Foundation.NotificationCenter.default is provided to GarminManager below without resolving it;
        // if this ever needs to change - make sure to keep the GarminManager in-sync
        container.register(NotificationCenter.self) { _ in Foundation.NotificationCenter.default }

        container.register(CalendarManager.self) { r in
            let glucoseStorage = r.resolve(GlucoseStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseCalendarManager(
                glucoseStorage: glucoseStorage,
                appCoordinator: appCoordinator
            )
        }
        container.register(HKHealthStore.self) { _ in HKHealthStore() }
        container.register(HealthKitManager.self) { r in
            let healthKitStore = r.resolve(HKHealthStore.self)!
            let settingsManager = r.resolve(SettingsManager.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseHealthKitManager(
                healthKitStore: healthKitStore,
                settingsManager: settingsManager,
                appCoordinator: appCoordinator
            )
        }
        container.register(UserNotificationsManager.self) { r in
            let settingsManager = r.resolve(SettingsManager.self)!
            let glucoseStorage = r.resolve(GlucoseStorage.self)!
            let apsManager = r.resolve(APSManager.self)!
            let deviceDataManager = r.resolve(DeviceDataManager.self)!
            let router = r.resolve(Router.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseUserNotificationsManager(
                settingsManager: settingsManager,
                glucoseStorage: glucoseStorage,
                apsManager: apsManager,
                deviceDataManager: deviceDataManager,
                router: router,
                appCoordinator: appCoordinator
            )
        }
        container.register(WatchManager.self) { r in
            let settingsManager = r.resolve(SettingsManager.self)!
            let apsManager = r.resolve(APSManager.self)!
            let storage = r.resolve(FileStorage.self)!
            let carbsStorage = r.resolve(CarbsStorage.self)!
            let tempTargetsStorage = r.resolve(TempTargetsStorage.self)!
            let garmin = r.resolve(GarminManager.self)!
            let nightscout = r.resolve(NightscoutManager.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseWatchManager(
                settingsManager: settingsManager,
                apsManager: apsManager,
                storage: storage,
                carbsStorage: carbsStorage,
                tempTargetsStorage: tempTargetsStorage,
                garmin: garmin,
                nightscout: nightscout,
                appCoordinator: appCoordinator
            )
        }
        container.register(GarminManager.self) { r in
            let appCoordinator = r.resolve(AppCoordinator.self)!
            // BaseGarminManager is @MainActor.
            // All resolution happens on the main actor (AppServices.performStartup and StateModels),
            // so asserting main isolation here is safe.
            return MainActor.assumeIsolated {
                BaseGarminManager(
                    notificationCenter: Foundation.NotificationCenter.default,
                    appCoordinator: appCoordinator
                )
            }
        }
        container.register(ContactTrickManager.self) { r in
            BaseContactTrickManager(
                appCoordinator: r.resolve(AppCoordinator.self)!,
                storage: r.resolve(FileStorage.self)!
            )
        }
        container.register(LiveActivityBridge.self) { r in
            let settingsManager = r.resolve(SettingsManager.self)!
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return LiveActivityBridge(
                settingsManager: settingsManager,
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(CoreDataManager.self) { r in CoreDataManager(resolver: r) }

        container.register(AppServices.self) { r in
            nonisolated(unsafe) let resolver = r
            return MainActor.assumeIsolated { AppServices(resolver: resolver) }
        }
    }
}
