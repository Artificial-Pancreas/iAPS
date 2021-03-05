import Foundation

struct TempTarget: JSON {
    var id = UUID().uuidString
    let createdAt: Date
    let targetTop: Decimal
    let targetBottom: Decimal
    let duration: Decimal
    let enteredBy: String?

    static let manual = "freeaps-x://manual"
}

extension TempTarget {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt = "created_at"
        case targetTop
        case targetBottom
        case duration
        case enteredBy
    }
}
