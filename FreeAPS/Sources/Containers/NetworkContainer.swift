import Alamofire
import Swinject
import UIKit

private let resolver = FreeAPSApp.resolver

enum NetworkContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }.inObjectScope(.transient)

        container.register(NightscoutManager.self) { _ in BaseNightscoutManager(resolver: resolver) }
        container.register(AuthorizationManager.self) { _ in BaseAuthorizationManager(resolver: resolver) }
    }
}
