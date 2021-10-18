//
//  Int.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension Int {
    init<T: Collection>(bigEndianBytes bytes: T) where T.Element == UInt8 {
        assert(bytes.count <= 4)
        var result: UInt = 0

        for (index, byte) in bytes.enumerated() {
            let shiftAmount = UInt((bytes.count) - index - 1) * 8
            result += UInt(byte) << shiftAmount
        }

        self.init(result)
    }
}
