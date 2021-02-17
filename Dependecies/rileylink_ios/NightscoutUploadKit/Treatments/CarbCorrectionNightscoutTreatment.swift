//
//  CarbCorrectionNightscoutTreatment.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/10/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class CarbCorrectionNightscoutTreatment: NightscoutTreatment {
    
    let carbs: Int
    let absorptionTime: TimeInterval?
    let glucose: Int?
    let units: Units? // of glucose entry
    let glucoseType: GlucoseType?
    let foodType: String?
    let userEnteredAt: Date?
    let userLastModifiedAt: Date?

    public init(timestamp: Date, enteredBy: String, id: String?, carbs: Int, absorptionTime: TimeInterval? = nil, glucose: Int? = nil, glucoseType: GlucoseType? = nil, units: Units? = nil, foodType: String? = nil, notes: String? = nil, syncIdentifier: String? = nil, userEnteredAt: Date? = nil, userLastModifiedAt: Date? = nil) {
        self.carbs = carbs
        self.absorptionTime = absorptionTime
        self.glucose = glucose
        self.glucoseType = glucoseType
        self.units = units
        self.foodType = foodType
        self.userEnteredAt = userEnteredAt
        self.userLastModifiedAt = userLastModifiedAt
        super.init(timestamp: timestamp, enteredBy: enteredBy, notes: notes, id: id, eventType: "Carb Correction", syncIdentifier: syncIdentifier)
    }
    
    override public var dictionaryRepresentation: [String: Any] {
        var rval = super.dictionaryRepresentation
        rval["carbs"] = carbs
        if let absorptionTime = absorptionTime {
            rval["absorptionTime"] = absorptionTime.minutes
        }
        if let glucose = glucose {
            rval["glucose"] = glucose
            rval["glucoseType"] = glucoseType?.rawValue
            rval["units"] = units?.rawValue
        }
        if let foodType = foodType {
            rval["foodType"] = foodType
        }
        if let userEnteredAt = userEnteredAt {
            rval["userEnteredAt"] = TimeFormat.timestampStrFromDate(userEnteredAt)
        }
        if let userLastModifiedAt = userLastModifiedAt {
            rval["userLastModifiedAt"] = TimeFormat.timestampStrFromDate(userLastModifiedAt)
        }
        return rval
    }
}
