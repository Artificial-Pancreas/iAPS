//
//  IOBStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/28/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct IOBStatus {
    typealias RawValue = [String: Any]

    public let timestamp: Date
    public let iob: Double? // basal iob + bolus iob: can be negative
    let basalIOB: Double? // does not include bolus iob

    public init(timestamp: Date, iob: Double? = nil, basalIOB: Double? = nil) {
        self.timestamp = timestamp
        self.iob = iob
        self.basalIOB = basalIOB
    }
    
    public var dictionaryRepresentation: [String: Any] {

        var rval = [String: Any]()

        rval["timestamp"] = TimeFormat.timestampStrFromDate(timestamp)

        if let iob = iob {
            rval["iob"] = iob
        }

        if let basalIOB = basalIOB {
            rval["basaliob"] = basalIOB
        }

        return rval
    }

    init?(rawValue: RawValue) {
        guard
            let timestampStr = rawValue["timestamp"] as? String,
            let timestamp = TimeFormat.dateFromTimestamp(timestampStr)
        else {
            return nil
        }

        self.timestamp = timestamp

        iob = rawValue["iob"] as? Double
        basalIOB = rawValue["basaliob"] as? Double
    }
}
