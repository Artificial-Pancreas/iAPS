import Swinject

private let resolver = FreeAPSApp.resolver

enum SecurityContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(UnlockManager.self) { _ in BaseUnlockManager() }
    }
}
