//
//  BatteryStatusTxMessage.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 3/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


struct BatteryStatusTxMessage {
    let opcode: Opcode = .batteryStatusTx

    // Response: 23003c012f01cd021f247bae
}
