//
//  AutomaticDoseRecommendation.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 1/16/21.
//  Copyright © 2021 Pete Schwamb. All rights reserved.
//

import Foundation

public struct AutomaticDoseRecommendation {
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
}
