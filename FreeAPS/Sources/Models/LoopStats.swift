import Foundation

struct LoopStats: JSON, Equatable {
    var start: Date
    var end: Date?
    var duration: Double?
    var loopStatus: String

    init(
        start: Date,
        loopStatus: String
    ) {
        self.start = start
        self.loopStatus = loopStatus
    }
}

extension LoopStats {
    private enum CodingKeys: String, CodingKey {
        case start
        case end
        case duration
        case loopStatus
    }
}
