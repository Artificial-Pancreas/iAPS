//
//  UnfinalizedDose.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 23/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import LoopKit

public class UnfinalizedDose {
    public typealias RawValue = [String: Any]
    
    public let type: DoseType
    public let startDate: Date
    public let endDate: Date
    public let unit: DoseUnit
    public let value: Double
    public var deliveredUnits: Double = 0
    public let insulinType: InsulinType?
    public let automatic: Bool?
    
    public init(units: Double, duration: TimeInterval, activationType: BolusActivationType, insulinType: InsulinType) {
        var endTime = Date.now
        endTime.addTimeInterval(duration)
        
        self.type = .bolus
        self.unit = .units
        self.value = units
        self.startDate = Date.now
        self.endDate = endTime
        self.insulinType = insulinType
        self.automatic = activationType.isAutomatic
    }
    
    public func toDoseEntry(isMutable: Bool = false) -> DoseEntry? {
        switch type {
        case .bolus:
            return DoseEntry(
                type: .bolus,
                startDate: startDate,
                endDate: endDate,
                value: value,
                unit: .units,
                deliveredUnits: isMutable ? value : deliveredUnits,
                insulinType: insulinType,
                automatic: automatic,
                isMutable: isMutable
            )
        default:
            return nil
        }
    }
}
