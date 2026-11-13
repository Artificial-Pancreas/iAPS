import Foundation
import LoopKit

struct BasalProfileEntry: JSON, Equatable {
    let start: String
    let minutes: Int
    let rate: Decimal
}

extension [BasalProfileEntry] {
    static let initial: [BasalProfileEntry] = [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]

    /// The profile's rate at `date`: the last entry starting at or before that time of day.
    /// A profile that does not start at midnight wraps: before its first entry the last one applies. Nil for an empty profile.
    func scheduledRate(at date: Date, calendar: Calendar = .current) -> Decimal? {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        let entries = sorted { $0.minutes < $1.minutes }
        return (entries.last { $0.minutes <= minutes } ?? entries.last)?.rate
    }
}

extension BasalProfileEntry {
    private enum CodingKeys: String, CodingKey {
        case start
        case minutes
        case rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(String.self, forKey: .start)
        let minutes = try container.decode(Int.self, forKey: .minutes)
        let rate = try Decimal(floatLiteral: container.decode(Double.self, forKey: .rate))

        self = BasalProfileEntry(start: start, minutes: minutes, rate: rate)
    }
}

extension BasalProfileEntry {
    /// Builds an entry from a LoopKit schedule value (`startTime` = seconds since midnight).
    init(startTime: TimeInterval, rate: Double) {
        let seconds = Int(startTime)
        self.init(
            start: String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60),
            minutes: seconds / 60,
            rate: Decimal(rate)
        )
    }

    func toLoopKit(concentration: Double) -> RepeatingScheduleValue<Double> {
        RepeatingScheduleValue(startTime: TimeInterval(minutes * 60), value: Double(rate) / concentration)
    }
}
