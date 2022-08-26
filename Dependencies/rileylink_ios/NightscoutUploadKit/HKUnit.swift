//
//  HKUnit.swift
//  RileyLink
//
//  Created by Nate Racklyeft on 8/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import HealthKit

extension HKUnit {
    static let milligramsPerDeciliter: HKUnit = {
        return HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
    }()
}
