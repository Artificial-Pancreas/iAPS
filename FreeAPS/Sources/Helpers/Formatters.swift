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

extension Date.ISO8601FormatStyle {
    static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

// Date(string, strategy: .iso8601WithFractionalSeconds)
extension ParseStrategy where Self == Date.ISO8601FormatStyle {
    static var iso8601WithFractionalSeconds: Self { .withFractionalSeconds }
}

// date.formatted(.iso8601WithFractionalSeconds)
extension FormatStyle where Self == Date.ISO8601FormatStyle {
    static var iso8601WithFractionalSeconds: Self { .withFractionalSeconds }
}

extension JSONDecoder.DateDecodingStrategy {
    static let customISO8601 = custom {
        let container = try $0.singleValueContainer()
        let string = try container.decode(String.self)
        if let date = (try? Date(string, strategy: .iso8601WithFractionalSeconds)) ?? (try? Date(string, strategy: .iso8601)) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
    }
}

extension JSONEncoder.DateEncodingStrategy {
    static let customISO8601 = custom {
        var container = $1.singleValueContainer()
        try container.encode($0.formatted(.iso8601WithFractionalSeconds))
    }
}
