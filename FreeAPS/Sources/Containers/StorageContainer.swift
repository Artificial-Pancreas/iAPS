import Foundation
import Swinject

private let resolver = FreeAPSApp.resolver

enum StorageContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(FileManager.self) { _ in
            Foundation.FileManager.default
        }

        container.register(FileStorage.self) { _ in BaseFileStorage() }

        container.register(Keychain.self) { _ in BaseKeychain() }
    }
}
