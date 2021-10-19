//
//  CalibrationDataTxMessage.swift
//  xDripG5
//
//  Created by Paul Dickens on 17/03/2018.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


struct CalibrationDataTxMessage: RespondableMessage {
    typealias Response = CalibrationDataRxMessage

    var data: Data {
        return Data(for: .calibrationDataTx).appendingCRC()
    }
}
