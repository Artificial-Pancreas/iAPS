import Foundation

extension Encodable {
    func rawJSON() -> String {
        String(data: try! JSONCoding.encoder.encode(self), encoding: .utf8)!
    }

    func toJSONObject() throws -> Any {
        let data = try JSONEncoder().encode(self)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    func asJavaScriptString() -> String {
        "\"" +
            rawJSON()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") +
            "\""
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

//    init?(from: String) {
//        guard let data = from.data(using: .utf8) else {
//            return nil
//        }
//
//        do {
//            let object = try JSONCoding.decoder.decode(Self.self, from: data)
//            self = object
//        } catch let DecodingError.dataCorrupted(context) {
//            warning(.service, "Cannot decode JSON", error: context.underlyingError)
//            return nil
//        } catch let DecodingError.keyNotFound(key, context) {
//            warning(
//                .service,
//                "Key '\(key)' not found: " + context.debugDescription + "codingPath: " + context.codingPath.debugDescription
//            )
//            return nil
//        } catch let DecodingError.valueNotFound(value, context) {
//            warning(
//                .service,
//                "Value '\(value)' not found: " + context.debugDescription +
//                    "codingPath: " + context.codingPath.debugDescription
//            )
//            return nil
//        } catch let DecodingError.typeMismatch(type, context) {
//            warning(
//                .service,
//                "Type '\(type)' mismatch:" + context.debugDescription +
//                    "codingPath:" + context.codingPath.debugDescription
//            )
//            return nil
//        } catch {
//            warning(.service, "error: \(error)")
//            return nil
//        }
//    }

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

// extension String: JSON {
//    var rawJSON: String { self }
//    init?(from: String) { self = from }
// }
//
// extension Double: JSON {}
//
// extension Int: JSON {}
//
// extension Bool: JSON {}
//
// extension Decimal: JSON {}

// extension Date: JSON {
//    init?(from: String) {
//        let dateFormatter = Formatter.iso8601withFractionalSeconds
//        let string = from.replacingOccurrences(of: "\"", with: "")
//        if let date = dateFormatter.date(from: string) {
//            self = date
//        } else {
//            return nil
//        }
//    }
// }

typealias RawJSON = String

extension RawJSON {
    static let null = "null"
    static let empty = ""
}

// extension Array: JSON where Element: JSON {}
// extension Dictionary: JSON where Key: JSON, Value: JSON {}

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
        decoder.dateDecodingStrategy = .customISO8601
        return decoder
    }
}
