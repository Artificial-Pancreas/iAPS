import Foundation

struct LoopStats: JSON, Equatable {
    var createdAt: Date
    var loopEnd: Date?
    var loopDuration: Double?
    var loopStatus: String

    init(
        createdAt: Date,
        loopStatus: String
    ) {
        self.createdAt = createdAt
        self.loopStatus = loopStatus
    }
}

extension LoopStats {
    private enum CodingKeys: String, CodingKey {
        case createdAt
        case loopEnd
        case loopDuration
        case loopStatus
    }
}
