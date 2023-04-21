//
//  DeviceLinkMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 2/29/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public struct DeviceLinkMessageBody: DecodableMessageBody {
    
    public static let length = 5
    
    public let deviceAddress: Data
    public let sequence: UInt8
    public var txData: Data
    
    
    public init?(rxData: Data) {
        self.txData = rxData
        
        if rxData.count == type(of: self).length {
            self.deviceAddress = rxData.subdata(in: 1..<4)
            sequence = rxData[0] & 0b1111111
        } else {
            return nil
        }
    }
    
    public var description: String {
        return "DeviceLink(\(deviceAddress.hexadecimalString), \(sequence))"
    }
}
