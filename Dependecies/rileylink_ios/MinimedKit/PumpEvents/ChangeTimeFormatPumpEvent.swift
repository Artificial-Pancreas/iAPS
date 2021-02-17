//
//  ChangeTimeFormatPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct ChangeTimeFormatPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let timeFormat: String

    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 7
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }

        timeFormat = d(1) == 1 ? "24hr" : "am_pm"
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "ChangeTimeFormat",
            "timeFormat": timeFormat,
        ]
    }
}
