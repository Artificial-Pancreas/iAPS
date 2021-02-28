import Foundation

struct CarbHystoryEntry: JSON {
    let date: Date
    let carbs: Int
    let enteredBy: String?
}

extension CarbHystoryEntry {
    private enum CodingKeys: String, CodingKey {
        case date = "created_at"
        case carbs
        case enteredBy
    }
}
