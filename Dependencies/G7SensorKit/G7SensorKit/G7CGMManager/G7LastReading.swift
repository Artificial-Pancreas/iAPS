//
//  G7LastReading.swift
//  CGMBLEKit
//
//  Created by Pete Schwamb on 10/4/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

struct G7LastReading {
    let glucose: Int?
    let timestamp: Date
    let sensorTimestamp: Date
}
