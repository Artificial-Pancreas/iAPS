//
//  ForecastError.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 5/28/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation
import HealthKit

public struct ForecastError {
    let velocity: Double
    let measurementDuration: Double
    
    public init(velocity: HKQuantity, measurementDuration: TimeInterval) {
        
        let glucoseUnit = HKUnit.milligramsPerDeciliterUnit()
        let velocityUnit = glucoseUnit.unitDivided(by: HKUnit.second())

        self.velocity = velocity.doubleValue(for: velocityUnit)
        self.measurementDuration = measurementDuration
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        rval["velocity"] = velocity
        rval["measurementDuration"] = measurementDuration
        //rval["velocityUnits"] = "mg/dL/s"
        return rval
    }
}
