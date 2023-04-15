import Foundation

struct Oref2_variables: JSON, Equatable {
    var average_total_data: Decimal
    var weightedAverage: Decimal
    var past2hoursAverage: Decimal
    var date: Date
    var isEnabled: Bool
    var presetActive: Bool
    var overridePercentage: Decimal
    var useOverride: Bool
    var duration: Decimal
    var unlimited: Bool
    var hbt: Decimal

    init(
        average_total_data: Decimal,
        weightedAverage: Decimal,
        past2hoursAverage: Decimal,
        date: Date,
        isEnabled: Bool,
        presetActive: Bool,
        overridePercentage: Decimal,
        useOverride: Bool,
        duration: Decimal,
        unlimited: Bool,
        hbt: Decimal
    ) {
        self.average_total_data = average_total_data
        self.weightedAverage = weightedAverage
        self.past2hoursAverage = past2hoursAverage
        self.date = date
        self.isEnabled = isEnabled
        self.presetActive = presetActive
        self.overridePercentage = overridePercentage
        self.useOverride = useOverride
        self.duration = duration
        self.unlimited = unlimited
        self.hbt = hbt
    }
}

extension Oref2_variables {
    private enum CodingKeys: String, CodingKey {
        case average_total_data
        case weightedAverage
        case past2hoursAverage
        case date
        case isEnabled
        case presetActive
        case overridePercentage
        case useOverride
        case duration
        case unlimited
        case hbt
    }
}
