//
//  TempBasalPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct TempBasalPumpEvent: TimestampedPumpEvent {
    
    public enum RateType : String {
        case Absolute = "absolute"
        case Percent = "percent"
    }
    
    
    public let length: Int
    public let rawData: Data
    public let rateType: RateType
    public let rate: Double
    public let timestamp: DateComponents
    public let wasRemotelyTriggered: Bool
    
    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 8
        
        func d(_ idx: Int) -> Int {
            return Int(availableData[idx])
        }
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        rateType = (d(7) >> 3) == 0 ? .Absolute : .Percent
        if rateType == .Absolute {
            rate = Double(((d(7) & 0b111) << 8) + d(1)) / 40.0
        } else {
            rate = Double(d(1))
        }
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 2)
        
        wasRemotelyTriggered = availableData[5] & 0b01000000 != 0
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "_type": "TempBasal",
            "rate": rate,
            "temp": rateType.rawValue,
            "wasRemotelyTriggered": wasRemotelyTriggered,
        ]
    }

    public var description: String {
        switch rateType {
        case .Absolute:
            return String(format: LocalizedString("Temporary Basal: %1$.3f U/hour", comment: "The format string description of a TempBasalPumpEvent. (1: The rate of the temp basal in minutes)"), rate)
        case .Percent:
            return String(format: LocalizedString("Temporary Basal: %1$d%%", comment: "The format string description of a TempBasalPumpEvent. (1: The rate of the temp basal in percent)"), Int(rate))
        }
    }
}

