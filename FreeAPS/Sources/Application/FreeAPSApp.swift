import SwiftUI
import Swinject

@main struct FreeAPSApp: App {
    private let resolver = Container(defaultObjectScope: .container) { container in
        UIContainer.register(container: container)
        StorageContainer.register(container: container)
        NetworkContainer.register(container: container)
        SecurityContainer.register(container: container)
    }.synchronize()

    var body: some Scene {
        resolver.resolve(AppearanceManager.self)!.setupGlobalAppearance()
        return WindowGroup {
            Main.Builder(resolver: resolver).buildView()
        }
    }
}
