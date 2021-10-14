//
//  SessionStartRxMessage.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 6/4/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct SessionStartRxMessage: TransmitterRxMessage {
    let status: UInt8
    let received: UInt8

    // I've only seen examples of these 2 values matching
    let requestedStartTime: UInt32
    let sessionStartTime: UInt32

    let transmitterTime: UInt32

    init?(data: Data) {
        guard data.count == 17 && data.isCRCValid else {
            return nil
        }

        guard data.starts(with: .sessionStartRx) else {
            return nil
        }

        status = data[1]
        received = data[2]
        requestedStartTime = data[3..<7].toInt()
        sessionStartTime = data[7..<11].toInt()
        transmitterTime = data[11..<15].toInt()
    }
}
