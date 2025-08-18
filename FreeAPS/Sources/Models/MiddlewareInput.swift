
import Foundation

struct MiddlewareInput: Codable {
    let glucose: [GlucoseEntry0]
    let current_temp: TempBasal
    let iob: [IOBItem]
    let profile: Profile
    let autosens: Autosens?
    let meal: RecentCarbs
    let microbolus_allowed: Bool
    let reservoir: Double
    let clock: Date
}

extension MiddlewareInput {
    enum CodingKeys: String, CodingKey {
        case glucose
        case current_temp
        case iob
        case profile
        case autosens
        case meal
        case microbolus_allowed
        case reservoir
        case clock
    }
}
