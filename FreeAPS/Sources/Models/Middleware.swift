import Foundation

struct Middleware: JSON, Equatable {
    var string: String?
    let profile_data: [String?]
}

extension Middleware {
    private enum CodingKeys: String, CodingKey {
        case string
        case profile_data
    }
}
