//
//  RadioAdapter.swift
//  RileyLink
//
//  Created by Pete Schwamb on 2/26/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public struct RadioAdapter {
    let hardware: String
    let frequency: Double?
    let name: String?
    let lastTuned: Date?
    let firmwareVersion: String
    let RSSI: Int?
    let pumpRSSI: Int?

    public init(hardware: String, frequency: Double?, name: String, lastTuned: Date?, firmwareVersion: String, RSSI: Int?, pumpRSSI: Int?) {
        self.hardware = hardware
        self.frequency = frequency
        self.name = name
        self.lastTuned = lastTuned
        self.firmwareVersion = firmwareVersion
        self.RSSI = RSSI
        self.pumpRSSI = pumpRSSI
    }

    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()

        rval["hardware"] = hardware

        if let frequency = frequency {
            rval["frequency"] = frequency
        }

        if let name = name {
            rval["name"] = name
        }

        if let lastTuned = lastTuned {
            rval["lastTuned"] = TimeFormat.timestampStrFromDate(lastTuned)
        }

        rval["firmwareVersion"] = firmwareVersion

        if let RSSI = RSSI {
            rval["RSSI"] = RSSI
        }

        if let pumpRSSI = pumpRSSI {
            rval["pumpRSSI"] = pumpRSSI
        }

        return rval
    }
}
