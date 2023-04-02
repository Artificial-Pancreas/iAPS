//
//  BasalSchedule+LoopKit.swift
//  OmniKit
//
//  Created by Pete Schwamb on 9/25/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit

extension BasalSchedule {
    public init(repeatingScheduleValues: [LoopKit.RepeatingScheduleValue<Double>]) {
        self.init(entries: repeatingScheduleValues.map { BasalScheduleEntry(rate: $0.value, startTime: $0.startTime) })
    }
}
