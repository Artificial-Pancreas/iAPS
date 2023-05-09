//
//  RestoreMystery54PumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 8/29/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct RestoreMystery54PumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 64
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "RestoreMystery54",
        ]
    }
}
