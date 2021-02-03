import Swinject

private let resolver = FreeAPSApp.resolver

enum UIContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(AppearanceManager.self) { _ in BaseAppearanceManager() }
        container.register(Router.self) { _ in BaseRouter(resolver: resolver) }
    }
}
