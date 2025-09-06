//
//  NewPumpEvent.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 21/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import LoopKit

extension NewPumpEvent {
    public static func bolus(dose: DoseEntry, units: Double, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.bolus.rawValue) \(units) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: LocalizedString("Bolus", comment: "Pump Event title for UnfinalizedDose with doseType of .bolus")
        )
    }
    
    public static func tempBasal(dose: DoseEntry, units: Double, duration: TimeInterval, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.tempBasal.rawValue) \(units) \(duration) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: LocalizedString("Temp Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .tempBasal")
        )
    }
    
    public static func basal(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.basal.rawValue) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: LocalizedString("Basal", comment: "Pump Event title for UnfinalizedDose with doseType of .basal")
        )
    }
    
    public static func resume(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.resume.rawValue) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: LocalizedString("Resume", comment: "Pump Event title for UnfinalizedDose with doseType of .resume")
        )
    }
    
    public static func suspend(dose: DoseEntry, date: Date = Date.now) -> NewPumpEvent {
        let dateFormatter = ISO8601DateFormatter()
        return NewPumpEvent(
            date: date,
            dose: dose,
            raw: "\(DoseType.suspend.rawValue) \(dateFormatter.string(from: date))".data(using: .utf8) ?? Data([]),
            title: LocalizedString("Suspend", comment: "Pump Event title for UnfinalizedDose with doseType of .suspend")
        )
    }
}
