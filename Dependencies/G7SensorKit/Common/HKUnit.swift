//
//  HKUnit.swift
//  xDripG5
//
//  Created by Nate Racklyeft on 8/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import HealthKit


extension HKUnit {
    static let milligramsPerDeciliter: HKUnit = {
        return HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
    }()

    static let milligramsPerDeciliterPerMinute: HKUnit = {
        return HKUnit.milligramsPerDeciliter.unitDivided(by: .minute())
    }()
}
