//
//  ChangeRemoteControlIDMessageBody.swift
//  MinimedKit
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation


public class ChangeRemoteControlIDMessageBody: CarelinkLongMessageBody {
    public convenience init?(id: Data? = nil, index: Int) {
        guard index < 3 else {
            return nil
        }

        var rxData = Data(repeating: 0x2d, count: 8)  // 2d signifies a deletion
        rxData[0] = 0x07  // length
        rxData[1] = UInt8(clamping: index)

        if let id = id {
            for (index, byte) in id.enumerated() {
                rxData[2 + index] = 0b00110000 + byte
            }
        }

        self.init(rxData: rxData)
    }

}
