//
//  UUIDContainer.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 08/01/2020.
//  Copyright © 2020 Bjørn Inge Berg. All rights reserved.
//

import CoreBluetooth
import Foundation
public struct UUIDContainer: ExpressibleByStringLiteral {
    public var value: CBUUID

    init(value: CBUUID) {
        self.value = value
    }
    public init(stringLiteral value: String) {
        self.value = CBUUID(string: value)
    }
}
