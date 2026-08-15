import Foundation
import Swinject

@MainActor final class AppServices {
    private(set) var appCoordinator: AppCoordinator?

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
        // Nothing below may run while our own files are unreadable.
        await ProtectedData.waitUntilFilesAreReadable()

        try await startService(resolver.resolve(DataMigrations.self))

        let appCoordinator = resolver.resolve(AppCoordinator.self)!
        Logger.WarningLogHandler.handler = { messageCont in
            appCoordinator.sendAlertMessage(messageCont)
        }

        try await startService(resolver.resolve(SettingsManager.self))
        try await startService(resolver.resolve(BasalProfileStorage.self))
        try await startService(resolver.resolve(AutotuneStorage.self))
        try await startService(resolver.resolve(IsfScheduleStorage.self))
        try await startService(resolver.resolve(CarbRatioScheduleStorage.self))
        try await startService(resolver.resolve(BgTargetsScheduleStorage.self))
        // must be before MetricKit (a crash event, if any, replaces the app start event)
        try await startService(resolver.resolve(LoopEventsStorage.self))
        try await startService(resolver.resolve(MetricKitService.self))

        _ = resolver.resolve(BluetoothStateManager.self)!

        try await startService(resolver.resolve(CoreDataManager.self))
        try await startService(resolver.resolve(DatabaseManager.self))
        try await startService(resolver.resolve(LoopStatRecordStorage.self))

        try await startService(resolver.resolve(NightscoutAPIProvider.self))
        try await startService(resolver.resolve(NightscoutUploads.self))
        try await startService(resolver.resolve(PumpHistoryStorage.self))
        try await startService(resolver.resolve(GlucoseStorage.self))
        try await startService(resolver.resolve(CarbsStorage.self))
        try await startService(resolver.resolve(TempTargetsStorage.self))
        try await startService(resolver.resolve(CalibrationService.self))

        try await startService(resolver.resolve(OverrideManager.self)!)

        try await startService(resolver.resolve(DynamicStateManager.self)!)

        try await startService(resolver.resolve(APSManager.self)!)

        try await startService(resolver.resolve(DeviceDataManager.self))

        try await startService(resolver.resolve(AppUIState.self))

        try await startService(resolver.resolve(FetchTreatmentsManager.self))
        try await startService(resolver.resolve(FetchAnnouncementsManager.self))
        try await startService(resolver.resolve(UserNotificationsManager.self))
        try await startService(resolver.resolve(CalendarManager.self))
        try await startService(resolver.resolve(WatchManager.self))
        try await startService(resolver.resolve(HealthKitManager.self))
        try await startService(resolver.resolve(LiveActivityBridge.self))
        try await startService(resolver.resolve(ContactTrickManager.self))
        try await startService(resolver.resolve(ProfileAndSettingsUploadManager.self))

        self.appCoordinator = appCoordinator
    }

    @discardableResult private func startService<Service>(_ service: Service?) async throws -> Service {
        if let service, let startable = service as? AppService {
            try await startable.start()
            return service
        } else if let service, let startable = service as? AppServiceSync {
            startable.start()
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
    func start() async throws
}

protocol AppServiceSync: Sendable {
    func start()
}
