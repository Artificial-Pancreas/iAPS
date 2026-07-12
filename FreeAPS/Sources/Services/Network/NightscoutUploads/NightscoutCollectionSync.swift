import Combine
import Foundation

final actor NightscoutCollectionSync<Source: Sendable, Record: SyncRecord, Sink: SyncSink>: LifetimeOwner, AppService
    where Sink.Record == Record
{
    let lifetime = Lifetime()

    private let name: String
    private let context: NightscoutUploadContext
    private let gate: UploadScheduleGate
    private let sync: DataSynchronizer<Record, Sink>
    private let source: KeyPath<AppCoordinator, CurrentValueSubject<Source, Never>> & Sendable
    private let isEnabled: @Sendable(AppCoordinator) -> Bool
    private let prepare: (@Sendable(Source) async -> Bool)?
    private let records: @Sendable(Source) async -> [Record]

    /// - Parameters:
    ///   - source: the app coordinator subject that both pushes changes and serves the current value for retries
    ///   - isEnabled: extra per-entity condition; when false the entity is silent (no upload, no pending work)
    ///   - prepare: runs on every source emission, before any checks; returns whether it produced
    ///     new data to upload. When set, a reconcile only happens for pending work, so emissions
    ///     that carry nothing new are cheap.
    ///   - records: converts the source value into the records to sync
    init(
        name: String,
        group: UploadScheduleGroup,
        sink: Sink,
        snapshotFile: String,
        retention: TimeInterval,
        deletionWindow: TimeInterval,
        context: NightscoutUploadContext,
        source: KeyPath<AppCoordinator, CurrentValueSubject<Source, Never>> & Sendable,
        isEnabled: @escaping @Sendable(AppCoordinator) -> Bool = { _ in true },
        prepare: (@Sendable(Source) async -> Bool)? = nil,
        records: @escaping @Sendable(Source) async -> [Record]
    ) {
        self.name = name
        self.context = context
        gate = context.makeGate(name: name, group: group)
        sync = DataSynchronizer(
            name: "ns.\(name)",
            sink: sink,
            storage: context.storage,
            snapshotFile: snapshotFile,
            retention: retention,
            deletionWindow: deletionWindow,
            category: .nightscout
        )
        self.source = source
        self.isEnabled = isEnabled
        self.prepare = prepare
        self.records = records
    }

    func start() async {
        observe(context.appCoordinator[keyPath: source]) { me, value in
            await withBackgroundTask("nightscout upload - \(me.name)") {
                await me.sourceUpdated(value)
            }
        }

        observe(context.appCoordinator.loopCompleted) { me, _ in
            await withBackgroundTask("nightscout upload retry - \(me.name)") {
                await me.retryPending()
            }
        }
    }

    private func sourceUpdated(_ value: Source) async {
        var trigger: SyncTrigger = .dataChanged
        if let prepare {
            if await prepare(value) {
                await sync.markPending()
            }
            trigger = .retry
        }

        guard isEnabled(context.appCoordinator) else { return }
        guard context.canUpload(), await gate.allows() else {
            if trigger == .dataChanged {
                await sync.markPending()
            }
            return
        }

        if await sync.reconcile(trigger: trigger, current: { [records] in await records(value) }) == .synced {
            gate.recordUpload()
        }
    }

    /// runs every loop: flushes deferred work (schedule or failure) once the schedule allows uploading again
    private func retryPending() async {
        guard isEnabled(context.appCoordinator), context.canUpload(), await gate.allows() else { return }
        let value = context.appCoordinator[keyPath: source].value
        if await sync.reconcile(trigger: .retry, current: { [records] in await records(value) }) == .synced {
            gate.recordUpload()
        }
    }
}
