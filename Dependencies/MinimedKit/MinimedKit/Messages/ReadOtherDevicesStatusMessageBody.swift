//
//  ReadOtherDevicesStatusMessageBody.swift
//  MinimedKit
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

public class ReadOtherDevicesStatusMessageBody: CarelinkLongMessageBody {
    public let isEnabled: Bool

    public required init?(rxData: Data) {
        guard rxData.count == type(of: self).length else {
            return nil
        }

        isEnabled = rxData[1] == 1

        super.init(rxData: rxData)
    }
}

// Body[1] encodes the bool state
// 0200010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
//  0201010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
