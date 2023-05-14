//
//  SensorDataHighGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/6/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct SensorDataHighGlucoseEvent: SensorValueGlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let sgv: Int
    public let timestamp: DateComponents
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 2
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        sgv = 400
        timestamp = relativeTimestamp
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "SensorDataHigh",
            "sgv": sgv
        ]
    }
}
