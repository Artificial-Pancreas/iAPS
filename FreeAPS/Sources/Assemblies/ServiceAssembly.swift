import Foundation
import HealthKit
import LoopKitUI
import Swinject

final class ServiceAssembly: Assembly {
    func assemble(container: Container) {
        container.register(AppCoordinator.self) { _ in AppCoordinator() }
        container.register(NotificationCenter.self) { _ in Foundation.NotificationCenter.default }

        container.register(GroupedIssueReporter.self) { _ in
            let reporter = CollectionIssueReporter()
            reporter.add(reporters: [
                SimpleLogReporter()
            ])
            reporter.setup()
            return reporter
        }
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
        container.register(GarminManager.self) { r in BaseGarminManager(resolver: r) }
        container.register(ContactTrickManager.self) { r in
            let appCoordinator = r.resolve(AppCoordinator.self)!
            let storage = r.resolve(FileStorage.self)!

            return BaseContactTrickManager(
                appCoordinator: appCoordinator,
                storage: storage
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
        container.register(CoreDataStorageGlucoseSaver.self) { r in CoreDataStorageGlucoseSaver(resolver: r) }
    }
}
