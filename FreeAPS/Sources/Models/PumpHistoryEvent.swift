import Foundation

struct PumpHistoryEvent: JSON {
    let id: String
    let type: PumpHistoryEventType
    let timestamp: Date
    let amount: Decimal?
    let duration: Int?
    let durationMin: Int?
    let rate: Decimal?
    let temp: PumpHistoryTempType?
    let carbInput: Int?
}

enum PumpHistoryEventType: String, JSON {
    case bolus = "Bolus"
    case mealBulus = "Meal Bolus"
    case correctionBolus = "Correction Bolus"
    case snackBolus = "Snack Bolus"
    case bolusWizard = "BolusWizard"
    case tempBasal = "TempBasal"
    case tempBasalDuration = "TempBasalDuration"
    case pumpSuspend = "PumpSuspend"
    case pumpResume = "PumpResume"
    case rewind = "Rewind"
    case prime = "Prime"
}

enum PumpHistoryTempType: String, JSON {
    case absolute
    case percent
}

extension PumpHistoryEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case type = "_type"
        case timestamp
        case amount
        case duration
        case durationMin = "duration (min)"
        case rate
        case temp
        case carbInput = "carb_input"
    }
}
