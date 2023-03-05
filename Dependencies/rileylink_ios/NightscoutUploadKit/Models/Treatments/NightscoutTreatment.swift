//
//  NightscoutTreatment.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/9/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public protocol DictionaryRepresentable {
    var dictionaryRepresentation: [String: Any] {
        get
    }
}

public enum TreatmentType: String {
    case correctionBolus = "Correction Bolus"
    case carbCorrection = "Carb Correction"
    case tempBasal = "Temp Basal"
    case temporaryOverride = "Temporary Override"
    case mealBolus = "Meal Bolus"
    case bloodGlucoseCheck = "BG Check"
    case suspendPump = "Suspend Pump"
    case resumePump = "Resume Pump"
    case note = "Note"

    public var classType: NightscoutTreatment.Type {
        switch self {
        case .correctionBolus:
            return BolusNightscoutTreatment.self
        case .carbCorrection:
            return CarbCorrectionNightscoutTreatment.self
        case .tempBasal:
            return TempBasalNightscoutTreatment.self
        case .temporaryOverride:
            return OverrideTreatment.self
        case .mealBolus:
            return MealBolusNightscoutTreatment.self
        case .bloodGlucoseCheck:
            return BGCheckNightscoutTreatment.self
        case .suspendPump:
            return PumpSuspendTreatment.self
        case .resumePump:
            return PumpResumeTreatment.self
        case .note:
            return NoteNightscoutTreatment.self
        }
    }
}

public class NightscoutTreatment: DictionaryRepresentable {
    
    public enum GlucoseType: String {
        case Meter
        case Sensor
        case Finger
        case Manual
    }
    
    public enum Units: String {
        case MMOLL = "mmol/L"
        case MGDL = "mg/dL"
    }
    
    public let timestamp: Date
    let enteredBy: String
    let notes: String?
    let id: String?
    let eventType: TreatmentType
    let syncIdentifier: String?
    let insulinType: String?


    public init(timestamp: Date, enteredBy: String, notes: String? = nil, id: String? = nil, eventType: TreatmentType, syncIdentifier: String? = nil, insulinType: String? = nil) {
        self.timestamp = timestamp
        self.enteredBy = enteredBy
        self.id = id
        self.notes = notes
        self.eventType = eventType
        self.syncIdentifier = syncIdentifier
        self.insulinType = insulinType
    }

    required public init?(_ entry: [String: Any]) {
        guard
            let identifier = entry["_id"] as? String,
            let eventTypeStr = entry["eventType"] as? String,
            let eventType = TreatmentType(rawValue: eventTypeStr),
            let timestampStr = entry["timestamp"] as? String,
            let timestamp = TimeFormat.dateFromTimestamp(timestampStr),
            let enteredBy = entry["enteredBy"] as? String
        else {
            return nil
        }

        self.id = identifier
        self.eventType = eventType
        self.timestamp = timestamp
        self.enteredBy = enteredBy
        self.notes = entry["notes"] as? String
        self.syncIdentifier = entry["syncIdentifier"] as? String
        self.insulinType = entry["insulinType"] as? String
    }

    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [
            "created_at": TimeFormat.timestampStrFromDate(timestamp),
            "timestamp": TimeFormat.timestampStrFromDate(timestamp),
            "enteredBy": enteredBy,
        ]
        rval["_id"] = id
        rval["notes"] = notes
        rval["eventType"] = eventType.rawValue
        rval["insulinType"] = insulinType

        // Not part of the normal NS model, but we store here to be able to match to client provided ids
        rval["syncIdentifier"] = syncIdentifier

        return rval
    }

    public static func fromServer(_ entry: [String: Any]) -> NightscoutTreatment? {
        guard
            let eventTypeStr = entry["eventType"] as? String,
            let eventType = TreatmentType(rawValue: eventTypeStr)
        else {
            return nil
        }

        return eventType.classType.init(entry)
    }
}
