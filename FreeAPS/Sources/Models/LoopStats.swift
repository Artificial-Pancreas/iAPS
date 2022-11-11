import Foundation

struct LoopStats: JSON, Equatable {
    var createdAt: Date
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
        case loopStatus
    }
}
