//
//  UnfinalizedDose.swift
//  MinimedKit
//
//  Created by Pete Schwamb on 7/31/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
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

    let doseType: DoseType
    public var units: Double
    var programmedUnits: Double?     // Set when finalized; tracks programmed units
    var programmedTempRate: Double?  // Set when finalized; tracks programmed temp rate
    let startTime: Date
    var duration: TimeInterval
    var isReconciledWithHistory: Bool
    var uuid: UUID
    let insulinType: InsulinType?
    let automatic: Bool?

    var finishTime: Date {
        get {
            return startTime.addingTimeInterval(duration)
        }
        set {
            duration = newValue.timeIntervalSince(startTime)
        }
    }

    public var progress: Double {
        let elapsed = -startTime.timeIntervalSinceNow
        return min(elapsed / duration, 1)
    }

    public var isFinished: Bool {
        return progress >= 1
    }

    // Units per hour
    public var rate: Double {
        guard duration.hours > 0 else {
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

    init(bolusAmount: Double, startTime: Date, duration: TimeInterval, insulinType: InsulinType, automatic: Bool, isReconciledWithHistory: Bool = false) {
        self.doseType = .bolus
        self.units = bolusAmount
        self.startTime = startTime
        self.duration = duration
        self.programmedUnits = nil
        self.insulinType = insulinType
        self.uuid = UUID()
        self.isReconciledWithHistory = isReconciledWithHistory
        self.automatic = automatic
    }

    init(tempBasalRate: Double, startTime: Date, duration: TimeInterval, insulinType: InsulinType, automatic: Bool = true, isReconciledWithHistory: Bool = false) {
        self.doseType = .tempBasal
        self.units = tempBasalRate * duration.hours
        self.startTime = startTime
        self.duration = duration
        self.programmedUnits = nil
        self.insulinType = insulinType
        self.automatic = automatic
        self.isReconciledWithHistory = isReconciledWithHistory
        self.uuid = UUID()
    }

    init(suspendStartTime: Date, isReconciledWithHistory: Bool = false) {
        self.doseType = .suspend
        self.units = 0
        self.startTime = suspendStartTime
        self.duration = 0
        self.isReconciledWithHistory = isReconciledWithHistory
        self.insulinType = nil
        self.automatic = false
        self.uuid = UUID()
    }

    init(resumeStartTime: Date, insulinType: InsulinType, isReconciledWithHistory: Bool = false) {
        self.doseType = .resume
        self.units = 0
        self.startTime = resumeStartTime
        self.duration = 0
        self.insulinType = insulinType
        self.isReconciledWithHistory = isReconciledWithHistory
        self.automatic = false
        self.uuid = UUID()
    }

    public mutating func cancel(at date: Date, pumpModel: PumpModel) {
        guard date < finishTime else {
            return
        }
        
        let programmedUnits = units
        self.programmedUnits = programmedUnits
        let newDuration = date.timeIntervalSince(startTime)

        switch doseType {
        case .bolus:
            (units,_) = pumpModel.estimateBolusProgress(elapsed: newDuration, programmedUnits: programmedUnits)
        case .tempBasal:
            programmedTempRate = rate
            (units,_) = pumpModel.estimateTempBasalProgress(unitsPerHour: rate, duration: duration, elapsed: newDuration)
        default:
            break
        }
        duration = newDuration
    }

    public var description: String {
        switch doseType {
        case .bolus:
            return "Bolus units:\(programmedUnits ?? units) \(startTime)"
        case .tempBasal:
            return "TempBasal rate:\(programmedTempRate ?? rate) \(startTime) duration:\(String(describing: duration))"
        default:
            return "\(String(describing: doseType).capitalized) \(startTime)"
        }
    }
    
    public mutating func reconcile(with event: NewPumpEvent) {
        isReconciledWithHistory = true
        if let dose = event.dose {
            switch dose.type {
            case .bolus:
                if programmedUnits == nil {
                    programmedUnits = units
                }
                let doseDuration = dose.endDate.timeIntervalSince(dose.startDate)
                
                if doseDuration > 0 && doseDuration < duration {
                    duration = doseDuration
                }
                if let deliveredUnits = dose.deliveredUnits {
                    units = deliveredUnits
                }
            default:
                break
            }
        }
    }

    // MARK: - RawRepresentable
    public init?(rawValue: RawValue) {
        guard
            let rawDoseType = rawValue["doseType"] as? Int,
            let doseType = DoseType(rawValue: rawDoseType),
            let units = rawValue["units"] as? Double,
            let startTime = rawValue["startTime"] as? Date,
            let duration = rawValue["duration"] as? Double
            else {
                return nil
        }

        self.doseType = doseType
        self.units = units
        self.startTime = startTime
        self.duration = duration

        if let scheduledUnits = rawValue["scheduledUnits"] as? Double {
            self.programmedUnits = scheduledUnits
        }

        if let scheduledTempRate = rawValue["scheduledTempRate"] as? Double {
            self.programmedTempRate = scheduledTempRate
        }
        
        if let uuidString = rawValue["uuid"] as? String {
            if let uuid = UUID(uuidString: uuidString) {
                self.uuid = uuid
            } else {
                return nil
            }
        } else {
            self.uuid = UUID()
        }
        
        if let rawInsulinType = rawValue["insulinType"] as? InsulinType.RawValue, let insulinType = InsulinType(rawValue: rawInsulinType) {
            self.insulinType = insulinType
        } else {
            self.insulinType = nil
        }

        self.isReconciledWithHistory = rawValue["isReconciledWithHistory"] as? Bool ?? false
        
        let defaultAutomaticState = doseType == .tempBasal
        
        self.automatic = rawValue["automatic"] as? Bool ?? defaultAutomaticState
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [
            "doseType": doseType.rawValue,
            "units": units,
            "startTime": startTime,
            "duration": duration,
            "isReconciledWithHistory": isReconciledWithHistory,
            "uuid": uuid.uuidString,
        ]

        if let scheduledUnits = programmedUnits {
            rawValue["scheduledUnits"] = scheduledUnits
        }

        if let scheduledTempRate = programmedTempRate {
            rawValue["scheduledTempRate"] = scheduledTempRate
        }
        
        if let insulinType = insulinType {
            rawValue["insulinType"] = insulinType.rawValue
        }
        
        if let automatic = automatic {
            rawValue["automatic"] = automatic
        }

        return rawValue
    }
}

// MARK: - UnfinalizedDose

extension UnfinalizedDose {
    var newPumpEvent: NewPumpEvent {
        return NewPumpEvent(self)
    }
}

// MARK: - NewPumpEvent

extension NewPumpEvent {
    init(_ dose: UnfinalizedDose) {
        let title = String(describing: dose)
        let entry = DoseEntry(dose)
        let raw = dose.uuid.asRaw
        self.init(date: dose.startTime, dose: entry, isMutable: !dose.isFinished || !dose.isReconciledWithHistory, raw: raw, title: title)
    }
    
    func replacingAttributes(raw newRaw: Data, date newDate: Date) -> NewPumpEvent {
        let newDose = dose?.replacingAttributes(startDate: newDate)
        return NewPumpEvent(date: newDate, dose: newDose, isMutable: isMutable, raw: newRaw, title: title, type: type)
    }
}

// MARK: - DoseEntry

extension DoseEntry {
    init (_ dose: UnfinalizedDose) {
        switch dose.doseType {
        case .bolus:
            self = DoseEntry(type: .bolus, startDate: dose.startTime, endDate: dose.finishTime, value: dose.programmedUnits ?? dose.units, unit: .units, deliveredUnits: dose.finalizedUnits, insulinType: dose.insulinType, automatic: dose.automatic)
        case .tempBasal:
            self = DoseEntry(type: .tempBasal, startDate: dose.startTime, endDate: dose.finishTime, value: dose.programmedTempRate ?? dose.rate, unit: .unitsPerHour, deliveredUnits: dose.finalizedUnits, insulinType: dose.insulinType)
        case .suspend:
            self = DoseEntry(suspendDate: dose.startTime)
        case .resume:
            self = DoseEntry(resumeDate: dose.startTime, insulinType: dose.insulinType)
        }
    }
    
    func replacingAttributes(startDate newStartDate: Date) -> DoseEntry {
        let value: Double
        switch unit {
        case .units:
            value = programmedUnits
        case .unitsPerHour:
            value = unitsPerHour
        }
        let duration = endDate.timeIntervalSince(startDate)
        let newEndDate = newStartDate.addingTimeInterval(duration)
        return DoseEntry(type: type, startDate: newStartDate, endDate: newEndDate, value: value, unit: unit, deliveredUnits: deliveredUnits, description: description, syncIdentifier: syncIdentifier, insulinType: insulinType)
    }
}

extension Collection where Element == NewPumpEvent {
    /// find matching entry
    func firstMatchingIndex(for dose: UnfinalizedDose, within: TimeInterval) -> Self.Index? {
        return firstIndex(where: { (event) -> Bool in
            guard let type = event.type, let eventDose = event.dose, abs(eventDose.startDate.timeIntervalSince(dose.startTime)) < within else {
                return false
            }

            switch dose.doseType {
            case .bolus:
                return type == .bolus && eventDose.programmedUnits == dose.programmedUnits ?? dose.units
            case .tempBasal:
                return type == .tempBasal && eventDose.unitsPerHour == dose.programmedTempRate ?? dose.rate
            case .suspend:
                return type == .suspend
            case .resume:
                return type == .resume
            }
        })
    }
}

extension UUID {
    var asRaw: Data {
        return withUnsafePointer(to: self) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: self))
        }
    }
}
