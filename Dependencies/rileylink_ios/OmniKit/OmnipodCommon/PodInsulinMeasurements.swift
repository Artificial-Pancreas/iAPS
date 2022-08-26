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
    
    public init(insulinDelivered: Double, reservoirLevel: Double?, validTime: Date) {
        self.validTime = validTime
        self.delivered = insulinDelivered
        self.reservoirLevel = reservoirLevel
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

