//
//  FindDeviceMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 2/29/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct FindDeviceMessageBody: DecodableMessageBody {
    
    public static let length = 5
    
    public let deviceAddress: Data
    public let sequence: UInt8
    let rxData: Data
    
    
    public init?(rxData: Data) {
        self.rxData = rxData
        
        if rxData.count == type(of: self).length {
            self.deviceAddress = rxData.subdata(in: 1..<4)
            sequence = rxData[0] & 0b1111111
        } else {
            return nil
        }
    }
    
    public var txData: Data {
        return rxData
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "sequence": Int(sequence),
            "deviceAddress": deviceAddress.hexadecimalString,
        ]
    }

    public var description: String {
        return "FindDevice(\(deviceAddress.hexadecimalString), \(sequence))"
    }
}
