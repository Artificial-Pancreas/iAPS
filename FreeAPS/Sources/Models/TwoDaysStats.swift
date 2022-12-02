import Foundation

struct TwoDaysStats: JSON, Equatable {
    var createdAt: Date
    var past2daysAverage: Decimal

    init(
        createdAt: Date,
        past2daysAverage: Decimal
    ) {
        self.createdAt = createdAt
        self.past2daysAverage = past2daysAverage
    }
}

extension TwoDaysStats {
    private enum CodingKeys: String, CodingKey {
        case createdAt
        case past2daysAverage
    }
}
