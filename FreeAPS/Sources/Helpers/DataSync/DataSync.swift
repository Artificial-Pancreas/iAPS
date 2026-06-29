import Foundation

// It diffs the CURRENT local state against a SNAPSHOT of what was last synced:
//
//   * `syncID` present in current, not in snapshot          -> INSERT
//   * `syncID` present in both, `syncSignature` changed     -> UPDATE
//   * `syncID` present in both, `syncSignature` equal       -> no-op
//   * `syncID` present in snapshot, not in current          -> DELETE (if within the deletion window)

protocol SyncRecord: JSON {
    associatedtype SyncID: Hashable & Sendable
    associatedtype SyncSignature: Equatable & Sendable

    var syncID: SyncID { get }
    var syncSignature: SyncSignature { get }
    var syncDate: Date { get }
}

struct SyncUpsert<Record: SyncRecord>: Sendable {
    let record: Record
    let isUpdate: Bool
}

protocol SyncSink: Sendable {
    associatedtype Record: SyncRecord

    func upsert(_ items: [SyncUpsert<Record>]) async throws
    func delete(_ records: [Record]) async throws
}

enum DataSyncError: Error {
    case sinkUnavailable
}

actor DataSynchronizer<Record: SyncRecord, Sink: SyncSink> where Sink.Record == Record {
    private let name: String
    private let sink: Sink
    private let storage: FileStorage
    private let snapshotFile: String
    /// How far back records are kept in the snapshot.
    private let retention: TimeInterval
    /// How far back a record's absence is treated as a delete. Should be <= `retention`.
    private let deletionWindow: TimeInterval
    private let category: Logger.Category

    private let serializer = TaskSerializer()
    private var snapshot: [Record.SyncID: Record]?

    init(
        name: String,
        sink: Sink,
        storage: FileStorage,
        snapshotFile: String,
        retention: TimeInterval,
        deletionWindow: TimeInterval,
        category: Logger.Category = .service
    ) {
        self.name = name
        self.sink = sink
        self.storage = storage
        self.snapshotFile = snapshotFile
        self.retention = retention
        self.deletionWindow = deletionWindow
        self.category = category
    }

    /// Returns `true` if everything reconciled without a sink error
    /// (nothing left pending).
    /// A `false` means some upsert/delete failed and will be retried next reconcile.
    @discardableResult
    func reconcile(current: [Record]) async -> Bool {
        await serializer.run {
            await self.performReconcile(current: current)
        }
    }

    private func performReconcile(current: [Record]) async -> Bool {
        let now = Date()
        let retentionCutoff = now.removingTimeInterval(retention)
        let deletionCutoff = now.removingTimeInterval(deletionWindow)

        if snapshot == nil {
            snapshot = await loadSnapshot()
        }

        var working = snapshot!.filter { $0.value.syncDate >= retentionCutoff }

        let windowed = current.filter { $0.syncDate >= retentionCutoff }
        let currentIDs = Set(windowed.map(\.syncID))

        var upserts: [SyncUpsert<Record>] = []
        for record in windowed {
            if let previous = working[record.syncID] {
                if previous.syncSignature != record.syncSignature {
                    upserts.append(SyncUpsert(record: record, isUpdate: true))
                }
            } else {
                upserts.append(SyncUpsert(record: record, isUpdate: false))
            }
        }

        let toDelete: [Record] = windowed.isEmpty ? [] : working.values.filter {
            !currentIDs.contains($0.syncID) && $0.syncDate >= deletionCutoff
        }

        var changed = false
        var failed = false

        if toDelete.isNotEmpty {
            do {
                try await sink.delete(toDelete)
                for record in toDelete { working[record.syncID] = nil }
                changed = true
            } catch {
                failed = true
                debug(category, "data sync [\(name)]: delete failed: \(error.localizedDescription)")
            }
        }

        if upserts.isNotEmpty {
            do {
                try await sink.upsert(upserts)
                for upsert in upserts { working[upsert.record.syncID] = upsert.record }
                changed = true
            } catch {
                failed = true
                debug(category, "data sync [\(name)]: upsert failed: \(error.localizedDescription)")
            }
        }

        snapshot = working
        if changed {
            await saveSnapshot(working)
            debug(category, "data sync [\(name)]: +\(upserts.count) -\(toDelete.count)")
        }
        return !failed
    }

    private func loadSnapshot() async -> [Record.SyncID: Record] {
        let list = await storage.retrieve(snapshotFile, as: [Record].self) ?? []
        return Dictionary(list.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func saveSnapshot(_ snapshot: [Record.SyncID: Record]) async {
        await storage.save(Array(snapshot.values), as: snapshotFile)
    }
}
