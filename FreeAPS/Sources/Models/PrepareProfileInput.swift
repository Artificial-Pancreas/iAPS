
import Foundation

struct PrepareProfileInput: Codable {
    let preferences: Preferences
    let pump_settings: PumpSettings
    let bg_targets: BGTargets
    let basal_profile: [BasalProfileEntry]
    let isf: InsulinSensitivities
    let carb_ratio: CarbRatios
    let temp_targets: [TempTarget]
    let model: String
    let autotune: Autotune?
    let freeaps: FreeAPSSettings
    let dynamic_variables: DynamicVariables
    let settings: FreeAPSSettings
    let clock: Date
}

extension PrepareProfileInput {
    enum CodingKeys: String, CodingKey {
        case preferences
        case pump_settings
        case bg_targets
        case basal_profile
        case isf
        case carb_ratio
        case temp_targets
        case model
        case autotune
        case freeaps
        case dynamic_variables
        case settings
        case clock
    }
}
