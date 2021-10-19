//
//  SensorDataLowEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/5/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct SensorDataLowGlucoseEvent: SensorValueGlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let sgv: Int
    public let timestamp: DateComponents
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 1
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        sgv = 40
        timestamp = relativeTimestamp
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "SensorDataLow",
            "sgv": sgv
        ]
    }
}
