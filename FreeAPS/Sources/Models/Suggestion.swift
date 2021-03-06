import Foundation

struct Suggestion: JSON {
    let reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    let eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Int?
    let iob: Decimal?
    let cob: Decimal?
    let predictions: Predictions?
}

struct Predictions: JSON {
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

protocol SuggestionObserver {
    func suggestionDidUpdate(_ suggestion: Suggestion)
}
