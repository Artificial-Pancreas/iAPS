//
//  Calibration.swift
//  xDripG5
//
//  Created by Paul Dickens on 17/03/2018.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit


public struct Calibration {
    init?(calibrationMessage: CalibrationDataRxMessage, activationDate: Date) {
        guard calibrationMessage.glucose > 0 else {
            return nil
        }

        let unit = HKUnit.milligramsPerDeciliter

        glucose = HKQuantity(unit: unit, doubleValue: Double(calibrationMessage.glucose))
        date = activationDate.addingTimeInterval(TimeInterval(calibrationMessage.timestamp))
    }

    public let glucose: HKQuantity
    public let date: Date
}
