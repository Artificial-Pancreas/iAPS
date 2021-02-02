import Foundation
import Swinject

enum StorageContainer {
    static func register(container: Container) {
        container.register(FileManager.self) { _ in
            Foundation.FileManager.default
        }

        container.register(Keychain.self) { _ in BaseKeychain() }
    }
}
