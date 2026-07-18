import Foundation

struct InsulinSensitivities: JSON {
    let units: GlucoseUnits
    let userPreferredUnits: GlucoseUnits
    let sensitivities: [InsulinSensitivityEntry]
}

extension InsulinSensitivities {
    static let initial = InsulinSensitivities(
        units: .mmolL,
        userPreferredUnits: .mmolL,
        sensitivities: [InsulinSensitivityEntry(sensitivity: 3.0, offset: 0, start: "00:00:00")]
    )
}

extension InsulinSensitivities {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case sensitivities
    }
}

struct InsulinSensitivityEntry: JSON {
    let sensitivity: Decimal
    let offset: Int
    let start: String
}

extension InsulinSensitivityEntry {
    private enum CodingKeys: String, CodingKey {
        case sensitivity
        case offset
        case start
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sensitivity = try container.decode(Decimal.self, forKey: .sensitivity)
        let start = try container.decode(String.self, forKey: .start)
        let offset = try container.decode(Int.self, forKey: .offset)

        self = InsulinSensitivityEntry(sensitivity: sensitivity, offset: offset, start: start)
    }
}
