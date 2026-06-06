import Foundation

struct Battery: JSON, Equatable, Sendable {
    let percent: Int?
    let voltage: Decimal?
    let string: BatteryState
    let display: Bool?
}

enum BatteryState: String, JSON {
    case normal
    case low
}
