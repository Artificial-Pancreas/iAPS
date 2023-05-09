//
//  PlaceholderPumpEvent.swift
//  RileyLink
//
//  Created by Nate Racklyeft on 6/20/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation


public struct PlaceholderPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents

    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 7

        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
    }

    public var dictionaryRepresentation: [String: Any] {
        let name: String
        if let type = PumpEventType(rawValue: rawData[0]) {
            name = String(describing: type).components(separatedBy: ".").last!
        } else {
            name = "UnknownPumpEvent(\(rawData[0]))"
        }
        
        return [
            "_type": name,
        ]
    }
}

