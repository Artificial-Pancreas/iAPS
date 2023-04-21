//
//  SensorPacketGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/6/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct SensorPacketGlucoseEvent: RelativeTimestampedGlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    private let packetType: String
    
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
        case 0x02:
            packetType = "init"
        default:
            packetType = "unknown"
        }
        
        timestamp = relativeTimestamp
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "SensorPacket",
            "packetType": packetType
        ]
    }
}
