import Foundation

struct BGTargets: JSON {
    let units: GlucoseUnits
    let userPreferredUnits: GlucoseUnits
    let targets: [BGTargetEntry]
}

extension BGTargets {
    static let initial = BGTargets(
        units: .mmolL,
        userPreferredUnits: .mmolL,
        targets: [BGTargetEntry(low: 5.5, high: 5.5, start: "00:00:00", offset: 0)]
    )
}

extension BGTargets {
    private enum CodingKeys: String, CodingKey {
        case units
        case userPreferredUnits = "user_preferred_units"
        case targets
    }
}

struct BGTargetEntry: JSON {
    let low: Decimal
    let high: Decimal
    let start: String
    let offset: Int
}
