import Foundation
import Swinject

@MainActor final class AppServices {
    private(set) var deviceManager: DeviceDataManager?

    private var startup: Task<Void, Error>?

    init(resolver: Resolver) {
        start(resolver: resolver)
    }

    private func start(resolver: Resolver) {
        guard startup == nil else { return }
        startup = Task { try await self.performStartup(resolver: resolver) }
    }

    func started() async throws { try await startup?.value }

    private func performStartup(resolver: Resolver) async throws {
        try await startService(resolver.resolve(SettingsManager.self))

        _ = resolver.resolve(BluetoothStateManager.self)!

        try await startService(resolver.resolve(FetchTreatmentsManager.self))
        try await startService(resolver.resolve(FetchAnnouncementsManager.self))
        try await startService(resolver.resolve(UserNotificationsManager.self))
        try await startService(resolver.resolve(WatchManager.self))
        try await startService(resolver.resolve(HealthKitManager.self))
        try await startService(resolver.resolve(LiveActivityBridge.self))
        try await startService(resolver.resolve(CoreDataStorageGlucoseSaver.self))
        try await startService(resolver.resolve(CalendarManager.self))
        try await startService(resolver.resolve(DatabaseManager.self))
        try await startService(resolver.resolve(ContactTrickManager.self))
        try await startService(resolver.resolve(NightscoutManager.self))
        try await startService(resolver.resolve(ProfileAndSettingsUploadManager.self))

        deviceManager = resolver.resolve(DeviceDataManager.self)!

        try await startService(resolver.resolve(APSManager.self)!)

        try await startService(resolver.resolve(AppUIState.self))
    }

    @discardableResult private func startService<Service>(_ service: Service?) async throws -> Service {
        if let service, let startable = service as? AppService {
            await startable.start()
            return service
        } else {
            throw NSError(
                domain: "APP_INIT",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "not an AppService: \(String(describing: service))"]
            )
        }
    }
}

protocol AppService: Sendable {
    func start() async
}
