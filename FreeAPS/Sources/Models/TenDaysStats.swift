import Foundation

struct TenDaysStats: JSON, Equatable {
    var createdAt: Date
    var past10daysAverage: Decimal

    init(
        createdAt: Date,
        past10daysAverage: Decimal
    ) {
        self.createdAt = createdAt
        self.past10daysAverage = past10daysAverage
    }
}

extension TenDaysStats {
    private enum CodingKeys: String, CodingKey {
        case createdAt
        case past10daysAverage
    }
}
