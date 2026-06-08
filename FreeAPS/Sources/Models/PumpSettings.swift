import Foundation

struct PumpSettings: JSON, Equatable {
    let insulinActionCurve: Decimal
    let maxBolus: Decimal
    let maxBasal: Decimal
}

extension PumpSettings {
    private enum CodingKeys: String, CodingKey {
        case insulinActionCurve = "insulin_action_curve"
        case maxBolus
        case maxBasal
    }
}

extension PumpSettings {
    static let defaultValue = PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 4)
}
