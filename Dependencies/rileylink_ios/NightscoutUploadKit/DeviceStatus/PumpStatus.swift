//
//  PumpStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/26/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct PumpStatus {
    let clock: Date
    let pumpID: String
    let manufacturer: String?
    let model: String?
    let iob: IOBStatus?
    let battery: BatteryStatus?
    let suspended: Bool?
    let bolusing: Bool?
    let reservoir: Double?
    let secondsFromGMT: Int?

    public init(clock: Date, pumpID: String, manufacturer: String? = nil, model: String? = nil, iob: IOBStatus? = nil, battery: BatteryStatus? = nil, suspended: Bool? = nil, bolusing: Bool? = nil, reservoir: Double? = nil, secondsFromGMT: Int? = nil) {
        self.clock = clock
        self.pumpID = pumpID
        self.manufacturer = manufacturer
        self.model = model
        self.iob = iob
        self.battery = battery
        self.suspended = suspended
        self.bolusing = bolusing
        self.reservoir = reservoir
        self.secondsFromGMT = secondsFromGMT
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        rval["clock"] = TimeFormat.timestampStrFromDate(clock)
        rval["pumpID"] = pumpID

        if let manufacturer = manufacturer {
            rval["manufacturer"] = manufacturer
        }

        if let model = model {
            rval["model"] = model
        }

        if let iob = iob {
            rval["iob"] = iob.dictionaryRepresentation
        }

        if let battery = battery {
            rval["battery"] = battery.dictionaryRepresentation
        }
        
        if let suspended = suspended {
            rval["suspended"] = suspended
        }

        if let bolusing = bolusing {
            rval["bolusing"] = bolusing
        }

        if let reservoir = reservoir {
            rval["reservoir"] = reservoir
        }

        if let secondsFromGMT = secondsFromGMT {
            rval["secondsFromGMT"] = secondsFromGMT
        }

        return rval
    }
}
