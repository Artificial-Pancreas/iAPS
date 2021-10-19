//
//  CalibrateGlucoseTxMessage.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 3/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct CalibrateGlucoseTxMessage: RespondableMessage {
    typealias Response = CalibrateGlucoseRxMessage

    let time: UInt32
    let glucose: UInt16

    var data: Data {
        var data = Data(for: .calibrateGlucoseTx)
        data.append(glucose)
        data.append(time)
        return data.appendingCRC()
    }
}
