import Foundation
import Swinject

class AppServices: ObservableObject {
    let deviceManager: DeviceDataManager
    let settingsManager: SettingsManager
    let carbsStorage: CarbsStorage
    let calendarManager: CalendarManager
    let apsManager: APSManager

    let resolver: Resolver

    init(assembler: Assembler) {
        resolver = assembler.resolver

        deviceManager = resolver.resolve(DeviceDataManager.self)!
        apsManager = resolver.resolve(APSManager.self)!
        _ = FreeAPSApp.resolver.resolve(BloodGlucoseManager.self)!
        _ = FreeAPSApp.resolver.resolve(FetchTreatmentsManager.self)!
        _ = FreeAPSApp.resolver.resolve(FetchAnnouncementsManager.self)!
        _ = FreeAPSApp.resolver.resolve(CalendarManager.self)!
        _ = FreeAPSApp.resolver.resolve(UserNotificationsManager.self)!
        _ = FreeAPSApp.resolver.resolve(WatchManager.self)!
        _ = FreeAPSApp.resolver.resolve(HealthKitManager.self)!
        _ = FreeAPSApp.resolver.resolve(BluetoothStateManager.self)!
        _ = FreeAPSApp.resolver.resolve(LiveActivityBridge.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        carbsStorage = resolver.resolve(CarbsStorage.self)!
        calendarManager = resolver.resolve(CalendarManager.self)!
        _ = FreeAPSApp.resolver.resolve(CoreDataStorageGlucoseSaver.self)!
    }
}
