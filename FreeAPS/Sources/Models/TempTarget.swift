import Foundation

struct TempTarget: JSON {
    let id: String
    let createdAt: Date
    let targetTop: Int
    let targetBottom: Int
    let duration: Int
}

extension TempTarget {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case createdAt = "created_at"
        case targetTop
        case targetBottom
        case duration
    }
}
