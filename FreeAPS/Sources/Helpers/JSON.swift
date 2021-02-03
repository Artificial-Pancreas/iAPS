import Foundation

protocol JSON: Codable {
    var string: String { get }
    init?(from: String)
}

extension JSON {
    var string: String {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }

    init?(from: String) {
        guard let data = from.data(using: .utf8),
              let object = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return nil
        }
        self = object
    }
}

extension String: JSON {
    var string: String { self }
    init?(from: String) { self = from }
}

extension Double: JSON {}

extension Int: JSON {}

extension Bool: JSON {}

extension Date: JSON {
    var string: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withColonSeparatorInTimeZone]
        return formatter.string(from: self)
    }

    init?(from: String) {
        let dateFormatter = ISO8601DateFormatter()
        let string = from.replacingOccurrences(of: "\"", with: "")
        if let date = dateFormatter.date(from: string) {
            self = date
        } else {
            return nil
        }
    }
}
