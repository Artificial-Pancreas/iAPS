import Foundation

enum WatchMessageType: String {
    case state
    case confirmation
    case command
}

struct WatchMessage {
    let type: WatchMessageType
    let carbs: Int?
    let tempTargetID: String?
    let bolusUnits: Decimal?
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
