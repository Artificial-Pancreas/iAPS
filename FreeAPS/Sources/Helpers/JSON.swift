import Foundation

protocol JSON: Codable {
    var rawJSON: String { get }
    init?(from: String)
}

extension JSON {
    var rawJSON: RawJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try! encoder.encode(self), encoding: .utf8)!
    }

    init?(from: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = from.data(using: .utf8),
              let object = try? decoder.decode(Self.self, from: data)
        else {
            return nil
        }
        self = object
    }
}

extension String: JSON {
    var rawJSON: String { self }
    init?(from: String) { self = from }
}

extension Double: JSON {}

extension Int: JSON {}

extension Bool: JSON {}

extension Date: JSON {
    var rawJSON: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }

    init?(from: String) {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions.insert(.withFractionalSeconds)
        let string = from.replacingOccurrences(of: "\"", with: "")
        if let date = dateFormatter.date(from: string) {
            self = date
        } else {
            return nil
        }
    }
}

typealias RawJSON = String

extension Array: JSON where Element: JSON {}
extension Dictionary: JSON where Key: JSON, Value: JSON {}
