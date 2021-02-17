//
//  BasalProfileStartPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct BasalProfileStartPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents

    public let scheduleEntry: BasalScheduleEntry

    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 10
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        
        let rate = Double(availableData[8..<10].to(UInt16.self)) / 40.0
        let offsetMinutes = Double(availableData[7]) * 30

        scheduleEntry = BasalScheduleEntry(
            index: Int(availableData[1]),
            timeOffset: TimeInterval(minutes: offsetMinutes),
            rate: rate
        )
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "BasalProfileStart",
            "offset": Int(scheduleEntry.timeOffset.milliseconds),
            "rate": scheduleEntry.rate,
            "profileIndex": scheduleEntry.index,
        ]
    }

    public var description: String {
        return String(format: LocalizedString("Basal Profile %1$@: %2$@ U/hour", comment: "The format string description of a BasalProfileStartPumpEvent. (1: The index of the profile)(2: The basal rate)"), scheduleEntry.index, scheduleEntry.rate)
    }
}
