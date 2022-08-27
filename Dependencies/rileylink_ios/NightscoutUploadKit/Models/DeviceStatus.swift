//
//  DeviceStatus.swift
//  RileyLink
//
//  Created by Pete Schwamb on 7/26/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public struct DeviceStatus {
    typealias RawValue = [String: Any]

    public let device: String
    public let timestamp: Date
    public let identifier: String?
    public let pumpStatus: PumpStatus?
    public let uploaderStatus: UploaderStatus?
    public let loopStatus: LoopStatus?
    public let radioAdapter: RadioAdapter?
    public let overrideStatus: OverrideStatus?

    public init(device: String, timestamp: Date, pumpStatus: PumpStatus? = nil, uploaderStatus: UploaderStatus? = nil, loopStatus: LoopStatus? = nil, radioAdapter: RadioAdapter? = nil, overrideStatus: OverrideStatus? = nil, identifier: String? = nil) {
        self.device = device
        self.timestamp = timestamp
        self.pumpStatus = pumpStatus
        self.uploaderStatus = uploaderStatus
        self.loopStatus = loopStatus
        self.radioAdapter = radioAdapter
        self.overrideStatus = overrideStatus
        self.identifier = identifier
    }

    public var dictionaryRepresentation: [String: Any] {
        var rval = [String: Any]()

        rval["device"] = device
        rval["created_at"] = TimeFormat.timestampStrFromDate(timestamp)

        if let pump = pumpStatus {
            rval["pump"] = pump.dictionaryRepresentation
        }

        if let uploader = uploaderStatus {
            rval["uploader"] = uploader.dictionaryRepresentation
        }

        if let loop = loopStatus {
            rval["loop"] = loop.dictionaryRepresentation
        }

        if let radioAdapter = radioAdapter {
            rval["radioAdapter"] = radioAdapter.dictionaryRepresentation
        }

        if let override = overrideStatus {
            rval["override"] = override.dictionaryRepresentation
        }

        if let identifier = identifier {
            rval["identifier"] = identifier
        }

        return rval
    }

    init?(rawValue: RawValue) {
        guard
            let identifier = rawValue["_id"] as? String,
            let timestampStr = rawValue["created_at"] as? String,
            let timestamp = TimeFormat.dateFromTimestamp(timestampStr),
            let device = rawValue["device"] as? String
        else {
            return nil
        }

        self.timestamp = timestamp
        self.device = device
        self.identifier = identifier

        if let loopStatusRaw = rawValue["loop"] as? LoopStatus.RawValue {
            loopStatus = LoopStatus(rawValue: loopStatusRaw)
        } else {
            loopStatus = nil
        }

        // TODO: OverrideStatus not being parsed yet
        self.overrideStatus = nil

        // TODO: PumpStatus not being parsed yet
        self.pumpStatus = nil

        // TODO: UploaderStatus not being parsed yet
        self.uploaderStatus = nil

        // TODO: RadioAdapter not being parsed yet
        self.radioAdapter = nil
    }
}
