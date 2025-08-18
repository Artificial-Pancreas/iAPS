
import Foundation

struct AutotuneInput: Codable {
    let pump_history: [PumpHistoryEvent]
    let profile: Profile
    let glucose: [GlucoseEntry0]
    let pump_profile: Profile
    let carbs: [CarbsEntry]
    let categorize_uam_as_basal: Bool
    let tune_insulin_curve: Bool
    let previous_autotune_result: Profile
}

extension AutotuneInput {
    enum CodingKeys: String, CodingKey {
        case pump_history
        case profile
        case glucose
        case pump_profile
        case carbs
        case categorize_uam_as_basal
        case tune_insulin_curve
        case previous_autotune_result
    }
}
