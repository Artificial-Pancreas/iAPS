import Foundation

typealias AutotunePrepared = RawJSONString

struct Autotune: JSON, Equatable {
    let createdAt: Date?
    let basalProfile: [BasalProfileEntry]
    let sensitivity: Decimal
    let carbRatio: Decimal

    static func from(profile: Profile) -> Autotune {
        Autotune(
            createdAt: nil,
            basalProfile: profile.basalProfile,
            sensitivity: Decimal(profile.sens),
            carbRatio: Decimal(profile.carbRatio),
        )
    }
}

extension Autotune {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case basalProfile = "basalprofile"
        case sensitivity = "sens"
        case carbRatio = "carb_ratio"
    }
}
