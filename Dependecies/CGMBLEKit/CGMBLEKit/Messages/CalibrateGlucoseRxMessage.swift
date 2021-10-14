//
//  CalibrateGlucoseRxMessage.swift
//  xDripG5
//
//  Created by Paul Dickens on 25/02/2018.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


public struct CalibrateGlucoseRxMessage: TransmitterRxMessage {
    init?(data: Data) {
        guard data.count == 5 && data.isCRCValid else {
            return nil
        }

        guard data.starts(with: .calibrateGlucoseRx) else {
            return nil
        }
    }
}
