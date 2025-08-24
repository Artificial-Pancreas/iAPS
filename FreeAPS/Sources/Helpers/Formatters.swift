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

@available(iOS 15, *) enum ISO8601Parsing {
    static let withFrac = Date.ISO8601FormatStyle(timeZone: .gmt)
        .year()
        .month()
        .day()
        .timeZone(separator: .omitted)
        .time(includingFractionalSeconds: true)

    static let noFrac = Date.ISO8601FormatStyle(timeZone: .gmt)
        .year()
        .month()
        .day()
        .timeZone(separator: .omitted)
        .time(includingFractionalSeconds: false)

    static func parse(_ s: String) -> Date? {
        (try? withFrac.parse(s)) ?? (try? noFrac.parse(s))
    }

    static func format(_ d: Date) -> String {
        let ms = Int(d.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) * 1000)
        if ms == 0 {
            return d.formatted(noFrac)
        } else {
            return d.formatted(withFrac)
        }
    }
}

extension ParseStrategy where Self == Date.ISO8601FormatStyle {
    static var iso8601withFractionalSeconds: Self { .init(includingFractionalSeconds: true) }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601withOptionalFractionalSeconds: Self {
        .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let d = ISO8601Parsing.parse(s) { return d }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ISO8601 date: \(s)"
            ))
        }
    }
}

extension JSONEncoder.DateEncodingStrategy {
    static var iso8601withOptionalFractionalSeconds: Self {
        .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ISO8601Parsing.format(date))
        }
    }
}
