import Foundation

struct CarbsEntry: JSON, Equatable {
    let createdAt: Date
    let carbs: Decimal
    let enteredBy: String?

    static let manual = "freeaps-x"
}

extension CarbsEntry {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case carbs
        case enteredBy
    }
}
