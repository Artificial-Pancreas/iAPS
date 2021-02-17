//
//  ChangeTempBasalTypePumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/20/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct ChangeTempBasalTypePumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let basalType: String
    public let timestamp: DateComponents
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 7
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        basalType = d(1) == 1 ? "percent" : "absolute"
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "TempBasal",
            "temp": basalType,
        ]
    }
}
