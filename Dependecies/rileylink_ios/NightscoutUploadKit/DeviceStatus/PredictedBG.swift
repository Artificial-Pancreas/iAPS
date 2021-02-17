//
//  PredictedBG.swift
//  RileyLink
//
//  Created by Pete Schwamb on 8/8/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation
import HealthKit

public struct PredictedBG {
    let startDate: Date
    let values: [Int]
    let cob: [Int]?
    let iob: [Int]?

    public init(startDate: Date, values: [HKQuantity], cob: [HKQuantity]? = nil, iob: [HKQuantity]? =
        nil) {
        self.startDate = startDate
        // BG values in nightscout are in mg/dL.
        let unit = HKUnit.milligramsPerDeciliterUnit()
        self.values = values.map { Int(round($0.doubleValue(for: unit))) }
        self.cob = cob?.map { Int(round($0.doubleValue(for: unit))) }
        self.iob = iob?.map { Int(round($0.doubleValue(for: unit))) }
    }

    public var dictionaryRepresentation: [String: Any] {

        var rval = [String: Any]()

        rval["startDate"] =  TimeFormat.timestampStrFromDate(startDate)
        rval["values"] = values

        if let cob = cob {
            rval["COB"] = cob
        }

        if let iob = iob {
            rval["IOB"] = iob
        }

        return rval
    }
}
