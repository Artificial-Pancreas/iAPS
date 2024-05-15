import Foundation

struct Version: JSON, Decodable {
    var main: String
    var dev: String
}

extension Version {
    private enum CodingKeys: String, CodingKey {
        case main
        case dev
    }
}
