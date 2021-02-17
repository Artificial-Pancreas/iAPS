//
//  UnfinalizedDose.swift
//  OmniKit
//
//  Created by Pete Schwamb on 9/5/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit

public struct UnfinalizedDose: RawRepresentable, Equatable, CustomStringConvertible {
    public typealias RawValue = [String: Any]

    enum DoseType: Int {
        case bolus = 0
        case tempBasal
        case suspend
        case resume
    }
    
    enum ScheduledCertainty: Int {
        case certain = 0
        case uncertain
        
        public var localizedDescription: String {
            switch self {
            case .certain:
                return LocalizedString("Certain", comment: "String describing a dose that was certainly scheduled")
            case .uncertain:
                return LocalizedString("Uncertain", comment: "String describing a dose that was possibly scheduled")
            }
        }
    }
    
    private let insulinFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }()
    
    private let shortDateFormatter: DateFormatter = {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .short
        timeFormatter.timeStyle = .medium
        return timeFormatter
    }()
    
    private let dateFormatter = ISO8601DateFormatter()
    
    fileprivate var uniqueKey: Data {
        return "\(doseType) \(scheduledUnits ?? units) \(dateFormatter.string(from: startTime))".data(using: .utf8)!
    }
    
    let doseType: DoseType
    public var units: Double
    var scheduledUnits: Double?     // Tracks the scheduled units, as boluses may be canceled before finishing, at which point units would reflect actual delivered volume.
    var scheduledTempRate: Double?  // Tracks the original temp rate, as during finalization the units are discretized to pump pulses, changing the actual rate
    let startTime: Date
    var duration: TimeInterval?
    var scheduledCertainty: ScheduledCertainty
    var insulinType: InsulinType?
    var automatic: Bool?
    
    var finishTime: Date? {
        get {
            return duration != nil ? startTime.addingTimeInterval(duration!) : nil
        }
        set {
            duration = newValue?.timeIntervalSince(startTime)
        }
    }
    
    private var nominalProgress: Double {
        guard let duration = duration else {
            return 0
        }
        let elapsed = -startTime.timeIntervalSinceNow
        return elapsed / duration
    }

    // A value from 0 to 1 giving the nominal progress percentage for a bolus or a temp basal
    public var progress: Double {
        return min(nominalProgress, 1)
    }
    
    // Is a bolus or a temp basal nominally finished
    public var isFinished: Bool {
        return progress >= 1
    }

    // Has a bolus operation had enough time to positively finish
    public var isBolusPositivelyFinished: Bool {
        // Pod faults if any pulse takes 20% or more of nominal to deliver
        return nominalProgress >= 1.2
    }
    
    // Units per hour
    public var rate: Double {
        guard let duration = duration else {
            return 0
        }
        return units / duration.hours
    }

    public var finalizedUnits: Double? {
        guard isFinished else {
            return nil
        }
        return units
    }

    init(bolusAmount: Double, startTime: Date, scheduledCertainty: ScheduledCertainty, insulinType: InsulinType, automatic: Bool?) {
        self.doseType = .bolus
        self.units = bolusAmount
        self.startTime = startTime
        self.duration = TimeInterval(bolusAmount / Pod.bolusDeliveryRate)
        self.scheduledCertainty = scheduledCertainty
        self.scheduledUnits = nil
        self.insulinType = insulinType
        self.automatic = automatic
    }
    
    init(tempBasalRate: Double, startTime: Date, duration: TimeInterval, scheduledCertainty: ScheduledCertainty, insulinType: InsulinType) {
        self.doseType = .tempBasal
        self.units = tempBasalRate * duration.hours
        self.startTime = startTime
        self.duration = duration
        self.scheduledCertainty = scheduledCertainty
        self.scheduledUnits = nil
        self.insulinType = insulinType
        self.automatic = nil
    }

    init(suspendStartTime: Date, scheduledCertainty: ScheduledCertainty) {
        self.doseType = .suspend
        self.units = 0
        self.startTime = suspendStartTime
        self.scheduledCertainty = scheduledCertainty
        self.automatic = nil
    }

    init(resumeStartTime: Date, scheduledCertainty: ScheduledCertainty, insulinType: InsulinType) {
        self.doseType = .resume
        self.units = 0
        self.startTime = resumeStartTime
        self.scheduledCertainty = scheduledCertainty
        self.insulinType = insulinType
        self.automatic = nil
    }

    public mutating func cancel(at date: Date, withRemaining remaining: Double? = nil) {
        guard let finishTime = finishTime, date < finishTime else {
            return
        }

        scheduledUnits = units
        let newDuration = date.timeIntervalSince(startTime)

        switch doseType {
        case .bolus:
            let oldRate = rate
            if let remaining = remaining {
                units = units - remaining
            } else {
                units = oldRate * newDuration.hours
            }
        case .tempBasal:
            scheduledTempRate = rate
            units = floor(rate * newDuration.hours * Pod.pulsesPerUnit) / Pod.pulsesPerUnit
            print("Temp basal scheduled units: \(String(describing: scheduledUnits)), delivered units: \(units), duration: \(newDuration.minutes)")
        default:
            break
        }
        duration = newDuration
    }

    public var isMutable: Bool {
        switch doseType {
        case .bolus, .tempBasal:
            return !isFinished
        default:
            return false
        }
    }

    public var description: String {
        let unitsStr = insulinFormatter.string(from: units) ?? ""
        let startTimeStr = shortDateFormatter.string(from: startTime)
        let durationStr = duration?.format(using: [.minute, .second]) ?? ""
        switch doseType {
        case .bolus:
            if let scheduledUnits = scheduledUnits {
                let scheduledUnitsStr = insulinFormatter.string(from: scheduledUnits) ?? "?"
                return String(format: LocalizedString("InterruptedBolus: %1$@ U (%2$@ U scheduled) %3$@ %4$@ %5$@", comment: "The format string describing a bolus that was interrupted. (1: The amount delivered)(2: The amount scheduled)(3: Start time of the dose)(4: duration)(5: scheduled certainty)"), unitsStr, scheduledUnitsStr, startTimeStr, durationStr, scheduledCertainty.localizedDescription)
            } else {
                return String(format: LocalizedString("Bolus: %1$@U %2$@ %3$@ %4$@", comment: "The format string describing a bolus. (1: The amount delivered)(2: Start time of the dose)(3: duration)(4: scheduled certainty)"), unitsStr, startTimeStr, durationStr, scheduledCertainty.localizedDescription)
            }
        case .tempBasal:
            let volumeStr = insulinFormatter.string(from: units) ?? "?"
            let rateStr = NumberFormatter.localizedString(from: NSNumber(value: scheduledTempRate ?? rate), number: .decimal)
            return String(format: LocalizedString("TempBasal: %1$@ U/hour %2$@ %3$@ %4$@ U %5$@", comment: "The format string describing a temp basal. (1: The rate)(2: Start time)(3: duration)(4: volume)(5: scheduled certainty"), rateStr, startTimeStr, durationStr, volumeStr, scheduledCertainty.localizedDescription)
        case .suspend:
            return String(format: LocalizedString("Suspend: %1$@ %2$@", comment: "The format string describing a suspend. (1: Time)(2: Scheduled certainty"), startTimeStr, scheduledCertainty.localizedDescription)
        case .resume:
            return String(format: LocalizedString("Resume: %1$@ %2$@", comment: "The format string describing a resume. (1: Time)(2: Scheduled certainty"), startTimeStr, scheduledCertainty.localizedDescription)
        }
    }
    
    // RawRepresentable
    public init?(rawValue: RawValue) {
        guard
            let rawDoseType = rawValue["doseType"] as? Int,
            let doseType = DoseType(rawValue: rawDoseType),
            let units = rawValue["units"] as? Double,
            let startTime = rawValue["startTime"] as? Date,
            let rawScheduledCertainty = rawValue["scheduledCertainty"] as? Int,
            let scheduledCertainty = ScheduledCertainty(rawValue: rawScheduledCertainty)
            else {
                return nil
        }
        
        self.doseType = doseType
        self.units = units
        self.startTime = startTime
        self.scheduledCertainty = scheduledCertainty
        
        if let scheduledUnits = rawValue["scheduledUnits"] as? Double {
            self.scheduledUnits = scheduledUnits
        }

        if let scheduledTempRate = rawValue["scheduledTempRate"] as? Double {
            self.scheduledTempRate = scheduledTempRate
        }

        if let duration = rawValue["duration"] as? Double {
            self.duration = duration
        }
        
        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue {
            self.insulinType = InsulinType(rawValue: rawInsulinType)
        }
    }
    
    public var rawValue: RawValue {
        var rawValue: RawValue = [
            "doseType": doseType.rawValue,
            "units": units,
            "startTime": startTime,
            "scheduledCertainty": scheduledCertainty.rawValue
        ]
        
        if let scheduledUnits = scheduledUnits {
           rawValue["scheduledUnits"] = scheduledUnits
        }

        if let scheduledTempRate = scheduledTempRate {
            rawValue["scheduledTempRate"] = scheduledTempRate
        }

        if let duration = duration {
            rawValue["duration"] = duration
        }
        
        if let insulinType = insulinType {
            rawValue["insulinType"] = insulinType.rawValue
        }
        
        return rawValue
    }
}

private extension TimeInterval {
    func format(using units: NSCalendar.Unit) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropLeading
        formatter.maximumUnitCount = 2
        
        return formatter.string(from: self)
    }
}

extension NewPumpEvent {
    init(_ dose: UnfinalizedDose) {
        let title = String(describing: dose)
        let entry = DoseEntry(dose)
        self.init(date: dose.startTime, dose: entry, isMutable: dose.isMutable, raw: dose.uniqueKey, title: title)
    }
}

extension DoseEntry {
    init (_ dose: UnfinalizedDose) {
        switch dose.doseType {
        case .bolus:
            self = DoseEntry(type: .bolus, startDate: dose.startTime, endDate: dose.finishTime, value: dose.scheduledUnits ?? dose.units, unit: .units, deliveredUnits: dose.finalizedUnits, insulinType: dose.insulinType, automatic: dose.automatic)
        case .tempBasal:
            self = DoseEntry(type: .tempBasal, startDate: dose.startTime, endDate: dose.finishTime, value: dose.scheduledTempRate ?? dose.rate, unit: .unitsPerHour, deliveredUnits: dose.finalizedUnits, insulinType: dose.insulinType)
        case .suspend:
            self = DoseEntry(suspendDate: dose.startTime)
        case .resume:
            self = DoseEntry(resumeDate: dose.startTime, insulinType: dose.insulinType)
        }
    }
}
