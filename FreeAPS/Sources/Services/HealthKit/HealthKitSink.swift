import Foundation
import HealthKit

struct HealthKitSink<Record: HealthKitRecord>: SyncSink {
    let store: HKHealthStore

    func upsert(_ items: [SyncUpsert<Record>]) async throws {
        let types = try await writableSampleTypes()

        // HealthKit only replaces a sample by sync identifier when the sync version increases, and we
        // don't carry versions, so an update has to be a delete followed by a fresh write.
        let updated = items.filter(\.isUpdate).flatMap(\.record.sampleSyncIDs)
        try await purge(types: types, syncIDs: updated)

        // a type the user declined is dropped rather than failing the whole batch: denying fat should
        // not stop carbs from syncing
        let samples = items
            .flatMap { $0.record.makeSamples() }
            .filter { types.contains($0.quantityType) }

        guard samples.isNotEmpty else { return }
        try await store.save(samples)
    }

    func delete(_ records: [Record]) async throws {
        let types = try await writableSampleTypes()
        try await purge(types: types, syncIDs: records.flatMap(\.sampleSyncIDs))
    }

    /// Throwing `sinkUnavailable` (rather than silently succeeding) is what keeps the work pending:
    /// `DataSynchronizer` records the failure and replays it on the next retry.
    private func writableSampleTypes() async throws -> Set<HKQuantityType> {
        guard await ProtectedData.isAvailable else { throw DataSyncError.sinkUnavailable }

        let authorized = Record.sampleTypes.filter {
            store.authorizationStatus(for: $0) == .sharingAuthorized
        }
        guard authorized.isNotEmpty else { throw DataSyncError.sinkUnavailable }

        return Set(authorized)
    }

    private func purge(types: Set<HKQuantityType>, syncIDs: [String]) async throws {
        guard syncIDs.isNotEmpty else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: syncIDs
        )
        for type in types {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }
}
