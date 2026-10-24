import Foundation

struct CarbsEntry: JSON, Equatable, Hashable {
    let id: String?
    var createdAt: Date
    let actualDate: Date?
    var carbs: Decimal
    let fat: Decimal?
    let protein: Decimal?
    let fiber: Decimal?
    let note: String?
    let enteredBy: String?
    let isFPU: Bool?

    var micronutrient: [MicronutrientValue]?

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
        case fiber
        case note
        case enteredBy
        case isFPU
        case micronutrient
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        actualDate = try container.decodeIfPresent(Date.self, forKey: .actualDate)
        carbs = try container.decode(Decimal.self, forKey: .carbs)
        fat = try container.decodeIfPresent(Decimal.self, forKey: .fat)
        protein = try container.decodeIfPresent(Decimal.self, forKey: .protein)
        fiber = try container.decodeIfPresent(Decimal.self, forKey: .fiber)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        enteredBy = try container.decodeIfPresent(String.self, forKey: .enteredBy)
        isFPU = try container.decodeIfPresent(Bool.self, forKey: .isFPU)

        let wrapped = try container.decodeIfPresent(
            [SafeMicronutrientValue].self,
            forKey: .micronutrient
        ) ?? []

        micronutrient = wrapped.compactMap(\.value)
    }
}
