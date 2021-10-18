//
//  MinimedPacket.swift
//  RileyLinkBLEKit
//
//  Created by Pete Schwamb on 10/7/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public struct MinimedPacket {
    public let data: Data
    
    public init(outgoingData: Data) {
        self.data = outgoingData
    }
    
    public init?(encodedData: Data) {
        
        if let decoded = encodedData.decode4b6b() {
            if decoded.count == 0 {
                return nil
            }
            let msg = decoded.prefix(upTo: (decoded.count - 1))
            if decoded.last != msg.crc8() {
                // CRC invalid
                return nil
            }
            self.data = Data(msg)
        } else {
            // Could not decode message
            return nil
        }
    }
    
    public func encodedData() -> Data {
        var dataWithCRC = self.data
        dataWithCRC.append(data.crc8())
        var encodedData = dataWithCRC.encode4b6b()
        encodedData.append(0)
        return Data(encodedData)
    }
}

