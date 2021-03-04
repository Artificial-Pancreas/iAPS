import Foundation

struct InsulinSensitivities: JSON {
    let units: GlucoseUnits
    let userPrefferedUnits: GlucoseUnits
    let sensitivities: [InsulinSensitivityEntry]
}

extension InsulinSensitivities {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPrefferedUnits = "user_preferred_units"
        case sensitivities
    }
}

struct InsulinSensitivityEntry: JSON {
    let sensitivity: Decimal
    let offset: Int
    let start: String
}
