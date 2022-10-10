//
//  MeterMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/10/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//


public struct MeterMessage: MessageBody, DictionaryRepresentable {
    
    public static let length = 7
    
    public let glucose: Int
    public let ackFlag: Bool
    let rxData: Data
    
    public init?(rxData: Data) {
        self.rxData = rxData
        
        if rxData.count == type(of: self).length,
            let packetType = PacketType(rawValue: rxData[0]), packetType == .meter
        {
            let flags = ((rxData[4]) & 0b110) >> 1
            ackFlag = flags == 0x03
            glucose = Int((rxData[4]) & 0b1) << 8 + Int(rxData[4])
        } else {
            ackFlag = false
            glucose = 0
            return nil
        }
    }
    
    public var txData: Data {
        return rxData
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "glucose": glucose,
            "ackFlag": ackFlag,
        ]
    }

    public var description: String {
        return "Meter(\(glucose), \(ackFlag))"
    }
}
