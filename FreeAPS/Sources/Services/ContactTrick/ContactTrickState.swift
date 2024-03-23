import Foundation

struct ContactTrickState: Codable {
    var glucose: String?
    var trend: String?
    var delta: String?
    var glucoseDate: Date?
    var lastLoopDate: Date?
    var iob: Decimal?
    var cob: Decimal?
    var eventualBG: String?
    var maxIOB: Decimal = 10.0
    var maxCOB: Decimal = 120.0
}
