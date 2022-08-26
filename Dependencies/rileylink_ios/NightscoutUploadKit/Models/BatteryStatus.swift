//
//  BatteryStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/28/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public enum BatteryIndicator: String {
    case low = "low"
    case normal = "normal"
}


public struct BatteryStatus {
    let percent: Int?
    let voltage: Double?
    let status: BatteryIndicator?
    
    public init(percent: Int? = nil, voltage: Double? = nil, status: BatteryIndicator? = nil) {
        self.percent = percent
        self.voltage = voltage
        self.status = status
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        if let percent = percent {
            rval["percent"] = percent
        }
        if let voltage = voltage {
            rval["voltage"] = voltage
        }

        if let status = status {
            rval["status"] = status.rawValue
        }
        
        return rval
    }
}
