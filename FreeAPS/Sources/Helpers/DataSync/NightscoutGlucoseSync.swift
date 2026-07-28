import Foundation

struct GlucoseSyncID: Hashable, Sendable {
    let type: String?
    let dateString: Date
}

struct GlucoseSyncSignature: Hashable, Sendable {
    let dateString: Date
    let glucose: Int
    let direction: BloodGlucose.Direction?
    let type: String?
}

extension BloodGlucose: SyncRecord {
    var syncID: GlucoseSyncID {
        GlucoseSyncID(type: type, dateString: dateString.truncatedToSecond)
    }

    var syncDate: Date { dateString }

    var syncSignature: GlucoseSyncSignature {
        GlucoseSyncSignature(
            dateString: dateString.truncatedToSecond,
            glucose: glucose,
            direction: direction,
            type: type
        )
    }
}

struct NightscoutGlucoseSink: SyncSink {
    let apiProvider: @Sendable() async -> NightscoutAPI?

    func upsert(_ items: [SyncUpsert<BloodGlucose>]) async throws {
        guard let api = await apiProvider() else { throw DataSyncError.sinkUnavailable }

        let glucose = items.map(\.record).filter { UUID(uuidString: $0._id) != nil }
        for chunk in glucose.chunks(ofCount: 100) {
            let entries = chunk.compactMap(\.toNightscoutEntry)
            _ = try await api.uploadGlucose(Array(entries))
        }
    }

    func delete(_ records: [BloodGlucose]) async throws {
        guard let api = await apiProvider() else { throw DataSyncError.sinkUnavailable }

        for record in records where record.type == GlucoseType.manual.rawValue {
            try await api.deleteManualGlucose(at: record.dateString)
        }
    }
}
