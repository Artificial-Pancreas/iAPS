import Foundation

struct TDD: JSON, Equatable {
    var TDD: Decimal
    var timestamp: Date
    let id: String

    init(
        TDD: Decimal,
        timestamp: Date,
        id: String
    ) {
        self.TDD = TDD
        self.timestamp = timestamp
        self.id = id
    }
}

extension TDD {
    private enum CodingKeys: String, CodingKey {
        case TDD
        case timestamp
        case id
    }
}
