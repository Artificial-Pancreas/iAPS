//
//  BGReceived.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct BGReceivedPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let amount: Int
    public let meter: String
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 10
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        amount = (d(1) << 3) + (d(4) >> 5)
        meter = availableData.subdata(in: 7..<10).hexadecimalString
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "BGReceivedPumpEvent",
            "amount": amount,
            "meter": meter,
        ]
    }
}
