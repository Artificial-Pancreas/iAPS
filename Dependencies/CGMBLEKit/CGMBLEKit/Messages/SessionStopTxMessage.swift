//
//  SessionStopTxMessage.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 3/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct SessionStopTxMessage: RespondableMessage {
    typealias Response = SessionStopRxMessage

    let stopTime: UInt32

    var data: Data {
        var data = Data(for: .sessionStopTx)
        data.append(stopTime)
        return data.appendingCRC()
    }
}
