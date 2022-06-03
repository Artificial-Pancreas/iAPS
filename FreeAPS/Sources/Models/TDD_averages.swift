import Foundation

struct TDD_averages: JSON, Equatable {
    var average_7days: Decimal
    var weightedAverage: Decimal
    var date: Date

    init(
        average_7days: Decimal,
        weightedAverage: Decimal,
        date: Date
    ) {
        self.average_7days = average_7days
        self.weightedAverage = weightedAverage
        self.date = date
    }
}

extension TDD_averages {
    private enum CodingKeys: String, CodingKey {
        case average_7days
        case weightedAverage
        case date
    }
}
