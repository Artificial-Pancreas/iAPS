//
//  BatteryChangeGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct BatteryChangeGlucoseEvent : GlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 5
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        timestamp = DateComponents(glucoseEventBytes: availableData.subdata(in: 1..<5))
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "BatteryChange",
        ]
    }
}
