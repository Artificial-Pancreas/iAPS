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
    typealias RawValue = [String: Any]

    let velocity: Double
    let measurementDuration: TimeInterval
    
    public init(velocity: HKQuantity, measurementDuration: TimeInterval) {
        
        let glucoseUnit = HKUnit.milligramsPerDeciliter
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

    init?(rawValue: RawValue) {
        guard
            let velocity = rawValue["velocity"] as? Double,
            let measurementDuration = rawValue["measurementDuration"] as? TimeInterval
        else {
            return nil
        }

        self.velocity = velocity
        self.measurementDuration = measurementDuration
    }
}
