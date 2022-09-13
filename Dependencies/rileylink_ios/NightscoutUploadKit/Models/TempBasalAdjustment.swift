//
//  TempBasalAdjustment.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 7/28/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct TempBasalAdjustment {
    typealias RawValue = [String: Any]

    let rate: Double
    let duration: TimeInterval

    public init(rate: Double, duration: TimeInterval) {
        self.rate = rate
        self.duration = duration
    }

    public var dictionaryRepresentation: [String: Any] {

        var rval = [String: Any]()

        rval["rate"] = rate
        rval["duration"] = duration / 60.0
        return rval
    }

    init?(rawValue: RawValue) {
        guard
            let rate = rawValue["rate"] as? Double,
            let durationMinutes = rawValue["duration"] as? Double
        else {
            return nil
        }

        self.rate = rate
        self.duration = TimeInterval(minutes: durationMinutes)
    }
}
