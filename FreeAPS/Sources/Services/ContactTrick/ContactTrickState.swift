import Foundation

struct ContactTrickState: Codable {
    var glucose: String?
    var trend: String?
    var delta: String?
    var glucoseDate: Date?
    var glucoseDateInterval: UInt64?
    var lastLoopDate: Date?
    var lastLoopDateInterval: UInt64?
    var bolusIncrement: Decimal?
    var maxCOB: Decimal?
    var maxBolus: Decimal?
    var carbsRequired: Decimal?
    var bolusRecommended: Decimal?
    var iob: Decimal?
    var cob: Decimal?
    var tempTargets: [TempTargetContactPreset] = []
    var overrides: [OverrideContactPresets_] = []
    var bolusAfterCarbs: Bool?
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

struct OverrideContactPresets_: Codable, Identifiable {
    let name: String
    let id: String
    let until: Date?
    let description: String
}
