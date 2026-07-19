import Foundation
import HealthKit

/// A record that maps onto one or more HealthKit quantity samples.
///
/// A sample's sync identifier is the only thing upserts and deletes match on, so a given entry must
/// derive the same identifiers every single time.
protocol HealthKitRecord: SyncRecord where SyncID == String {
    static var sampleTypes: [HKQuantityType] { get }

    var sampleSyncIDs: [String] { get }

    func makeSamples() -> [HKQuantitySample]
}

extension HealthKitRecord {
    var sampleSyncIDs: [String] { [syncID] }
}

private let sourceMetaKey = "From iAPS"

private func quantitySample(
    type: HKQuantityType,
    unit: HKUnit,
    value: Double,
    syncID: String,
    start: Date,
    end: Date,
    extraMetadata: [String: Any] = [:]
) -> HKQuantitySample {
    var metadata: [String: Any] = [
        HKMetadataKeyExternalUUID: syncID,
        HKMetadataKeySyncIdentifier: syncID,
        HKMetadataKeySyncVersion: 1,
        sourceMetaKey: true
    ]
    metadata.merge(extraMetadata) { _, new in new }

    return HKQuantitySample(
        type: type,
        quantity: HKQuantity(unit: unit, doubleValue: value),
        start: start,
        end: end,
        metadata: metadata
    )
}

struct HealthKitGlucose: JSON, HealthKitRecord {
    struct Signature: Equatable, Sendable {
        let date: Date
        let glucose: Int
    }

    let id: String
    let date: Date
    let glucose: Int

    static let glucoseType = HKObjectType.quantityType(forIdentifier: .bloodGlucose)

    static var sampleTypes: [HKQuantityType] { [glucoseType].compactMap { $0 } }

    var syncID: String { id }
    var syncDate: Date { date }
    var syncSignature: Signature { Signature(date: date, glucose: glucose) }

    func makeSamples() -> [HKQuantitySample] {
        guard let type = Self.glucoseType else { return [] }
        return [
            quantitySample(
                type: type,
                unit: .milligramsPerDeciliter,
                value: Double(glucose),
                syncID: id,
                start: date,
                end: date
            )
        ]
    }

    static func from(_ entries: [BloodGlucose]) -> [HealthKitGlucose] {
        entries.compactMap { entry in
            let glucose = entry.glucose
            guard glucose > 0 else { return nil }
            return HealthKitGlucose(id: entry.id, date: entry.dateString, glucose: glucose)
        }
    }
}

struct HealthKitCarbs: JSON, HealthKitRecord {
    struct Signature: Equatable, Sendable {
        let date: Date
        let carbs: Decimal
        let fat: Decimal?
        let protein: Decimal?
    }

    let id: String
    let date: Date
    let carbs: Decimal
    let fat: Decimal?
    let protein: Decimal?

    static let carbType = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
    static let fatType = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
    static let proteinType = HKObjectType.quantityType(forIdentifier: .dietaryProtein)

    static var sampleTypes: [HKQuantityType] { [carbType, fatType, proteinType].compactMap { $0 } }

    var syncID: String { id }
    var syncDate: Date { date }
    var syncSignature: Signature { Signature(date: date, carbs: carbs, fat: fat, protein: protein) }

    private var fatSyncID: String { "\(id)-fat" }
    private var proteinSyncID: String { "\(id)-protein" }

    var sampleSyncIDs: [String] { [id, fatSyncID, proteinSyncID] }

    func makeSamples() -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []

        func append(_ grams: Decimal?, type: HKQuantityType?, syncID: String) {
            guard let grams, grams > 0, let type else { return }
            samples.append(
                quantitySample(
                    type: type,
                    unit: .gram(),
                    value: Double(grams),
                    syncID: syncID,
                    start: date,
                    end: date
                )
            )
        }

        append(carbs, type: Self.carbType, syncID: id)
        append(fat, type: Self.fatType, syncID: fatSyncID)
        append(protein, type: Self.proteinType, syncID: proteinSyncID)

        return samples
    }

    static func from(_ entries: [CarbsEntry]) -> [HealthKitCarbs] {
        entries.compactMap { entry in
            guard let id = entry.id, entry.isSyncableMeal else { return nil }
            return HealthKitCarbs(
                id: id,
                date: entry.actualDate ?? entry.createdAt,
                carbs: entry.carbs,
                fat: entry.fat,
                protein: entry.protein
            )
        }
    }
}

struct HealthKitInsulin: JSON, HealthKitRecord {
    enum Reason: String, JSON {
        case bolus
        case basal

        var deliveryReason: HKInsulinDeliveryReason {
            switch self {
            case .bolus: return .bolus
            case .basal: return .basal
            }
        }
    }

    struct Signature: Equatable, Sendable {
        let units: Decimal
        let start: Date
        let end: Date
    }

    let id: String
    let reason: Reason
    let units: Decimal
    let start: Date
    let end: Date

    static let insulinType = HKObjectType.quantityType(forIdentifier: .insulinDelivery)

    static var sampleTypes: [HKQuantityType] { [insulinType].compactMap { $0 } }

    var syncID: String { id }
    var syncDate: Date { start }
    var syncSignature: Signature { Signature(units: units, start: start, end: end) }

    func makeSamples() -> [HKQuantitySample] {
        guard let type = Self.insulinType else { return [] }
        return [
            quantitySample(
                type: type,
                unit: .internationalUnit(),
                value: Double(units),
                syncID: id,
                start: start,
                end: end,
                extraMetadata: [
                    HKMetadataKeyInsulinDeliveryReason: NSNumber(value: reason.deliveryReason.rawValue)
                ]
            )
        ]
    }

    /// Pump history stores a temp basal as a *pair* of events sharing a timestamp: a `.tempBasalDuration`
    /// carrying `durationMin` under id `X`, and a `.tempBasal` carrying the rate under id `_X`. When the
    /// TBR ends, that pair is rewritten in place with the real duration and `deliveredUnits` - so a
    /// running TBR syncs at its scheduled amount and is corrected to the delivered amount once it
    /// finalizes, which the snapshot diff picks up as a signature change.
    static func from(_ events: [PumpHistoryEvent]) -> [HealthKitInsulin] {
        let boluses = events.compactMap { event -> HealthKitInsulin? in
            guard event.type == .bolus, let units = event.amount, units > 0 else { return nil }
            return HealthKitInsulin(
                id: event.id,
                reason: .bolus,
                units: units,
                start: event.timestamp,
                end: event.timestamp
            )
        }

        let durations = Dictionary(
            events.filter { $0.type == .tempBasalDuration }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let basals = events.compactMap { event -> HealthKitInsulin? in
            guard event.type == .tempBasal else { return nil }

            let id = event.id.hasPrefix("_") ? String(event.id.dropFirst()) : event.id
            guard let duration = durations[id]?.durationMin, duration > 0 else { return nil }

            let units = event.deliveredUnits ?? ((event.rate ?? 0) * duration / 60)
            guard units > 0 else { return nil }

            return HealthKitInsulin(
                id: id,
                reason: .basal,
                units: units,
                start: event.timestamp,
                end: event.timestamp.addingTimeInterval(.minutes(duration))
            )
        }

        return boluses + basals
    }
}
