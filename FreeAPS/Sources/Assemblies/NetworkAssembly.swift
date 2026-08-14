import Foundation
import Swinject

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }

        container.register(NightscoutAPIProvider.self) { r in
            NightscoutAPIProvider(
                keychain: r.resolve(Keychain.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!
            )
        }
        container.register(NightscoutUploads.self) { r in
            NightscoutUploads(
                apiProvider: r.resolve(NightscoutAPIProvider.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!,
                reachabilityManager: r.resolve(ReachabilityManager.self)!,
                storage: r.resolve(FileStorage.self)!
            )
        }
        container.register(NightscoutManager.self) { r in
            BaseNightscoutManager(
                apiProvider: r.resolve(NightscoutAPIProvider.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!,
                tempTargetsStorage: r.resolve(TempTargetsStorage.self)!,
                carbsStorage: r.resolve(CarbsStorage.self)!,
                storage: r.resolve(FileStorage.self)!,
                announcementsStorage: r.resolve(AnnouncementsStorage.self)!,
                reachabilityManager: r.resolve(ReachabilityManager.self)!,
                overridesUploader: r.resolve(NightscoutUploads.self)!.overridesUploader,
                overrideStorage: r.resolve(OverrideStorage.self)!
            )
        }
        container.register(Database.self) { r in
            Database(
                userToken: r.resolve(UserToken.self)!
            )
        }
        container.register(DatabaseManager.self) { r in
            BaseDatabaseManager(
                storage: r.resolve(FileStorage.self)!,
                database: r.resolve(Database.self)!,
                reachabilityManager: r.resolve(ReachabilityManager.self)!,
                contactTrickManager: r.resolve(ContactTrickManager.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!,
                overrideStorage: r.resolve(OverrideStorage.self)!
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
                reachabilityManager: r.resolve(ReachabilityManager.self)!,
                statisticsFactory: r.resolve(DatabaseStatisticsFactory.self)!
            )
        }
    }
}
