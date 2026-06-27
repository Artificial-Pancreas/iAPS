import Foundation
import Swinject

class BaseIntentsRequest: Injectable {
    @Injected() var appCoordinator: AppCoordinator!
    @Injected() var tempTargetsStorage: TempTargetsStorage!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var fileStorage: FileStorage!
    @Injected() var carbsStorage: CarbsStorage!
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var apsManager: APSManager!
    @Injected() var nightscoutManager: NightscoutManager!

    let overrideStorage = OverrideStorage()
    let coreDataStorage = CoreDataStorage()

    let resolver: Resolver

    init() {
        resolver = FreeAPSApp.resolver
        injectServices(resolver)
    }

    // iAPS can be started from an iOS shortcut, so the main app startup will not have happened/waited for the `appServices` to start all the services/managers.
    // we await this at each shortcut entry point to make sure AppCoordinator is initialized.
    @MainActor static func awaitStartup() async throws {
        try await FreeAPSApp.resolver.resolve(AppServices.self)!.started()
    }
}
