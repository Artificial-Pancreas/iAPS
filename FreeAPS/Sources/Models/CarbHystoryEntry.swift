import Foundation

struct CarbHystoryEntry: JSON {
    let createdAt: Date
    let carbs: Int
    let enteredBy: String?
}

extension CarbHystoryEntry {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case carbs
        case enteredBy
    }
}
