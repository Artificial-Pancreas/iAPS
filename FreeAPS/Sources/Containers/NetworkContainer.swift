import Swinject
import UIKit

enum NetworkContainer {
    static func register(container: Container) {
        container.register(NetworkManager.self) { _ in BaseNetworkManager() }
        container.register(AuthorizationManager.self) { r in BaseAuthorizationManager(resolver: r) }
    }
}
