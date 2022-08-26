//
//  CorrectionRange.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 5/28/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation
import HealthKit

public struct CorrectionRange {
    typealias RawValue = [String: Any]

    let minValue: Double
    let maxValue: Double
    
    public init(minValue: HKQuantity, maxValue: HKQuantity) {

        // BG values in nightscout are in mg/dL.
        let unit = HKUnit.milligramsPerDeciliter
        self.minValue = minValue.doubleValue(for: unit)
        self.maxValue = maxValue.doubleValue(for: unit)
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        rval["minValue"] = minValue
        rval["maxValue"] = maxValue
        
        return rval
    }

    init?(rawValue: RawValue) {
        guard
            let minValue = rawValue["minValue"] as? Double,
            let maxValue = rawValue["maxValue"] as? Double
        else {
            return nil
        }

        self.minValue = minValue
        self.maxValue = maxValue
    }
}
