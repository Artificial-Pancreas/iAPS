//
//  GetGlucosePageMessageBody.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/19/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class GetGlucosePageMessageBody: CarelinkLongMessageBody {
    public let lastFrame: Bool
    public let frameNumber: Int
    public let frame: Data
    
    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }
        frameNumber = Int(rxData[0]) & 0b1111111
        lastFrame = (rxData[0]) & 0b10000000 > 0
        frame = rxData.subdata(in: 1..<65)
        super.init(rxData: rxData)
    }
    
    public required init(pageNum: UInt32) {
        let numArgs = 4
        lastFrame = false
        frame = Data()
        frameNumber = 0
        let data = Data(hexadecimalString: String(format: "%02x%08x", numArgs, pageNum))!
        super.init(rxData: data)!
    }
    
}
