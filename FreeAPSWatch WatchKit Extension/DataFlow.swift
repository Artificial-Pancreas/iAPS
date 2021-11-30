import Foundation

enum WatchCommandKey: String {
    case command
}

enum WatchCommand: String {
    case stateRequest
    case carbs
}

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

struct WatchCommandConfitmation: Codable {
    let confirmed: Bool
    let reason: String?
}
