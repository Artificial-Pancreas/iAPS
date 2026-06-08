import Foundation
import Swinject

final class APSAssembly: Assembly {
    func assemble(container: Container) {
        container.register(CalibrationService.self) { r in BaseCalibrationService(resolver: r) }
        container.register(BloodGlucoseManager.self) { r in BloodGlucoseManager(resolver: r) }
        container.register(DeviceDataManager.self) { r in BaseDeviceDataManager(resolver: r) }
        container.register(OpenAPS.self) { r in
            OpenAPS(
                storage: r.resolve(FileStorage.self)!,
                glucoseStorage: r.resolve(GlucoseStorage.self)!,
                nightscout: r.resolve(NightscoutManager.self)!,
                pumpStorage: r.resolve(PumpHistoryStorage.self)!,
                settingsManager: r.resolve(SettingsManager.self)!,
                appCoordinator: r.resolve(AppCoordinator.self)!,
            )
        }
        container.register(APSManager.self) { r in BaseAPSManager(resolver: r) }
        container.register(FetchTreatmentsManager.self) { r in
            let nightscoutManager = r.resolve(NightscoutManager.self)!
            let tempTargetsStorage = r.resolve(TempTargetsStorage.self)!
            let carbsStorage = r.resolve(CarbsStorage.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!
            let settingsManager = r.resolve(SettingsManager.self)!

            return BaseFetchTreatmentsManager(
                nightscoutManager: nightscoutManager,
                tempTargetsStorage: tempTargetsStorage,
                carbsStorage: carbsStorage,
                appCoordinator: appCoordinator,
                settingsManager: settingsManager
            )
        }
        container.register(FetchAnnouncementsManager.self) { r in
            let announcementsStorage = r.resolve(AnnouncementsStorage.self)!
            let nightscoutManager = r.resolve(NightscoutManager.self)!
            let apsManager = r.resolve(APSManager.self)!
            let settingsManager = r.resolve(SettingsManager.self)!
            let appCoordinator = r.resolve(AppCoordinator.self)!

            return BaseFetchAnnouncementsManager(
                announcementsStorage: announcementsStorage,
                nightscoutManager: nightscoutManager,
                apsManager: apsManager,
                settingsManager: settingsManager,
                appCoordinator: appCoordinator
            )
        }
        container.register(BluetoothStateManager.self) { r in BaseBluetoothStateManager(resolver: r) }
    }
}
