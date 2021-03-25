import SwiftUI
import Swinject

private let dependencies: [DependeciesContainer.Type] = [
    StorageContainer.self,
    ServiceContainer.self,
    APSContainer.self,
    UIContainer.self,
    NetworkContainer.self,
    SecurityContainer.self
]

private extension Swinject.Resolver {
    func setup() {
        for dep in dependencies {
            dep.setup()
        }
    }
}

@main struct FreeAPSApp: App {
    static let resolver = Container(defaultObjectScope: .container) { container in
        for dep in dependencies {
            dep.register(container: container)
        }
    }.synchronize()

    private static func loadServices() {
        resolver.resolve(AppearanceManager.self)!.setupGlobalAppearance()
        _ = resolver.resolve(DeviceDataManager.self)!
        _ = resolver.resolve(APSManager.self)!
        _ = resolver.resolve(GlucoseManager.self)!
    }

    var body: some Scene {
        FreeAPSApp.resolver.setup()
        FreeAPSApp.loadServices()

        return WindowGroup {
            Main.Builder(resolver: FreeAPSApp.resolver).buildView()
        }
    }
}
