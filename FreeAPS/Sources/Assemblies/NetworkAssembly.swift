import Foundation
import Swinject

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }

        container.register(NightscoutManager.self) { r in BaseNightscoutManager(resolver: r) }
        container.register(Database.self) { r in Database(resolver: r) }
        container.register(DatabaseManager.self) { r in BaseDatabaseManager(resolver: r) }
        container.register(DatabaseStatisticsFactory.self) { r in DatabaseStatisticsFactory(resolver: r) }
        container.register(ProfileAndSettingsUploadManager.self) { r in BaseProfileAndSettingsUploadManager(resolver: r) }
    }
}
