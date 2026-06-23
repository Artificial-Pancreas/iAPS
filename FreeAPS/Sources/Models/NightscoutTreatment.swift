import Foundation

struct NigtscoutTreatment: JSON {
    var duration: Decimal?
    var rawDuration: PumpHistoryEvent?
    var rawRate: PumpHistoryEvent?
    var absolute: Decimal?
    var rate: Decimal?
    var eventType: EventType
    var createdAt: Date
    var enteredBy: String?
    var bolus: PumpHistoryEvent?
    var insulin: Decimal?
    var notes: String?
    var carbs: Decimal?
    var fat: Decimal?
    var protein: Decimal?
    var foodType: String?
    let targetTop: Decimal?
    let targetBottom: Decimal?
    var glucoseType: String?
    var glucose: String?
    var units: String?
    var id: String?
    var fpuID: String?
    var creation_date: Date?

    static let local = "iAPS"
    static let trio = "Trio"

    static let empty = NigtscoutTreatment(from: "{}")!
}

extension NigtscoutTreatment {
    private enum CodingKeys: String, CodingKey {
        case duration
        case rawDuration = "raw_duration"
        case rawRate = "raw_rate"
        case absolute
        case rate
        case eventType
        case createdAt = "created_at"
        case enteredBy
        case bolus
        case insulin
        case notes
        case carbs
        case fat
        case protein
        case foodType
        case targetTop
        case targetBottom
        case glucoseType
        case glucose
        case units
        case id
        case fpuID
        case creation_date
    }
}

// used by NightscoutManager to check if two treatments are the same event (different versions of the same event)
struct NigtscoutTreatmentIdentity: Equatable, Hashable {
    let eventType: EventType
    let createdAt: Date
}

// used by NightscoutManager to check if two treatments hold the same data - if not, they need to be updated in nightscout
// any field that can be edited in iAPS needs to be part of this structure, otherwise local edits to that field will not be re-uploaded to nightscout
struct NigtscoutTreatmentData: Equatable, Hashable {
    let duration: Decimal?
    let absolute: Decimal?
    let rate: Decimal?
    let eventType: EventType
    let createdAt: Date
    let insulin: Decimal?
    let notes: String?
    let carbs: Decimal?
    let fat: Decimal?
    let protein: Decimal?
    let foodType: String?
    let targetTop: Decimal?
    let targetBottom: Decimal?
    let glucoseType: String?
    let glucose: String?
    let units: String?
}

extension NigtscoutTreatment {
    var identity: NigtscoutTreatmentIdentity {
        NigtscoutTreatmentIdentity(
            eventType: eventType,
            createdAt: createdAt.truncatedToSecond
        )
    }

    var data: NigtscoutTreatmentData {
        NigtscoutTreatmentData(
            duration: duration,
            absolute: absolute,
            rate: rate,
            eventType: eventType,
            createdAt: createdAt,
            insulin: insulin,
            notes: notes,
            carbs: carbs,
            fat: fat,
            protein: protein,
            foodType: foodType,
            targetTop: targetTop,
            targetBottom: targetBottom,
            glucoseType: glucoseType,
            glucose: glucose,
            units: units
        )
    }
}
