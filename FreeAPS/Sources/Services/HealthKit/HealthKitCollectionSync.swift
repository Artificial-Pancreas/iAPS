import Combine
import Foundation
import HealthKit

/// One entity's worth of HealthKit sync: it owns its source, its gate and its `DataSynchronizer`.
///
/// Dedup comes from the locally persisted snapshot, never from reading HealthKit back - reads are the
/// thing that fails on a locked device, and a failed read is indistinguishable from an empty one, which
/// used to make every sample look new.
final actor HealthKitCollectionSync<Source: Sendable, Record: HealthKitRecord>: LifetimeOwner, AppService {
    let lifetime = Lifetime()

    private let name: String
    private let appCoordinator: AppCoordinator
    private let settingsManager: SettingsManager
    private let sync: DataSynchronizer<Record, HealthKitSink<Record>>
    private let source: KeyPath<AppCoordinator, CurrentValueSubject<Source, Never>> & Sendable
    private let records: @Sendable(Source) -> [Record]

    init(
        name: String,
        store: HKHealthStore,
        storage: FileStorage,
        snapshotFile: String,
        retention: TimeInterval,
        deletionWindow: TimeInterval,
        appCoordinator: AppCoordinator,
        settingsManager: SettingsManager,
        source: KeyPath<AppCoordinator, CurrentValueSubject<Source, Never>> & Sendable,
        records: @escaping @Sendable(Source) -> [Record]
    ) {
        self.name = name
        self.appCoordinator = appCoordinator
        self.settingsManager = settingsManager
        sync = DataSynchronizer(
            name: "healthkit.\(name)",
            sink: HealthKitSink(store: store),
            storage: storage,
            snapshotFile: snapshotFile,
            retention: retention,
            deletionWindow: deletionWindow
        )
        self.source = source
        self.records = records
    }

    func start() async {
        // not dropping the initial value: the snapshot diff makes a launch-time reconcile cheap when
        // there is nothing to do, and self-healing when a previous run left something unwritten
        observe(appCoordinator[keyPath: source]) { me, value in
            await withBackgroundTask("healthkit sync - \(me.name)") {
                await me.sourceUpdated(value)
            }
        }
        observe(appCoordinator.loopCompleted) { me, _ in
            await withBackgroundTask("healthkit sync retry - \(me.name)") {
                await me.retryPending()
            }
        }
        observe(notification: ProtectedData.didBecomeAvailable) { me in
            await withBackgroundTask("healthkit sync unlock - \(me.name)") {
                await me.retryPending()
            }
        }
    }

    private func sourceUpdated(_ value: Source) async {
        guard await isEnabled() else { return }

        guard await ProtectedData.isAvailable else {
            await sync.markPending()
            return
        }

        await sync.reconcile(trigger: .dataChanged, current: { [records] in records(value) })
    }

    /// Flushes work deferred by a locked store or a failed write. Runs every loop, and again the moment
    /// the device unlocks.
    private func retryPending() async {
        guard await isEnabled(), await ProtectedData.isAvailable else { return }

        let value = appCoordinator[keyPath: source].value
        await sync.reconcile(trigger: .retry, current: { [records] in records(value) })
    }

    private func isEnabled() async -> Bool {
        await settingsManager.settings.useAppleHealth
    }
}
