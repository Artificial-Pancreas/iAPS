import Foundation

struct TreatmentSyncID: Hashable, Sendable {
    let eventType: EventType
    let createdAt: Date
}

struct TreatmentSyncSignature: Hashable, Sendable {
    let createdAt: Date
    let duration: Decimal?
    let rate: Decimal?
    let absolute: Decimal?
    let insulin: Decimal?
    let carbs: Decimal?
    let fat: Decimal?
    let protein: Decimal?
    let targetTop: Decimal?
    let targetBottom: Decimal?
    let notes: String?
    let foodType: String?
    let glucoseType: String?
    let glucose: String?
    let units: String?
}

extension NigtscoutTreatment: SyncRecord {
    var syncID: TreatmentSyncID {
        TreatmentSyncID(eventType: eventType, createdAt: createdAt.truncatedToSecond)
    }

    var syncDate: Date { createdAt }

    var syncSignature: TreatmentSyncSignature {
        TreatmentSyncSignature(
            createdAt: createdAt.truncatedToSecond,
            duration: duration,
            rate: rate,
            absolute: absolute,
            insulin: insulin,
            carbs: carbs,
            fat: fat,
            protein: protein,
            targetTop: targetTop,
            targetBottom: targetBottom,
            notes: notes,
            foodType: foodType,
            glucoseType: glucoseType,
            glucose: glucose,
            units: units
        )
    }
}

struct NightscoutTreatmentSink: SyncSink {
    let apiProvider: @Sendable() async -> NightscoutAPI?

    func upsert(_ items: [SyncUpsert<NigtscoutTreatment>]) async throws {
        guard let api = await apiProvider() else { throw DataSyncError.sinkUnavailable }

        for item in items where item.isUpdate {
            try await api.deleteTreatment(item.record)
        }
        try await api.uploadTreatments(items.map(\.record))
    }

    func delete(_ records: [NigtscoutTreatment]) async throws {
        guard let api = await apiProvider() else { throw DataSyncError.sinkUnavailable }
        for record in records {
            try await api.deleteTreatment(record)
        }
    }
}
