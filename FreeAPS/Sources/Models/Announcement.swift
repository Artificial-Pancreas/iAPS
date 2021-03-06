import Foundation

struct Announcement: JSON {
    let createdAt: Date
    let enteredBy: String
    let notes: String

    static let remote = "freeaps-x-remote"

    var action: AnnouncementAction? {
        let components = notes.replacingOccurrences(of: " ", with: "").split(separator: ":")
        guard components.count == 2 else {
            return nil
        }

        switch String(components[0]) {
        case "bolus":
            guard let amount = Decimal(from: String(components[1])) else { return nil }
            return .bolus(amount)
        case "pump":
            guard let action = PumpAction(rawValue: String(components[1])) else { return nil }
            return .pump(action)
        default: return nil
        }
    }
}

extension Announcement {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case enteredBy
        case notes
    }
}

enum AnnouncementAction {
    case bolus(Decimal)
    case pump(PumpAction)
}

enum PumpAction: String {
    case suspend
    case resume
}
