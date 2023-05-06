//
//  JournalEntryMealMarkerPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/14/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct JournalEntryMealMarkerPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let carbohydrates: Double
    public let carbUnits: CarbUnits
    
    public enum CarbUnits: String {
        case Exchanges
        case Grams
    }

    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 9
        
        let useExchangesBit = ((availableData[8]) >> 1) & 0b1
        carbUnits = (useExchangesBit != 0) ? .Exchanges : .Grams
        
        let carbHighBit = (availableData[1]) & 0b1
        let carbLowBits = availableData[7]
        
        if carbUnits == .Exchanges {
            carbohydrates = Double(carbLowBits) / 10.0
        } else {
            carbohydrates = Double(Int(carbHighBit) << 8 + Int(carbLowBits))
        }

        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)

        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
    }

    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "JournalEntryMealMarker",
            "carbohydrates": carbohydrates,
            "carbUnits": carbUnits.rawValue,
        ]
    }
}
