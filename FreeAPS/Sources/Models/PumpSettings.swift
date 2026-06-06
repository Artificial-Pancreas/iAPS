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
