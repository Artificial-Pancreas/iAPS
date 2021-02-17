//
//  UploaderStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/26/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct UploaderStatus {

    public let battery: Int?
    public let name: String
    public let timestamp: Date

    public init(name: String, timestamp: Date, battery: Float? = nil) {
        let intBattery: Int?
        if let battery = battery , battery >= 0 {
            intBattery = Int(battery * 100)
        } else {
            intBattery = nil
        }

        self.init(name: name, timestamp: timestamp, battery: intBattery)
    }

    public init(name: String, timestamp: Date, battery: Int? = nil) {
        self.name = name
        self.timestamp = timestamp
        self.battery = battery
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        rval["name"] = name
        rval["timestamp"] = TimeFormat.timestampStrFromDate(timestamp)
        
        if let battery = battery {
            rval["battery"] = battery
        }

        return rval
    }
}
