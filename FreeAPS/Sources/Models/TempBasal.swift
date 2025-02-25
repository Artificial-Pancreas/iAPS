import Foundation

struct TempBasal: JSON {
    let duration: Int
    var rate: Decimal
    let temp: TempType
    let timestamp: Date
}
