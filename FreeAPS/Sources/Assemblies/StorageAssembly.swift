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
            let settingsManager = r.resolve(SettingsManager.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseGlucoseStorage(
                storage: storage,
                settingsManager: settingsManager,
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
        container.register(SettingsManager.self) { r in
            let storage = r.resolve(FileStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseSettingsManager(
                storage: storage,
                appCoordinator: appCoordinator
            )
        }
        container.register(Keychain.self) { _ in BaseKeychain() }
        container.register(Token.self) { r in Token(resolver: r) }
        container.register(AlertHistoryStorage.self) { r in BaseAlertHistoryStorage(resolver: r) }
    }
}
