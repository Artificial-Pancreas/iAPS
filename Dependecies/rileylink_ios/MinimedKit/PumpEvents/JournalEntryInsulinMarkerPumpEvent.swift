//
//  JournalEntryInsulinMarkerPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/16/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct JournalEntryInsulinMarkerPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let amount: Double
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 8
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        
        let lowBits = rawData[1]
        let highBits = rawData[4]
        amount = Double((Int(highBits & 0b1100000) << 3) + Int(lowBits)) / 10.0
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "JournalEntryInsulinMarker",
            "amount": amount,
        ]
    }
}
