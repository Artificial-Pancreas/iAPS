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
}
