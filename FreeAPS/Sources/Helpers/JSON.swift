import Foundation

extension Encodable {
    func rawJSON() -> String {
        String(data: try! JSONCoding.encoder.encode(self), encoding: .utf8)!
    }

    func toJSONObject() throws -> Any {
        let data = try JSONCoding.encoder.encode(self)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

@dynamicMemberLookup protocol JSON: Codable, Sendable {
    var rawJSON: String { get }
}

extension Decodable {
    static func decodeFrom(jsonData data: Data) throws -> Self {
        do {
            return try JSONCoding.decoder.decode(Self.self, from: data)
        } catch {
            if case let DecodingError.dataCorrupted(context) = error {
                warning(.service, "Cannot decode JSON", error: context.underlyingError)
            } else if case let DecodingError.keyNotFound(key, context) = error {
                warning(
                    .service,
                    "Key '\(key)' not found: " + context.debugDescription + "codingPath: " + context.codingPath.debugDescription
                )
            } else if case let DecodingError.valueNotFound(value, context) = error {
                warning(
                    .service,
                    "Value '\(value)' not found: " + context.debugDescription +
                        "codingPath: " + context.codingPath.debugDescription
                )
            } else if case let DecodingError.typeMismatch(type, context) = error {
                warning(
                    .service,
                    "Type '\(type)' mismatch:" + context.debugDescription +
                        "codingPath:" + context.codingPath.debugDescription
                )

            } else {
                warning(.service, "error: \(error)")
            }
            throw error
        }
    }

    static func decodeFrom(json string: String) throws -> Self {
        let data = Data(string.utf8)
        return try Self.decodeFrom(jsonData: data)
    }
}

extension JSON {
    var rawJSON: RawJSON {
        String(data: try! JSONCoding.encoder.encode(self), encoding: .utf8)!
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

typealias RawJSON = String

extension RawJSON {
    static let null = "null"
    static let empty = ""
}

extension Dictionary where Key == String {
    var rawJSON: RawJSON? {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: .prettyPrinted) else { return nil }
        return RawJSON(data: data, encoding: .utf8)
    }
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .customISO8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds
        return decoder
    }
}
