//
//  SensorTimestampGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/16/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

public enum SensorTimestampType: String {
    case lastRf
    case pageEnd
    case gap
    case unknown
    
    init(code: UInt8) {
        switch code {
        case 0x00:
            self = .lastRf
        case 0x01:
            self = .pageEnd
        case 0x02:
            self = .gap
        default:
            self = .unknown
        }
    }
    
}

public struct SensorTimestampGlucoseEvent: GlucoseEvent {
    public let length: Int
    public let rawData: Data
    public let timestamp: DateComponents
    public let timestampType: SensorTimestampType
    
    public init?(availableData: Data, relativeTimestamp: DateComponents) {
        length = 5
        
        guard length <= availableData.count else {
            return nil
        }
        
        rawData = availableData.subdata(in: 0..<length)
        timestamp = DateComponents(glucoseEventBytes: availableData.subdata(in: 1..<5))
        timestampType = SensorTimestampType(code: availableData[3] >> 5 & 0b00000011)
    }
    
    public func isForwardOffsetReference() -> Bool {
        return timestampType == .lastRf || timestampType == .pageEnd
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            "name": "SensorTimestamp",
            "timestampType": timestampType
        ]
    }
}
