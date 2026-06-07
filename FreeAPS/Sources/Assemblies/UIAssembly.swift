import Foundation
import Swinject

final class UIAssembly: Assembly {
    func assemble(container: Container) {
        container.register(Router.self) { r in BaseRouter(resolver: r) }

        container.register(AppUIState.self) { r in
            let appCoordinator = r.resolve(AppCoordinator.self)!
            return MainActor.assumeIsolated {
                AppUIState(appCoordinator: appCoordinator)
            }
        }
    }
}
