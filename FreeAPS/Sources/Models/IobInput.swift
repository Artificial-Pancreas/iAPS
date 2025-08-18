import Foundation

struct IobInput: Codable {
    let pump_history: [PumpHistoryEvent]
    let profile: Profile
    let clock: Date
    let autosens: Autosens?
}

extension IobInput {
    enum CodingKeys: String, CodingKey {
        case pump_history
        case profile
        case clock
        case autosens
    }
}
