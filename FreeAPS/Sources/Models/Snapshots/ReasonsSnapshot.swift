import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Reasons entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct ReasonsSnapshot: Sendable {
    let date: Date?
    let cob: Decimal?
    let cr: Decimal?
    let eventualBG: Decimal?
    let glucose: Decimal?
    let insulinReq: Decimal?
    let iob: Decimal?
    let isf: Decimal?
    let minPredBG: Decimal?
    let mmol: Bool
    let override: Bool
    let rate: Decimal?
    let ratio: Decimal?
    let reasons: String?
    let smb: Decimal?
    let target: Decimal?
    let tdd: Decimal?
}

extension ReasonsSnapshot {
    static func create(from record: Reasons) -> ReasonsSnapshot {
        ReasonsSnapshot(
            date: record.date,
            cob: record.cob?.decimalValue,
            cr: record.cr?.decimalValue,
            eventualBG: record.eventualBG?.decimalValue,
            glucose: record.glucose?.decimalValue,
            insulinReq: record.insulinReq?.decimalValue,
            iob: record.iob?.decimalValue,
            isf: record.isf?.decimalValue,
            minPredBG: record.minPredBG?.decimalValue,
            mmol: record.mmol,
            override: record.override,
            rate: record.rate?.decimalValue,
            ratio: record.ratio?.decimalValue,
            reasons: record.reasons,
            smb: record.smb?.decimalValue,
            target: record.target?.decimalValue,
            tdd: record.tdd?.decimalValue
        )
    }
}
