import Foundation

struct Battery: JSON {
    let percent: Int?
    let voltage: Decimal?
    let string: BatteryState
}

enum BatteryState: String, JSON {
    case normal
    case low
}
