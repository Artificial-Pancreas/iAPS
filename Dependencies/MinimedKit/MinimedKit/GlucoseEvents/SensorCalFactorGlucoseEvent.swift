//
//  SensorCalFactorGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct SensorCalFactorGlucoseEvent: GlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let factor: Float
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 7
        
        guard length <= availableData.count else {
            return nil
        }
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        rawData = availableData.subdata(in: 0..<length)
        timestamp = DateComponents(glucoseEventBytes: availableData.subdata(in: 1..<5))
        factor = Float(UInt16(d(5) << 8 | d(6))) / Float(1000.0)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "SensorCalFactor",
            "factor": factor
        ]
    }
}
