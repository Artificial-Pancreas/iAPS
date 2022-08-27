//
//  OverrideTreatment.swift
//  NightscoutUploadKit
//
//  Created by Pete Schwamb on 9/28/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation


public class OverrideTreatment: NightscoutTreatment {
    
    public enum Duration {
        case finite(TimeInterval)
        case indefinite
    }

    let correctionRange: ClosedRange<Double>?  // mg/dL
    let insulinNeedsScaleFactor: Double?
    let duration: Duration
    let reason: String
    let remoteAddress: String?

    public init(startDate: Date, enteredBy: String, reason: String, duration: Duration, correctionRange: ClosedRange<Double>?, insulinNeedsScaleFactor: Double?, remoteAddress: String? = nil, id: String? = nil) {
        self.reason = reason
        self.duration = duration
        self.correctionRange = correctionRange
        self.insulinNeedsScaleFactor = insulinNeedsScaleFactor
        self.remoteAddress = remoteAddress
        super.init(timestamp: startDate, enteredBy: enteredBy, id: id, eventType: .temporaryOverride)
    }

    required public init?(_ entry: [String : Any]) {
        guard
            let reason = entry["reason"] as? String
        else {
            return nil
        }

        if let durationMinutes = entry["duration"] as? Double {
            self.duration = .finite(TimeInterval(minutes: durationMinutes))
        } else if let durationType = entry["durationType"] as? String, durationType == "indefinite" {
            self.duration = .indefinite
        } else {
            return nil
        }

        self.reason = reason
        if let correctionRange = entry["correctionRange"] as? [Double], correctionRange.count >= 2 {
            self.correctionRange = ClosedRange(uncheckedBounds: (lower: correctionRange[0], upper: correctionRange[1]))
        } else {
            self.correctionRange = nil
        }

        insulinNeedsScaleFactor = entry["insulinNeedsScaleFactor"] as? Double
        remoteAddress = entry["remoteAddress"] as? String

        super.init(entry)
    }

    override public var dictionaryRepresentation: [String: Any] {
        var rval = super.dictionaryRepresentation

        switch duration {
        case .finite(let timeInterval):
            rval["duration"] = timeInterval.minutes
        case .indefinite:
            rval["durationType"] = "indefinite"
        }
        rval["reason"] = reason
        rval["insulinNeedsScaleFactor"] = insulinNeedsScaleFactor
        rval["remoteAddress"] = remoteAddress

        if let correctionRange = correctionRange {
            rval["correctionRange"] = [correctionRange.lowerBound, correctionRange.upperBound]
        }

        return rval
    }
}
