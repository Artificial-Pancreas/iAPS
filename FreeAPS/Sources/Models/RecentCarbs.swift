import Foundation

struct RecentCarbs: Codable, Sendable {
    var carbs: Double
    var nsCarbs: Double
    var bwCarbs: Double
    var journalCarbs: Double
    var mealCOB: Double
    var currentDeviation: Double
    var maxDeviation: Double
    var minDeviation: Double
    var slopeFromMaxDeviation: Double
    var slopeFromMinDeviation: Double
    var allDeviations: [Double]
    var lastCarbTime: Double? // Option<f64> -> Double?
    var bwFound: Bool
}

extension RecentCarbs {
    private enum CodingKeys: String, CodingKey {
        case carbs
        case nsCarbs
        case bwCarbs
        case journalCarbs
        case mealCOB
        case currentDeviation
        case maxDeviation
        case minDeviation
        case slopeFromMaxDeviation
        case slopeFromMinDeviation
        case allDeviations
        case lastCarbTime
        case bwFound
    }
}
