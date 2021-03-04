import Foundation

struct Suggestion: JSON {
    let reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    let eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Int?
}
