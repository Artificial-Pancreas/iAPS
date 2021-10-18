//
//  RileyLinkStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 8/12/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct RileyLinkStatus {

    public enum State: String {
        case Connected = "connected"
        case Connecting = "connecting"
        case Disconnected = "disconnected"
    }

    let name: String
    let state: State
    let lastIdle: Date?
    let version: String?
    let rssi: Double?

    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()

        rval["name"] = name
        rval["state"] = state.rawValue

        if let lastIdle = lastIdle {
            rval["lastIdle"] = TimeFormat.timestampStrFromDate(lastIdle)
        }

        if let version = version {
            rval["version"] = version
        }

        if let rssi = rssi {
            rval["rssi"] = rssi
        }

        return rval
    }
}
