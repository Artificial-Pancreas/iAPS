import Foundation

struct ContactTrickState: Codable {
    var glucose: String?
    var trend: String?
    var delta: String?
    var glucoseDate: Date?
    var lastLoopDate: Date?
    var carbsRequired: Decimal?
    var bolusRecommended: Decimal?
    var iob: Decimal?
    var maxIOB: Decimal = 0.0
    var cob: Decimal?
    var tempTargets: [TempTargetContactPreset] = []
    var eventualBG: String?
    var eventualBGRaw: String?
    var profilesOrTempTargets: Bool?
    var useNewCalc: Bool?
    var isf: Decimal?
    var override: String?
}

struct TempTargetContactPreset: Codable, Identifiable {
    let name: String
    let id: String
    let description: String
    let until: Date?
}
