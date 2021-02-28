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

extension Decimal: JSON {}

extension Date: JSON {
    init?(from: String) {
        let dateFormatter = Formatter.iso8601withFractionalSeconds
        let string = from.replacingOccurrences(of: "\"", with: "")
        if let date = dateFormatter.date(from: string) {
            self = date
        } else {
            return nil
        }
    }
}

typealias RawJSON = String

extension RawJSON {
    static let null = "null"
}

extension Array: JSON where Element: JSON {}
extension Dictionary: JSON where Key: JSON, Value: JSON {}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .customISO8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601
        return decoder
    }
}
