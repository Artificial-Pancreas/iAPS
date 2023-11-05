import Foundation

struct CarbsEntry: JSON, Equatable, Hashable {
    let collectionID: String?
    let createdAt: Date
    let carbs: Decimal
    let fat: Decimal?
    let protein: Decimal?
    let note: String?
    let enteredBy: String?
    let isFPU: Bool?
    let fpuID: String?

    static let manual = "iAPS"
    static let appleHealth = "applehealth"

    static func == (lhs: CarbsEntry, rhs: CarbsEntry) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }
}

extension CarbsEntry {
    private enum CodingKeys: String, CodingKey {
        case collectionID = "_id"
        case createdAt = "created_at"
        case carbs
        case fat
        case protein
        case note
        case enteredBy
        case isFPU
        case fpuID
    }
}
