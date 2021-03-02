import Foundation

@dynamicMemberLookup protocol JSON: Codable {
    var rawJSON: String { get }
    init?(from: String)
}

private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

extension JSON {
    var rawJSON: RawJSON {
        String(data: try! encoder().encode(self), encoding: .utf8)!
    }

    init?(from: String) {
        guard let data = from.data(using: .utf8),
              let object = try? decoder().decode(Self.self, from: data)
        else {
            return nil
        }
        self = object
    }

    var dictionaryRepresentation: [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    subscript(dynamicMember string: String) -> Any? {
        dictionaryRepresentation?[string]
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

extension Dictionary where Key == String {
    var rawJSON: RawJSON? {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: .prettyPrinted) else { return nil }
        return RawJSON(data: data, encoding: .utf8)
    }
}

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
