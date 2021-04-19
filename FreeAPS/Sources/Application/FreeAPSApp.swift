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
    @Environment(\.scenePhase) var scenePhase

    static let resolver = Container(defaultObjectScope: .container) { container in
        for dep in dependencies {
            dep.register(container: container)
        }
    }.synchronize()

    private static func loadServices() {
        resolver.resolve(AppearanceManager.self)!.setupGlobalAppearance()
        _ = resolver.resolve(DeviceDataManager.self)!
        _ = resolver.resolve(APSManager.self)!
        _ = resolver.resolve(FetchGlucoseManager.self)!
        _ = resolver.resolve(FetchTreatmentsManager.self)!
        _ = resolver.resolve(FetchAnnouncementsManager.self)!
    }

    init() {
        FreeAPSApp.resolver.setup()
        FreeAPSApp.loadServices()
    }

    var body: some Scene {
        WindowGroup {
            Main.Builder(resolver: FreeAPSApp.resolver).buildView()
        }
        .onChange(of: scenePhase) { newScenePhase in
            switch newScenePhase {
            case .active:
                debug(.default, "APPLICATION is active")
            case .inactive:
                debug(.default, "APPLICATION is inactive")
            case .background:
                debug(.default, "APPLICATION is in background")
            @unknown default:
                debug(.default, "APPLICATION: Received an unexpected scenePhase.")
            }
        }
    }
}
