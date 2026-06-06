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
        container.register(FetchTreatmentsManager.self) { r in BaseFetchTreatmentsManager(resolver: r) }
        container.register(FetchAnnouncementsManager.self) { r in BaseFetchAnnouncementsManager(resolver: r) }
        container.register(BluetoothStateManager.self) { r in BaseBluetoothStateManager(resolver: r) }
    }
}
