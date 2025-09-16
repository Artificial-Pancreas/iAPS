import Foundation
import Swinject

final class APSAssembly: Assembly {
    func assemble(container: Container) {
        container.register(CalibrationService.self) { r in BaseCalibrationService(resolver: r) }
        container.register(BloodGlucoseManager.self) { r in BloodGlucoseManager(resolver: r) }
        container.register(DeviceDataManager.self) { r in BaseDeviceDataManager(resolver: r) }
        container.register(APSManager.self) { r in BaseAPSManager(resolver: r) }
        container.register(FetchTreatmentsManager.self) { r in BaseFetchTreatmentsManager(resolver: r) }
        container.register(FetchAnnouncementsManager.self) { r in BaseFetchAnnouncementsManager(resolver: r) }
        container.register(BluetoothStateManager.self) { r in BaseBluetoothStateManager(resolver: r) }
    }
}
