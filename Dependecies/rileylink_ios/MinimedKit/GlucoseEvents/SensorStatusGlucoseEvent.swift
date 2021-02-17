//
//  SensorStatusGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/16/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct SensorStatusGlucoseEvent: GlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    private let statusType: String
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 5
        
        guard length <= availableData.count else {
            return nil
        }
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        rawData = availableData.subdata(in: 0..<length)
        timestamp = DateComponents(glucoseEventBytes: availableData.subdata(in: 1..<5))
        
        switch (d(3) >> 5 & 0b00000011) {
        case 0x00:
            statusType = "off"
        case 0x01:
            statusType = "on"
        case 0x02:
            statusType = "lost"
        default:
            statusType = "unknown"
        }
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "SensorStatus",
            "statusType": statusType
        ]
    }
}

