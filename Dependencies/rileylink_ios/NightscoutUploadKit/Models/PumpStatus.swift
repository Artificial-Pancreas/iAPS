//
//  PumpStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/26/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public enum NightscoutSeverityLevel: Int {
    case urgent = 2
    case warn = 1
    case info = 0
    case low = -1
    case lowest = -2
    case none = -3
}

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
    let reservoirDisplayOverride: String?
    let reservoirLevelOverride: NightscoutSeverityLevel?

    public init(clock: Date, pumpID: String, manufacturer: String? = nil, model: String? = nil, iob: IOBStatus? = nil, battery: BatteryStatus? = nil, suspended: Bool? = nil, bolusing: Bool? = nil, reservoir: Double? = nil, secondsFromGMT: Int? = nil, reservoirDisplayOverride: String?, reservoirLevelOverride: NightscoutSeverityLevel?) {
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
        self.reservoirDisplayOverride = reservoirDisplayOverride
        self.reservoirLevelOverride = reservoirLevelOverride
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()
        
        rval["clock"] = TimeFormat.timestampStrFromDate(clock)
        rval["pumpID"] = pumpID
        rval["manufacturer"] = manufacturer
        rval["model"] = model
        rval["iob"] = iob?.dictionaryRepresentation
        rval["battery"] = battery?.dictionaryRepresentation
        rval["suspended"] = suspended
        rval["bolusing"] = bolusing
        rval["reservoir"] = reservoir
        rval["secondsFromGMT"] = secondsFromGMT
        rval["reservoir_display_override"] = reservoirDisplayOverride
        rval["reservoir_level_override"] = reservoirLevelOverride?.rawValue

        return rval
    }
}
