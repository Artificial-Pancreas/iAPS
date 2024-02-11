import Foundation

struct Announcement: JSON, Equatable, Hashable {
    let createdAt: Date
    let enteredBy: String
    let notes: String

    static let remote = "remote"

    var action: AnnouncementAction? {
        let components = notes.replacingOccurrences(of: " ", with: "").split(separator: ":")
        guard components.count == 2 else {
            return nil
        }
        var name = String(notes.split(separator: ":")[1])
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
        case "meal":
            let mealComponents = arguments.split(separator: ",")
            guard mealComponents.count == 3 else { return nil }
            let carbsArg = String(mealComponents[0])
            let fatArg = String(mealComponents[1])
            let proteinArg = String(mealComponents[2])
            guard let carbs = Decimal(from: carbsArg), let fat = Decimal(from: fatArg),
                  let protein = Decimal(from: proteinArg) else { return nil }
            return .meal(carbs: carbs, fat: fat, protein: protein)
        case "override":
            guard !name.isEmpty else { return nil }
            if name.prefix(1) == " " { name = String(name.dropFirst()) }
            return .override(name: name)
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
    case meal(carbs: Decimal, fat: Decimal, protein: Decimal)
    case override(name: String)
}

enum PumpAction: String {
    case suspend
    case resume
}
