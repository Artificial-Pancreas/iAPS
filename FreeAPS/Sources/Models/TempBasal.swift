import Foundation

struct TempBasal: JSON {
    let duration: Int
    let rate: Decimal
    let temp: PumpHistoryTempType
    let updatedAt: Date
}
