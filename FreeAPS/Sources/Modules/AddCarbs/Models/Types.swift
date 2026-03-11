import Foundation

struct ImageSearchResult: Identifiable {
    let id: String
    let thumbnailURL: String?
    let fullURL: String
    let attribution: String?
}

enum FoodTags {
    static let favorites = "⭐️"
}
