import Foundation

struct Suggestion: JSON, Equatable {
    var reason: String
    var units: Decimal?
    let insulinReq: Decimal?
    let eventualBG: Int?
    let sensitivityRatio: Decimal?
    var rate: Decimal?
    var duration: Int?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    var deliverAt: Date?
    let carbsReq: Decimal?
    var temp: TempType?
    let bg: Decimal?
    let reservoir: Decimal?
    var timestamp: Date?
    var recieved: Bool?
    var targetBG: Decimal?
    var error: String?
    var bgi: Decimal?
    var deviation: Decimal?
    var isf: Decimal?
    var cr: Decimal?
    // added by iAPS after oref0 returns
    var iaps: SuggestionExtraFields?
}

struct SuggestionExtraFields: JSON, Equatable {
    let aisfReasons: String?
    let maxSafeBasal: Decimal?
    let units: GlucoseUnits?
    let overrideActive: Bool
    let totalDailyDose: Decimal?
    let isf: Decimal?
    let cr: Decimal?
    let minPredBG: Decimal?
}

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
}

extension Suggestion {
    private enum CodingKeys: String, CodingKey {
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case recieved
        case targetBG = "target_bg"
        case error
        case bgi = "BGI"
        case deviation
        case isf = "ISF"
        case cr = "CR"
        case iaps
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }
}

extension Suggestion {
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
