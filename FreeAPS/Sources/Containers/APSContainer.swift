import Foundation
import Swinject

private let resolver = FreeAPSApp.resolver

enum APSContainer: DependeciesContainer {
    static func register(container: Container) {
        container.register(DeviceDataManager.self) { _ in BaseDeviceDataManager(resolver: resolver) }
        container.register(APSManager.self) { _ in BaseAPSManager(resolver: resolver) }
        container.register(FetchGlucoseManager.self) { _ in BaseFetchGlucoseManager(resolver: resolver) }
        container.register(FetchTreatmentsManager.self) { _ in BaseFetchTreatmentsManager(resolver: resolver) }
        container.register(FetchAnnouncementsManager.self) { _ in BaseFetchAnnouncementsManager(resolver: resolver) }
    }
}
