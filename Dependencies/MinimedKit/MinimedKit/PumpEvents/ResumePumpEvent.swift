//
//  ResumePumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct ResumePumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let wasRemotelyTriggered: Bool
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 7
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        
        wasRemotelyTriggered = availableData[5] & 0b01000000 != 0
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "Resume",
            "wasRemotelyTriggered": wasRemotelyTriggered,
        ]
    }
}
