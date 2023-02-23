//
//  SensorMessage.swift
//  G7SensorKit
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

extension Data {
    func starts(with opcode: G7Opcode) -> Bool {
        guard count > 0 else {
            return false
        }

        return self[startIndex] == opcode.rawValue
    }
}

/// A data sequence received by the sensor
protocol SensorMessage {
    init?(data: Data)
}
