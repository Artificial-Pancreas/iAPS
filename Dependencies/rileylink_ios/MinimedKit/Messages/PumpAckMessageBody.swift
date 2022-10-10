//
//  PumpAckMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/14/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class PumpAckMessageBody: DecodableMessageBody {
    public static let length = 1
    
    let rxData: Data
    
    public required init?(rxData: Data) {
        self.rxData = rxData
    }
    
    public var txData: Data {
        return rxData
    }

    public var description: String {
        return "PumpAck(\(rxData.hexadecimalString))"
    }

}
