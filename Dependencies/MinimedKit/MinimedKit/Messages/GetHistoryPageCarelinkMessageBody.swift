//
//  GetHistoryPageCarelinkMessageBody.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/14/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public class GetHistoryPageCarelinkMessageBody: CarelinkLongMessageBody {
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
    
    public required init(pageNum: Int) {
        let numArgs = 1
        lastFrame = false
        frame = Data()
        frameNumber = 0
        let data = Data(hexadecimalString: String(format: "%02x%02x", numArgs, UInt8(pageNum)))!
        super.init(rxData: data)!
    }
    
}
