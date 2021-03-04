import Foundation

struct CarbsEntry: JSON {
    let createdAt: Date
    let carbs: Int
    let enteredBy: String?
}

extension CarbsEntry {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case carbs
        case enteredBy
    }
}
