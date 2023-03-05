//
//  ReadTimeCarelinkMessageBody.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/17/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public class ReadTimeCarelinkMessageBody: DecodableMessageBody {
    public var txData: Data

    public static var length: Int = 65

    public let dateComponents: DateComponents

    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.hour   = Int(rxData[1])
        dateComponents.minute = Int(rxData[2])
        dateComponents.second = Int(rxData[3])
        dateComponents.year   = Int(bigEndianBytes: rxData.subdata(in: 4..<6))
        dateComponents.month  = Int(rxData[6])
        dateComponents.day    = Int(rxData[7])

        self.dateComponents = dateComponents
        self.txData = rxData
    }

    public init(dateComponents: DateComponents) {
        self.dateComponents = dateComponents
        txData = Data().paddedTo(length: Self.length)
        txData[1] = UInt8(dateComponents.hour!)
        txData[2] = UInt8(dateComponents.minute!)
        txData[3] = UInt8(dateComponents.second!)
        txData[4] = UInt8(dateComponents.year! >> 8 & 0xff)
        txData[5] = UInt8(dateComponents.year! & 0xff)
        txData[6] = UInt8(dateComponents.month!)
        txData[7] = UInt8(dateComponents.day!)
    }

    public var description: String {
        return "ReadTime(\(dateComponents))"
    }
}
