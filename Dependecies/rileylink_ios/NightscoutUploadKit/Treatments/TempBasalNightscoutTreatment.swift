//
//  TempBasalNightscoutTreatment.swift
//  RileyLink
//
//  Created by Pete Schwamb on 4/18/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class TempBasalNightscoutTreatment: NightscoutTreatment {
    
    public enum RateType: String {
        case Absolute = "absolute"
        case Percentage = "percentage"
    }
    
    
    let rate: Double
    let amount: Double?
    let absolute: Double?
    let temp: RateType
    let duration: TimeInterval
    
    public init(timestamp: Date, enteredBy: String, temp: RateType, rate: Double, absolute: Double?, duration: TimeInterval, amount: Double? = nil, id: String? = nil, syncIdentifier: String? = nil) {
        self.rate = rate
        self.absolute = absolute
        self.temp = temp
        self.duration = duration
        self.amount = amount
        
        // Commenting out usage of surrogate ID until supported by Nightscout
        super.init(timestamp: timestamp, enteredBy: enteredBy, id: id, eventType: "Temp Basal", syncIdentifier: syncIdentifier)
    }
    
    override public var dictionaryRepresentation: [String: Any] {
        var rval = super.dictionaryRepresentation
        rval["temp"] = temp.rawValue
        rval["rate"] = rate
        rval["absolute"] = absolute
        rval["duration"] = duration.minutes
        rval["amount"] = amount
        return rval
    }
}
