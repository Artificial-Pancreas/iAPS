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

        // Before anything resolves a storage. A store that can't be opened stops the startup here (StartupGate shows
        // the error): no loop and no device managers run on an empty database.
        try await CoreDataStack.shared.loadStores()

        try await startService(resolver.resolve(DataMigrations.self))

        let appCoordinator = resolver.resolve(AppCoordinator.self)!
        Logger.WarningLogHandler.handler = { messageCont in
            appCoordinator.sendAlertMessage(messageCont)
        }

        try await startService(resolver.resolve(SettingsManager.self))
        // installs the crash handlers if the launch-time attempt ran before the first unlock,
        // and handles the reports of the previous run (needs the Sharing setting)
        try await startService(resolver.resolve(CrashReportService.self))
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
        // before anything stores readings: it listens for their changes
        try await startService(resolver.resolve(GlucoseStatistics.self))
        // before PumpHistoryStorage publishes the file, which it mirrors; its start() only registers observers. Also
        // before DeviceDataManager (it creates the pump manager): the pump's change events (pumpLifecycleEvents, a
        // PassthroughSubject) sent before the store observes them would be lost (the heartbeat's fallback start covers that)
        try await startService(resolver.resolve(PumpEventStore.self))
        // listens for the insulin data changes the store (and the Reasons save) send; its start() only registers observers
        try await startService(resolver.resolve(InsulinStatsService.self))
        try await startService(resolver.resolve(DatabaseManager.self))
        try await startService(resolver.resolve(LoopStatRecordStorage.self))

        try await startService(resolver.resolve(NightscoutAPIProvider.self))
        // before DeviceDataManager too: its Site Changes come from pumpLifecycleEvents
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
        try await startService(resolver.resolve(UserNotificationsManager.self))
        try await startService(resolver.resolve(DeviceAlertManager.self))

        try await startService(resolver.resolve(AppUIState.self))

        try await startService(resolver.resolve(FetchTreatmentsManager.self))
        try await startService(resolver.resolve(FetchAnnouncementsManager.self))
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
