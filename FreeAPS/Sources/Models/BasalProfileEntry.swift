import Foundation
import LoopKit

struct BasalProfileEntry: JSON, Equatable {
    let start: String
    let minutes: Int
    let rate: Decimal
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
