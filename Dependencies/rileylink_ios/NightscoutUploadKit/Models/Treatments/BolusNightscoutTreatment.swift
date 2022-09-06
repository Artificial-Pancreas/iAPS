//
//  BolusNightscoutTreatment.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/10/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class BolusNightscoutTreatment: NightscoutTreatment {
    
    public enum BolusType: String {
        case Normal = "normal"
        case Square = "square"
        case DualWave = "dual"
    }

    public let bolusType: BolusType
    public let amount: Double
    public let programmed: Double
    public let unabsorbed: Double?
    public let duration: TimeInterval
    public let automatic: Bool

    public init(timestamp: Date, enteredBy: String, bolusType: BolusType, amount: Double, programmed: Double, unabsorbed: Double, duration: TimeInterval, automatic: Bool, notes: String? = nil, id: String? = nil, syncIdentifier: String? = nil, insulinType: String?) {
        self.bolusType = bolusType
        self.amount = amount
        self.programmed = programmed
        self.unabsorbed = unabsorbed
        self.duration = duration
        self.automatic = automatic
        super.init(timestamp: timestamp, enteredBy: enteredBy, notes: notes, id: id, eventType: .correctionBolus, syncIdentifier: syncIdentifier, insulinType: insulinType)
    }

    required public init?(_ entry: [String : Any]) {
        guard
            let bolusTypeRaw = entry["type"] as? String,
            let bolusType = BolusType(rawValue: bolusTypeRaw),
            let amount = entry["insulin"] as? Double,
            let programmed = entry["programmed"] as? Double,
            let durationMinutes = entry["duration"] as? Double
        else {
            return nil
        }

        self.bolusType = bolusType
        self.amount = amount
        self.programmed = programmed
        self.duration = TimeInterval(minutes: durationMinutes)
        self.unabsorbed = entry["unabsorbed"] as? Double
        self.automatic = entry["automatic"] as? Bool ?? false
        super.init(entry)
     }

    override public var dictionaryRepresentation: [String: Any] {
        var rval = super.dictionaryRepresentation
        rval["type"] = bolusType.rawValue
        rval["insulin"] = amount
        rval["programmed"] = programmed
        rval["unabsorbed"] = unabsorbed
        rval["duration"] = duration.minutes
        rval["automatic"] = automatic
        return rval
    }
}
