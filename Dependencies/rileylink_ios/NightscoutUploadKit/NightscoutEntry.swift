//
//  NightscoutEntry.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 11/5/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public class NightscoutEntry: DictionaryRepresentable {
    
    public enum GlucoseType: String {
        case Meter
        case Sensor
    }
    
    public let timestamp: Date
    let glucose: Int
    let previousSGV: Int?
    let previousSGVNotActive: Bool?
    let direction: String?
    let device: String
    let glucoseType: GlucoseType
    
    public init(glucose: Int, timestamp: Date, device: String, glucoseType: GlucoseType,
         previousSGV: Int? = nil, previousSGVNotActive: Bool? = nil, direction: String? = nil) {
        
        self.glucose = glucose
        self.timestamp = timestamp
        self.device = device
        self.previousSGV = previousSGV
        self.previousSGVNotActive = previousSGVNotActive
        self.direction = direction
        self.glucoseType = glucoseType
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var representation: [String: Any] = [
            "device": device,
            "date": timestamp.timeIntervalSince1970 * 1000,
            "dateString": TimeFormat.timestampStrFromDate(timestamp)
        ]
        
        switch glucoseType {
        case .Meter:
            representation["type"] = "mbg"
            representation["mbg"] = glucose
        case .Sensor:
            representation["type"] = "sgv"
            representation["sgv"] = glucose
        }
        
        if let direction = direction {
            representation["direction"] = direction
        }
        
        if let previousSGV = previousSGV {
            representation["previousSGV"] = previousSGV
        }
        
        if let previousSGVNotActive = previousSGVNotActive {
            representation["previousSGVNotActive"] = previousSGVNotActive
        }
        
        return representation
    }
}
