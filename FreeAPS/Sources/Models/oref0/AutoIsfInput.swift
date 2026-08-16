import Foundation

struct AutoIsfInput: Codable {
    let glucose: [GlucoseEntry0]
    /// Readings at the CGM's native rate, when the user asked Auto ISF to use them.
    let glucose_fast: [GlucoseEntry0]?
    let iob: [IOBEntry]
    let profile: Profile
    let autosens: Autosens?
    let pump_history: [PumpHistoryEvent]
    let clock: Date
}

extension AutoIsfInput {
    enum CodingKeys: String, CodingKey {
        case glucose
        case glucose_fast
        case iob
        case profile
        case autosens
        case pump_history
        case clock
    }
}
