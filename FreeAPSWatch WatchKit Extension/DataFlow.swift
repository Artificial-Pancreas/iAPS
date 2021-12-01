import Foundation

struct WatchState: Codable {
    var glucose: String?
    var trend: String?
    var delta: String?
    var glucoseDate: Date?
    var lastLoopDate: Date?
    var bolusIncrement: Decimal?
    var maxCOB: Decimal?
    var maxBolus: Decimal?
    var carbsRequired: Decimal?
    var bolusRecommended: Decimal?
    var iob: Decimal?
    var cob: Decimal?
}
