//
//  G7Opcode.swift
//  CGMBLEKit
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

enum G7Opcode: UInt8 {
    case authChallengeRx = 0x05
    case glucoseTx = 0x4e
    case backfillFinished = 0x59
}
