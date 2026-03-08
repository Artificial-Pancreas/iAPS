import Foundation

struct CarbsEntry: JSON, Equatable, Hashable {
    let id: String?
    var createdAt: Date
    let actualDate: Date?
    var carbs: Decimal
    let fat: Decimal?
    let protein: Decimal?
    let note: String?
    let enteredBy: String?
    let isFPU: Bool?
    let kcal: Decimal?

    static let manual = "iAPS"
    static let watch = "iAPS Watch"
    static let remote = "Nightscout operator"
    static let appleHealth = "applehealth"
    static let shortcut = "iAPS shortcut"

    static func == (lhs: CarbsEntry, rhs: CarbsEntry) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }
}

extension CarbsEntry {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt = "created_at"
        case actualDate
        case carbs
        case fat
        case protein
        case note
        case enteredBy
        case isFPU
        case kcal
    }

    var kcalValue: Decimal {
        if let kcal {
            return kcal
        }
        let c = carbs
        let f = fat ?? 0
        let p = protein ?? 0
        // 4 kcal/g Carbs & Protein, 9 kcal/g Fat
        return c * 4 + f * 9 + p * 4
    }
}
