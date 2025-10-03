import LoopKit

public struct BasalSchedule: RawRepresentable {
    public typealias RawValue = [String: Any]

    let entries: [BasalScheduleEntry]

    public init(entries: [LoopKit.RepeatingScheduleValue<Double>]) {
        self.entries = entries.map { BasalScheduleEntry(rate: $0.value, startTime: $0.startTime) }
    }

    public init?(rawValue: RawValue) {
        guard let entries = rawValue["entries"] as? [BasalScheduleEntry.RawValue] else {
            return nil
        }

        self.entries = entries.compactMap { BasalScheduleEntry(rawValue: $0) }
    }

    public var rawValue: RawValue {
        let rawValue: RawValue = [
            "entries": entries.map(\.rawValue)
        ]

        return rawValue
    }

    public func toData() -> Data {
        var output = Data([UInt8(entries.count)])

        entries.forEach { item in
            let rate = UInt32(round(item.rate / 0.05))
            let time = UInt32(item.startTime.minutes)

            if time > 0xFFF || rate > 0xFFF {
                preconditionFailure("Rate or time is too big: \(rate), \(time)")
            }

            let entries = UInt64(rate << 12 | time).toData(length: 3)
            output.append(entries)
        }

        return output
    }
}

public struct BasalScheduleEntry: RawRepresentable {
    public typealias RawValue = [String: Any]

    let rate: Double
    let startTime: TimeInterval

    public init(rate: Double, startTime: TimeInterval) {
        self.rate = rate
        self.startTime = startTime
    }

    public init?(rawValue: RawValue) {
        guard let rate = rawValue["rate"] as? Double, let startTime = rawValue["startTime"] as? Double else {
            return nil
        }

        self.rate = rate
        self.startTime = startTime
    }

    public var rawValue: RawValue {
        let rawValue: RawValue = [
            "rate": rate,
            "startTime": startTime
        ]

        return rawValue
    }
}
