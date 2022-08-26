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
    typealias RawValue = [String: Any]

    public let startDate: Date
    public let values: [Double]
    public let cob: [Double]?
    public let iob: [Double]?

    public init(startDate: Date, values: [HKQuantity], cob: [HKQuantity]? = nil, iob: [HKQuantity]? =
        nil) {
        self.startDate = startDate
        // BG values in nightscout are in mg/dL.
        let unit = HKUnit.milligramsPerDeciliter
        self.values = values.map { round($0.doubleValue(for: unit) * 100) / 100 }
        self.cob = cob?.map { round($0.doubleValue(for: unit) * 100) / 100 }
        self.iob = iob?.map { round($0.doubleValue(for: unit) * 100) / 100 }
    }

    public var dictionaryRepresentation: [String: Any] {
        var rval = RawValue()

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

    init?(rawValue: RawValue) {
        guard
            let startDateRaw = rawValue["startDate"] as? String,
            let startDate = TimeFormat.dateFromTimestamp(startDateRaw),
            let values = rawValue["values"] as? [Double]
        else {
            return nil
        }

        self.startDate = startDate
        self.values = values
        self.cob = rawValue["COB"] as? [Double]
        self.iob = rawValue["IOB"] as? [Double]
    }
}
