import Foundation
import Swinject

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }

        container.register(NightscoutManager.self) { r in BaseNightscoutManager(resolver: r) }
        container.register(LibreLinkManager.self) { r in BaseLibreLinkManager(resolver: r) }
    }
}
