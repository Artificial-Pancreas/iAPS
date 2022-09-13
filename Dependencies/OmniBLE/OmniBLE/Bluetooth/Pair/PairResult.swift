//
//  PairResult.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/4/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

struct PairResult {
    var ltk: Data
    var address: UInt32
    var msgSeq: UInt8
}
