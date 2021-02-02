import Foundation
import Swinject

enum StorageContainer {
    static func register(container: Container) {
        container.register(FileManager.self) { _ in
            Foundation.FileManager.default
        }

        container.register(Keychain.self) { _ in BaseKeychain() }

        container.register(IsDrinkImageFileStorage.self) { r in BaseImageFileStorage(resolver: r, name: "IsDrink")
        }
        container
            .register(DrinkTypeImageFileStorage.self) { r in BaseImageFileStorage(resolver: r, name: "DrinkType")
            }
    }
}

protocol IsDrinkImageFileStorage: ImageFileStorage {}
protocol DrinkTypeImageFileStorage: ImageFileStorage {}
extension BaseImageFileStorage: IsDrinkImageFileStorage {}
extension BaseImageFileStorage: DrinkTypeImageFileStorage {}
