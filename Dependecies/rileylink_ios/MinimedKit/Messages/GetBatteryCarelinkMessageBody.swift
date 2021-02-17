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

public class GetBatteryCarelinkMessageBody: CarelinkLongMessageBody {
    public let status: BatteryStatus
    public let volts: Double
    
    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            volts = 0
            status = .unknown(rawVal: 0)
            super.init(rxData: rxData)
            return nil
        }
        
        volts = Double(Int(rxData[2]) << 8 + Int(rxData[3])) / 100.0
        status = BatteryStatus(statusByte: rxData[1])
        
        super.init(rxData: rxData)
    }

    public required init?(rxData: NSData) {
        fatalError("init(rxData:) has not been implemented")
    }
}
