import Foundation

struct MealInput: Codable {
    let pump_history: [PumpHistoryEvent]
    let profile: Profile
    let basal_profile: [BasalProfileEntry]
    let clock: Date
    let carbs: [CarbsEntry]
    let glucose: [GlucoseEntry0]
    let temporaryCarbs: CarbsEntry?
}

extension MealInput {
    enum CodingKeys: String, CodingKey {
        case pump_history
        case profile
        case basal_profile
        case clock
        case carbs
        case glucose
        case temporaryCarbs
    }
}
