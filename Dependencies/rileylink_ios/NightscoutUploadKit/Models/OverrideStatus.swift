//
//  OverrideStatus.swift
//  NightscoutUploadKit
//
//  Created by Kenneth Stack on 5/6/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation
import HealthKit

public struct OverrideStatus {
    let name: String?
    let timestamp: Date
    let active: Bool
    let currentCorrectionRange: CorrectionRange?
    let duration: TimeInterval?
    let multiplier: Double?
    
    
    public init(name: String? = nil, timestamp: Date, active: Bool, currentCorrectionRange: CorrectionRange? = nil, duration: TimeInterval? = nil, multiplier: Double? = nil) {
        self.name = name
        self.timestamp = timestamp
        self.active = active
        self.currentCorrectionRange = currentCorrectionRange
        self.duration = duration
        self.multiplier = multiplier
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        rval["timestamp"] = TimeFormat.timestampStrFromDate(timestamp)
        rval["active"] = active
        
        if let name = name {
            rval["name"] = name
        }
        
        if let currentCorrectionRange = currentCorrectionRange {
            rval["currentCorrectionRange"] = currentCorrectionRange.dictionaryRepresentation
        }
        
        if let duration = duration {
            rval["duration"] = duration
        }
        
        if let multiplier = multiplier {
            rval["multiplier"] = multiplier
        }
        
        return rval
    }
    
 
    
}
