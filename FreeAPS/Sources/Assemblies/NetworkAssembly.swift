import Foundation
import Swinject

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }

        container.register(NightscoutManager.self) { r in
            BaseNightscoutManager(
                keychain: r.resolve(Keychain.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!,
                glucoseStorage: r.resolve(GlucoseStorage.self)!,
                tempTargetsStorage: r.resolve(TempTargetsStorage.self)!,
                carbsStorage: r.resolve(CarbsStorage.self)!,
                storage: r.resolve(FileStorage.self)!,
                announcementsStorage: r.resolve(AnnouncementsStorage.self)!,
                settingsManager: r.resolve(SettingsManager.self)!,
                reachabilityManager: r.resolve(ReachabilityManager.self)!
            )
        }
        container.register(Database.self) { r in Database(resolver: r) }
        container.register(DatabaseManager.self) { r in
            BaseDatabaseManager(
                storage: r.resolve(FileStorage.self)!,
                database: r.resolve(Database.self)!,
                reachabilityManager: r.resolve(ReachabilityManager.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!
            )
        }
        container.register(DatabaseStatisticsFactory.self) { r in
            DatabaseStatisticsFactory(
                storage: r.resolve(FileStorage.self)!,
                settingsManager: r.resolve(SettingsManager.self)!,
                deviceDataManager: r.resolve(DeviceDataManager.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!
            )
        }
        container.register(ProfileAndSettingsUploadManager.self) { r in
            BaseProfileAndSettingsUploadManager(
                storage: r.resolve(FileStorage.self)!,
                settingsManager: r.resolve(SettingsManager.self)!,
                nightscoutManager: r.resolve(NightscoutManager.self)!,
                databaseManager: r.resolve(DatabaseManager.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!,
                statisticsFactory: r.resolve(DatabaseStatisticsFactory.self)!
            )
        }
    }
}
