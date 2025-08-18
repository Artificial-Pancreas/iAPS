
import Foundation

struct AutoIsfInput: Codable {
    let glucose: [GlucoseEntry0]
    let iob: [IOBItem]
    let profile: Profile
    let autosens: Autosens?
    let pump_history: [PumpHistoryEvent]
    let clock: Date
}

extension AutoIsfInput {
    enum CodingKeys: String, CodingKey {
        case glucose
        case iob
        case profile
        case autosens
        case pump_history
        case clock
    }
}
