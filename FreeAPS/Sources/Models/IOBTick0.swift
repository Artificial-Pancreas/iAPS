import Foundation

// "0" for oref0
struct IOBTick0: JSON, Equatable, Comparable {
    let time: Date
    let iob: Decimal
    let activity: Decimal

    static func < (lhs: IOBTick0, rhs: IOBTick0) -> Bool {
        rhs.time < lhs.time
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601WithFractionalSeconds = custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: dateStr) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateStr)"
            )
        }
        return date
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension IOBTick0 {
    static func parseArrayFromJSON(from iob: RawJSON) -> [IOBTick0]? {
        guard let iobData = iob.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds

        do {
            let iobEntries = try decoder.decode([IOBTick0].self, from: iobData)
            return iobEntries
        } catch {
            print("Error decoding IOBTick0 array: \(error)\n\(iob)")
            return nil
        }
    }
}
