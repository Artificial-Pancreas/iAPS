//
//  PumpOpsSession.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit


extension PumpOpsSession {
    public func getBasalRateSchedule(for profile: BasalProfile) throws -> BasalRateSchedule? {
        let basalSchedule = try getBasalSchedule(for: profile)

        return BasalRateSchedule(dailyItems: basalSchedule?.entries.map { $0.repeatingScheduleValue } ?? [], timeZone: pump.timeZone)
    }
}


extension BasalSchedule {
    public init(repeatingScheduleValues: [LoopKit.RepeatingScheduleValue<Double>]) {
        self.init(entries: repeatingScheduleValues.enumerated().map({ (index, value) -> BasalScheduleEntry in
            return BasalScheduleEntry(index: index, repeatingScheduleValue: value)
        }))
    }
}


extension MinimedKit.BasalScheduleEntry {
    init(index: Int, repeatingScheduleValue: LoopKit.RepeatingScheduleValue<Double>) {
        self.init(index: index, timeOffset: repeatingScheduleValue.startTime, rate: repeatingScheduleValue.value)
    }

    var repeatingScheduleValue: LoopKit.RepeatingScheduleValue<Double> {
        return RepeatingScheduleValue(startTime: timeOffset, value: rate)
    }
}
