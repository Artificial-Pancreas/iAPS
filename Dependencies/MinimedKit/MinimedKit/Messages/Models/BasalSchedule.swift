//
//  BasalSchedule.swift
//  RileyLink
//
//  Created by Pete Schwamb on 5/6/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import Foundation

public struct BasalScheduleEntry: Equatable {
    public let index: Int
    public let timeOffset: TimeInterval
    public let rate: Double  // U/hour

    public init(index: Int, timeOffset: TimeInterval, rate: Double) {
        self.index = index
        self.timeOffset = timeOffset
        self.rate = rate
    }
}


public struct BasalSchedule: Equatable {
    public let entries: [BasalScheduleEntry]

    public init(entries: [BasalScheduleEntry]) {
        self.entries = entries
    }

    public func rateAt(offset: TimeInterval) -> Double {
        let (_, entry, _) = lookup(offset: offset)
        return entry.rate
    }

    // Only valid for fixed offset timezones
    public func currentRate(using calendar: Calendar, at date: Date = Date()) -> Double {
        let midnight = calendar.startOfDay(for: date)
        return rateAt(offset: date.timeIntervalSince(midnight))
    }

    // Returns index, entry, and time remaining
    func lookup(offset: TimeInterval) -> (Int, BasalScheduleEntry, TimeInterval) {
        guard offset >= 0 && offset < .hours(24) else {
            fatalError("Schedule offset out of bounds")
        }

        var last: TimeInterval = .hours(24)
        for (index, entry) in entries.reversed().enumerated() {
            if entry.timeOffset <= offset {
                return (entries.count - (index + 1), entry, last - entry.timeOffset)
            }
            last = entry.timeOffset
        }
        fatalError("Schedule incomplete")
    }
}

extension BasalSchedule {
    static let rawValueLength = 192
    public typealias RawValue = Data

    public init?(rawValue: RawValue) {
        var entries = [BasalScheduleEntry]()

        for tuple in sequence(first: (index: 0, offset: 0), next: { (index: $0.index + 1, $0.offset + 3) }) {
            let beginOfRange = tuple.offset
            let endOfRange = beginOfRange + 3

            guard endOfRange < rawValue.count else {
                break
            }

            if let entry = BasalScheduleEntry(
                index: tuple.index,
                rawValue: rawValue[beginOfRange..<endOfRange]
            ) {
                if let last = entries.last, last.timeOffset >= entry.timeOffset {
                    // Stop if the new timeOffset isn't greater than the last one
                    break
                }

                entries.append(entry)
            } else {
                // Stop if we can't decode the entry
                break
            }
        }

        guard entries.count > 0 else {
            return nil
        }

        self.init(entries: entries)
    }

    public var rawValue: RawValue {
        var buffer = Data(count: BasalSchedule.rawValueLength)
        var byteIndex = 0

        for rawEntry in entries.map({ $0.rawValue }) {
            buffer.replaceSubrange(byteIndex..<(byteIndex + rawEntry.count), with: rawEntry)
            byteIndex += rawEntry.count
        }

        // Send the special "empty" code to clear a schedule
        if entries.count == 0 {
            buffer[2] = 0x3f
        }

        return buffer
    }
}


private extension BasalScheduleEntry {
    static let rawValueLength = 3
    typealias RawValue = Data

    init?(index: Int, rawValue: RawValue) {
        guard rawValue.count == BasalScheduleEntry.rawValueLength else {
            return nil
        }

        let rawRate = rawValue[rawValue.startIndex..<rawValue.startIndex.advanced(by: 2)]
        let rate = Double(rawRate.to(UInt16.self)) / 40.0

        let offsetMinutes = Double(rawValue.last!) * 30
        let timeOffset = TimeInterval(minutes: offsetMinutes)

        // 0x3f *30*60 denotes a stop value
        guard timeOffset < .hours(24) else {
            return nil
        }

        self.init(index: index, timeOffset: timeOffset, rate: rate)
    }

    var rawValue: RawValue {
        var buffer = Data(count: type(of: self).rawValueLength)

        var rate = UInt16(clamping: Int(self.rate * 40))
        buffer.replaceSubrange(0..<2, with: Data(bytes: &rate, count: rate.bitWidth / 8))
        buffer[2] = UInt8(clamping: Int(timeOffset.minutes / 30))

        return buffer
    }
}
