import Foundation

struct PumpHystoryEvent: JSON {
    let id: UUID
    let type: PumpHystoryEventType
    let timestamp: Date
    let amount: Decimal?
    let duration: Int?
    let durationMin: Int?
    let rate: Decimal?
    let temp: PumpHystoryTempType?
}

enum PumpHystoryEventType: String, JSON {
    case bolus = "Bolus"
    case mealBulus = "Meal Bolus"
    case correctionBolus = "Correction Bolus"
    case snackBolus = "Snack Bolus"
    case bolusWizard = "Bolus Wizard"
    case tempBasal = "TempBasal"
    case tempBasalDuration = "TempBasalDuration"
}

enum PumpHystoryTempType: String, JSON {
    case absolute
    case percent
}

extension PumpHystoryEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case type = "_type"
        case timestamp
        case amount
        case duration
        case durationMin = "duration (min)"
        case rate
        case temp
    }
}
