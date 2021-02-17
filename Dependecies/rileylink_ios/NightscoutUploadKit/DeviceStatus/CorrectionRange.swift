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
    let minValue: Int
    let maxValue: Int
    
    public init(minValue: HKQuantity, maxValue: HKQuantity) {

        // BG values in nightscout are in mg/dL.
        let unit = HKUnit.milligramsPerDeciliterUnit()
        self.minValue = Int(round(minValue.doubleValue(for: unit)))
        self.maxValue = Int(round(maxValue.doubleValue(for: unit)))
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        rval["minValue"] = minValue
        rval["maxValue"] = maxValue
        
        return rval
    }
}
