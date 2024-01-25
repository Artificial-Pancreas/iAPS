//
//  DoseEntry.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 21/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import LoopKit

extension DoseEntry {
    public static func bolus(units: Double, deliveredUnits: Double, duration: TimeInterval, activationType: BolusActivationType, insulinType: InsulinType) -> DoseEntry {
        var endTime = Date.now
        endTime.addTimeInterval(duration)
        
        return DoseEntry(
            type: .bolus,
            startDate: Date.now,
            endDate: endTime,
            value: units,
            unit: .units,
            deliveredUnits: deliveredUnits,
            insulinType: insulinType,
            automatic: activationType.isAutomatic,
            manuallyEntered: activationType == .manualNoRecommendation,
            isMutable: true
        )
    }
    
    public static func tempBasal(absoluteUnit: Double, insulinType: InsulinType) -> DoseEntry {
        return DoseEntry(
            type: .tempBasal,
            startDate: Date.now,
            value: absoluteUnit,
            unit: .unitsPerHour,
            insulinType: insulinType
        )
    }
    
    public static func basal(rate: Double, insulinType: InsulinType) -> DoseEntry {
        return DoseEntry(
            type: .basal,
            startDate: Date.now,
            value: rate,
            unit: .unitsPerHour,
            insulinType: insulinType
        )
    }
    
    public static func resume(insulinType: InsulinType) -> DoseEntry {
        return DoseEntry(
            resumeDate: Date.now,
            insulinType: insulinType
        )
    }
    
    public static func suspend() -> DoseEntry {
        return DoseEntry(suspendDate: Date.now)
    }
}
