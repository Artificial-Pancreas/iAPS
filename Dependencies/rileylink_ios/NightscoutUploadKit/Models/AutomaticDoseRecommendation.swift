//
//  AutomaticDoseRecommendation.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 1/16/21.
//  Copyright © 2021 Pete Schwamb. All rights reserved.
//

import Foundation

public struct AutomaticDoseRecommendation {
    typealias RawValue = [String: Any]

    let timestamp: Date
    let tempBasalAdjustment: TempBasalAdjustment?
    let bolusVolume: Double

    public init(timestamp: Date, tempBasalAdjustment: TempBasalAdjustment?, bolusVolume: Double) {
        self.timestamp = timestamp
        self.tempBasalAdjustment = tempBasalAdjustment
        self.bolusVolume = bolusVolume
    }

    public var dictionaryRepresentation: [String: Any] {

        var rval = [String: Any]()

        rval["timestamp"] = TimeFormat.timestampStrFromDate(timestamp)
        rval["tempBasalAdjustment"] = tempBasalAdjustment?.dictionaryRepresentation
        rval["bolusVolume"] = bolusVolume
        return rval
    }

    init?(rawValue: RawValue) {
        guard
            let timestampStr = rawValue["timestamp"] as? String,
            let timestamp = TimeFormat.dateFromTimestamp(timestampStr)
        else {
            return nil
        }

        if let tempBasalAdjustmentRaw = rawValue["tempBasalAdjustment"] as? TempBasalAdjustment.RawValue,
           let tempBasalAdjustment = TempBasalAdjustment(rawValue: tempBasalAdjustmentRaw)
        {
            self.tempBasalAdjustment = tempBasalAdjustment
        } else {
            self.tempBasalAdjustment = nil
        }

        self.bolusVolume = rawValue["bolusVolume"] as? Double ?? 0
        self.timestamp = timestamp
    }
}
