//
//  NSDateComponents.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/13/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension DateComponents {
    init(mySentryBytes: Data) {
        self.init()

        hour   = Int(mySentryBytes[0] & 0b00011111)
        minute = Int(mySentryBytes[1] & 0b00111111)
        second = Int(mySentryBytes[2] & 0b00111111)
        year   = Int(mySentryBytes[3]) + 2000
        month  = Int(mySentryBytes[4] & 0b00001111)
        day    = Int(mySentryBytes[5] & 0b00011111)

        calendar = Calendar(identifier: .gregorian)
    }

    init(pumpEventData: Data, offset: Int, length: Int = 5) {
        self.init(pumpEventBytes: pumpEventData.subdata(in: offset..<offset + length))
    }

    init(pumpEventBytes: Data) {
        self.init()

        if pumpEventBytes.count == 5 {
            second = Int(pumpEventBytes[0] & 0b00111111)
            minute = Int(pumpEventBytes[1] & 0b00111111)
            hour   = Int(pumpEventBytes[2] & 0b00011111)
            day    = Int(pumpEventBytes[3] & 0b00011111)
            month = Int((pumpEventBytes[0] & 0b11000000) >> 4) +
                    Int((pumpEventBytes[1] & 0b11000000) >> 6)
            year   = Int(pumpEventBytes[4] & 0b01111111) + 2000
        } else {
            day    = Int(pumpEventBytes[0] & 0b00011111)
            month = Int((pumpEventBytes[0] & 0b11100000) >> 4) +
                    Int((pumpEventBytes[1] & 0b10000000) >> 7)
            year   = Int(pumpEventBytes[1] & 0b01111111) + 2000
        }

        calendar = Calendar(identifier: .gregorian)
    }
    
    init(glucoseEventBytes: Data) {
        self.init()
        
        year   = Int(glucoseEventBytes[3] & 0b01111111) + 2000
        month = Int((glucoseEventBytes[0] & 0b11000000) >> 4) +
                Int((glucoseEventBytes[1] & 0b11000000) >> 6)
        day    = Int(glucoseEventBytes[2] & 0b00011111)
        hour   = Int(glucoseEventBytes[0] & 0b00011111)
        minute = Int(glucoseEventBytes[1] & 0b00111111)
        
        calendar = Calendar(identifier: .gregorian)
    }
}
