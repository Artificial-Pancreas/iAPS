import Foundation
import Swinject

private let resolver = FreeAPSApp.resolver

enum StorageContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(FileManager.self) { _ in
            Foundation.FileManager.default
        }
        container.register(FileStorage.self) { _ in BaseFileStorage() }
        container.register(PumpHistoryStorage.self) { _ in BasePumpHistoryStorage(resolver: resolver) }
        container.register(GlucoseStorage.self) { _ in BaseGlucoseStorage(resolver: resolver) }
        container.register(TempTargetsStorage.self) { _ in BaseTempTargetsStorage(resolver: resolver) }
        container.register(SettingsManager.self) { _ in BaseFSettingsManager(resolver: resolver) }

        container.register(Keychain.self) { _ in BaseKeychain() }
    }
}
