//
//  SensorCalGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct SensorCalGlucoseEvent: RelativeTimestampedGlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    private let calibrationType: String
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 2
        
        guard length <= availableData.count else {
            return nil
        }
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        rawData = availableData.subdata(in: 0..<length)
        switch d(1) {
        case 0x00:
            calibrationType = "meter_bg_now"
        case 0x01:
            calibrationType = "waiting"
        case 0x02:
            calibrationType = "cal_error"
        default:
            calibrationType = "unknown"
        }
        timestamp = relativeTimestamp
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "SensorCal",
            "calibrationType": calibrationType
        ]
    }
}


