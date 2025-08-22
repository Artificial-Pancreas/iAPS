import Foundation
import HealthKit

enum Formatters {
    static func percent(for number: Double) -> String {
        let formater = NumberFormatter()
        formater.numberStyle = .percent
        return formater.string(for: number)!
    }

    static func timeFor(minutes: Int) -> String {
        let formater = DateComponentsFormatter()
        formater.unitsStyle = .abbreviated
        formater.allowedUnits = [.hour, .minute]
        return formater.string(from: TimeInterval(minutes * 60))!
    }
}

extension Formatter {
    static let iso8601withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension ParseStrategy where Self == Date.ISO8601FormatStyle {
    static var iso8601withFractionalSeconds: Self { .init(includingFractionalSeconds: true) }
}

extension JSONDecoder.DateDecodingStrategy {
    static let iso8601withOptionalFractionalSeconds = custom {
        let string = try $0.singleValueContainer().decode(String.self)
        do {
            return try .init(string, strategy: .iso8601withFractionalSeconds)
        } catch {
            return try .init(string, strategy: .iso8601)
        }
    }
}

extension JSONEncoder.DateEncodingStrategy {
    static let customISO8601 = custom {
        var container = $1.singleValueContainer()
        try container.encode(Formatter.iso8601withFractionalSeconds.string(from: $0))
    }
}
