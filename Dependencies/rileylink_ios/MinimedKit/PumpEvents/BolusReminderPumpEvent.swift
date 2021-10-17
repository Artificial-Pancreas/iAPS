//
//  Mystery69PumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 9/23/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct BolusReminderPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        let length: Int
        if pumpModel.larger {
            length = 9
        } else {
            length = 7 // This may not actually occur, as I don't think x22 and earlier pumps have missed bolus reminders.
        }
        
        guard length <= availableData.count else {
            return nil
        }
        
        let rawData = availableData.subdata(in: 0..<length)
        
        let timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        
        self.init(length: length, rawData: rawData, timestamp: timestamp)
    }
    
    public init(length: Int, rawData: Data, timestamp: DateComponents) {
        self.length = length
        self.rawData = rawData
        self.timestamp = timestamp
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "BolusReminder",
        ]
    }
}
