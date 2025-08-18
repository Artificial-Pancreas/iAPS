
import Foundation

struct AutosensInput: Codable {
    let glucose: [GlucoseEntry0]
    let pump_history: [PumpHistoryEvent]
    let basal_profile: [BasalProfileEntry]
    let profile: Profile
    let carbs: [CarbsEntry]
    let temp_targets: [TempTarget]
}

extension AutosensInput {
    enum CodingKeys: String, CodingKey {
        case glucose
        case pump_history
        case basal_profile
        case profile
        case carbs
        case temp_targets
    }
}
