import Foundation

struct Announcement: JSON {
    let createdAt: Date
    let enteredBy: String
    let notes: String

    static let remote = "remote"

    var action: AnnouncementAction? {
        let components = notes.replacingOccurrences(of: " ", with: "").split(separator: ":")
        guard components.count == 2 else {
            return nil
        }
        let command = String(components[0]).lowercased()
        let arguments = String(components[1]).lowercased()
        switch command {
        case "bolus":
            guard let amount = Decimal(from: arguments) else { return nil }
            return .bolus(amount)
        case "pump":
            guard let action = PumpAction(rawValue: arguments) else { return nil }
            return .pump(action)
        case "looping":
            guard let looping = Bool(from: arguments) else { return nil }
            return .looping(looping)
        case "tempbasal":
            let basalComponents = arguments.split(separator: ",")
            guard basalComponents.count == 2 else { return nil }
            let rateArg = String(basalComponents[0])
            let durationArg = String(basalComponents[1])
            guard let rate = Decimal(from: rateArg), let duration = Decimal(from: durationArg) else { return nil }
            return .tempbasal(rate: rate, duration: duration)
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
    case looping(Bool)
    case tempbasal(rate: Decimal, duration: Decimal)
}

enum PumpAction: String {
    case suspend
    case resume
}
