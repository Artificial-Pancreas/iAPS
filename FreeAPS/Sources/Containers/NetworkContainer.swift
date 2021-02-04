import Swinject
import UIKit

private let resolver = FreeAPSApp.resolver

enum NetworkContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(NetworkManager.self) { _ in BaseNetworkManager(resolver: resolver) }
        container.register(AuthorizationManager.self) { _ in BaseAuthorizationManager(resolver: resolver) }
    }
}
