//
//  SessionKeys.swift
//  OmniBLE
//
//  Created by Randall Knutson on 11/8/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

struct SessionKeys {
    var ck: Data
    var nonce: Nonce
    var msgSequenceNumber: Int
}

struct SessionNegotiationResynchronization {
    let synchronizedEapSqn: EapSqn
    let msgSequenceNumber: UInt8
}
