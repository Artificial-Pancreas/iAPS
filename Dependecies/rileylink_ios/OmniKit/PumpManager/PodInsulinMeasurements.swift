//
//  PodInsulinMeasurements.swift
//  OmniKit
//
//  Created by Pete Schwamb on 9/5/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct PodInsulinMeasurements: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]
    
    public let validTime: Date
    public let delivered: Double
    public let reservoirLevel: Double?
    
    public init(insulinDelivered: Double, reservoirLevel: Double?, setupUnitsDelivered: Double?, validTime: Date) {
        self.validTime = validTime
        self.reservoirLevel = reservoirLevel
        if let setupUnitsDelivered = setupUnitsDelivered {
            self.delivered = insulinDelivered - setupUnitsDelivered
        } else {
            // subtract off the fixed setup command values as we don't have an actual value (yet)
            self.delivered = max(insulinDelivered - Pod.primeUnits - Pod.cannulaInsertionUnits, 0)
        }
    }
    
    // RawRepresentable
    public init?(rawValue: RawValue) {
        guard
            let validTime = rawValue["validTime"] as? Date,
            let delivered = rawValue["delivered"] as? Double
            else {
                return nil
        }
        self.validTime = validTime
        self.delivered = delivered
        self.reservoirLevel = rawValue["reservoirLevel"] as? Double
    }
    
    public var rawValue: RawValue {
        var rawValue: RawValue = [
            "validTime": validTime,
            "delivered": delivered
            ]
        
        if let reservoirLevel = reservoirLevel {
            rawValue["reservoirLevel"] = reservoirLevel
        }
        
        return rawValue
    }
}

