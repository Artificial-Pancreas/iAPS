import Combine
import Foundation

final actor NightscoutCollectionSync<Source: Sendable, Record: SyncRecord, Sink: SyncSink>: LifetimeOwner, NightscoutUploadEntity
    where Sink.Record == Record
{
    let lifetime = Lifetime()

    private let name: String
    private let context: NightscoutUploadContext
    private let gate: UploadScheduleGate
    private let sync: DataSynchronizer<Record, Sink>
    /// the source's pushes
    private let changes: @Sendable(AppCoordinator) -> AnyPublisher<Source, Never>
    /// the records to sync now, read only when there is work pending
    private let current: @Sendable(AppCoordinator) async -> [Record]
    private let isEnabled: @Sendable(AppCoordinator) -> Bool
    private let prepare: (@Sendable(Source) async -> Bool)?
    private let isUrgent: (@Sendable(_ previous: Source, _ current: Source) -> Bool)?
    /// the previous source value, for `isUrgent`
    private var previous: Source?
    private let flushSerializer = TaskSerializer()

    /// - Parameters:
    ///   - source: the app coordinator subject that both pushes changes and serves the current value for uploads
    ///   - isEnabled: extra per-entity condition; when false the entity doesn't upload (its work stays pending)
    ///   - prepare: runs on every source emission; returns whether it produced new data to upload.
    ///     When set, only emissions that do mark the work pending.
    ///   - records: converts the source value into the records to sync
    ///   - isUrgent: whether a change should be uploaded right away, instead of with the next loop's burst
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
        records: @escaping @Sendable(Source) async -> [Record],
        isUrgent: (@Sendable(_ previous: Source, _ current: Source) -> Bool)? = nil
    ) {
        self.init(
            name: name,
            group: group,
            sink: sink,
            snapshotFile: snapshotFile,
            retention: retention,
            deletionWindow: deletionWindow,
            context: context,
            changes: { $0[keyPath: source].eraseToAnyPublisher() },
            current: { await records($0[keyPath: source].value) },
            isEnabled: isEnabled,
            prepare: prepare,
            isUrgent: isUrgent
        )
    }

    /// An entity whose source only pushes (a `PassthroughSubject` of events): `record` keeps each push where `records`
    /// reads it (a local log), and returns whether it added anything to upload.
    init(
        name: String,
        group: UploadScheduleGroup,
        sink: Sink,
        snapshotFile: String,
        retention: TimeInterval,
        deletionWindow: TimeInterval,
        context: NightscoutUploadContext,
        events: KeyPath<AppCoordinator, PassthroughSubject<Source, Never>> & Sendable,
        record: @escaping @Sendable(Source) async -> Bool,
        records: @escaping @Sendable() async -> [Record]
    ) {
        self.init(
            name: name,
            group: group,
            sink: sink,
            snapshotFile: snapshotFile,
            retention: retention,
            deletionWindow: deletionWindow,
            context: context,
            changes: { $0[keyPath: events].eraseToAnyPublisher() },
            current: { _ in await records() },
            isEnabled: { _ in true },
            prepare: record,
            isUrgent: nil
        )
    }

    private init(
        name: String,
        group: UploadScheduleGroup,
        sink: Sink,
        snapshotFile: String,
        retention: TimeInterval,
        deletionWindow: TimeInterval,
        context: NightscoutUploadContext,
        changes: @escaping @Sendable(AppCoordinator) -> AnyPublisher<Source, Never>,
        current: @escaping @Sendable(AppCoordinator) async -> [Record],
        isEnabled: @escaping @Sendable(AppCoordinator) -> Bool,
        prepare: (@Sendable(Source) async -> Bool)?,
        isUrgent: (@Sendable(_ previous: Source, _ current: Source) -> Bool)?
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
        self.changes = changes
        self.current = current
        self.isEnabled = isEnabled
        self.prepare = prepare
        self.isUrgent = isUrgent
    }

    func start() async {
        observe(changes(context.appCoordinator)) { me, value in
            await me.sourceUpdated(value)
        }
    }

    /// only marks the work pending: the next burst uploads it
    private func sourceUpdated(_ value: Source) async {
        let previous = self.previous
        if isUrgent != nil {
            self.previous = value
        }

        if let prepare {
            guard await prepare(value) else { return }
        }
        await sync.markPending()

        guard let isUrgent, let previous, isEnabled(context.appCoordinator), isUrgent(previous, value) else { return }
        await context.burst.requestImmediate()
    }

    func flush(startedAt: Date) async {
        // bursts can overlap: one flush at a time, so the gate check can't race
        await flushSerializer.run {
            await self.performFlush(startedAt: startedAt)
        }
    }

    private func performFlush(startedAt: Date) async {
        guard isEnabled(context.appCoordinator), context.canUpload(), await gate.allows() else { return }
        // the latest value, read only when there is work pending
        let read: @Sendable() async -> [Record] = { [context, current] in
            await current(context.appCoordinator)
        }
        if await sync.reconcile(trigger: .retry, current: read) == .synced {
            gate.recordUpload(at: startedAt)
        }
    }
}

extension Array where Element: SyncRecord {
    /// what a sync compares: arrays with equal states upload the same
    var syncState: [Element.SyncID: Element.SyncSignature] {
        Dictionary(map { ($0.syncID, $0.syncSignature) }, uniquingKeysWith: { first, _ in first })
    }
}
