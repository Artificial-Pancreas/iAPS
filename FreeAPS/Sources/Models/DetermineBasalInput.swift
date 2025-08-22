
import Foundation

struct DetermineBasalInput: Codable {
    let glucose: [GlucoseEntry0]
    let current_temp: TempBasal
    let iob: [IOBEntry]
    let profile: Profile
    let autosens: Autosens?
    let meal: RecentCarbs
    let microbolus_allowed: Bool
    let reservoir: Double
    let pump_history: [PumpHistoryEvent] // TODO: pumpHistory not used
    let clock: Date
}

extension DetermineBasalInput {
    enum CodingKeys: String, CodingKey {
        case glucose
        case current_temp
        case iob
        case profile
        case autosens
        case meal
        case microbolus_allowed
        case reservoir
        case pump_history
        case clock
    }
}
