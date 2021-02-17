//
//  TempBasalDurationPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/20/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct TempBasalDurationPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let duration: Int
    public let timestamp: DateComponents
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 7
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        duration = d(1) * 30
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "TempBasalDuration",
            "duration": duration,
        ]
    }

    public var description: String {
        return String(format: LocalizedString("Temporary Basal: %1$d min", comment: "The format string description of a TempBasalDurationPumpEvent. (1: The duration of the temp basal in minutes)"), duration)
    }
}
