//
//  DailyTotal523PumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct DailyTotal523PumpEvent: PumpEvent {
    
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 52
        
        // Sometimes we encounter this at the end of a page, and it can be less characters???
        // need at least 16, I think.
        guard 16 <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<min(length, availableData.count))

        timestamp = DateComponents(pumpEventBytes: availableData.subdata(in: 1..<3))
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "DailyTotal523",
            "validDate": String(format: "%04d-%02d-%02d", timestamp.year!, timestamp.month!, timestamp.day!),
        ]
    }
}
