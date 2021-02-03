import Foundation
import Swinject

private let resolver = FreeAPSApp.resolver

enum ServiceContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(APSManager.self) { _ in BaseAPSManager() }
    }
}
