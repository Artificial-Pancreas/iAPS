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
    public static func bolus(dose: DoseEntry, units: Double) -> NewPumpEvent {
        return NewPumpEvent(
            date: Date.now,
            dose: dose,
            raw: "\(DoseType.bolus.rawValue) \(units) \(formatter.string(from: Date.now))".data(using: .utf8) ?? Data([]),
            title: "Bolus: \(units)"
        )
    }
    
    public static func tempBasal(dose: DoseEntry, units: Double, duration: TimeInterval) -> NewPumpEvent {
        return NewPumpEvent(
            date: Date.now,
            dose: dose,
            raw: "\(DoseType.tempBasal.rawValue) \(units) \(duration) \(formatter.string(from: Date.now))".data(using: .utf8) ?? Data([]),
            title: "Temp basal: \(units) for \(duration)"
        )
    }
    
    public static func basal(dose: DoseEntry) -> NewPumpEvent {
        return NewPumpEvent(
            date: Date.now,
            dose: dose,
            raw: "\(DoseType.basal.rawValue) \(formatter.string(from: Date.now))".data(using: .utf8) ?? Data([]),
            title: "Basal"
        )
    }
    
    public static func resume(dose: DoseEntry) -> NewPumpEvent {
        return NewPumpEvent(
            date: Date.now,
            dose: dose,
            raw: "\(DoseType.resume.rawValue) \(formatter.string(from: Date.now))".data(using: .utf8) ?? Data([]),
            title: "Resume"
        )
    }
    
    public static func suspend(dose: DoseEntry) -> NewPumpEvent {
        return NewPumpEvent(
            date: Date.now,
            dose: dose,
            raw: "\(DoseType.suspend.rawValue) \(formatter.string(from: Date.now))".data(using: .utf8) ?? Data([]),
            title: "Suspend"
        )
    }
}
