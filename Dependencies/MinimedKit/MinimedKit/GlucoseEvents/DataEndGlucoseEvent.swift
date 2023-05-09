//
//  DataEndGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/9/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct DataEndGlucoseEvent: GlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 1
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        timestamp = relativeTimestamp
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "Data End",
        ]
    }
}

