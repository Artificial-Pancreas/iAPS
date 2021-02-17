//
//  AlarmSensorPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct AlarmSensorPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 8
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 3)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "AlarmSensor",
        ]
    }

    public var description: String {
        return LocalizedString("AlarmSensor", comment: "The description of AlarmSensorPumpEvent")
    }
}
