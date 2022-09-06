//
//  BGCheckNightscoutTreatment.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/10/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class BGCheckNightscoutTreatment: NightscoutTreatment {
    
    let glucose: Double
    let glucoseType: GlucoseType
    let units: Units
    
    public init(timestamp: Date, enteredBy: String, glucose: Double, glucoseType: GlucoseType, units: Units, notes: String? = nil) {
        self.glucose = glucose
        self.glucoseType = glucoseType
        self.units = units
        super.init(timestamp: timestamp, enteredBy: enteredBy, notes: notes, eventType: .bloodGlucoseCheck)
    }

    required public init?(_ entry: [String : Any]) {
        guard
            let glucose = entry["glucose"] as? Double,
            let glucoseTypeRaw = entry["glucoseType"] as? String,
            let glucoseType = GlucoseType(rawValue: glucoseTypeRaw),
            let unitsRaw = entry["units"] as? String,
            let units = Units(rawValue: unitsRaw)
        else {
            return nil
        }

        self.glucose = glucose
        self.glucoseType = glucoseType
        self.units = units

        super.init(entry)
    }
    
    override public var dictionaryRepresentation: [String: Any] {
        var rval = super.dictionaryRepresentation
        rval["glucose"] = glucose
        rval["glucoseType"] = glucoseType.rawValue
        rval["units"] = units.rawValue
        return rval
    }
}
