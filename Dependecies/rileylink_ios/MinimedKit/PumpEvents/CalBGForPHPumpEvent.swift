//
//  CalBGForPHPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct CalBGForPHPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let amount: Int
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 7
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        amount = ((d(4) & 0b10000000) << 2) + ((d(6) & 0b10000000) << 1) + d(1)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "CalBGForPH",
            "amount": amount,
        ]
    }
}
