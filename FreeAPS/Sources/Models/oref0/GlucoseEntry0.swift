import Foundation

struct GlucoseEntry0: Codable {
    let date: Int?
    let displayTime: String?
    let dateString: String?
    let sgv: Int?
    let glucose: Int?
    let type: String? // TODO: GlucoseType?
    let noise: Int?
}

extension GlucoseEntry0 {
    enum CodingKeys: String, CodingKey {
        case date
        case displayTime = "display_time"
        case dateString
        case sgv
        case glucose
        case type
        case noise
    }
}
