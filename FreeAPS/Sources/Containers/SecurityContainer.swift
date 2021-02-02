import Swinject

enum SecurityContainer {
    static func register(container: Container) {
        container.register(UnlockManager.self) { _ in BaseUnlockManager() }
    }
}
