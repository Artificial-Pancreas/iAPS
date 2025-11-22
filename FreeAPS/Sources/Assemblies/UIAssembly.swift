import Foundation
import Swinject

final class UIAssembly: Assembly {
    func assemble(container: Container) {
        container.register(Router.self) { r in BaseRouter(resolver: r) }
    }
}
