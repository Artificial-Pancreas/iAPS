import Swinject

enum UIContainer {
    static func register(container: Container) {
        container.register(AppearanceManager.self) { _ in BaseAppearanceManager() }
        container.register(Router.self) { r in BaseRouter(resolver: r) }
    }
}
