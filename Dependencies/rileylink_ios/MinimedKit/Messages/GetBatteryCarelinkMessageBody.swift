//
//  GetBatteryCarelinkMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/13/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public enum BatteryStatus: Equatable {
    case low
    case normal
    case unknown(rawVal: UInt8)
    
    init(statusByte: UInt8) {
        switch statusByte {
        case 1:
            self = .low
        case 0:
            self = .normal
        default:
            self = .unknown(rawVal: statusByte)
        }
    }
}

public class GetBatteryCarelinkMessageBody: DecodableMessageBody {
    public static var length: Int = 65

    public var txData: Data

    public let status: BatteryStatus
    public let volts: Double
    
    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }
        
        volts = Double(Int(rxData[2]) << 8 + Int(rxData[3])) / 100.0
        status = BatteryStatus(statusByte: rxData[1])
        txData = rxData
    }

    public var description: String {
        return "GetBattery(status:\(status), volts:\(volts))"
    }

}
