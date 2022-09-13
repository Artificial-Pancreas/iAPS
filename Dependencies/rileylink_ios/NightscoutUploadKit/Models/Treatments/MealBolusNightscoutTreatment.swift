//
//  MealBolusNightscoutTreatment.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/10/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//
import Foundation

public class MealBolusNightscoutTreatment: NightscoutTreatment {

    public let carbs: Double
    public let absorptionTime: TimeInterval?
    public let insulin: Double?
    public let glucose: Double?
    public let units: Units? // of glucose entry
    public let glucoseType: GlucoseType?
    public let foodType: String?

    required public init?(_ entry: [String : Any]) {
        guard let carbs = entry["carbs"] as? Double else {
            return nil
        }

        self.carbs = carbs
        if let absorptionTimeMinutes = entry["absorptionTime"] as? Double {
            absorptionTime = TimeInterval(minutes: absorptionTimeMinutes)
        } else {
            absorptionTime = nil
        }

        self.insulin = entry["insulin"] as? Double

        if let glucoseUnitsRaw = entry["units"] as? String,
            let glucoseUnits = Units(rawValue: glucoseUnitsRaw),
            let glucoseValue = entry["glucose"] as? Double
        {
            self.units = glucoseUnits
            self.glucose = glucoseValue
        } else {
            self.units = nil
            self.glucose = nil
        }

        if let glucoseTypeRaw = entry["glucoseType"] as? String, let glucoseType = GlucoseType(rawValue: glucoseTypeRaw) {
            self.glucoseType = glucoseType
        } else {
            self.glucoseType = nil
        }

        self.foodType = entry["foodType"] as? String

        super.init(entry)
    }

    override public var dictionaryRepresentation: [String: Any] {
        var rval = super.dictionaryRepresentation
        rval["carbs"] = carbs
        if let absorptionTime = absorptionTime {
            rval["absorptionTime"] = absorptionTime.minutes
        }
        rval["insulin"] = insulin
        if let glucose = glucose {
            rval["glucose"] = glucose
            rval["glucoseType"] = glucoseType?.rawValue
            rval["units"] = units?.rawValue
        }
        if let foodType = foodType {
            rval["foodType"] = foodType
        }
        return rval
    }
}
