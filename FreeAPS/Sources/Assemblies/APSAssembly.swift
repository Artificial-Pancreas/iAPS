import Foundation
import Swinject

final class APSAssembly: Assembly {
    func assemble(container: Container) {
        container.register(CalibrationService.self) { r in BaseCalibrationService(resolver: r) }
        container.register(LibreTransmitterSource.self) { r in BaseLibreTransmitterSource(resolver: r) }
        container.register(DeviceDataManager.self) { r in BaseDeviceDataManager(resolver: r) }
        container.register(APSManager.self) { r in BaseAPSManager(resolver: r) }
        container.register(FetchGlucoseManager.self) { r in BaseFetchGlucoseManager(resolver: r) }
        container.register(FetchTreatmentsManager.self) { r in BaseFetchTreatmentsManager(resolver: r) }
        container.register(FetchAnnouncementsManager.self) { r in BaseFetchAnnouncementsManager(resolver: r) }
    }
}
