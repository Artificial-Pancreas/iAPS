//
//  TimestampedPumpEvent.swift
//  RileyLink
//
//  Created by Nate Racklyeft on 6/15/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation


// Boxes a TimestampedPumpEvent, storing its reconciled date components
public struct TimestampedHistoryEvent {
    public let pumpEvent: PumpEvent
    public let date: Date

    public init(pumpEvent: PumpEvent, date: Date) {
        self.pumpEvent = pumpEvent
        self.date = date
    }
}


extension TimestampedHistoryEvent: DictionaryRepresentable {
    public var dictionaryRepresentation: [String : Any] {
        var dict = pumpEvent.dictionaryRepresentation

        dict["timestamp"] = ISO8601DateFormatter.defaultFormatter().string(from: date)

        return dict
    }
}
