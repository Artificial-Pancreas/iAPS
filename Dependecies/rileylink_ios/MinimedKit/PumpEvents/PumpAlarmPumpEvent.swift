//
//  PumpAlarmPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public enum PumpAlarmType {
    case batteryOutLimitExceeded
    case noDelivery             
    case batteryDepleted
    case autoOff
    case deviceReset
    case deviceResetBatteryIssue17
    case deviceResetBatteryIssue21
    case reprogramError         
    case emptyReservoir         
    case unknownType(rawType: UInt8)

    init(rawType: UInt8) {
        switch rawType {
        case 3:
            self = .batteryOutLimitExceeded
        case 4:
            self = .noDelivery
        case 5:
            self = .batteryDepleted
        case 6:
            self = .autoOff 
        case 16:
            self = .deviceReset
        case 17:
            self = .deviceResetBatteryIssue17
        case 21:
            self = .deviceResetBatteryIssue21
        case 61:
            self = .reprogramError
        case 62:
            self = .emptyReservoir
        default:
            self = .unknownType(rawType: rawType)
        }
    }
}

public struct PumpAlarmPumpEvent: TimestampedPumpEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let alarmType: PumpAlarmType

    public init?(availableData: Data, pumpModel: PumpModel) {
        length = 9
        
        guard length <= availableData.count else {
            return nil
        }

        rawData = availableData.subdata(in: 0..<length)
        
        alarmType = PumpAlarmType(rawType: availableData[1])
        
        timestamp = DateComponents(pumpEventData: availableData, offset: 4)
    }
    
    public var dictionaryRepresentation: [String: Any] {

        return [
            "_type": "AlarmPump",
            "alarm": "\(self.alarmType)",
        ]
    }
}
