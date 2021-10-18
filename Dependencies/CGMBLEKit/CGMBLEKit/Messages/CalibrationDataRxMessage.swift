//
//  CalibrationDataRxMessage.swift
//  Pods
//
//  Created by Nate Racklyeft on 9/18/16.
//
//

import Foundation


struct CalibrationDataRxMessage: TransmitterRxMessage {
    let glucose: UInt16
    let timestamp: UInt32

    init?(data: Data) {
        guard data.count == 19 && data.isCRCValid else {
            return nil
        }

        guard data.starts(with: .calibrationDataRx) else {
            return nil
        }

        glucose = data[11..<13].toInt() & 0xfff
        timestamp = data[13..<17].toInt()
    }
}
